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

/// AppDataProvider——导入合并与数据包恢复域（名单/原因合并导入、整包还原、出厂重置）。
///
/// `_ProviderBase` 的一个功能域（mixin 方法就是真正的类成员，
/// 可跨域调用、触发 notifyListeners；on 同 library 基类，其
/// 私有成员在此直接可见）。
mixin _ImportRestoreDomain on _ProviderBase {
  /// 批量导入记录（按日期分组写入，同日按时间排序），返回写入条数。
  ///
  /// [syncAttendance]：导入时按当前"考勤状态 → 批评原因"映射补登考勤（B-04）。
  /// 仅处理批评记录；同一（日期+学生+时段）已存在考勤时默认**跳过，不覆盖**
  /// 老师手工登记的考勤；[overwriteAttendance] 仅供“覆盖重复”导入使用，
  /// 此时按导入记录重新登记该时段，避免记录已改而考勤仍停留在旧状态。
  ///
  /// [onAttendanceSynced]：实际补登的考勤条数回调（UI 用于提示，避免返回值
  /// 语义变更影响既有调用方）。
  int importRecords(
    List<StudentRecord> records, {
    bool syncAttendance = false,
    bool overwriteAttendance = false,
    void Function(int generated)? onAttendanceSynced,
  }) {
    if (!_authorizedFor('records', action: PasswordAction.recordImport)) {
      return 0;
    }
    if (records.isEmpty) return 0;
    final touchedDates = <String>{};
    final createdRecords = <StudentRecord>[];
    // 日期非法/类型非法的记录跳过计数（不静默吞，统一写日志）。
    var skippedBadDate = 0;
    var skippedEmptyDate = 0;
    var skippedBadType = 0;
    final usedIds = <String>{
      for (final dayRecords in _appData.recordsByDate.values)
        for (final record in dayRecords) record.id,
    };
    for (final record in records) {
      // 修复（1.3，2026-10-03 审查）：此前对日期不做校验，
      // `importRecords([date:'2026-99-99'])` 会把这个脏串当成桶键写进数据——
      // 该桶内记录在历史列表/导出/统计里永不显示，等于静默吞数据。
      // 对外部文件（表格导入、数据包）尤其需要这道校验。
      final rawDate = record.date;
      if (rawDate != null && rawDate.isNotEmpty && !isValidYmdDate(rawDate)) {
        skippedBadDate++;
        continue;
      }
      if (record.operationType != '表扬' && record.operationType != '批评') {
        skippedBadType++;
        continue;
      }
      // 日期为空同样跳过：整包还原（restoreFromPackage）已是这个口径，两条
      // 导入路径必须一致；此前这里把空日期改写成“今天”，等于静默改期。
      if (rawDate == null || rawDate.isEmpty) {
        skippedEmptyDate++;
        continue;
      }
      final date = rawDate;
      // 导入的记录 id 可能与现有记录冲突（重复导入同一数据包），这里重新分配。
      var id = record.id;
      if (id.isEmpty || usedIds.contains(id)) {
        id = _generateId();
      }
      usedIds.add(id);
      // N-2：导入同样收口到 _buildRecord——此前 id 未冲突时直接透传原对象，
      // 导致导入进来的超长姓名/备注不受任何限制，与手工新增两套规则。
      // 注意传 isImported: true，保留导入标记（考勤同步不覆盖导入记录）。
      final built = _buildRecord(
        id: id,
        studentName: record.studentName,
        operationType: record.operationType,
        reasons: record.reasons.split('、'),
        periodKey: record.periodKey,
        remark: record.remark,
        date: date,
        timestamp: record.timestamp,
        isAppended: record.isAppended,
        isImported: record.isImported,
        isBatch: record.isBatch,
        // 外部表格可能只给了原始时段名（periodKey 空/无法识别）——
        // 必须原样保留（含空键），否则会被重算成"全天"，把原始信息洗掉。
        periodNameOverride: record.periodName,
        normalizePeriodKey: false,
        recordedBy: record.recordedBy,
      );
      _appData.recordsByDate
          .putIfAbsent(date, () => <StudentRecord>[])
          .add(built);
      createdRecords.add(built);
      touchedDates.add(date);
    }
    // 导入的历史记录按时间排序，避免列表与导出里顺序错乱。
    for (final date in touchedDates) {
      _appData.recordsByDate[date]!.sort(
        (a, b) => a.timestamp.compareTo(b.timestamp),
      );
    }
    // B-04：导入记录按映射补登考勤（勾选时）。只补“还没有任何考勤”的时段，
    // 不覆盖手工考勤；同一时段多条导入记录只登记一次。
    var generatedAttendance = 0;
    if (syncAttendance && AttendanceFeature.enabled) {
      final syncedSlots = <String>{};
      _batch(() {
        for (final record in createdRecords) {
          if (record.operationType != '批评') continue;
          final status = _mappedStatusOfReasons(record.reasons);
          if (status.isEmpty) continue;
          final date = record.date;
          if (date == null || date.isEmpty) continue;
          final periodKey = record.periodKey.isEmpty
              ? AttendanceRecord.allDayKey
              : record.periodKey;
          final slot = '$date|${record.studentName}|$periodKey';
          if (!syncedSlots.add(slot)) continue;
          final existing = _appData.attendanceByDate[date];
          final hasAttendance =
              existing != null &&
              existing.any(
                (item) =>
                    item.studentName == record.studentName &&
                    item.periodKey == periodKey,
              );
          if (hasAttendance && !overwriteAttendance) continue;
          final changed = _runInternalWrite(
            () => setAttendanceForStudents(
              [record.studentName],
              status,
              date: date,
              periodKey: periodKey,
              periodName: record.periodName,
              syncedRecordId: record.id,
              syncedFromRecord: true,
              overwriteManualAttendance: overwriteAttendance,
              recordedBy: record.recordedBy,
            ),
          );
          if (changed > 0) generatedAttendance++;
        }
      });
      onAttendanceSynced?.call(generatedAttendance);
    }
    final skippedTotal = skippedBadDate + skippedEmptyDate + skippedBadType;
    _log(
      '导入记录',
      [
        skippedTotal > 0
            ? '共 ${records.length} 条，其中 $skippedTotal 条'
                  '（日期非法 $skippedBadDate / 日期为空 $skippedEmptyDate / '
                  '类型非法 $skippedBadType）已跳过'
            : '共 ${records.length} 条',
        if (generatedAttendance > 0) '补登考勤 $generatedAttendance 条',
      ].join('，'),
    );
    _save();
    // 返回**实际写入**条数（跳过非法/空日期、非法类型后提示不虚高）。
    return records.length - skippedTotal;
  }

  /// 统计使用某时段 key 的考勤条数（删除时段前提示影响面，B-06）。
  int countAttendanceUsingPeriodKey(String periodKey) {
    var count = 0;
    for (final list in _appData.attendanceByDate.values) {
      for (final record in list) {
        if (record.periodKey == periodKey) count++;
      }
    }
    return count;
  }

  /// 统计使用某时段 key 的记录条数（导入/删除时段前提示影响面）。
  int countRecordsUsingPeriodKey(String periodKey) {
    var count = 0;
    for (final list in _appData.recordsByDate.values) {
      for (final record in list) {
        if (record.periodKey == periodKey) count++;
      }
    }
    return count;
  }

  /// 批量把导入时遇到的陌生学生加入名单。
  /// 返回 (新增人数, 被拒人数) —— 被拒指空名/超长（审计 P2-69：此前静默拒绝，
  /// 用户只看到成功数，超长姓名会一直以"名单外学生"存在）。
  ({int added, int rejected}) addStudentsFromImport(Iterable<String> names) {
    if (!_authorizedFor('library', action: PasswordAction.rosterImport)) {
      return (added: 0, rejected: 0);
    }
    var added = 0;
    var rejected = 0;
    for (final name in names) {
      final value = name.trim();
      // N-3：与 addStudent 同一口径（含长度上限），保证名单与记录长度规则一致。
      if (value.isEmpty || value.length > AppDataProvider.maxNameLength) {
        rejected++;
        continue;
      }
      if (!_appData.addStudent(value)) continue;
      added++;
    }
    if (added > 0) {
      _log(
        '名单变更',
        '导入补充 $added 人'
            '${rejected > 0 ? '（另有 $rejected 个名字不合法被拒）' : ''}',
      );
      _save();
    }
    return (added: added, rejected: rejected);
  }

  /// 批量删除记录（导入时选择"覆盖重复"时使用），返回删除条数。
  /// [keepAttendance] 为 true 时不联动撤销考勤——导入覆盖时用，
  /// 否则"先删旧记录"会把它关联的考勤一起删掉。
  int deleteRecords(
    Iterable<StudentRecord> records, {
    bool keepAttendance = false,
  }) {
    if (!_authorizedFor('records', action: PasswordAction.recordDelete)) {
      return 0;
    }
    var removed = 0;
    var denied = 0;
    // 审计 P1-5：批量删除前先抓一份“全部命中记录”的快照，删除完成后统一
    // 写回 _lastRecordUndo —— 否则逐条 deleteRecord 会互相覆盖快照，撤销
    // 只能恢复最后一条。
    final undoEntries = <({StudentRecord record, String date, int index})>[];
    if (!keepAttendance) {
      for (final record in records) {
        for (final entry in _appData.recordsByDate.entries) {
          final index = entry.value.indexWhere((item) => item.id == record.id);
          if (index < 0) continue;
          undoEntries.add((
            record: entry.value[index],
            date: entry.key,
            index: index,
          ));
          break;
        }
      }
    }
    // G-11：记录被删后，指向它的考勤会留下悬空 syncedRecordId（链接语义腐坏）。
    // 收集本次删除的 id，最后统一按 id 跨日期扫一遍清链接。
    final removedIds = <String>{};
    // 修复（审查 三-3）：整批只在最后落盘一次 —— 此前逐条调用 deleteRecord，
    // 每条各触发一次 _save()（N 条 = N 次全库加密写盘），批量删除明显卡顿。
    _batch(() {
      for (final record in records) {
        if (keepAttendance && !canMutateRecord(record)) {
          denied++;
          continue;
        }
        final date = record.date;
        if (!keepAttendance && date != null) {
          if (deleteRecord(record.id, date: date)) {
            removed++;
            removedIds.add(record.id);
          }
          continue;
        }
        // 修复（审查 P3-14）：date 为 null 时此前直接跳过 —— 这类记录在
        // "保留考勤"模式下永远删不掉且无任何提示。这里兜底全表按 id 查找。
        if (date == null) {
          for (final entry in _appData.recordsByDate.entries.toList()) {
            final before = entry.value.length;
            entry.value.removeWhere((item) => item.id == record.id);
            if (entry.value.length == before) continue;
            removed++;
            removedIds.add(record.id);
            if (entry.value.isEmpty) _appData.recordsByDate.remove(entry.key);
            _log(
              '删除记录',
              '${entry.key} · ${record.studentName} · ${record.operationType}（保留考勤）',
            );
            break;
          }
          continue;
        }
        // 仅删记录、保留考勤：直接操作记录表。
        final dayRecords = _appData.recordsByDate[date];
        var removedHere = false;
        if (dayRecords != null) {
          final before = dayRecords.length;
          dayRecords.removeWhere((item) => item.id == record.id);
          removedHere = dayRecords.length != before;
          if (removedHere) {
            if (dayRecords.isEmpty) _appData.recordsByDate.remove(date);
            _log(
              '删除记录',
              '$date · ${record.studentName} · ${record.operationType}（保留考勤）',
            );
          }
        }
        // 桶键与记录的 date 字段不一致时，指定桶会找不到这条记录；再全表兜底。
        if (!removedHere) {
          for (final entry in _appData.recordsByDate.entries.toList()) {
            final before = entry.value.length;
            entry.value.removeWhere((item) => item.id == record.id);
            if (entry.value.length == before) continue;
            if (entry.value.isEmpty) _appData.recordsByDate.remove(entry.key);
            removedHere = true;
            _log(
              '删除记录',
              '${entry.key} · ${record.studentName} · '
                  '${record.operationType}（保留考勤）',
            );
            break;
          }
        }
        if (!removedHere) continue;
        removed++;
        removedIds.add(record.id);
      }
      // G-11：清掉指向已删记录的悬空链接（考勤保留，但不再"关联"到不存在的记录，
      // 并标记为手工录入，避免下游按方向误判）。
      if (removedIds.isNotEmpty) {
        for (final list in _appData.attendanceByDate.values) {
          for (var i = 0; i < list.length; i++) {
            if (removedIds.contains(list[i].syncedRecordId)) {
              list[i] = list[i].copyWith(
                syncedRecordId: '',
                syncedFromRecord: false,
              );
            }
          }
        }
      }
    });
    if (removed > 0) {
      // 撤销快照只保留真正删除成功的记录，避免把无权限而跳过的命中项
      // 也写进撤销栈（撤销时会重复恢复并未删除的记录）。
      if (!keepAttendance) {
        undoEntries.removeWhere(
          (entry) => !removedIds.contains(entry.record.id),
        );
      }
      _lastRecordUndo = keepAttendance
          ? null
          : (undoEntries.isEmpty ? null : _RecordUndo.delete(undoEntries));
    }
    if (denied > 0) {
      _log('删除记录', '$denied 条记录无权限删除，已跳过');
    }
    return removed;
  }

  /// 合并名单：补充缺失的姓名，返回新增人数（保留现有名单与顺序）。
  int mergeStudents(Iterable<String> names) {
    if (!_authorizedFor('library', action: PasswordAction.rosterImport)) {
      return 0;
    }
    var added = 0;
    for (final name in names) {
      final value = name.trim();
      // 修复（审查四 G-10）：与 addStudentsFromImport 同口径加长度上限。
      if (value.isEmpty || value.length > AppDataProvider.maxNameLength) {
        continue;
      }
      if (!_appData.addStudent(value)) continue;
      added++;
    }
    if (added > 0) {
      _log('名单变更', '导入补充 $added 人');
      _save();
    }
    return added;
  }

  /// 替换名单（导入名单时选择"替换"）：去重、忽略空名。
  ///
  /// N-4：全部名字为空/非法时返回 false（名单不变），供调用方提示；成功返回 true。
  bool replaceStudents(List<String> names) {
    if (!_authorizedFor('library', action: PasswordAction.rosterImport)) {
      return false;
    }
    final cleaned = <String>[];
    for (final name in names) {
      final value = name.trim();
      // 修复（审查四 G-10）：与 mergeStudents / addStudentsFromImport 同口径。
      if (value.isEmpty ||
          value.length > AppDataProvider.maxNameLength ||
          cleaned.contains(value)) {
        continue;
      }
      cleaned.add(value);
    }
    if (cleaned.isEmpty) return false;
    _appData.setStudents(cleaned);
    _log('名单变更', '替换名单为 ${cleaned.length} 人');
    _save();
    return true;
  }

  /// 合并原因库：把导入的原因补充到对应时段，返回新增条数。
  int mergeReasons(Iterable<ReasonImportRow> rows) {
    var added = 0;
    // 批量合并只落盘一次，避免 N 条原因写 N 次文件。
    _batch(() {
      for (final row in rows) {
        if (addReason(row.operationType, row.periodKey, row.reason)) added++;
      }
    });
    if (added > 0) _log('原因库', '导入补充 $added 条');
    return added;
  }

  /// 保存备份位置。
  void setBackupPath(String path) {
    _appData.settings = _appData.settings.copyWith(backupPath: path);
    _log('备份设置', '备份目录改为 $path');
    _save();
  }

  /// 保存记录对话框默认操作类型与是否自动预选时段。
  void setRecordDefaults({
    required int defaultType,
    required bool autoSelectPeriod,
  }) {
    // G-8：同口径 clamp（与 fromJson `_parseChoice(...,3)` 一致）。
    final type = defaultType.clamp(0, 2);
    _appData.settings = _appData.settings.copyWith(
      recordDefaultType: type,
      autoSelectPeriod: autoSelectPeriod,
    );
    _log('记录设置', '默认类型改为 $type · 默认自动选时段 $autoSelectPeriod');
    _save();
  }

  /// 只保存管理密码总开关；权限固定由班主任管理模型决定。
  void setPasswordEnabled(bool enabled) {
    if (!_canManageSecuritySettings) {
      _log('密码设置', '拒绝未授权的管理密码开关修改');
      return;
    }
    if (_appData.settings.passwordEnabled == enabled) return;
    _appData.settings = _appData.settings.copyWith(passwordEnabled: enabled);
    _syncIdentitySession();
    _save();
  }

  /// 用数据包整包还原（覆盖现有数据）：记录、考勤、名单、原因库、
  /// 时段、考勤状态、每周起始日、同步映射都按包内内容替换。
  /// 不含管理密码（包内没有），其余设置（主题、关闭行为等）保持本机不变。
  ///
  /// 返回**实际写入**的记录条数（包内条数减去日期非法/为空而跳过的部分），
  /// 供界面提示，避免“还原完成：记录 500 条”比实际写入数虚高。
  Future<int> restoreFromPackage(PackageData data) async {
    if (!_authorizedFor('data', action: PasswordAction.dataPackageImport)) {
      return 0;
    }
    // 审计 P2-33：整包还原先在内存整体替换，保存失败时必须回滚，
    // 不能把“内存已换、磁盘还是旧数据”的半套状态留给界面。
    final previousAppData = _appData;
    // 修复（审查四 S-8）：名单走与 addStudentsFromImport 同口径校验
    //（trim / 去重 / 长度上限）；包内名单为空时**保持空** ——
    // 此前回退到 AppData.defaultStudents()（真实名单），是隐私外溢通道。
    final seenStudents = <String>{};
    final students = <String>[
      for (final name in data.students)
        if (seenStudents.add(name.trim()) &&
            name.trim().isNotEmpty &&
            name.trim().length <= AppDataProvider.maxNameLength)
          name.trim(),
    ];
    final recordsByDate = <String, List<StudentRecord>>{};
    // 复查 3.2：跳过条数要计数并写日志，且日志里的条数必须是**实际写入数**——
    // 此前静默跳过、日志还照抄包内原始条数（"500 条"实际只写 480 条），
    // 事后核对日志会误判。
    var skippedBadDate = 0;
    var skippedEmptyDate = 0;
    var skippedBadType = 0;
    for (final record in data.records) {
      // 审计 P1-12：整包还原也必须走与表格导入相同的类型白名单，避免包内
      // 夹带非法 operationType 污染统计/角标（非表扬即批评的口径会误算）。
      if (record.operationType != '表扬' && record.operationType != '批评') {
        skippedBadType++;
        continue;
      }
      // 修复（1.3）：外部数据包的日期同样要过校验，非法日期的记录直接跳过，
      // 避免脏桶键进入历史/导出/统计区间（这些记录永远显示不出来）。
      final rawDate = record.date;
      if (rawDate != null && rawDate.isNotEmpty && !isValidYmdDate(rawDate)) {
        skippedBadDate++;
        continue;
      }
      // 日期为空的记录无法确定属于哪一天：绝不能静默挪到今天（那会把历史
      // 记录整体改写），直接跳过并计数。
      if (rawDate == null || rawDate.isEmpty) {
        skippedEmptyDate++;
        continue;
      }
      final date = rawDate;
      // 修复（审查 P2-5）：与 importRecords 同口径，**收口到 _buildRecord**（唯一入口）。
      // 数据包是外部文件，姓名/备注长度与原因分隔符必须过同一套净化规则——
      // 此前直接 add 原始对象，可注入超长姓名与含顿号的原因，破坏分隔符不变量。
      recordsByDate
          .putIfAbsent(date, () => <StudentRecord>[])
          .add(
            _buildRecord(
              id: record.id.isEmpty ? _generateId() : record.id,
              studentName: record.studentName,
              operationType: record.operationType,
              reasons: record.reasons.split('、'),
              periodKey: record.periodKey,
              remark: record.remark,
              date: date,
              timestamp: record.timestamp,
              isAppended: record.isAppended,
              isImported: record.isImported,
              isBatch: record.isBatch,
              periodNameOverride: record.periodName,
              normalizePeriodKey: false,
              recordedBy: record.recordedBy,
              createdByIdentityId: record.createdByIdentityId,
              createdAtIso: record.createdAtIso,
            ),
          );
    }
    for (final list in recordsByDate.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    final attendanceByDate = <String, List<AttendanceRecord>>{};
    // 审计 H1：旧数据包没有 attendance 键时，PackageData.attendance 为 null。
    // 这种“未提供”必须保留本机考勤；只有显式空列表才表示包内确实没有考勤。
    if (data.attendance == null) {
      for (final entry in previousAppData.attendanceByDate.entries) {
        attendanceByDate[entry.key] = List<AttendanceRecord>.from(entry.value);
      }
    }
    // X-18 修复：三类跳过原因**分开计数** —— 此前混在一个变量里，
    // 日志统一写成"跳过日期非法 N 条"，把"状态非法/重复"也误报成日期非法，
    // 事后核对日志会被误导。
    var skippedBadAttendanceDate = 0;
    var skippedBadAttendanceStatus = 0;
    var skippedDuplicateAttendance = 0;
    final seenAttendance = <String>{};
    for (final record in data.attendance ?? const <AttendanceRecord>[]) {
      // 修复（审查 P2-6）：日期校验与记录侧同口径 —— 此前只判空串，
      // 非法日期会成为脏桶键（历史/导出/统计里永远显示不出来）。
      if (record.date.isEmpty || !isValidYmdDate(record.date)) {
        skippedBadAttendanceDate++;
        continue;
      }
      // 修复（审查四 S-8）：①状态必须合法（非空、非保留"出勤"）；②空时段键
      // 规整为"全天"；③按（学生 + 时段）去重，保住"一人一时段一条"不变量。
      if (AttendanceRecord.validateStatus(record.status) != null) {
        skippedBadAttendanceStatus++;
        continue;
      }
      final periodKey = record.periodKey.isEmpty
          ? AttendanceRecord.allDayKey
          : record.periodKey;
      // 修复（复查 #1）：去重键必须含日期 —— 此前只拼"学生+时段"，
      // 同一学生同一时段在不同日期（周一迟到、周二迟到）会被误判重复而静默丢弃。
      final dedupeKey =
          '${record.date}\u0000${record.studentName.trim()}\u0000$periodKey';
      if (!seenAttendance.add(dedupeKey)) {
        skippedDuplicateAttendance++;
        continue;
      }
      attendanceByDate
          .putIfAbsent(record.date, () => <AttendanceRecord>[])
          .add(record.copyWith(periodKey: periodKey));
    }
    // 修复（审计 P2-33）：包内字段"缺失"与"显式清空"区分对待 ——
    // 缺失（null，旧数据包）保持本机现值；显式空列表/空映射 = 按包内内容
    //（即用户就是要清空）。
    final statusSource =
        data.attendanceStatuses ?? _appData.settings.attendanceStatuses;
    // 修复（复查 #5）：与 setAttendanceStatuses 同口径过滤保留词"出勤"与空项，
    // 此前直接取包内值，可注入保留词破坏"未登记即出勤"不变量。
    final filteredStatuses = [
      for (final status in statusSource)
        if (AttendanceRecord.validateStatus(status) == null) status,
    ];
    // 修复（剩余清单 N-2）：包内状态显式给出却全非法（如只给"出勤"）时过滤
    // 结果为空，直接入库会让考勤进入"无可用状态"的破态 —— 回退出厂状态；
    // 字段缺失时保持本机。
    final attendanceStatuses = filteredStatuses.isNotEmpty
        ? filteredStatuses
        : (data.attendanceStatuses == null
              ? _appData.settings.attendanceStatuses
              : AppSettings.defaultAttendanceStatuses);
    // "计入未到"的口径：缺失 → 保持本机；显式给出 → 按包内内容（可为空 =
    // 全部状态都不计未到）；只保留确实存在于状态项里的名称。
    final absentSource =
        data.attendanceAbsentStatuses ??
        _appData.settings.attendanceAbsentStatuses;
    final attendanceAbsentStatuses = [
      for (final status in attendanceStatuses)
        if (absentSource.contains(status)) status,
    ];
    // 包内 periods 缺失（null，当前包不会出现）时保持本机自定义时段；
    // 显式空列表表示回到出厂时段。
    final incomingPeriods = data.periods;
    final settings = _appData.settings.copyWith(
      periods: incomingPeriods,
      weekStart: data.weekStart,
      attendanceEnabled: data.attendanceEnabled,
      attendanceSyncMap: data.attendanceSyncMap,
      attendanceStatuses: attendanceStatuses,
      attendanceAbsentStatuses: attendanceAbsentStatuses,
    );
    _appData = AppData(
      recordsByDate: recordsByDate,
      settings: settings,
      // 修复（1.17，2026-10-03 审查）：**只对可变对象**做拷贝 ——
      // `students`（List）与 `reasons`（内部是可变 Map）会被调用方改写，
      // 直接接管引用会让包对象与 provider 状态互相污染。
      // 记录/考勤（StudentRecord / AttendanceRecord）是不可变值对象，
      // 按引用共享是安全的，不必也不应逐条复制（复查 3.5 已确认这一点，
      // 此前注释写成"统一深拷贝"与实现不符，容易误导后续维护者）。
      students: List<String>.from(students),
      // 审计 P1-2：包内 reasons 缺失时保留本机原因库，不用出厂库覆盖。
      reasons: data.reasons == null
          ? _appData.reasons
          : _sanitizedReasonLibrary(data.reasons!),
      attendanceByDate: attendanceByDate,
    );
    // 先套用包内时段，保证恢复后的时段解释与数据包一致。
    applyCustomPeriods(settings.periods);
    _resetAccessStateAfterDataChange();
    _syncIdentitySession();
    _repairDuplicateIds();
    final writtenRecords = recordsByDate.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    // X-18：三类跳过原因分别列出，只显示非零项，避免误报成"全是日期非法"。
    final attendanceSkipParts = <String>[
      if (skippedBadAttendanceDate > 0) '日期非法 $skippedBadAttendanceDate 条',
      if (skippedBadAttendanceStatus > 0) '状态非法 $skippedBadAttendanceStatus 条',
      if (skippedDuplicateAttendance > 0) '重复 $skippedDuplicateAttendance 条',
    ];
    _log(
      '整包还原',
      '记录 $writtenRecords 条'
          '${skippedBadDate + skippedEmptyDate + skippedBadType > 0 ? '（跳过日期非法 ${skippedBadDate + skippedEmptyDate} 条${skippedBadType > 0 ? '、类型非法 $skippedBadType 条' : ''}）' : ''}'
          ' · 考勤 ${attendanceByDate.values.fold<int>(0, (s, l) => s + l.length)} 条'
          '${attendanceSkipParts.isEmpty ? '' : '（跳过 ${attendanceSkipParts.join(' / ')}）'}'
          ' · 名单 ${students.length} 人'
          '${data.discardedRecordCount > 0 ? ' · 包内 ${data.discardedRecordCount} 条记录因姓名/日期缺失被忽略' : ''}'
          '${data.discardedAttendanceCount > 0 ? ' · 包内 ${data.discardedAttendanceCount} 条考勤因姓名/日期缺失或损坏被忽略' : ''}',
    );
    // 修复（审查 三-2）：通知统一交给 _save()，不再额外同步通知。
    _save();
    // 审计 P2-33：等待真正落盘；失败则回滚内存与全局时段表，返回 -1 供
    // 界面提示。此前只提示“保存失败”，内存里却已经是包内数据，重启即回退。
    // 尚未 initialize 的测试替身没有可写盘状态（_isLoading=true），跳过严格
    // 落盘校验；生产路径一定在 initialize 完成后调用。
    final saved = isLoading ? true : await saveNow();
    if (!saved) {
      _appData = previousAppData;
      applyCustomPeriods(previousAppData.settings.periods);
      _invalidateDerivedCaches();
      _syncIdentitySession();
      notifyListeners();
      _log('整包还原失败', '保存失败，已回滚到还原前数据');
      return -1;
    }
    return writtenRecords;
  }

  /// 恢复出厂：清空全部记录与自定义内容，名单清空，原因库与设置恢复默认。
  /// 覆盖主数据文件；上一份数据仍保留在 .bak 中，必要时可用"从备份恢复"挽回。
  /// 返回是否已成功落盘；失败时回滚内存，避免界面显示已清空但磁盘仍是旧数据。
  Future<bool> factoryReset() async {
    if (!_authorizedFor('factoryReset', action: PasswordAction.factoryReset)) {
      return false;
    }
    final previousAppData = _appData;
    _appData = AppData.empty();
    applyCustomPeriods(const []);
    _lastSaveFailed = false;
    _log('恢复出厂', '全部记录、考勤与自定义内容已清空');
    // 未初始化的测试 provider 没有可写的真实文件；生产路径必须等待落盘。
    final saved = _isLoading ? true : await saveNow();
    if (!saved) {
      // 保存失败时磁盘仍是旧数据；回滚内存与时段表，避免“看似已清空、
      // 重启后又回来”，也避免下一次成功保存把旧数据覆盖成空库。
      _appData = previousAppData;
      _applySettingsPeriods();
      _invalidateDerivedCaches();
      _syncIdentitySession();
      _log('恢复出厂失败', '保存失败，已回滚到清空前数据');
      notifyListeners();
      return false;
    }
    _resetAccessStateAfterDataChange();
    _syncIdentitySession();
    notifyListeners();
    return true;
  }
}
