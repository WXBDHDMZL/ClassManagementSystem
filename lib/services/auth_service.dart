/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import 'atomic_file.dart';
import 'local_storage_paths.dart';
import 'operation_log_service.dart';
import 'security_service.dart';
import 'storage_service.dart';
import '../utils/app_clock.dart';

/// 需要验证的密码类型。
enum AuthCredential { operation, recoveryCode }

/// 一次密码校验的结果。
class AuthResult {
  const AuthResult.success()
      : success = true,
        locked = false,
        remainingSeconds = 0;

  const AuthResult.failure({this.locked = false, this.remainingSeconds = 0})
      : success = false;

  final bool success;
  final bool locked;

  /// 锁定时剩余秒数（非锁定失败为 0）。
  final int remainingSeconds;
}

/// 管理密码的统一校验入口。
///
/// 负责取哈希、失败计数与锁定。
/// 本类只做“验证 + 计数 + 日志”，写入由 provider 负责；UI 不要直接调用
/// `SecurityService.verifyPassword*`，否则会绕开锁定与日志。
class AuthService {
  AuthService._();

  static const int maxFailuresBeforeLock = 5;
  static const Duration firstLock = Duration(seconds: 60);
  static const Duration maxLock = Duration(minutes: 15);

  static final Map<AuthCredential, int> _failures = {};
  static final Map<AuthCredential, DateTime> _lockedUntil = {};
  static final Map<AuthCredential, int> _lockCount = {};

  /// B-23：锁定状态落盘（无密码明文，仅失败次数/截止时间）。
  /// 重启程序后仍生效，不再能被“重启继续试”绕过。
  static const String _stateFileName = 'class_management_auth_guard.json';
  static bool _stateLoaded = false;
  static bool _persistFailedLogged = false;

  /// 测试专用：覆盖状态文件所在目录（避免写真实文档目录）。
  @visibleForTesting
  static Directory? debugStorageDirectory;

  static Future<File?> _stateFile() async {
    try {
      final override = debugStorageDirectory;
      if (override != null) {
        return File('${override.path}/$_stateFileName');
      }
      return LocalStoragePaths.authGuardFile();
    } on Object catch (_) {
      // 测试/异常环境没有 path_provider（可能抛 FlutterError/Error）：
      // 退回纯内存，不影响功能。
      return null;
    }
  }

  static Future<void>? _stateLoading;

  static Future<void> _loadStateIfNeeded() {
    if (_stateLoaded) return Future<void>.value();
    // 并发调用共用同一个加载 Future，避免第一个请求尚未读完时
    // 其他请求误以为“已加载”而按空状态校验。
    return _stateLoading ??= _readState().whenComplete(() {
      _stateLoaded = true;
      _stateLoading = null;
    });
  }

  static Future<void> _readState() async {
    try {
      final file = await _stateFile();
      if (file == null || !await file.exists()) return;
      final stored = await file.readAsString();
      // 锁定状态只接受 LRX2 密文；无法解密时按“无记录”处理。
      final plain = StorageService.decodeLocalText(stored);
      if (plain == null) return;
      final map = jsonDecode(plain);
      if (map is! Map) return;
      for (final credential in AuthCredential.values) {
        final key = credential.name;
        final failures = map['failures']?[key];
        if (failures is int && failures > 0) _failures[credential] = failures;
        final lockCount = map['lockCount']?[key];
        if (lockCount is int && lockCount > 0) {
          _lockCount[credential] = lockCount;
        }
        final untilText = map['lockedUntil']?[key];
        if (untilText is String && untilText.isNotEmpty) {
          final until = DateTime.tryParse(untilText);
          if (until != null && until.isAfter(AppClock.now())) {
            _lockedUntil[credential] = until;
          }
        }
      }
    } on Object catch (e) {
      // 状态文件损坏/不可读：退回内存策略，不阻断密码验证。
      debugPrint('读取密码锁定状态失败：$e');
    }
  }

  static Future<void> _persistState() async {
    try {
      final file = await _stateFile();
      if (file == null) return;
      // 目录缺失时先建：锁定状态写不进去会退化成“仅内存生效”，
      // 重启即可绕过锁定（旧数据/首次运行/目录被清理时都可能发生）。
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final plain = jsonEncode({
        'failures': {
          for (final c in AuthCredential.values)
            if ((_failures[c] ?? 0) > 0) c.name: _failures[c],
        },
        'lockCount': {
          for (final c in AuthCredential.values)
            if ((_lockCount[c] ?? 0) > 0) c.name: _lockCount[c],
        },
        'lockedUntil': {
          for (final c in AuthCredential.values)
            if (_lockedUntil[c] != null)
              c.name: _lockedUntil[c]!.toIso8601String(),
        },
      });
      await AtomicFile.writeString(
        file.path,
        StorageService.encodeLocalText(plain),
      );
    } on Object catch (e) {
      if (!_persistFailedLogged) {
        _persistFailedLogged = true;
        debugPrint('写入密码锁定状态失败（本次运行仅内存生效）：$e');
      }
    }
  }

  /// provider 层鉴权用：一次成功验证后，在短窗口内允许写操作。
  /// “班主任管理”授权：与旧的 30 分钟写门禁独立，由设置页配置时长。
  /// 只存在内存中，程序重启/手动退出即失效。
  static DateTime? _managementGrantUntil;

  static void grantManagement(Duration ttl) {
    _managementGrantUntil = AppClock.now().add(ttl);
  }

  static bool get hasManagementGrant {
    final until = _managementGrantUntil;
    if (until == null) return false;
    if (AppClock.now().isAfter(until)) {
      _managementGrantUntil = null;
      return false;
    }
    return true;
  }

  static Duration? get managementRemaining {
    final until = _managementGrantUntil;
    if (until == null) return null;
    final left = until.difference(AppClock.now());
    return left.isNegative ? null : left;
  }

  static void clearManagementGrant() => _managementGrantUntil = null;

  static String label(AuthCredential credential) => switch (credential) {
        AuthCredential.operation => '管理密码',
        AuthCredential.recoveryCode => '恢复码',
      };

  /// 该密码当前是否处于锁定期；返回剩余时间（null = 未锁定）。
  static Duration? lockRemaining(AuthCredential credential) {
    final until = _lockedUntil[credential];
    if (until == null) return null;
    final remaining = until.difference(AppClock.now());
    if (remaining <= Duration.zero) {
      _lockedUntil.remove(credential);
      return null;
    }
    return remaining;
  }

  static int failureCount(AuthCredential credential) =>
      _failures[credential] ?? 0;

  /// 该密码当前是否启用/可用。
  static bool isEnabled(AppSettings settings, AuthCredential credential) {
    switch (credential) {
      case AuthCredential.operation:
        return settings.passwordEnabled;
      case AuthCredential.recoveryCode:
        return settings.recoveryCodeEnabled;
    }
  }

  /// 当前该密码对应的哈希。
  static String storedHash(AppSettings settings, AuthCredential credential) {
    switch (credential) {
      case AuthCredential.operation:
        return settings.passwordHash;
      case AuthCredential.recoveryCode:
        return settings.recoveryCodeHash;
    }
  }

  /// 校验一次密码。内部处理锁定、失败计数与安全日志。
  static Future<AuthResult> verify(
    AppSettings settings,
    AuthCredential credential,
    String input,
  ) async {
    // 恢复码不是“门禁密码”：未设置时必须明确失败，不能像未启用密码那样放行。
    if (credential == AuthCredential.recoveryCode &&
        !settings.recoveryCodeEnabled) {
      return const AuthResult.failure();
    }
    // 未启用该密码：任何输入都视为通过（与旧版 enforced=false 语义一致）。
    if (!isEnabled(settings, credential)) return const AuthResult.success();

    // B-23：先恢复上次运行落盘的锁定/失败计数（重启后仍生效）。
    await _loadStateIfNeeded();

    final remaining = lockRemaining(credential);
    if (remaining != null) {
      return AuthResult.failure(
        locked: true,
        remainingSeconds: remaining.inSeconds + 1,
      );
    }

    final ok = await SecurityService.verifyPasswordAsync(
      input,
      storedHash: storedHash(settings, credential),
      enforced: true,
    );
    if (ok) {
      _failures.remove(credential);
      _lockedUntil.remove(credential);
      _lockCount.remove(credential);
      await _persistState();
      return const AuthResult.success();
    }

    final failures = (_failures[credential] ?? 0) + 1;
    _failures[credential] = failures;
    if (failures < maxFailuresBeforeLock) {
      OperationLogService.log(
        '安全验证',
        '${label(credential)}验证失败（第 $failures 次）',
      );
      await _persistState();
      return const AuthResult.failure();
    }

    // 达到阈值：锁定，连续触发则翻倍，最长 15 分钟。
    _failures[credential] = 0;
    final lockCount = (_lockCount[credential] ?? 0) + 1;
    _lockCount[credential] = lockCount;
    // 指数翻倍最多到 maxLock：先封顶移位次数，避免 lockCount 很大时
    // `1 << (lockCount - 1)` 溢出成负数/零，反而让锁定立即失效。
    final shift = lockCount - 1 > 20 ? 20 : lockCount - 1;
    var seconds = firstLock.inSeconds * (1 << shift);
    if (seconds <= 0 || seconds > maxLock.inSeconds) {
      seconds = maxLock.inSeconds;
    }
    _lockedUntil[credential] = AppClock.now().add(Duration(seconds: seconds));
    OperationLogService.log(
      '安全验证',
      '${label(credential)}连续错误 $maxFailuresBeforeLock 次，已锁定 $seconds 秒',
    );
    await _persistState();
    return AuthResult.failure(locked: true, remainingSeconds: seconds);
  }

  /// 清除所有密码的失败计数/锁定（找回密码成功后调用）。
  static Future<void> clearAllLocks() async {
    _failures.clear();
    _lockedUntil.clear();
    _lockCount.clear();
    await _persistState();
  }

  /// 测试用：清空内存中的锁定/失败计数与会话授权（不删除落盘状态文件）。
  static void resetForTest() {
    _failures.clear();
    _lockedUntil.clear();
    _lockCount.clear();
    _managementGrantUntil = null;
    _stateLoaded = false;
    _stateLoading = null;
    _persistFailedLogged = false;
  }
}
