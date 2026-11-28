/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../app_data_provider.dart';

/// AppDataProvider——名单与原因库域（学生增删改排序、原因库增删改排序、同步映射联动）。
///
/// `_ProviderBase` 的一个功能域（mixin 方法就是真正的类成员，
/// 可跨域调用、触发 notifyListeners；on 同 library 基类，其
/// 私有成员在此直接可见）。
mixin _RosterDomain on _ProviderBase {
  /// 新增学生：名称不得为空、不得超过长度上限且不得与他人重名，成功返回 true。
  bool addStudent(String name) {
    if (!_authorizedFor('library', action: PasswordAction.rosterModify)) {
      return false;
    }
    final value = name.trim();
    // N-3：与记录侧同一上限——否则 40 字姓名能进名单，
    // 而该生记录里的姓名会被截成 30 字，导致考勤把该生算作"名单外学生"。
    if (value.isEmpty || value.length > AppDataProvider.maxNameLength) {
      return false;
    }
    if (!_appData.addStudent(value)) return false;
    _log('名单变更', '新增学生 $value');
    _save();
    return true;
  }

  /// 重命名学生：同步更新所有历史记录中的该学生姓名，
  /// 名称不得为空且不得与他人重名，成功返回 true。
  bool renameStudent(String oldName, String newName) {
    if (!_authorizedFor('library', action: PasswordAction.rosterModify)) {
      return false;
    }
    final value = newName.trim();
    // N-3：与新增同一口径，否则改名可以绕过长度上限。
    if (value.isEmpty || value.length > AppDataProvider.maxNameLength) {
      return false;
    }
    if (value == oldName) return true;
    final index = _appData.students.indexOf(oldName);
    if (index == -1) return false;
    if (_appData.students.contains(value)) return false;
    // 该姓名若已出现在历史记录或考勤里（可能是已从名单移除的学生），
    // 改名会把两人的数据合并，这里直接拒绝。
    if (_existingNames().contains(value)) return false;
    _appData.replaceStudentAt(index, value);
    // 记录为不可变对象，需逐条重建；改名后历史记录随之更新。
    // R-1：这里改用 entries 迭代，拿到**桶键**作为日期兜底（此前用 values
    // 拿不到桶键，只能退回"今天"，会把 date 为空的历史记录写错日期）。
    for (final entry in _appData.recordsByDate.entries) {
      final bucketDate = entry.key;
      final records = entry.value;
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        if (record.studentName != oldName) continue;
        // N-2：改名同样走唯一入口（新名字已由 addStudent 侧统一裁剪，
        // 这里再走一遍保证记录与名单用的是同一口径）。
        records[i] = _buildRecord(
          id: record.id,
          studentName: value,
          operationType: record.operationType,
          reasons: record.reasons.split('、'),
          periodKey: record.periodKey,
          remark: record.remark,
          date: _recordRelativeDate(record, bucketDate),
          timestamp: record.timestamp,
          isAppended: record.isAppended,
          isImported: record.isImported,
          isBatch: record.isBatch,
          // 改名是"搬运既有数据"，原始时段标签与空键都要原样保留。
          periodNameOverride: record.periodName,
          normalizePeriodKey: false,
          recordedBy: record.recordedBy,
          createdByIdentityId: record.createdByIdentityId,
          createdAtIso: record.createdAtIso,
        );
      }
    }
    _log('名单变更', '学生改名 $oldName → $value（记录与考勤同步更新）');
    // 改名已重建全部历史记录，旧的撤销快照指向改名前的数据；若此刻撤销会
    // 把旧姓名的记录写回，产生"名单外学生"脏数据（审计 P2-9），故作废快照。
    _lastRecordUndo = null;
    // 历史考勤同样跟随改名，避免名单与考勤对不上。
    // 注意用 copyWith 保留时间段与同步关联，否则分时段考勤会塌成"全天"、同步链断裂。
    for (final attendance in _appData.attendanceByDate.values) {
      for (var i = 0; i < attendance.length; i++) {
        final item = attendance[i];
        if (item.studentName != oldName) continue;
        attendance[i] = item.copyWith(studentName: value);
      }
    }
    _save();
    return true;
  }

  /// 当前数据里出现过的全部姓名（名单 + 历史记录 + 考勤）。
  Set<String> _existingNames() {
    final names = <String>{
      ..._appData.students,
      for (final records in _appData.recordsByDate.values)
        for (final record in records) record.studentName,
      for (final records in _appData.attendanceByDate.values)
        for (final record in records) record.studentName,
    }..removeWhere((name) => name.isEmpty);
    return names;
  }

  /// 从名单中移除学生，成功返回 true（历史记录保持不变）。
  bool removeStudent(String name) {
    if (!_authorizedFor('library', action: PasswordAction.rosterModify)) {
      return false;
    }
    final removed = _appData.removeStudent(name);
    if (removed) {
      _log('名单变更', '移除学生 $name（历史记录与考勤保留）');
      _save();
    }
    return removed;
  }

  /// 名单拖动排序（参数为 ReorderableListView.onReorderItem 已调整后的位置）。
  void reorderStudents(int oldIndex, int newIndex) {
    if (!_authorizedFor('library', action: PasswordAction.rosterModify)) {
      return;
    }
    final list = _appData.students;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list[oldIndex];
    final target = _appData.moveStudent(oldIndex, newIndex);
    if (target < 0) return;
    _log('名单变更', '调整排序：$item 移到第 ${target + 1} 位');
    _save();
  }

  /// 清空学生名单（不回溯修改历史记录中的姓名）。
  /// 出厂名单为空，不再内置任何真实或示例姓名。
  /// 清空名单，返回是否已进入落盘队列。
  ///
  /// 审计 P3：旧实现返回 void，界面调用后无条件提示"名单已清空"——
  /// 未授权或写盘阻断时名单其实没动，提示与事实相反。
  bool clearStudents() {
    if (!_authorizedFor('library', action: PasswordAction.rosterModify)) {
      return false;
    }
    _appData.setStudents(const <String>[]);
    _log('名单变更', '清空名单');
    return _save();
  }

  /// 整体替换原因库。未授权返回 false（调用方不得再提示“已替换”）。
  bool setReasons(ReasonLibrary library) {
    if (!_authorizedFor('library', action: PasswordAction.reasonImport)) {
      return false;
    }
    // 修复（审计 P1-9）：替换导入此前绕过净化 —— 含顿号/超长原因会直接入库，
    // 破坏"原因以顿号拼接存储"的不变量；现与"补充"路径（addReason）统一口径。
    final sanitized = _sanitizedReasonLibrary(library);
    _log(
      '原因库',
      '整体替换为导入的内容（表扬 ${sanitized.praise.length} 组 / '
          '批评 ${sanitized.criticism.length} 组）',
    );
    _appData.setReasons(sanitized);
    _save();
    return true;
  }

  /// 恢复默认原因库。未授权返回 false。
  bool resetReasons() {
    if (!_authorizedFor('library', action: PasswordAction.reasonModify)) {
      return false;
    }
    _log('原因库', '恢复为出厂默认（自定义内容被清空）');
    _appData.setReasons(ReasonLibrary.defaults());
    _save();
    return true;
  }

  /// 重命名指定分组内的原因，成功返回 true。
  bool renameReason(
    String operationType,
    String periodKey,
    String oldReason,
    String newReason,
  ) {
    if (!_authorizedFor('library', action: PasswordAction.reasonModify)) {
      return false;
    }
    final value = _sanitizeReasonText(newReason);
    if (value.isEmpty) return false;
    if (!_appData.reasons.renameReason(
      operationType,
      periodKey,
      oldReason,
      value,
    )) {
      return false;
    }
    // 审计 P1-3：考勤同步映射是"状态 → 原因文本"的全局表（持久化格式冻结，
    // 没有时段维度）。只有当该原因在**所有分组**里都已不存在时，映射才必须
    // 跟着改名；否则仍留在其它分组的原因还要靠旧文本命中映射。
    if (!_reasonExistsInAnyGroup(operationType, oldReason)) {
      _renameSyncMapReason(oldReason, value);
    }
    // G-7：历史记录里的原因文本一并更新 —— 否则旧记录在再编辑时按原因反查映射
    // 不命中，`_resyncRecordEdit` 会撤销掉原本关联的考勤（隐性数据关联断裂）。
    // 与 renameStudent 的"改名同步历史"保持一致。
    // 审计 P1-3 根因修复：必须按 [periodKey] 精确匹配 —— 此前只按操作类型过滤，
    // 而「睡觉/趴桌」等文本同时存在于 5 个时段组，改一处会污染其余四组的历史。
    _renameReasonInRecordHistory(operationType, periodKey, oldReason, value);
    _log(
      '原因库',
      '原因改名 $oldReason → $value'
          '（$periodKey 分组历史记录同步更新）',
    );
    _save();
    return true;
  }

  /// 该原因是否仍存在于指定操作类型的任意分组（含全时段通用分组）。
  bool _reasonExistsInAnyGroup(String operationType, String reason) {
    final map = operationType == '表扬'
        ? _appData.reasons.praise
        : _appData.reasons.criticism;
    for (final group in map.values) {
      if (group.contains(reason)) return true;
    }
    return false;
  }

  /// 记录是否属于被改名的原因分组。
  ///
  /// `_common` 是全时段通用分组，改名必须影响该类型下的全部记录；具体分组
  /// 只影响同组记录；记录时段键为空（无法识别的导入数据）时无法判断归属，
  /// 保守跳过，避免把别的组的历史改坏。
  static bool _recordBelongsToGroup(StudentRecord record, String periodKey) {
    if (periodKey == '_common') return true;
    if (record.periodKey == periodKey) return true;
    // 记录侧把"未选时段"规整成 all_day，原因分组侧没有对应项时不强行匹配。
    return false;
  }

  /// 把历史记录里的旧原因文本替换为新原因（同类型 + 同时段分组）。
  void _renameReasonInRecordHistory(
    String operationType,
    String periodKey,
    String oldReason,
    String newReason,
  ) {
    for (final records in _appData.recordsByDate.values) {
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        if (record.operationType != operationType) continue;
        if (!_recordBelongsToGroup(record, periodKey)) continue;
        final parts = record.reasons.split('、');
        if (!parts.contains(oldReason)) continue;
        records[i] = record.copyWith(
          reasons: [
            for (final reason in parts)
              reason == oldReason ? newReason : reason,
          ].join('、'),
        );
      }
    }
  }

  /// 批评原因改名/删除时同步维护"考勤状态 → 批评原因"的映射，
  /// 否则映射会指向已不存在的旧原因，双向同步随之失效。
  void _renameSyncMapReason(String oldReason, String newReason) {
    final map = Map<String, String>.from(_appData.settings.attendanceSyncMap);
    var changed = false;
    map.forEach((status, reason) {
      if (reason != oldReason) return;
      map[status] = newReason;
      changed = true;
    });
    if (changed) {
      _appData.settings = _appData.settings.copyWith(attendanceSyncMap: map);
    }
  }

  void _removeSyncMapReason(String reason) {
    final map = Map<String, String>.from(_appData.settings.attendanceSyncMap);
    final before = map.length;
    map.removeWhere((status, value) => value == reason);
    if (map.length != before) {
      _appData.settings = _appData.settings.copyWith(attendanceSyncMap: map);
    }
  }

  /// 删除指定分组内的原因，成功返回 true。
  bool removeReason(String operationType, String periodKey, String reason) {
    if (!_authorizedFor('library', action: PasswordAction.reasonModify)) {
      return false;
    }
    final removed = _appData.reasons.removeReason(
      operationType,
      periodKey,
      reason,
    );
    if (removed) {
      // 审计 P1-3：该原因若仍存在于其它分组，全局同步映射不能删——否则别的
      // 分组里同名的原因会突然失去"记录 → 考勤"的联动。
      if (!_reasonExistsInAnyGroup(operationType, reason)) {
        _removeSyncMapReason(reason);
      }
      _log('原因库', '删除原因 $reason');
      _save();
    }
    return removed;
  }

  /// 原因拖动排序（参数为 ReorderableListView.onReorderItem 已调整后的位置）。
  void reorderReasons(
    String operationType,
    String periodKey,
    int oldIndex,
    int newIndex,
  ) {
    if (!_authorizedFor('library', action: PasswordAction.reasonModify)) {
      return;
    }
    // 先取移动项与目标位置用于日志；实际变更交由原因库（内部数据不外泄）。
    final group = _appData.reasons.groupReasons(operationType, periodKey);
    if (oldIndex < 0 || oldIndex >= group.length) return;
    final item = group[oldIndex];
    final target = _appData.reasons.reorderReason(
      operationType,
      periodKey,
      oldIndex,
      newIndex,
    );
    if (target < 0) return;
    _log(
      '原因库',
      '调整排序：$item 移到 $operationType · ${getTimePeriodName(periodKey)} 第 ${target + 1} 位',
    );
    _save();
  }
}
