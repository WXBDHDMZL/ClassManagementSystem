// 托盘 / 悬浮球的 Dart 侧行为测试（补交接说明 §10 的测试缺口）。
//
// 说明：真正的"原生消息循环"与球窗口本体（ball_window.cpp）无法在单元测试里跑，
// 这部分只能在真机上手工验证。本文件覆盖的是 Dart 侧**全部**逻辑：
// 通过 mock window_manager / tray_manager / 悬浮球三个 MethodChannel，
// 断言"该调哪个原生方法、参数是什么"，以及插件不可用时的降级行为。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/desktop_service.dart';
import 'package:class_management_system/utils/app_clock.dart';

const MethodChannel _windowChannel = MethodChannel('window_manager');
const MethodChannel _trayChannel = MethodChannel('tray_manager');
const MethodChannel _ballChannel = MethodChannel('class_management_system/ball');
const String _ballChannelName = 'class_management_system/ball';

/// 记录某个通道收到的全部方法调用。
class _Recorded {
  final List<MethodCall> calls = [];

  bool has(String method) => calls.any((c) => c.method == method);
  MethodCall? last(String method) {
    final matched = calls.where((c) => c.method == method).toList();
    return matched.isEmpty ? null : matched.last;
  }

  List<String> get methods => calls.map((c) => c.method).toList();
}

/// 取出最近一次下发的托盘菜单项文案。
List<String> _menuLabels(_Recorded tray) {
  final menu = tray.last('setContextMenu');
  expect(menu, isNotNull, reason: '应下发过托盘菜单');
  final items = ((menu!.arguments as Map)['menu'] as Map)['items'] as List;
  return items
      .map((e) => (e as Map)['label'])
      .whereType<String>()
      .toList();
}

void main() {
  final service = DesktopService.instance;
  late _Recorded window;
  late _Recorded tray;
  late _Recorded ball;
  late AppDataProvider provider;

  /// 原生 getBounds 的返回值，按需改（用于验证尺寸被夹回）。
  late Map<String, double> windowBounds;
  /// 托盘是否可用的开关（false 时模拟托盘初始化失败）。
  late bool trayWorks;

  void mock(MethodChannel channel, _Recorded rec, Object? Function(MethodCall) onCall) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      rec.calls.add(call);
      return onCall(call);
    });
  }

  Future<void> emitFromNative(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      _ballChannelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  Future<void> initService() => service.initialize(
    provider: provider,
    navigatorKey: GlobalKey<NavigatorState>(),
  );

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    service.debugReset();

    window = _Recorded();
    tray = _Recorded();
    ball = _Recorded();
    windowBounds = {'x': 100, 'y': 50, 'width': 1280, 'height': 720};
    trayWorks = true;

    mock(_windowChannel, window, (call) {
      switch (call.method) {
        case 'getBounds':
          return Map<String, double>.from(windowBounds);
        case 'isMaximized':
        case 'isMinimized':
          return false;
        default:
          return null;
      }
    });
    mock(_trayChannel, tray, (call) {
      if (!trayWorks) {
        throw PlatformException(code: 'unavailable', message: '托盘不可用');
      }
      return null;
    });
    mock(_ballChannel, ball, (call) => null);

    provider = AppDataProvider();
    // 用一份短名单，让"按名单推算的最小窗口尺寸"落在下限 1080×680，
    // 这样本文件的窗口尺寸断言可以用固定数字（推算逻辑另在 window_min_size_test 覆盖）。
    provider.replaceStudents(['张三', '李四']);
  });

  tearDown(() {
    service.debugReset();
    for (final channel in [_windowChannel, _trayChannel, _ballChannel]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  // ---------------- 初始化与降级 ----------------

  test('初始化：注册托盘、下发最小尺寸与 PreventClose，托盘就绪', () async {
    await initService();

    expect(service.initialized, isTrue);
    expect(service.trayReady, isTrue);
    expect(service.ballActive, isFalse);

    final minSize = window.last('setMinimumSize');
    expect(minSize, isNotNull);
    expect(
      minSize!.arguments['width'],
      service.minimumWindowSize.width,
    );
    expect(
      minSize.arguments['height'],
      service.minimumWindowSize.height,
    );

    expect(
      (window.last('setPreventClose')!.arguments as Map)['isPreventClose'],
      true,
    );
    expect(tray.has('setIcon'), isTrue);
    expect(tray.has('setToolTip'), isTrue);
    // 托盘菜单四项（显示主窗口 / 悬浮球模式 / 分隔线 / 退出程序）
    expect(_menuLabels(tray).length, 4);
  });

  test('初始化：托盘不可用时向上抛出，但关闭拦截仍已建立', () async {
    trayWorks = false;

    await expectLater(initService(), throwsA(isA<PlatformException>()));

    expect(service.trayReady, isFalse);
    // 旧期望：expect(window.has('setPreventClose'), isFalse,
    //   reason: '托盘失败后不应接管关闭');
    // 新期望：托盘失败时关闭拦截必须已经建立。原因（审计 A-09）：旧实现把
    // setPreventClose 排在托盘初始化之后，托盘任一环节失败就退回"点 ✗ 走原生
    // 销毁"，跳过 flushPendingSaves 与退出备份；现在先立拦截，托盘失败只影响
    // 托盘图标与菜单。
    expect(
      (window.last('setPreventClose')!.arguments as Map)['isPreventClose'],
      true,
      reason: '托盘失败也应保留关闭拦截，避免关闭时丢失未落盘数据',
    );
  });

  // ---------------- 悬浮球 ----------------

  test('进入球模式：按记忆坐标显示球、隐藏主窗口、菜单文案切换', () async {
    provider.setBallPosition(1200, 640);
    await initService();
    tray.calls.clear();

    await service.enterBallMode();

    expect(service.ballActive, isTrue);
    final show = ball.last('showBall');
    expect(show, isNotNull);
    expect((show!.arguments as Map)['x'], 1200);
    expect((show.arguments as Map)['y'], 640);
    expect(window.has('hide'), isTrue, reason: '球显示后主窗口应隐藏');
    expect(_menuLabels(tray), contains('退出悬浮球'));
  });

  test('进入球模式：球显示失败时保持主窗口可见（不让用户失去界面）', () async {
    // 球通道直接报错：模拟原生层不可用。
    mock(_ballChannel, ball, (call) {
      throw PlatformException(code: 'no_native', message: '原生球不可用');
    });
    await initService();

    await service.enterBallMode();

    expect(service.ballActive, isFalse);
    // 新流程是"先藏主窗口、再显示球"（否则采集玻璃背景时会把主窗口画面拍进去），
    // 所以球失败时必须把主窗口恢复回来——同样保证用户不会失去界面。
    expect(window.has('hide'), isTrue, reason: '先藏主窗口');
    expect(window.has('show'), isTrue, reason: '球显示失败后要把主窗口恢复回来');
  });

  test('退出球模式：隐藏球并恢复主窗口', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();
    tray.calls.clear();

    await service.exitBallMode();

    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
    expect(ball.has('showMainWindow'), isTrue);
    expect(window.has('show'), isFalse,
        reason: '恢复主窗口交给原生 cloak 路径，避免白闪');
    expect(window.has('focus'), isTrue);
    expect(_menuLabels(tray), contains('悬浮球模式'));
  });

  test('退出球模式：本身不在球模式时是空操作', () async {
    await initService();
    window.calls.clear();
    ball.calls.clear();

    await service.exitBallMode();

    expect(window.has('show'), isFalse);
    expect(ball.has('hideBall'), isFalse);
  });

  test('显示主窗口：非球模式走原生无闪恢复，不再直接 show', () async {
    await initService();
    window.calls.clear();
    ball.calls.clear();

    await service.showMainWindow();

    expect(ball.has('showMainWindow'), isTrue);
    expect(window.has('show'), isFalse,
        reason: '原生恢复路径会先 cloak，等下一帧再显示');
    expect(window.has('focus'), isTrue);
  });

  test('显示主窗口：球模式下先退球，再显示窗口', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();

    await service.showMainWindow();

    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
    expect(ball.has('showMainWindow'), isTrue);
  });

  test('最小化到托盘：只隐藏窗口，不退出进程', () async {
    await initService();
    window.calls.clear();

    await service.hideToTray();

    expect(window.has('hide'), isTrue);
    expect(window.has('close'), isFalse);
    expect(window.has('destroy'), isFalse);
  });

  test('窗口最小化：保持任务栏行为，不自动进入悬浮球', () async {
    await initService();
    ball.calls.clear();
    window.calls.clear();

    service.onWindowMinimize();
    await pumpEventQueue();

    expect(service.ballActive, isFalse);
    expect(ball.has('showBall'), isFalse);
    expect(window.has('hide'), isFalse);
  });

  test('窗口最小化：已经在球模式时不重复显示', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();

    service.onWindowMinimize();
    await pumpEventQueue();

    expect(service.ballActive, isTrue);
    expect(ball.has('showBall'), isFalse);
  });

  test('原生事件：单击球 → 恢复主窗口（退出球模式）', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();

    await emitFromNative('onBallClicked');

    expect(service.ballActive, isFalse);
    expect(ball.has('showMainWindow'), isTrue);
  });

  test('原生事件：拖动球 → 把坐标记进设置（位置记忆）', () async {
    await initService();

    await emitFromNative('onBallMoved', {'x': 42, 'y': 99});

    expect(provider.appData.settings.ballX, 42);
    expect(provider.appData.settings.ballY, 99);
  });

  test('原生事件：拖动坐标非法时忽略，不写入非法值', () async {
    await initService();

    await emitFromNative('onBallMoved', {'x': 'abc', 'y': null});

    expect(provider.appData.settings.ballX, -1);
    expect(provider.appData.settings.ballY, -1);
  });

  test('右键菜单状态：进入球模式会下发不透明度与托盘可用', () async {
    await initService();
    await service.enterBallMode();

    final state = ball.last('setBallMenuState');
    expect(state, isNotNull);
    final arguments = state!.arguments as Map;
    expect(arguments['opacity'], closeTo(0.88, 0.001));
    expect(arguments['trayReady'], isTrue);
    expect(arguments['todayPraise'], 0);
    expect(arguments['todayCriticize'], 0);
    expect(arguments['positionLocked'], isFalse);
    expect(arguments['praiseEnabled'], isTrue);
    expect(arguments['criticismEnabled'], isTrue);
  });

  test('右键菜单状态：跨零点今日计数按归属日', () async {
    AppClock.freezeForTest(DateTime(2026, 11, 22, 0, 30));
    addTearDown(AppClock.resetForTest);
    provider.addRecord('张三', '表扬', const ['课堂表现'], 'sleep', '');
    expect(provider.todayAttributionDate, '2026-11-21');

    await initService();
    await service.applyBallMenuState();

    final state = ball.last('setBallMenuState');
    expect(state, isNotNull);
    final arguments = state!.arguments as Map;
    expect(arguments['todayPraise'], 1);
    expect(arguments['todayCriticize'], 0);
  });

  test('右键菜单状态：停用的记录类型会同步为不可用', () async {
    await initService();
    provider.setRecordTypesEnabled(praise: false, criticism: true);
    await service.applyBallMenuState();

    final state = ball.last('setBallMenuState');
    expect(state, isNotNull);
    final arguments = state!.arguments as Map;
    expect(arguments['praiseEnabled'], isFalse);
    expect(arguments['criticismEnabled'], isTrue);
  });

  test('右键菜单：锁定位置会写入设置并同步勾选状态', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();

    await emitFromNative('onBallMenuCommand', {
      'action': 'togglePositionLock',
    });
    expect(provider.appData.settings.ballPositionLocked, isTrue);
    final state = ball.last('setBallMenuState');
    expect(state, isNotNull);
    expect((state!.arguments as Map)['positionLocked'], isTrue);
  });

  test('右键菜单：选择不透明度会写入设置并同步外观', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();

    await emitFromNative('onBallMenuCommand', {
      'action': 'setOpacity',
      'value': 0.5,
    });

    expect(provider.appData.settings.ballOpacity, 0.5);
    final style = ball.last('setBallStyle');
    expect(style, isNotNull);
    expect((style!.arguments as Map)['opacity'], closeTo(0.5, 0.001));
  });

  test('右键菜单：打开主窗口会退出球模式', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();

    await emitFromNative('onBallMenuCommand', {'action': 'open'});

    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
    expect(ball.has('showMainWindow'), isTrue);
  });

  test('右键菜单：收起到托盘只隐藏球，不显示主窗口', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();

    await emitFromNative('onBallMenuCommand', {'action': 'hideToTray'});

    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
    expect(window.has('show'), isFalse);
  });

  test('右键菜单：收起到托盘失败时保持球模式，可重试且不误显示主窗口', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();
    tray.calls.clear();

    mock(_ballChannel, ball, (call) {
      if (call.method == 'hideBall') {
        throw PlatformException(code: 'hide_failed', message: '原生隐藏失败');
      }
      return null;
    });
    await emitFromNative('onBallMenuCommand', {'action': 'hideToTray'});

    expect(service.ballActive, isTrue, reason: '隐藏失败不能让状态误判为已收起');
    expect(ball.has('hideBall'), isTrue);
    expect(window.has('show'), isFalse, reason: '不能把主窗口意外显示出来');
    expect(_menuLabels(tray), contains('退出悬浮球'));

    // 原生恢复后重试应能正常收起。
    mock(_ballChannel, ball, (call) => null);
    await service.hideBallToTray();
    expect(service.ballActive, isFalse);
    expect(_menuLabels(tray), contains('悬浮球模式'));
  });

  test('右键菜单：表扬/批评批量入口先退出球模式并交给界面回调', () async {
    final received = <BallMenuAction>[];
    service.onBallMenuAction = (action) async {
      received.add(action);
    };
    await initService();
    await service.enterBallMode();
    ball.calls.clear();
    window.calls.clear();

    await emitFromNative('onBallMenuCommand', {'action': 'quickPraise'});
    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
    expect(ball.has('showMainWindow'), isTrue);

    await service.enterBallMode();
    await emitFromNative('onBallMenuCommand', {'action': 'quickCriticize'});

    expect(received, [
      BallMenuAction.quickPraise,
      BallMenuAction.quickCriticize,
    ]);
  });

  test('原生事件：主窗口被原生显示时自动收起球（避免球与窗口同时存在）', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();

    service.onWindowEvent('show');
    await Future<void>.delayed(Duration.zero);

    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
  });

  // ---------------- 托盘菜单 ----------------

  test('托盘菜单：球模式下点"悬浮球"项是退出球模式', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();

    service.onTrayMenuItemClick(MenuItem(key: 'ball', label: '退出悬浮球'));
    await Future<void>.delayed(Duration.zero);

    expect(service.ballActive, isFalse);
    expect(ball.has('hideBall'), isTrue);
  });

  test('托盘菜单：非球模式下点"悬浮球"项是进入球模式', () async {
    await initService();
    ball.calls.clear();

    service.onTrayMenuItemClick(MenuItem(key: 'ball', label: '悬浮球模式'));
    // 新流程是"先藏窗口 → 再显示球"，中间多了一次 await，需要把事件队列排空。
    await pumpEventQueue();

    expect(service.ballActive, isTrue);
    expect(ball.has('showBall'), isTrue);
  });

  // ---------------- 窗口尺寸 ----------------

  test('窗口尺寸校正：比最小尺寸小时下发夹取后的尺寸', () async {
    await initService();
    windowBounds = {'x': 0, 'y': 0, 'width': 700, 'height': 500};
    window.calls.clear();

    service.onWindowResized();
    await Future<void>.delayed(Duration.zero);

    final setBounds = window.last('setBounds');
    expect(setBounds, isNotNull);
    expect(setBounds!.arguments['width'], 1080);
    expect(setBounds.arguments['height'], 680);
  });

  test('窗口尺寸校正：已不小于最小尺寸时不下发多余调用', () async {
    await initService();
    window.calls.clear();

    service.onWindowResized();
    await Future<void>.delayed(Duration.zero);

    expect(window.has('setBounds'), isFalse);
  });

  // ---------------- 启动窗口状态 ----------------

  test('启动状态-记住上次：过小的记忆尺寸会被夹到最小尺寸', () async {
    await initService();
    window.calls.clear();

    await service.applyStartupWindowMode(
      AppSettings(
        themeMode: ThemeModeType.system,
        startupWindowMode: StartupWindowMode.remember,
        windowX: 200,
        windowY: 120,
        windowWidth: 600,
        windowHeight: 400,
      ),
    );

    final call = window.last('setBounds');
    expect(call, isNotNull);
    expect(call!.arguments['x'], 200);
    expect(call.arguments['y'], 120);
    expect(call.arguments['width'], 1080);
    expect(call.arguments['height'], 680);
  });

  test('启动状态-记住上次：上次是最大化则直接最大化', () async {
    await initService();
    window.calls.clear();

    await service.applyStartupWindowMode(
      AppSettings(
        themeMode: ThemeModeType.system,
        startupWindowMode: StartupWindowMode.remember,
        windowMaximized: true,
        windowWidth: 1280,
        windowHeight: 720,
      ),
    );

    expect(window.has('maximize'), isTrue);
    expect(window.has('setBounds'), isFalse);
  });

  test('启动状态-启动即最大化', () async {
    await initService();
    window.calls.clear();

    await service.applyStartupWindowMode(
      AppSettings(
        themeMode: ThemeModeType.system,
        startupWindowMode: StartupWindowMode.maximized,
      ),
    );

    expect(window.has('maximize'), isTrue);
  });

  test('启动状态-默认大小：默认窗口大小取"按名单推算的最小尺寸"', () async {
    await initService();
    window.calls.clear();

    await service.applyStartupWindowMode(
      AppSettings(
        themeMode: ThemeModeType.system,
        startupWindowMode: StartupWindowMode.defaultSize,
        windowWidth: 900,
        windowHeight: 600,
      ),
    );

    // window_manager 的 setSize 内部走 setBounds。
    final setSize = window.last('setBounds');
    expect(setSize, isNotNull, reason: '默认大小应设为推算出的最小尺寸');
    expect(setSize!.arguments['width'], service.minimumWindowSize.width);
    expect(setSize.arguments['height'], service.minimumWindowSize.height);
    expect(window.has('maximize'), isFalse);
  });

  test('启动状态-首次启动：没有记忆尺寸时用"按名单推算的最小尺寸"', () async {
    await initService();
    window.calls.clear();

    await service.applyStartupWindowMode(
      AppSettings(
        themeMode: ThemeModeType.system,
        startupWindowMode: StartupWindowMode.remember,
        windowWidth: -1,
        windowHeight: -1,
      ),
    );

    // window_manager 的 setSize 内部走 setBounds。
    final setSize = window.last('setBounds');
    expect(setSize, isNotNull);
    expect(setSize!.arguments['width'], service.minimumWindowSize.width);
    expect(setSize.arguments['height'], service.minimumWindowSize.height);
  });

  // ---------------- 窗口状态记忆 ----------------

  test('记录窗口状态：记住模式下落盘，且尺寸被夹到最小尺寸', () async {
    provider.setStartupWindowMode(StartupWindowMode.remember);
    await initService();
    windowBounds = {'x': 300, 'y': 200, 'width': 700, 'height': 400};

    await service.rememberWindowBounds();

    final settings = provider.appData.settings;
    expect(settings.windowX, 300);
    expect(settings.windowY, 200);
    expect(settings.windowWidth, 1080);
    expect(settings.windowHeight, 680);
  });

  test('记录窗口状态：非记住模式不写任何位置', () async {
    provider.setStartupWindowMode(StartupWindowMode.defaultSize);
    await initService();
    provider.setWindowBounds(11, 22, 333, 444, maximized: false);

    await service.rememberWindowBounds();

    final settings = provider.appData.settings;
    expect(settings.windowX, 11);
    expect(settings.windowY, 22);
  });

  test('记录窗口状态：球模式下不写（窗口是隐藏的，尺寸不可信）', () async {
    provider.setStartupWindowMode(StartupWindowMode.remember);
    await initService();
    await service.enterBallMode();
    provider.setWindowBounds(11, 22, 333, 444, maximized: false);

    await service.rememberWindowBounds();

    final settings = provider.appData.settings;
    expect(settings.windowX, 11);
    expect(settings.windowY, 22);
  });

  // ---------------- 退出 ----------------

  test('退出程序：只放行关闭再 close，不再调用 destroy（审计 P2-50）', () async {
    await initService();
    final before = window.calls.length;

    await service.quitApp();

    final tail = window.calls
        .sublist(before)
        .map((c) => c.method)
        .toList();
    expect(tail, contains('setPreventClose'));
    expect(tail, contains('close'));
    // 直接 destroy（PostQuitMessage）会让进程多活约 10 秒，必须走 close；
    // close 卡住的兜底交给 10 秒看门狗，不再有 destroy/800ms 强杀。
    expect(tail, isNot(contains('destroy')));
    expect(tail.indexOf('setPreventClose'), lessThan(tail.indexOf('close')));
    expect(
      (window.calls.sublist(before).lastWhere(
        (c) => c.method == 'setPreventClose',
      ).arguments as Map)['isPreventClose'],
      false,
    );
  });

  test('退出程序：球模式下退出前先收起球（避免球残留在桌面）', () async {
    await initService();
    await service.enterBallMode();
    ball.calls.clear();

    await service.quitApp();

    expect(ball.has('hideBall'), isTrue);
    expect(service.ballActive, isFalse);
  });

  // ---------------- 深浅色同步 ----------------

  test('主题同步：深色设置只下发一次，重复调用不重复下发', () async {
    provider.setThemeMode(ThemeModeType.dark);
    await initService();
    // 初始化时就应把深色同步给原生（悬浮球与托盘菜单跟随主题）。
    expect(ball.last('setDarkMode')?.arguments, true);

    ball.calls.clear();
    await service.applyNativeTheme();
    expect(ball.has('setDarkMode'), isFalse, reason: '值未变化时不应重复下发');
  });

  test('主题同步：切到浅色会重新下发', () async {
    provider.setThemeMode(ThemeModeType.dark);
    await initService();
    ball.calls.clear();

    provider.setThemeMode(ThemeModeType.light);
    await service.applyNativeTheme();

    expect(ball.last('setDarkMode')?.arguments, false);
  });
}
