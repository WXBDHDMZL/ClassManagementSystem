// 导出落盘与日志专项回归（V2.30.24，第 5 轮：G-35 / G-36 / G-40）。
//
//   G-35 导出：目标目录不存在时先建目录、文件名消毒、写入原子化（不留 .tmp）；
//   G-36 日志按月分文件（操作日志/错误日志），旧的单文件仍被枚举到（不丢历史）；
//   G-40 日志导出改异步读（行为层面，无法直接断言，这里锁定其依赖的枚举能力）。
//
// 模式沿用 v230_parse_robustness_test：test() + mock path_provider。

import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/error_log_service.dart';
import 'package:class_management_system/services/excel_export.dart';
import 'package:class_management_system/services/operation_log_service.dart';
import 'package:class_management_system/utils/file_names.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late Directory logDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_export_log');
    logDir = Directory('${tempDir.path}/日志')..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteStorageTestRoot(tempDir);
  });

  group('G-35 导出落盘', () {
    excel.Excel sampleWorkbook() {
      final book = ExcelExport.newWorkbook();
      book['Sheet1'].appendRow([excel.TextCellValue('测试')]);
      return book;
    }

    test('导出目录不存在时自动建目录并写入', () async {
      final target = '${tempDir.path}/还没有的目录/更深一层';
      final path = await ExcelExport.saveWorkbook(
        sampleWorkbook(),
        baseName: '导出测试',
        exportPath: target,
      );
      expect(path, isNotNull);
      expect(await File(path!).exists(), isTrue);
      expect(path, contains('还没有的目录'));
    });

    test('文件名含非法字符时被消毒，仍能正确写入', () async {
      final path = await ExcelExport.saveWorkbook(
        sampleWorkbook(),
        baseName: 'a:b*c?d',
        exportPath: tempDir.path,
      );
      expect(path, isNotNull);
      expect(path!.endsWith('/abcd.xlsx'), isTrue,
          reason: '非法字符应被剔除');
      expect(await File(path).exists(), isTrue);
    });

    test('原子写不留 .tmp 残留', () async {
      await ExcelExport.saveWorkbook(
        sampleWorkbook(),
        baseName: '清理检查',
        exportPath: tempDir.path,
      );
      final leftovers = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty, reason: '原子写成功后不应残留临时文件');
    });

    test('sanitizeFileName：非法字符/折叠../保留名/空串', () {
      expect(sanitizeFileName('a:b\\c/d*e?f"g<h>i|j'), 'abcdefghij');
      expect(sanitizeFileName('上..级'), '上级');
      expect(sanitizeFileName('CON'), '导出文件');
      expect(sanitizeFileName('CON.xlsx'), '导出文件');
      expect(sanitizeFileName('   '), '导出文件');
      expect(sanitizeFileName('abc.'), 'abc');
      expect(sanitizeFileName('正常名字.txt'), '正常名字.txt');
    });
  });

  group('日志合并为单一文件', () {
    test('文件名固定，不再按月生成', () {
      expect(
        OperationLogService.fileNameFor(DateTime(2026, 10, 4)),
        '班级管理系统_日志.txt',
      );
      expect(
        OperationLogService.fileNameFor(DateTime(2026, 1, 1)),
        '班级管理系统_日志.txt',
      );
      expect(OperationLogService.fileName, '班级管理系统_日志.txt');
    });

    test('log() 写入合并日志文件', () async {
      OperationLogService.log('回归写入', '一条测试日志');
      // 异步排队写盘：轮询等待（最多 2 秒）。
      File? target;
      for (var i = 0; i < 100; i++) {
        final file = File('${logDir.path}/${OperationLogService.fileName}');
        if (file.existsSync() &&
            (await EncryptedTextFile.readAllText(file))
                .contains('一条测试日志')) {
          target = file;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(target, isNotNull, reason: '应写入合并日志文件');
    });

    test('allLogFiles 只返回合并日志文件，忽略旧分类文件', () async {
      await OperationLogService.appendLineTo(
        File('${logDir.path}/${OperationLogService.fileName}'),
        '2026-10-01  当前日志',
      );
      for (final name in const [
        '班级管理系统_操作日志.txt', // 旧单文件
        '班级管理系统_操作日志_2026-09.txt',
        '班级管理系统_错误日志_2026-10.txt',
        '班级管理系统_操作日志_DEV_2026-10.txt', // 开发日志
      ]) {
        await File('${logDir.path}/$name').writeAsString('x\n');
      }
      await File('${logDir.path}/class_management_data.enc').writeAsString('x');

      final files = await OperationLogService.allLogFiles();
      expect(files.map((f) => f.uri.pathSegments.last).toList(), [
        '班级管理系统_日志.txt',
      ]);
    });

    test('recentLines 只返回操作日志，且新→旧排列', () async {
      final file = File('${logDir.path}/${OperationLogService.fileName}');
      await OperationLogService.appendLineTo(file, '2026-09-30  九月日志');
      await OperationLogService.appendLineTo(file, '2026-10-01  十月日志');
      final lines = await OperationLogService.recentLines();
      expect(lines, hasLength(2));
      expect(lines.first, contains('十月日志'), reason: '最新的应排在最前');
      expect(lines.last, contains('九月日志'));
    });

    test('错误日志与操作日志共用同一文件', () async {
      expect(errorLogFileName, '班级管理系统_日志.txt');
      appendErrorLog('共用文件用例', '错误与操作共用一份日志', null);
      await flushErrorLogWrites();
      final file = File('${logDir.path}/$errorLogFileName');
      expect(await file.exists(), isTrue);
      final files = await allErrorLogFiles();
      expect(files, hasLength(1));
      expect(files.single.uri.pathSegments.last, '班级管理系统_日志.txt');
    });
  });
}
