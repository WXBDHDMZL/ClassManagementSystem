/*
 * 班级管理系统 - 回归用例（第 12 轮 三/四/五类修复）
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V2.34.2
 *
 * 覆盖：G-2（内部集合封装）、G-3（操作类型白名单）、G-7（原因改名回溯历史）、
 * G-8（入口 clamp）、G-18（值相等）、G-19（setPeriods 过滤）。
 * 均为"先失败后修复"防护：撤掉修复即用例失败。
 */

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

void main() {
  tearDown(resetPeriodsForTest);

  group('G-2 封装：内部集合不可被外部改写', () {
    test('students 是只读视图；provider 名单方法仍然生效', () {
      final p = AppDataProvider();
      p.appData.setStudents(const ['甲', '乙']);
      expect(() => p.appData.students.clear(), throwsUnsupportedError);
      expect(() => p.appData.students.add('X'), throwsUnsupportedError);
      expect(() => p.appData.students[0] = 'X', throwsUnsupportedError);

      final before = p.appData.students.length;
      expect(p.addStudent('新同学甲'), isTrue);
      expect(p.appData.students, contains('新同学甲'));
      expect(p.appData.students.length, before + 1);
      // 重名拒绝
      expect(p.addStudent('新同学甲'), isFalse);
      // 改名（同步历史）
      expect(p.renameStudent('新同学甲', '新同学乙'), isTrue);
      expect(p.appData.students, contains('新同学乙'));
      expect(p.appData.students, isNot(contains('新同学甲')));
      // 按位置替换
      final first = p.appData.students.first;
      p.reorderStudents(0, 1);
      expect(p.appData.students[1], first);
      // 移除
      expect(p.removeStudent('新同学乙'), isTrue);
      expect(p.appData.students, isNot(contains('新同学乙')));
      // 整体替换
      p.appData.setStudents(const ['甲', '乙']);
      expect(p.appData.students, ['甲', '乙']);
    });

    test('reasons 是只读视图；provider 原因变更方法仍然生效', () {
      final p = AppDataProvider();
      final lib = p.appData.reasons;
      expect(() => lib.praise.clear(), throwsUnsupportedError);
      expect(() => lib.praise['_common'] = const [], throwsUnsupportedError);
      expect(() => lib.praise['_common']!.add('X'), throwsUnsupportedError);

      expect(p.addReason('表扬', '_common', '测试原因A'), isTrue);
      expect(p.addReason('表扬', '_common', '测试原因A'), isFalse, reason: '重复拒绝');
      expect(p.appData.reasons.praise['_common'], contains('测试原因A'));
      expect(p.renameReason('表扬', '_common', '测试原因A', '测试原因B'), isTrue);
      expect(p.appData.reasons.praise['_common'], contains('测试原因B'));
      expect(p.removeReason('表扬', '_common', '测试原因B'), isTrue);
      expect(p.appData.reasons.praise['_common'], isNot(contains('测试原因B')));
    });
  });

  group('G-3 操作类型白名单', () {
    test('addRecord 拒收非"表扬/批评"的操作类型', () {
      final p = AppDataProvider();
      final before = p.totalRecordCount;
      p.addRecord('张三', '其他', const ['测试'], 'class', '', date: '2026-09-30');
      expect(p.totalRecordCount, before, reason: '非法操作类型不得入库');
    });
  });

  group('G-7 原因改名回溯历史记录', () {
    test('改名后历史记录里的原因文本同步更新', () {
      final p = AppDataProvider();
      expect(p.addReason('批评', '_common', '原原因'), isTrue);
      p.addRecord('张三', '批评', const ['原原因'], 'class', '', date: '2026-09-30');
      expect(
        p.getRecordsForDate('2026-09-30').first.reasons,
        '原原因',
      );
      expect(p.renameReason('批评', '_common', '原原因', '新原因'), isTrue);
      expect(
        p.getRecordsForDate('2026-09-30').first.reasons,
        '新原因',
        reason: '原因改名必须同步历史记录，否则再编辑会撤销已关联的考勤',
      );
    });
  });

  group('G-8 入口 clamp', () {
    test('setRecordDefaults 收敛到 0..2', () {
      final p = AppDataProvider();
      p.setRecordDefaults(defaultType: 99, autoSelectPeriod: true);
      expect(p.appData.settings.recordDefaultType, 2);
      p.setRecordDefaults(defaultType: -1, autoSelectPeriod: false);
      expect(p.appData.settings.recordDefaultType, 0);
    });
  });

  group('G-19 setPeriods 过滤非法项', () {
    test('缺 key / 标签非法的时段被过滤后才落库', () {
      final p = AppDataProvider();
      p.setPeriods(const [
        {'key': 'class', 'label': '08:00-12:30 上课'},
        {'key': '', 'label': '08:00-12:30 空键'},
        {'key': 'bad', 'label': ''},
      ]);
      expect(p.appData.settings.periods, hasLength(1));
      expect(p.appData.settings.periods.first['key'], 'class');
    });
  });

  group('G-18 值相等', () {
    test('StudentRecord / AttendanceRecord 按内容相等', () {
      final a = StudentRecord.fromJson(<String, dynamic>{
        'id': '1', 'studentName': '张三', 'operationType': '表扬',
        'reasons': 'x', 'periodKey': 'class', 'periodName': '上课',
        'remark': '', 'timestamp': '08:00:00', 'date': '2026-09-30',
      });
      final b = StudentRecord.fromJson(<String, dynamic>{
        'id': '1', 'studentName': '张三', 'operationType': '表扬',
        'reasons': 'x', 'periodKey': 'class', 'periodName': '上课',
        'remark': '', 'timestamp': '08:00:00', 'date': '2026-09-30',
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(remark: '改'), isFalse);

      const att1 = AttendanceRecord(
        id: '1', studentName: '张三', status: '迟到',
        date: '2026-09-30', timestamp: '08:00:00',
      );
      const att2 = AttendanceRecord(
        id: '1', studentName: '张三', status: '迟到',
        date: '2026-09-30', timestamp: '08:00:00',
      );
      expect(att1, att2);
      expect(att1.hashCode, att2.hashCode);
    });

    test('ReasonLibrary 相等与分组顺序无关，组内顺序有语义', () {
      final l1 = ReasonLibrary(praise: {'class': ['a', 'b']}, criticism: {});
      final l2 = ReasonLibrary(praise: {'class': ['a', 'b']}, criticism: {});
      expect(l1, l2);
      expect(l1.hashCode, l2.hashCode);
      // 分组插入顺序不同但内容相同 → 仍相等。
      final l3 = ReasonLibrary(criticism: {}, praise: {'class': ['a', 'b']});
      expect(l1, l3);
      expect(l1.hashCode, l3.hashCode);
      // 组内顺序有语义 → 不等。
      final l4 = ReasonLibrary(praise: {'class': ['b', 'a']}, criticism: {});
      expect(l1 == l4, isFalse, reason: '组内原因顺序有语义');
    });
  });
}
