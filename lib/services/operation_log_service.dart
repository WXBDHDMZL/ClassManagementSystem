/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/app_date.dart';
import 'error_log_service.dart';
import 'local_storage_paths.dart';
import 'log_file_service.dart';
import 'storage_service.dart';
import '../utils/app_clock.dart';

/// 操作日志：把关键数据操作（新增/删除记录、考勤登记、名单与原因改动、
/// 导入导出、备份恢复等）按时间写入文档目录下的《班级管理系统_日志.txt》。
/// 用于事后核对"某条数据什么时候被谁改/删了"，排查问题时也能对时间线。
///
/// 操作日志与错误日志共用同一份加密文件，行首用 `[操作]` / `[错误]` 区分。
class OperationLogService {
  OperationLogService._();

  /// 日志文件基名（展示用）。
  static const String fileBaseName = '班级管理系统_操作日志';

  /// 指定时间对应的日志文件名（现已合并为单一文件）。
  static String fileNameFor(DateTime time) => LogFileService.fileName;

  /// 合并日志的文件名（兼容既有引用）。
  static String get fileName => LogFileService.fileName;

  /// 串行写队列：保证日志顺序与调用顺序一致。
  static Future<void> _queue = Future<void>.value();

  /// 记录一条操作（异步排队写盘；任何失败都静默，不影响主流程）。
  static void log(String action, [String detail = '']) {
    final line = formatLogLine(AppClock.now(), action, detail);
    _queue = _queue.then((_) => _appendLine(line));
  }

  /// 等待已排队的日志写入完成（退出/删除日志前调用）。
  static Future<void> flush() async {
    await _queue;
    await LogFileService.flush();
  }

  /// 测试专用：覆盖日志目录（生产环境为 `文档/班级管理系统/日志`）。
  @visibleForTesting
  static Directory? debugDirectoryOverride;

  static Future<Directory> _logDirectory() async {
    final override = debugDirectoryOverride;
    if (override != null) return override;
    return LocalStoragePaths.logDirectory();
  }

  /// 合并日志文件路径（界面展示/打开所在目录用）。
  static Future<String> filePath() async {
    final directory = await _logDirectory();
    return LogFileService.fileIn(directory).path;
  }

  /// 合并日志文件（不存在时返回空列表）。
  static Future<List<File>> allLogFiles() async {
    try {
      final file = LogFileService.fileIn(await _logDirectory());
      return await file.exists() ? [file] : const [];
    } catch (e) {
      debugPrint('枚举操作日志文件失败：$e');
      return const [];
    }
  }

  /// 界面展示的行数上限（修复 6.10，2026-10-03 审查）。
  ///
  /// 日志文件本身**全量保留、不截断**（这是既定约定）；这里限制的只是
  /// "一次读进内存给界面看多少行"——不设限时，一年几十万行的日志会让
  /// 打开查看器瞬间构造数十 MB 字符串、界面卡死甚至内存溢出。
  /// 完整内容仍可通过「导出操作日志」或「打开日志文件位置」查看。
  static const int displayLineLimit = 2000;

  /// 读取最近 [maxLines] 条操作日志（新→旧顺序返回，供界面展示）。
  static Future<List<String>> recentLines({int maxLines = displayLineLimit}) async {
    try {
      final file = LogFileService.fileIn(await _logDirectory());
      if (!await file.exists()) return const [];
      return readTail(file, maxLines: maxLines);
    } catch (e) {
      debugPrint('读取操作日志失败：$e');
      appendErrorLog('operation_log_service', e, StackTrace.current);
      return const [];
    }
  }

  static Future<void> _appendLine(String line) async {
    try {
      final file = LogFileService.fileIn(await _logDirectory());
      await LogFileService.append(file, LogFileService.prefixOperation, line);
    } catch (e) {
      debugPrint('操作日志写入失败：$e');
      appendErrorLog('operation_log_service', e, StackTrace.current);
    }
  }

  /// 组装一行日志：`2026-09-26 18:40:12  删除记录  张三 · 批评 · 迟到`。
  static String formatLogLine(DateTime time, String action, [String detail = '']) {
    final stamp = '${formatYmd(time)} '
        '${twoDigit(time.hour)}:${twoDigit(time.minute)}:${twoDigit(time.second)}';
    final trimmed = detail.trim();
    return trimmed.isEmpty ? '$stamp  $action' : '$stamp  $action  $trimmed';
  }

  /// 删除 [cutoff] 之前的操作日志条目，返回删除数量（维护页“清理旧日志”用）。
  static Future<int> deleteLogsBefore(DateTime cutoff) async {
    try {
      final file = LogFileService.fileIn(await _logDirectory());
      return await LogFileService.pruneBefore(
        file,
        cutoff,
        category: LogFileService.categoryOperation,
      );
    } on Object catch (e) {
      debugPrint('清理旧操作日志失败：$e');
      return 0;
    }
  }

  /// 追加一行到指定文件（内容加密）。
  static Future<void> appendLineTo(File file, String line) async {
    await LogFileService.append(
      file,
      LogFileService.prefixOperation,
      line,
    );
  }

  /// 读取文件尾部的操作日志条目，按新→旧返回；[maxLines] 限制返回条数。
  ///
  /// 修复（6.10）：改为**从文件尾部分块读取**，而不是 `readAsString()` 整份
  /// 读入再切分——日志全量保留，整份读在大文件下会一次分配数十 MB 内存。
  /// 块边界可能切断一个 UTF-8 多字节字符，用 allowMalformed 兜底：
  /// 受影响的只是**每个块边界处**可能出现的替换符（一行显示不全），
  /// 不改变行数与内容顺序，属可接受的显示噪声。
  static Future<List<String>> readTail(File file, {int? maxLines}) async {
    const chunkSize = 64 * 1024;
    const limit = 5000; // 兜底上限：即使调用方不传 maxLines 也不整份读入
    final effectiveLimit =
        (maxLines == null || maxLines <= 0 || maxLines > limit) ? limit : maxLines;
    final length = await file.length();
    if (length == 0) return const [];
    final chunks = <String>[];
    var position = length;
    var newlineCount = 0;
    final raf = await file.open();
    try {
      while (position > 0 && newlineCount <= effectiveLimit) {
        final readSize = position >= chunkSize ? chunkSize : position;
        position -= readSize;
        await raf.setPosition(position);
        final bytes = await raf.read(readSize);
        final text = utf8.decode(bytes, allowMalformed: true);
        newlineCount += '\n'.allMatches(text).length;
        chunks.add(text);
      }
    } finally {
      await raf.close();
    }
    final content = chunks.reversed.join();
    final lines = content
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        // 新日志每行是 LRX2 密文；无法解密的行跳过。
        .map((line) => StorageService.decodeLocalText(line))
        .whereType<String>()
        .where((line) => line.startsWith(LogFileService.prefixOperation))
        .map((line) => line.substring(LogFileService.prefixOperation.length))
        .toList();
    if (lines.length <= effectiveLimit) {
      return lines.reversed.toList();
    }
    return lines.sublist(lines.length - effectiveLimit).reversed.toList();
  }

  /// 导出全部操作日志（明文，旧→新）。
  static Future<String> exportText() async {
    final file = LogFileService.fileIn(await _logDirectory());
    return LogFileService.exportText(file, LogFileService.prefixOperation);
  }
}
