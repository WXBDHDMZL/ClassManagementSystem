// 统计增强测试：需关注学生名单与"上一等长区间"换算。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/statistics_service.dart';

StudentRecord _record(String name, String type, String date) {
  return StudentRecord(
    id: '$name-$type-$date-${DateTime.now().microsecondsSinceEpoch}',
    studentName: name,
    operationType: type,
    reasons: '测试原因',
    periodKey: 'class',
    periodName: '上课',
    remark: '',
    timestamp: '08:00:00',
    isAppended: false,
    date: date,
  );
}

void main() {
  test('需关注学生：批评达到阈值才入选，按次数降序', () {
    final records = [
      _record('张三', '批评', '2026-09-01'),
      _record('张三', '批评', '2026-09-02'),
      _record('张三', '批评', '2026-09-03'),
      _record('李四', '批评', '2026-09-01'),
      _record('李四', '批评', '2026-09-02'),
      _record('王五', '批评', '2026-09-01'),
      _record('王五', '批评', '2026-09-02'),
      _record('王五', '批评', '2026-09-03'),
      _record('王五', '批评', '2026-09-04'),
      // 表扬再多也不进关注名单
      _record('赵六', '表扬', '2026-09-01'),
      _record('赵六', '表扬', '2026-09-02'),
      _record('赵六', '表扬', '2026-09-03'),
    ];

    final attention = StatisticsService.attentionStudents(records);

    expect(attention.length, 2);
    expect(attention.first.name, '王五');
    expect(attention.first.count, 4);
    expect(attention.last.name, '张三');
    expect(attention.last.count, 3);
  });

  test('需关注学生：可自定义阈值，空区间返回空列表', () {
    final records = [
      _record('张三', '批评', '2026-09-01'),
      _record('张三', '批评', '2026-09-02'),
    ];

    expect(StatisticsService.attentionStudents(records, threshold: 2).length, 1);
    expect(StatisticsService.attentionStudents(records, threshold: 5), isEmpty);
    expect(StatisticsService.attentionStudents(const []), isEmpty);
  });

  test('上一等长区间：一周区间对应紧邻的前一周', () {
    final period = StatisticsService.previousPeriod('2026-09-07', '2026-09-13');

    expect(period, isNotNull);
    expect(period!.$1, '2026-08-31');
    expect(period.$2, '2026-09-06');
  });

  test('上一等长区间：跨月与单日区间', () {
    final month = StatisticsService.previousPeriod('2026-09-01', '2026-09-30');
    expect(month!.$1, '2026-08-02');
    expect(month.$2, '2026-08-31');

    final single = StatisticsService.previousPeriod('2026-09-01', '2026-09-01');
    expect(single!.$1, '2026-08-31');
    expect(single.$2, '2026-08-31');
  });

  test('上一等长区间：日期非法或倒序时返回 null', () {
    expect(StatisticsService.previousPeriod('bad', '2026-09-01'), isNull);
    expect(StatisticsService.previousPeriod('2026-09-10', '2026-09-01'), isNull);
  });
}
