/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'dpapi.dart';

/// 本机 LRX3 数据密钥的持久化。
///
/// 文件格式：`base64("LRK1" + DPAPI(32 字节随机密钥))`。
/// - 密钥只在当前 Windows 用户 + 当前机器上可解；
/// - 文件缺失时生成新钥；文件存在但损坏时**拒绝重建**，避免把旧数据
///   误判成新库后覆盖。
class StorageKeyStore {
  StorageKeyStore(this.keyFile);

  final File keyFile;

  static const List<int> _magic = [0x4C, 0x52, 0x4B, 0x31]; // LRK1
  static const int keyLength = 32;

  Future<Uint8List> loadOrCreate({bool createIfMissing = true}) async {
    if (await keyFile.exists()) {
      return _readExisting();
    }
    if (!createIfMissing) {
      throw const FormatException('数据密钥文件不存在，已停止启动以保护现有数据');
    }
    final key = Uint8List.fromList(
      List<int>.generate(
        keyLength,
        (_) => Random.secure().nextInt(256),
      ),
    );
    await _write(key);
    return key;
  }

  Future<Uint8List> _readExisting() async {
    final raw = (await keyFile.readAsString()).trim();
    if (raw.isEmpty) {
      throw const FormatException('数据密钥文件为空，已停止启动以保护现有数据');
    }
    try {
      final bytes = base64Decode(raw);
      if (bytes.length <= _magic.length ||
          !_startsWith(bytes, _magic)) {
        throw const FormatException('数据密钥文件格式不正确');
      }
      final clear = Dpapi.unprotect(bytes.sublist(_magic.length));
      if (clear.length != keyLength) {
        throw const FormatException('数据密钥长度不正确');
      }
      return clear;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('数据密钥无法用当前 Windows 用户解密：$error');
    }
  }

  Future<void> _write(Uint8List key) async {
    final protected = Dpapi.protect(key);
    final encoded = base64Encode([..._magic, ...protected]);
    await keyFile.parent.create(recursive: true);
    final temp = File('${keyFile.path}.tmp');
    try {
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(keyFile.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  static bool _startsWith(List<int> bytes, List<int> magic) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
