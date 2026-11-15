/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:collection';

import 'student_record.dart';
// N-5：只依赖零 Flutter 依赖的错误通道，避免数据层反向依赖 UI 层。
import '../utils/error_sink.dart';
import 'app_settings.dart';
import 'reason_library.dart';
import 'attendance_record.dart';
// 日期校验唯一入口（X-3/G-13/X-4：桶键与归属日期都过同一道校验）。
import '../utils/app_date.dart';

/// 应用全量数据聚合：按日期分组的学生记录 + 用户设置 + 学生名单 + 原因库。
/// 作为持久化的最小单元，由 [StorageService] 加密读写。
class AppData {
  /// 按日期（yyyy-MM-dd）分组的学生记录
  final Map<String, List<StudentRecord>> recordsByDate;

  /// 用户设置（主题模式、导出路径等）
  AppSettings settings;

  /// 学生名单内部存储（G-2：私有 —— 外部只能通过 [students] 只读视图读取，
  /// 通过 [setStudents] / [addStudent] / [removeStudent] / [replaceStudentAt] /
  /// [moveStudent] 修改）。此前是公开可变 List，界面一句 `.clear()` 就会
  /// 静默清空名单且不落盘、不通知。
  List<String> _students;

  /// [students] 的只读视图缓存：名单可能被 UI 每次 build 读取，
  /// 缓存包装对象避免重复分配。[_students] 只就地增删改、绝不重新赋值，
  /// 因此本视图始终有效。
  late final UnmodifiableListView<String> _studentsView =
      UnmodifiableListView(_students);

  /// 学生名单只读视图（修改请用本类的变更方法）。
  List<String> get students => _studentsView;

  /// 表扬/批评原因库内部存储（G-2：私有 —— 经 [setReasons] 整体替换，
  /// 库内条目由 [ReasonLibrary] 的变更方法维护）。
  ReasonLibrary _reasons;

  /// 表扬/批评原因库（不可直接替换，请用 [setReasons]）。
  ReasonLibrary get reasons => _reasons;

  /// 按日期（yyyy-MM-dd）分组的考勤记录
  final Map<String, List<AttendanceRecord>> attendanceByDate;

  AppData({
    required this.recordsByDate,
    required this.settings,
    List<String>? students,
    ReasonLibrary? reasons,
    Map<String, List<AttendanceRecord>>? attendanceByDate,
  })  : _students = List<String>.from(students ?? defaultStudents()),
        _reasons = reasons ?? ReasonLibrary.defaults(),
        attendanceByDate = attendanceByDate ?? {};

  /// 整体替换学生名单（内部就地更新，保持只读视图有效）。
  void setStudents(Iterable<String> names) {
    _students
      ..clear()
      ..addAll(names);
  }

  /// 新增学生；已存在或为空返回 false。
  bool addStudent(String name) {
    if (name.isEmpty || _students.contains(name)) return false;
    _students.add(name);
    return true;
  }

  /// 从名单移除学生；不存在返回 false。
  bool removeStudent(String name) => _students.remove(name);

  /// 替换指定下标处的学生姓名；下标越界返回 false。
  bool replaceStudentAt(int index, String name) {
    if (index < 0 || index >= _students.length) return false;
    _students[index] = name;
    return true;
  }

  /// 名单拖动排序；返回移动后的新下标，失败返回 -1。
  int moveStudent(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _students.length) return -1;
    final item = _students.removeAt(oldIndex);
    var target = newIndex < 0 ? 0 : newIndex;
    if (target > _students.length) target = _students.length;
    _students.insert(target, item);
    return target;
  }

  /// 整体替换原因库。
  void setReasons(ReasonLibrary library) {
    _reasons = library;
  }

  /// 出厂学生名单为空：真实班级名单由用户导入或手动添加，
  /// 不随程序分发，避免把学生姓名编译进安装包。
  static List<String> defaultStudents() => <String>[];

  Map<String, dynamic> toJson() {
    return {
      'recordsByDate': recordsByDate.map(
        (date, records) => MapEntry(
          date,
          records.map((r) => r.toJson()).toList(),
        ),
      ),
      'settings': settings.toJson(),
      'students': _students,
      'reasons': reasons.toJson(),
      'attendanceByDate': attendanceByDate.map(
        (date, records) => MapEntry(
          date,
          records.map((r) => r.toJson()).toList(),
        ),
      ),
    };
  }

  factory AppData.fromJson(Map<String, dynamic> json) {
    final recordsByDate = <String, List<StudentRecord>>{};
    // X-3 修复：顶层字段类型不对时不再 `as` 强转 —— 强转会抛 TypeError 冒泡到
    // StorageService._tryLoadFile，把**整个文件**判为损坏（连本可解析的记录一起丢）。
    // 改为安全判型：类型不对就当空表，本文件其余字段照常解析。
    final rawRecords = json['recordsByDate'];
    var droppedRecords = 0;
    var badRecordBuckets = 0;
    if (rawRecords is Map) {
      rawRecords.forEach((dateKey, records) {
        final date = dateKey.toString();
        // G-13 修复：桶键必须是合法日期 —— 否则桶内记录在历史/导出/统计里
        // 永远显示不出来（等于静默吞数据）。
        final bucketValid = isValidYmdDate(date);
        if (!bucketValid) badRecordBuckets++;
        if (records is! List) {
          droppedRecords++;
          return;
        }
        for (final r in records) {
          try {
            if (r is! Map<String, dynamic>) {
              droppedRecords++;
              continue;
            }
            // R-1 根因修复：`date` 字段是后加的，旧数据文件里这一项为空/缺失，
            // 而记录的归属日期其实就等于它所在的**桶键**。空值用桶键回填后，
            // 导出日期空白 / 编辑删不掉 / 启动重建时被写成今天 这几条路径同时变正确。
            final record = StudentRecord.fromJson(r);
            final ownDate = record.date;
            final ownValid =
                ownDate != null && ownDate.isNotEmpty && isValidYmdDate(ownDate);
            // G-13 修复：分组以**合法桶键**为准。桶键非法（数据可疑）时才退回
            // 记录自带的合法日期抢救，免得连数据带日期一起丢；两者都不合法才丢弃。
            final String? bucketKey =
                bucketValid ? date : (ownValid ? ownDate : null);
            if (bucketKey == null) {
              droppedRecords++;
              continue;
            }
            // 归属日期字段：空/非法时用桶键修正；**已有合法值保持原样不覆盖**
            //（既有约定：加载不擅自改写用户已有的合法日期）。
            final String fieldDate = ownValid ? ownDate : bucketKey;
            recordsByDate.putIfAbsent(bucketKey, () => <StudentRecord>[]).add(
                  record.date == fieldDate ? record : record.copyWith(date: fieldDate),
                );
          } catch (_) {
            // 跳过损坏的单条记录，避免一条坏数据拖垮全部数据。
            droppedRecords++;
          }
        }
      });
    } else if (rawRecords != null) {
      // 类型完全不对（如误写成 List/字符串）：整块记录视为不可用。
      droppedRecords++;
    }
    // F-8：损坏/非法的记录不静默丢弃——写进错误日志，便于排查"数据少了"。
    if (droppedRecords > 0) {
      reportError('记录数据', '加载时跳过 $droppedRecords 条损坏记录');
    }
    if (badRecordBuckets > 0) {
      reportError('记录数据', '加载时跳过 $badRecordBuckets 个日期非法的记录分组');
    }

    final rawSettings = json['settings'];
    return AppData(
      recordsByDate: recordsByDate,
      // X-3 修复：settings 类型不对时回退出厂默认设置
      //（此前直传会抛类型错误，同样是"整文件判损坏"的隐患）。
      settings: rawSettings is Map<String, dynamic>
          ? AppSettings.fromJson(rawSettings)
          : AppSettings.defaultSettings(),
      students: _parseStudents(json['students']),
      reasons: _parseReasons(json['reasons']),
      attendanceByDate: _parseAttendance(json['attendanceByDate']),
    );
  }

  factory AppData.empty() {
    return AppData(
      recordsByDate: {},
      settings: AppSettings.defaultSettings(),
    );
  }

  /// 兼容旧数据文件：**字段缺失**（或类型不对）时回退到空名单。
  /// 注意：用户主动把名单清空是合法状态，旧版曾回退出厂名单，
  /// 导致“删光后重启又冒出来”；新版出厂名单为空，也不会再泄露真实姓名。
  static List<String> _parseStudents(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }
    return defaultStudents();
  }

  /// 兼容旧数据文件：**字段缺失**时回退到出厂默认原因库；
  /// 用户主动清空原因库同样是合法状态，予以保留。
  static ReasonLibrary _parseReasons(dynamic value) {
    if (value is Map<String, dynamic>) {
      return ReasonLibrary.fromJson(value);
    }
    return ReasonLibrary.defaults();
  }

  /// 考勤数据：旧数据文件无该字段时返回空表；单条损坏的考勤记录直接跳过。
  ///
  /// X-4 修复：与记录侧完全对称 —— 校验桶键日期、以桶键回填归属日期、
  /// 丢弃条目录入错误日志。此前三者都没有：脏桶键会静默进库（历史/导出
  /// 里永远显示不出来），且丢了多少条无任何痕迹。
  static Map<String, List<AttendanceRecord>> _parseAttendance(dynamic value) {
    final result = <String, List<AttendanceRecord>>{};
    if (value is! Map) return result;
    var dropped = 0;
    var badBuckets = 0;
    var duplicates = 0;
    // 修复（审计 P2-29）：按唯一键（学生+时段）去重 —— 旧文件/手改文件里的
    // 重复行会被计入"状态人次"（实到不受影响，因 absent 用 Set），first-wins。
    final seenKeys = <String, Set<String>>{};
    value.forEach((dateKey, records) {
      final date = dateKey.toString();
      final bucketValid = isValidYmdDate(date);
      if (!bucketValid) badBuckets++;
      if (records is! List) {
        dropped++;
        return;
      }
      for (final r in records) {
        try {
          if (r is! Map<String, dynamic>) {
            dropped++;
            continue;
          }
          final record = AttendanceRecord.fromJson(r);
          // 归属日期以合法桶键为准；桶键非法时退回记录自带的合法日期抢救。
          final ownValid =
              record.date.isNotEmpty && isValidYmdDate(record.date);
          final String? bucketKey =
              bucketValid ? date : (ownValid ? record.date : null);
          if (bucketKey == null) {
            dropped++;
            continue;
          }
          // 空/非法日期用桶键修正；已有合法值保持原样不覆盖（与记录侧同口径）。
          // 修复（审计 P2-29）：唯一键（学生+时段）去重，first-wins。
          final uniqueKey = '${record.studentName}|${record.periodKey}';
          final seen = seenKeys.putIfAbsent(bucketKey, () => <String>{});
          if (!seen.add(uniqueKey)) {
            duplicates++;
            continue;
          }
          final String fieldDate = ownValid ? record.date : bucketKey;
          result.putIfAbsent(bucketKey, () => <AttendanceRecord>[]).add(
                record.date == fieldDate ? record : record.copyWith(date: fieldDate),
              );
        } catch (_) {
          // 跳过损坏的单条考勤记录。
          dropped++;
        }
      }
    });
    if (dropped > 0) {
      reportError('考勤数据', '加载时跳过 $dropped 条损坏记录');
    }
    if (badBuckets > 0) {
      reportError('考勤数据', '加载时跳过 $badBuckets 个日期非法的考勤分组');
    }
    if (duplicates > 0) {
      reportError('考勤数据', '加载时跳过 $duplicates 条重复考勤（同学生同时段只保留第一条）');
    }
    return result;
  }
}