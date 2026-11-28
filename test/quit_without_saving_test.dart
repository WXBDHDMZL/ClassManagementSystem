// 审计 A-01：阻断态下的"退出并换回原密钥"必须是**不保存**退出。
//
// 关键回归点：`quitApp()` 会 `flushPendingSaves()` 并可能触发退出备份；
// 数据处于阻断状态时这两件事都必须发生不了，否则"阻断"形同虚设。
// 原生窗口/托盘无法在单元测试里跑，这里通过三个 MethodChannel 的 mock
// 断言"该调哪个原生方法、有没有意外写盘"，并注入 exit 以免杀掉测试进程。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/desktop_service.dart';

const MethodChannel _windowChannel = MethodChannel('window_manager');
const MethodChannel _trayChannel = MethodChannel('tray_manager');
const MethodChannel _ballChannel = MethodChannel('class_management_system/ball');

/// 记录通道收到的全部方法调用。
class _Recorded {
  final List<MethodCall> calls = [];

  bool has(String method) => calls.any((c) => c.method == method);

  MethodCall? last(String method) {
    final matched = calls.where((c) => c.method == method).toList();
    return matched.isEmpty ? null : matched.last;
  }
}

/// 统计"会不会写盘"的 provider 探针。
class _CountingProvider extends AppDataProvider {
  int flushCalls = 0;
  int exitBackupCalls = 0;

  @override
  Future<void> flushPendingSaves() async {
    flushCalls++;
    await super.flushPendingSaves();
  }

  @override
  Future<String?> performExitBackup() async {
    exitBackupCalls++;
    return super.performExitBackup();
  }
}

void main() {
  final service = DesktopService.instance;
  late _Recorded window;
  late _Recorded tray;
  late _CountingProvider provider;
  late bool closeFails;
  late List<int> exitCodes;

  void mock(MethodChannel channel, _Recorded rec, Object? Function(MethodCall) onCall) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      rec.calls.add(call);
      return onCall(call);
    });
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    service.debugReset();
    window = _Recorded();
    tray = _Recorded();
    closeFails = false;
    exitCodes = <int>[];
    DesktopService.debugExitOverride = (code) => exitCodes.add(code);

    mock(_windowChannel, window, (call) {
      if (closeFails && call.method == 'close') {
        throw PlatformException(code: 'unavailable', message: '关窗失败');
      }
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
    mock(_trayChannel, tray, (call) => null);
    mock(_ballChannel, _Recorded(), (call) => null);

    provider = _CountingProvider();
    provider.replaceStudents(['张三', '李四']);
  });

  tearDown(() {
    service.debugReset();
    DesktopService.debugExitOverride = null;
    for (final channel in [_windowChannel, _trayChannel, _ballChannel]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> initService() => service.initialize(
    provider: provider,
    navigatorKey: GlobalKey<NavigatorState>(),
  );

  group('quitWithoutSaving', () {
    test('不调用 flushPendingSaves / 退出备份，只解除拦截并关窗', () async {
      await initService();

      await service.quitWithoutSaving(reason: '测试：数据阻断');

      expect(provider.flushCalls, 0, reason: '不保存退出绝不能 flush 写盘队列');
      expect(provider.exitBackupCalls, 0, reason: '不保存退出绝不能触发退出备份');

      final preventClose = window.last('setPreventClose');
      expect(preventClose, isNotNull);
      expect((preventClose!.arguments as Map)['isPreventClose'], isFalse,
          reason: '必须先解除关闭拦截，close 才不会被拦回来');
      expect(window.has('close'), isTrue, reason: '必须尝试关闭窗口');
      expect(tray.has('destroy'), isTrue, reason: '必须移除托盘图标');
      expect(exitCodes, isEmpty,
          reason: '关窗成功后进程自行结束；兜底计时器此时不应立刻触发');
    });

    test('关窗失败时走 200ms 兜底结束进程（不留看不见的僵尸）', () async {
      await initService();
      closeFails = true;

      await service.quitWithoutSaving(reason: '测试：关窗失败');
      expect(exitCodes, isEmpty, reason: '兜底是延时触发，方法返回时应尚未退出');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(exitCodes, [0], reason: '关窗失败必须兜底退出，否则托盘图标已没了但进程还在');
    });

    test('托盘销毁失败也不妨碍继续关窗', () async {
      await initService();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_trayChannel, (call) async {
        tray.calls.add(call);
        if (call.method == 'destroy') {
          throw PlatformException(code: 'unavailable', message: '托盘不可用');
        }
        return null;
      });

      await service.quitWithoutSaving(reason: '测试：托盘失败');

      expect(tray.has('destroy'), isTrue);
      expect(window.has('close'), isTrue, reason: '托盘失败不能阻断关窗');
      expect(provider.flushCalls, 0);
    });

    test('重复调用只执行一次（_quitting 门闩）', () async {
      await initService();

      await service.quitWithoutSaving(reason: '第一次');
      await service.quitWithoutSaving(reason: '第二次');

      final destroys = tray.calls.where((c) => c.method == 'destroy').length;
      expect(destroys, 1, reason: '门闩内重复调用不得重复销毁托盘');
    });

    test('未初始化也能退出（不依赖托盘/球注册）', () async {
      await service.quitWithoutSaving(reason: '测试：未初始化');

      expect(window.has('close'), isTrue);
      expect(provider.flushCalls, 0);
      expect(provider.exitBackupCalls, 0);
    });
  });
}
