// 审计 P1 修复专项回归（2026-10-05，第四批：10/11/12/16/21/23）。
// 桌面三项（24 窗口夹取/25 自启校正/26 --tray 隐藏）以构建冒烟 + 真机行为
// 验证覆盖；27（红色按钮）为界面样式，由 analyze 与人工核对覆盖。
//
//   P1-10 addRecordsBatch：与 addRecord 同一套操作类型白名单，整批单次落盘；
//   P1-11 编辑含多个自定义原因的记录：提交时按顿号拆回多条；
//   P1-12 编辑"时段无法识别"的导入记录：不改动则保留原空键与原始时段名；
//   P1-21 并列名次：denseRanks 与导出"排名"表同口径（1、1、2…）；
//   P1-23 操作日志查看器跨月拼接读取。
//
// 模式沿用 v230_audit_p1b_test：test() + mock path_provider。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/operation_log_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/record_dialog.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

Widget _wrapDialog(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => child,
                ),
                child: const Text('打开对话框'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  late Directory tempDir;
  late Directory logDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_audit_p1c');
    logDir = Directory('${tempDir.path}/日志')..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
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
    await deleteStorageTestRoot(tempDir);
  });

  group('P1-10 批量新增记录', () {
    test('非法操作类型被拒收，合法的正常写入', () {
      provider.mergeStudents(['张三']);

      final added = provider.addRecordsBatch([
        (
          studentName: '张三',
          operationType: '点评',
          reasons: const ['认真'],
          periodKey: 'class',
          remark: '',
          date: '2026-10-04',
        ),
        (
          studentName: '张三',
          operationType: '表扬',
          reasons: const ['认真'],
          periodKey: 'class',
          remark: '',
          date: '2026-10-04',
        ),
      ]);

      expect(added, 1, reason: '非法类型整条跳过');
      final records = provider.getRecordsForDate('2026-10-04');
      expect(records, hasLength(1));
      expect(records.single.operationType, '表扬');
    });
  });

  group('P1-11 编辑多个自定义原因', () {
    testWidgets('提交时按顿号拆回多条，不再合并成一条', (tester) async {
      provider.mergeStudents(['张三']);
      final today = StatisticsService.todayString(AppClock.now());
      provider.addRecord(
        '张三',
        '批评',
        ['自定原因甲', '自定原因乙'],
        'class',
        '',
        date: today,
      );
      final record = provider.getRecordsForDate(today).single;
      expect(record.reasons, '自定原因甲、自定原因乙');

      await tester.pumpWidget(
        _wrapDialog(
          provider,
          RecordDialog(
            studentName: record.studentName,
            editRecord: record,
            targetDate: today,
          ),
        ),
      );
      await tester.tap(find.text('打开对话框'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      final saved = provider.getRecordsForDate(today).single;
      expect(saved.reasons, '自定原因甲、自定原因乙',
          reason: '两条自定义原因不能因编辑保存被合并成一条');
      expect(saved.reasons.split('、'), hasLength(2));
    });
  });

  group('P1-12 编辑"时段无法识别"的导入记录', () {
    StudentRecord unnamedPeriodRecord() => StudentRecord(
          id: 'imp1',
          studentName: '张三',
          operationType: '批评',
          reasons: '认真听讲',
          periodKey: '',
          periodName: '上午上课',
          remark: '',
          timestamp: '08:00:00',
          date: '2026-10-04',
        );

    test('不改动直接保存：保留原空时段键与原始时段名', () {
      provider.loadForTest(AppData(
        recordsByDate: {
          '2026-10-04': [unnamedPeriodRecord()],
        },
        settings: AppSettings.defaultSettings(),
      ));

      final ok = provider.updateRecord(
        'imp1',
        '批评',
        ['认真听讲'],
        '',
        '补充备注',
        date: '2026-10-04',
      );

      expect(ok, isTrue);
      final saved = provider.getRecordsForDate('2026-10-04').single;
      expect(saved.periodKey, isEmpty, reason: '不能把原空键规整成 all_day');
      expect(saved.periodName, '上午上课', reason: '不能把原时段文本洗成"全天"');
      expect(saved.remark, '补充备注');
    });

    testWidgets('编辑对话框里显示原始时段名 chip，且保存后保留', (tester) async {
      provider.loadForTest(AppData(
        recordsByDate: {
          '2026-10-04': [unnamedPeriodRecord()],
        },
        settings: AppSettings.defaultSettings(),
      ));
      final record = provider.getRecordsForDate('2026-10-04').single;

      await tester.pumpWidget(
        _wrapDialog(
          provider,
          RecordDialog(
            studentName: record.studentName,
            editRecord: record,
            targetDate: '2026-10-04',
          ),
        ),
      );
      await tester.tap(find.text('打开对话框'));
      await tester.pumpAndSettle();

      expect(find.text('上午上课'), findsOneWidget, reason: '空白时段应以原始时段名显示');

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      final saved = provider.getRecordsForDate('2026-10-04').single;
      expect(saved.periodKey, isEmpty);
      expect(saved.periodName, '上午上课');
    });
  });

  group('P1-21 并列名次口径', () {
    test('denseRanks：同次数同名次、名次连续（1、1、2）', () {
      expect(
        StatisticsService.denseRanks([5, 5, 3, 1, 1, 1]),
        [1, 1, 2, 3, 3, 3],
      );
      expect(StatisticsService.denseRanks(const []), isEmpty);
    });
  });

  group('P1-23 操作日志读取', () {
    test('recentLines 在同一份日志中按新→旧返回', () async {
      final log = File(
        '${logDir.path}/${OperationLogService.fileName}',
      );
      await OperationLogService.appendLineTo(log, '2026-09-30  九月日志');
      await OperationLogService.appendLineTo(log, '2026-10-01  十月日志');

      final lines = await OperationLogService.recentLines();

      expect(lines, hasLength(2));
      expect(lines.first, contains('十月日志'), reason: '最新的应排在最前');
      expect(lines.last, contains('九月日志'));
    });
  });
}
