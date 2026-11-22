/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// LRX3 文件格式的纯 Dart 实现。
///
/// 5.0 主程序只支持 LRX3；LRX2 仅保留魔数识别，用于明确拒绝旧数据。
class StorageCrypto {
  StorageCrypto._();

  static const List<int> magicV2 = [0x4C, 0x52, 0x58, 0x32]; // "LRX2"
  static const List<int> magicV3 = [0x4C, 0x52, 0x58, 0x33]; // "LRX3"
  static const int saltLength = 16;
  static const int nonceLength = 16;
  static const int tagLength = 32;
  static const int blockSize = 32;

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// 当前版本（LRX3）：每条文件使用独立随机盐/随机数，密钥来自本机随机
  /// 数据密钥（DPAPI 保护）。HMAC 标签覆盖头部与密文。
  static String encodeV3(String plainText, Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', '数据密钥必须是 32 字节');
    }
    final salt = randomBytes(saltLength);
    final nonce = randomBytes(nonceLength);
    final (encKey, macKey) = _deriveSubKeysV3(key, salt);
    final data = Uint8List.fromList(utf8.encode(plainText));
    final stream = _keystream(encKey, salt, nonce, data.length);
    final cipher = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      cipher[i] = data[i] ^ stream[i];
    }
    final body = Uint8List.fromList([...magicV3, ...salt, ...nonce, ...cipher]);
    final tag = Hmac(sha256, macKey).convert(body).bytes;
    return base64Encode([...body, ...tag]);
  }

  static String? decodeV3(String encodedText, Uint8List key) {
    try {
      final bytes = base64Decode(encodedText.trim());
      if (!isV3(bytes)) return null;
      if (bytes.length < 4 + saltLength + nonceLength + tagLength) return null;
      final body = bytes.sublist(0, bytes.length - tagLength);
      final tag = bytes.sublist(bytes.length - tagLength);
      final salt = Uint8List.fromList(bytes.sublist(4, 4 + saltLength));
      final nonce = Uint8List.fromList(
        bytes.sublist(4 + saltLength, 4 + saltLength + nonceLength),
      );
      final cipher = bytes.sublist(
        4 + saltLength + nonceLength,
        bytes.length - tagLength,
      );
      final (encKey, macKey) = _deriveSubKeysV3(key, salt);
      final expected = Hmac(sha256, macKey).convert(body).bytes;
      if (!constantTimeEquals(expected, tag)) return null;
      final stream = _keystream(encKey, salt, nonce, cipher.length);
      final plain = Uint8List(cipher.length);
      for (var i = 0; i < cipher.length; i++) {
        plain[i] = cipher[i] ^ stream[i];
      }
      return utf8.decode(plain);
    } on Object catch (_) {
      return null;
    }
  }

  static bool isV2(List<int> bytes) =>
      bytes.length >= magicV2.length && _startsWith(bytes, magicV2);

  static bool isV3(List<int> bytes) =>
      bytes.length >= magicV3.length && _startsWith(bytes, magicV3);

  static bool looksEncrypted(String text) {
    try {
      final bytes = base64Decode(text.trim());
      return isV2(bytes) || isV3(bytes);
    } on FormatException catch (_) {
      return false;
    }
  }

  static (Uint8List, Uint8List) _deriveSubKeysV3(
    Uint8List key,
    Uint8List salt,
  ) {
    final master = Hmac(sha256, key).convert([...utf8.encode('lrx3'), ...salt]).bytes;
    final encKey = Uint8List.fromList(
      Hmac(sha256, master).convert(utf8.encode('enc')).bytes,
    );
    final macKey = Uint8List.fromList(
      Hmac(sha256, master).convert(utf8.encode('mac')).bytes,
    );
    return (encKey, macKey);
  }

  static Uint8List _keystream(
    Uint8List encKey,
    Uint8List salt,
    Uint8List nonce,
    int length,
  ) {
    final result = Uint8List(length);
    final prefix = Uint8List.fromList([...salt, ...nonce]);
    var offset = 0;
    var counter = 0;
    while (offset < length) {
      final block = Hmac(
        sha256,
        encKey,
      ).convert([...prefix, ..._uint32(counter)]).bytes;
      for (var i = 0; i < blockSize && offset < length; i++, offset++) {
        result[offset] = block[i];
      }
      counter++;
    }
    return result;
  }

  static List<int> _uint32(int value) => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

  static bool _startsWith(List<int> bytes, List<int> magic) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
