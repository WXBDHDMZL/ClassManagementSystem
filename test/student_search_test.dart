import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/main.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/student_card.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider) => ChangeNotifierProvider.value(
  value: provider,
  child: testApp(
    theme: AppTheme.light(),
    home: const Scaffold(body: SafeArea(child: HomePage())),
  ),
);

void main() {
  testWidgets('学生搜索实时筛选名单，搜索时隐藏批量入口，清空后恢复', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(
      const ['张三', '李四', '王五', '赵六'],
    );
    final students = provider.appData.students;
    expect(students.length, greaterThanOrEqualTo(2));
    final first = students.first;
    final second = students[1];

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    expect(find.text('批量'), findsOneWidget);
    expect(find.widgetWithText(StudentCard, first), findsOneWidget);
    expect(find.widgetWithText(StudentCard, second), findsOneWidget);

    await tester.enterText(find.byType(TextField), first);
    await tester.pump();

    expect(find.widgetWithText(StudentCard, first), findsOneWidget);
    expect(find.widgetWithText(StudentCard, second), findsNothing);
    expect(find.text('批量'), findsNothing);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();

    expect(find.text('批量'), findsOneWidget);
    expect(find.widgetWithText(StudentCard, first), findsOneWidget);
    expect(find.widgetWithText(StudentCard, second), findsOneWidget);
  });

  testWidgets('没有匹配学生时显示提示，不显示批量入口', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(
      const ['张三', '李四', '王五', '赵六'],
    );
    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '不存在的学生姓名');
    await tester.pump();

    expect(find.text('未找到匹配学生'), findsOneWidget);
    expect(find.text('批量'), findsNothing);
  });

  testWidgets('关闭主页学生搜索后隐藏搜索框并恢复完整名单', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(
      const ['张三', '李四', '王五', '赵六'],
    );
    final students = provider.appData.students;
    final first = students.first;
    final second = students[1];

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.enterText(find.byType(TextField), first);
    await tester.pump();
    expect(find.widgetWithText(StudentCard, second), findsNothing);

    provider.setStudentSearchEnabled(false);
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(StudentCard, second), findsOneWidget);
    expect(find.text('批量'), findsOneWidget);
  });
}
