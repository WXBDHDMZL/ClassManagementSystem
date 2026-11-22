/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-11-15
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:class_management_system/services/github_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String _releaseJson({String tag = 'v4.9.8'}) => '''
{
  "tag_name": "$tag",
  "name": "V4.9.8",
  "body": "修复若干问题。",
  "assets": [
    {
      "name": "ClassManagementSystem_Setup_v4.9.8.exe",
      "browser_download_url": "https://github.com/WXBDHDMZL/ClassManagementSystem/releases/download/v4.9.8/ClassManagementSystem_Setup_v4.9.8.exe",
      "size": 12000000,
      "digest": "sha256:$_digest"
    },
    {
      "name": "ClassManagementSystem_Setup_v4.9.8.exe.sha256",
      "browser_download_url": "https://github.com/WXBDHDMZL/ClassManagementSystem/releases/download/v4.9.8/ClassManagementSystem_Setup_v4.9.8.exe.sha256",
      "size": 105
    }
  ]
}
''';

void main() {
  group('GitHubUpdateService.parseRelease', () {
    test('解析版本号、说明和附件', () {
      final release = GitHubUpdateService.parseRelease(_releaseJson());
      expect(release.tagName, 'v4.9.8');
      expect(release.title, 'V4.9.8');
      expect(release.notes, '修复若干问题。');
      expect(release.assets, hasLength(2));
      expect(release.assets.first.size, 12000000);
      expect(release.assets.first.digest, 'sha256:$_digest');
    });

    test('缺少 tag_name 时抛错', () {
      expect(
        () => GitHubUpdateService.parseRelease('{"assets": []}'),
        throwsA(isA<GitHubUpdateException>()),
      );
    });
  });

  group('GitHubReleaseInfo', () {
    test('优先选择名字带 Setup 的 exe', () {
      final release = GitHubUpdateService.parseRelease(_releaseJson());
      final asset = release.installerAsset;
      expect(asset, isNotNull);
      expect(asset!.name, 'ClassManagementSystem_Setup_v4.9.8.exe');
    });

    test('能找到对应的 sha256 校验文件', () {
      final release = GitHubUpdateService.parseRelease(_releaseJson());
      final asset = release.installerAsset!;
      expect(release.checksumAssetFor(asset)?.name, '${asset.name}.sha256');
    });
  });

  group('GitHubUpdateService.isNewerVersion', () {
    test('新补丁版本可用', () {
      expect(GitHubUpdateService.isNewerVersion('v4.9.8', 'V4.9.7'), isTrue);
      expect(GitHubUpdateService.isNewerVersion('V5.0.0', 'V4.9.7'), isTrue);
      expect(GitHubUpdateService.isNewerVersion('v4.10.0', 'V4.9.7'), isTrue);
    });

    test('相同版本或旧版本不可用', () {
      expect(GitHubUpdateService.isNewerVersion('v4.9.7', 'V4.9.7'), isFalse);
      expect(GitHubUpdateService.isNewerVersion('v4.9.6', 'V4.9.7'), isFalse);
      expect(GitHubUpdateService.isNewerVersion('', 'V4.9.7'), isFalse);
    });

    test('构建号参与比较', () {
      expect(
        GitHubUpdateService.isNewerVersion('v4.9.7+170', '4.9.7+169'),
        isTrue,
      );
      expect(
        GitHubUpdateService.isNewerVersion('v4.9.7+168', '4.9.7+169'),
        isFalse,
      );
    });
  });

  group('GitHubUpdateService.parseChecksum', () {
    test('解析文件名匹配的 sha256sum 行', () {
      final text =
          '$_digest  ClassManagementSystem_Setup_v4.9.8.exe\n'
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  other.exe\n';
      expect(
        GitHubUpdateService.parseChecksum(
          text,
          'ClassManagementSystem_Setup_v4.9.8.exe',
        ),
        _digest,
      );
    });

    test('文件名不匹配时返回 null', () {
      const text =
          '$_digest  OtherSetup.exe\n';
      expect(
        GitHubUpdateService.parseChecksum(
          text,
          'ClassManagementSystem_Setup_v4.9.8.exe',
        ),
        isNull,
      );
    });
  });

  test('formatBytes 显示可读单位', () {
    expect(GitHubUpdateService.formatBytes(900), '900 B');
    expect(GitHubUpdateService.formatBytes(2048), '2 KB');
    expect(GitHubUpdateService.formatBytes(12 * 1024 * 1024), '12.0 MB');
  });
}
