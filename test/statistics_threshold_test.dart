// "需关注学生"三档阈值（一周 / 一个月 / 一学期）回归：
// 区间长度 → 用哪一档；设置项的保存与读取；以及"全部记录"区间不会用错档位。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/services/statistics_service.dart';

void main() {
  group('区间长度 → 阈值档位', () {
    const weekly = 3;
    const monthly = 8;
    const semester = 20;

    int pick(int days) => StatisticsService.attentionThresholdForDays(
          days,
          weekly: weekly,
          monthly: monthly,
          semester: semester,
        );

    test('一周以内（本周 / 近 7 天）用周值', () {
      expect(pick(1), weekly);
      expect(pick(7), weekly);
      expect(pick(10), weekly, reason: '10 天仍按周口径');
    });

    test('一个月（本月 / 近 30 天）用月值', () {
      expect(pick(11), monthly);
      expect(pick(30), monthly);
      expect(pick(45), monthly, reason: '45 天仍按月口径');
    });

    test('更长（本学期 / 全部记录）用学期值', () {
      expect(pick(46), semester);
      expect(pick(120), semester, reason: '本学期约 4 个月');
      expect(pick(400), semester, reason: '全部记录可能跨学年，仍按学期口径');
    });
  });

  test('三档阈值能正确保存与读取', () {
    final settings = AppSettings(
      themeMode: ThemeModeType.light,
      attentionThreshold: 4,
      attentionMonthThreshold: 9,
      attentionSemesterThreshold: 25,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.attentionThreshold, 4);
    expect(restored.attentionMonthThreshold, 9);
    expect(restored.attentionSemesterThreshold, 25);
  });

  test('老数据没有新字段时用出厂默认（3 / 8 / 20），越界值回退到出厂默认', () {
    final legacy = AppSettings.fromJson({
      'themeMode': 0,
      'attentionThreshold': 5,
    });
    expect(legacy.attentionThreshold, 5, reason: '旧字段就是"一周"这一档');
    expect(legacy.attentionMonthThreshold, 8, reason: '新增档位用出厂默认');
    expect(legacy.attentionSemesterThreshold, 20);

    final outOfRange = AppSettings.fromJson({
      'themeMode': 0,
      'attentionMonthThreshold': 999,
      'attentionSemesterThreshold': 0,
    });
    expect(
      outOfRange.attentionMonthThreshold,
      AppSettings.defaultAttentionMonthThreshold,
      reason: '超出 1–40 的值按出厂默认处理，而不是留下非法值',
    );
    expect(
      outOfRange.attentionSemesterThreshold,
      AppSettings.defaultAttentionSemesterThreshold,
    );
  });
}
