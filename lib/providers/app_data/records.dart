/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../app_data_provider.dart';

/// 最近一次记录变更的类型。
enum _RecordUndoKind { add, update, delete }

/// “最近一次记录变更”的撤销快照：新增保存记录 id/日期桶，修改保存修改前
/// 的整条记录，删除保存被删记录及原始位置。运行期只保留最近一次操作。
class _RecordUndo {
  const _RecordUndo.add(this.addedEntries)
    : kind = _RecordUndoKind.add,
      oldRecord = null,
      date = null,
      index = -1,
      previousRecordId = null,
      nextRecordId = null,
      removedEntries = const [];

  const _RecordUndo.update({
    required this.oldRecord,
    required this.date,
    required this.index,
    this.previousRecordId,
    this.nextRecordId,
  }) : kind = _RecordUndoKind.update,
       addedEntries = const [],
       removedEntries = const [];

  const _RecordUndo.delete(this.removedEntries)
    : kind = _RecordUndoKind.delete,
      addedEntries = const [],
      oldRecord = null,
      date = null,
      index = -1,
      previousRecordId = null,
      nextRecordId = null;

  final _RecordUndoKind kind;
  final List<({String recordId, String date})> addedEntries;
  final StudentRecord? oldRecord;
  final String? date;
  final int index;

  /// 修改发生时紧邻记录 id，用于撤销时在列表已变化的场景下恢复原相对位置
  /// （审计 P2-6：只用旧 index 插入，期间同桶增删会让顺序错乱）。
  final String? previousRecordId;
  final String? nextRecordId;
  final List<({StudentRecord record, String date, int index})> removedEntries;
}

/// AppDataProvider——记录域（单条/批量增删改查、记录副作用、当日与区间查询）。
///
/// `_ProviderBase` 的一个功能域（mixin 方法就是真正的类成员，
/// 可跨域调用、触发 notifyListeners；on 同 library 基类，其
/// 私有成员在此直接可见）。
mixin _RecordsDomain on _ProviderBase {
  /// 记录入库后的副作用：记录最近使用的操作类型、按映射登记考勤。
  /// addRecord 与批量写入**共用**，保证两条路径行为一致。
  void _applyRecordSideEffects(
    StudentRecord record, {
    bool overwriteManualAttendance = false,
  }) {
    rememberOperationType(record.operationType);
    // 记录派生考勤属于内部派生写入：即使记录密码开启也不应再次要求密码。
    _runInternalWrite(
      () => _syncRecordToAttendance(
        record,
        overwriteManualAttendance: overwriteManualAttendance,
      ),
    );
  }

  StudentRecord? addRecord(
    String studentName,
    String operationType,
    List<String> reasons,
    String periodKey,
    String remark, {
    bool isAppended = false,
    bool isBatch = false,
    String? date,
    String? timestamp,
    String? recordId,
  }) {
    // 审计 A-18a：阻断态下拒绝写入，避免"界面已加、磁盘没有"的假成功。
    if (_blockedByStartup()) return null;
    if (_internalWriteDepth == 0 && !canActiveIdentityAddRecord) {
      _log('安全验证', '拒绝新增记录：当前身份无普通模式新增权限');
      return null;
    }
    // G-3：操作类型只允许"表扬/批评"——其它值会被统计口径（isPraiseType）排除，
    // 入库只会制造"看不见"的脏记录，直接拒收并留痕。
    if (operationType != '表扬' && operationType != '批评') {
      debugPrint('拒收操作类型非法的记录：$operationType（$studentName）');
      return null;
    }
    // X-12：未显式指定日期（"此刻记录"）时按**归属日**取 —— 凌晨 00:00-06:20
    // 记的就寝算前一天（入睡那天）。显式传入 date（追加记录/编辑/导入）
    // 一律尊重，不擅自改写。
    final rawDate = date ?? _attributionDateFor(periodKey);
    // G-3：外部传入的 date 可能非法（导入）——非法时回退到归属日，避免产生
    // `2026-99-99` 这类永不命中的脏桶键（与表格导入、G-13 的校验口径一致）。
    final today = isValidYmdDate(rawDate)
        ? rawDate
        : _attributionDateFor(periodKey);
    final time = timestamp ?? _getCurrentTime();
    // G-3：传入的 recordId 若不查重会与既有记录撞 id（下游按 id 建链接/判重时出错）。
    final id = (recordId == null || _recordIdExists(recordId))
        ? _generateUniqueRecordId()
        : recordId;
    final record = _buildRecord(
      id: id,
      studentName: studentName,
      operationType: operationType,
      reasons: reasons,
      periodKey: periodKey,
      remark: remark,
      date: today,
      timestamp: time,
      isAppended: isAppended,
      isBatch: isBatch,
      recordedBy: currentRecordedBy,
      createdByIdentityId: currentIdentityId,
      createdAtIso: AppClock.now().toIso8601String(),
    );

    if (!_appData.recordsByDate.containsKey(today)) {
      _appData.recordsByDate[today] = [];
    }
    _appData.recordsByDate[today]!.add(record);
    // 审计 P1-6：撤销快照必须先于任何可能通知界面的步骤（_applyRecordSideEffects
    // 会派生考勤并 _save()/notify）——否则监听者在回调里撤销会回滚到上一次操作。
    _lastRecordUndo = _RecordUndo.add([(recordId: record.id, date: today)]);
    _applyRecordSideEffects(record);
    _log(
      '新增记录',
      '$studentName · $operationType · ${record.reasons} · '
          '${getTimePeriodName(periodKey)}${remark.isEmpty ? '' : ' · 备注：$remark'}',
    );
    _save();
    return record;
  }

  /// 批量新增同一条记录（给多名学生，如课后统一追加）：语义与逐条 [addRecord]
  /// 完全一致（含考勤同步与操作日志），但**整批只落盘一次**，
  /// 避免给全班（50+ 人）追加时产生 N 次整库加密写盘造成的卡顿。
  /// 返回实际新增的条数。
  int addRecordsForStudents(
    Iterable<String> studentNames,
    String operationType,
    List<String> reasons,
    String periodKey,
    String remark, {
    bool isAppended = false,
    bool isBatch = false,
    String? date,
  }) {
    if (_blockedByStartup()) return 0;
    if (_internalWriteDepth == 0 && !canActiveIdentityAddRecord) {
      _log('安全验证', '拒绝批量新增：当前身份无普通模式新增权限');
      return 0;
    }
    final names = studentNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return 0;
    final addedRecords = <({String recordId, String date})>[];
    _batch(() {
      for (final name in names) {
        final record = addRecord(
          name,
          operationType,
          reasons,
          periodKey,
          remark,
          isAppended: isAppended,
          isBatch: isBatch,
          date: date,
        );
        if (record == null) continue;
        final recordDate = record.date;
        if (recordDate != null) {
          addedRecords.add((recordId: record.id, date: recordDate));
        }
      }
    });
    if (addedRecords.isNotEmpty) {
      _lastRecordUndo = _RecordUndo.add(addedRecords);
    }
    return addedRecords.length;
  }

  /// 更新记录，成功返回 true；记录不存在时返回 false 供 UI 提示。
  bool updateRecord(
    String recordId,
    String operationType,
    List<String> reasons,
    String periodKey,
    String remark, {
    String? date,
  }) {
    if (_blockedByStartup()) return false;
    var searchDate = date ?? _getTodayString();
    var records = _appData.recordsByDate[searchDate];
    var index = records?.indexWhere((r) => r.id == recordId) ?? -1;
    // 历史数据的 record.date 可能与桶键不一致；指定桶没命中时全表按 id 兜底，
    // 否则这类记录在界面上永远编辑不了。
    if (index == -1) {
      for (final entry in _appData.recordsByDate.entries) {
        final found = entry.value.indexWhere((r) => r.id == recordId);
        if (found != -1) {
          searchDate = entry.key;
          records = entry.value;
          index = found;
          break;
        }
      }
    }
    if (records == null || index == -1) return false;
    final record = records[index];
    if (!canMutateRecord(record)) {
      _log('安全验证', '拒绝修改记录：非本人/超出窗口/无班主任管理');
      return false;
    }
    final oldRecord = record;
    rememberOperationType(operationType);
    // 修复（审计 P1-12）：编辑一条"时段无法识别"的导入记录（key 为空）且
    // 老师没有重新选时段时，保持原空键与原始时段名 —— 此前会被规整成
    // all_day 并把原时段文本（如"上午上课"）重算成"全天"，不改内容直接
    // 保存也会把原始信息洗掉。
    // B-06：同样的保护扩展到"已删除/改名的自定义时段"——key 非空但当前
    // 时段表里已找不到（isKnownPeriodKey=false），且老师没有重新选择时，
    // 保留原 key + 显示名快照。
    // 审计 P1-2 根因修复：编辑对话框会用 `editRecord.periodKey` 预选时段，
    // 时段被删除后这个 key 仍然非空，于是原来的 `periodKey.isEmpty &&` 判断
    // 恒为 false，保护形同虚设 —— 保存时 `_buildRecord` 按未知 key 重算，
    // 而 `getTimePeriodName` 对未知 key **原样返回 key**，`periodName` 就被
    // 永久改写成 `custom_xxx`（已实证复现）。这里改成"老师没有换时段"即保护：
    // 传入 key 与记录原 key 相同、且该 key 在当前时段表里已无法识别。
    final sameAsOriginal = periodKey == record.periodKey;
    final keepUnidentifiedPeriod =
        (sameAsOriginal || periodKey.isEmpty) &&
        (record.periodKey.isEmpty ||
            (!isKnownPeriodKey(record.periodKey) && record.periodName.isNotEmpty));
    // N-2：编辑与新增必须同一套长度/净化规则（此前编辑不截断 →
    // 同一份数据里存在两种规则）。这里直接复用 _buildRecord 的净化逻辑。
    final updatedRecord = _buildRecord(
      id: record.id,
      studentName: record.studentName,
      operationType: operationType,
      reasons: reasons,
      periodKey: keepUnidentifiedPeriod ? record.periodKey : periodKey,
      remark: remark,
      date: record.date ?? searchDate,
      timestamp: record.timestamp,
      isAppended: record.isAppended,
      isImported: record.isImported,
      isBatch: record.isBatch,
      periodNameOverride: keepUnidentifiedPeriod ? record.periodName : null,
      normalizePeriodKey: !keepUnidentifiedPeriod,
      recordedBy: record.recordedBy,
      createdByIdentityId: record.createdByIdentityId,
      createdAtIso: record.createdAtIso,
    );
    final previousRecordId = index > 0 ? records[index - 1].id : null;
    final nextRecordId = index + 1 < records.length
        ? records[index + 1].id
        : null;
    records[index] = updatedRecord;
    // 撤销快照必须先于任何可能通知界面的步骤就绪：_resyncRecordEdit 在考勤
    // 同步开启时也会落盘并同步 notifyListeners，监听者若立即撤销，不能拿到
    // 上一次操作的旧快照（否则可能误删原新增记录）。
    _lastRecordUndo = _RecordUndo.update(
      oldRecord: oldRecord,
      date: searchDate,
      index: index,
      previousRecordId: previousRecordId,
      nextRecordId: nextRecordId,
    );
    // 编辑后重新对齐考勤（原因不再同步时撤销考勤，换原因时更新状态）。
    // 返回 false 表示目标时段撞键、考勤保留原时段 —— 记录侧必须回退时段，
    // 否则记录写新时段、考勤留旧时段，两侧永久不一致（审计 P1-8）。
    final synced = _resyncRecordEdit(searchDate, updatedRecord);
    if (!synced && record.periodKey != updatedRecord.periodKey) {
      // 回退记录时段到编辑前（保留原 key 与显示名快照），并记录一条日志。
      final reverted = _buildRecord(
        id: record.id,
        studentName: record.studentName,
        operationType: operationType,
        reasons: reasons,
        periodKey: record.periodKey,
        remark: remark,
        date: record.date ?? searchDate,
        timestamp: record.timestamp,
        isAppended: record.isAppended,
        isImported: record.isImported,
        isBatch: record.isBatch,
        periodNameOverride: record.periodName.isNotEmpty
            ? record.periodName
            : null,
        normalizePeriodKey: false,
        recordedBy: record.recordedBy,
        createdByIdentityId: record.createdByIdentityId,
        createdAtIso: record.createdAtIso,
      );
      records[index] = reverted;
      _log('修改记录', '${reverted.studentName} 目标时段已有考勤，已将该记录的时段保留为原时段');
      _save();
      return true;
    }
    _log(
      '修改记录',
      '${updatedRecord.studentName} · $operationType · '
          '${updatedRecord.reasons} · '
          '${updatedRecord.periodName.isNotEmpty ? updatedRecord.periodName : getTimePeriodName(periodKey)}',
    );
    _save();
    return true;
  }

  /// 批量新增记录（P2-5：导入等多条场景一次落盘，
  /// 避免逐条 addRecord 造成的"每条一次全库加密+写盘"）。返回实际写入条数。
  int addRecordsBatch(
    List<
      ({
        String studentName,
        String operationType,
        List<String> reasons,
        String periodKey,
        String remark,
        String? date,
      })
    >
    items,
  ) {
    if (_blockedByStartup()) return 0;
    if (_internalWriteDepth == 0 && !canActiveIdentityAddRecord) {
      _log('安全验证', '拒绝批量新增：当前身份无普通模式新增权限');
      return 0;
    }
    var added = 0;
    final addedRecords = <({String recordId, String date})>[];
    // 修复（审计 P1-10）：整批包一次 _batch —— 此前命中"考勤同步"的每条记录
    // 都会经 _applyRecordSideEffects → setAttendanceForStudents 触发一次整库
    // 加密写盘；现在无论内部触发多少次保存，整批只落盘一次。
    _batch(() {
      for (final item in items) {
        // 修复（审计 P1-10）：与 addRecord 共用操作类型白名单 —— 其它值会被
        // 统计口径排除，只会制造"看不见"的脏记录。
        if (item.operationType != '表扬' && item.operationType != '批评') {
          _log('批量新增记录', '跳过 1 条：操作类型非法（${item.operationType}）');
          continue;
        }
        // P2-19 修复：批量写入的日期必须是真实存在的 yyyy-MM-dd，否则整条跳过
        //（此前 "abc" / "2026-99-99" 会成为 recordsByDate 的脏键）。
        // X-12：同样"未指定日期 = 此刻"时按归属日取（凌晨就寝算前一天）。
        final dateKey = item.date ?? _attributionDateFor(item.periodKey);
        if (!isValidYmdDate(dateKey)) {
          _log('批量新增记录', '跳过 1 条：日期不合法（${item.date}）');
          continue;
        }
        // 与 addRecord 共用同一套构造与副作用（此前这里另写一份，导致
        // isImported / 考勤同步 / 空时段键三处行为与单条写入不一致）。
        final record = _buildRecord(
          id: _generateUniqueRecordId(),
          studentName: item.studentName,
          operationType: item.operationType,
          reasons: item.reasons,
          periodKey: item.periodKey,
          remark: item.remark,
          date: dateKey,
          timestamp: _getCurrentTime(),
          isAppended: false,
          recordedBy: currentRecordedBy,
          createdByIdentityId: currentIdentityId,
          createdAtIso: AppClock.now().toIso8601String(),
        );
        _appData.recordsByDate
            .putIfAbsent(dateKey, () => <StudentRecord>[])
            .add(record);
        _applyRecordSideEffects(record);
        addedRecords.add((recordId: record.id, date: dateKey));
        added++;
      }
      if (added > 0) {
        _log('批量新增记录', '写入 $added 条');
        // 挂起中：仅置"待落盘"标记，批次结束统一写一次。
        _save();
      }
    });
    if (addedRecords.isNotEmpty) {
      _lastRecordUndo = _RecordUndo.add(addedRecords);
    }
    return added;
  }

  /// 撤销最近一次记录变更（新增/修改/删除）。
  ///
  /// 返回 [UndoResult]：`changed` 是实际撤销条数（0 表示没有可撤销的操作、
  /// 已过期，或目标记录已被修改/删除）；`saved` 表示撤销后的数据是否已落盘。
  ///
  /// 审计 A-18b：此前撤销只改内存就立刻返回，`_save()` 的结果没人看，界面
  /// 一律提示“已撤销本次记录”——写盘失败时磁盘仍是撤销前的数据，重启就回到
  /// 撤销前，用户却以为撤销成功了。现在撤销会 await 一次真实落盘并如实回报。
  Future<UndoResult> undoLastRecordChange() async {
    if (_blockedByStartup()) return UndoResult.none;
    final undo = _lastRecordUndo;
    if (undo == null) return UndoResult.none;
    _lastRecordUndo = null;

    var changed = 0;
    _batch(() {
      switch (undo.kind) {
        case _RecordUndoKind.add:
          for (final entry in undo.addedEntries) {
            if (_deleteRecordFromDate(
              entry.recordId,
              entry.date,
              logAction: '撤销新增记录',
            )) {
              changed++;
            }
          }
        case _RecordUndoKind.update:
          final oldRecord = undo.oldRecord;
          final date = undo.date;
          if (oldRecord == null || date == null) break;
          final records = _appData.recordsByDate[date];
          if (records == null) break;
          final currentIndex = records.indexWhere(
            (record) => record.id == oldRecord.id,
          );
          if (currentIndex == -1) break;
          records.removeAt(currentIndex);
          // P2-6：优先按修改时紧邻记录定位；邻居已被删除时回退旧 index。
          var insertIndex = -1;
          final previousId = undo.previousRecordId;
          final nextId = undo.nextRecordId;
          if (previousId != null) {
            final anchor = records.indexWhere((r) => r.id == previousId);
            if (anchor >= 0) insertIndex = anchor + 1;
          }
          if (insertIndex < 0 && nextId != null) {
            final anchor = records.indexWhere((r) => r.id == nextId);
            if (anchor >= 0) insertIndex = anchor;
          }
          if (insertIndex < 0) {
            insertIndex = undo.index < 0
                ? records.length
                : (undo.index > records.length ? records.length : undo.index);
          }
          records.insert(insertIndex, oldRecord);
          _resyncRecordEdit(date, oldRecord);
          _log(
            '撤销修改记录',
            '${oldRecord.studentName} · ${oldRecord.operationType} · '
                '${oldRecord.reasons} · ${oldRecord.timestamp}',
          );
          changed++;
        case _RecordUndoKind.delete:
          // 审计 P3：多选删除时各条记录带的是**删除前**的 index，按原顺序
          // 逐条 insert 会在同一天多选删除后把顺序插乱。改为按 index 升序
          // 依次插入（后插的高位 index 仍指向原始位置），即可还原原顺序。
          final entries = [...undo.removedEntries]
            ..sort((a, b) => a.index.compareTo(b.index));
          for (final entry in entries) {
            final records = _appData.recordsByDate.putIfAbsent(
              entry.date,
              () => <StudentRecord>[],
            );
            if (records.contains(entry.record)) continue;
            final insertIndex = entry.index < 0
                ? records.length
                : (entry.index > records.length ? records.length : entry.index);
            records.insert(insertIndex, entry.record);
            // 审计 A-06：删除记录时，它派生过的考勤要么被删、要么被解绑成
            // “人工登记”。撤销删除必须把这一格重新接管回来（overwrite），
            // 否则记录回来了、考勤却永久停在人工行上，两侧关联静默丢失。
            _applyRecordSideEffects(
              entry.record,
              overwriteManualAttendance: true,
            );
            _log(
              '撤销删除记录',
              '${entry.date} · ${entry.record.studentName} · '
                  '${entry.record.operationType} · ${entry.record.reasons} · '
                  '${entry.record.timestamp}',
            );
            changed++;
          }
      }
      // 修改/删除撤销只恢复内存数据，不会像新增撤销那样经过
      // _deleteRecordFromDate 自动触发 _save；必须在批处理内显式落盘，
      // 否则 _batch 结束时没有待保存标记，界面不会收到 notifyListeners。
      if (changed > 0) _save();
    });
    if (changed == 0) return UndoResult.none;
    // 审计 A-18b：_batch 结束时那次 _save() 只是入队；这里 await 到真正写盘，
    // 并把结果如实返回给界面（失败时磁盘仍是撤销前的数据）。
    final saved = await saveNow();
    return UndoResult(changed: changed, saved: saved);
  }
}
