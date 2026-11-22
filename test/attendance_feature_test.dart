import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/widgets/record_list.dart';

import 'package:class_management_system/constants/attendance_feature.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/services/storage_service.dart';
import 'package:class_management_system/services/transfer_service.dart';

void main() {
  setUp(() {
    AttendanceFeature.enabledForTests = false;
  });
  tearDown(() {
    AttendanceFeature.enabledForTests = true;
  });

  test('生产默认关闭考勤功能', () {
    expect(AttendanceFeature.enabled, isFalse);
  });

  testWidgets('考勤关闭时记录面板不显示考勤入口', (tester) async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setPasswordEnabled(false);
    provider.setAttendanceEnabled(true);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: RecordList(records: [])),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('考勤'), findsNothing);
    expect(find.text('历史记录'), findsOneWidget);
  });

  test('考勤关闭时反向同步不会生成批评记录', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setPasswordEnabled(false);
    provider.setAttendanceEnabled(true);
    provider.setAttendanceSyncMap(const {'迟到': '迟到'});

    provider.setAttendanceForStudents(
      const ['张三'],
      '迟到',
      date: '2026-10-31',
      periodKey: 'class',
    );

    expect(provider.getRecordsForDate('2026-10-31'), isEmpty);
    expect(provider.getAttendanceForDate('2026-10-31'), hasLength(1));
  });

  test('考勤关闭时批量导入记录不补登考勤', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setPasswordEnabled(false);
    provider.setAttendanceEnabled(true);
    provider.setAttendanceSyncMap(const {'迟到': '迟到'});

    provider.importRecords(
      [
        StudentRecord(
          id: 'r1',
          studentName: '张三',
          operationType: '批评',
          reasons: '迟到',
          periodKey: 'class',
          periodName: '上课',
          remark: '',
          timestamp: '08:00:00',
          date: '2026-10-31',
        ),
      ],
      syncAttendance: true,
    );

    expect(provider.getRecordsForDate('2026-10-31'), hasLength(1));
    expect(provider.getAttendanceForDate('2026-10-31'), isEmpty);
  });

  test('考勤关闭时数据包和本地加密仍保留考勤字段', () async {
    const attendance = AttendanceRecord(
      id: 'a1',
      studentName: '张三',
      status: '迟到',
      date: '2026-10-31',
      timestamp: '08:00:00',
    );
    final data = AppData(
      recordsByDate: const {},
      settings: AppSettings.defaultSettings().copyWith(
        attendanceEnabled: true,
      ),
      attendanceByDate: {
        '2026-10-31': [attendance],
      },
    );

    final packageText = TransferService.buildPackage(
      data,
      exportedAt: '2026-10-31T22:00:00',
    );
    expect(TransferService.parsePackage(packageText)!.attendance, hasLength(1));

    final encoded = await StorageService().encodeForTest(data);
    final decoded = await StorageService().decodeForTest(encoded);
    expect(decoded!.attendanceByDate['2026-10-31'], hasLength(1));
  });

  test('考勤关闭时新增记录不会自动生成考勤', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setPasswordEnabled(false);
    provider.setAttendanceEnabled(true);
    provider.setAttendanceSyncMap(const {'迟到': '迟到'});

    provider.addRecord('张三', '批评', const ['迟到'], 'class', '');

    expect(provider.getTodayRecords(), hasLength(1));
    expect(
      provider.getAttendanceForDate(
        provider.getTodayRecords().single.date!,
      ),
      isEmpty,
    );
  });
}
