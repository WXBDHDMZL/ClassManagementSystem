/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-10-01
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// 原子写文件：同一目标的写入串行化 + "唯一临时文件 → rename 覆盖"。
///
/// 背景（P1-4/N4 修复）：此前的写法是"先 delete 主文件、再 rename"，实测 25/25 次
/// 存在主文件短暂不存在的时间窗，此刻掉电/进程被杀主文件即消失。经实验验证
/// Dart 的 `File.rename` 在 Windows 上可直接覆盖已存在文件，因此**不再需要删除**。
class AtomicFile {
  AtomicFile._();

  /// 测试专用：rename 故障注入（null = 正常执行 `temp.rename(path)`）。
  ///
  /// 用途（审查 L10）："写入中断"是数据安全的核心不变量，此前无任何守护。
  /// 测试可让注入实现在前若干次抛 [FileSystemException]（模拟杀软/索引器占用）、
  /// 之后放行，或**始终抛出**验证"原文件不被截断 + 临时文件被清理 + 异常上抛"。
  @visibleForTesting
  static Future<void> Function(File tempFile, String targetPath)?
      debugRenameOverride;

  static final Map<String, Future<void>> _queues = <String, Future<void>>{};

  /// 原子写入文本：同一 [path] 的多次调用按顺序串行执行。
  static Future<void> writeString(String path, String content) {
    return _write(path, () async {
      await _ensureParent(path);
      final temp = File(
        '$path.${DateTime.now().microsecondsSinceEpoch}'
        '${DateTime.now().microsecond}.tmp',
      );
      await temp.writeAsString(content, flush: true);
      await _renameWithRetry(temp, path);
    });
  }

  /// 原子写入字节。
  static Future<void> writeBytes(String path, List<int> bytes) {
    return _write(path, () async {
      await _ensureParent(path);
      final temp = File(
        '$path.${DateTime.now().microsecondsSinceEpoch}'
        '${DateTime.now().microsecond}.tmp',
      );
      await temp.writeAsBytes(bytes, flush: true);
      await _renameWithRetry(temp, path);
    });
  }

  /// 原子复制：把 [sourcePath] 复制到 [destPath]（同目标写入串行化 + 临时文件 rename）。
  ///
  /// G-21：备份 `.bak` 此前用 `file.copy` 直接覆盖，中途掉电/进程被杀会留下**截断的
  /// .bak**；下次主文件损坏时它解析失败，等于丢掉最后一份可用备份。
  static Future<void> copyAtomic(String sourcePath, String destPath) {
    return _write(destPath, () async {
      await _ensureParent(destPath);
      final temp = File(
        '$destPath.${DateTime.now().microsecondsSinceEpoch}'
        '${DateTime.now().microsecond}.tmp',
      );
      await File(sourcePath).copy(temp.path);
      await _renameWithRetry(temp, destPath);
    });
  }

  /// 目标目录不存在时先建：目录被清理/首次运行/路径切换后，
  /// 否则临时文件写入直接抛 `PathNotFoundException`，本次保存静默失败。
  static Future<void> _ensureParent(String path) async {
    final parent = File(path).parent;
    if (!await parent.exists()) await parent.create(recursive: true);
  }

  static Future<void> _write(String path, Future<void> Function() task) {
    final previous = _queues[path] ?? Future<void>.value();
    final run = previous.then((_) => task());
    // 队尾兜底：任何一次失败都不阻断后续写入。
    final tail = run.then((_) {}, onError: (_) {});
    _queues[path] = tail;
    // G-22：队尾完成后若仍是本队尾（期间没有更新写入入队）就移除该条目 —— 此前
    // `_queues` 只增不删，按时间戳生成临时路径的调用方会让 Map 无限增长。
    tail.whenComplete(() {
      if (identical(_queues[path], tail)) _queues.remove(path);
    });
    return run;
  }

  /// Windows 上目标文件可能被杀毒软件/索引器短暂占用导致 rename 拒绝访问，
  /// 这里做有限次退避重试（实测 errno=5 为偶发）。
  static Future<void> _renameWithRetry(File temp, String path) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final override = debugRenameOverride;
        if (override != null) {
          await override(temp, path);
        } else {
          await temp.rename(path);
        }
        return;
      } on FileSystemException {
        if (attempt >= 5) {
          // 修复（1.30）：重试耗尽后清掉临时文件 —— 此前每次保存失败都在
          // 文档目录留下一个 .tmp（被杀毒软件占用时反复失败会持续堆积）。
          try {
            if (await temp.exists()) await temp.delete();
          } catch (_) {
            // 清理失败不影响主流程。
          }
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
      }
    }
  }
}
