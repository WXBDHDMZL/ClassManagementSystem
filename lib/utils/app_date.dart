/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-10-01
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

// 日期字符串校验的唯一入口。
//
// 背景：项目里曾同时存在三种口径——记录导入用严格校验，考勤导入与设置日期
// 只查长度10且含两个-，导致 2026-13-45 这类日期被当作合法数据入库/生效。
// 所有需要校验 yyyy-MM-dd 的地方一律使用 isValidYmdDate（滚动即非法）。

/// 日期年份的允许范围（1900–2100）——日期校验与统计解析共用同一口径。
const int kMinSupportedYear = 1900;
const int kMaxSupportedYear = 2100;

/// 日期区间长度上限（约 10 年）：`datesBetween`（统计区间）使用，
/// 防止极端输入（如 1900→2100）生成数万条而长时间占用 UI 线程。
const int kMaxDateRangeDays = 3660;

/// 把 `yyyy-MM-dd` 显示成 `yyyy年M月D日`；格式不符时原样返回。
///
/// 此前 record_list 与 attendance_dialog 各写一份（后者还多一个永不触发的
/// try/catch），统一到这里，避免两处实现漂移。
String formatChineseDate(String dateStr) {
  final parts = dateStr.split('-');
  if (parts.length == 3) {
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }
  return dateStr;
}

/// 两位数补零（yyyy-MM-dd、HH:mm:ss 等格式化的公共构件）。
///
/// 审查 M10：此前全项目有 6 份不同名的 padLeft(2,'0') 实现（two/pad/_pad/裸内联），
/// 并已实际出现过"一处产出 2026-1、另一处产出 2026-01"的不一致。统一到这里。
String twoDigit(int value) => value.toString().padLeft(2, '0');

/// 格式化日期为 `yyyy-MM-dd`（与校验、桶键、统计口径统一的唯一写法）。
String formatYmd(DateTime date) =>
    '${date.year}-${twoDigit(date.month)}-${twoDigit(date.day)}';

/// 格式化月份为 `yyyy-MM`（月度统计标签、按月分文件的日志名）。
String formatYm(DateTime date) => '${date.year}-${twoDigit(date.month)}';

// 是否为真实存在的公历日期（yyyy-MM-dd），滚动即非法。
bool isValidYmdDate(String text) {
  if (text.length != 10) return false;
  final parts = text.split('-');
  if (parts.length != 3) return false;
  // 修复（1.9，2026-10-03 审查）：每段必须**只含数字** —— `int.tryParse('+1')`
  // 返回 1，此前 `2026-01-+1` 会被判为合法日期，脏字符串因此可以进入统计区间。
  for (final part in parts) {
    if (part.isEmpty) return false;
    for (final code in part.codeUnits) {
      if (code < 0x30 || code > 0x39) return false;
    }
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return false;
  // 复查 3.1：下界从 2000 放宽到 1900 —— 上游表格解析（import_service
  // `_normalizeDate`）放行 1900–9999，下游若只认 2000+ 会把"上游判合法、
  // 下游判非法"的记录**静默丢弃**（用户看到"可导入 1 条"、结果是 0 条）。
  // 上界统一到 2100（统计侧 parseDate 同口径）。
  if (year < kMinSupportedYear || year > kMaxSupportedYear) return false;
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > 31) return false;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}
