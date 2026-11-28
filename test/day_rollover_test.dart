// 行为测试：跨天检测（按归属日，而不是自然日）。
//
// 主界面“今日记录/角标/悬浮球”都按归属日读取：默认就寝时段
// 22:00-06:20 的凌晨部分归属前一天，真正的刷新点是 06:20。
// 把“现在”注入后，这里直接验证归属日判定与下一次检查时机。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/utils/day_rollover.dart';
import 'package:class_management_system/utils/today_boundary.dart';

void main() {
  group('归属日边界', () {
    test('00:30 仍在就寝时段，归属前一天', () {
      expect(
        attributionDateString(DateTime(2026, 11, 22, 0, 30)),
        '2026-11-21',
      );
    });

    test('06:19:59 仍归前一天，06:20:00 切到当天', () {
      expect(
        attributionDateString(DateTime(2026, 11, 22, 6, 19, 59)),
        '2026-11-21',
      );
      expect(
        attributionDateString(DateTime(2026, 11, 22, 6, 20)),
        '2026-11-22',
      );
    });

    test('nextAttributionChange 返回 06:20，而不是 0 点', () {
      expect(
        nextAttributionChange(DateTime(2026, 11, 22, 0, 30)),
        DateTime(2026, 11, 22, 6, 20),
      );
      expect(
        nextAttributionChange(DateTime(2026, 11, 21, 23, 0)),
        DateTime(2026, 11, 22, 6, 20),
      );
    });

    test('自定义跨零点时段也按实际边界计算', () {
      applyCustomPeriods(const [
        {'key': 'night', 'label': '21:00-03:30 夜间'},
        {'key': 'day', 'label': '03:30-21:00 白天'},
      ]);
      addTearDown(resetPeriodsForTest);

      expect(
        attributionDateString(DateTime(2026, 11, 22, 2, 0)),
        '2026-11-21',
      );
      expect(
        nextAttributionChange(DateTime(2026, 11, 22, 0, 30)),
        DateTime(2026, 11, 22, 3, 30),
      );
    });
  });

  group('DayRolloverTracker', () {
    test('00:30 启动后即使跨过 06:20 也只触发一次', () {
      var now = DateTime(2026, 11, 22, 0, 30);
      final tracker = DayRolloverTracker(clock: () => now);

      expect(tracker.date, '2026-11-21');
      expect(tracker.check(), isFalse);

      now = DateTime(2026, 11, 22, 6, 19, 59);
      expect(tracker.check(), isFalse);

      now = DateTime(2026, 11, 22, 6, 20);
      expect(tracker.check(), isTrue, reason: '归属日切换必须触发刷新');
      expect(tracker.date, '2026-11-22');
      expect(tracker.check(), isFalse);
    });

    test('23:00 启动后下一次检查点是次日 06:20', () {
      var now = DateTime(2026, 11, 21, 23, 0);
      final tracker = DayRolloverTracker(clock: () => now);
      expect(
        tracker.untilNextChange(),
        const Duration(hours: 7, minutes: 20),
      );

      now = DateTime(2026, 11, 22, 6, 20);
      expect(tracker.check(), isTrue);
    });
  });
}
