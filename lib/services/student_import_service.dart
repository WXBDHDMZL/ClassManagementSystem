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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../utils/student_name.dart';
import '../utils/utf16.dart';
import 'import_limits.dart';
import 'transfer_service.dart';
import 'xlsx_merge.dart';
import 'xlsx_reader.dart';

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
  static const Set<String> _otherHeaders = {'序号', '学号', '性别', '班级', '备注', '编号'};
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
    for (var i = 0; i < lines.length; i++) {
      // 审计 P1-7（纯文本路径）：首行若是"高一(3)班学生名单"这类标题，
      // 不能当成第一个学生姓名导入。只对首行做保守判定 —— 正文行里的
      // "名单"等字样可能是真实内容，不在此过滤。
      if (i == 0 && _isTitleLikeLine(lines[i])) continue;
      final parts = lines[i].split(RegExp(r'[,，、;；]'));
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
      // 审计 A-08：先按字节数挡掉超大文件（解压放大在
      // _parseDocxRows / readRows 里挡）。放在 try 内，超限才会走下面的
      // `on FormatException` 变成预览里的可读错误，而不是抛到界面上。
      ImportLimits.ensureFileBytes(bytes.length);
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
          var rows = const <List<String>>[];
          try {
            rows = await TransferService.readRowsAsync(
              bytes,
              isCsv: false,
              headerKeywords: _nameHeaders,
            );
          } on Object {
            rows = const <List<String>>[];
          }
          if (rows.isEmpty) {
            rows = await Isolate.run(() => _parseXlsxRows(bytes));
          }
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

  // 审计 A-25：UTF-16 解码统一走 utils/utf16.dart，奇数字节与孤立代理项
  // 都会被判为"文件损坏"，不再静默丢字节或写出不可见字符。
  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) =>
      decodeUtf16(bytes, littleEndian: littleEndian);

  static StudentImportPreview _fromRows(
    List<List<String>> rows,
    StudentImportSource source,
  ) {
    if (rows.isEmpty) {
      return StudentImportPreview(source: source, error: '文件里没有内容');
    }
    // 审计 A-08：名单不会有一万行以上；超限宁可报错也不静默只读前 N 行。
    ImportLimits.ensureRowCount(rows.length);

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
    //
    // 审计 P1-7：但表格前更常见的是一行标题（如"高一(3)班学生名单"）。
    // 此前无条件把这些单格段落当成姓名收下，`_fromNames` 只按"空/超长"过滤，
    // 标题就作为一条学生姓名被导入。这里用 [_isTitleLikeLine] 排除标题类文本。
    if (headerRow > 0 && rows.take(headerRow).every((row) => row.length == 1)) {
      for (var i = 0; i < headerRow; i++) {
        final text = rows[i].first;
        if (_isTitleLikeLine(text)) continue;
        raw.add(text);
      }
    }
    final start = headerRow >= 0 ? headerRow + 1 : 0;
    final invalidRows = <String>[];
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (nameColumn >= row.length) {
        // 审计 P2-32：短行不能静默丢，否则用户不知道该行未被导入。
        invalidRows.add('第 ${i + 1} 行：缺少姓名列');
        continue;
      }
      var name = row[nameColumn];
      if (headerRow < 0 && nameColumn == 0 && _isOrdinalCell(name)) {
        if (row.length > 1) name = row[1];
      }
      raw.add(name);
    }
    final preview = _fromNames(raw, source);
    if (invalidRows.isEmpty) return preview;
    return StudentImportPreview(
      source: preview.source,
      names: preview.names,
      invalid: [...preview.invalid, ...invalidRows],
      duplicateCount: preview.duplicateCount,
      error: preview.error,
    );
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

      final error = validateStudentName(name);
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

  /// 标题类文本（"高一(3)班学生名单""某某中学 学生名册"等）。
  ///
  /// 审计 P1-7：表头之前单格段落里混入的标题不是姓名。判定刻意保守 ——
  /// 只认"名单/名册/花名册/表格/学生表"等标题词，或含书名号/括号且明显不像
  /// 姓名的整句，避免误伤真姓名（如"名单"两个字本身是罕见姓氏组合，但仍
  /// 由 [validateStudentName] 与长度限制兜底）。
  static bool _isTitleLikeLine(String value) {
    final text = _cleanName(value);
    if (text.isEmpty) return true;
    // 含明确标题词的一律按标题处理（真姓名不会出现这些词）。
    for (final keyword in _titleKeywords) {
      if (text.contains(keyword)) return true;
    }
    // 段落里出现冒号/全角冒号通常是说明性文字，不是姓名。
    if (text.contains(':') || text.contains('：')) return true;
    return false;
  }

  static const List<String> _titleKeywords = [
    '名单',
    '名册',
    '花名册',
    '学生表',
    '学生信息',
    '人员表',
    '通讯录',
    '统计表',
  ];

  static bool _isOrdinalCell(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    return RegExp(r'^\d{1,6}$').hasMatch(text) ||
        RegExp(r'^\d{1,3}\s*[\.、\)．]$').hasMatch(text) ||
        RegExp(r'^[\u2460-\u2473]$').hasMatch(text);
  }

  /// 从 Word 的 `word/document.xml` 提取段落与表格行。
  static List<List<String>> _parseDocxRows(List<int> bytes) {
    ImportLimits.ensureZipPayload(bytes, what: 'Word 文件');
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
    // 审计 P2：Word 常把内容包在 `w:sdt`（内容控件）里，直接遍历 body 的
    // 一级子元素会整段漏掉。这里递归展开 `sdt` → `sdtContent` 后再按段落/表格处理。
    for (final node in _documentBlocks(body)) {
      if (node.name.local == 'p') {
        if (_isHeadingParagraph(node)) continue;
        final text = _paragraphText(node);
        if (text.trim().isNotEmpty) rows.add([text]);
      } else if (node.name.local == 'tbl') {
        for (final row in node.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'tr',
        )) {
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

  /// 展开 body 的块级子元素（把 `w:sdt` 里的 `w:sdtContent` 内容提上来）。
  static Iterable<XmlElement> _documentBlocks(XmlElement body) sync* {
    for (final node in body.children.whereType<XmlElement>()) {
      final name = node.name.local;
      if (name == 'p' || name == 'tbl') {
        yield node;
        continue;
      }
      if (name == 'sdt') {
        for (final content in node.children.whereType<XmlElement>()) {
          if (content.name.local != 'sdtContent') continue;
          yield* _documentBlocks(content);
        }
      }
    }
  }

  static List<List<String>> _parseXlsxRows(List<int> bytes) {
    // 审计 P2-13：合并单元格只有左上角有值，铺满后表头/姓名才不会丢。
    // 审计 P2-16：兜底路径也要按「姓名」表头挑表，避免读到封面/说明表。
    final parsed = XlsxReader.readRowsWithSpans(
      bytes,
      headerKeywords: _nameHeaders,
    );
    return XlsxMerge.fill(parsed.rows, parsed.spans);
  }

  static bool _isHeadingParagraph(XmlElement paragraph) {
    for (final style in paragraph.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'pStyle',
    )) {
      String value = '';
      for (final attribute in style.attributes) {
        if (attribute.name.local == 'val') value = attribute.value;
      }
      final lower = value.toLowerCase();
      if (lower.contains('heading') ||
          lower.contains('title') ||
          lower.contains('标题')) {
        return true;
      }
    }
    return false;
  }

  static String _paragraphText(XmlElement element) {
    final buffer = StringBuffer();
    _writeRunText(element, buffer);
    return buffer.toString().trim();
  }

  /// 按文档顺序收集段落里的可见文本。
  ///
  /// 审计 P2：此前只取 `w:t`，Word 里的制表符（`w:tab`）与换行（`w:br`）
  /// 全部丢失 —— 一行 `张三<TAB>李四` 会被拼成 `张三李四`，名单直接错。
  /// 同时跳过 `w:rPh`（注音/拼音）子树，避免把注音重复拼进姓名。
  static void _writeRunText(XmlElement element, StringBuffer buffer) {
    for (final node in element.children.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 'rPh':
          continue;
        case 't':
          buffer.write(node.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br':
        case 'cr':
          buffer.write('\n');
        default:
          _writeRunText(node, buffer);
      }
    }
  }
}
