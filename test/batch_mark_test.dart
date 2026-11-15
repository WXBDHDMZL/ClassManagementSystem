// 行为测试：批量记录标记（修改3）。
//
// 需求：批量入口产生的记录显示“批量”标签、空备注默认写“批量”；
// 单条事后补录仍保持“追加”；老师手填备注不被覆盖；JSON 往返与旧数据兼容。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

const _date = '2026-10-18';

void main() {
  group('批量记录标记', () {
    test('批量写入的记录 isBatch=true，空备注默认“批量”', () {
      final provider = AppDataProvider();
      provider.mergeStudents(const ['张三', '李四']);

      final added = provider.addRecordsForStudents(
        const ['张三', '李四'],
        '批评',
        const ['迟到'],
        'class',
        '',
        date: _date,
        isBatch: true,
      );

      expect(added, 2);
      final records = provider.getRecordsForDate(_date);
      expect(records, hasLength(2));
      expect(records.every((record) => record.isBatch), isTrue);
      expect(records.every((record) => record.remark == '批量'), isTrue);
      expect(records.every((record) => record.isAppended), isFalse);
    });

    test('单条事后补录仍是“追加”，不是“批量”', () {
      final provider = AppDataProvider();
      provider.mergeStudents(const ['张三']);

      provider.addRecord(
        '张三',
        '批评',
        const ['迟到'],
        'class',
        '',
        isAppended: true,
        date: _date,
      );

      final record = provider.getRecordsForDate(_date).single;
      expect(record.isAppended, isTrue);
      expect(record.isBatch, isFalse);
      expect(record.remark, '追加');
    });

    test('老师手填备注不被“批量”覆盖', () {
      final provider = AppDataProvider();
      provider.mergeStudents(const ['张三', '李四']);

      provider.addRecordsForStudents(
        const ['张三', '李四'],
        '表扬',
        const ['认真'],
        'class',
        '小组合作',
        date: _date,
        isBatch: true,
      );

      final records = provider.getRecordsForDate(_date);
      expect(records.every((record) => record.isBatch), isTrue);
      expect(records.every((record) => record.remark == '小组合作'), isTrue);
    });

    test('JSON 往返保留 isBatch；缺字段的旧数据默认 false', () {
      final record = StudentRecord(
        id: 'r1',
        studentName: '张三',
        operationType: '批评',
        reasons: '迟到',
        periodKey: 'class',
        periodName: '上课',
        remark: '批量',
        timestamp: '08:00:00',
        date: _date,
        isBatch: true,
      );

      final restored = StudentRecord.fromJson(record.toJson());
      expect(restored.isBatch, isTrue);
      expect(restored, record);

      final legacy = StudentRecord.fromJson(const {
        'id': 'r2',
        'studentName': '李四',
        'operationType': '表扬',
        'reasons': '认真',
        'periodKey': 'class',
        'periodName': '上课',
        'remark': '',
        'timestamp': '08:00:00',
        'date': _date,
      });
      expect(legacy.isBatch, isFalse);
    });
  });
}
