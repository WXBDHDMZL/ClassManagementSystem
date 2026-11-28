/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 旧版动作标识：V3.0.0 起仅用于内部门禁/日志名称，
/// 不再由用户逐项配置。
enum PasswordAction {
  // 记录
  recordAddSingle,
  recordAddBatch,
  recordEdit,
  recordDelete,
  recordAppend,
  recordImport,
  recordExport,
  // 考勤
  attendanceRegister,
  attendanceUndo,
  attendanceSettings,
  attendanceImport,
  attendanceStatusImport,
  // 名单与原因库
  rosterModify,
  rosterImport,
  reasonModify,
  reasonImport,
  // 时间段
  periodModify,
  periodImport,
  // 数据与备份
  dataPackageExport,
  dataPackageImport,
  backupManual,
  backupRestore,
  logExport,
  logCleanup,
  factoryReset,
}
