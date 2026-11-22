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
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'storage_crypto.dart';

/// 便携备份的密钥信封。
///
/// 数据密钥本身仍由 LRX3 文件使用；这里额外用备份口令派生的密钥把它包一层，
/// 这样把 `.enc` 与 `.pkey` 一起拷到另一台机器后，输入备份口令即可解出数据密钥。
/// 信封不包含明文密钥；口令错误时 LRX3 的 HMAC 校验会失败。
class BackupCrypto {
  static const String envelopeFormat = 'LRBK';
  static const int _iterations = 120000;
  static const int _saltLength = 16;

  /// 用 [password] 包裹 32 字节 [dataKey]，返回 JSON 信封。
  static String wrapKey(Uint8List dataKey, String password) {
    if (dataKey.length != 32) {
      throw ArgumentError('数据密钥必须是 32 字节');
    }
    final salt = _randomBytes(_saltLength);
    final kek = _pbkdf2(utf8.encode(password), salt, _iterations);
    final wrapped = StorageCrypto.encodeV3(base64Encode(dataKey), kek);
    return jsonEncode({
      'format': envelopeFormat,
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'wrapped': wrapped,
    });
  }

  /// 解出口令包裹的数据密钥；口令错误/信封损坏返回 null。
  static Uint8List? unwrapKey(String envelope, String password) {
    try {
      final decoded = jsonDecode(envelope.trim());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['format'] != envelopeFormat) return null;
      final iterations = decoded['iterations'];
      if (iterations is! int || iterations < 10000 || iterations > 500000) {
        return null;
      }
      final salt = base64Decode(decoded['salt'] as String);
      if (salt.length != _saltLength) return null;
      final wrapped = decoded['wrapped'];
      if (wrapped is! String) return null;
      final kek = _pbkdf2(utf8.encode(password), salt, iterations);
      final plain = StorageCrypto.decodeV3(wrapped, kek);
      if (plain == null) return null;
      final key = base64Decode(plain);
      return key.length == 32 ? key : null;
    } on Object catch (_) {
      return null;
    }
  }

  static Uint8List _pbkdf2(List<int> password, Uint8List salt, int iterations) {
    final hmac = Hmac(sha256, password);
    final block = <int>[...salt, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
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
