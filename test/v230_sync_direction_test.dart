// 考勤↔记录同步链·方向判定专项回归（V2.30.22，第 3 轮：X-5 / X-13）。
//
// 目的：把"同步链绝不动老师手工数据"钉死。
//   X-5  编辑派生记录时，只有"记录派生考勤"才随记录撤销；手工登记的考勤只解绑、不删；
//   X-13 导入覆盖考勤时，关联的"考勤同步"派生批评记录要一并删除，避免孤儿持续计数。
//
// 模式沿用 sync_chain_test / v230_parse_robustness_test：test() + mock path_provider。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';

import 'test_helpers.dart';

AttendanceRecord legacyAttendance({
  String id = 'a1',
  String name = '张三',
  String status = '迟到',
  String date = '2026-10-04',
  String syncedRecordId = '',
  bool syncedFromRecord = false,
  String periodKey = AttendanceRecord.allDayKey,
}) =>
    AttendanceRecord(
      id: id,
      studentName: name,
      status: status,
      date: date,
      periodKey: periodKey,
      timestamp: '08:00:00',
      syncedRecordId: syncedRecordId,
      syncedFromRecord: syncedFromRecord,
    );

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_sync_dir');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.path
          : null,
    );
    provider = AppDataProvider();
  });

  tearDown(() async {
    await flushWrites(provider);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteDirectoryWithRetry(tempDir);
  });

  group('X-5 编辑派生记录：按方向决定考勤去留', () {
    test('记录→考勤方向：原因不再同步时，派生考勤随之撤销', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      // 老师直接录一条映射到考勤的批评 → 派生一条考勤。
      provider.addRecord('张三', '批评', ['迟到'], 'class', '', date: '2026-10-04');
      final record = provider.getRecordsForDate('2026-10-04').single;
      final attendance =
          provider.getAttendanceOf('张三', '2026-10-04', periodKey: 'class');
      expect(attendance, isNotNull);
      expect(attendance!.syncedFromRecord, isTrue, reason: '记录派生的考勤应带方向标记');

      // 编辑记录：原因改到不再映射 → 派生考勤应被撤销。
      provider.updateRecord(
        record.id, '批评', ['认真'], 'class', '', date: '2026-10-04');

      expect(
        provider.getAttendanceOf('张三', '2026-10-04', periodKey: 'class'),
        isNull,
        reason: '记录派生的考勤应随记录撤销',
      );
    });

    test('考勤→记录方向：编辑派生记录绝不删除老师手工登记的考勤（X-5 核心）', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      // 老师手工登记考勤 → 自动派生一条批评记录（备注带"考勤同步"）。
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      final derived = provider.getRecordsForDate('2026-10-04').single;
      expect(derived.remark, AppDataProvider.attendanceSyncMarker);

      // 编辑这条派生记录：原因改到不再映射。
      provider.updateRecord(
        derived.id, '批评', ['认真'], AttendanceRecord.allDayKey, '',
        date: '2026-10-04');

      final kept = provider.getAttendanceOf('张三', '2026-10-04');
      expect(kept, isNotNull, reason: '手工登记的考勤绝不能被派生记录的编辑删掉');
      expect(kept!.status, '迟到');
      expect(kept.syncedRecordId, isEmpty, reason: '应只解除关联、保留考勤本体');
    });
  });

  group('X-13 导入覆盖考勤：清理孤儿派生批评记录', () {
    test('覆盖手工考勤时，关联的"考勤同步"派生记录被一并删除', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04'), hasLength(1),
          reason: '手工登记考勤会派生一条批评记录');

      // 导入一条同人同时段、状态不同的考勤 → 覆盖。
      provider.importAttendance([
        legacyAttendance(
            id: 'imp1', status: '请假', syncedRecordId: '', date: '2026-10-04'),
      ]);

      expect(provider.getAttendanceOf('张三', '2026-10-04')!.status, '请假');
      expect(
        provider.getRecordsForDate('2026-10-04'),
        isEmpty,
        reason: '被覆盖后，原派生批评记录成为孤儿，必须一并删除',
      );
    });

    test('覆盖记录→考勤方向的考勤时，老师直接录的批评记录不被删除', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      // 老师直接录的批评（remark 为空，不是同步标记）→ 派生考勤。
      provider.addRecord('张三', '批评', ['迟到'], 'all_day', '',
          date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04'), hasLength(1));

      provider.importAttendance([
        legacyAttendance(id: 'imp1', status: '请假', date: '2026-10-04'),
      ]);

      expect(provider.getAttendanceOf('张三', '2026-10-04')!.status, '请假');
      expect(
        provider.getRecordsForDate('2026-10-04'),
        hasLength(1),
        reason: '老师直接录的批评记录是真实数据，不能因导入覆盖考勤而被删',
      );
    });
  });
}
