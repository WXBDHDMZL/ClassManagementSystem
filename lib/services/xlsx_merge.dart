/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-11-28
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 合并单元格展开工具（审计 P2-13）。
///
/// `excel` 包与 [XlsxReader] 读出的二维表里，合并区只有左上角单元格有值，
/// 其余位置是空串。表格里把「日期」或「学生姓名」纵向合并时，后续行会被
/// 导入逻辑当成"缺姓名/缺日期"静默计入跳过，用户看到的是"导入了但少了很多行"。
///
/// 这里把合并区左上角的值填充到整个区域，让合并与重复填写等价。
class XlsxMerge {
  XlsxMerge._();

  /// 按 [spans]（形如 `A1:A2`、`A4:G6`）把 [rows] 里合并区左上角的值铺满全区。
  ///
  /// [rows] 允许是锯齿状（不同行长度不同），缺失的格子按空串处理并补齐。
  static List<List<String>> fill(
    List<List<String>> rows,
    Iterable<String> spans,
  ) {
    if (rows.isEmpty || spans.isEmpty) return rows;
    final grid = [for (final row in rows) List<String>.from(row)];
    for (final span in spans) {
      final parts = span.split(':');
      if (parts.length != 2) continue;
      final start = _parseCellRef(parts[0]);
      final end = _parseCellRef(parts[1]);
      if (start == null || end == null) continue;
      final topRow = start.$1 < end.$1 ? start.$1 : end.$1;
      final bottomRow = start.$1 < end.$1 ? end.$1 : start.$1;
      final leftColumn = start.$2 < end.$2 ? start.$2 : end.$2;
      final rightColumn = start.$2 < end.$2 ? end.$2 : start.$2;
      if (topRow >= grid.length) continue;
      final sourceRow = grid[topRow];
      final value = leftColumn < sourceRow.length ? sourceRow[leftColumn] : '';
      if (value.isEmpty) continue;
      for (
        var rowIndex = topRow;
        rowIndex <= bottomRow && rowIndex < grid.length;
        rowIndex++
      ) {
        final row = grid[rowIndex];
        while (row.length <= rightColumn) {
          row.add('');
        }
        for (var column = leftColumn; column <= rightColumn; column++) {
          if (row[column].isEmpty) row[column] = value;
        }
      }
    }
    return grid;
  }

  /// 把 `A1` 解析成 `(行下标, 列下标)`，两者均从 0 开始；非法引用返回 null。
  static (int, int)? _parseCellRef(String reference) {
    final match = RegExp(
      r'^\$?([A-Za-z]+)\$?(\d+)$',
    ).firstMatch(reference.trim());
    if (match == null) return null;
    var column = 0;
    for (final code in match.group(1)!.toUpperCase().codeUnits) {
      column = column * 26 + (code - 64);
    }
    final rowNumber = int.tryParse(match.group(2)!);
    if (rowNumber == null || rowNumber < 1 || column < 1) return null;
    return (rowNumber - 1, column - 1);
  }
}
