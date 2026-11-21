/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
 * 创建日期 (Created): 2026-11-15
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../constants/app_version.dart';

/// GitHub Release 中的一个附件。
class GitHubAsset {
  const GitHubAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.digest,
  });

  final String name;
  final Uri downloadUrl;
  final int size;

  /// GitHub 提供的 `sha256:<hex>` 摘要；旧附件可能为空。
  final String? digest;

  bool get isInstaller {
    final lower = name.toLowerCase();
    return lower.endsWith('.exe') || lower.endsWith('.msi');
  }
}

/// 一个 GitHub Release 的基本信息。
class GitHubReleaseInfo {
  const GitHubReleaseInfo({
    required this.tagName,
    required this.title,
    required this.notes,
    required this.assets,
  });

  final String tagName;
  final String title;
  final String notes;
  final List<GitHubAsset> assets;

  /// 优先选择名字带 Setup 的 exe，其次任意 exe/msi。
  GitHubAsset? get installerAsset {
    final installers = assets.where((asset) => asset.isInstaller).toList();
    if (installers.isEmpty) return null;
    for (final asset in installers) {
      if (asset.name.toLowerCase().contains('setup')) return asset;
    }
    for (final asset in installers) {
      if (asset.name.toLowerCase().endsWith('.exe')) return asset;
    }
    return installers.first;
  }

  /// 找到与 [asset] 对应的 `*.sha256` 校验文件。
  GitHubAsset? checksumAssetFor(GitHubAsset asset) {
    final expected = '${asset.name}.sha256'.toLowerCase();
    for (final candidate in assets) {
      if (candidate.name.toLowerCase() == expected) return candidate;
    }
    return null;
  }
}

/// 检查更新或下载过程中的可读错误。
class GitHubUpdateException implements Exception {
  const GitHubUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 通过 GitHub Releases API 检查、下载并校验更新包。
///
/// 只访问 GitHub 官方域名；下载后必须通过 SHA-256 校验才会交给安装器。
class GitHubUpdateService {
  GitHubUpdateService._();

  static const String owner = AppVersion.githubOwner;
  static const String repo = AppVersion.githubRepo;
  static const Duration requestTimeout = Duration(seconds: 20);
  static const Set<String> _allowedHosts = {
    'api.github.com',
    'github.com',
    'objects.githubusercontent.com',
    'uploads.github.com',
  };

  static Uri get latestReleaseUri =>
      Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');

  static Uri get latestReleasePageUri =>
      Uri.https('github.com', '/$owner/$repo/releases/latest');

  /// 读取最新正式版 Release。
  static Future<GitHubReleaseInfo> fetchLatestRelease({
    HttpClient? client,
    Uri? uri,
  }) async {
    final http = client ?? HttpClient();
    try {
      final request = await http
          .getUrl(uri ?? latestReleaseUri)
          .timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ClassManagementSystem/${AppVersion.pubspecVersion}',
      );
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw GitHubUpdateException('GitHub 返回 HTTP ${response.statusCode}');
      }
      return parseRelease(body);
    } on SocketException catch (e) {
      throw GitHubUpdateException('无法连接 GitHub：${e.message}');
    } on TimeoutException {
      throw const GitHubUpdateException('连接 GitHub 超时，请稍后重试');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 解析 Release JSON；测试可直接调用。
  static GitHubReleaseInfo parseRelease(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const GitHubUpdateException('GitHub 返回的数据格式不正确');
    }
    final tagName = (decoded['tag_name'] as String? ?? '').trim();
    if (tagName.isEmpty) {
      throw const GitHubUpdateException('GitHub 返回的版本号为空');
    }
    final assets = <GitHubAsset>[];
    final rawAssets = decoded['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final name = (item['name'] as String? ?? '').trim();
        final url = (item['browser_download_url'] as String? ?? '').trim();
        if (name.isEmpty || url.isEmpty) continue;
        final parsed = Uri.tryParse(url);
        if (parsed == null || parsed.scheme != 'https') continue;
        assets.add(
          GitHubAsset(
            name: name,
            downloadUrl: parsed,
            size: (item['size'] as num?)?.toInt() ?? 0,
            digest: item['digest'] as String?,
          ),
        );
      }
    }
    return GitHubReleaseInfo(
      tagName: tagName,
      title: (decoded['name'] as String? ?? tagName).trim(),
      notes: (decoded['body'] as String? ?? '').trim(),
      assets: assets,
    );
  }

  /// 判断 [latest] 是否比 [current] 新；支持 `V4.9.8` 与 `4.9.8+170` 形式。
  static bool isNewerVersion(String latest, String current) {
    final a = _Version.parse(latest);
    final b = _Version.parse(current);
    for (var i = 0; i < 3; i++) {
      if (a.parts[i] != b.parts[i]) return a.parts[i] > b.parts[i];
    }
    if (a.build != null && b.build != null && a.build != b.build) {
      return a.build! > b.build!;
    }
    return false;
  }

  /// 下载安装包到 [targetDir]，返回本地文件。
  static Future<File> downloadAsset(
    GitHubAsset asset, {
    required Directory targetDir,
    void Function(int received, int total)? onProgress,
    HttpClient? client,
  }) async {
    _ensureAllowedHost(asset.downloadUrl);
    final http = client ?? HttpClient();
    try {
      final request = await http.getUrl(asset.downloadUrl).timeout(requestTimeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ClassManagementSystem/${AppVersion.pubspecVersion}',
      );
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw GitHubUpdateException('下载安装包失败：HTTP ${response.statusCode}');
      }
      final file = File(
        '${targetDir.path}${Platform.pathSeparator}${_safeFileName(asset.name)}',
      );
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength > 0 ? response.contentLength : asset.size;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        throw const GitHubUpdateException('安装包下载不完整，请重试');
      }
      return file;
    } on SocketException catch (e) {
      throw GitHubUpdateException('下载安装包失败：${e.message}');
    } on TimeoutException {
      throw const GitHubUpdateException('下载安装包超时，请重试');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 下载一个文本附件（用于 `*.sha256` 校验文件）。
  static Future<String> downloadText(GitHubAsset asset, {HttpClient? client}) async {
    _ensureAllowedHost(asset.downloadUrl);
    final http = client ?? HttpClient();
    try {
      final request = await http.getUrl(asset.downloadUrl).timeout(requestTimeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ClassManagementSystem/${AppVersion.pubspecVersion}',
      );
      final response = await request.close().timeout(requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw GitHubUpdateException('下载校验文件失败：HTTP ${response.statusCode}');
      }
      return body;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 从 `sha256sum` 文本中取出 64 位十六进制摘要。
  static String? parseChecksum(String text, String assetName) {
    final match = RegExp(r'\b([0-9a-fA-F]{64})\b').firstMatch(text);
    if (match == null) return null;
    final normalized = match.group(1)!.toLowerCase();
    final fileName = text
        .split(RegExp(r'\r?\n'))
        .where((line) => line.toLowerCase().contains(normalized))
        .map((line) => line.replaceFirst(normalized, '').trim())
        .where((rest) => rest.isNotEmpty)
        .toList();
    if (fileName.isEmpty) return normalized;
    final listedName = fileName.first.replaceFirst(RegExp(r'^\*'), '').trim();
    if (listedName.isEmpty || listedName.endsWith(assetName)) return normalized;
    return null;
  }

  /// 校验文件 SHA-256；[expectedHex] 为 64 位十六进制。
  static Future<bool> verifyFileSha256(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedHex.toLowerCase();
  }

  /// 人类可读的字节数，用于下载进度。
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static void _ensureAllowedHost(Uri uri) {
    if (uri.scheme != 'https' || !_allowedHosts.contains(uri.host)) {
      throw const GitHubUpdateException('更新地址不是 GitHub 官方地址，已取消');
    }
  }

  static String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'update.exe' : cleaned;
  }
}

class _Version {
  const _Version(this.parts, this.build);

  final List<int> parts;
  final int? build;

  static _Version parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    int? build;
    final plus = value.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(value.substring(plus + 1).split('.').first);
      value = value.substring(0, plus);
    }
    final parts = <int>[];
    for (final part in value.split('.')) {
      final match = RegExp(r'^\d+').firstMatch(part);
      parts.add(match == null ? 0 : int.parse(match.group(0)!));
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return _Version(parts.sublist(0, 3), build);
  }
}
