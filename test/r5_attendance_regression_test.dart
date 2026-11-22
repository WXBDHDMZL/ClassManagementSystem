// 回归测试：R5 考勤同步修复（审计 P1-7/P1-8/P1-9、P2-12/P2-13/P2-16/P2-19）。
//
// 约定：全部使用合成学生与固定日期，不触碰真实数据；AttendanceFeature 由
// flutter_test_config.dart 全局开启（生产默认关闭，测试需要开启才能跑同步链）。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/attendance_feature.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const date = '2026-10-18';

  AppDataProvider newProvider() {
    final provider = AppDataProvider();
    provider.mergeStudents(const ['张三', '李四']);
    provider.setAttendanceSyncMap(const {
      '迟到': '迟到',
      '早退': '早退',
      '缺勤': '缺勤',
    });
    return provider;
  }

  tearDown(() {
    // 该文件全程依赖考勤开启；若其它用例改动全局开关，这里兜底恢复。
    AttendanceFeature.enabledForTests = true;
  });

  group('P1-7 记录同步不抢占已有记录的考勤关联', () {
    test('先登记缺勤（自动建批评）再录迟到批评，考勤保持缺勤且关联不变', () {
      final provider = newProvider();

      // 1. 手工登记缺勤：考勤 → 自动生成一条"考勤同步"批评记录并回填链接。
      provider.setAttendanceForStudents(
        const ['张三'],
        '缺勤',
        date: date,
        periodKey: 'class',
      );
      final before = provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(before?.status, '缺勤');
      expect(before?.syncedRecordId, isNotEmpty);

      // 2. 再录一条映射"迟到"的批评：不得抢占这条考勤的关联。
      provider.addRecord('张三', '批评', const ['迟到'], 'class', '', date: date);

      final after = provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(after?.status, '缺勤', reason: '已有记录派生的考勤不得被新记录静默改写');
      expect(after?.syncedRecordId, before?.syncedRecordId,
          reason: '关联不得被新记录抢走，否则原自动记录变孤儿');

      // 3. 原"缺勤"自动记录仍在（未成孤儿），"迟到"记录也已正常入库。
      final records = provider.getRecordsForDate(date);
      expect(records.where((r) => r.reasons == '缺勤'), hasLength(1));
      expect(records.where((r) => r.reasons == '迟到'), hasLength(1));
    });
  });

  group('P1-8 编辑改时段撞键时回退记录时段', () {
    test('目标时段已有人工考勤时，记录时段回退、考勤保持原时段', () {
      final provider = newProvider();

      // 1. 一条批评记录派生 class 时段考勤。
      provider.addRecord('张三', '批评', const ['迟到'], 'class', '', date: date);
      final record = provider.getRecordsForDate(date).single;
      expect(record.periodKey, 'class');

      // 2. 目标时段 meal 先有人工考勤（无映射状态，不产生新记录）。
      provider.setAttendanceForStudents(
        const ['张三'],
        '请假',
        date: date,
        periodKey: 'meal',
      );

      // 3. 编辑记录把时段改到 meal：撞键 → 记录应回退到 class。
      provider.updateRecord(record.id, '批评', const ['迟到'], 'meal', '');

      final updated = provider.getRecordsForDate(date).single;
      expect(updated.periodKey, 'class',
          reason: '撞键后记录时段必须回退，不能记录在 meal、考勤在 class');

      final classAttendance =
          provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(classAttendance?.status, '迟到');
      final mealAttendance =
          provider.getAttendanceOf('张三', date, periodKey: 'meal');
      expect(mealAttendance?.status, '请假', reason: '人工考勤不得被静默清除');
    });
  });

  group('P1-9 编辑改时段成功时刷新显示名快照', () {
    test('考勤搬移到目标时段后 periodName 同步刷新', () {
      final provider = newProvider();

      provider.addRecord('张三', '批评', const ['迟到'], 'class', '', date: date);
      final record = provider.getRecordsForDate(date).single;

      provider.updateRecord(record.id, '批评', const ['迟到'], 'meal', '');

      final moved = provider.getAttendanceOf('张三', date, periodKey: 'meal');
      expect(moved, isNotNull, reason: '无撞键时应成功搬移');
      expect(moved!.periodKey, 'meal');
      expect(moved.periodName, getTimePeriodName('meal'),
          reason: '搬移后显示名必须刷新，不能仍旧名');

      final old = provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(old, isNull, reason: '搬移后原时段不应残留考勤');
    });
  });

  group('P2-12 / P2-13 考勤导入清理链接与校验日期', () {
    test('导入新增考勤清掉派生标记与关联 id', () {
      final provider = newProvider();

      provider.importAttendance(const [
        AttendanceRecord(
          id: 'a1',
          studentName: '张三',
          status: '迟到',
          date: date,
          periodKey: 'class',
          timestamp: '08:00:00',
          syncedRecordId: 'external-id',
          syncedFromRecord: true,
        ),
      ]);

      final got = provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(got, isNotNull);
      expect(got!.syncedRecordId, isEmpty);
      expect(got.syncedFromRecord, isFalse);
    });

    test('脏日期考勤被跳过，不产生不可见数据', () {
      final provider = newProvider();

      final written = provider.importAttendance(const [
        AttendanceRecord(
          id: 'a2',
          studentName: '张三',
          status: '迟到',
          date: '2026-99-99',
          periodKey: 'class',
          timestamp: '08:00:00',
        ),
      ]);

      expect(written, 0);
      expect(provider.getAttendanceForDate('2026-99-99'), isEmpty);
    });
  });

  group('P2-16 撤销删除记录沿用源记录登记时间', () {
    test('撤销删除后重建的派生考勤保留原 timestamp', () {
      final provider = newProvider();

      provider.addRecord('张三', '批评', const ['迟到'], 'class', '', date: date);
      final record = provider.getRecordsForDate(date).single;
      final originalAttendance =
          provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(originalAttendance, isNotNull);

      provider.deleteRecord(record.id, date: date);
      expect(provider.getAttendanceOf('张三', date, periodKey: 'class'), isNull);

      provider.undoLastRecordChange();

      final restored =
          provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(restored, isNotNull, reason: '撤销删除应重建派生考勤');
      expect(restored!.timestamp, record.timestamp,
          reason: '重建考勤必须沿用源记录时间，不能取当前时间');
    });
  });

  group('P2-19 clearAttendance 跨桶清理同步记录', () {
    test('同步记录建在 record.date 桶时也能随清空一并删除', () {
      final provider = newProvider();

      // 登记缺勤 → 自动生成同步记录，链接回填（记录与考勤都在 date 桶）。
      provider.setAttendanceForStudents(
        const ['张三'],
        '缺勤',
        date: date,
        periodKey: 'class',
      );
      final linked = provider.getAttendanceOf('张三', date, periodKey: 'class');
      final linkedRecord = provider
          .getRecordsForDate(date)
          .firstWhere((r) => r.id == linked!.syncedRecordId);
      expect(linkedRecord.remark, AppDataProvider.attendanceSyncMarker);

      // 构造"同步记录与考勤不在同一桶"的历史脏数据：把自动记录整体搬到
      // 另一个桶，但保持 record.date 不变（正是审计 P2-19 描述的发散场景）。
      provider.appData.recordsByDate['2026-10-19'] = [linkedRecord];
      provider.appData.recordsByDate.remove(date);

      final cleared = provider.clearAttendance(date);
      expect(cleared, 1);
      expect(
        provider.appData.recordsByDate['2026-10-19'],
        isNull,
        reason: '清空考勤应按 record.date 兜底删除跨桶的同步记录'
            '（删除后空桶被移除，故为 null）',
      );
    });
  });
}
