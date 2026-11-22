// 审查修复的回归测试（V2.30.5）。
//
// 目的：把《代码审查报告_2026-10-04.md》中修掉的问题逐个"钉住"，
// 避免以后悄悄退化（这些正是报告"测试覆盖缺口"一节点名的位置）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/app_version.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/services/statistics_service.dart';

void main() {
  // 时段是模块级全局状态：每个用例结束后复位，避免跨用例污染
  //（这正是报告"测试覆盖缺口"里点名的问题）。
  tearDown(() => applyCustomPeriods(const []));

  group('时段（审查 五-6 / 一-9 / 一-10）', () {
    test('标签带尾随空格时短名不退化', () {
      applyCustomPeriods(const [
        {'key': 'p1', 'label': '08:00-09:40 第一节 '},
      ]);
      expect(getTimePeriodShortName('p1'), '第一节');
      expect(getTimePeriodName('p1'), '08:00-09:40 第一节');
    });

    test('matchTimePeriodKey 容忍标签里的连续空格', () {
      applyCustomPeriods(const [
        {'key': 'p2', 'label': '08:00-09:40  第一节'},
      ]);
      expect(matchTimePeriodKey('第一节'), 'p2');
      expect(matchTimePeriodKey('08:00-09:40  第一节'), 'p2');
      expect(matchTimePeriodKey('不存在的时段'), '');
    });

    test('validatePeriodLabel 拒绝起止相同与越界时间', () {
      expect(validatePeriodLabel('08:00-08:00 课'), '时间段的起止时间不能相同');
      expect(validatePeriodLabel('25:00-26:00 课'), isNotNull);
      expect(validatePeriodLabel('08:00-09:40 第一节'), isNull);
      expect(validatePeriodLabel(''), isNotNull);
    });

    test('落库时会过滤非法时段（审查 一-9：导入路径绕过 UI 校验）', () {
      applyCustomPeriods(const [
        {'key': 'ok', 'label': '08:00-09:40 第一节'},
        {'key': 'bad', 'label': '08:00-08:00 起止相同'},
      ]);
      expect(getTimePeriodName('ok'), '08:00-09:40 第一节');
      expect(
        effectivePeriods().any((item) => item['key'] == 'bad'),
        isFalse,
        reason: '起止相同的非法时段不应入库',
      );
    });
  });

  group('统计日期（审查 一-11：环比区间按日历运算）', () {
    test('previousPeriod 跨月正确，且紧接在前、不含当天', () {
      final p = StatisticsService.previousPeriod('2026-03-01', '2026-03-07');
      expect(p, isNotNull);
      expect(p!.$1, '2026-02-22');
      expect(p.$2, '2026-02-28');
    });

    test('previousPeriod 跨年正确', () {
      final y = StatisticsService.previousPeriod('2026-01-01', '2026-01-05')!;
      expect(y.$1, '2025-12-27');
      expect(y.$2, '2025-12-31');
    });

    test('previousPeriod 对非法日期返回 null', () {
      expect(
        StatisticsService.previousPeriod('2026-99-99', '2026-10-01'),
        isNull,
      );
    });
  });

  group('测试缺口：版本一致性', () {
    test('AppVersion 与 pubspec.yaml 一致（此前只有脚本检查）', () {
      final text = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(r'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)')
          .firstMatch(text);
      expect(match, isNotNull, reason: 'pubspec.yaml 必须能解析出版本号');
      expect(AppVersion.version, 'V${match!.group(1)}');
      expect(AppVersion.pubspecVersion, '${match.group(1)}+${match.group(2)}');
    });
  });
}
