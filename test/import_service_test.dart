// 记录表格导入解析测试（走 CSV 解析链路）：表头识别、缺日期列按今天导入、
// 判重（含时段/备注）、文件内部去重、非法日期拒绝。

import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/import_service.dart';

StudentRecord _existing({
  String id = 'r1',
  String name = '张三',
  String type = '表扬',
  String reason = '认真听讲',
  String periodKey = 'class',
  String timestamp = '12:00:00',
  String remark = '',
  String date = '2026-09-20',
}) => StudentRecord(
  id: id,
  studentName: name,
  operationType: type,
  reasons: reason,
  periodKey: periodKey,
  periodName: '',
  remark: remark,
  timestamp: timestamp,
  isAppended: false,
  date: date,
);

/// 用 CSV 文本走真实的解析链路。
ImportPreview _parse(String csv, {List<StudentRecord> existing = const []}) =>
    ImportService.parseCsvText(csv, existing: existing);

void main() {
  test('判重降级：时间列存在但整列为空时，仍能识别重复', () {
    // 场景：用户在 Excel 里清空了"时间"列的值（列还在），反复导入不应产生重复。
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
      '2026-09-20,张三,表扬,认真听讲,上课,,\n',
      existing: [_existing(periodKey: 'class')],
    );
    expect(preview.records, isEmpty, reason: '与现有记录重复，不应新增');
    expect(preview.duplicates, hasLength(1), reason: '空时间值也要能判重');
  });

  test('判重计数：同一重复行出现两次时只记一条', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
      '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,\n'
      '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,\n',
      existing: [_existing(periodKey: 'class')],
    );
    expect(preview.duplicates, hasLength(1), reason: '重复计数不应虚高');
  });

  test('标准表头解析：姓名/操作项目/原因/时间段/时间/备注', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
      '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,\n',
    );

    expect(preview.hasError, isFalse);
    expect(preview.records.length, 1);
    final record = preview.records.single;
    expect(record.studentName, '张三');
    expect(record.operationType, '表扬');
    expect(record.reasons, '认真听讲');
    expect(record.date, '2026-09-20');
    expect(record.periodKey, 'class');
    expect(record.isImported, isTrue, reason: '导入的记录应标为"导入"');
    expect(record.isAppended, isFalse);
  });

  test('导入识别记录人列：有值保留，空值保持未记录', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注,记录人\n'
      '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,,班长 · 王五\n'
      '2026-09-20,李四,批评,迟到,上课,12:00:00,,\n',
    );

    expect(preview.records, hasLength(2));
    expect(preview.records[0].recordedBy, '班长 · 王五');
    expect(preview.records[1].recordedBy, isEmpty);
  });

  test('“未记录”是导出占位，回导时按空记录人处理', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注,记录人\n'
      '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,,未记录\n',
    );

    expect(preview.records.single.recordedBy, isEmpty);
  });

  test('缺少"日期"列：直接报错，不再按今天导入', () {
    final preview = _parse(
      '学生姓名,操作项目,原因,时间段,时间,备注\n'
      '李四,批评,迟到,早读,07:30:00,\n',
    );

    expect(preview.hasError, isTrue);
    expect(preview.error, contains('日期'));
    expect(preview.records, isEmpty);
  });

  test('P2-10：表格缺"时间"列时，与现有记录相同的行仍判为重复', () {
    // 缺陷复现：导出时取消勾选"时间"列 → 同一份文件反复导入会不断产生重复记录。
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,备注\n'
      '2026-09-20,张三,表扬,认真听讲,上课,\n',
      existing: [_existing(periodKey: 'class')],
    );
    expect(preview.records, isEmpty, reason: '与现有记录重复，不应新增');
    expect(preview.duplicates, hasLength(1), reason: '缺时间列也必须能识别出重复');
  });

  test('P2-10：缺"时间"列时，只有时段不同的行不算重复', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,备注\n'
      '2026-09-20,张三,表扬,认真听讲,早读,\n',
      existing: [_existing(periodKey: 'class')],
    );
    expect(preview.records, hasLength(1), reason: '时段不同应作为新记录导入');
    expect(preview.duplicates, isEmpty);
  });

  test('判重包含时间段：只有时段不同不算重复，完全一致才算', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
      '2026-09-20,张三,表扬,认真听讲,早读,12:00:00,\n'
      '2026-09-20,张三,表扬,认真听讲,上课,12:00:00,\n',
      existing: [_existing(periodKey: 'class')],
    );

    expect(preview.records.length, 1);
    expect(preview.records.single.periodKey, 'morning_reading');
    expect(preview.duplicates.length, 1);
    expect(preview.duplicates.single.id, 'r1');
    // 覆盖导入时要把表格里的这一行写回去（否则只删不写会丢数据）
    expect(preview.duplicateImports.length, 1);
    expect(preview.duplicateImports.single.periodKey, 'class');
  });

  test('同一文件内部完全重复的行只导入一条', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
      '2026-09-20,王五,批评,讲话,上课,10:00:00,\n'
      '2026-09-20,王五,批评,讲话,上课,10:00:00,\n',
    );

    expect(preview.records.length, 1);
  });

  test('非法日期（2026-02-31）跳过，非法类型跳过', () {
    final preview = _parse(
      '日期,学生姓名,操作项目,原因\n'
      '2026-02-31,张三,表扬,认真听讲\n'
      '2026-02-28,张三,进步,认真听讲\n'
      '2026-02-28,张三,表扬,认真听讲\n',
    );

    expect(preview.records.length, 1);
    expect(preview.records.single.date, '2026-02-28');
    expect(preview.skippedRows, 2);
  });

  test('找不到表头时给出错误提示（而不是静默导入）', () {
    final preview = _parse('随便,两列\n2026-09-20,张三\n');
    expect(preview.hasError, isTrue);
  });

  test('空文件：报错提示，不产生任何记录', () {
    final preview = _parse('');
    expect(preview.hasError, isTrue);
    expect(preview.records, isEmpty);
  });

  test('内容全是空行/空白的文件：报错提示，不产生任何记录', () {
    final preview = _parse('\n\n   \n\t\n');
    expect(preview.hasError, isTrue);
    expect(preview.records, isEmpty);
  });

  test('乱码内容（非表格文本）：报错提示而不是崩溃或导入脏数据', () {
    final preview = _parse('\u0000ÿþ\x00\x01\x02 ½¾¿ random garbage ¯\\_(ツ)_/¯');
    expect(preview.hasError, isTrue);
    expect(preview.records, isEmpty);
  });

  // ── 审计 A-04 / A-21 ───────────────────────────────────────────────
  group('A-04 记录导入与名单导入同口径（超长姓名不再截断）', () {
    test('31 个字的学生姓名：整行跳过，不再静默截断成 30 字入库', () {
      // 旧行为：clipName 截断到 30 字后照样入库，前 30 字相同的两个人会
      // 被合并成同一学生（名单导入却是直接拒绝）。
      final longName = '张' * 31;
      final preview = _parse(
        '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
        '2026-10-05,$longName,表扬,认真听讲,上课,08:00:00,\n',
      );

      expect(preview.hasError, isFalse);
      expect(preview.records, isEmpty, reason: '超长姓名应整行拒绝');
      expect(preview.skippedRows, 1);
    });

    test('正好 30 个字：仍然允许导入（与名单导入的上限一致）', () {
      final name = '李' * 30;
      final preview = _parse(
        '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
        '2026-10-05,$name,表扬,认真听讲,上课,08:00:00,\n',
      );

      expect(preview.hasError, isFalse);
      expect(preview.records, hasLength(1));
      expect(preview.records.single.studentName.length, 30);
      expect(preview.skippedRows, 0);
    });
  });

  group('A-21 表格取值语义', () {
    test('时间写成 25:99：整行跳过，不再静默归零成 00:00:00', () {
      final preview = _parse(
        '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
        '2026-10-05,张三,表扬,认真听讲,上课,25:99,\n',
      );

      expect(preview.hasError, isFalse);
      expect(preview.records, isEmpty);
      expect(preview.skippedRows, 1);
    });

    test('时间写成无法解析的文本：整行跳过', () {
      final preview = _parse(
        '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
        '2026-10-05,张三,表扬,认真听讲,上课,八点半,\n',
      );

      expect(preview.records, isEmpty);
      expect(preview.skippedRows, 1);
    });

    test('时间列留空：仍按“没写时间”导入为 00:00:00', () {
      final preview = _parse(
        '日期,学生姓名,操作项目,原因,时间段,时间,备注\n'
        '2026-10-05,张三,表扬,认真听讲,上课,,\n',
      );

      expect(preview.records, hasLength(1));
      expect(preview.records.single.timestamp, '00:00:00');
    });

    test('学生姓名列是公式：不把公式原文当姓名，整行跳过', () {
      final book = excel.Excel.createExcel();
      final sheet = book['Sheet1'];
      sheet.appendRow([
        excel.TextCellValue('日期'),
        excel.TextCellValue('学生姓名'),
        excel.TextCellValue('操作项目'),
        excel.TextCellValue('原因'),
      ]);
      sheet.appendRow([
        excel.TextCellValue('2026-10-05'),
        const excel.FormulaCellValue('CONCAT("张","三")'),
        excel.TextCellValue('表扬'),
        excel.TextCellValue('认真听讲'),
      ]);

      final preview = ImportService.parseExcelBytes(
        book.encode()!,
        existing: const [],
      );

      expect(preview.hasError, isFalse);
      expect(preview.records, isEmpty, reason: '公式原文不得成为姓名');
      expect(preview.skippedRows, 1);
    });

    test('原因列是公式：公式原文不落库，记录按空原因导入', () {
      final book = excel.Excel.createExcel();
      final sheet = book['Sheet1'];
      sheet.appendRow([
        excel.TextCellValue('日期'),
        excel.TextCellValue('学生姓名'),
        excel.TextCellValue('操作项目'),
        excel.TextCellValue('原因'),
      ]);
      sheet.appendRow([
        excel.TextCellValue('2026-10-05'),
        excel.TextCellValue('张三'),
        excel.TextCellValue('表扬'),
        const excel.FormulaCellValue('SUM(A1:A2)'),
      ]);

      final preview = ImportService.parseExcelBytes(
        book.encode()!,
        existing: const [],
      );

      expect(preview.hasError, isFalse);
      expect(preview.records, hasLength(1));
      expect(preview.records.single.reasons, isEmpty);
      expect(preview.records.single.reasons.contains('SUM'), isFalse);
    });
  });
}
