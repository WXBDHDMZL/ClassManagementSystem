/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'import_limits.dart';

/// 直接读取 .xlsx 的最小实现，绕过 excel 包对关系目标路径的假设。
///
/// 主要用于 openpyxl / WPS 等把关系目标写成绝对路径（/xl/worksheets/...）
/// 的文件；Excel 包会拼成 xl//xl/... 而找不到工作表。
class XlsxReader {
  XlsxReader._();

  /// 兼容 openpyxl / WPS 等写出的绝对路径关系（`/xl/worksheets/...`），
  /// `excel` 包按相对路径拼会找不到工作表。
  static List<List<String>> readRows(List<int> bytes) {
    // 审计 A-08：zip 炸弹/超大表在这里挡住，别等解压完才发现内存不够。
    ImportLimits.ensureZipPayload(bytes, what: '表格文件');
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);

    final workbookEntry = archive.findFile('xl/workbook.xml');
    if (workbookEntry == null) {
      throw const FormatException('表格文件里没有工作簿（缺少 xl/workbook.xml）');
    }
    final workbook = XmlDocument.parse(_entryText(workbookEntry));

    final sharedStrings = <String>[];
    final sharedEntry = archive.findFile('xl/sharedStrings.xml');
    if (sharedEntry != null) {
      final sharedDoc = XmlDocument.parse(_entryText(sharedEntry));
      for (final item in sharedDoc.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'si',
      )) {
        sharedStrings.add(_allText(item));
      }
    }

    final relationships = <String, String>{};
    final relEntry = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relEntry != null) {
      final relDoc = XmlDocument.parse(_entryText(relEntry));
      for (final rel in relDoc.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'Relationship',
      )) {
        String id = '';
        String target = '';
        for (final attribute in rel.attributes) {
          if (attribute.name.local == 'Id') id = attribute.value;
          if (attribute.name.local == 'Target') target = attribute.value;
        }
        if (id.isNotEmpty) relationships[id] = target;
      }
    }

    final sheets = workbook.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'sheet',
    );
    for (final sheet in sheets) {
      String relationId = '';
      for (final attribute in sheet.attributes) {
        if (attribute.name.local == 'id') relationId = attribute.value;
      }
      final target = _normalizeXlsxTarget(relationships[relationId] ?? '');
      final sheetEntry = archive.findFile(target);
      if (sheetEntry == null) continue;
      final rows = _parseXlsxSheet(_entryText(sheetEntry), sharedStrings);
      if (rows.any((row) => row.any((cell) => cell.trim().isNotEmpty))) {
        return rows;
      }
    }
    return const [];
  }

  static String _entryText(ArchiveFile entry) {
    final content = entry.content;
    if (content is String) return content;
    if (content is Uint8List) return utf8.decode(content);
    if (content is List<int>) return utf8.decode(content);
    throw const FormatException('表格文件内容无法读取');
  }

  static String _normalizeXlsxTarget(String raw) {
    var target = raw.replaceAll('\\', '/');
    if (target.startsWith('/')) target = target.substring(1);
    if (target.startsWith('xl/')) return target;
    return 'xl/$target';
  }

  static List<List<String>> _parseXlsxSheet(
    String xmlText,
    List<String> sharedStrings,
  ) {
    final document = XmlDocument.parse(xmlText);
    final rows = <List<String>>[];
    for (final row in document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'row',
    )) {
      final cells = <String>[];
      for (final cell in row.children.whereType<XmlElement>().where(
        (element) => element.name.local == 'c',
      )) {
        var column = cells.length;
        String reference = '';
        String type = '';
        for (final attribute in cell.attributes) {
          if (attribute.name.local == 'r') reference = attribute.value;
          if (attribute.name.local == 't') type = attribute.value;
        }
        if (reference.isNotEmpty) column = _columnIndexOf(reference);
        while (cells.length <= column) {
          cells.add('');
        }
        String value;
        if (type == 's') {
          final raw = _childText(cell, 'v');
          final index = int.tryParse(raw);
          value = index != null && index >= 0 && index < sharedStrings.length
              ? sharedStrings[index]
              : '';
        } else if (type == 'inlineStr') {
          value = _allText(cell);
        } else {
          value = _childText(cell, 'v');
        }
        cells[column] = value;
      }
      rows.add(cells);
    }
    return rows;
  }

  static String _childText(XmlElement element, String localName) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (child.name.local == localName) return child.innerText;
    }
    return '';
  }

  static String _allText(XmlElement element) {
    final buffer = StringBuffer();
    for (final text in element.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 't',
    )) {
      buffer.write(text.innerText);
    }
    return buffer.toString();
  }

  static int _columnIndexOf(String reference) {
    var index = 0;
    for (final code in reference.codeUnits) {
      if (code >= 65 && code <= 90) {
        index = index * 26 + (code - 64);
      } else if (code >= 97 && code <= 122) {
        index = index * 26 + (code - 96);
      } else {
        break;
      }
    }
    return index > 0 ? index - 1 : 0;
  }

}
