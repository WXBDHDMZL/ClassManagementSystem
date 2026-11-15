/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-11-15
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/foundation.dart' show visibleForTesting;

/// 程序内“现在”的唯一来源。
///
/// 为什么需要它：凡是按“今天/本月”决定行为的代码（新增记录的默认日期、
/// 今日统计、日志按月、跨天检测…）都直接调 `DateTime.now()`，测试就无法
/// 稳定复现“跨午夜”“月初”这类边界——用例跑到一半跨过 0 点就会偶发失败。
/// 统一走这里之后，测试可以把时钟固定在任意时刻，生产行为完全不变。
///
/// 约定：**只有需要“日期/时刻语义”的地方才用它**；生成临时文件名、唯一 ID
/// 这类只要求“不重复”的地方继续用 `DateTime.now()`，避免时钟被固定后重名。
class AppClock {
  AppClock._();

  static DateTime Function() _now = DateTime.now;

  /// 当前时间。
  static DateTime now() => _now();

  /// 当前日期（`yyyy-MM-dd` 由调用方格式化，这里只提供时间点）。
  static DateTime today() {
    final value = _now();
    return DateTime(value.year, value.month, value.day);
  }

  /// 测试专用：固定时钟。
  @visibleForTesting
  static void setForTest(DateTime Function() clock) {
    _now = clock;
  }

  /// 测试专用：恢复真实时钟。
  @visibleForTesting
  static void resetForTest() {
    _now = DateTime.now;
  }

  /// 测试专用：把时钟固定在某个时刻。
  @visibleForTesting
  static void freezeForTest(DateTime fixed) {
    _now = () => fixed;
  }

  /// 测试专用：当前是否被固定。
  @visibleForTesting
  static bool get isFrozenForTest => !identical(_now, DateTime.now);
}
