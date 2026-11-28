/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import '../constants/time_periods.dart';
import 'app_date.dart';

/// 当前时刻的“归属日”（yyyy-MM-dd）。
///
/// 与记录、考勤、今日列表、今日角标共用同一口径：跨零点时段（如就寝
/// 22:00-06:20）的次日凌晨部分归到前一天；其余时刻归到日历当天。
///
/// 这是“今日”的唯一计算入口，`AppDataProvider` 与跨天刷新必须共用它，
/// 避免像 D-103 之后那样出现“数据按归属日、刷新按自然日”的双口径。
String attributionDateString(DateTime now) {
  final periodKey = matchPeriodByMinutes(now.hour * 60 + now.minute);
  return formatYmd(attributionDay(now, periodKey));
}

/// 下一次“归属日”发生变化的时间点。
///
/// 不能再用自然日 0 点代替：默认就寝时段 22:00-06:20 使 0 点前后仍属于
/// 同一个归属日，真正的切换点在 06:20；自定义时段也可能有别的跨零点区间。
/// 这里按分钟扫描（最多 24 小时），对所有时段配置都适用。
DateTime nextAttributionChange(DateTime now) {
  final current = attributionDateString(now);
  // 从下一个整分钟开始找；归属日只会在分钟边界变化。
  var probe = DateTime(now.year, now.month, now.day, now.hour, now.minute)
      .add(const Duration(minutes: 1));
  for (var i = 0; i <= 24 * 60; i++) {
    if (attributionDateString(probe) != current) return probe;
    probe = probe.add(const Duration(minutes: 1));
  }
  // 24 小时内都没变化（例如只有一个“全天”时段）时，下一轮再查。
  return now.add(const Duration(hours: 24));
}
