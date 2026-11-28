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
    // 审计 P2-10：此前是「exists() 检查 → 写临时文件 → rename」，两个实例
    // 同时首启会各自生成一把钥并先后 rename，最后落盘的钥与先启动实例
    // 内存里的钥不同 —— 先启动的那个实例此后写出的数据下次启动就解不开。
    // 这里改用**独占创建**占住 key 文件路径：抢到的实例写入自己的钥，
    // 没抢到的实例丢弃刚生成的钥、改读磁盘上已有的那把。
    if (await _reserveKeyFile()) {
      await _write(key);
      return key;
    }
    return _readExisting();
  }

  /// 以独占方式创建密钥文件占位；已存在则返回 false（说明另一个实例先到）。
  Future<bool> _reserveKeyFile() async {
    await keyFile.parent.create(recursive: true);
    try {
      await keyFile.create(exclusive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<Uint8List> _readExisting() async {
    // 占位与写入之间有一个极短的空文件窗口：另一个实例此刻读到空文件会误判
    // 为「密钥损坏」。这里短暂重试，把瞬时窗口与真正的空文件区分开。
    var raw = (await keyFile.readAsString()).trim();
    for (var attempt = 0; attempt < 5 && raw.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      raw = (await keyFile.readAsString()).trim();
    }
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
