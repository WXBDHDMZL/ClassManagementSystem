// 日常使用全流程回归（第 1 部分：记录操作多入口 + 内容展示）。
// 模拟老师的真实一天：点学生卡片记录 → 事后批量补录 → 修改/删除 → 考勤登记
// （含与批评记录双向同步）→ 表格导入。每一步都同时校验"数据已保存"与"界面展示正确"。
// 全程使用内存数据 + 临时导出目录，绝不触碰用户真实数据文件。

import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/main.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/attendance_dialog.dart';
import 'package:class_management_system/widgets/history_dialog.dart';
import 'package:class_management_system/widgets/import_records_dialog.dart';
import 'package:class_management_system/widgets/record_dialog.dart';
import 'package:class_management_system/widgets/record_list.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    );

/// 通过 showDialog 打开对话框：与用户点击路径一致，
/// 且对话框是独立路由（pop 时不会把根路由一起弹掉）。
Future<void> _pumpDialog(
  WidgetTester tester,
  AppDataProvider provider,
  Widget dialog,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('打开对话框'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await tester.pumpAndSettle();
}

/// 点一个 FilterChip（原因/时段）并等待重建。
Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  expect(chip, findsOneWidget, reason: '应能找到「$label」选项');
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// 原因较多时界面会折叠，先点"展开全部"（文案形如"展开全部（18）"）。
Future<void> _expandReasons(WidgetTester tester) async {
  final more = find.textContaining('展开全部');
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more.first);
    await tester.pumpAndSettle();
  }
}

/// 数据改动后等一等：provider 的"保存队列 → notifyListeners"是一条真实异步链
/// （测试环境里保存必然失败，但刷新仍会触发），只靠 pumpAndSettle 等不到它，
/// 会出现"数据已改、界面还是旧的"的假失败。
Future<void> _settleData(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// 点确认按钮（记录对话框较高，先滚到可见处）。
Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('确认'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认'));
  await tester.pumpAndSettle();
  await _settleData(tester);
}

/// 跑掉顶部提示的 2 秒定时器，避免测试结束时残留 Timer。
Future<void> _drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cms_daily_flow');
  });

  tearDown(() async {
    // N-1：写盘是异步的，等它结束后再删目录（带重试），避免文件句柄占用造成偶发失败。
    await deleteDirectoryWithRetry(tempDir);
  });

  testWidgets('① 主页点学生卡片记录：数据落库 + 今日面板与历史列表展示正确', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(syntheticStudents(5));
    provider.setExportPath(tempDir.path);
    // 固定默认类型与时段，让原因列表可预期（真实使用中这两项可配置）。
    provider.setRecordDefaults(defaultType: 0, autoSelectPeriod: false);

    await tester.pumpWidget(_wrap(provider, const HomePage()));
    await tester.pump();

    final student = provider.appData.students.first;
    expect(find.text(student), findsWidgets, reason: '主页应展示学生卡片');

    // 点学生卡片 → 打开记录对话框
    await tester.tap(find.text(student).first);
    await tester.pumpAndSettle();
    expect(find.text('为 $student 操作'), findsOneWidget);

    // 先选原因（默认时段下"全时段通用"原因可见），再选时段"上课"；
    // 切成"上课"后已选原因仍在该时段的可选范围内，不会被剔除。
    await _tapChip(tester, '助人为乐');
    await _tapChip(tester, '上课');
    await _tapConfirm(tester);

    // 数据已保存
    final today = provider.getTodayRecords();
    expect(today, hasLength(1));
    expect(today.first.studentName, student);
    expect(today.first.operationType, '表扬');
    expect(today.first.reasons, '助人为乐');
    expect(today.first.periodKey, 'class');
    expect(today.first.date, StatisticsService.todayString(AppClock.now()));

    // 今日记录面板展示：姓名 + 原因 + 时段 + 表扬标签
    expect(find.text('今日记录'), findsOneWidget);
    expect(find.textContaining('助人为乐 · 上课'), findsOneWidget);
    expect(find.widgetWithText(Container, '表扬'), findsWidgets);

    await _drainSnackBars(tester);
  });

  testWidgets('② 事后批量补录：一次给 3 名学生追加到指定日期，历史列表按日期分组展示', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(syntheticStudents(5));
    provider.setExportPath(tempDir.path);
    provider.setRecordDefaults(defaultType: 1, autoSelectPeriod: false);
    final students = provider.appData.students.take(3).toList();
    const pastDate = '2026-09-20';

    // 走真实的"批量追加"入口（历史记录里多选学生后构造的对话框）
    await _pumpDialog(
      tester,
      provider,
      RecordDialog(
        studentName: '',
        targetDate: pastDate,
        isAppend: true,
        isBatch: true,
        selectedStudents: students,
      ),
    );
    expect(find.text('为 ${students[0]}、${students[1]} 等 3 人操作'), findsOneWidget);

    await _tapChip(tester, '上课');
    await _tapChip(tester, '讲话');
    await _tapConfirm(tester);

    // 数据：3 名学生各一条，全部落在指定日期，且标记为“批量”
    final dayRecords = provider.getRecordsForDate(pastDate);
    expect(dayRecords, hasLength(3));
    for (final record in dayRecords) {
      expect(record.date, pastDate);
      expect(record.operationType, '批评');
      expect(record.reasons, '讲话');
      expect(record.isAppended, isTrue);
      expect(record.isBatch, isTrue);
      expect(record.remark, '批量', reason: '批量补录应有“批量”备注');
    }
    expect(provider.getHistoryDates(), contains(pastDate));

    // 展示：历史对话框里该日期分组存在，展开后能看到 3 名学生与“批量”标签
    await tester.pumpWidget(_wrap(provider, const HistoryDialog()));
    await tester.pumpAndSettle();
    expect(find.text(pastDate), findsOneWidget);
    await tester.tap(find.text(pastDate));
    await tester.pumpAndSettle();
    for (final name in students) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.text('批量'), findsNWidgets(3));

    await _drainSnackBars(tester);
  });

  testWidgets('③ 修改与删除记录：操作可撤销，数据与展示同步更新', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(syntheticStudents(5));
    provider.setExportPath(tempDir.path);
    provider.setRecordDefaults(defaultType: 0, autoSelectPeriod: false);
    final student = provider.appData.students.first;
    provider.addRecord(student, '表扬', const ['作业优秀'], 'class', '');

    await tester.pumpWidget(_wrap(provider, const HomePage()));
    await tester.pump();
    expect(find.textContaining('作业优秀'), findsOneWidget);

    // 修改：点该条记录的编辑按钮 → 换成另一个原因
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    expect(find.text('编辑 $student 的记录'), findsOneWidget);
    await _expandReasons(tester);
    // 取消原来的"作业优秀"，改选"助人为乐"（验证的是"修改"而不是"追加原因"）
    await _tapChip(tester, '作业优秀');
    await _tapChip(tester, '助人为乐');
    await _tapConfirm(tester);

    expect(provider.getTodayRecords(), hasLength(1));
    expect(provider.getTodayRecords().first.reasons, '助人为乐');
    expect(find.textContaining('助人为乐'), findsOneWidget);
    expect(find.textContaining('作业优秀'), findsNothing);
    expect(find.text('已修改记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    // 删除：不再弹二次确认，直接删除并显示撤销入口
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    expect(find.text('删除记录'), findsNothing);
    expect(find.textContaining('删除后无法撤销'), findsNothing);
    await _settleData(tester);

    expect(provider.getTodayRecords(), isEmpty);
    expect(find.text('暂无记录'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await _drainSnackBars(tester);
  });

  testWidgets('④ 考勤登记与批评记录双向同步：登记生成、撤销回收，对话框展示正确', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(syntheticStudents(5));
    provider.setAttendanceEnabled(true);
    final student = provider.appData.students.first;
    // 考勤对话框默认日期 = 归属日（X-12：凌晨归属前一天），用例与生产同口径。
    final now = AppClock.now();
    final today = StatisticsService.dateString(
      attributionDay(now, matchPeriodByMinutes(now.hour * 60 + now.minute)),
    );

    // 登记"迟到"：默认同步映射 迟到 → 批评原因「迟到」
    final changed = provider.setAttendance(student, '迟到', date: today);
    expect(changed, isTrue);

    final synced = provider
        .getRecordsForDate(today)
        .where((r) => r.remark == AppDataProvider.attendanceSyncMarker)
        .toList();
    expect(synced, hasLength(1), reason: '应同步生成一条批评记录');
    expect(synced.first.studentName, student);
    expect(synced.first.operationType, '批评');
    expect(synced.first.reasons, '迟到');

    // 考勤对话框展示：应到/实到卡片、状态分组、学生芯片、页脚条数
    await tester.pumpWidget(_wrap(provider, const AttendanceDialog()));
    await tester.pumpAndSettle();
    expect(find.text('应到'), findsOneWidget);
    expect(find.text('实到'), findsOneWidget);
    expect(find.widgetWithText(InputChip, student), findsOneWidget);
    expect(find.text('共 1 条异常记录'), findsOneWidget);
    // 应到 = 名单人数；迟到属于"到了"，不减实到（可配置的"计为未到"口径）
    final stats = provider.attendanceStats(today);
    expect(stats.total, provider.appData.students.length);
    expect(stats.presentCount, stats.total, reason: '迟到不减实到');
    expect(find.text('${stats.total}'), findsWidgets);

    // 撤销考勤：点学生芯片上的 ×（同步的批评记录应一并删除）
    await tester.tap(
      find.descendant(
        of: find.byType(InputChip),
        matching: find.byIcon(Icons.close),
      ).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('撤销考勤登记'), findsOneWidget);
    await tester.tap(find.text('确定撤销'));
    await tester.pumpAndSettle();
    await _settleData(tester);

    expect(provider.getRecordsForDate(today), isEmpty, reason: '撤销考勤应回收同步记录');
    expect(find.text('各时间段均无异常记录，全员到齐'), findsOneWidget);

    await _drainSnackBars(tester);
  });

  testWidgets('⑤ 表格导入：先预览再确认，覆盖重复并补充名单，导入记录带"导入"标签', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = providerWithStudents(syntheticStudents(5));
    final student = provider.appData.students.first;
    final today = StatisticsService.todayString(AppClock.now());

    // 先放一条已有记录（用于验证"重复识别"）
    provider.addRecord(student, '表扬', const ['作业优秀'], 'class', '');
    final existing = provider.getRecordsForDates(provider.getHistoryDates());
    final seeded = existing.single;

    // 构造一张与现有记录完全一致的行（日期/姓名/类型/时间/原因/时段/备注都相同）
    // + 一条新记录 + 一名新学生。
    final rows = <List<String>>[
      ['日期', '学生姓名', '操作项目', '原因', '时间段', '时间', '备注'],
      [
        today,
        student,
        '表扬',
        '作业优秀',
        '上课',
        seeded.timestamp,
        '',
      ],
      [today, '新同学甲', '批评', '讲话', '上课', '00:00:00', ''],
    ];
    final preview = ImportService.parseExcelBytes(
      _buildXlsx(rows),
      existing: existing,
    );
    expect(preview.hasError, isFalse);
    expect(preview.records, hasLength(1), reason: '只剩新同学甲那条');
    expect(preview.duplicates, hasLength(1), reason: '与现有记录完全相同的应被识别为重复');
    expect(preview.unknownStudents, ['新同学甲']);

    // 走真实的导入确认对话框（经 showDialog 弹出，与用户点击路径一致）
    await _pumpDialog(
      tester,
      provider,
      ImportRecordsDialog(fileName: '测试导入.xlsx', preview: preview),
    );
    expect(find.textContaining('可导入'), findsOneWidget);
    expect(find.textContaining('与现有记录完全相同'), findsOneWidget);
    await tester.tap(find.textContaining('用表格里的内容覆盖重复记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    await _settleData(tester);

    final todayRecords = provider.getTodayRecords();
    expect(todayRecords, hasLength(2), reason: '覆盖后仍是一条本人 + 一条新同学');
    expect(
      todayRecords.where((r) => r.studentName == '新同学甲').single.isImported,
      isTrue,
    );
    expect(provider.appData.students, contains('新同学甲'));

    // 展示：导入的记录在今日面板上带"导入"标签
    await tester.pumpWidget(_wrap(provider, const HomePage()));
    await tester.pump();
    expect(find.text('新同学甲'), findsWidgets);
    expect(find.text('导入'), findsAtLeastNWidgets(1));

    await _drainSnackBars(tester);
  });

  testWidgets('⑥ 时段无法识别的历史记录：列表展示记录里的原始时段名，不出现悬空分隔符', (tester) async {
    final provider = providerWithStudents(syntheticStudents(5));
    final today = StatisticsService.todayString(AppClock.now());
    // 模拟"从外部表格导入、时间段列没被识别"的记录：periodKey 为空、只有原始时段名。
    provider.importRecords([
      StudentRecord(
        id: 'imported-1',
        studentName: '张三',
        operationType: '表扬',
        reasons: '作业优秀',
        periodKey: '',
        periodName: '上午上课',
        remark: '',
        timestamp: '08:00:00',
        isImported: true,
        date: today,
      ),
    ]);

    await tester.pumpWidget(
      _wrap(provider, RecordList(records: provider.getTodayRecords())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('作业优秀 · 上午上课'), findsOneWidget);
    expect(find.text('作业优秀 · '), findsNothing, reason: '不应出现悬空的分隔符');
  });
}

/// 生成一份 xlsx 字节（供导入测试用）。
List<int> _buildXlsx(List<List<String>> rows) {
  final file = excel.Excel.createExcel();
  final sheet = file['Sheet1'];
  for (final row in rows) {
    sheet.appendRow([for (final cell in row) excel.TextCellValue(cell)]);
  }
  return file.encode()!;
}
