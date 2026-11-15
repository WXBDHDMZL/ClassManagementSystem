/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:collection';

import '../constants/reasons.dart';

/// 原因库：表扬/批评两类原因，按时间段 key 分组（含 '_common' 全时段通用项）。
/// 可在程序内维护，并随 [AppData] 一并加密持久化；
/// 出厂默认值取自 constants/reasons.dart。
///
/// G-2（2026-10-04 审查）：内部映射改为私有 —— 对外只暴露**只读视图**与一组
/// 显式的变更方法。此前 `praise`/`criticism` 是公开可变 Map，任何持有原因库的
/// 界面代码都能 `library.praise['x']!.add(...)` 直接改写内部数据，既不落盘也不
/// 通知界面（静默损坏）。现在所有写入都必须经 [addReason] / [renameReason] /
/// [removeReason] / [reorderReason]，由调用方决定何时落盘与通知。
class ReasonLibrary {
  /// 表扬原因：时段 key → 原因列表（私有，仅本类可改）。
  late final Map<String, List<String>> _praise;

  /// 批评原因：时段 key → 原因列表（私有，仅本类可改）。
  late final Map<String, List<String>> _criticism;

  ReasonLibrary({
    required Map<String, List<String>> praise,
    required Map<String, List<String>> criticism,
  }) {
    _praise = praise;
    _criticism = criticism;
  }

  /// 表扬原因只读视图（时段 key → 只读原因列表）。
  ///
  /// 每次访问新建包装对象：调用点很少（导出/导入/设置页/快照），
  /// 换取"外部绝无可能绕过变更方法改到内部数据"的强保证。
  Map<String, List<String>> get praise => _readOnlyView(_praise);

  /// 批评原因只读视图（理由同 [praise]）。
  Map<String, List<String>> get criticism => _readOnlyView(_criticism);

  static Map<String, List<String>> _readOnlyView(
    Map<String, List<String>> source,
  ) {
    return UnmodifiableMapView({
      for (final entry in source.entries)
        entry.key: UnmodifiableListView(entry.value),
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'praise': _praise,
      'criticism': _criticism,
    };
  }

  factory ReasonLibrary.fromJson(Map<String, dynamic> json) {
    return ReasonLibrary(
      praise: _parseGroupMap(json['praise']),
      criticism: _parseGroupMap(json['criticism']),
    );
  }

  /// 出厂默认原因库：深拷贝常量内容，避免程序内改动污染常量本身。
  factory ReasonLibrary.defaults() {
    return ReasonLibrary(
      praise: _deepCopy(praiseReasons),
      criticism: _deepCopy(criticismReasons),
    );
  }

  /// 取指定操作类型对应的内部映射（表扬 / 批评）。
  Map<String, List<String>> _mapOf(String operationType) =>
      operationType == '表扬' ? _praise : _criticism;

  /// 取指定操作类型与时间段下的可选原因：该时段专属项 + 全时段通用项。
  /// periodKey 为 '_common' 时只返回通用项，避免重复。
  List<String> forPeriod(String operationType, String periodKey) {
    final reasonsMap = _mapOf(operationType);
    final specific = periodKey == '_common'
        ? const <String>[]
        : (reasonsMap[periodKey] ?? const <String>[]);
    final common = reasonsMap['_common'] ?? const <String>[];
    return [...specific, ...common];
  }

  /// 指定分组的只读原因列表（不存在时返回空列表）。
  List<String> groupReasons(String operationType, String periodKey) =>
      List<String>.unmodifiable(_mapOf(operationType)[periodKey] ?? const []);

  /// 新增原因到指定分组；已存在返回 false。
  bool addReason(String operationType, String periodKey, String reason) {
    final group =
        _mapOf(operationType).putIfAbsent(periodKey, () => <String>[]);
    if (group.contains(reason)) return false;
    group.add(reason);
    return true;
  }

  /// 重命名指定分组内的原因；未找到或新名重复返回 false。
  bool renameReason(
    String operationType,
    String periodKey,
    String oldReason,
    String newReason,
  ) {
    final group = _mapOf(operationType)[periodKey];
    if (group == null) return false;
    final index = group.indexOf(oldReason);
    if (index == -1) return false;
    if (newReason != oldReason && group.contains(newReason)) return false;
    group[index] = newReason;
    return true;
  }

  /// 删除指定分组内的原因；未找到返回 false。
  bool removeReason(String operationType, String periodKey, String reason) =>
      _mapOf(operationType)[periodKey]?.remove(reason) ?? false;

  /// 分组内拖动排序；返回移动后的新下标，失败返回 -1。
  int reorderReason(
    String operationType,
    String periodKey,
    int oldIndex,
    int newIndex,
  ) {
    final group = _mapOf(operationType)[periodKey];
    if (group == null || oldIndex < 0 || oldIndex >= group.length) return -1;
    final item = group.removeAt(oldIndex);
    var target = newIndex < 0 ? 0 : newIndex;
    if (target > group.length) target = group.length;
    group.insert(target, item);
    return target;
  }

  static Map<String, List<String>> _parseGroupMap(dynamic value) {
    final result = <String, List<String>>{};
    if (value is Map) {
      value.forEach((key, list) {
        if (list is List) {
          // 修复（审查四 G-17）：模型层解析即净化（trim + 顿号改逗号），
          // 与 provider 侧入口约束对齐，含顿号原因不再 join/split 错位。
          result[key.toString()] = list
              .map((e) => e.toString().trim().replaceAll('、', '，'))
              .where((e) => e.isNotEmpty)
              .toList();
        }
      });
    }
    return result;
  }

  static Map<String, List<String>> _deepCopy(
    Map<String, List<String>> source,
  ) {
    return source.map(
      (key, list) => MapEntry(key, List<String>.from(list)),
    );
  }

  /// 顺序敏感的列表值相等（G-18：不引入 package:collection 等新依赖）。
  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 分组映射相等（**分组顺序无关**：键序不影响语义）。
  static bool _mapEquals(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !_listEquals(entry.value, other)) return false;
    }
    return true;
  }

  /// 分组映射哈希（**顺序无关**：先按键排序，再逐项滚动哈希；
  /// 组内原因顺序有语义，故列表按顺序参与）。
  static int _mapHash(Map<String, List<String>> map) {
    final keys = map.keys.toList()..sort();
    var hash = 17;
    for (final key in keys) {
      hash = 0x1fffffff & (hash * 31 + key.hashCode);
      for (final value in map[key]!) {
        hash = 0x1fffffff & (hash * 31 + value.hashCode);
      }
    }
    return hash;
  }

  /// 值相等（修复 审查四 G-18）：原因库按内容比较，分组顺序无关。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReasonLibrary &&
        _mapEquals(other._praise, _praise) &&
        _mapEquals(other._criticism, _criticism);
  }

  @override
  int get hashCode => Object.hash(_mapHash(_praise), _mapHash(_criticism));
}
