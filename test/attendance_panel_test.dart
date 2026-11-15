// 班级管理系统 - 记录面板底部按钮测试：
// 启用考勤后底部会多出"考勤"入口，验证在右侧面板的固定宽度下三个按钮仍不溢出。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/record_list.dart';

Future<void> _pumpPanel(
  WidgetTester tester,
  AppDataProvider provider,
  double width,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        // 必须使用应用主题：语义色由 AppSemanticTheme 扩展提供。
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 600,
              child: const RecordList(records: []),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('未启用考勤时记录面板底部只有历史记录与数据统计', (WidgetTester tester) async {
    final provider = AppDataProvider();
    await _pumpPanel(tester, provider, 328);

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('数据统计'), findsOneWidget);
    expect(find.text('考勤'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('启用考勤后三个按钮在面板宽度内不溢出', (WidgetTester tester) async {
    final provider = AppDataProvider();
    provider.setAttendanceEnabled(true);
    await _pumpPanel(tester, provider, 328);

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('数据统计'), findsOneWidget);
    expect(find.text('考勤'), findsOneWidget);
    // 布局溢出会以异常形式抛出（FlutterError），此处应为空。
    expect(tester.takeException(), isNull);
  });
}
