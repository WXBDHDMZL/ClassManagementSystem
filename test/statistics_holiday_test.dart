// 行为测试：统计不排除任何日期（含放假日期，BACKLOG B-03 / D-014）。
//
// 用户拍板：放假日期产生的表扬/批评记录**计入总数**；因此记录天数、
// 趋势与每日统计也必须包含这些日期，避免同一份报表内部数字对不上。
// 统计接口不再接收 holidays 参数；考勤统计的“跳过放假日期”是独立口径。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/statistics_service.dart';

void main() {
  StudentRecord rec({required String date, String type = '表扬'}) {
    return StudentRecord(
      id: 'r-$date-$type',
      studentName: '张三',
      operationType: type,
      reasons: '认真',
      periodKey: 'class',
      periodName: '上课',
      remark: '',
      timestamp: '08:00:00',
      date: date,
    );
  }

  group('B-03 日期记录口径（D-014）', () {
    test('任何日期的记录都计入总数与记录天数', () {
      final result = StatisticsService.compute(
        [rec(date: '2026-10-01')],
      );

      expect(result.summary.praiseCount, 1);
      expect(result.summary.recordDays, 1,
          reason: '记录已计入总数，记录天数就不能把它排除，否则同一次统计自相矛盾');
      expect(result.dailyCounts, hasLength(1));
      expect(result.dailyCounts.single.date, '2026-10-01');
    });

    test('rangeDates 给出完整区间时，趋势逐日保留并补 0', () {
      final result = StatisticsService.compute(
        [rec(date: '2026-10-02', type: '批评')],
        rangeDates: const ['2026-10-01', '2026-10-02', '2026-10-03'],
      );

      expect(
        result.dailyCounts.map((item) => item.date).toList(),
        ['2026-10-01', '2026-10-02', '2026-10-03'],
        reason: '有记录的日期必须留在趋势里；空档仍补 0',
      );
      final criticizePoint =
          result.dailyCounts.firstWhere((item) => item.date == '2026-10-02');
      expect(criticizePoint.criticizeCount, 1);
      expect(criticizePoint.praiseCount, 0);
      expect(
        result.dailyCounts.firstWhere((item) => item.date == '2026-10-01').praiseCount,
        0,
      );
    });

    test('普通日期行为不变', () {
      final result = StatisticsService.compute(
        [rec(date: '2026-10-03')],
      );

      expect(result.summary.recordDays, 1);
      expect(result.dailyCounts.single.date, '2026-10-03');
    });
  });
}
