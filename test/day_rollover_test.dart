// 行为测试：跨天检测（修改4）。
//
// 主界面需要在自然日变化后立即刷新“今日记录/角标”；把“现在”注入后，
// 这里直接验证跨天判定与下一次检查时机的计算，不需要等到真实午夜。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/utils/day_rollover.dart';

void main() {
  group('DayRolloverTracker', () {
    test('同一天不触发；跨天触发一次并更新日期', () {
      var now = DateTime(2026, 10, 18, 23, 59, 30);
      final tracker = DayRolloverTracker(clock: () => now);

      expect(tracker.date, '2026-10-18');
      expect(tracker.check(), isFalse, reason: '同一天不应触发刷新');

      now = DateTime(2026, 10, 19, 0, 0, 1);
      expect(tracker.check(), isTrue, reason: '跨天后必须触发一次刷新');
      expect(tracker.date, '2026-10-19');
      expect(tracker.check(), isFalse, reason: '同一天只触发一次');
    });

    test('untilNextDay 返回距离下一天 0 点的时间', () {
      var now = DateTime(2026, 10, 18, 23, 0);
      final tracker = DayRolloverTracker(clock: () => now);

      expect(tracker.untilNextDay(), const Duration(hours: 1));

      now = DateTime(2026, 10, 18, 0, 30);
      expect(tracker.untilNextDay(), const Duration(hours: 23, minutes: 30));
    });
  });
}
