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

/// 撤销最近一次记录变更的结果。
///
/// 审计 A-18b：撤销此前只改内存、`_save()` 立刻返回，界面无论落盘成败都提示
/// “已撤销本次记录”。现在撤销会 `await saveNow()`，把“内存撤销了几条”与
/// “是否真的写进磁盘”分开报给界面：
/// - [changed] 大于 0 表示内存里确实回滚了记录；
/// - [saved] 为 false 表示写盘失败（磁盘仍是撤销前的数据，重启会回到撤销前）。
class UndoResult {
  const UndoResult({required this.changed, required this.saved});

  /// 没有可撤销的操作时的结果。
  static const UndoResult none = UndoResult(changed: 0, saved: true);

  /// 内存里实际撤销的条数。
  final int changed;

  /// 撤销后的数据是否已成功写入磁盘。
  final bool saved;

  /// 是否有记录被真正撤销。
  bool get hasChanges => changed > 0;
}
