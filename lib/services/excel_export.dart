/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-10-02
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';
import 'dart:isolate';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../utils/file_names.dart';
import 'atomic_file.dart';

/// Excel 导出的统一入口：工作簿的创建、编码、列宽自适应与"保存到哪里"只在这里写一次。
///
/// 目的：此前 10 个导出点各自写 `Excel.createExcel()` / `encode()!`，
/// 一旦 `excel` 依赖升级改了 API，就要改多处并容易漏（这是本项目反复出现的
/// "两份实现漂移"模式）。现在依赖 API 只在本文档里出现。
class ExcelExport {
  ExcelExport._();

  /// 新建工作簿（访问 `book['Sheet1']` 时 excel 会自动建表）。
  static Excel newWorkbook() => Excel.createExcel();

  /// 编码为字节（写盘用）。
  ///
  /// 修复（审查 四-7）：`excel.encode()` 理论上可能返回 null，此前用 `!` 强解包
  /// 会抛空断言（用户看到的是内部错误），这里改成可读的异常。
  static List<int> encodeWorkbook(Excel book) {
    final bytes = book.encode();
    if (bytes == null) {
      throw StateError('工作簿编码失败（内容异常，无法生成 Excel 文件）');
    }
    return bytes;
  }

  /// [encodeWorkbook] 的隔离版本（性能批 H4）：xlsx 编码（zip 压缩）是纯计算，
  /// 数千行的大表可达数百毫秒，放后台 isolate 执行避免导出时冻结界面。
  /// 实测 `Excel` 工作簿对象可安全跨 isolate 传递（同一 isolate group 深拷贝）。
  static Future<List<int>> encodeWorkbookAsync(Excel book) {
    return Isolate.run(() => encodeWorkbook(book));
  }

  /// 按单元格内容自动调整列宽：中文等宽字符按 2 个单位计，另留边距。
  ///
  /// 修复（审查 二-1 的一部分）：此方法原在 `RecordList`（一个 Widget）里，
  /// 被考勤对话框与统计导出反向调用 —— 统计模块依赖界面组件，依赖方向倒置。
  /// 移到服务层后，界面只调用、不再互相依赖。
  ///
  /// 修复（审查 六-7）：逐字符改走 code units（避免 `split('')` 为每格新建列表）。
  static void autoFitColumns(Sheet sheet, {int minWidth = 10}) {
    final rows = sheet.rows;
    if (rows.isEmpty) return;
    var colCount = 0;
    for (final row in rows) {
      if (row.length > colCount) colCount = row.length;
    }
    for (var col = 0; col < colCount; col++) {
      var maxWidth = minWidth.toDouble();
      for (final row in rows) {
        if (col >= row.length) continue;
        final value = row[col]?.value;
        if (value == null) continue;
        // excel 包各 CellValue 的 toString 均返回纯文本内容。
        final text = value.toString();
        var width = 0.0;
        for (final code in text.codeUnits) {
          width += code > 0x7F ? 2 : 1;
        }
        if (width > maxWidth) maxWidth = width;
      }
      // Excel 列宽上限 255，另加 2 个单位边距。
      sheet.setColumnWidth(col, (maxWidth + 2).clamp(0.0, 255.0).toDouble());
    }
  }

  /// 保存工作簿：设置了导出目录就直接写进去，否则弹"另存为"对话框。
  /// 返回保存到的完整路径；用户取消返回 null。
  ///
  /// 修复（审查 二-1）：此前这段逻辑在 `RecordList.exportToExcel` 与
  /// `_ExportDomain._saveExcel` 里**各写一份**，且行为已经分歧
  ///（一处在提示前判 `context.mounted` 但不 return，一处直接 return）。
  /// 现在只有这一份实现，两处共用。
  ///
  /// G-35 修复：导出目录**先建好**（不存在时 `writeAsBytes` 直接失败）、
  /// 文件名**消毒**（非法字符/保留设备名）、写入改为**原子写**
  ///（唯一临时文件 → rename，避免中断留下半个文件）。
  static Future<String?> saveWorkbook(
    Excel workbook, {
    required String baseName,
    required String exportPath,
    String dialogTitle = '保存文件',
  }) async {
    // 性能批 H4：编码（zip 压缩）移入后台 isolate —— 全部导出（统计报表、
    // 考勤、今日/全部记录）都走这里，一处改动覆盖所有导出路径。
    final bytes = await encodeWorkbookAsync(workbook);
    final safeName = sanitizeFileName(baseName);
    if (exportPath.isNotEmpty) {
      await Directory(exportPath).create(recursive: true);
      final fullPath = '$exportPath/$safeName.xlsx';
      await AtomicFile.writeBytes(fullPath, bytes);
      return fullPath;
    }
    final result = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: '$safeName.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null) return null;
    await AtomicFile.writeBytes(result, bytes);
    return result;
  }
}
