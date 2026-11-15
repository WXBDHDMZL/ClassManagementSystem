// 测试公用工具。
//
// 背景（复核报告 V2.27.2 的 N-1）：`AppDataProvider` 的写盘是**串行的异步链**
// （`_pendingSave` + `unawaited`），用例断言往往在写盘真正落盘之前就返回了。
// 此时 `tearDown` 里立刻 `deleteSync(recursive: true)` 删临时目录，Windows 上
// 文件句柄仍被写盘占用 → 抛 `PathAccessException ... errno = 32`，
// **用例在 tearDown 阶段偶发失败**（断言本身其实是通过的）。
// `backup_rotation_test` 时序最紧、最先暴露，但凡是"造数据 → 断言 → 删临时目录"
// 的用例都可能踩到同一个竞态。
//
// 这里提供两件工具：
//  1. [deleteDirectoryWithRetry]：删除失败时有限重试（覆盖 10 个测试文件）；
//  2. [flushWrites]：用例结束前主动等待写盘链清空（更根本的做法）。
//
// 用法（推荐两者都用）：
// ```dart
// tearDown(() async {
//   await flushWrites(provider);           // 先等写盘结束
//   await deleteDirectoryWithRetry(temp);  // 再删目录（带重试兜底）
// });
// ```

import 'dart:io';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/local_storage_paths.dart';
import 'package:class_management_system/widgets/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成不包含真实学生信息的测试名单。
List<String> syntheticStudents(int count, {String prefix = '学生'}) =>
    List<String>.generate(count, (index) => '$prefix${index + 1}');

/// 建一个已经填入测试名单的 provider（不写盘、不触发通知），
/// 供不再内置真实名单后的界面/流程测试使用。
AppDataProvider providerWithStudents([
  List<String> students = const <String>['学生1', '学生2', '学生3'],
]) {
  final provider = AppDataProvider();
  provider.appData.setStudents(students);
  return provider;
}

/// 删除目录，失败时**有限重试**。
///
/// Windows 上"另一个程序正在使用此文件"（errno 32）通常是异步写盘尚未结束，
/// 短暂等待后即可删除；重试 20 次 × 50ms = 最多等 1 秒。
/// 若最终仍失败则**不再抛出**——避免把"清理不掉的临时目录"变成用例失败
/// （临时目录本身由系统在临时目录里自然回收，不删也不影响正确性）。
Future<void> deleteDirectoryWithRetry(
  Directory dir, {
  int attempts = 20,
  Duration interval = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } catch (_) {
      await Future<void>.delayed(interval);
    }
  }
  // 最终仍删不掉：按约定不抛出（不把清理失败变成用例失败），但留痕便于
  // 排查——如果某文件频繁删不掉，说明该用例的写盘时序有问题，值得看。
  debugPrint(
    'deleteDirectoryWithRetry: 重试 $attempts 次后仍无法删除 ${dir.path}',
  );
}

/// 等待 [provider] 已排队的写盘任务全部完成（不写盘则立即返回）。
///
/// 这是消除 N-1 竞态的**根本做法**：写盘链本来就提供了 `flushPendingSaves()`，
/// 用例结束前等一下，就不会与 tearDown 的删目录抢文件句柄。
///
/// 加 [timeout] 兜底（第 12 轮）：测试环境里 path_provider 缺失，写盘会走
/// "失败并返回 false"的路径；个别用例（如 daily_export ③，末尾打开了考勤
/// 对话框）会把写盘链的最后一段留在假异步 zone 里，测试体结束后该 Future
/// 再也不会完成 —— tearDown 若无限等待会**挂起整整 10 分钟**（表现为用例超时
/// 失败）。这里最多等 5 秒，超时就放弃等待（临时目录删不掉也不影响用例结果），
/// 让"清理等待"永远不会变成用例失败或长时间挂起。
Future<void> flushWrites(AppDataProvider? provider) async {
  if (provider == null) return;
  try {
    await provider
        .flushPendingSaves()
        .timeout(const Duration(seconds: 5), onTimeout: () {
      debugPrint('flushWrites: 写盘链 5 秒内未完成，放弃等待（不影响用例结果）');
    });
  } catch (_) {
    // 个别用例的写盘失败是断言的对象，这里不掩盖、也不额外抛出。
  }
}

/// 建一个临时“文档目录”，并在其中预建程序的固定数据根目录。
///
/// 返回的是 `文档/班级管理系统`（真正的数据根），调用方既可以直接拼
/// `class_management_data.enc`、`日志`、`备份` 等路径，也应把
/// 返回值的 `.parent` 交给 path_provider 的文档目录 mock。
Directory createStorageTestRoot(String prefix) {
  final docs = Directory.systemTemp.createTempSync(prefix);
  return Directory(
    '${docs.path}${Platform.pathSeparator}${LocalStoragePaths.rootFolderName}',
  )..createSync(recursive: true);
}

/// 删除 [createStorageTestRoot] 创建的整个临时文档目录（含数据根）。
Future<void> deleteStorageTestRoot(Directory storageRoot) =>
    deleteDirectoryWithRetry(storageRoot.parent);

/// 给测试用的 [MaterialApp] 挂上通知作用域与宿主。
///
/// 生产入口在 `main.dart` 的 `MaterialApp.builder` 里挂了同一套 Scope；
/// 测试如果直接 pump 业务页面而没有 Scope，`showTopSnackBar` 会明确报错。
/// 这个包装只负责测试环境，不改变生产回退策略。
Widget testApp({
  required Widget home,
  ThemeData? theme,
  AppNoticeController? controller,
}) {
  return _TestApp(home: home, theme: theme, controller: controller);
}

class _TestApp extends StatefulWidget {
  const _TestApp({required this.home, this.theme, this.controller});

  final Widget home;
  final ThemeData? theme;
  final AppNoticeController? controller;

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  late final AppNoticeController _controller =
      widget.controller ?? AppNoticeController();
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: widget.theme,
      builder: (context, child) => AppNotificationScope(
        controller: _controller,
        child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
      ),
      home: widget.home,
    );
  }
}

/// 交替推进"真实事件循环 + 假异步队列"，直到 [condition] 成立或轮次耗尽。
///
/// 用途（性能批 M6/H4）：界面里有些校验/解析会 await `Isolate.run` 的结果，
/// 而 widget 测试默认跑在 FakeAsync 环境里 —— 单靠 `pump()` 只推进假时钟与
/// 微任务队列，isolate 的结果消息永远送不到主 isolate。必须用 `tester.runAsync`
/// 让真实事件循环跑一小段，再 `pump()` 把送达后触发的续体冲完，交替进行。
///
/// [condition] 建议用 `find.xxx.evaluate().isNotEmpty` 这类「目标已出现」判断。
/// 返回是否在轮次内满足；调用方可自行断言。
Future<bool> pumpUntilRealAsync(
  WidgetTester tester,
  bool Function() condition, {
  int maxRounds = 300,
  Duration step = const Duration(milliseconds: 10),
}) async {
  for (var i = 0; i < maxRounds; i++) {
    if (condition()) return true;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
  return condition();
}
