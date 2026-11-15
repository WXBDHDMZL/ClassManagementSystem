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

import '../constants/time_periods.dart';

/// 单条考勤记录：某个学生某个时间段（或"全天"）的**异常**考勤状态。
/// 未登记的学生一律视为"出勤"，因此只有请假、缺勤、迟到等异常才落库；
/// 同一学生同一天的不同时间段可以各记一条（如早读迟到、上课请假）。
class AttendanceRecord {
  final String id;
  final String studentName;
  final String status;

  /// 记录日期（yyyy-MM-dd）
  final String date;

  /// 时间段 key（见 time_periods.dart）；[allDayKey] 表示"全天"。
  final String periodKey;

  /// 时间段的显示名快照（B-06）：登记当时的中文名。
  ///
  /// 为什么需要快照：时段设置可增删改名/删除；若只存 key，删掉时段后历史考勤
  /// 会退化成内部 key（`class` / `late`）或空串。旧数据没有该字段，回退用
  /// [periodKey] 当前名称（[periodLabel]）。
  final String periodName;

  /// 登记时刻（HH:mm:ss）
  final String timestamp;

  /// 由记录（批评）同步而来时保存对应记录 id；空表示没有关联记录。
  final String syncedRecordId;

  /// 方向标记（修复 审查四 S-1）：true 表示**这条考勤是由批评记录派生的**
  /// （记录先创建、考勤后生成）；false 表示原生手工登记。
  /// 删除记录时只撤销派生考勤，绝不删除老师手工登记的考勤。
  final bool syncedFromRecord;

  /// 记录人快照（如"纪律委员 · 李四"）；旧记录或未启用身份时为空。
  final String recordedBy;

  const AttendanceRecord({
    required this.id,
    required this.studentName,
    required this.status,
    required this.date,
    this.periodKey = allDayKey,
    this.periodName = '',
    required this.timestamp,
    this.syncedRecordId = '',
    this.syncedFromRecord = false,
    this.recordedBy = '',
  });

  /// "全天"时间段：不区分具体时段时的默认值（定义在 time_periods.dart）。
  static const String allDayKey = allDayPeriodKey;

  /// "全天"的显示名称。
  static const String allDayLabel = allDayPeriodLabel;

  /// 本记录时间段的显示名（"全天"或时段名称）。
  ///
  /// B-06：优先使用登记当时的 [periodName] 快照；旧数据为空时回退当前名称。
  String get periodLabel =>
      periodName.isNotEmpty ? periodName : getTimePeriodName(periodKey);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentName': studentName,
      'status': status,
      'date': date,
      'periodKey': periodKey,
      'periodName': periodName,
      'timestamp': timestamp,
      'syncedRecordId': syncedRecordId,
      'syncedFromRecord': syncedFromRecord,
      'recordedBy': recordedBy,
    };
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final period = (json['periodKey'] ?? '').toString();
    return AttendanceRecord(
      id: (json['id'] ?? '').toString(),
      studentName: (json['studentName'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      // 旧数据没有时间段字段：按"全天"处理，与旧的"每人每天一个状态"一致。
      periodKey: period.isEmpty ? allDayKey : period,
      // B-06：旧数据没有显示名快照，回退为空（读取时按当前时段名显示）。
      periodName: (json['periodName'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? '').toString(),
      syncedRecordId: (json['syncedRecordId'] ?? '').toString(),
      // 旧数据无此字段：默认 false。升级后，历史"记录派生考勤"不再随记录删除
      //（宁可残留、不误删手工考勤），新数据方向正确。
      syncedFromRecord: json['syncedFromRecord'] == true,
      recordedBy: (json['recordedBy'] ?? '').toString(),
    );
  }

  AttendanceRecord copyWith({
    String? id,
    String? studentName,
    String? status,
    String? date,
    String? periodKey,
    String? periodName,
    String? timestamp,
    String? syncedRecordId,
    bool? syncedFromRecord,
    String? recordedBy,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      studentName: studentName ?? this.studentName,
      status: status ?? this.status,
      date: date ?? this.date,
      periodKey: periodKey ?? this.periodKey,
      periodName: periodName ?? this.periodName,
      timestamp: timestamp ?? this.timestamp,
      syncedRecordId: syncedRecordId ?? this.syncedRecordId,
      syncedFromRecord: syncedFromRecord ?? this.syncedFromRecord,
      recordedBy: recordedBy ?? this.recordedBy,
    );
  }

  /// 值相等（修复 审查四 G-18）：考勤同样是不可变值对象，按内容比较。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttendanceRecord &&
        other.id == id &&
        other.studentName == studentName &&
        other.status == status &&
        other.date == date &&
        other.periodKey == periodKey &&
        other.periodName == periodName &&
        other.timestamp == timestamp &&
        other.syncedRecordId == syncedRecordId &&
        other.syncedFromRecord == syncedFromRecord &&
        other.recordedBy == recordedBy;
  }

  @override
  int get hashCode => Object.hash(
        id,
        studentName,
        status,
        date,
        periodKey,
        periodName,
        timestamp,
        syncedRecordId,
        syncedFromRecord,
        recordedBy,
      );

  /// 默认考勤状态（可在设置里增删改名），同时作为 [AppSettings.attendanceStatuses] 的出厂值。
  static const List<String> defaultStatuses = ['迟到', '早退', '请假', '缺勤'];

  /// 保留状态：未登记的学生即视为出勤，该名称不能作为自定义状态项。
  static const String presentStatus = '出勤';

  /// 校验状态项名称：合法返回 null，否则返回给用户看的提示。
  static String? validateStatus(String status) {
    final value = status.trim();
    if (value.isEmpty) return '考勤状态不能为空';
    if (value == presentStatus) {
      return '「$presentStatus」是保留状态：没有登记的学生就视为出勤，无需自定义';
    }
    return null;
  }
}
