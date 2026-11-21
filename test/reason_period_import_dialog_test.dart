/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/period_import_dialog.dart';
import 'package:class_management_system/widgets/reason_import_dialog.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('粘贴原因文本后预览并可补充到原因库', (tester) async {
    final provider = providerWithStudents(const ['学生1']);

    await tester.pumpWidget(_wrap(provider, const ReasonImportDialog()));
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      '表扬\t08:00-12:30、14:00-16:40 上课\t认真听课\n'
      '批评\t\t走神',
    );
    await tester.pump();

    expect(find.text('识别到 2 条原因（表扬 1 / 批评 1）'), findsOneWidget);

    await tester.tap(find.text('补充到原因库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(provider.appData.reasons.praise['class'], contains('认真听课'));
    expect(provider.appData.reasons.criticism['_common'], contains('走神'));
  });

  testWidgets('替换原因库前会二次确认', (tester) async {
    final provider = providerWithStudents(const ['学生1']);

    await tester.pumpWidget(_wrap(provider, const ReasonImportDialog()));
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      '表扬\t\t主动帮忙\n'
      '批评\t\t走神',
    );
    await tester.pump();
    expect(find.text('识别到 2 条原因（表扬 1 / 批评 1）'), findsOneWidget);

    await tester.tap(find.text('替换原因库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('将用识别到的 2 条原因替换当前原因库。历史记录里已保存的原因不会被删除。'),
      findsOneWidget,
    );
    await tester.tap(find.text('替换'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(provider.appData.reasons.praise['_common'], ['主动帮忙']);
    expect(provider.appData.reasons.criticism['_common'], ['走神']);
  });

  testWidgets('粘贴时段文本后应用会返回解析结果', (tester) async {
    final provider = providerWithStudents(const ['学生1']);
    List<Map<String, String>>? applied;

    await tester.pumpWidget(
      _wrap(
        provider,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              applied = await PeriodImportDialog.show(context);
            },
            child: const Text('导入时段'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('导入时段'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'morning_reading\t07:00-08:00 早读\n'
      '19:00-21:30 晚自习',
    );
    await tester.pump();

    expect(find.text('识别到 2 个时段'), findsOneWidget);

    await tester.tap(find.text('应用到列表'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.length, 2);
    expect(applied![0]['key'], 'morning_reading');
    expect(applied![1]['label'], '19:00-21:30 晚自习');
  });
}
