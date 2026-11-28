/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 管理密码校验：
/// 代码中只保存密码的 SHA-256 哈希，不保存明文密码，
/// 避免程序被逆向时直接提取到密码；
/// 用户在设置里改过密码后，哈希随数据文件一起加密保存。
class SecurityService {
  SecurityService._();

  /// 出厂默认密码的 SHA-256 哈希（十六进制小写）。
  static const String _defaultPasswordHash =
      '5582868f17d5b4fd3aa9fe7251f8409dcfb6a11f4653e3e704bbf4842786ef6f';

  /// 密码长度限制（去首尾空格后计算）。
  /// 最小口令长度（修复 审查 七-2）：4 → 6。
  /// 4 位口令空间仅约 10^4，配合本地哈希（即使加盐多轮）也过于容易穷举。
  /// 注意：这不影响已设置的短密码——只是"改密码"时要求更长。
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 20;

  /// 恢复码字符集：去掉易混的 0/O、1/I/L 等，便于抄写。
  static const String _recoveryCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// 生成恢复码（默认 5 组 × 4 位 = 20 位，约 100 bit 熵），显示时用 `-` 分组。
  static String generateRecoveryCode({int groups = 5, int groupLength = 4}) {
    final random = Random.secure();
    final parts = <String>[];
    for (var g = 0; g < groups; g++) {
      final buffer = StringBuffer();
      for (var i = 0; i < groupLength; i++) {
        buffer.write(
          _recoveryCodeAlphabet[random.nextInt(_recoveryCodeAlphabet.length)],
        );
      }
      parts.add(buffer.toString());
    }
    return parts.join('-');
  }

  /// 恢复码归一化：去空格/连字符、转大写（比对哈希前统一口径）。
  static String normalizeRecoveryCode(String code) =>
      code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  /// 校验输入密码是否正确：[storedHash] 为空时与出厂默认密码比对。
  /// 首尾空格会被忽略，避免输入法误带空格导致"密码明明对却打不开"。
  ///
  /// 注意：同步版含两万轮 PBKDF2（约数百毫秒），**UI 一律用
  /// [verifyPasswordAsync]**（性能批 M6：放后台 isolate，密码框不再冻结）；
  /// 同步版保留给纯 Dart 单测与内部实现。
  static bool verifyPassword(
    String input, {
    String storedHash = '',
    bool enforced = true,
  }) {
    // 未启用密码保护时，任何输入都视为通过（供统一门禁复用）。
    if (!enforced) return true;
    return _verifyAgainst(input.trim(), effectivePasswordHash(storedHash));
  }

  /// [verifyPassword] 的异步版本（性能批 M6）：PBKDF2 移入后台 isolate，
  /// 校验期间界面保持可响应。
  static Future<bool> verifyPasswordAsync(
    String input, {
    String storedHash = '',
    bool enforced = true,
  }) {
    if (!enforced) return Future<bool>.value(true);
    final trimmed = input.trim();
    final stored = effectivePasswordHash(storedHash);
    return Isolate.run(() => _verifyAgainst(trimmed, stored));
  }

  /// 当前生效的密码哈希（[storedHash] 为空表示仍在用出厂默认密码）。
  static String effectivePasswordHash(String storedHash) =>
      storedHash.isEmpty ? _defaultPasswordHash : storedHash;

  /// 是否仍在使用出厂默认密码（审计 A-17）。
  ///
  /// 判定语义（按修复裁决固定）：当前存储的哈希为空（沿用出厂密码），
  /// 或严格等于内置的出厂裸 SHA-256 常量。
  /// 出厂密码是公开在源码里的固定哈希，任何人都能离线比对，
  /// 因此它只能当"首次进入"的初始口令，不能当长期密码。
  /// 说明：用户把密码改回出厂口令时，存的是带盐 `p2:` 哈希，
  /// 不会命中这里的常量比较；这类情况靠"设置页持续提示 + 启动提示"覆盖。
  static bool isUsingFactoryPassword(String storedHash) {
    final trimmed = storedHash.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    return trimmed == _defaultPasswordHash;
  }

  /// 新版口令格式前缀（V2.30.2 加固，审查 7.5）：
  /// - 当前格式：`p2:迭代次数:盐:哈希`。
  static const String _pbkdf2Prefix = 'p2:';

  /// PBKDF2 迭代次数。纯 Dart 实现性能约每次数百毫秒（已放后台 isolate）；
  /// V2.36.0 起从 20,000 提升到 100,000，提高离线暴力破解成本。
  static const int _pbkdf2Iterations = 100000;

  /// 计算密码哈希（首尾空格忽略，与实际校验口径一致）。
  /// 新设置的密码一律使用加盐多轮格式，并**把迭代次数写进哈希**，
  /// 以后调整默认迭代次数不会让已有密码失效。
  static String hashPassword(String input) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final hash = _pbkdf2(utf8.encode(input.trim()), salt, _pbkdf2Iterations);
    return '$_pbkdf2Prefix$_pbkdf2Iterations:'
        '${base64Encode(salt)}:${base64Encode(hash)}';
  }

  /// [hashPassword] 的异步版本（性能批 M6）：PBKDF2 放后台 isolate，
  /// 改密码确认时界面不冻结。
  static Future<String> hashPasswordAsync(String input) =>
      Isolate.run(() => hashPassword(input));

  /// 校验 [input] 是否匹配 [stored]。
  ///
  /// 除当前 `p2:` 格式外，只额外接受内置的出厂默认哈希（裸 SHA-256）。
  /// 出厂默认密码从未由用户设置，也没有可迁移的盐；若不单独识别它，
  /// 一旦数据满足“已启用密码 + 密码哈希为空”，任何输入都会失败且用户
  /// 无法自助改密。
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static bool _verifyAgainst(String input, String stored) {
    if (!stored.startsWith(_pbkdf2Prefix)) {
      if (stored != _defaultPasswordHash) return false;
      final digest = sha256.convert(utf8.encode(input)).toString();
      return _constantTimeEquals(utf8.encode(digest), utf8.encode(stored));
    }
    final parts = stored.substring(_pbkdf2Prefix.length).split(':');
    if (parts.length != 3) return false;
    try {
      final iterations = int.tryParse(parts[0]);
      if (iterations == null || iterations <= 0) return false;
      final salt = base64Decode(parts[1]);
      final expected = base64Decode(parts[2]);
      final actual = _pbkdf2(utf8.encode(input), salt, iterations);
      if (actual.length != expected.length) return false;
      // 常数时间比较，避免按字节提前返回。
      var diff = 0;
      for (var i = 0; i < expected.length; i++) {
        diff |= expected[i] ^ actual[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  /// PBKDF2-HMAC-SHA256（单块，输出 32 字节）。
  static Uint8List _pbkdf2(List<int> password, Uint8List salt, int iterations) {
    final hmac = Hmac(sha256, password);
    // U1 = HMAC(P, salt || INT(1))，随后 U2 = HMAC(P, U1) … 逐轮异或。
    final first = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    var u = Uint8List.fromList(first);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  /// 常见弱口令（小写比较）：命中即拒绝，避免 "123456" 这类口令通过长度检查。
  static const Set<String> _commonWeakPasswords = {
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '000000',
    '111111',
    '666666',
    '888888',
    '112233',
    '123123',
    '520520',
    'abc123',
    'abc123456',
    'admin',
    'admin123',
    'password',
    'passwd',
    'qwerty',
    'woaini',
    'iloveyou',
    'letmein',
    'welcome',
  };

  /// 密码是否过于简单（长度之外的最低防线）。
  static bool isWeakPassword(String password) {
    final value = password.trim().toLowerCase();
    if (value.isEmpty) return false;
    if (_commonWeakPasswords.contains(value)) return true;
    // 纯重复字符（aaaaaa / 111111）。
    if (value.split('').toSet().length == 1) return true;
    // 纯递增/递减数字（123456 / 654321）。
    if (RegExp(r'^\d+$').hasMatch(value)) {
      var ascending = true;
      var descending = true;
      for (var i = 1; i < value.length; i++) {
        final prev = value.codeUnitAt(i - 1);
        final cur = value.codeUnitAt(i);
        if (cur != prev + 1) ascending = false;
        if (cur != prev - 1) descending = false;
      }
      if (ascending || descending) return true;
    }
    return false;
  }

  /// 校验新密码，返回错误提示文案；合法时返回 null。
  static String? validateNewPassword(String password, String confirm) {
    final value = password.trim();
    if (value.isEmpty) return '新密码不能为空';
    if (value.length < minPasswordLength || value.length > maxPasswordLength) {
      return '新密码需为 $minPasswordLength-$maxPasswordLength 位';
    }
    if (password.trim() != confirm.trim()) return '两次输入的新密码不一致';
    if (isWeakPassword(value)) return '密码过于简单，请换一个更复杂的密码';
    return null;
  }
}
