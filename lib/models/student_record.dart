/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 单条学生表现记录（表扬/批评）。
/// 记录所属日期、时间段、原因、备注等完整信息，支持 JSON 序列化以便加密存储。
class StudentRecord {
  /// 记录唯一标识（时间戳生成）
  final String id;
  final String studentName;

  /// 操作类型：'表扬' 或 '批评'
  final String operationType;

  /// 原因列表，以 '、' 连接的字符串
  final String reasons;

  /// 时间段键（对应 time_periods.dart 中的 key）
  final String periodKey;

  /// 时间段显示名（如 "早读"）
  final String periodName;
  final String remark;

  /// 记录时刻（HH:mm:ss）
  final String timestamp;

  /// 是否为事后追加的记录
  final bool isAppended;

  /// 由表格/数据包导入进来的历史记录（列表里显示"导入"标签）。
  final bool isImported;

  /// 由“批量记录”入口一次为多人写入的记录（列表里显示“批量”标签）。
  final bool isBatch;

  /// 所属日期（yyyy-MM-dd）
  final String? date;

  /// 记录人快照（如“纪律委员 · 李四”）；旧记录或未启用身份时为空。
  final String recordedBy;

  /// 创建者身份 ID（用于“本人编辑窗口”）；旧记录/导入记录为空。
  final String createdByIdentityId;

  /// 创建时刻（ISO 8601）；用于计算本人编辑窗口。旧记录为空。
  final String createdAtIso;

  StudentRecord({
    required this.id,
    required this.studentName,
    required this.operationType,
    required this.reasons,
    required this.periodKey,
    required this.periodName,
    required this.remark,
    required this.timestamp,
    this.isAppended = false,
    this.isImported = false,
    this.isBatch = false,
    this.date,
    this.recordedBy = '',
    this.createdByIdentityId = '',
    this.createdAtIso = '',
  });

  /// 复制并覆盖部分字段（用于数据迁移与"仅回填归属日期"这类原地修正）。
  StudentRecord copyWith({
    String? id,
    String? studentName,
    String? operationType,
    String? reasons,
    String? periodKey,
    String? periodName,
    String? remark,
    String? timestamp,
    bool? isAppended,
    bool? isImported,
    bool? isBatch,
    String? date,
    String? recordedBy,
    String? createdByIdentityId,
    String? createdAtIso,
  }) {
    return StudentRecord(
      id: id ?? this.id,
      studentName: studentName ?? this.studentName,
      operationType: operationType ?? this.operationType,
      reasons: reasons ?? this.reasons,
      periodKey: periodKey ?? this.periodKey,
      periodName: periodName ?? this.periodName,
      remark: remark ?? this.remark,
      timestamp: timestamp ?? this.timestamp,
      isAppended: isAppended ?? this.isAppended,
      isImported: isImported ?? this.isImported,
      isBatch: isBatch ?? this.isBatch,
      date: date ?? this.date,
      recordedBy: recordedBy ?? this.recordedBy,
      createdByIdentityId:
          createdByIdentityId ?? this.createdByIdentityId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentName': studentName,
      'operationType': operationType,
      'reasons': reasons,
      'periodKey': periodKey,
      'periodName': periodName,
      'remark': remark,
      'timestamp': timestamp,
      'isAppended': isAppended,
      'isImported': isImported,
      'isBatch': isBatch,
      'date': date,
      'recordedBy': recordedBy,
      'createdByIdentityId': createdByIdentityId,
      'createdAtIso': createdAtIso,
    };
  }

  /// 值相等（修复 审查四 G-18）：记录是**不可变值对象**，按内容比较可让
  /// `contains`/集合去重等按"同一条记录"语义工作，避免依赖对象引用。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StudentRecord &&
        other.id == id &&
        other.studentName == studentName &&
        other.operationType == operationType &&
        other.reasons == reasons &&
        other.periodKey == periodKey &&
        other.periodName == periodName &&
        other.remark == remark &&
        other.timestamp == timestamp &&
        other.isAppended == isAppended &&
        other.isImported == isImported &&
        other.isBatch == isBatch &&
        other.date == date &&
        other.recordedBy == recordedBy &&
        other.createdByIdentityId == createdByIdentityId &&
        other.createdAtIso == createdAtIso;
  }

  @override
  int get hashCode => Object.hash(
        id,
        studentName,
        operationType,
        reasons,
        periodKey,
        periodName,
        remark,
        timestamp,
        isAppended,
        isImported,
        isBatch,
        date,
        recordedBy,
        createdByIdentityId,
        createdAtIso,
      );

  factory StudentRecord.fromJson(Map<String, dynamic> json) {
    // 修复（审查四 G-16）：与 AttendanceRecord.fromJson 同口径，字段一律
    // .toString() 兜底 —— 单字段类型错误（int/bool 混入）不再抛 TypeError
    // 丢整条本可挽救的记录。
    return StudentRecord(
      id: (json['id'] ?? '').toString(),
      studentName: (json['studentName'] ?? '').toString(),
      operationType: (json['operationType'] ?? '').toString(),
      reasons: (json['reasons'] ?? '').toString(),
      periodKey: (json['periodKey'] ?? '').toString(),
      periodName: (json['periodName'] ?? '').toString(),
      remark: (json['remark'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? '').toString(),
      isAppended: json['isAppended'] == true,
      isImported: json['isImported'] == true,
      isBatch: json['isBatch'] == true,
      // 修复（复查 #2）：不用 as 强转 —— date 为非 null 非字符串时会抛
      // TypeError 拖垮整库解析；空安全转串，null 保持 null 语义不变。
      date: json['date']?.toString(),
      recordedBy: (json['recordedBy'] ?? '').toString(),
      createdByIdentityId:
          (json['createdByIdentityId'] ?? '').toString(),
      createdAtIso: (json['createdAtIso'] ?? '').toString(),
    );
  }
}
