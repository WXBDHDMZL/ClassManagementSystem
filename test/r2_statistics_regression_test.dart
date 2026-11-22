// R2 统计口径回归：停用类型不计入汇总、超长区间取最近 3660 天。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/utils/app_date.dart';

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
  test('停用批评后，记录天数与涉及学生数不再计入批评记录', () {
    final records = [
      _record('张三', '表扬', '2026-09-01'),
      _record('李四', '批评', '2026-09-02'),
      _record('王五', '批评', '2026-09-03'),
    ];
    final result = StatisticsService.compute(records, includeCriticize: false);
    expect(result.summary.praiseCount, 1);
    expect(result.summary.criticizeCount, 0);
    expect(result.summary.recordDays, 1);
    expect(result.summary.studentCount, 1);
  });

  test('超长区间 datesBetween 取结束日往前 3660 天，不丢近年数据', () {
    final dates = StatisticsService.datesBetween('1900-01-01', '2026-09-01');
    expect(dates.length, kMaxDateRangeDays);
    expect(dates.last, '2026-09-01');
    expect(dates.first, '2016-08-25');
  });

  test('rangeDates 外日期的记录不进入统计', () {
    final records = [
      _record('张三', '表扬', '2020-01-01'),
      _record('李四', '表扬', '2026-09-01'),
    ];
    final result = StatisticsService.compute(
      records,
      rangeDates: const ['2026-09-01'],
    );
    expect(result.summary.praiseCount, 1);
    expect(result.summary.recordDays, 1);
    expect(result.summary.studentCount, 1);
  });
}
