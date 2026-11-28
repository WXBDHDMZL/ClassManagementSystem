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

import 'app_clock.dart';
import 'today_boundary.dart';

/// 跨天检测：界面只需要在“归属日变化”时刷新一次。
///
/// 为什么不能用自然日：今日记录/角标/悬浮球都按 `attributionDateString`
/// 读取（跨零点就寝的凌晨部分归前一天），自然日 0 点既不是数据边界，
/// 也会让 06:20 的真正切换点永远不触发刷新。详见 `today_boundary.dart`。
class DayRolloverTracker {
  DayRolloverTracker({DateTime Function()? clock, String? initialDate})
      : _clock = clock ?? AppClock.now {
    date = initialDate ?? attributionDateString(_clock());
  }

  final DateTime Function() _clock;

  /// 当前记录的归属日（yyyy-MM-dd）。
  late String date;

  /// 检查归属日是否变化；返回 true 表示已变化且 [date] 已更新。
  bool check() {
    final today = attributionDateString(_clock());
    if (today == date) return false;
    date = today;
    return true;
  }

  /// 距离下一次归属日变化还有多久（不含额外缓冲）。
  Duration untilNextChange() {
    final now = _clock();
    final next = nextAttributionChange(now);
    final diff = next.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }
}
