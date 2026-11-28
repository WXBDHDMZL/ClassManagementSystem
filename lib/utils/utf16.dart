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

/// UTF-16 文本解码（名单 / 原因库 / 时段表导入共用）。
///
/// 审计 A-25：此前两个导入服务各自手写"每两字节拼一个 code unit"的循环，
/// 存在三个问题：奇数字节被静默丢弃、孤立代理项（半个 emoji）被原样写进库、
/// 同一段逻辑在两处重复实现容易漂移。这里统一成一处，并让坏数据明确报错，
/// 由调用方转成可见的导入错误，而不是生成不可见字符。
library;

/// 把 UTF-16 字节序列解码成字符串。
///
/// [bytes] 已去掉 BOM；[littleEndian] 表示字节序。
///
/// 抛出 [FormatException]（消息可展示给用户）的情况：
/// - 字节数为奇数（末字节无处配对）；
/// - 存在孤立代理项（高位 0xD800–0xDBFF 后未跟低位 0xDC00–0xDFFF，
///   或单独出现低位代理项）——这类数据在导出为表格或写回文件时会变成
///   替换字符，属于静默数据损坏。
String decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  if (bytes.isEmpty) return '';
  if (bytes.length.isOdd) {
    throw const FormatException(
      '文本文件声明为 UTF-16，但字节数为奇数，文件可能已损坏。请另存为 UTF-8 后重试。',
    );
  }

  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }

  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final next = i + 1 < units.length ? units[i + 1] : -1;
      if (next < 0xDC00 || next > 0xDFFF) {
        throw const FormatException(
          '文本文件声明为 UTF-16，但包含损坏的字符（缺少配对的代理项）。'
          '请另存为 UTF-8 后重试。',
        );
      }
      i++; // 跳过已配对低位代理项
      continue;
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const FormatException(
        '文本文件声明为 UTF-16，但包含损坏的字符（缺少配对的代理项）。'
        '请另存为 UTF-8 后重试。',
      );
    }
  }

  return String.fromCharCodes(units);
}
