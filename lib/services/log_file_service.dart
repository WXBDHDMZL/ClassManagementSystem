/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-14
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'atomic_file.dart';
import 'encrypted_text_file.dart';
import 'local_storage_paths.dart';

/// 运行日志单文件：把操作日志与错误日志合并存进
/// `文档/班级管理系统/日志/班级管理系统_日志.txt`。
///
/// 每条日志单独以 LRX3 加密成一行，行首带类别标记：
/// - `[操作] YYYY-MM-DD HH:MM:SS  动作  明细`
/// - `[错误] ─────… / 时间  …`
///
/// 这样只有一份文件，既便于查看与备份，也不会随月份增加文件数量。
/// 防误删采用两层：日志文件与日志目录加“拒绝删除”ACL（拒绝 DE / DC，
/// 不影响读写），同时运行期间保持文件句柄；程序自己的重写/清理先临时解除。
class LogFileService {
  LogFileService._();

  /// 合并后的日志文件名。
  static const String fileName = '班级管理系统_日志.txt';

  static const String categoryOperation = '操作';
  static const String categoryError = '错误';

  static const String prefixOperation = '[操作] ';
  static const String prefixError = '[错误] ';

  /// 测试专用：关闭 Windows ACL 加固，避免在临时目录执行 icacls。
  @visibleForTesting
  static bool disableProtectionForTests = false;

  /// 目录下的合并日志文件（不创建目录/文件）。
  static File fileIn(Directory directory) {
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  /// 文档目录中的合并日志文件。
  static Future<File> defaultFile() async {
    final directory = await LocalStoragePaths.logDirectory();
    return fileIn(directory);
  }

  /// 串行队列：操作日志、错误日志、迁移与清理共用同一把锁，
  /// 避免两个写队列同时改同一份文件。
  static Future<void> _queue = Future<void>.value();

  /// 等待当前排队中的日志写入全部完成（测试/退出前用）。
  static Future<void> flush() => _queue;

  /// 追加一条日志。
  static Future<void> append(File file, String prefix, String text) {
    final plain = '$prefix${text.trimRight()}';
    return _serialize(() async {
      await file.parent.create(recursive: true);
      await EncryptedTextFile.appendLine(file, plain);
      await _hold(file);
      await _protect(file);
    });
  }

  /// 读取某一类日志（旧→新顺序）。
  static Future<List<String>> readEntries(File file, String prefix) async {
    if (!await file.exists()) return const [];
    final lines = await EncryptedTextFile.readLines(file);
    return lines
        .where((line) => line.startsWith(prefix))
        .map((line) => line.substring(prefix.length))
        .toList();
  }

  /// 导出某一类日志的明文（旧→新，整份）。
  static Future<String> exportText(File file, String prefix) async {
    final entries = await readEntries(file, prefix);
    return entries.isEmpty ? '' : '${entries.join('\n')}\n';
  }

  /// 删除 [cutoff] 之前的日志条目；[category] 为 null 时操作/错误一起清理。
  /// 返回删除的条目数。
  static Future<int> pruneBefore(
    File file,
    DateTime cutoff, {
    String? category,
  }) {
    return _serialize(() async {
      if (!await file.exists()) return 0;
      final parsed = await EncryptedTextFile.readLinesDetailed(file);
      if (parsed.hasUndecodableLines) {
        // 审计 P2-3：坏行不能被永久抹掉，但也不能因此让整份日志永不收缩。
        // 逐行处理：可解密行按截止时间清理，无法解密的坏行原样保留。
        final keptRaw = <String>[];
        var removed = 0;
        for (final raw in parsed.rawLines) {
          final entry = EncryptedTextFile.decodeLine(raw);
          if (entry == null) {
            keptRaw.add(raw);
            continue;
          }
          final entryCategory = _categoryOf(entry);
          if (category != null && entryCategory != category) {
            keptRaw.add(raw);
            continue;
          }
          final time = _entryTime(entry);
          if (time != null && time.isBefore(cutoff)) {
            removed++;
            continue;
          }
          keptRaw.add(raw);
        }
        if (removed > 0) {
          await _rewriteRaw(file, keptRaw);
        }
        return removed;
      }
      final entries = parsed.lines;
      final kept = <String>[];
      var removed = 0;
      for (final entry in entries) {
        final entryCategory = _categoryOf(entry);
        if (category != null && entryCategory != category) {
          kept.add(entry);
          continue;
        }
        final time = _entryTime(entry);
        if (time != null && time.isBefore(cutoff)) {
          removed++;
          continue;
        }
        kept.add(entry);
      }
      if (removed > 0) {
        await _rewrite(file, kept);
      }
      return removed;
    });
  }

  /// 把备份旁的日志快照合并进当前日志（从备份恢复时可选）。
  ///
  /// 只追加当前日志中不存在的条目，不删除、不覆盖现有条目；
  /// 合并后按日志内的时间戳排序。返回新增条数。
  static Future<int> mergeSnapshot(File snapshot, {File? target}) {
    return _serialize(() async {
      if (!await snapshot.exists()) return 0;
      final file = target ?? await defaultFile();
      final incoming = await EncryptedTextFile.readLines(snapshot);
      if (incoming.isEmpty) return 0;
      if (await file.exists()) {
        final parsed = await EncryptedTextFile.readLinesDetailed(file);
        if (parsed.hasUndecodableLines) {
          debugPrint(
            '日志文件有 ${parsed.skippedLines} 行无法解密，已跳过本次快照合并：${file.path}',
          );
          return 0;
        }
      }
      final existing = await file.exists()
          ? (await EncryptedTextFile.readLinesDetailed(file)).lines
          : <String>[];
      final seen = existing.map((line) => line.trimRight()).toSet();
      final entries = <_PendingEntry>[];
      for (var i = 0; i < existing.length; i++) {
        entries.add(_PendingEntry(existing[i], i));
      }
      var order = entries.length;
      var added = 0;
      for (final line in incoming) {
        final normalized = line.trimRight();
        if (normalized.isEmpty) continue;
        if (!seen.add(normalized)) continue;
        entries.add(_PendingEntry(normalized, order++));
        added++;
      }
      if (added == 0) return 0;
      _sortByTime(entries);
      await _rewrite(file, entries.map((entry) => entry.text).toList());
      return added;
    });
  }

  /// 删除合并日志文件（恢复出厂“同时清除日志”用）。
  static Future<bool> deleteFile(File file) {
    return _serialize(() async {
      // 先释放句柄：文件可能已被外部删除，句柄仍指向旧路径。
      await _releaseGuard();
      if (!await file.exists()) return false;
      await _unprotect(file);
      try {
        await file.delete();
        return true;
      } on Object catch (e) {
        debugPrint('删除日志文件失败：${file.path}：$e');
        return false;
      }
    });
  }

  /// 删除全部日志：合并日志文件与 `历史归档_*` 旧日志目录。
  /// 返回删除的文件/目录数量。
  static Future<int> deleteAllLogs(Directory directory) {
    return _serialize(() async {
      var removed = 0;
      final file = fileIn(directory);
      // 先解除文件与日志目录的防删除保护，否则删除会被系统拒绝。
      await _releaseGuard();
      await _unprotect(file);
      if (await file.exists()) {
        try {
          await file.delete();
          removed++;
        } on Object catch (e) {
          debugPrint('删除日志文件失败：${file.path}：$e');
        }
      }
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is! Directory) continue;
          // Directory 的 uri 以 '/' 结尾，最后一段是空字符串，需跳过。
          final name = entity.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
            orElse: () => '',
          );
          if (!name.startsWith('历史归档_')) continue;
          try {
            await entity.delete(recursive: true);
            removed++;
          } on Object catch (e) {
            debugPrint('删除旧日志归档失败：${entity.path}：$e');
          }
        }
      }
      return removed;
    });
  }

  /// 运行期间持有的日志文件句柄：Windows 上只要文件被打开且未共享删除，
  /// 其他程序（资源管理器、cmd del）就无法删除它，作为 ACL 之外的第二层。
  /// 程序正常退出或重写/清理日志前会主动释放，不影响自身维护。
  static RandomAccessFile? _guard;
  static String? _guardPath;

  /// 已加固的日志文件与日志目录（避免每条日志都调用 icacls）。
  static final Set<String> _protectedFiles = <String>{};
  static final Set<String> _protectedDirs = <String>{};

  /// 给日志文件加“拒绝删除”ACL：
  /// - 文件拒绝 `DE`（删除）：右键删除、`del` 都会提示拒绝访问；
  /// - 日志目录拒绝 `DC`（删除子项）：否则同账号可借父目录的删除子项权限绕过。
  /// 只拒绝删除权限，不拒绝同步/读取/写入，程序仍可正常追加与读取。
  static Future<void> _protect(File file) async {
    if (disableProtectionForTests || !Platform.isWindows) return;
    final user = Platform.environment['USERNAME'];
    if (user == null || user.isEmpty) return;
    final path = file.path;
    final directoryPath = file.parent.path;
    if (!_protectedFiles.contains(path) && await file.exists()) {
      // 先清掉本账号旧的拒绝项，避免程序重启后重复叠加。
      await _icacls(<String>[path, '/remove:d', user]);
      if (await _icacls(<String>[path, '/deny', '$user:(DE)'])) {
        _protectedFiles.add(path);
      }
    }
    if (!_protectedDirs.contains(directoryPath) && await file.parent.exists()) {
      await _icacls(<String>[directoryPath, '/remove:d', user]);
      if (await _icacls(<String>[directoryPath, '/deny', '$user:(DC)'])) {
        _protectedDirs.add(directoryPath);
      }
    }
  }

  /// 临时解除“拒绝删除”保护，供程序自己重写/清理日志。
  /// [file] 不存在时也会清理目录上的保护（上次运行可能已加过）。
  static Future<void> _unprotect(File file) async {
    if (disableProtectionForTests || !Platform.isWindows) return;
    final user = Platform.environment['USERNAME'];
    if (user == null || user.isEmpty) return;
    _protectedFiles.remove(file.path);
    _protectedDirs.remove(file.parent.path);
    await _icacls(<String>[file.path, '/remove:d', user]);
    await _icacls(<String>[file.parent.path, '/remove:d', user]);
  }

  static Future<bool> _icacls(List<String> arguments) async {
    try {
      final result = await Process.run('icacls', arguments);
      return result.exitCode == 0;
    } on Object catch (e) {
      debugPrint('设置日志防删除保护失败：$e');
      return false;
    }
  }

  static Future<void> _hold(File file) async {
    if (disableProtectionForTests || !Platform.isWindows) return;
    if (_guardPath == file.path && _guard != null) return;
    await _releaseGuard();
    try {
      if (!await file.exists()) return;
      _guard = await file.open(mode: FileMode.append);
      _guardPath = file.path;
    } on Object catch (e) {
      debugPrint('持有日志文件失败：$e');
    }
  }

  /// 释放句柄，供程序自身重写/清理日志。
  static Future<void> _releaseGuard() async {
    final guard = _guard;
    _guard = null;
    _guardPath = null;
    if (guard == null) return;
    try {
      await guard.close();
    } on Object catch (e) {
      debugPrint('释放日志文件句柄失败：$e');
    }
  }

  static Future<void> _rewrite(File file, List<String> entries) async {
    await _releaseGuard();
    await _unprotect(file);
    final content = entries.isEmpty
        ? ''
        : '${entries.map(EncryptedTextFile.encodeLine).join('\n')}\n';
    try {
      await AtomicFile.writeString(file.path, content);
    } finally {
      // 即使写入失败，也要恢复句柄与 ACL；否则日志文件会处于“无保护”状态，
      // 且后续 append 可能对着已失效的旧句柄写。
      await _hold(file);
      await _protect(file);
    }
  }

  /// 按原始密文行重写日志；坏行原样保留，不做二次加密。
  static Future<void> _rewriteRaw(File file, List<String> rawLines) async {
    await _releaseGuard();
    await _unprotect(file);
    try {
      await EncryptedTextFile.rewriteRawLines(file, rawLines);
    } finally {
      await _hold(file);
      await _protect(file);
    }
  }

  static String _categoryOf(String entry) =>
      entry.startsWith(prefixError) ? categoryError : categoryOperation;

  /// 按日志内的时间戳排序（同一时间保持原有顺序；无时间戳的排最后）。
  static void _sortByTime(List<_PendingEntry> entries) {
    entries.sort((a, b) {
      final left = _entryTime(a.text);
      final right = _entryTime(b.text);
      if (left == null && right == null) return a.order.compareTo(b.order);
      if (left == null) return 1;
      if (right == null) return -1;
      final byTime = left.compareTo(right);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });
  }

  static DateTime? _entryTime(String entry) {
    final match = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(entry);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  static Future<T> _serialize<T>(Future<T> Function() action) {
    // 用一条 Future 链排队；上一个任务失败不影响后续任务。
    final previous = _queue;
    final result = previous.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

class _PendingEntry {
  _PendingEntry(this.text, this.order);

  final String text;
  final int order;
}
