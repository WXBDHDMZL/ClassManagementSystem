// 时段常量测试：时刻匹配、自定义标签生效、标签格式校验。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';

void main() {
  tearDown(() {
    // 自定义时段是全局状态，测试后必须清空，避免影响其它用例。
    applyCustomPeriods(const []);
  });

  test('按时刻匹配出厂时段：早读、上课、午休、晚修、就寝', () {
    String? at(int hour, int minute) => matchPeriodByMinutes(hour * 60 + minute);

    expect(at(7, 30), 'morning_reading');
    expect(at(10, 0), 'class');
    expect(at(13, 30), 'noon_rest');
    expect(at(20, 0), 'evening_study');
    expect(at(23, 0), 'sleep');
    // 跨零点：凌晨 1 点仍属就寝（22:00-06:20）
    expect(at(1, 0), 'sleep');
    expect(at(6, 0), 'sleep');
    expect(at(6, 30), 'meal');
    expect(at(12, 40), 'meal');
  });

  test('自定义时段标签立即生效：名称与时间范围都会改变', () {
    applyCustomPeriods(const [
      {'key': 'morning_reading', 'label': '07:30-08:10 晨读'},
      {'key': 'class', 'label': '08:10-12:00 第一课堂'},
    ]);

    expect(getTimePeriodName('morning_reading'), '07:30-08:10 晨读');
    expect(getTimePeriodShortName('morning_reading'), '晨读');
    expect(getTimePeriodShortName('class'), '第一课堂');
    // 新范围之外的老时间点不再命中早读
    expect(matchPeriodByMinutes(7 * 60 + 10), isNot('morning_reading'));
    expect(matchPeriodByMinutes(7 * 60 + 40), 'morning_reading');
    // 按名称反查也认自定义名称
    expect(matchTimePeriodKey('晨读'), 'morning_reading');
    expect(matchTimePeriodKey('07:30-08:10 晨读'), 'morning_reading');
  });

  test('时段标签校验：非空、含名称、时间段格式正确', () {
    expect(validatePeriodLabel(''), '时段内容不能为空');
    expect(validatePeriodLabel('08:00-12:30'), isNotNull);
    expect(validatePeriodLabel('08:00-12:30 上课'), isNull);
    expect(validatePeriodLabel('08:00-12:30、14:00-16:40 上课'), isNull);
    expect(validatePeriodLabel('8点-12点 上课'), isNotNull);
  });

  test('时段可增删：自定义列表生效后出厂时段被替换', () {
    applyCustomPeriods([
      {'key': 'morning', 'label': '07:30-08:10 晨读'},
      {'key': 'custom_1', 'label': '10:00-10:20 大课间'},
    ]);

    final periods = effectivePeriods();
    expect(periods.length, 2);
    expect(periods[0]['key'], 'morning');
    expect(getTimePeriodName('custom_1'), '10:00-10:20 大课间');
    expect(getTimePeriodShortName('custom_1'), '大课间');
    // 出厂时段已被替换：原"上课"不再出现在匹配结果里
    expect(matchPeriodByMinutes(10 * 60), 'custom_1');
    expect(matchPeriodByMinutes(9 * 60), isNull);
    // 名称反查也认新增时段
    expect(matchTimePeriodKey('大课间'), 'custom_1');
  });

  test('不存在的时段名称反查为空', () {
    expect(matchTimePeriodKey('不存在的时段'), '');
  });
}
