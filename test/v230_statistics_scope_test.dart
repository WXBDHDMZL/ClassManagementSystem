// 统计与时间口径专项回归（V2.30.25，第 6 轮：X-9 / X-10 / X-11 / X-12 / X-19）。
//
//   X-12 跨零点时段（就寝 22:00-06:20）的"归属日"：凌晨部分回退到前一天；
//   X-10 operationType 分流统一：只有明确"表扬"/"批评"计数，"其它"不计入任何一类；
//   X-11 趋势（dailyCounts）与"记录天数"同口径，一并排除放假日期；
//   X-9 / X-19 为界面接线（跳放假、全部记录起点含纯考勤日期），无直接断言。
//
// 模式沿用 v230_parse_robustness_test：test() + mock path_provider。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/statistics_service.dart';

StudentRecord rec({
  String id = 'r1',
  String name = '张三',
  String type = '批评',
  String periodKey = 'sleep',
  String timestamp = '02:00:00',
  String date = '2026-10-05',
  String reasons = '迟到',
  bool appended = false,
  bool imported = false,
}) =>
    StudentRecord(
      id: id,
      studentName: name,
      operationType: type,
      reasons: reasons,
      periodKey: periodKey,
      periodName: '就寝',
      remark: '',
      timestamp: timestamp,
      isAppended: appended,
      isImported: imported,
      date: date,
    );

void main() {
  group('X-12 归属日计算', () {
    test('就寝：凌晨归属前一天，夜间归属当天', () {
      expect(attributionDay(DateTime(2026, 10, 5, 0, 30), 'sleep'),
          DateTime(2026, 10, 4));
      expect(attributionDay(DateTime(2026, 10, 5, 2, 0), 'sleep'),
          DateTime(2026, 10, 4));
      expect(attributionDay(DateTime(2026, 10, 5, 23, 0), 'sleep'),
          DateTime(2026, 10, 5));
    });

    test('边界 06:19 属前一天、06:20 属当天', () {
      expect(attributionDay(DateTime(2026, 10, 5, 6, 19), 'sleep'),
          DateTime(2026, 10, 4));
      expect(attributionDay(DateTime(2026, 10, 5, 6, 20), 'sleep'),
          DateTime(2026, 10, 5));
    });

    test('非跨零点时段 / 空时段：归属当天', () {
      expect(attributionDay(DateTime(2026, 10, 5, 2, 0), 'class'),
          DateTime(2026, 10, 5));
      expect(attributionDay(DateTime(2026, 10, 5, 2, 0), null),
          DateTime(2026, 10, 5));
      expect(attributionDay(DateTime(2026, 10, 5, 2, 0), ''),
          DateTime(2026, 10, 5));
    });

    test('minutesOfTimeText 解析与容错', () {
      expect(minutesOfTimeText('02:00:00'), 120);
      expect(minutesOfTimeText('23:59'), 1439);
      expect(minutesOfTimeText('bad'), isNull);
      expect(minutesOfTimeText(''), isNull);
    });
  });

  group('X-10 operationType 分流统一', () {
    test('isPraiseType：只有明确两类返回非空', () {
      expect(StatisticsService.isPraiseType('表扬'), isTrue);
      expect(StatisticsService.isPraiseType('批评'), isFalse);
      expect(StatisticsService.isPraiseType('其它'), isNull);
      expect(StatisticsService.isPraiseType(''), isNull);
    });

    test('compute：未知类型不计入任何一类（此前被算作批评）', () {
      final result = StatisticsService.compute([
        rec(id: 'x', type: '未知类型', periodKey: 'class', timestamp: '08:00:00'),
      ]);
      expect(result.summary.praiseCount, 0);
      expect(result.summary.criticizeCount, 0);
    });

    test('studentDetail：未知类型同样不计入（与 compute 同口径）', () {
      final stats = StatisticsService.studentDetail(
        [rec(id: 'x', type: '未知类型', periodKey: 'class', timestamp: '08:00:00')],
        '张三',
      );
      expect(stats.praiseCount, 0);
      expect(stats.criticizeCount, 0);
    });
  });

  group('X-11 趋势与记录天数同口径', () {
    test('放假日期产生的记录计入记录天数与趋势（D-014）', () {
      final record = rec(
        id: 'r1',
        type: '表扬',
        periodKey: 'class',
        timestamp: '08:00:00',
        date: '2026-10-01',
      );
      final result = StatisticsService.compute(
        [record],
      );
      expect(result.summary.recordDays, 1);
      expect(result.dailyCounts, hasLength(1),
          reason: 'D-014：放假日的记录计入总数后，天数/趋势必须同口径保留');
      expect(result.dailyCounts.single.date, '2026-10-01');
    });

    test('非放假日期仍正常进入趋势', () {
      final result = StatisticsService.compute(
        [
          rec(
            id: 'r1',
            type: '表扬',
            periodKey: 'class',
            timestamp: '08:00:00',
            date: '2026-10-02',
          ),
        ],
      );
      expect(result.summary.recordDays, 1);
      expect(result.dailyCounts, hasLength(1));
    });
  });
}
