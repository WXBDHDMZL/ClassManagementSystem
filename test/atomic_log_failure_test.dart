// 审计 A-22 / A-23 专项：原子写残留清理、日志读失败不再被当成"没有日志"。
//
// A-22：`AtomicFile` 此前只在 rename 阶段（且只对 FileSystemException）清理临时
//       文件；写入/复制阶段抛错会把 `*.tmp` 永久留在数据目录。
// A-23：`OperationLogService.recentLines()` 此前把读失败吞成空列表，界面因此显示
//       "还没有操作日志"；日志导出/清理入口也没有兜底。
//
// 只使用临时目录，绝不接触真实班级数据。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/atomic_file.dart';
import 'package:class_management_system/services/log_file_service.dart';
import 'package:class_management_system/services/operation_log_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_atomic_log_failure');
  });

  tearDown(() async {
    LogFileService.disableProtectionForTests = false;
    await deleteStorageTestRoot(tempDir);
  });

  /// 目录里残留的临时文件（`*.tmp`）。
  List<String> leftoverTemps(Directory dir) {
    if (!dir.existsSync()) return const <String>[];
    return dir
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.tmp'))
        .toList();
  }

  group('A-22 原子写失败不留临时文件', () {
    test('复制失败（源文件不存在）：异常上抛且不留 .tmp', () async {
      final dest = '${tempDir.path}/copied.enc';
      final source = '${tempDir.path}/missing_source.enc';

      await expectLater(
        AtomicFile.copyAtomic(source, dest),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(dest).existsSync(), isFalse, reason: '目标文件不应被创建');
      expect(
        leftoverTemps(tempDir),
        isEmpty,
        reason: '审计 A-22：写入/复制阶段失败也必须清理临时文件',
      );
    });

    test('rename 抛出非 FileSystemException：异常上抛且不留 .tmp', () async {
      final target = '${tempDir.path}/written.txt';
      AtomicFile.debugRenameOverride = (tempFile, path) async {
        throw StateError('模拟非 FileSystemException 失败');
      };
      addTearDown(() => AtomicFile.debugRenameOverride = null);

      await expectLater(
        AtomicFile.writeString(target, '内容'),
        throwsA(isA<StateError>()),
      );
      expect(
        leftoverTemps(tempDir),
        isEmpty,
        reason: '审计 A-22：清理范围要覆盖整个"写临时文件 → rename"流程',
      );
    });

    test('rename 重试耗尽（FileSystemException）：异常上抛且不留 .tmp', () async {
      final target = '${tempDir.path}/retry.txt';
      AtomicFile.debugRenameOverride = (tempFile, path) async {
        throw const FileSystemException('模拟被占用');
      };
      addTearDown(() => AtomicFile.debugRenameOverride = null);

      await expectLater(
        AtomicFile.writeString(target, '内容'),
        throwsA(isA<FileSystemException>()),
      );
      expect(leftoverTemps(tempDir), isEmpty);
    });
  });

  group('A-23 日志读失败要能被界面感知', () {
    /// 让日志文件存在但内容无法按 UTF-8 解码：`readAsString()` 必然失败。
    void blockLogFileWithInvalidUtf8() {
      final logDir = Directory('${tempDir.path}/日志')..createSync(recursive: true);
      final file = File(
        '${logDir.path}${Platform.pathSeparator}${LogFileService.fileName}',
      );
      // 0xC3 后跟 0x28 是非法 UTF-8 序列。
      file.writeAsBytesSync(const <int>[0xC3, 0x28, 0x00]);
      OperationLogService.debugDirectoryOverride = logDir;
    }

    tearDown(() {
      OperationLogService.debugDirectoryOverride = null;
      OperationLogService.debugReadTailOverride = null;
    });

    test('recentLines：读失败必须上抛，不能返回空列表冒充"没有日志"', () async {
      final logDir = Directory('${tempDir.path}/日志')..createSync(recursive: true);
      File(
        '${logDir.path}${Platform.pathSeparator}${LogFileService.fileName}',
      ).writeAsStringSync('x');
      OperationLogService.debugDirectoryOverride = logDir;
      OperationLogService.debugReadTailOverride = (file, {int? maxLines}) async {
        throw const FileSystemException('模拟日志文件被占用');
      };

      await expectLater(
        OperationLogService.recentLines(),
        throwsA(isA<FileSystemException>()),
        reason: '审计 A-23：空列表会让界面显示"还没有操作日志"',
      );
    });

    test('exportText：读失败必须上抛，供导出入口提示失败', () async {
      blockLogFileWithInvalidUtf8();

      await expectLater(
        OperationLogService.exportText(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('pruneBefore：读失败必须上抛，供"清理旧日志"提示失败', () async {
      blockLogFileWithInvalidUtf8();
      final file = LogFileService.fileIn(
        OperationLogService.debugDirectoryOverride!,
      );

      await expectLater(
        LogFileService.pruneBefore(file, DateTime(2026, 1, 1)),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('日志不存在时仍是"空"而不是失败', () async {
      final logDir = Directory('${tempDir.path}/日志');
      OperationLogService.debugDirectoryOverride = logDir;

      expect(await OperationLogService.recentLines(), isEmpty);
      expect(await OperationLogService.exportText(), isEmpty);
    });
  });
}
