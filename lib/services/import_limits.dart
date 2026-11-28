/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-28
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// 导入上限被突破时抛出。继承 [FormatException]，这样已经按
/// `on FormatException` 分流"文件格式不对"的调用方（名单导入预览等）
/// 会直接把 [message] 当成可读错误展示给用户，不需要额外改造。
///
/// 审计 A-08：此前 Excel/CSV/Word/数据包的导入路径完全没有体积、解压量
/// 与行数上限。一个几百 MB 的表格、或压缩比 1000:1 的 zip 炸弹，会在
/// `ZipDecoder().decodeBytes()` / `Excel.decodeBytes()` 里直接把内存吃光，
/// 表现为"点导入后程序卡死或静默退出"，属于必须挡住的可利用面。
class ImportLimitException extends FormatException {
  ImportLimitException(super.message);
}

/// 导入的硬上限。数值按"一个班级一学年的真实数据量 + 充裕余量"取整：
/// 20 MB 的表格约等于三十万行文本；80 MB 解压量足够放下几千张表；
/// 2 万行远超任何一学期的记录条数。
class ImportLimits {
  ImportLimits._();

  /// 单个导入文件的字节上限（压缩后的大小）。
  static const int maxFileBytes = 20 * 1024 * 1024;

  /// 单个 zip 容器（xlsx/docx）解压后的总字节上限。
  static const int maxZipUncompressedBytes = 80 * 1024 * 1024;

  /// 单个 zip 容器的条目数上限（防御"几十万个小条目"式的解压放大）。
  static const int maxZipEntries = 5000;

  /// 单个表格/文本的行数上限。
  static const int maxRows = 20000;

  /// 测试用的可下调上限：真实阈值（20 MB / 80 MB / 5000 / 20000）没法在
  /// 单测里造出对应体量的样本，所以允许测试把阈值临时调低来验证拦截分支。
  /// 只允许下调，[debugResetLimits] 恢复默认值。
  static int _testFileBytes = maxFileBytes;
  static int _testZipUncompressedBytes = maxZipUncompressedBytes;
  static int _testZipEntries = maxZipEntries;
  static int _testRows = maxRows;

  @visibleForTesting
  static void debugLowerLimits({
    int? fileBytes,
    int? zipUncompressedBytes,
    int? zipEntries,
    int? rows,
  }) {
    if (fileBytes != null) _testFileBytes = _clampDown(fileBytes, maxFileBytes);
    if (zipUncompressedBytes != null) {
      _testZipUncompressedBytes = _clampDown(
        zipUncompressedBytes,
        maxZipUncompressedBytes,
      );
    }
    if (zipEntries != null) _testZipEntries = _clampDown(zipEntries, maxZipEntries);
    if (rows != null) _testRows = _clampDown(rows, maxRows);
  }

  @visibleForTesting
  static void debugResetLimits() {
    _testFileBytes = maxFileBytes;
    _testZipUncompressedBytes = maxZipUncompressedBytes;
    _testZipEntries = maxZipEntries;
    _testRows = maxRows;
  }

  static int _clampDown(int value, int max) => value < max ? value : max;

  /// 检查原始字节数。
  static void ensureFileBytes(int bytes, {String what = '文件'}) {
    if (bytes <= 0) return;
    if (bytes > _testFileBytes) {
      throw ImportLimitException(
        '$what过大（${_mb(bytes)} MB），上限 ${_mb(_testFileBytes)} MB；'
        '请删除多余的工作表或拆分成多个文件后再导入',
      );
    }
  }

  /// 检查 zip 容器的条目数与解压后总字节。
  ///
  /// 只读中央目录里的声明值（[ArchiveFile.size]），不触发解压，因此
  /// 检查本身不会被 zip 炸弹撑爆内存。
  static void ensureZipPayload(List<int> bytes, {String what = '文件'}) {
    ensureFileBytes(bytes.length, what: what);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } on Object {
      // 不是合法 zip：交给调用方原来的解析流程去报"格式不正确"。
      return;
    }
    if (archive.length > _testZipEntries) {
      throw ImportLimitException(
        '$what里的条目过多（${archive.length} 个），上限 $_testZipEntries 个',
      );
    }
    var total = 0;
    for (final file in archive) {
      total += file.size;
      if (total > _testZipUncompressedBytes) {
        throw ImportLimitException(
          '$what解压后超过 ${_mb(_testZipUncompressedBytes)} MB，'
          '可能是压缩炸弹或表格体积过大；请拆分成多个文件后再导入',
        );
      }
    }
  }

  /// 检查表格/文本行数。
  static void ensureRowCount(int rows, {String what = '表格'}) {
    if (rows > _testRows) {
      throw ImportLimitException(
        '$what行数过多（$rows 行），上限 $_testRows 行；'
        '请拆分成多个文件后再导入',
      );
    }
  }

  static String _mb(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1);
}
