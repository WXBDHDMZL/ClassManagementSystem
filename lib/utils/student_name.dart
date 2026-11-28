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

import 'record_text.dart';

/// 名单姓名校验：与记录侧共用同一长度上限，避免“名单里的名字 ≠ 记录里的名字”。
/// 返回 null 表示通过，否则返回可直接展示给用户的原因。
String? validateStudentName(String name) {
  final value = name.trim();
  if (value.isEmpty) return '姓名不能为空';
  if (value.length > RecordText.maxNameLength) {
    return '姓名不能超过 ${RecordText.maxNameLength} 个字（当前 ${value.length} 个字）';
  }
  return null;
}
