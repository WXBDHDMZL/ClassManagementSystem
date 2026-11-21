/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../providers/app_data_provider.dart';
import 'transfer_service.dart';

/// 名单导入来源。
enum StudentImportSource { paste, textFile, tableFile, wordFile }

/// 名单解析结果：可直接导入的姓名、被跳过的无效项与输入内重复数量。
class StudentImportPreview {
  const StudentImportPreview({
    required this.source,
    this.names = const [],
    this.invalid = const [],
    this.duplicateCount = 0,
    this.error,
  });

  final StudentImportSource source;
  final List<String> names;
  final List<String> invalid;
  final int duplicateCount;
  final String? error;

  bool get hasError => error != null;
  bool get hasNames => names.isNotEmpty;
}

/// 名单导入解析：粘贴文本、TXT、Excel/CSV、Word 文档。
///
/// 只做解析与校验，不写数据；写入由界面确认后调用 provider。
class StudentImportService {
  static const Set<String> _nameHeaders = {'姓名', '学生姓名', '名字', '学生'};
  static const Set<String> _otherHeaders = {
    '序号',
    '学号',
    '性别',
    '班级',
    '备注',
    '编号',
  };
  static const int _maxScanRows = 10;

  /// 解析粘贴文本或 TXT 文本。
  static StudentImportPreview parseText(String text) {
    final normalized = text
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return const StudentImportPreview(
        source: StudentImportSource.paste,
        error: '没有读到内容，请粘贴姓名或表格后再试',
      );
    }

    final looksTabular =
        lines.any((line) => line.contains('\t')) ||
        lines.any(_looksLikeTableLine) ||
        lines.any((line) => _cellsOf(line).any(_isNameHeader));
    if (looksTabular) {
      final rows = lines
          .map(_cellsOf)
          .where((row) => row.any((cell) => cell.trim().isNotEmpty))
          .toList(growable: false);
      return _fromRows(rows, StudentImportSource.paste);
    }

    final raw = <String>[];
    for (final line in lines) {
      final parts = line.split(RegExp(r'[,，、;；]'));
      for (final part in parts) {
        raw.add(part);
      }
    }
    return _fromNames(raw, StudentImportSource.paste);
  }

  /// 解析文件：按扩展名分派。
  static Future<StudentImportPreview> parseFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    final lower = fileName.toLowerCase();
    final extension = lower.contains('.') ? lower.split('.').last : '';
    try {
      switch (extension) {
        case 'txt':
          return _fromTextBytes(bytes);
        case 'csv':
          final rows = await TransferService.readRowsAsync(
            bytes,
            isCsv: true,
            headerKeywords: _nameHeaders,
          );
          return _fromRows(rows, StudentImportSource.tableFile);
        case 'xlsx':
          final rows = await TransferService.readRowsAsync(
            bytes,
            isCsv: false,
            headerKeywords: _nameHeaders,
          );
          return _fromRows(rows, StudentImportSource.tableFile);
        case 'docx':
          final rows = await Isolate.run(() => _parseDocxRows(bytes));
          return _fromRows(rows, StudentImportSource.wordFile);
        default:
          return StudentImportPreview(
            source: StudentImportSource.tableFile,
            error: '不支持 .$extension 文件，请选择 .xlsx、.csv、.txt 或 .docx',
          );
      }
    } on FormatException catch (e) {
      return StudentImportPreview(
        source: _sourceFor(extension),
        error: e.message,
      );
    } on Object catch (e) {
      return StudentImportPreview(
        source: _sourceFor(extension),
        error: '文件读取失败：$e',
      );
    }
  }

  static StudentImportSource _sourceFor(String extension) {
    if (extension == 'txt') return StudentImportSource.textFile;
    if (extension == 'docx') return StudentImportSource.wordFile;
    return StudentImportSource.tableFile;
  }

  static StudentImportPreview _fromTextBytes(List<int> bytes) {
    final text = _decodeText(bytes);
    final parsed = parseText(text);
    return StudentImportPreview(
      source: StudentImportSource.textFile,
      names: parsed.names,
      invalid: parsed.invalid,
      duplicateCount: parsed.duplicateCount,
      error: parsed.error,
    );
  }

  static String _decodeText(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(
        '文本文件不是 UTF-8 编码：请另存为 UTF-8 后重试，或改用 .docx / .xlsx',
      );
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static StudentImportPreview _fromRows(
    List<List<String>> rows,
    StudentImportSource source,
  ) {
    if (rows.isEmpty) {
      return StudentImportPreview(source: source, error: '文件里没有内容');
    }

    var headerRow = -1;
    var nameColumn = 0;
    final limit = rows.length < _maxScanRows ? rows.length : _maxScanRows;
    for (var i = 0; i < limit; i++) {
      final row = rows[i];
      for (var c = 0; c < row.length; c++) {
        if (_isNameHeader(row[c])) {
          headerRow = i;
          nameColumn = c;
          break;
        }
      }
      if (headerRow >= 0) break;
    }

    if (headerRow < 0) {
      // 没有表头时：首列是序号/学号（数字）就取第二列，否则取第一列。
      final sample = rows
          .take(limit)
          .where((row) => row.any((cell) => cell.trim().isNotEmpty))
          .toList(growable: false);
      if (sample.isNotEmpty &&
          sample.every((row) => row.isEmpty || _isOrdinalCell(row.first))) {
        nameColumn = 1;
      }
    }

    final raw = <String>[];
    // Word 常见结构：表格前先写几段姓名。若表头之前的行都是单格段落，
    // 这些段落也是名单内容，不能因为后面的表格表头而丢掉。
    if (headerRow > 0 &&
        rows.take(headerRow).every((row) => row.length == 1)) {
      for (var i = 0; i < headerRow; i++) {
        raw.add(rows[i].first);
      }
    }
    final start = headerRow >= 0 ? headerRow + 1 : 0;
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (nameColumn >= row.length) continue;
      var name = row[nameColumn];
      if (headerRow < 0 && nameColumn == 0 && _isOrdinalCell(name)) {
        if (row.length > 1) name = row[1];
      }
      raw.add(name);
    }
    return _fromNames(raw, source);
  }

  static StudentImportPreview _fromNames(
    Iterable<String> raw,
    StudentImportSource source,
  ) {
    final names = <String>[];
    final invalid = <String>[];
    final seen = <String>{};
    final seenInvalid = <String>{};
    var duplicateCount = 0;

    for (final value in raw) {
      var name = _cleanName(value);
      if (name.isEmpty) continue;
      if (_isNameHeader(name) || _otherHeaders.contains(name)) continue;
      if (_isOrdinalCell(name)) continue;

      final error = AppDataProvider.validateStudentName(name);
      if (error != null) {
        if (seenInvalid.add(name)) invalid.add(name);
        continue;
      }
      if (seen.add(name)) {
        names.add(name);
      } else {
        duplicateCount++;
      }
    }

    if (names.isEmpty && invalid.isEmpty) {
      return StudentImportPreview(
        source: source,
        error: '没有识别到姓名，请检查是否有“姓名”列或每行一个姓名',
      );
    }
    return StudentImportPreview(
      source: source,
      names: names,
      invalid: invalid,
      duplicateCount: duplicateCount,
    );
  }

  static String _cleanName(String value) {
    var name = value
        .replaceAll('\u200B', '')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u3000', ' ')
        .trim();
    // 去掉“1.”“1、”“①”这类粘贴/Word 编号。
    name = name.replaceFirst(
      RegExp(r'^(?:\d{1,3}\s*[\.、\)．]|[\u2460-\u2473])\s*'),
      '',
    );
    name = name.replaceFirst(RegExp(r'^\d{1,3}\s+'), '');
    return name.trim();
  }

  static List<String> _cellsOf(String line) {
    if (line.contains('\t')) return line.split('\t');
    if (line.contains(',') || line.contains('，')) {
      return line.split(RegExp(r'[,，]'));
    }
    return [line];
  }

  static bool _looksLikeTableLine(String line) {
    if (line.contains('\t')) return true;
    final cells = _cellsOf(line);
    if (cells.length < 2) return false;
    return _isOrdinalCell(cells.first) || cells.any(_isNameHeader);
  }

  static bool _isNameHeader(String value) =>
      _nameHeaders.contains(value.trim());

  static bool _isOrdinalCell(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    return RegExp(r'^\d{1,6}$').hasMatch(text) ||
        RegExp(r'^\d{1,3}\s*[\.、\)．]$').hasMatch(text) ||
        RegExp(r'^[\u2460-\u2473]$').hasMatch(text);
  }

  /// 从 Word 的 `word/document.xml` 提取段落与表格行。
  static List<List<String>> _parseDocxRows(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) {
      throw const FormatException('Word 文件里没有正文（缺少 word/document.xml）');
    }
    final content = entry.content;
    final String xmlText;
    if (content is String) {
      xmlText = content;
    } else if (content is Uint8List) {
      xmlText = utf8.decode(content);
    } else if (content is List<int>) {
      xmlText = utf8.decode(content);
    } else {
      throw const FormatException('Word 文件正文无法读取');
    }

    final document = XmlDocument.parse(xmlText);
    XmlElement? body;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'body') {
        body = element;
        break;
      }
    }
    if (body == null) {
      throw const FormatException('Word 文件里没有正文');
    }

    final rows = <List<String>>[];
    for (final node in body.children.whereType<XmlElement>()) {
      if (node.name.local == 'p') {
        final text = _paragraphText(node);
        if (text.trim().isNotEmpty) rows.add([text]);
      } else if (node.name.local == 'tbl') {
        for (final row in node.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'tr')) {
          final cells = row.children
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'tc')
              .map(_paragraphText)
              .toList(growable: false);
          if (cells.any((cell) => cell.trim().isNotEmpty)) rows.add(cells);
        }
      }
    }
    return rows;
  }

  static String _paragraphText(XmlElement element) {
    final buffer = StringBuffer();
    for (final text in element.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 't')) {
      buffer.write(text.innerText);
    }
    return buffer.toString().trim();
  }
}
