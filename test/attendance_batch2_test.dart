// Batch 2 回归：考勤时段名快照、考勤改写记录人。
//
// 背景（历史缺陷记录）：
//  - B-06 时段删除后考勤显示/导出退化为内部 key；
//  - B-12 考勤被改写时更新时间但不更新记录人。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

import 'test_bootstrap.dart';

const _nightPeriod = {'key': 'night', 'label': '22:00-06:30 就寝'};

StudentRecord _record({
  String id = 'r1',
  String name = '张三',
  String date = '2026-10-04',
  String timestamp = '00:30:00',
  String periodKey = 'night',
  String periodName = '就寝',
}) {
  return StudentRecord(
    id: id,
    studentName: name,
    operationType: '批评',
    reasons: '迟到',
    periodKey: periodKey,
    periodName: periodName,
    remark: '',
    timestamp: timestamp,
    date: date,
  );
}

AttendanceRecord _attendance({
  String id = 'a1',
  String name = '张三',
  String status = '迟到',
  String date = '2026-10-04',
  String periodKey = 'night',
  String timestamp = '00:30:00',
}) {
  return AttendanceRecord(
    id: id,
    studentName: name,
    status: status,
    date: date,
    periodKey: periodKey,
    timestamp: timestamp,
  );
}

void main() {
  late Directory docsDir;

  setUp(() {
    docsDir = createTestDocumentsDir('cms_attendance_batch2');
    installTestPathProvider(docsDir);
  });

  tearDown(() async {
    uninstallTestPathProvider();
    await deleteTestDocumentsDir(docsDir);
  });

  tearDown(() {
    // 测试里会改全局时段表，恢复默认避免同文件后续用例串味。
    applyCustomPeriods(const []);
  });

  group('B-06 考勤时段名快照', () {
    test('JSON 往返保留 periodName；旧数据缺字段时回退当前时段名', () {
      final record = _attendance(
        periodKey: 'class',
        // 故意存一个与当前时段名不同的快照。
      ).copyWith(periodName: '当年的上课时段');
      final restored = AttendanceRecord.fromJson(record.toJson());
      expect(restored.periodName, '当年的上课时段');
      expect(restored.periodLabel, '当年的上课时段');
      expect(restored, record);

      final legacy = AttendanceRecord.fromJson(const {
        'id': 'a2',
        'studentName': '张三',
        'status': '迟到',
        'date': '2026-10-04',
        'periodKey': 'class',
        'timestamp': '08:00:00',
      });
      expect(legacy.periodName, '');
      expect(legacy.periodLabel, getTimePeriodName('class'));
    });

    test('登记时保存显示名快照；之后时段改名/删除也不影响历史显示', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.setPeriods([_nightPeriod]);
      provider.setAttendance(
        '张三',
        '迟到',
        date: '2026-10-04',
        periodKey: 'night',
      );

      final record = provider.getAttendanceForDate('2026-10-04').single;
      expect(record.periodName, '22:00-06:30 就寝');
      expect(record.periodLabel, '22:00-06:30 就寝');

      // 删除该时段后，历史考勤仍显示登记时的中文名。
      provider.setPeriods(const []);
      final afterDelete = provider.getAttendanceForDate('2026-10-04').single;
      expect(afterDelete.periodLabel, '22:00-06:30 就寝');
      expect(provider.countAttendanceUsingPeriodKey('night'), 1);
    });

    test('编辑记录时已删除时段保留原 key 与显示名', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.setPeriods([_nightPeriod]);
      provider.importRecords([
        _record(periodKey: 'night', periodName: '22:00-06:30 就寝'),
      ]);
      // 删除该时段，模拟“时段已不存在”。
      provider.setPeriods(const []);

      final edited = provider.updateRecord(
        'r1',
        '批评',
        const ['迟到'],
        '',
        '',
        date: '2026-10-04',
      );
      expect(edited, isTrue);
      final record = provider.getRecordsForDate('2026-10-04').single;
      expect(record.periodKey, 'night');
      expect(record.periodName, '22:00-06:30 就寝');
    });
  });

  group('B-12 考勤改写更新记录人', () {
    test('同一时段被再次登记时，recordedBy 更新为最近一次操作者', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.setAttendance(
        '张三',
        '迟到',
        date: '2026-10-04',
        periodKey: 'class',
      );
      expect(
        provider.getAttendanceForDate('2026-10-04').single.recordedBy,
        '',
      );

      provider.setIdentityFeatureEnabled(true);
      provider.setActiveIdentity('discipline_committee');
      provider.setAttendance(
        '张三',
        '请假',
        date: '2026-10-04',
        periodKey: 'class',
      );

      final record = provider.getAttendanceForDate('2026-10-04').single;
      expect(record.status, '请假');
      expect(record.recordedBy, provider.activeIdentity!.displayLabel);
    });

    test('关闭记录身份后改写考勤，保留原记录人（不清空历史快照）', () {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.setIdentityFeatureEnabled(true);
      provider.setActiveIdentity('discipline_committee');
      provider.setAttendance(
        '张三',
        '迟到',
        date: '2026-10-04',
        periodKey: 'class',
      );
      final before = provider.getAttendanceForDate('2026-10-04').single;
      expect(before.recordedBy, isNotEmpty);

      provider.setIdentityFeatureEnabled(false);
      provider.setAttendance(
        '张三',
        '请假',
        date: '2026-10-04',
        periodKey: 'class',
      );

      final after = provider.getAttendanceForDate('2026-10-04').single;
      expect(after.status, '请假');
      expect(after.recordedBy, before.recordedBy);
    });
  });
}
