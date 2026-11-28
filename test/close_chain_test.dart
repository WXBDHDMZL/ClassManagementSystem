/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-28
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

// 审计 A-09 / A-16 的关闭链路回归：
//  - A-09：关闭拦截（setPreventClose）必须先于托盘初始化建立，托盘失败不能让
//    "点 ✗ 直接走原生销毁"回来。
//  - A-16：关闭确认框的重入守卫必须在任何 await 之前置位，连点两次 ✗ 只能弹一个框。
//
// 原生消息循环本身仍需真机验收，这里覆盖 Dart 侧的顺序与守卫语义。
// 注意：window_manager 与 tray_manager 是两个通道，"谁先调用"只能靠共享的
// 全局调用顺序表（_sequence）判断，不能用各自的 indexOf 比较。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/desktop_service.dart';
import 'package:class_management_system/services/error_log_service.dart';

import 'test_helpers.dart';
import 'package:class_management_system/widgets/close_confirm_dialog.dart';

const MethodChannel _windowChannel = MethodChannel('window_manager');
const MethodChannel _trayChannel = MethodChannel('tray_manager');
const MethodChannel _ballChannel = MethodChannel('class_management_system/ball');
const MethodChannel _sessionChannel = MethodChannel(
  'class_management_system/session',
);
const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

class _Recorded {
  final List<MethodCall> calls = [];

  MethodCall? last(String method) {
    final matched = calls.where((c) => c.method == method).toList();
    return matched.isEmpty ? null : matched.last;
  }
}

void main() {
  final service = DesktopService.instance;
  late _Recorded window;
  late _Recorded tray;
  late _Recorded ball;
  late AppDataProvider provider;
  late bool trayWorks;
  late List<String> sequence;
  late _Recorded session;
  late Directory tempRoot;

  void mock(MethodChannel channel, String label, _Recorded rec,
      Object? Function(MethodCall) onCall) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      rec.calls.add(call);
      sequence.add('$label:${call.method}');
      return onCall(call);
    });
  }

  int indexInSequence(String entry) => sequence.indexOf(entry);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    service.debugReset();

    window = _Recorded();
    tray = _Recorded();
    ball = _Recorded();
    session = _Recorded();
    trayWorks = true;
    sequence = <String>[];
    tempRoot = createStorageTestRoot('cms_close_chain');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempRoot.parent.path;
      }
      return null;
    });

    mock(_windowChannel, 'window', window, (call) {
      switch (call.method) {
        case 'getBounds':
          return <String, double>{
            'x': 100,
            'y': 50,
            'width': 1280,
            'height': 720,
          };
        case 'isMaximized':
        case 'isMinimized':
          return false;
        default:
          return null;
      }
    });
    mock(_trayChannel, 'tray', tray, (call) {
      if (!trayWorks) {
        throw PlatformException(code: 'unavailable', message: '托盘不可用');
      }
      return null;
    });
    mock(_ballChannel, 'ball', ball, (call) => null);
    mock(_sessionChannel, 'session', session, (call) => null);

    provider = AppDataProvider();
    provider.replaceStudents(['张三', '李四']);
  });

  tearDown(() async {
    service.debugReset();
    // 先排空日志队列再删临时目录，避免删除与排队写入竞态刷出
    // "操作日志写入失败：PathNotFoundException"。
    await flushErrorLogs();
    for (final channel in [
      _windowChannel,
      _trayChannel,
      _ballChannel,
      _sessionChannel,
      _pathProviderChannel,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    await deleteStorageTestRoot(tempRoot);
  });

  group('A-09 关闭拦截先于托盘建立', () {
    test('初始化时 setPreventClose 早于托盘 setIcon', () async {
      await service.initialize(
        provider: provider,
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      final preventIndex = indexInSequence('window:setPreventClose');
      final iconIndex = indexInSequence('tray:setIcon');
      expect(preventIndex, greaterThanOrEqualTo(0));
      expect(iconIndex, greaterThanOrEqualTo(0));
      expect(
        preventIndex,
        lessThan(iconIndex),
        reason: '关闭拦截必须先立起来，托盘初始化失败才不会让关闭变成原生销毁',
      );
      expect(
        (window.last('setPreventClose')!.arguments as Map)['isPreventClose'],
        true,
      );
    });

    test('托盘失败时关闭拦截仍然已建立', () async {
      trayWorks = false;

      await expectLater(
        service.initialize(
          provider: provider,
          navigatorKey: GlobalKey<NavigatorState>(),
        ),
        throwsA(isA<PlatformException>()),
      );

      expect(service.trayReady, isFalse);
      expect(
        window.last('setPreventClose'),
        isNotNull,
        reason: '托盘失败也应保留关闭拦截，否则点 ✗ 会跳过落盘与退出备份',
      );
      expect(
        (window.last('setPreventClose')!.arguments as Map)['isPreventClose'],
        true,
      );
    });
  });

  group('A-16 关闭确认不重复弹框', () {
    testWidgets('连点两次关闭只弹一个确认框', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      // 真实 async 段必须放在 runAsync 里：FakeAsync 下插件通道/延时不会推进
      //（c1 阶段同一个坑：widget 测试里 await 真实 IO 会整测试挂死）。
      await tester.runAsync(() async {
        provider.setCloseAction(CloseActionType.ask);
        await service.initialize(
          provider: provider,
          navigatorKey: navigatorKey,
        );

        // 模拟"任务栏缩略图 ✗ / 关闭按钮"连续两次触发 onWindowClose。
        service.onWindowClose();
        service.onWindowClose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byType(CloseConfirmDialog),
        findsOneWidget,
        reason: '重入守卫必须在 await 之前置位，否则会叠出两个确认框',
      );

      // 收尾：点"取消"，避免留下未关闭的对话框影响其它用例。
      final cancel = find.text('取消');
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel.first);
        await tester.pump(const Duration(milliseconds: 300));
      }
    });
  });

  group('A-12 退出看门狗兜底', () {
    test('准备阶段被卡住时由看门狗结束进程并留档', () async {
      final exitCodes = <int>[];
      DesktopService.debugExitOverride = exitCodes.add;
      DesktopService.debugWatchdogPrepare = const Duration(milliseconds: 80);
      addTearDown(() {
        DesktopService.debugExitOverride = null;
        DesktopService.debugWatchdogPrepare = const Duration(seconds: 30);
        DesktopService.debugWatchdogClose = const Duration(seconds: 10);
      });

      final hanging = _HangingProvider();
      await service.initialize(
        provider: hanging,
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      final future = service.quitApp();
      // flushPendingSaves 永不完成，只有看门狗能让退出流程结束。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(exitCodes, <int>[0], reason: '超时必须走统一退出出口，而不是静默挂死');

      // 留档：超出必须写一条错误日志，事后能查到"为什么进程没了"。
      await flushErrorLogWrites();
      final logText = await exportErrorLogText();
      expect(logText, contains('退出超时'));
      expect(
        window.last('close'),
        isNull,
        reason: '准备阶段超时时窗口还没走到关窗，看门狗直接结束进程',
      );
      // 让 quitApp 的 Future 收尾（它仍卡在 flushPendingSaves 上，不 await）。
      unawaited(future);
    });

    test('正常退出先关窗，不会被看门狗提前误杀', () async {
      final exitCodes = <int>[];
      DesktopService.debugExitOverride = exitCodes.add;
      DesktopService.debugWatchdogPrepare = const Duration(seconds: 2);
      DesktopService.debugWatchdogClose = const Duration(seconds: 2);
      addTearDown(() {
        DesktopService.debugExitOverride = null;
        DesktopService.debugWatchdogPrepare = const Duration(seconds: 30);
        DesktopService.debugWatchdogClose = const Duration(seconds: 10);
      });

      await service.initialize(
        provider: provider,
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      await service.quitApp();

      expect(
        window.last('close'),
        isNotNull,
        reason: '正常路径应由 windowManager.close 关闭窗口',
      );
      expect(
        exitCodes,
        isEmpty,
        reason: '落盘与关窗阶段不能被看门狗提前结束；关窗后的兜底由 tearDown 的 debugReset 取消',
      );
    });

  });

  group('A-24 / A-11 退出与关机时排空日志、落盘再回执', () {
    test('退出前把日志队列排空（关窗前最后一条日志不丢）', () async {
      await service.initialize(
        provider: provider,
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      appendErrorLog('test', '关窗前最后一条日志', null, context: 'A-24');

      await service.quitApp();

      // 错误日志落盘是加密的（LRX3），必须走服务的导出接口比对明文。
      final content = await exportErrorLogText();
      expect(
        content,
        contains('关窗前最后一条日志'),
        reason: 'quitApp 必须在关窗前排空日志队列，否则最后几条日志随进程消失',
      );
    });

    test('关机通知：先落盘、再回执 shutdownPrepared', () async {
      final counting = _CountingProvider();
      await service.initialize(
        provider: counting,
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _sessionChannel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('prepareForShutdown')),
        (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(counting.flushCalls, 1, reason: '关机前必须把待落盘数据刷下去');
      expect(
        session.calls.map((c) => c.method),
        contains('shutdownPrepared'),
        reason: '落盘后必须回执，原生侧据此提前结束 500ms 等待',
      );

      final content = await exportErrorLogText();
      expect(content, contains('系统即将关机'));
    });
  });
}

/// flushPendingSaves 永不完成，用来触发退出看门狗。
class _HangingProvider extends AppDataProvider {
  final Completer<void> _never = Completer<void>();

  @override
  Future<void> flushPendingSaves() => _never.future;
}

/// 统计关机前落盘调用次数。
class _CountingProvider extends AppDataProvider {
  int flushCalls = 0;

  @override
  Future<void> flushPendingSaves() async {
    flushCalls++;
  }
}
