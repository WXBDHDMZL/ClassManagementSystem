// 审计 P0 修复专项回归（2026-10-05，外部全项目审计的 3 个 P0）。
//
//   P0-1 考勤侧联动删除只清理"考勤同步"自动生成的批评记录，老师手录的一律保留
//        （撤销 / 改状态 / 清空三条路径）；考勤→记录方向的自动化行为不变。
//   P0-2 导出：备注列有值、遵循"导出选项"的列设置。
//
// 模式沿用 v230_sync_direction_test：test() + mock path_provider。

import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_audit_p0');
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

  group('P0-1 考勤侧联动删除：只清自动生成，绝不删手录记录', () {
    test('撤销由手录记录派生的考勤：批评记录保留，仅考勤撤销', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.addRecord(
        '张三',
        '批评',
        ['迟到'],
        AttendanceRecord.allDayKey,
        '',
        date: '2026-10-04',
      );
      final attendance = provider.getAttendanceOf('张三', '2026-10-04');
      expect(attendance, isNotNull);
      expect(attendance!.syncedFromRecord, isTrue, reason: '应标记为记录派生');

      provider.setAttendance('张三', '', date: '2026-10-04');

      expect(provider.getAttendanceOf('张三', '2026-10-04'), isNull);
      final records = provider.getRecordsForDate('2026-10-04');
      expect(records, hasLength(1), reason: '老师手录的批评记录不能因撤销考勤被删');
      expect(records.single.reasons, '迟到');
    });

    test('撤销考勤同步生成的记录：自动记录一并删除（原行为不变）', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04'), hasLength(1));
      expect(
        provider.getRecordsForDate('2026-10-04').single.remark,
        AppDataProvider.attendanceSyncMarker,
      );

      provider.setAttendance('张三', '', date: '2026-10-04');

      expect(
        provider.getRecordsForDate('2026-10-04'),
        isEmpty,
        reason: '考勤同步生成的记录随撤销一并清理',
      );
      expect(provider.getAttendanceOf('张三', '2026-10-04'), isNull);
    });

    test('状态改为不再同步：手录记录保留并解除关联', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.addRecord('张三', '批评', ['迟到'], 'class', '', date: '2026-10-04');

      provider.setAttendanceForStudents(
        ['张三'],
        '请假',
        date: '2026-10-04',
        periodKey: 'class',
      );

      final attendance = provider.getAttendanceOf(
        '张三',
        '2026-10-04',
        periodKey: 'class',
      );
      expect(attendance, isNotNull);
      expect(attendance!.status, '请假');
      expect(attendance.syncedRecordId, isEmpty, reason: '不再同步应解除关联');
      final records = provider.getRecordsForDate('2026-10-04');
      expect(records, hasLength(1), reason: '手录记录不能因考勤改状态被删');
      expect(records.single.reasons, '迟到');
    });

    test('状态改为不再同步：自动生成记录随改状态一并清理', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04'), hasLength(1));

      provider.setAttendanceForStudents(['张三'], '请假', date: '2026-10-04');

      expect(provider.getAttendanceOf('张三', '2026-10-04')!.status, '请假');
      expect(
        provider.getRecordsForDate('2026-10-04'),
        isEmpty,
        reason: '自动生成的批评记录在状态不再同步时清理',
      );
    });

    test('清空全天：手录记录保留、自动记录删除', () {
      provider.mergeStudents(['张三', '李四']);
      provider.setAttendanceSyncMap({'迟到': '迟到', '缺勤': '旷课'});
      provider.addRecord(
        '张三',
        '批评',
        ['迟到'],
        AttendanceRecord.allDayKey,
        '',
        date: '2026-10-04',
      );
      provider.setAttendanceForStudents(['李四'], '缺勤', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04'), hasLength(2));

      final cleared = provider.clearAttendance('2026-10-04');

      expect(cleared, 2);
      final records = provider.getRecordsForDate('2026-10-04');
      expect(records, hasLength(1), reason: '手录记录保留、自动记录清理');
      expect(records.single.studentName, '张三');
      expect(provider.getAttendanceForDate('2026-10-04'), isEmpty);
    });
  });

  group('P0-2 导出：备注列与导出列设置', () {
    test('buildRecordsXlsx 默认列含备注列且值正确', () {
      provider.mergeStudents(['张三']);
      provider.addRecord(
        '张三',
        '批评',
        ['迟到'],
        AttendanceRecord.allDayKey,
        '家长已知晓',
        date: '2026-10-04',
      );

      final bytes = TransferService.buildRecordsXlsx(
        provider.getRecordsForDate('2026-10-04'),
      );
      final table = excel.Excel.decodeBytes(bytes).tables.values.first;
      final header = table.rows.first;
      final remarkCol = header.indexWhere(
        (cell) => cell?.value.toString() == '备注',
      );
      expect(remarkCol, greaterThanOrEqualTo(0), reason: '默认导出列必须含备注列');
      expect(table.rows[1][remarkCol]?.value.toString(), '家长已知晓');
    });

  });
}
