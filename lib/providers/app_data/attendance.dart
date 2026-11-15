/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../app_data_provider.dart';

/// AppDataProvider——考勤域（考勤设置、同步映射、批量考勤、考勤↔记录双向同步）。
///
/// `_ProviderBase` 的一个功能域（mixin 方法就是真正的类成员，
/// 可跨域调用、触发 notifyListeners；on 同 library 基类，其
/// 私有成员在此直接可见）。
mixin _AttendanceDomain on _ProviderBase {
  /// 保存考勤开关。
  void setAttendanceEnabled(bool enabled) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceSettings)) {
      return;
    }
    _appData.settings = _appData.settings.copyWith(attendanceEnabled: enabled);
    _log('考勤', enabled ? '启用考勤功能' : '关闭考勤功能');
    _save();
  }

  /// 保存"计入未到"的状态名单（影响"实到"人数统计）。
  void setAttendanceAbsentStatuses(List<String> statuses) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceSettings)) {
      return;
    }
    final valid = [
      for (final status in _appData.settings.attendanceStatuses)
        if (statuses.contains(status)) status,
    ];
    _appData.settings = _appData.settings.copyWith(
      attendanceAbsentStatuses: List<String>.unmodifiable(valid),
    );
    _log('考勤状态项', '计入未到的状态：${valid.isEmpty ? '无' : valid.join('、')}');
    _save();
  }

  /// 保存考勤状态项列表（界面已保证至少一项、非空且不重名，且不含保留词"出勤"）。
  /// 删除的状态项会同时从"同步到批评"的映射与"计入未到"名单里移除。
  void setAttendanceStatuses(List<String> statuses) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceSettings)) {
      return;
    }
    // 修复（审查四 G-6）：provider 层校验（此前只靠 UI）——去重、拒绝空与
    // 保留词"出勤"；非法值不入库，避免与"校验只在 UI"的旧隐患同类。
    final seen = <String>{};
    final cleaned = <String>[];
    for (final raw in statuses) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (AttendanceRecord.validateStatus(value) != null) continue;
      if (seen.add(value)) cleaned.add(value);
    }
    if (cleaned.isEmpty) return; // 至少要保留一个状态项，否则不保存。
    statuses = cleaned;
    _log('考勤状态项', '保存 ${statuses.length} 个状态项');
    final syncMap = Map<String, String>.from(
      _appData.settings.attendanceSyncMap,
    )..removeWhere((status, _) => !statuses.contains(status));
    // 新增的状态项默认按名称推断是否算"未到"（含"假/缺"）；
    // 已有状态项一律**沿用用户手动设置**，不再按名称重算，
    // 否则用户手动取消"计为未到"后，一新增状态项就会被悄悄改回来。
    final previousStatuses = _appData.settings.attendanceStatuses;
    final previousAbsent = _appData.settings.attendanceAbsentStatuses;
    final absent = <String>{
      for (final status in statuses)
        if (previousAbsent.contains(status) ||
            (!previousStatuses.contains(status) &&
                AppSettings.guessAbsentByName(status)))
          status,
    };
    _appData.settings = _appData.settings.copyWith(
      attendanceStatuses: List<String>.unmodifiable(statuses),
      attendanceSyncMap: syncMap,
      attendanceAbsentStatuses: List<String>.unmodifiable(absent),
    );
    _save();
  }

  /// 重命名考勤状态项：同步更新历史考勤记录与该状态的同步映射。
  void renameAttendanceStatus(String oldStatus, String newStatus) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceSettings)) {
      return;
    }
    final value = newStatus.trim();
    if (value.isEmpty || value == oldStatus) return;
    // 修复（审计 P2-31）：provider 层补保留词/非法值校验（此前只靠 UI）。
    if (AttendanceRecord.validateStatus(value) != null) return;
    final statuses = _appData.settings.attendanceStatuses;
    final index = statuses.indexOf(oldStatus);
    if (index == -1 || statuses.contains(value)) return;
    final updated = List<String>.from(statuses);
    updated[index] = value;
    final syncMap = Map<String, String>.from(
      _appData.settings.attendanceSyncMap,
    );
    if (syncMap.containsKey(oldStatus)) {
      syncMap[value] = syncMap.remove(oldStatus)!;
    }
    final absent = List<String>.from(
      _appData.settings.attendanceAbsentStatuses,
    );
    final absentIndex = absent.indexOf(oldStatus);
    if (absentIndex != -1) {
      absent[absentIndex] = value;
    }
    _log('考勤状态项', '改名 $oldStatus → $value（历史考勤同步更新）');
    _appData.settings = _appData.settings.copyWith(
      attendanceStatuses: List<String>.unmodifiable(updated),
      attendanceSyncMap: syncMap,
      attendanceAbsentStatuses: List<String>.unmodifiable(absent),
    );
    for (final date in _appData.attendanceByDate.keys.toList()) {
      final list = _appData.attendanceByDate[date]!;
      for (var i = 0; i < list.length; i++) {
        final record = list[i];
        if (record.status != oldStatus) continue;
        list[i] = record.copyWith(status: value);
      }
    }
    _save();
  }

  /// 使用某状态的考勤记录条数（删除状态项前提示用）。
  int countAttendanceWithStatus(String status) {
    var count = 0;
    for (final list in _appData.attendanceByDate.values) {
      for (final record in list) {
        if (record.status == status) count++;
      }
    }
    return count;
  }

  // ---------- 考勤与批评记录的同步 ----------

  /// 保存"考勤状态 → 批评原因"的同步映射；新用到的原因会自动补进批评原因库，
  /// 保证在记录对话框里能选到。
  void setAttendanceSyncMap(Map<String, String> map) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceSettings)) {
      return;
    }
    // 修复（审计 P2-36）：映射的状态键若不在状态项里，先补进状态项 —— 此前会
    // 形成"幽灵映射"（该状态不出现在考勤界面，映射永不命中；反查还可能把
    // 幽灵状态写进考勤）。自动补入与"先配映射、再用该状态登记"的既有用法兼容。
    final missingStatuses = <String>[
      for (final key in map.keys)
        if (key.trim().isNotEmpty &&
            !_appData.settings.attendanceStatuses.contains(key.trim()) &&
            AttendanceRecord.validateStatus(key.trim()) == null)
          key.trim(),
    ];
    final cleaned = <String, String>{};
    map.forEach((status, reason) {
      // P2-6 修复：映射值走统一净化（此前仅 trim，含顿号的值会让原因串 2→4→6 段膨胀）。
      final value = _sanitizeReasonText(reason);
      if (value.isEmpty) return;
      cleaned[status] = value;
    });
    _log('考勤同步映射', '保存 ${cleaned.length} 项');
    // 修复（审查四 B-1）：_batch 只有在内部有人调用过 _save() 才 flush —— 清空映射
    //（循环零次）或原因已存在（addReason 不触发 _save）时，settings 变更会静默丢失。
    // N-3：把 `_save()` 移进批次末尾统一一次 —— 此前它在批次外先写一遍，批次内
    // addReason 成功再写一遍，补了新原因时两次全库写盘 / 两次 notify。
    // 报告 H9 连带优化：补状态项也收进同一批次，整次调用只落盘一次。
    _batch(() {
      if (missingStatuses.isNotEmpty) {
        setAttendanceStatuses([
          ..._appData.settings.attendanceStatuses,
          ...missingStatuses,
        ]);
      }
      _appData.settings = _appData.settings.copyWith(
        attendanceSyncMap: cleaned,
      );
      for (final reason in cleaned.values) {
        addReason('批评', '_common', reason);
      }
      // 挂起期间只置 _savePending，批次结束时统一落盘，保证映射变更必落盘。
      _save();
    });
  }

  // ---------- 统计周期 ----------

  /// 每周起始日：1=周一 … 7=周日。
  void setWeekStart(int weekStart) {
    if (weekStart < 1 || weekStart > 7) return;
    _appData.settings = _appData.settings.copyWith(weekStart: weekStart);
    _log('统计设置', '每周起始日改为 $weekStart');
    _save();
  }

  // ---------- 考勤数据 ----------

  /// 区间内的考勤记录（按日期升序展开，供统计与导出使用）。
  List<AttendanceRecord> getAttendanceForDates(Iterable<String> dates) {
    final result = <AttendanceRecord>[];
    for (final date in dates.toList()..sort()) {
      result.addAll(getAttendanceForDate(date));
    }
    return result;
  }

  /// 有考勤记录的日期（从新到旧）。
  List<String> getAttendanceDates() {
    return _appData.attendanceByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));
  }

  /// 登记/修改某学生某时间段的考勤状态；status 为空表示撤销（恢复为出勤）。
  /// 返回 true 表示数据确实发生变化（用于界面提示"未改动"）。
  bool setAttendance(
    String studentName,
    String status, {
    required String date,
    String periodKey = AttendanceRecord.allDayKey,
    PasswordAction action = PasswordAction.attendanceRegister,
  }) {
    return setAttendanceForStudents(
      [studentName],
      status,
      date: date,
      periodKey: periodKey,
      action: action,
    ) > 0;
  }

  /// 批量导入考勤（同一天同一学生同一时间段以导入的为准），返回写入条数。
  /// 导入记录允许 id 为空（表格导入时没有 id），由这里分配。
  int importAttendance(Iterable<AttendanceRecord> records) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceImport)) {
      return 0;
    }
    var imported = 0;
    for (final record in records) {
      final date = record.date;
      final name = record.studentName.trim();
      if (date.isEmpty || name.isEmpty) continue;
      // 修复（审查 P2-8）：状态必须合法（非空、非保留的"出勤"）——
      // 否则会破坏"未登记即出勤"的不变量并污染 byStatus/presentCount 统计。
      if (AttendanceRecord.validateStatus(record.status) != null) continue;
      final periodKey = record.periodKey.isEmpty
          ? AttendanceRecord.allDayKey
          : record.periodKey;
      final list = _appData.attendanceByDate.putIfAbsent(
        date,
        () => <AttendanceRecord>[],
      );
      final index = list.indexWhere(
        (r) => r.studentName == name && r.periodKey == periodKey,
      );
      if (index == -1) {
        list.add(
          record.copyWith(
            id: record.id.isEmpty ? _generateUniqueRecordId() : record.id,
            studentName: name,
            periodKey: periodKey,
            // G-5：导入新增一律清空 syncedRecordId —— 外部包里的链接 id 与本机无关，
            // 透传后与本机某条记录撞号时，删那条记录会连带删掉这条导入考勤。
            syncedRecordId: '',
          ),
        );
        imported++;
        continue;
      }
      final old = list[index];
      if (old.status == record.status) {
        // 状态没变，但表格带了记录人时按导入值更新；没带则保留原记录人，
        // 与记录表格导入“没有记录人列不擦除留痕”的口径一致。
        if (record.recordedBy.isNotEmpty &&
            record.recordedBy != old.recordedBy) {
          list[index] = old.copyWith(recordedBy: record.recordedBy);
          imported++;
        }
        continue;
      }
      // X-13 修复：旧考勤若关联的是一条"考勤同步"派生批评记录，导入覆盖掉状态后
      // 这条记录会变成孤儿——在册但不再对应任何考勤，批评统计里持续计数。
      // 解绑的同时一并删除它。只删带同步标记的记录：老师自己录的批评记录
      //（记录→考勤方向）保留，避免误删真实记录。
      final linkId = old.syncedRecordId;
      if (linkId.isNotEmpty) {
        final linkedRecords = _appData.recordsByDate[date];
        if (linkedRecords != null) {
          final recordCountBefore = linkedRecords.length;
          linkedRecords.removeWhere(
            (r) =>
                r.id == linkId &&
                r.remark == AppDataProvider.attendanceSyncMarker,
          );
          if (linkedRecords.length != recordCountBefore && linkedRecords.isEmpty) {
            _appData.recordsByDate.remove(date);
          }
        }
      }
      // P2-9 修复：状态被导入覆盖时，旧的"记录同步"关联显式解绑——
      // 否则会出现"考勤=请假、关联批评=迟到"的自相矛盾且不会自愈。
      list[index] = old.copyWith(
        status: record.status,
        timestamp: record.timestamp.isEmpty ? old.timestamp : record.timestamp,
        // 修复（5.3）：原来是 `isEmpty ? '' : ''`（两个分支相同），
        // 行为上等于无条件解绑，但写法极易被误读成"有条件解绑"。
        syncedRecordId: '',
        // 与记录导入一致：表格带记录人则采用，没带则保留原记录人。
        recordedBy: record.recordedBy.isEmpty
            ? old.recordedBy
            : record.recordedBy,
      );
      if (linkId.isNotEmpty) {
        _log('考勤导入', '$name 原状态 ${old.status}（关联记录）被导入覆盖，已解除关联');
      }
      imported++;
    }
    if (imported > 0) {
      _log('考勤导入', '写入 $imported 条');
      // 注意：导入是"搬数据"，这里**不**做"考勤 → 批评记录"的同步，
      // 否则每导入一次就会凭空多出一批"考勤同步"的批评记录。
      _save();
    }
    return imported;
  }

  /// 把数据里用到的考勤状态补进状态项（保持现有顺序，新增追加在末尾），返回新增个数。
  int mergeAttendanceStatuses(Iterable<String> statuses) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceStatusImport)) {
      return 0;
    }
    // 说明：合并结果会写日志（在下方 added > 0 分支里）。
    final current = _appData.settings.attendanceStatuses;
    final merged = List<String>.from(current);
    var added = 0;
    for (final status in statuses) {
      final value = status.trim();
      if (value.isEmpty || merged.contains(value)) continue;
      if (AttendanceRecord.validateStatus(value) != null) continue;
      merged.add(value);
      added++;
    }
    if (added > 0) {
      // 与"设置 → 时间与考勤 → 考勤"里手动新增状态项的行为保持一致：
      // 名称含"假/缺"的新状态默认计入未到；已有状态项不动用户的手动设置。
      final absent = <String>{
        ..._appData.settings.attendanceAbsentStatuses,
        for (final status in merged)
          if (!current.contains(status) &&
              AppSettings.guessAbsentByName(status))
            status,
      };
      _appData.settings = _appData.settings.copyWith(
        attendanceStatuses: List<String>.unmodifiable(merged),
        attendanceAbsentStatuses: List<String>.unmodifiable(absent),
      );
      _log('考勤状态项', '新增 $added 个');
      _save();
    }
    return added;
  }

  /// 全部考勤记录（按日期分组展开为一条条记录，供导出使用）。
  List<AttendanceRecord> getAllAttendance() {
    return [
      for (final records in _appData.attendanceByDate.values) ...records,
    ];
  }

  /// 清空某天的全部考勤记录（连同同步产生的批评记录），返回清掉的条数。
  int clearAttendance(String date) {
    if (!_authorizedFor('attendance', action: PasswordAction.attendanceUndo)) {
      return 0;
    }
    final list = _appData.attendanceByDate.remove(date);
    if (list == null || list.isEmpty) return 0;
    _log('考勤清空', '$date · 共 ${list.length} 条（同步生成的批评记录随之清理）');
    // 修复（审计 P0-1）：只清理"考勤同步"自动生成的记录；老师手工录入的
    // 批评记录（记录→考勤方向的源头）保留，仅解除关联。
    final linked = {
      for (final record in list)
        if (record.syncedRecordId.isNotEmpty &&
            _isAttendanceGeneratedRecord(date, record.syncedRecordId))
          record.syncedRecordId,
    };
    if (linked.isNotEmpty) {
      _removeRecordsByIds(date, linked);
    }
    _save();
    return list.length;
  }

  /// 某天的考勤统计：应到（名单人数）、实到（无异常的学生数）、各状态人次。
  /// 名单外学生（已从名单移除但留有考勤）只计入状态人次并单独计条数。
  AttendanceStats attendanceStats(String date) {
    final students = _appData.students;
    final absentStatuses = _appData.settings.attendanceAbsentStatuses;
    final byStatus = <String, int>{
      for (final status in _appData.settings.attendanceStatuses) status: 0,
    };
    // 修复（审查三 6.3）：循环内 contains 改 Set 判断。
    final studentSet = students.toSet();
    final abnormal = <String>{};
    final absent = <String>{};
    var offRoster = 0;
    var recordCount = 0;
    for (final record in getAttendanceForDate(date)) {
      byStatus[record.status] = (byStatus[record.status] ?? 0) + 1;
      recordCount++;
      if (studentSet.contains(record.studentName)) {
        abnormal.add(record.studentName);
        // 只有"算作未到"的状态（默认 请假/缺勤）才减少实到；迟到/早退仍算到了。
        if (absentStatuses.contains(record.status)) {
          absent.add(record.studentName);
        }
      } else {
        offRoster++;
      }
    }
    return AttendanceStats(
      total: students.length,
      abnormalStudents: abnormal.length,
      absentStudents: absent.length,
      recordCount: recordCount,
      byStatus: byStatus,
      offRosterCount: offRoster,
    );
  }

  /// 当天的异常记录按时间段分组（全天最前，其余按当前时段顺序），
  /// 每个时间段内按名单顺序排列。
  Map<String, List<AttendanceRecord>> attendanceByPeriod(String date) {
    final students = _appData.students;
    final groups = <String, List<AttendanceRecord>>{};
    for (final record in getAttendanceForDate(date)) {
      groups.putIfAbsent(record.periodKey, () => <AttendanceRecord>[]).add(
            record,
          );
    }
    // 修复（审查三 6.3）：排序比较器里每次都 indexOf（O(N×55)），先建索引 Map。
    final rosterIndex = {
      for (var i = 0; i < students.length; i++) students[i]: i,
    };
    // 名单顺序里"查不到该学生"时的哨兵名次：远大于任何班额，排到最后。
    const int unknownRosterRank = 1 << 20;
    int keyOf(String name) {
      return (rosterIndex[name] ?? unknownRosterRank);
    }

    final sortedKeys = groups.keys.toList()
      ..sort(
        (a, b) => attendancePeriodOrder(a).compareTo(attendancePeriodOrder(b)),
      );
    final result = <String, List<AttendanceRecord>>{};
    for (final key in sortedKeys) {
      final list = groups[key]!
        ..sort((a, b) {
          final byIndex = keyOf(a.studentName).compareTo(keyOf(b.studentName));
          if (byIndex != 0) return byIndex;
          return a.studentName.compareTo(b.studentName);
        });
      result[key] = list;
    }
    return result;
  }

}
