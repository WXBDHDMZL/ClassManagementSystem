import 'package:flutter/material.dart';
import 'package:class_management_system/models/undo_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/widgets/app_notification.dart';

void main() {
  testWidgets('通知立即叠放：新通知不等待上一条消失', (tester) async {
    final controller = AppNoticeController();
    addTearDown(controller.dispose);

    final first = controller.show('第一条');
    await tester.pump(const Duration(milliseconds: 500));
    controller.show('第二条');
    expect(controller.current?.message, '第一条');
    expect(controller.active, hasLength(2));
    expect(controller.active.last.message, '第二条');
    expect(first.isDone, isFalse);

    await tester.pump(const Duration(milliseconds: 2100));
    expect(controller.current?.message, '第二条');
    expect(controller.active, hasLength(1));
    expect(first.isDone, isTrue);

    controller.dismissAll();
  });

  testWidgets('超过上限时优先淘汰最早的普通提示', (tester) async {
    final controller = AppNoticeController();
    addTearDown(controller.dispose);

    controller.show('错误 A', kind: AppNoticeKind.error);
    controller.show('警告 B', kind: AppNoticeKind.warning);
    final normal = controller.show('普通 C');
    expect(controller.active, hasLength(3));

    controller.show('错误 D', kind: AppNoticeKind.error);
    expect(controller.active, hasLength(AppNoticeController.maxVisible));
    expect(controller.active.map((notice) => notice.message).toList(), [
      '错误 A',
      '警告 B',
      '错误 D',
    ]);
    expect(normal.isDone, isTrue);

    controller.dismissAll();
  });

  testWidgets('全是重要提示时，新普通提示也不会被立即挤掉', (tester) async {
    final controller = AppNoticeController();
    addTearDown(controller.dispose);

    final first = controller.show('错误 A', kind: AppNoticeKind.error);
    controller.show('错误 B', kind: AppNoticeKind.error);
    controller.show('错误 C', kind: AppNoticeKind.error);
    controller.show('普通 D');

    expect(controller.active, hasLength(3));
    expect(controller.active.last.message, '普通 D');
    expect(first.isDone, isTrue);

    controller.dismissAll();
  });

  testWidgets('常驻通知不自动消失，不影响瞬时通知', (tester) async {
    final controller = AppNoticeController();
    addTearDown(controller.dispose);

    controller.showPinned('数据写入失败');
    controller.show('普通提示');
    expect(controller.pinned?.message, '数据写入失败');
    expect(controller.current?.message, '普通提示');

    await tester.pump(const Duration(milliseconds: 3000));
    expect(controller.pinned?.message, '数据写入失败');
    expect(controller.current, isNull);

    controller.clearPinned();
    expect(controller.pinned, isNull);
    controller.dismissAll();
  });

  testWidgets('宿主在 Navigator 上方：对话框打开后顶部通知仍可见', (tester) async {
    final controller = AppNoticeController();
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppNotificationScope(
          controller: controller,
          child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('对话框')),
                ),
                child: const Text('打开对话框'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开对话框'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    showTopSnackBar(hostContext, '顶层通知');
    await tester.pump();
    expect(find.text('顶层通知'), findsOneWidget);
    expect(find.text('对话框'), findsOneWidget);

    controller.dismissAll();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('通知层不拦截背后的点击', (tester) async {
    final controller = AppNoticeController();
    late BuildContext hostContext;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppNotificationScope(
          controller: controller,
          child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    top: 92,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: () => taps++,
                        child: const Text('背后按钮'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    showTopSnackBar(hostContext, '测试通知');
    await tester.pump();
    expect(find.text('测试通知'), findsOneWidget);

    await tester.tap(find.text('背后按钮'));
    expect(taps, 1, reason: '通知层必须 IgnorePointer，不能拦截背后操作');

    controller.dismissAll();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('带动作的通知显示按钮，点击后执行并给出结果', (tester) async {
    final controller = AppNoticeController();
    late BuildContext hostContext;
    var undoCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppNotificationScope(
          controller: controller,
          child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    showUndoTopSnackBar(
      hostContext,
      '已记录：张三 · 表扬',
      onUndo: () async {
        undoCount++;
        return const UndoResult(changed: 1, saved: true);
      },
    );
    await tester.pump();
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(undoCount, 1);
    expect(find.text('已撤销本次记录'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);

    controller.dismissAll();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  // 审计 A-18b：撤销结果要分三种如实报告，不能一律显示"已撤销"。
  testWidgets('撤销落盘失败时明确告知磁盘仍是旧数据', (tester) async {
    final controller = AppNoticeController();
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppNotificationScope(
          controller: controller,
          child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    showUndoTopSnackBar(
      hostContext,
      '已记录：张三 · 表扬',
      onUndo: () async => const UndoResult(changed: 1, saved: false),
    );
    await tester.pump();
    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(find.text('已撤销本次记录'), findsNothing,
        reason: '磁盘没写成时不得显示成功');
    expect(
      find.text('已撤销本次记录，但保存失败：磁盘仍是撤销前的数据，请检查磁盘空间或文件权限'),
      findsOneWidget,
    );

    controller.dismissAll();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('撤销已过期时告知失败而不是假装成功', (tester) async {
    final controller = AppNoticeController();
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppNotificationScope(
          controller: controller,
          child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    showUndoTopSnackBar(
      hostContext,
      '已记录：张三 · 表扬',
      onUndo: () async => UndoResult.none,
    );
    await tester.pump();
    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(find.text('撤销失败：操作已过期或记录已被修改'), findsOneWidget);

    controller.dismissAll();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('普通提示不挡住下方按钮', (tester) async {
    final controller = AppNoticeController();
    addTearDown(controller.dispose);
    late BuildContext hostContext;
    var tapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => AppNotificationScope(
          controller: controller,
          child: AppNotificationHost(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    top: 90,
                    left: 20,
                    right: 20,
                    child: SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () => tapped++,
                        child: const Text('下方按钮'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    showTopSnackBar(hostContext, '普通提示');
    await tester.pump();
    expect(find.text('普通提示'), findsOneWidget);

    await tester.tap(find.text('下方按钮'));
    expect(tapped, 1);

    controller.dismissAll();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新的动作通知会让上一条动作通知立即失效', (tester) async {
    final controller = AppNoticeController();
    addTearDown(controller.dispose);

    final first = controller.show(
      '第一次记录',
      action: AppNoticeAction(label: '撤销', onPressed: () {}),
    );
    final second = controller.show(
      '第二次记录',
      action: AppNoticeAction(label: '撤销', onPressed: () {}),
    );

    expect(first.isDone, isTrue);
    expect(second.isDone, isFalse);
    expect(controller.active.map((notice) => notice.message).toList(), [
      '第二次记录',
    ]);
    expect(controller.hasAction, isTrue);

    controller.dismissAll();
  });

  testWidgets('无 Scope 时明确报错，不再使用旧 Overlay 回退', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );

    try {
      expect(
        () => showTopSnackBar(context, '无 Scope'),
        throwsA(isA<FlutterError>()),
      );
    } finally {
      // 让旧实现留下的计时器也能在失败测试中完成清理。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
    }
  });
}
