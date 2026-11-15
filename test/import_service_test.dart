// 记录表格导入解析测试（走 CSV 解析链路）：表头识别、缺日期列按今天导入、
// 判重（含时段/备注）、文件内部去重、非法日期拒绝。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/import_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/utils/app_clock.dart';

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

  test('缺少"日期"列（老版今日记录导出）：按今天导入', () {
    final preview = _parse(
      '学生姓名,操作项目,原因,时间段,时间,备注\n'
      '李四,批评,迟到,早读,07:30:00,\n',
    );

    expect(preview.hasError, isFalse);
    expect(
      preview.records.single.date,
      StatisticsService.todayString(AppClock.now()),
    );
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
}
