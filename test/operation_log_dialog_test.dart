// 操作日志查看器（OperationLogDialog）的界面回归。
//
// 背景（V2.28.1 测试补空白）：操作日志查看器此前 0 测试。写它的过程中
// 两次踩到 testWidgets 的 IO 死锁（挂 12/8 分钟），探针实验定位出准确机制：
// **testWidgets 里未 mock 的 platform channel 会永久挂起**（invokeMethod 在等
// 引擎回复事件，FakeAsync zone 永远收不到 native 回调）；mock 返回路径也不行——
// 后续真实文件 IO 同样挂死。正确做法是 mock handler **返回 null**：
// path_provider 立即抛 MissingPlatformDirectoryException，全链零真实 IO，
// 且恰好真实模拟"文档目录不可用"的降级场景（交接说明 §2.1 第 15 条已更新）。
//
// 为此给 _load 加了 try/catch 防御（V2.28.1）：读取失败退出加载态并显示红色
// 错误提示，绝不永远转圈。依赖真实读文件的"日志行展示"逻辑由 operation_log_test
// （服务层 readTail/格式）覆盖，本文件负责界面层的降级、按钮与关闭。
// 无 snackbar 用例所以无定时器，收尾照惯例多 pump 一帧并清树。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/widgets/operation_log_dialog.dart';

Future<void> _pumpDialog(WidgetTester tester) async {
  // 按真实使用方式 showDialog 打开：对话框的"关闭"按钮是 Navigator.pop，
  // 直接塞进 home body 的话 pop 没有路由可弹。
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  final context = tester.element(find.byType(Scaffold));
  unawaited(showDialog<void>(
    context: context,
    builder: (_) => const OperationLogDialog(),
  ));
  await tester.pump(); // 进场动画
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _settleDown(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 返回 null = 模拟"文档目录不可用"：path_provider 立即抛
    // MissingPlatformDirectoryException，全链不碰真实 IO（fake zone 可推进）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  testWidgets('文档目录不可用：退出加载态，显示红色错误提示而不是永远转圈',
      (tester) async {
    await _pumpDialog(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '读取失败后绝不能停在转圈上');
    expect(find.textContaining('日志读取失败'), findsOneWidget);
    expect(find.text('暂无日志'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '读取失败要被内部消化，不能有未捕获异常');

    await _settleDown(tester);
  });

  testWidgets('按钮齐备：刷新 / 打开位置（只断言存在，不点击）/ 复制全部 / 关闭',
      (tester) async {
    await _pumpDialog(tester);

    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(find.byTooltip('打开日志文件位置'), findsOneWidget,
        reason: '该按钮会启动 explorer 进程，测试里只能断言存在、绝不点击');
    expect(find.text('复制全部'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('操作日志'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _settleDown(tester);
  });

  testWidgets('没有日志时点"复制全部"：安全无事发生（空列表直接返回）', (tester) async {
    await _pumpDialog(tester);

    await tester.tap(find.text('复制全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('已复制日志内容到剪贴板'), findsNothing,
        reason: '没有日志时不应弹出"已复制"的误导提示');
    expect(tester.takeException(), isNull);

    await _settleDown(tester);
  });

  testWidgets('关闭按钮：弹窗收起', (tester) async {
    await _pumpDialog(tester);

    await tester.tap(find.text('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('操作日志'), findsNothing);
    expect(tester.takeException(), isNull);

    await _settleDown(tester);
  });
}
