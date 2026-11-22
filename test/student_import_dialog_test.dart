/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
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
import 'package:class_management_system/widgets/student_import_dialog.dart';

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
  testWidgets('粘贴文本后预览姓名并可补充到名单', (tester) async {
    final provider = providerWithStudents(const ['学生1']);

    await tester.pumpWidget(
      _wrap(provider, const StudentImportDialog()),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '学生2\n学生3\n学生2');
    await tester.pump();

    expect(find.text('识别到 2 人'), findsOneWidget);
    expect(find.text('已合并 1 个重复姓名'), findsOneWidget);

    await tester.tap(find.text('补充到名单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(provider.appData.students, containsAll(['学生1', '学生2', '学生3']));
  });

  testWidgets('替换现有名单前会二次确认', (tester) async {
    final provider = providerWithStudents(const ['学生1', '学生2']);

    await tester.pumpWidget(
      _wrap(provider, const StudentImportDialog()),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '学生3\n学生4');
    await tester.pump();
    expect(find.text('识别到 2 人'), findsOneWidget);

    await tester.tap(find.text('替换现有名单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('将用识别到的 2 人替换当前 2 人名单。历史记录不会被删除。'),
      findsOneWidget,
    );
    await tester.tap(find.text('替换'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(provider.appData.students, ['学生3', '学生4']);
  });
}
