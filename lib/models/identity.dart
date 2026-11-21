/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 操作身份类别：老师 / 学生。
enum IdentityKind { teacher, student }

/// 操作身份：不是登录账号，只用于标注"这条记录是谁做的"。
/// 班主任身份固定保留并受管理密码保护；其余身份不需要密码。
class Identity {
  const Identity({
    required this.id,
    required this.name,
    this.nickname = '',
    required this.kind,
    this.isHeadTeacher = false,
    this.allowSelfEdit = true,
    this.allowAddRecord = true,
    this.allowAttendanceRegister = true,
  });

  final String id;

  /// 角色名称，如“班主任”“纪律委员”。
  final String name;

  /// 可选的姓名/昵称，如“李四”；显示为“纪律委员 · 李四”。
  final String nickname;

  final IdentityKind kind;
  final bool isHeadTeacher;

  /// 是否允许在“本人编辑窗口”内修改/删除自己创建的记录。
  /// 班主任始终有完整权限；该开关主要给普通学生/班干部使用。
  final bool allowSelfEdit;

  /// 正常模式是否允许该身份新增记录。
  final bool allowAddRecord;

  /// 正常模式是否允许该身份登记考勤。
  final bool allowAttendanceRegister;

  String get displayLabel {
    final trimmed = nickname.trim();
    return trimmed.isEmpty ? name : '$name · $trimmed';
  }

  String get kindLabel =>
      kind == IdentityKind.teacher ? '老师' : '学生';

  Identity copyWith({
    String? name,
    String? nickname,
    IdentityKind? kind,
    bool? allowSelfEdit,
    bool? allowAddRecord,
    bool? allowAttendanceRegister,
  }) {
    return Identity(
      id: id,
      name: name ?? this.name,
      nickname: nickname ?? this.nickname,
      kind: kind ?? this.kind,
      isHeadTeacher: isHeadTeacher,
      allowSelfEdit: allowSelfEdit ?? this.allowSelfEdit,
      allowAddRecord: allowAddRecord ?? this.allowAddRecord,
      allowAttendanceRegister:
          allowAttendanceRegister ?? this.allowAttendanceRegister,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nickname': nickname,
        'kind': kind.index,
        'isHeadTeacher': isHeadTeacher,
        'allowSelfEdit': allowSelfEdit,
        'allowAddRecord': allowAddRecord,
        'allowAttendanceRegister': allowAttendanceRegister,
      };

  factory Identity.fromJson(Map<String, dynamic> json) {
    final kindIndex = json['kind'];
    return Identity(
      id: (json['id'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
      nickname: (json['nickname'] ?? '').toString().trim(),
      kind: kindIndex is int &&
              kindIndex >= 0 &&
              kindIndex < IdentityKind.values.length
          ? IdentityKind.values[kindIndex]
          : IdentityKind.student,
      isHeadTeacher: json['isHeadTeacher'] == true,
      // 旧数据没有该字段：默认允许，行为与升级前一致。
      allowSelfEdit: json['allowSelfEdit'] != false,
      allowAddRecord: json['allowAddRecord'] != false,
      allowAttendanceRegister: json['allowAttendanceRegister'] != false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Identity &&
      other.id == id &&
      other.name == name &&
      other.nickname == nickname &&
      other.kind == kind &&
      other.isHeadTeacher == isHeadTeacher &&
      other.allowSelfEdit == allowSelfEdit &&
      other.allowAddRecord == allowAddRecord &&
      other.allowAttendanceRegister == allowAttendanceRegister;

  @override
  int get hashCode =>
      Object.hash(
        id,
        name,
        nickname,
        kind,
        isHeadTeacher,
        allowSelfEdit,
        allowAddRecord,
        allowAttendanceRegister,
      );

  /// 出厂默认身份：班主任固定保留，其余身份可在设置里增删改。
  static const List<Identity> defaults = [
    Identity(
      id: 'head_teacher',
      name: '班主任',
      kind: IdentityKind.teacher,
      isHeadTeacher: true,
    ),
    Identity(
      id: 'other_teacher',
      name: '其他老师',
      kind: IdentityKind.teacher,
    ),
    Identity(id: 'class_monitor', name: '班长', kind: IdentityKind.student),
    Identity(id: 'vice_monitor', name: '副班长', kind: IdentityKind.student),
    Identity(
      id: 'discipline_committee',
      name: '纪律委员',
      kind: IdentityKind.student,
    ),
    Identity(
      id: 'sports_committee',
      name: '体育委员',
      kind: IdentityKind.student,
    ),
    Identity(
      id: 'hygiene_committee',
      name: '卫生委员',
      kind: IdentityKind.student,
    ),
    Identity(
      id: 'study_committee',
      name: '学习委员',
      kind: IdentityKind.student,
    ),
    Identity(
      id: 'arts_committee',
      name: '文艺委员',
      kind: IdentityKind.student,
    ),
    Identity(
      id: 'life_committee',
      name: '生活委员',
      kind: IdentityKind.student,
    ),
    Identity(id: 'student_union', name: '学生会', kind: IdentityKind.student),
    Identity(id: 'duty_student', name: '值日生', kind: IdentityKind.student),
    Identity(id: 'duty_officer', name: '值日班干', kind: IdentityKind.student),
  ];

  static const Identity defaultHeadTeacher = Identity(
    id: 'head_teacher',
    name: '班主任',
    kind: IdentityKind.teacher,
    isHeadTeacher: true,
  );
}
