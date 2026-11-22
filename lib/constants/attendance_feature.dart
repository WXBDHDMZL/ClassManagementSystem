import 'package:flutter/foundation.dart' show visibleForTesting;

/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-10-31
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 考勤功能边界。
///
/// 当前版本暂停向普通用户开放考勤：界面、导出、统计与自动同步
/// 都统一读取本开关；考勤数据模型和备份/数据包兼容保留，供后续 DLC 恢复。
class AttendanceFeature {
  AttendanceFeature._();

  /// 测试开关：生产默认 false，测试启动时由 flutter_test_config 打开，
  /// 让考勤引擎/数据兼容测试继续验证底层能力。
  static bool _enabledForTests = false;

  /// 是否向普通用户开放考勤功能。
  ///
  /// 恢复 DLC 时把 [_enabledForTests] 的默认值或本 getter 改为 true，
  /// 再由后续版本补齐节次/历史设计。
  static bool get enabled => _enabledForTests;

  /// 仅供测试：切换业务开关，生产代码不要调用。
  @visibleForTesting
  static set enabledForTests(bool value) => _enabledForTests = value;
}
