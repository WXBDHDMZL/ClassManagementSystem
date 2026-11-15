/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// 加密文本文件：与主数据文件相同的 LRX2 方案，用于操作日志/错误日志。
///
/// - 每条“记录”单独加密后以一行 Base64 写入；只追加一行，不重写整份；
/// - 读取时逐行解密；无法解密的行会被跳过；
/// - 错误日志一个条目本身是多行文本，加密后仍是一行密文。
class EncryptedTextFile {
  EncryptedTextFile._();

  static String _encode(String plain) => StorageService.encodeLocalText(plain);

  /// 把一条明文加密成一行密文（供单文件日志整体重写）。
  static String encodeLine(String plain) => _encode(plain);

  static String? _decode(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    return StorageService.decodeLocalText(trimmed);
  }

  /// 追加一条记录。
  static Future<void> appendLine(File file, String plainLine) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${_encode(plainLine)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// 逐行解密读取。无法解密的行会被跳过并写一条 debug 日志。
  static Future<List<String>> readLines(File file) async {
    if (!await file.exists()) return <String>[];
    final content = await file.readAsString();
    final result = <String>[];
    var skipped = 0;
    for (final raw in content.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      final decoded = _decode(line);
      if (decoded != null) {
        result.add(decoded);
      } else {
        skipped++;
      }
    }
    if (skipped > 0) {
      debugPrint('加密文本有 $skipped 行无法解密，已跳过：${file.path}');
    }
    return result;
  }

  /// 读取整份文本（用于日志导出）。
  static Future<String> readAllText(File file) async {
    final lines = await readLines(file);
    return lines.isEmpty ? '' : '${lines.join('\n')}\n';
  }
}
