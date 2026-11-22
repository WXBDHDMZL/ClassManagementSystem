/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:typed_data';

import '../constants/time_periods.dart';
import 'transfer_service.dart';

/// 原因库导入预览：解析成功的条目与无法识别的行数。
class ReasonImportPreview {
  const ReasonImportPreview({required this.rows, required this.skipped});

  final List<ReasonImportRow> rows;
  final int skipped;

  int get praiseCount => rows.where((row) => row.operationType == '表扬').length;

  int get criticismCount =>
      rows.where((row) => row.operationType == '批评').length;

  bool get hasRows => rows.isNotEmpty;
}

/// 时段导入预览：按顺序排列的 `{key, label}` 与无法识别的行数。
class PeriodImportPreview {
  const PeriodImportPreview({required this.periods, required this.skipped});

  final List<Map<String, String>> periods;
  final int skipped;

  bool get hasPeriods => periods.isNotEmpty;
}

/// 原因库与时段表的文本/表格导入解析。
class LibraryImportService {
  /// 把粘贴文本拆成二维单元格：优先 Tab，其次竖线，再按中英文逗号/分号。
  static List<List<String>> rowsFromText(String text) {
    final rows = <List<String>>[];
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      List<String> cells;
      if (line.contains('\t')) {
        cells = line.split('\t');
        if (rawLine.endsWith('\t')) cells.add('');
      } else if (line.contains('|')) {
        cells = line.split('|');
        if (rawLine.endsWith('|')) cells.add('');
      } else if (RegExp(r'[,，;；]').hasMatch(line)) {
        cells = line.split(RegExp(r'[,，;；]'));
        if (RegExp(r'[,，;；]\s*$').hasMatch(rawLine)) cells.add('');
      } else {
        cells = [line];
      }
      cells = cells.map((cell) => cell.trim()).toList();
      // 两列式“表扬 认真听课”允许用空格分隔。
      if (cells.length == 1) {
        final match = RegExp(r'^(表扬|批评)\s+(.+)$').firstMatch(line);
        if (match != null) {
          cells = [match.group(1)!, match.group(2)!.trim()];
        }
      }
      if (cells.any((cell) => cell.isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  /// 解析原因库文本：支持“类型 / 时段 / 原因”三列与“类型 / 原因”两列。
  static ReasonImportPreview parseReasonsText(String text) {
    return _parseReasonRows(rowsFromText(text));
  }

  /// 解析原因库文件：支持 `.xlsx`、`.csv`、`.txt`。
  static Future<ReasonImportPreview> parseReasonsFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    final extension = _extensionOf(fileName);
    if (extension == 'txt') {
      return parseReasonsText(_decodeText(bytes));
    }
    if (extension == 'csv') {
      return _parseReasonRows(
        await TransferService.readRowsAsync(
          bytes,
          isCsv: true,
          headerKeywords: const {'类型', '原因'},
        ),
      );
    }
    if (extension == 'xlsx') {
      return _parseReasonRows(
        await TransferService.readRowsAsync(
          bytes,
          isCsv: false,
          headerKeywords: const {'类型', '原因'},
        ),
      );
    }
    throw const FormatException('原因库只支持 .xlsx、.csv、.txt 文件');
  }

  static ReasonImportPreview _parseReasonRows(List<List<String>> rows) {
    var skipped = 0;
    final parsed = TransferService.parseReasonsRows(
      rows,
      onSkipped: (value) => skipped = value,
    );
    return ReasonImportPreview(rows: parsed, skipped: skipped);
  }

  /// 解析时段文本：支持“时段 key / 标签”两列与只写标签的一列。
  static PeriodImportPreview parsePeriodsText(String text) {
    return _parsePeriodRows(rowsFromText(text));
  }

  /// 解析时段文件：支持 `.xlsx`、`.csv`、`.txt`。
  static Future<PeriodImportPreview> parsePeriodsFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    final extension = _extensionOf(fileName);
    if (extension == 'txt') {
      return parsePeriodsText(_decodeText(bytes));
    }
    if (extension == 'csv') {
      return _parsePeriodRows(
        await TransferService.readRowsAsync(
          bytes,
          isCsv: true,
          headerKeywords: const {'时段', '标签'},
        ),
      );
    }
    if (extension == 'xlsx') {
      return _parsePeriodRows(
        await TransferService.readRowsAsync(
          bytes,
          isCsv: false,
          headerKeywords: const {'时段', '标签'},
        ),
      );
    }
    throw const FormatException('时段表只支持 .xlsx、.csv、.txt 文件');
  }

  static PeriodImportPreview _parsePeriodRows(List<List<String>> rows) {
    final periods = <Map<String, String>>[];
    final seen = <String>{};
    var skipped = 0;
    final known = effectivePeriods();
    final keyByLabel = <String, String>{
      for (final item in known) item['label']!.trim(): item['key']!,
    };
    final knownKeys = <String>{
      ...timePeriods.keys,
      for (final item in known) item['key']!,
    };
    var start = 0;
    if (rows.isNotEmpty && rows.first.isNotEmpty) {
      final first = rows.first.map((cell) => cell.trim()).toList();
      if (first.contains('时段') || first.contains('标签')) start = 1;
    }
    for (var i = start; i < rows.length; i++) {
      final row = rows[i].map((cell) => cell.trim()).toList();
      if (row.every((cell) => cell.isEmpty)) continue;
      String keyText;
      String label;
      if (row.length >= 2 && row[1].isNotEmpty) {
        keyText = row[0];
        label = row[1];
      } else {
        keyText = '';
        label = row[0];
      }
      if (validatePeriodLabel(label) != null) {
        skipped++;
        continue;
      }
      var key = '';
      if (keyText.isNotEmpty) {
        if (knownKeys.contains(keyText) || keyText.startsWith('custom_')) {
          key = keyText;
        } else {
          key = matchTimePeriodKey(keyText, known);
        }
      }
      if (key.isEmpty) key = keyByLabel[label] ?? '';
      if (key.isEmpty) {
        key = 'custom_${DateTime.now().microsecondsSinceEpoch}_$i';
      }
      if (!seen.add(key)) {
        skipped++;
        continue;
      }
      periods.add({'key': key, 'label': label});
    }
    return PeriodImportPreview(periods: periods, skipped: skipped);
  }

  static String _extensionOf(String fileName) {
    final index = fileName.lastIndexOf('.');
    return index < 0 ? '' : fileName.substring(index + 1).toLowerCase();
  }

  static String _decodeText(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
      return _decodeUtf16(data, littleEndian: true);
    }
    if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
      return _decodeUtf16(data, littleEndian: false);
    }
    final String text;
    try {
      text = utf8.decode(data);
    } on FormatException {
      throw const FormatException('文件不是 UTF-8 编码，请另存为 UTF-8 后重试');
    }
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }
}
