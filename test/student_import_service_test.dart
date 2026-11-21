/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/student_import_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

void main() {
  group('粘贴文本解析', () {
    test('每行一个姓名，跳过空行与编号', () {
      final preview = StudentImportService.parseText(
        '\uFEFF张三\n\n李四\n1. 王五\n2、赵六\n',
      );
      expect(preview.names, ['张三', '李四', '王五', '赵六']);
      expect(preview.error, isNull);
    });

    test('逗号、顿号、分号混合分隔', () {
      final preview = StudentImportService.parseText('张三，李四、王五;赵六');
      expect(preview.names, ['张三', '李四', '王五', '赵六']);
    });

    test('粘贴表格含表头时按姓名列提取', () {
      final preview = StudentImportService.parseText(
        '序号\t姓名\t性别\n1\t张三\t男\n2\t李四\t女',
      );
      expect(preview.names, ['张三', '李四']);
      expect(preview.invalid, isEmpty);
    });

    test('重复姓名只保留一个并计数', () {
      final preview = StudentImportService.parseText('张三\n李四\n张三');
      expect(preview.names, ['张三', '李四']);
      expect(preview.duplicateCount, 1);
    });

    test('超长姓名进入不合法列表', () {
      final preview = StudentImportService.parseText(
        List.filled(100, '张').join(),
      );
      expect(preview.names, isEmpty);
      expect(preview.invalid.length, 1);
      expect(preview.error, isNull);
    });

    test('没有内容时提示', () {
      final preview = StudentImportService.parseText('   \n\n');
      expect(preview.hasError, isTrue);
    });
  });

  group('文件解析', () {
    test('TXT UTF-8', () async {
      final bytes = utf8.encode('张三\n李四');
      final preview = await StudentImportService.parseFile(
        bytes: bytes,
        fileName: '名单.txt',
      );
      expect(preview.source, StudentImportSource.textFile);
      expect(preview.names, ['张三', '李四']);
    });

    test('TXT UTF-16 LE BOM', () async {
      final text = '张三\r\n李四';
      final units = text.codeUnits;
      final bytes = <int>[0xFF, 0xFE];
      for (final unit in units) {
        bytes.add(unit & 0xFF);
        bytes.add((unit >> 8) & 0xFF);
      }
      final preview = await StudentImportService.parseFile(
        bytes: bytes,
        fileName: '名单.txt',
      );
      expect(preview.names, ['张三', '李四']);
    });

    test('CSV', () async {
      final bytes = utf8.encode('姓名,性别\n张三,男\n李四,女');
      final preview = await StudentImportService.parseFile(
        bytes: bytes,
        fileName: '名单.csv',
      );
      expect(preview.source, StudentImportSource.tableFile);
      expect(preview.names, ['张三', '李四']);
    });

    test('XLSX 往返', () async {
      final bytes = TransferService.buildStudentsXlsx(['张三', '李四', '王五']);
      final preview = await StudentImportService.parseFile(
        bytes: bytes,
        fileName: '名单.xlsx',
      );
      expect(preview.names, ['张三', '李四', '王五']);
    });

    test('DOCX 段落与表格', () async {
      const documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>张三</w:t></w:r></w:p>
    <w:p><w:r><w:t>李四</w:t></w:r></w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>序号</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>姓名</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>王五</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
  </w:body>
</w:document>''';
      final archive = Archive();
      final xmlBytes = utf8.encode(documentXml);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final bytes = ZipEncoder().encode(archive)!;
      final preview = await StudentImportService.parseFile(
        bytes: bytes,
        fileName: '名单.docx',
      );
      expect(preview.source, StudentImportSource.wordFile);
      expect(preview.names, ['张三', '李四', '王五']);
    });

    test('不支持 .xls', () async {
      final preview = await StudentImportService.parseFile(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: '名单.xls',
      );
      expect(preview.hasError, isTrue);
      expect(preview.error, contains('.xls'));
    });
  });
}
