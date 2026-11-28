/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-11-15
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../constants/app_version.dart';
import '../constants/update_signing_key.dart';

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

  /// 找到与 [asset] 对应的 `*.sig` 签名文件。
  GitHubAsset? signatureAssetFor(GitHubAsset asset) {
    final expected = '${asset.name}.sig'.toLowerCase();
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

/// 用户在下载过程中主动取消（审计 P2-23：进度框原先不可取消）。
class UpdateCancelledException extends GitHubUpdateException {
  const UpdateCancelledException() : super('已取消更新');
}

/// 通过 GitHub Releases API 检查、下载并校验更新包。
///
/// 只访问 GitHub 官方域名；下载后必须通过 SHA-256 校验才会交给安装器。
class GitHubUpdateService {
  GitHubUpdateService._();

  static const String owner = AppVersion.githubOwner;
  static const String repo = AppVersion.githubRepo;
  static const Duration requestTimeout = Duration(seconds: 20);

  /// 下载响应体的空闲超时：超过这么久没有收到任何数据就判定失败。
  static const Duration idleTimeout = Duration(seconds: 30);
  static const Set<String> _allowedHosts = {
    'api.github.com',
    'github.com',
    'objects.githubusercontent.com',
    'uploads.github.com',
    // GitHub Releases 的下载 302 会跳到该主机；缺它会导致所有真实安装包
    // 下载被拒绝（审计 F1-1）。
    'release-assets.githubusercontent.com',
  };

  /// 更新下载只允许 GitHub 官方 HTTPS 主机。
  static bool isAllowedHost(String host) =>
      _allowedHosts.contains(host.toLowerCase());

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
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
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

  /// 更新包临时目录（下载的安装包与更新助手脚本都放在这里）。
  static Directory defaultDownloadDir() => Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}班级管理系统_更新',
      );

  /// 清理更新包临时目录里 [maxAge] 之前留下的旧安装包（审计 A-26）。
  ///
  /// 更新流程是"退出后由更新助手安装"，所以**不能**在下载成功时删包；
  /// 但历史版本失败/取消后会留下几十上百 MB 的安装包没人清理。这里在启动时
  /// 只删除明显过期的文件，返回删除数量；任何异常都不影响启动。
  static Future<int> cleanupStaleDownloads({
    Directory? directory,
    Duration maxAge = const Duration(days: 7),
    DateTime? now,
  }) async {
    final dir = directory ?? defaultDownloadDir();
    var removed = 0;
    try {
      if (!await dir.exists()) return 0;
      final cutoff = (now ?? DateTime.now()).subtract(maxAge);
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isAfter(cutoff)) continue;
          await entity.delete(recursive: true);
          removed++;
        } on Object catch (e) {
          debugPrint('清理旧更新包失败：$e');
        }
      }
    } on Object catch (e) {
      debugPrint('扫描更新包目录失败：$e');
    }
    return removed;
  }

  /// 下载安装包到 [targetDir]，返回本地文件。
  ///
  /// 审计 P2-23：响应体逐块读取原先没有任何超时，网络半死不活时下载会
  /// 永久挂起（进度框又不可取消）。现在加了 30 秒空闲超时，并支持通过
  /// [shouldCancel] 中途取消。
  static Future<File> downloadAsset(
    GitHubAsset asset, {
    required Directory targetDir,
    void Function(int received, int total)? onProgress,
    bool Function()? shouldCancel,
    HttpClient? client,
  }) async {
    final http = client ?? HttpClient();
    File? partialFile;
    var succeeded = false;
    try {
      final response = await _openFollowingAllowedRedirects(
        http,
        asset.downloadUrl,
      );
      if (response.statusCode != HttpStatus.ok) {
        throw GitHubUpdateException('下载安装包失败：HTTP ${response.statusCode}');
      }
      final file = File(
        '${targetDir.path}${Platform.pathSeparator}${_safeFileName(asset.name)}',
      );
      partialFile = file;
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength > 0
          ? response.contentLength
          : asset.size;
      try {
        final stream = response.timeout(
          idleTimeout,
          onTimeout: (chunkSink) {
            chunkSink.addError(
              const GitHubUpdateException('下载长时间无数据，请检查网络后重试'),
            );
            chunkSink.close();
          },
        );
        await for (final chunk in stream) {
          if (shouldCancel?.call() ?? false) {
            throw const UpdateCancelledException();
          }
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
      succeeded = true;
      return file;
    } on SocketException catch (e) {
      throw GitHubUpdateException('下载安装包失败：${e.message}');
    } on TimeoutException {
      throw const GitHubUpdateException('下载安装包超时，请重试');
    } finally {
      if (!succeeded && partialFile != null) {
        try {
          await partialFile.delete();
        } on Object catch (_) {}
      }
      if (client == null) http.close(force: true);
    }
  }

  /// 下载一个文本附件（用于 `*.sha256` 校验文件）。
  static Future<String> downloadText(
    GitHubAsset asset, {
    HttpClient? client,
  }) async {
    final http = client ?? HttpClient();
    try {
      final response = await _openFollowingAllowedRedirects(
        http,
        asset.downloadUrl,
      );
      if (response.statusCode != HttpStatus.ok) {
        throw GitHubUpdateException('下载校验文件失败：HTTP ${response.statusCode}');
      }
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 从 `sha256sum` 文本中取出 64 位十六进制摘要。
  ///
  /// 审计 P2-24：原实现只取全文第一个摘要再校验文件名，多资产 checksum
  /// 文件里目标资产不是第一行时会返回 null，界面误报「未提供校验值」。
  /// 现在逐行按文件名匹配，只有完全没有文件名信息（纯摘要文件）时才
  /// 退回到唯一摘要。
  static String? parseChecksum(String text, String assetName) {
    final lines = text.split(RegExp(r'\r?\n'));
    final digestPattern = RegExp(r'([0-9a-fA-F]{64})');
    final digests = <String>[];
    var sawNamedLine = false;
    for (final line in lines) {
      final match = digestPattern.firstMatch(line);
      if (match == null) continue;
      final digest = match.group(1)!.toLowerCase();
      if (!digests.contains(digest)) digests.add(digest);
      final rest = line.replaceFirst(match.group(1)!, '').trim();
      if (rest.isEmpty) continue;
      final listedName = rest.replaceFirst(RegExp(r'^\*'), '').trim();
      if (listedName.isEmpty) continue;
      sawNamedLine = true;
      final baseName = listedName.split(RegExp(r'[/\\]')).last.trim();
      if (baseName == assetName) return digest;
    }
    // 纯摘要文件（没有文件名）只有一个摘要时直接采用；有文件名但都不匹配
    // 说明这份 checksum 不是给当前资产的，必须返回 null 让调用方报错。
    if (!sawNamedLine && digests.length == 1) return digests.single;
    return null;
  }

  /// 校验文件 SHA-256；[expectedHex] 为 64 位十六进制。
  static Future<bool> verifyFileSha256(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedHex.toLowerCase();
  }

  /// 校验安装包的 Ed25519 签名。
  ///
  /// 签名对象是文件 SHA-256 摘要的 32 字节原始值；[signatureBase64] 是
  /// Release 资产 `*.sig` 的内容。公钥默认使用内置常量。
  static Future<bool> verifyFileSignature(
    File file,
    String signatureBase64, {
    String publicKeyBase64 = UpdateSigningKey.publicKeyBase64,
  }) async {
    try {
      final signatureBytes = base64Decode(signatureBase64.trim());
      final publicKeyBytes = base64Decode(publicKeyBase64);
      if (signatureBytes.length != 64 || publicKeyBytes.length != 32) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      return await Ed25519().verify(
        digest.bytes,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(
            publicKeyBytes,
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    } on StateError {
      return false;
    }
  }

  /// 人类可读的字节数，用于下载进度。
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  /// 打开请求并手动校验每一跳重定向（审计 P2-40：默认自动跟随 302
  /// 会把请求带到任意 HTTPS 主机）。
  static Future<HttpClientResponse> _openFollowingAllowedRedirects(
    HttpClient http,
    Uri initial, {
    int redirects = 0,
  }) async {
    _ensureAllowedHost(initial);
    final request = await http.getUrl(initial).timeout(requestTimeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'ClassManagementSystem/${AppVersion.pubspecVersion}',
    );
    request.followRedirects = false;
    final response = await request.close().timeout(requestTimeout);
    const redirectCodes = {301, 302, 303, 307, 308};
    if (redirectCodes.contains(response.statusCode)) {
      if (redirects >= 5) {
        await response.drain();
        throw const GitHubUpdateException('更新下载重定向次数过多，已取消');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain();
      if (location == null || location.isEmpty) {
        throw const GitHubUpdateException('更新下载重定向缺少地址，已取消');
      }
      return _openFollowingAllowedRedirects(
        http,
        initial.resolve(location),
        redirects: redirects + 1,
      );
    }
    return response;
  }

  static void _ensureAllowedHost(Uri uri) {
    // 审计 P2-40：只接受标准 443 端口，避免 https://github.com:8443 绕过。
    if (uri.scheme != 'https' ||
        !isAllowedHost(uri.host) ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty) {
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
