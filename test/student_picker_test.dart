// 学生选择框测试：多选必须能同时选中多人（曾漏传 multiSelect 导致只能单选），
// 单选场景则用单选按钮、选中互斥。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/widgets/student_picker_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('多选：可以同时选中多名学生', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StudentPickerDialog(
          title: '选择学生（可多选）',
          students: ['张三', '李四', '王五'],
          multiSelect: true,
        ),
      ),
    );

    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(find.byType(RadioListTile<String>), findsNothing);

    await tester.tap(find.text('张三'));
    await tester.pump();
    await tester.tap(find.text('李四'));
    await tester.pump();

    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(boxes[0].value, isTrue);
    expect(boxes[1].value, isTrue);
    expect(boxes[2].value, isFalse);

    // 再点一次取消选择
    await tester.tap(find.text('张三'));
    await tester.pump();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .first
          .value,
      isFalse,
    );
  });

  testWidgets('单选：用单选按钮且选中互斥（避免"看着能多选其实只能单选"）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StudentPickerDialog(
          title: '选择学生',
          students: ['张三', '李四'],
        ),
      ),
    );

    expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(find.text('张三'));
    await tester.pump();
    await tester.tap(find.text('李四'));
    await tester.pump();

    final radios = tester
        .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
        .toList();
    // RadioGroup 统一管理选中值，选中李四后只有李四被选中
    final group = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, '李四');
    expect(radios.length, 2);
  });

  testWidgets('搜索过滤后仍可多选，副标题按学生显示', (tester) async {
    await tester.pumpWidget(
      _wrap(
        StudentPickerDialog(
          title: '选择学生（可多选）',
          students: const ['张三', '李四', '张小明'],
          multiSelect: true,
          subtitleBuilder: (name) => '状态：$name',
        ),
      ),
    );

    expect(find.text('状态：张三'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '张');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    await tester.tap(find.text('张小明'));
    await tester.pump();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .last
          .value,
      isTrue,
    );
  });
}
