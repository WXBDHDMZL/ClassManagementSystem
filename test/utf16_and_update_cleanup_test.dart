// 审计 A-25 / A-26 专项：UTF-16 解码不再静默丢字节、更新包临时文件会被清理。
//
// A-25：名单/原因库/时段表三条导入路径此前各自手写"每两字节拼一个 code unit"，
//       奇数字节被丢弃、孤立代理项被原样写进库。现在统一走 lib/utils/utf16.dart，
//       坏数据必须在导入预览里变成可见错误。
// A-26：长期失败/取消的更新会在 %TEMP%\班级管理系统_更新 留下安装包，启动时清理。
//
// 只使用临时目录，绝不接触真实班级数据。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/github_update_service.dart';
import 'package:class_management_system/services/library_import_service.dart';
import 'package:class_management_system/services/student_import_service.dart';
import 'package:class_management_system/utils/utf16.dart';

import 'test_helpers.dart';

/// 把字符串按 UTF-16 编码（含 BOM 可选）。
List<int> encodeUtf16(String text, {required bool littleEndian, bool bom = true}) {
  final units = text.codeUnits;
  final bytes = <int>[];
  if (bom) bytes.addAll(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  for (final unit in units) {
    if (littleEndian) {
      bytes
        ..add(unit & 0xFF)
        ..add((unit >> 8) & 0xFF);
    } else {
      bytes
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);
    }
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    tempDir = createStorageTestRoot('cms_utf16_update');
  });

  tearDown(() async {
    await deleteStorageTestRoot(tempDir);
  });

  group('A-25 UTF-16 解码', () {
    test('小端/大端都能解出原文（含 emoji 代理对）', () {
      const text = '张三🚀李四';
      expect(
        decodeUtf16(
          encodeUtf16(text, littleEndian: true, bom: false),
          littleEndian: true,
        ),
        text,
      );
      expect(
        decodeUtf16(
          encodeUtf16(text, littleEndian: false, bom: false),
          littleEndian: false,
        ),
        text,
      );
    });

    test('字节数为奇数：报错而不是丢掉最后一个字节', () {
      expect(
        () => decodeUtf16(<int>[0x41, 0x00, 0x42], littleEndian: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('奇数'),
          ),
        ),
      );
    });

    test('孤立高位代理项：报错而不是写出不可见字符', () {
      expect(
        () => decodeUtf16(<int>[0x00, 0xD8, 0x41, 0x00], littleEndian: true),
        throwsA(isA<FormatException>()),
      );
    });

    test('孤立低位代理项：报错', () {
      expect(
        () => decodeUtf16(<int>[0x00, 0xDC], littleEndian: true),
        throwsA(isA<FormatException>()),
      );
    });

    test('名单导入：损坏的 UTF-16 文本文件给出可见错误', () async {
      final file = File('${tempDir.path}/名单.txt');
      await file.writeAsBytes(<int>[0xFF, 0xFE, 0x00, 0xD8, 0x41, 0x00]);

      final preview = await StudentImportService.parseFile(
        bytes: await file.readAsBytes(),
        fileName: file.path,
      );
      expect(preview.error, isNotNull);
      expect(preview.error, contains('UTF-16'));
      expect(preview.names, isEmpty);
    });

    test('原因库导入：损坏的 UTF-16 文本文件给出可见错误', () async {
      final file = File('${tempDir.path}/原因.txt');
      await file.writeAsBytes(<int>[0xFF, 0xFE, 0x41]);

      await expectLater(
        LibraryImportService.parseReasonsFile(
          bytes: await file.readAsBytes(),
          fileName: file.path,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('正常 UTF-16 名单仍能导入（回归）', () async {
      final file = File('${tempDir.path}/名单2.txt');
      await file.writeAsBytes(encodeUtf16('张三\n李四\n', littleEndian: true));

      final preview = await StudentImportService.parseFile(
        bytes: await file.readAsBytes(),
        fileName: file.path,
      );
      expect(preview.error, isNull);
      expect(preview.names, containsAll(<String>['张三', '李四']));
    });

    test('UTF-8 名单不受影响（回归）', () async {
      final file = File('${tempDir.path}/名单3.txt');
      await file.writeAsBytes(utf8.encode('王五\n'));

      final preview = await StudentImportService.parseFile(
        bytes: await file.readAsBytes(),
        fileName: file.path,
      );
      expect(preview.error, isNull);
      expect(preview.names, contains('王五'));
    });
  });

  group('A-26 更新包临时目录清理', () {
    test('只删过期文件，保留新下载的安装包', () async {
      final dir = Directory('${tempDir.path}/更新')..createSync(recursive: true);
      final old = File('${dir.path}/old_installer.exe')
        ..writeAsBytesSync(const <int>[1, 2, 3]);
      final fresh = File('${dir.path}/fresh_installer.exe')
        ..writeAsBytesSync(const <int>[4, 5, 6]);
      final oldTime = DateTime(2026, 1, 1);
      final now = DateTime(2026, 11, 28);
      await old.setLastModified(oldTime);
      await fresh.setLastModified(now.subtract(const Duration(hours: 1)));

      final removed = await GitHubUpdateService.cleanupStaleDownloads(
        directory: dir,
        maxAge: const Duration(days: 7),
        now: now,
      );

      expect(removed, 1);
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue, reason: '本次更新要用的安装包不能被删');
    });

    test('目录不存在时安静返回 0', () async {
      final removed = await GitHubUpdateService.cleanupStaleDownloads(
        directory: Directory('${tempDir.path}/不存在'),
      );
      expect(removed, 0);
    });

    test('下载目录与更新流程使用同一处路径常量', () {
      expect(
        GitHubUpdateService.defaultDownloadDir().path,
        contains('班级管理系统_更新'),
      );
    });
  });
}
