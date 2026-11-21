/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import '../services/statistics_service.dart';

/// 跨天检测（修改4）：界面只需要在“自然日变化”时刷新一次。
///
/// 为什么单独抽出来：`DateTime.now()` 无法在测试里伪造；把“现在”注入进来，
/// 就能用纯单元测试覆盖跨天逻辑，而不必真的等到午夜。
class DayRolloverTracker {
  DayRolloverTracker({DateTime Function()? clock, String? initialDate})
      : _clock = clock ?? DateTime.now {
    date = initialDate ?? StatisticsService.todayString(_clock());
  }

  final DateTime Function() _clock;

  /// 当前记录的日期（yyyy-MM-dd）。
  late String date;

  /// 检查是否跨天；返回 true 表示已跨天且 [date] 已更新。
  bool check() {
    final today = StatisticsService.todayString(_clock());
    if (today == date) return false;
    date = today;
    return true;
  }

  /// 距离下一次自然日 0 点还有多久（不含额外缓冲）。
  Duration untilNextDay() {
    final now = _clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    return next.difference(now);
  }
}
