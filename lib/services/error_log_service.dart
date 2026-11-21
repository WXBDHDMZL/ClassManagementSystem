/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants/app_version.dart';
import '../utils/app_date.dart';
import '../utils/error_sink.dart';
import 'local_storage_paths.dart';
import 'log_file_service.dart';
import '../utils/app_clock.dart';

/// 运行期异常日志：与操作日志共用文档目录下的《班级管理系统_日志.txt》，
/// 行首以 `[错误]` 区分。出现"界面异常/黑屏"类问题时，把这个文件发给作者即可定位原因。

/// 安装全局异常记录：框架异常与平台异步异常都会落盘。
///
/// 注意（N-5）：错误接收器会同时注入给 [reportError]（`utils/error_sink.dart`），
/// 供 models 等**不依赖 Flutter** 的层使用。
///
/// 注意：`ErrorWidget.builder` 由 `main.dart` 统一设置，服务层不依赖任何 UI 组件。
void installErrorLog() {
  // 把"写日志"注入给零依赖通道，供 models 层使用（N-5）。
  setErrorSink(appendErrorLog);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appendErrorLog(
      'FlutterError',
      details.exception,
      details.stack,
      context: details.context?.toString(),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appendErrorLog('PlatformError', error, stack);
    return true;
  };
}

/// 错误日志所在的合并日志文件名（公开：导出动作的提示文案要用）。
String get errorLogFileName => LogFileService.fileName;

/// 当前运行环境的一行摘要（版本 / 模式 / 系统），每条错误日志都带上，
/// 这样单独截一条日志就能判断"什么版本、什么系统上出的错"。
String environmentLine() {
  final mode = kReleaseMode
      ? 'Release'
      : kProfileMode
          ? 'Profile'
          : 'Debug';
  return '${AppVersion.version}（${AppVersion.pubspecVersion}）· $mode · '
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion} · '
      '${Platform.localeName}';
}

/// 错误日志的串行写队列（N-4）。
///
/// 背景：`appendErrorLog` 的底层 `_writeLog` 是 async 的且调用方不 await，
/// 反复失败的操作（备份清理失败等）会**并发**调用
/// `FileMode.append`，多次写入可能交错/乱序，甚至丢行。
/// 这里用一条 Promise 链把它们排成队，保证"先来的先写、逐条写完"。
Future<void> _writeChain = Future<void>.value();

/// 测试专用：覆盖错误日志所在的文档目录（null = 走 path_provider）。
///
/// 用途（审查 L10）：日志落盘此前完全依赖 `getApplicationDocumentsDirectory`，
/// 测试环境没有 path_provider 插件时**无法验证任何写入行为**（全被静默吞掉）。
/// 注入临时目录后可断言：条目格式、串行顺序、限流窗口、写盘失败降级。
@visibleForTesting
Directory? debugLogDirectoryOverride;

/// 等待错误日志写队列清空（删除日志/退出前调用）。
Future<void> flushErrorLogs() => _writeChain;

/// 测试专用：等待错误日志写队列清空。
@visibleForTesting
Future<void> flushErrorLogWrites() => _writeChain;

Future<Directory> _logDirectory() async {
  final override = debugLogDirectoryOverride;
  if (override != null) return override;
  return LocalStoragePaths.logDirectory();
}

/// 同一 tag + 同一错误内容的限流窗口（**有意的防刷屏设计**，审计 P2-73）：
/// 5 秒内的同一条错误只记一次 —— 错误日志本身仍**无上限、不截断**（这是
/// 既定约定），限流只作用于"完全相同的重复条目"，不同错误/带不同上下文的
/// 记录都会照常写入，不影响台账完整性。
const Duration _throttleWindow = Duration(seconds: 5);
final Map<String, DateTime> _lastSeen = <String, DateTime>{};

/// 追加一条错误日志（失败时静默，绝不影响主流程）。
///
/// [context] 描述"当时在做什么"，例如"保存数据：自动备份"——
/// 排查故障时这条往往比堆栈更快定位问题，新代码请尽量带上。
void appendErrorLog(String tag, Object error, StackTrace? stack,
    {String? context}) {
  try {
    // 限流（有意设计）：同一 tag 的同一错误 5 秒内只记一次，避免高频可预期
    // 错误刷爆日志；这不是"丢日志"—— 限流窗口内的重复不影响台账完整性。
    final signature = '$tag\u0000$error';
    final now = AppClock.now();
    final last = _lastSeen[signature];
    if (last != null && now.difference(last) < _throttleWindow) {
      return;
    }
    _lastSeen[signature] = now;
    // 顺手清理过期条目，避免 Map 无限增长。
    if (_lastSeen.length > 200) {
      _lastSeen.removeWhere(
        (_, time) => now.difference(time) >= _throttleWindow,
      );
    }
    final text = _formatEntry(AppClock.now(), tag, error, stack, context);
    // 串行化：接到队尾，保证写入顺序与调用顺序一致。
    _writeChain = _writeChain.then((_) => _writeLog(text));
  } catch (_) {
    // 日志写入失败不影响程序运行。
  }
}

/// 组装一条结构化的错误记录（分块 + 逐字段标注，便于直接截图/复制定位）。
String _formatEntry(
  DateTime time,
  String tag,
  Object error,
  StackTrace? stack,
  String? context,
) {
  final stamp = '${formatYmd(time)} '
      '${twoDigit(time.hour)}:${twoDigit(time.minute)}:${twoDigit(time.second)}';
  final buffer = StringBuffer()
    ..writeln('──────────────────────────────────────────────')
    ..writeln('时间  $stamp')
    ..writeln('环境  ${environmentLine()}')
    ..writeln('模块  $tag');
  final scene = context?.trim() ?? '';
  if (scene.isNotEmpty) buffer.writeln('场景  $scene');
  buffer
    ..writeln('错误  $error')
    ..writeln('堆栈');
  final stackText = stack?.toString().trim() ?? '';
  if (stackText.isEmpty) {
    buffer.writeln('（无堆栈）');
  } else {
    buffer.writeln(stackText);
  }
  buffer.writeln('──────────────────────────────────────────────');
  return buffer.toString();
}

Future<void> _writeLog(String text) async {
  try {
    final directory = await _logDirectory();
    final file = LogFileService.fileIn(directory);
    // 错误日志全量保留；内容按 LRX2 加密成一条记录追加，无法解密的历史行跳过。
    await LogFileService.append(
      file,
      LogFileService.prefixError,
      text,
    );
  } catch (_) {
    // 忽略：没有写入权限或磁盘满时不影响使用。
  }
}

/// 删除 [cutoff] 之前的错误日志条目，返回删除数量（维护页“清理旧日志”用）。
Future<int> deleteErrorLogsBefore(DateTime cutoff) async {
  try {
    final file = LogFileService.fileIn(await _logDirectory());
    return await LogFileService.pruneBefore(
      file,
      cutoff,
      category: LogFileService.categoryError,
    );
  } on Object catch (_) {
    // 清理失败不抛；维护动作静默降级。
    return 0;
  }
}

/// 合并日志文件的绝对路径（供"导出错误日志"动作读取与展示）。
Future<String> errorLogFilePath() async {
  final directory = await _logDirectory();
  return LogFileService.fileIn(directory).path;
}

/// 错误日志所在的合并日志文件（不存在时返回空列表）。
Future<List<File>> allErrorLogFiles() async {
  try {
    final file = LogFileService.fileIn(await _logDirectory());
    return await file.exists() ? [file] : const [];
  } catch (_) {
    return const [];
  }
}

/// 导出全部错误日志（明文，旧→新）。
Future<String> exportErrorLogText() async {
  final file = LogFileService.fileIn(await _logDirectory());
  return LogFileService.exportText(file, LogFileService.prefixError);
}
