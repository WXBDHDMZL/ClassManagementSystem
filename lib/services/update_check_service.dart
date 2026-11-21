/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-11-15
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/foundation.dart';

import '../constants/app_version.dart';
import 'github_update_service.dart';

/// 后台检查 GitHub 最新正式版，并把结果提供给「关于」页。
class UpdateCheckService {
  UpdateCheckService._();

  /// 有可用版本时为对应 Release，否则为 null。
  static final ValueNotifier<GitHubReleaseInfo?> availableRelease =
      ValueNotifier<GitHubReleaseInfo?>(null);

  /// 启动时静默检查；失败不影响使用，也不打扰用户。
  static Future<GitHubReleaseInfo?> checkInBackground({
    Future<GitHubReleaseInfo> Function()? fetch,
  }) async {
    try {
      final release = (fetch ?? GitHubUpdateService.fetchLatestRelease)();
      final latest = await release;
      if (GitHubUpdateService.isNewerVersion(
        latest.tagName,
        AppVersion.version,
      )) {
        availableRelease.value = latest;
        return latest;
      }
      availableRelease.value = null;
    } on Object catch (e) {
      debugPrint('启动检查更新失败：$e');
    }
    return null;
  }

  @visibleForTesting
  static void resetForTest() {
    availableRelease.value = null;
  }
}
