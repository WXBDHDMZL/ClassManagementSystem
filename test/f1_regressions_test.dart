/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.7
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/desktop_service.dart';
import 'package:class_management_system/services/github_update_service.dart';

void main() {
  group('更新下载白名单（F1-1）', () {
    test('放行 GitHub Releases 实际跳转主机', () {
      expect(
        GitHubUpdateService.isAllowedHost(
          'release-assets.githubusercontent.com',
        ),
        isTrue,
      );
      expect(
        GitHubUpdateService.isAllowedHost(
          'RELEASE-ASSETS.GITHUBUSERCONTENT.COM',
        ),
        isTrue,
      );
    });

    test('拒绝非 GitHub 主机', () {
      expect(GitHubUpdateService.isAllowedHost('evil.example.com'), isFalse);
      expect(GitHubUpdateService.isAllowedHost('github.com.evil.test'), isFalse);
    });
  });

  group('StartupApproved 首字节语义（F1-3）', () {
    test('0x02 表示启用', () {
      expect(DesktopService.startupApprovedAllowsStart('02'), isTrue);
      expect(DesktopService.startupApprovedAllowsStart('2'), isTrue);
    });

    test('0x03 表示禁用', () {
      expect(DesktopService.startupApprovedAllowsStart('03'), isFalse);
      expect(DesktopService.startupApprovedAllowsStart('3'), isFalse);
    });

    test('无法解析时按启用处理，避免误判', () {
      expect(DesktopService.startupApprovedAllowsStart(''), isTrue);
      expect(DesktopService.startupApprovedAllowsStart('zz'), isTrue);
    });
  });
}
