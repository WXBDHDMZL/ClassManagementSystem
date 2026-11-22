// 回归测试：R6 全面复查补修（撞键状态一致性 P1-1/P1-2、改名撤销 P2-9）。
//
// 约定：全部使用合成学生与固定日期，不触碰真实数据；AttendanceFeature 由
// flutter_test_config.dart 全局开启（生产默认关闭，测试需要开启才能跑同步链）。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/attendance_feature.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const date = '2026-11-01';

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
    AttendanceFeature.enabledForTests = true;
  });

  group('P1-1 撞键时状态照常对齐（不脱节）', () {
    test('改原因+改时段撞键：记录回退旧时段带新原因，考勤留旧时段更新状态', () {
      final provider = newProvider();

      // 1. 批评"迟到"派生 class 时段考勤（状态=迟到）。
      provider.addRecord('张三', '批评', const ['迟到'], 'class', '', date: date);
      final record = provider.getRecordsForDate(date).single;
      expect(record.periodKey, 'class');

      // 2. meal 时段先有人工考勤"请假"（不在同步映射里，不生成记录）。
      provider.setAttendanceForStudents(
        const ['张三'],
        '请假',
        date: date,
        periodKey: 'meal',
      );

      // 3. 编辑：原因 迟到→缺勤，时段 class→meal（撞键）。
      provider.updateRecord(record.id, '批评', const ['缺勤'], 'meal', '');

      final updated = provider.getRecordsForDate(date).single;
      expect(updated.periodKey, 'class', reason: '撞键后记录时段必须回退');
      expect(updated.reasons, '缺勤', reason: '新原因必须保留');

      final classAttendance =
          provider.getAttendanceOf('张三', date, periodKey: 'class');
      expect(classAttendance?.status, '缺勤',
          reason: '撞键时考勤必须留在原时段并更新为新原因映射的状态，不能停留在旧状态');

      final mealAttendance =
          provider.getAttendanceOf('张三', date, periodKey: 'meal');
      expect(mealAttendance?.status, '请假', reason: '人工考勤不得被静默清除');
    });
  });

  group('P1-2 periodKey 为空的老记录撞键回退', () {
    test('空时段老记录改时段撞键：记录回退空时段，考勤更新状态', () {
      final provider = newProvider();

      // 1. 直接构造历史脏数据：空 periodKey 记录 + all_day 派生考勤。
      final oldRecord = StudentRecord(
        id: 'r-legacy',
        studentName: '张三',
        operationType: '批评',
        reasons: '迟到',
        periodKey: '',
        periodName: '迟到',
        remark: AppDataProvider.attendanceSyncMarker,
        timestamp: '08:00:00',
        date: date,
      );
      provider.appData.recordsByDate[date] = [oldRecord];
      provider.appData.attendanceByDate[date] = [
        AttendanceRecord(
          id: 'a-legacy',
          studentName: '张三',
          status: '迟到',
          date: date,
          periodKey: AttendanceRecord.allDayKey,
          periodName: getTimePeriodName(AttendanceRecord.allDayKey),
          timestamp: '08:00:00',
          syncedRecordId: 'r-legacy',
          syncedFromRecord: true,
        ),
      ];

      // 2. meal 时段先有人工考勤"请假"。
      provider.setAttendanceForStudents(
        const ['张三'],
        '请假',
        date: date,
        periodKey: 'meal',
      );

      // 3. 编辑：时段 空→meal、原因 迟到→缺勤（撞键）。
      provider.updateRecord('r-legacy', '批评', const ['缺勤'], 'meal', '',
          date: date);

      final updated =
          provider.getRecordsForDate(date).singleWhere((r) => r.id == 'r-legacy');
      expect(updated.periodKey, '',
          reason: '空时段老记录撞键后必须回退，不能把记录改到新时段而考勤留在全天');

      final allDayAttendance = provider.getAttendanceOf(
        '张三',
        date,
        periodKey: AttendanceRecord.allDayKey,
      );
      expect(allDayAttendance?.status, '缺勤', reason: '考勤留原时段并更新状态');

      final mealAttendance =
          provider.getAttendanceOf('张三', date, periodKey: 'meal');
      expect(mealAttendance?.status, '请假', reason: '人工考勤不得被静默清除');
    });
  });

  group('P2-9 学生改名后撤销快照作废', () {
    test('改名后撤销不再把旧姓名写回', () {
      final provider = newProvider();

      provider.addRecord('张三', '表扬', const ['认真'], 'class', '', date: date);
      expect(provider.getRecordsForDate(date).single.studentName, '张三');

      provider.renameStudent('张三', '张三丰');

      final renamed = provider.getRecordsForDate(date).single;
      expect(renamed.studentName, '张三丰');

      final undone = provider.undoLastRecordChange();
      expect(undone, 0, reason: '改名后撤销快照必须作废，否则旧姓名记录被写回');

      final after = provider.getRecordsForDate(date).single;
      expect(after.studentName, '张三丰',
          reason: '记录仍保持新姓名，不得被旧快照回滚成名单外学生');
    });
  });
}
