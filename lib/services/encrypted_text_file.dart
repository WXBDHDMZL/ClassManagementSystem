/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';
import 'atomic_file.dart';

/// 加密文本文件：与主数据文件相同的 LRX3 方案，用于操作日志/错误日志。
///
/// - 每条“记录”单独加密后以一行 Base64 写入；只追加一行，不重写整份；
/// - 读取时逐行解密；无法解密的行会被跳过；
/// - 错误日志一个条目本身是多行文本，加密后仍是一行密文。
class EncryptedTextFileContent {
  const EncryptedTextFileContent(
    this.lines,
    this.skippedLines, {
    this.rawLines = const [],
  });

  final List<String> lines;
  final int skippedLines;

  /// 原始密文行（与 [lines] 不同：包含无法解密的坏行），供安全重写时保留坏行。
  final List<String> rawLines;

  bool get hasUndecodableLines => skippedLines > 0;
}

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

  /// 解密单行；无法解密返回 null。供日志清理保留坏行时复用。
  static String? decodeLine(String line) => _decode(line);

  /// 按原始密文行重写文件；坏行原样保留，不做二次加密。
  static Future<void> rewriteRawLines(
    File file,
    List<String> rawLines,
  ) async {
    await file.parent.create(recursive: true);
    final content = rawLines.isEmpty ? '' : '${rawLines.join('\n')}\n';
    await AtomicFile.writeString(file.path, content);
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
  /// 调用方在重写整份文件前应改用 [readLinesDetailed]，避免把坏行永久抹掉。
  static Future<List<String>> readLines(File file) async {
    final result = await readLinesDetailed(file);
    return result.lines;
  }

  /// 逐行解密读取，并返回无法解密的坏行数量（审计 P2-3）。
  static Future<EncryptedTextFileContent> readLinesDetailed(File file) async {
    if (!await file.exists()) {
      return const EncryptedTextFileContent(<String>[], 0);
    }
    final content = await file.readAsString();
    final result = <String>[];
    final rawLines = <String>[];
    var skipped = 0;
    for (final raw in content.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      rawLines.add(line);
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
    return EncryptedTextFileContent(result, skipped, rawLines: rawLines);
  }

  /// 读取整份文本（用于日志导出）。
  /// 有坏行时在导出内容顶部留一行提示，避免用户以为日志完整。
  static Future<String> readAllText(File file) async {
    final content = await readLinesDetailed(file);
    final lines = content.lines;
    if (content.skippedLines > 0) {
      lines.insert(0, '[导出提示] 有 ${content.skippedLines} 行日志无法解密，已跳过。');
    }
    return lines.isEmpty ? '' : '${lines.join('\n')}\n';
  }
}
