// 审计 P2 修复专项回归（2026-10-05，第一批：28/29/30/39/40/42/43/44/46/48）。
//
//   P2-28 时段解析：_parsePeriodList 与 sanitizePeriods 同口径（标签校验 + key 去重）；
//   P2-29 考勤加载：同学生同时段的重复行按唯一键去重（first-wins）；
//   P2-30 记录 id 生成后循环查重（现有用例回归覆盖，不构造撞号场景）；
//   P2-39 备份恢复 .bak 改原子复写（AtomicFile 已有专项用例，不重复）；
//   P2-40 自动导出文件名走统一消毒；
//   P2-42 原因库导入按**列数**判布局（三列原因为空→跳过而不是误当两列）；
//   P2-43 Excel 时间型单元格保留时分秒、日期格取日期段；
//   P2-44 记录表头重名列 first-wins；
//   P2-46 报表考勤判定与写表口径统一（skipHolidays，界面层由人工核对）。
//
// 模式沿用 v230_audit_p1c_test：test() + mock path_provider。

import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_audit_p2');
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

  group('P2-28 时段解析与净化同口径', () {
    test('fromJson：非法标签与重复 key 被过滤（first-wins）', () {
      final settings = AppSettings.fromJson({
        'periods': [
          {'key': 'p1', 'label': '08:00-09:40 第一节'},
          {'key': 'p1', 'label': '10:00-11:40 第二节'},
          {'key': 'bad', 'label': '没有时间段的标签'},
          {'key': '', 'label': '08:00-09:40 空键'},
        ],
      });

      expect(settings.periods, hasLength(1));
      expect(settings.periods.single['key'], 'p1');
      expect(settings.periods.single['label'], '08:00-09:40 第一节');
    });

    test('sanitizePeriods：重复 key first-wins、非法标签被剔', () {
      final cleaned = sanitizePeriods(const [
        {'key': 'a', 'label': '08:00-09:00 一'},
        {'key': 'a', 'label': '09:00-10:00 二'},
        {'key': 'b', 'label': '乱写'},
      ]);

      expect(cleaned, hasLength(1));
      expect(cleaned.single['label'], '08:00-09:00 一');
    });
  });

  group('P2-29 考勤加载去重', () {
    test('同学生同时段的重复行 first-wins，只保留第一条', () {
      final data = AppData.fromJson({
        'recordsByDate': <String, dynamic>{},
        'settings': <String, dynamic>{},
        'attendanceByDate': {
          '2026-10-04': [
            {
              'id': 'a1',
              'studentName': '张三',
              'status': '迟到',
              'date': '2026-10-04',
              'periodKey': 'all_day',
              'timestamp': '08:00:00',
            },
            {
              'id': 'a2',
              'studentName': '张三',
              'status': '请假',
              'date': '2026-10-04',
              'periodKey': 'all_day',
              'timestamp': '09:00:00',
            },
          ],
        },
      });

      final list = data.attendanceByDate['2026-10-04']!;
      expect(list, hasLength(1));
      expect(list.single.id, 'a1', reason: '重复行应 first-wins');
      expect(list.single.status, '迟到');
    });
  });

  group('P2-42 原因库导入布局判定', () {
    test('三列但原因为空：按无法识别跳过而不是把时段名当原因', () {
      var skipped = 0;
      final rows = TransferService.parseReasonsRows(
        const [
          ['类型', '时段', '原因'],
          ['批评', '上课', ''],
          ['批评', '上课', '迟到'],
        ],
        onSkipped: (count) => skipped = count,
      );

      expect(rows, hasLength(1));
      expect(rows.single.reason, '迟到');
      expect(skipped, 1);
    });

    test('两列布局（类型/原因）仍按全时段通用导入', () {
      final rows = TransferService.parseReasonsRows(const [
        ['批评', '认真听讲'],
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.periodKey, '_common');
      expect(rows.single.reason, '认真听讲');
    });
  });

  group('P2-43 Excel 时间型单元格', () {
    test('记录导入：时间格保留时分秒、日期格仍取日期', () {
      final book = excel.Excel.createExcel();
      final sheet = book['Sheet1'];
      sheet.appendRow([
        excel.TextCellValue('学生姓名'),
        excel.TextCellValue('操作项目'),
        excel.TextCellValue('日期'),
        excel.TextCellValue('时间'),
      ]);
      sheet.appendRow([
        excel.TextCellValue('张三'),
        excel.TextCellValue('批评'),
        const excel.DateCellValue(year: 2026, month: 10, day: 4),
        const excel.DateTimeCellValue(
          year: 1899,
          month: 12,
          day: 31,
          hour: 8,
          minute: 30,
        ),
      ]);
      final bytes = book.encode()!;

      final preview = ImportService.parseExcelBytes(bytes, existing: const []);

      expect(preview.hasError, isFalse);
      expect(preview.records, hasLength(1));
      expect(preview.records.single.date, '2026-10-04');
      expect(preview.records.single.timestamp, '08:30:00',
          reason: '时间型单元格此前被静默归零');
    });
  });

  group('P2-44 表头重名列 first-wins', () {
    test('同时含"类型"和"操作项目"两列时取第一列', () {
      final book = excel.Excel.createExcel();
      final sheet = book['Sheet1'];
      sheet.appendRow([
        excel.TextCellValue('学生姓名'),
        excel.TextCellValue('类型'),
        excel.TextCellValue('操作项目'),
      ]);
      sheet.appendRow([
        excel.TextCellValue('张三'),
        excel.TextCellValue('批评'),
        excel.TextCellValue('表扬'),
      ]);
      final bytes = book.encode()!;

      final preview = ImportService.parseExcelBytes(bytes, existing: const []);

      expect(preview.records, hasLength(1));
      expect(preview.records.single.operationType, '批评',
          reason: 'first-wins：应取第一个类型列');
    });
  });

}
