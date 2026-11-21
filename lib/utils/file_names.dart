/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-10-04
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 文件名消毒（Windows 安全）。
///
/// 背景（G-35）：导出时会把用户可见的文本（导出前缀、列表名等）拼进文件名。
/// 一旦含 `\ / : * ? " < > |`、控制字符或 `..`，轻则写盘失败，重则把文件写到
/// 导出目录之外（路径逃逸）。所有拼文件名的地方统一走这里。
library;

/// Windows 保留设备名：这些名字（含带扩展名形式）不能作为文件名。
const Set<String> _reservedNames = {
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// 消毒文件名：去掉非法/控制字符、折叠 `..`、去掉首尾空白。
/// 命中 Windows 保留设备名或消毒后为空时回退 [fallback]。
String sanitizeFileName(String name, {String fallback = '导出文件'}) {
  var value = name
      // 控制字符（0x00-0x1F）在 Windows 文件名里非法。
      .replaceAll(RegExp(r'[\x00-\x1f]'), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll('..', '')
      .trim();
  // Windows 不允许文件名以点结尾（"abc." 会被静默去点后与 "abc" 冲突）。
  while (value.endsWith('.')) {
    value = value.substring(0, value.length - 1);
  }
  if (value.isEmpty) return fallback;
  // 保留设备名（如 CON、CON.xlsx）同样非法：整名回退，避免用户意外。
  final stem = value.split('.').first.toUpperCase();
  if (_reservedNames.contains(stem)) return fallback;
  return value;
}
