// 审计 P2 修复专项回归（2026-10-05，第二批：界面细节与提示）。
//
//   P2-63 记录对话框缓存"原因使用次数"（大库不再每次 build 全库扫描，
//         行为由现有折叠/排序用例回归）；
//   P2-65 历史记录空态提示；
//   P2-67 "会同步登记考勤"提示覆盖自定义原因（且输入时即时刷新）；
//   P2-68 导入文件内重复行计入独立计数并提示；
//   P2-69 补名单被拒（空/超长）姓名如实提示；
//   P2-70 学生卡点击回调 setState 补 mounted 守卫（代码层核对）；
//   今日批评角标与底部区域不重叠（布局层核对）；
//   P2-72 删除确认框时段显示与列表项同口径（periodNameForRecord）；
//   P2-73 错误日志限流注释如实说明"有意设计、不影响台账完整性"（注释层）；
//   P2-74 theme.semantic 扩展缺失时按亮度回退，不再强解包崩溃。
//
// 模式沿用 v230_audit_p2_test：test() + mock path_provider。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/attendance_feature.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/widgets/history_dialog.dart';
import 'package:class_management_system/widgets/record_dialog.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_audit_p2b');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.path
          : null,
    );
    provider = AppDataProvider();
  });

  tearDown(() async {
    await flushWrites(provider);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteDirectoryWithRetry(tempDir);
  });

  group('P2-68 导入文件内重复计数', () {
    test('同一文件里完全相同的行只导入一条并计入 fileDuplicates', () {
      final preview = ImportService.parseCsvText(
        '日期,学生姓名,操作项目,原因\n'
        '2026-10-04,张三,批评,迟到\n'
        '2026-10-04,张三,批评,迟到\n',
        existing: const [],
      );

      expect(preview.records, hasLength(1));
      expect(preview.fileDuplicates, 1, reason: '文件内重复行应单独计数');
      expect(preview.skippedRows, 0);
    });
  });

  group('P2-69 补名单被拒姓名提示', () {
    test('空名与超长名被拒并计入 rejected', () {
      final result = provider.addStudentsFromImport(['张三', 'x' * 31, '  ']);

      expect(result.added, 1);
      expect(result.rejected, 2);
      expect(provider.appData.students, contains('张三'));
      expect(provider.appData.students, isNot(contains('x' * 31)));
    });
  });

  group('P2-74 theme.semantic 回退', () {
    test('未挂扩展的 ThemeData 不再崩溃，按亮度回退', () {
      final plainLight = ThemeData(brightness: Brightness.light);
      expect(plainLight.semantic.praise, AppSemanticColors.light.praise);

      final plainDark = ThemeData(brightness: Brightness.dark);
      expect(plainDark.semantic.praise, AppSemanticColors.dark.praise);
    });

    test('应用主题的 semantic 维持原值', () {
      expect(AppTheme.light().semantic.praise, AppSemanticColors.light.praise);
    });
  });

  group('P2-67 自定义原因的考勤同步提示', () {
    testWidgets('自定义原因命中同步映射时立即给出提示', (tester) async {
      await tester.pumpWidget(
        _wrap(provider, const RecordDialog(studentName: '张三')),
      );
      await tester.pump();

      // 默认同步映射含"迟到 → 迟到"；在"自定义原因"输入框输入它。
      await tester.enterText(find.byType(TextField).first, '迟到');
      await tester.pump();

      expect(find.textContaining('同步登记考勤'), findsOneWidget,
          reason: '自定义原因命中同步映射时也要提示');
    });

    testWidgets('考勤关闭时不显示同步登记考勤提示', (tester) async {
      AttendanceFeature.enabledForTests = false;
      addTearDown(() => AttendanceFeature.enabledForTests = true);

      await tester.pumpWidget(
        _wrap(provider, const RecordDialog(studentName: '张三')),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '迟到');
      await tester.pump();

      expect(find.textContaining('同步登记考勤'), findsNothing,
          reason: '考勤功能关闭后，记录对话框不应再提示同步登记考勤');
    });
  });

  group('P2-65 历史记录空态', () {
    testWidgets('没有历史记录时显示"暂无历史记录"', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: HistoryDialog()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('暂无历史记录'), findsOneWidget);
    });
  });
}
