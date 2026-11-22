// 导入与恢复一致性专项回归（V2.30.23，第 4 轮：X-6 / X-14 / X-15 / X-17）。
//
//   X-6  表格导入：文件内同一条重复行出现两次时，"覆盖写回"只写一条（否则库内多一条）；
//   X-14 从备份恢复后必须失效派生缓存（计数/指纹），否则界面显示恢复前的旧值；
//   X-15 判重键必须与表格导入同口径（含"时段""备注"），仅这两项不同不算重复；
//   X-17 分类导入多工作表时按表头关键词挑表（封面/说明表在前也能读对）。
//
// 模式沿用 v230_parse_robustness_test：test() + mock path_provider。

import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/excel_export.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/storage_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

StudentRecord rec({
  String id = 'r1',
  String name = '张三',
  String reasons = '迟到',
  String periodKey = '',
  String remark = '',
  String timestamp = '08:00:00',
  String date = '2026-10-04',
}) =>
    StudentRecord(
      id: id,
      studentName: name,
      operationType: '批评',
      reasons: reasons,
      periodKey: periodKey,
      periodName: '',
      remark: remark,
      timestamp: timestamp,
      date: date,
    );

void main() {
  late Directory tempDir;
  AppDataProvider? provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_import_consistency');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
    provider = null;
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

  group('X-6 表格导入：重复行只写回一条', () {
    test('文件内同一重复行出现两次 → duplicates 与 duplicateImports 各 1 条', () {
      const csv = '日期,学生姓名,操作项目,原因\n'
          '2026-10-04,张三,批评,迟到\n'
          '2026-10-04,张三,批评,迟到\n';
      final preview = ImportService.parseCsvText(
        csv,
        existing: [rec(timestamp: '08:00:00')],
      );
      expect(preview.records, isEmpty, reason: '两行都与现有记录重复');
      expect(preview.duplicates, hasLength(1));
      expect(preview.duplicateImports, hasLength(1),
          reason: '同一条现有记录只能对应一条"覆盖写回"，否则覆盖后库内多一条');
    });

    test('两条不同的现有记录各自重复 → 各写回一条（不会被误合并）', () {
      const csv = '日期,学生姓名,操作项目,原因\n'
          '2026-10-04,张三,批评,迟到\n'
          '2026-10-04,李四,批评,迟到\n';
      final preview = ImportService.parseCsvText(
        csv,
        existing: [rec(id: 'e1'), rec(id: 'e2', name: '李四')],
      );
      expect(preview.duplicates, hasLength(2));
      expect(preview.duplicateImports, hasLength(2));
    });
  });

  group('X-14 从备份恢复后失效派生缓存', () {
    test('恢复后 totalRecordCount 反映新数据（不是恢复前的旧值）', () async {
      final p = provider = AppDataProvider();
      p.loadForTest(AppData(
        recordsByDate: {
          '2026-10-01': [rec(id: 'old1', date: '2026-10-01')],
        },
        settings: AppSettings.defaultSettings(),
      ));
      // 先读一次，把计数缓存填上（模拟界面已显示过总条数）。
      expect(p.totalRecordCount, 1);

      final backup = AppData(
        recordsByDate: {
          '2026-10-02': [
            rec(id: 'b1', date: '2026-10-02'),
            rec(id: 'b2', date: '2026-10-02'),
            rec(id: 'b3', date: '2026-10-02'),
          ],
        },
        settings: AppSettings.defaultSettings(),
      );
      final path = '${tempDir.path}/备份.enc';
      await File(path).writeAsString(
        await StorageService().encodeForTest(backup),
      );

      final error = await p.restoreBackupFrom(path);
      expect(error, isNull);
      expect(p.totalRecordCount, 3,
          reason: '恢复后必须失效计数缓存，否则界面仍显示恢复前的 1 条');
    });
  });

  group('X-15 判重键与表格导入同口径', () {
    test('仅"时段"或"备注"不同 → 身份串不同（不再是重复）', () {
      final base = rec(periodKey: 'class', remark: '');
      expect(
        ImportService.recordIdentityKey(base),
        isNot(ImportService.recordIdentityKey(rec(periodKey: 'meal'))),
      );
      expect(
        ImportService.recordIdentityKey(base),
        isNot(ImportService.recordIdentityKey(rec(periodKey: 'class', remark: '备注'))),
      );
      // 完全相同的记录身份串一致。
      expect(
        ImportService.recordIdentityKey(base),
        ImportService.recordIdentityKey(rec(periodKey: 'class')),
      );
    });

    test('表格导入：仅"时段"不同的行不算重复（与身份串口径一致）', () {
      const csv = '日期,学生姓名,操作项目,原因,时间段\n'
          '2026-10-04,张三,批评,迟到,就餐\n';
      final preview = ImportService.parseCsvText(
        csv,
        existing: [rec(periodKey: 'class')],
      );
      expect(preview.duplicates, isEmpty);
      expect(preview.records, hasLength(1));
    });
  });

  group('X-17 分类导入多工作表按表头挑表', () {
    test('封面/说明表在前时，仍能选中含表头的数据表', () {
      final book = ExcelExport.newWorkbook();
      book.rename('Sheet1', '封面');
      book['封面'].appendRow([excel.TextCellValue('班级名单导入说明')]);
      final data = book['名单'];
      data.appendRow([excel.TextCellValue('姓名')]);
      data.appendRow([excel.TextCellValue('张三')]);
      final bytes = ExcelExport.encodeWorkbook(book);

      final rows = TransferService.readRows(
        bytes,
        isCsv: false,
        headerKeywords: const {'姓名', '学生姓名'},
      );
      expect(rows.first.first, '姓名', reason: '应选中"名单"表而不是"封面"表');
      expect(TransferService.parseStudentsRows(rows), ['张三']);
    });

    test('无表头的单表文件：退回非空表，解析仍可用（保持旧行为）', () {
      final book = ExcelExport.newWorkbook();
      book['Sheet1'].appendRow([excel.TextCellValue('张三')]);
      book['Sheet1'].appendRow([excel.TextCellValue('李四')]);
      final bytes = ExcelExport.encodeWorkbook(book);

      final rows = TransferService.readRows(
        bytes,
        isCsv: false,
        headerKeywords: const {'姓名', '学生姓名'},
      );
      expect(TransferService.parseStudentsRows(rows), ['张三', '李四']);
    });
  });
}
