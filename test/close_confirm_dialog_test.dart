// 关闭确认对话框测试：最小化到托盘 / 退出程序 / 取消三条路径，
// 以及"记住我的选择"勾选状态是否正确回传。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/widgets/close_confirm_dialog.dart';

/// 打开对话框并把用户选择写入 [onResult]。
Future<void> _openDialog(
  WidgetTester tester,
  void Function(CloseConfirmResult?) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            onResult(await CloseConfirmDialog.show(context));
          },
          child: const Text('测试打开'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('测试打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('选择“最小化到托盘”：返回对应行为且默认不记住', (tester) async {
    CloseConfirmResult? result;
    await _openDialog(tester, (value) => result = value);

    expect(find.text('关闭窗口'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '最小化到托盘'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.action, CloseActionType.minimizeToTray);
    expect(result!.remember, isFalse);
  });

  testWidgets('选择“最小化到悬浮球”：返回对应行为且默认不记住', (tester) async {
    CloseConfirmResult? result;
    await _openDialog(tester, (value) => result = value);

    await tester.tap(find.widgetWithText(TextButton, '最小化到悬浮球'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.action, CloseActionType.minimizeToBall);
    expect(result!.remember, isFalse);
  });

  testWidgets('勾选“记住我的选择”后选择“退出程序”', (tester) async {
    CloseConfirmResult? result;
    await _openDialog(tester, (value) => result = value);

    await tester.tap(find.text('记住我的选择，不再询问'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '退出程序'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.action, CloseActionType.exit);
    expect(result!.remember, isTrue);
  });

  testWidgets('点击“取消”：返回 null，窗口保持打开', (tester) async {
    CloseConfirmResult? result;
    var closed = false;
    await _openDialog(tester, (value) {
      closed = true;
      result = value;
    });

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });
}
