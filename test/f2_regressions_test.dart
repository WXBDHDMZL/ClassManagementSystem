import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

StudentRecord _record({
  String studentName = '张三',
  String operationType = '批评',
  String reasons = '请假',
  String periodKey = 'class',
  String date = '2026-09-26',
}) {
  return StudentRecord(
    id: 'f2-${DateTime.now().microsecondsSinceEpoch}',
    studentName: studentName,
    operationType: operationType,
    reasons: reasons,
    periodKey: periodKey,
    periodName: '课堂',
    remark: '',
    date: date,
    timestamp: '08:00:00',
    isImported: true,
  );
}

void main() {
  tearDown(AuthService.resetForTest);

  test('覆盖导入会同步改写已有关联考勤，避免记录与考勤长期不一致', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(AppData.empty());
    provider.setAttendanceSyncMap({'请假': '请假'});
    provider.setAttendance(
      '张三',
      '迟到',
      date: '2026-09-26',
      periodKey: 'class',
    );

    final imported = provider.importRecords(
      [_record()],
      syncAttendance: true,
      overwriteAttendance: true,
    );

    expect(imported, 1);
    final attendance = provider.getAllAttendance().single;
    expect(attendance.status, '请假');
    expect(attendance.syncedFromRecord, isTrue);
  });

  test('普通导入仍不覆盖已有考勤', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(AppData.empty());
    provider.setAttendanceSyncMap({'请假': '请假'});
    provider.setAttendance(
      '张三',
      '迟到',
      date: '2026-09-26',
      periodKey: 'class',
    );

    provider.importRecords([_record()], syncAttendance: true);

    expect(provider.getAllAttendance().single.status, '迟到');
  });

  test('整包还原缺 attendance 字段的旧包时直接拒绝', () {
    final package = TransferService.parsePackage(
      jsonEncode({
        'format': TransferService.packageFormat,
        'version': TransferService.packageVersion,
        'students': ['张三'],
        'records': [],
      }),
    );

    expect(package, isNull);
  });
}
