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

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'storage_crypto.dart';

/// 便携备份的密钥信封。
///
/// 数据密钥本身仍由 LRX3 文件使用；这里额外用备份口令派生的密钥把它包一层，
/// 这样把 `.enc` 与 `.pkey` 一起拷到另一台机器后，输入备份口令即可解出数据密钥。
/// 信封不包含明文密钥；口令错误时 LRX3 的 HMAC 校验会失败。
class BackupCrypto {
  static const String envelopeFormat = 'LRBK';

  /// 当前写入新备份时使用的 PBKDF2 迭代数。
  static const int iterations = 120000;

  /// 允许读入的最低迭代数：低于此值的信封视为不可信（可能是伪造或被削弱）。
  static const int minIterations = 10000;

  /// 允许读入的最高迭代数：防止被篡改成天文数字后把恢复流程卡死。
  static const int maxIterations = 500000;

  static const int _saltLength = 16;

  /// 读取信封声明的迭代数；信封损坏时返回 null。
  static int? iterationsOf(String envelope) {
    try {
      final decoded = jsonDecode(envelope.trim());
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded['iterations'];
      return value is int ? value : null;
    } on Object catch (_) {
      return null;
    }
  }

  /// 信封的 PBKDF2 迭代数是否低于当前标准（旧备份，强度较弱）。
  ///
  /// 审计 A-20：旧版本写出的备份可能只有几万轮，恢复时不能因为"强度不够"
  /// 直接作废（那会让用户的合法旧备份永远打不开），但必须让用户与日志
  /// 知道这份备份的保护强度偏低。
  static bool isWeakEnvelope(String envelope) {
    final declared = iterationsOf(envelope);
    if (declared == null) return false;
    return declared < iterations;
  }

  /// 用 [password] 包裹 32 字节 [dataKey]，返回 JSON 信封。
  static String wrapKey(Uint8List dataKey, String password) {
    if (dataKey.length != 32) {
      throw ArgumentError('数据密钥必须是 32 字节');
    }
    final salt = _randomBytes(_saltLength);
    final kek = _pbkdf2(utf8.encode(password), salt, iterations);
    final wrapped = StorageCrypto.encodeV3(base64Encode(dataKey), kek);
    return jsonEncode({
      'format': envelopeFormat,
      'iterations': iterations,
      'salt': base64Encode(salt),
      'wrapped': wrapped,
    });
  }

  /// 用指定迭代数包裹数据密钥，仅用于测试"旧版本写出的弱信封仍可恢复"。
  @visibleForTesting
  static String wrapKeyForTest(
    Uint8List dataKey,
    String password, {
    required int rounds,
  }) {
    if (dataKey.length != 32) {
      throw ArgumentError('数据密钥必须是 32 字节');
    }
    final salt = _randomBytes(_saltLength);
    final kek = _pbkdf2(utf8.encode(password), salt, rounds);
    final wrapped = StorageCrypto.encodeV3(base64Encode(dataKey), kek);
    return jsonEncode({
      'format': envelopeFormat,
      'iterations': rounds,
      'salt': base64Encode(salt),
      'wrapped': wrapped,
    });
  }

  /// 与 [wrapKey] 相同，但在后台 isolate 里跑 PBKDF2。
  ///
  /// 审计 A-20：12 万轮 PBKDF2 在 UI isolate 同步执行会让"创建便携备份"
  /// 卡住整个界面（低配机可达数百毫秒到数秒）。UI 侧一律走这个入口。
  static Future<String> wrapKeyAsync(Uint8List dataKey, String password) {
    final keyCopy = Uint8List.fromList(dataKey);
    return Isolate.run(() => wrapKey(keyCopy, password));
  }

  /// 解出口令包裹的数据密钥；口令错误/信封损坏返回 null。
  static Uint8List? unwrapKey(String envelope, String password) {
    try {
      final decoded = jsonDecode(envelope.trim());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['format'] != envelopeFormat) return null;
      final declared = decoded['iterations'];
      if (declared is! int ||
          declared < minIterations ||
          declared > maxIterations) {
        return null;
      }
      final declaredIterations = declared;
      final salt = base64Decode(decoded['salt'] as String);
      if (salt.length != _saltLength) return null;
      final wrapped = decoded['wrapped'];
      if (wrapped is! String) return null;
      final kek = _pbkdf2(utf8.encode(password), salt, declaredIterations);
      final plain = StorageCrypto.decodeV3(wrapped, kek);
      if (plain == null) return null;
      final key = base64Decode(plain);
      return key.length == 32 ? key : null;
    } on Object catch (_) {
      return null;
    }
  }

  /// 与 [unwrapKey] 相同，但在后台 isolate 里跑 PBKDF2（审计 A-20）。
  static Future<Uint8List?> unwrapKeyAsync(String envelope, String password) =>
      Isolate.run(() => unwrapKey(envelope, password));

  static Uint8List _pbkdf2(List<int> password, Uint8List salt, int rounds) {
    final hmac = Hmac(sha256, password);
    final block = <int>[...salt, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
