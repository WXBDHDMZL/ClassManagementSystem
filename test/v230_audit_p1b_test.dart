// 审计 P1 修复专项回归（2026-10-05，第三批：7/8/9/14/15）。
//
//   P1-7  删除记录的联动：手工登记考勤保留且**清理悬空链接**；派生考勤随删
//         （原行为不变）；确认文案已按实际方向生成（界面层）。
//   P1-8  "恢复出厂时段"同步清空旧格式 periodLabels（不再重启复活）。
//   P1-9  原因库"替换导入"统一走净化（顿号→逗号、去空、限长）。
//   P1-14 名单导入表头在**前 10 行**内定位（带标题行的表格不再把标题当姓名）。
//   P1-15 考勤导入表头必须"日期+学生姓名+考勤状态"齐全才锚定（单关键词行
//         不再误锚定导致整表降级固定列序）。
//
// 模式沿用 v230_audit_p1_test：test() + mock path_provider。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_audit_p1b');
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
    resetPeriodsForTest();
    await deleteDirectoryWithRetry(tempDir);
  });

  group('P1-7 删除记录与考勤联动', () {
    test('删除"考勤同步生成"的记录：手工考勤保留、悬空链接被清理', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      final record = provider.getRecordsForDate('2026-10-04').single;
      expect(
        provider.getAttendanceOf('张三', '2026-10-04')!.syncedRecordId,
        record.id,
      );

      provider.deleteRecord(record.id, date: '2026-10-04');

      final attendance = provider.getAttendanceOf('张三', '2026-10-04');
      expect(attendance, isNotNull, reason: '手工登记的考勤绝不能被连删');
      expect(attendance!.status, '迟到');
      expect(attendance.syncedRecordId, isEmpty,
          reason: '指向已删记录的悬空链接必须清理');
    });

    test('删除"派生考勤"的批评记录：派生考勤随记录撤销（原行为不变）', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.addRecord('张三', '批评', ['迟到'], AttendanceRecord.allDayKey, '',
          date: '2026-10-04');
      final record = provider.getRecordsForDate('2026-10-04').single;

      provider.deleteRecord(record.id, date: '2026-10-04');

      expect(provider.getAttendanceOf('张三', '2026-10-04'), isNull);
    });
  });

  group('P1-9 原因库替换导入统一净化', () {
    test('含顿号/超长/空项的原因被净化后再入库', () {
      final dirty = ReasonLibrary(
        praise: {
          '_common': ['打闹、喧哗', '', '  ', '这'.padRight(60, '长')],
        },
        criticism: const {},
      );

      provider.setReasons(dirty);

      final stored = provider.appData.reasons.praise['_common']!;
      expect(stored, contains('打闹，喧哗'));
      expect(stored, isNot(contains('打闹、喧哗')));
      expect(stored.where((reason) => reason.trim().isEmpty), isEmpty);
      expect(
        stored.every(
          (reason) => reason.length <= AppDataProvider.maxReasonLength,
        ),
        isTrue,
        reason: '原因库属于新建内容，超长一律裁剪到上限',
      );
    });
  });

  group('P1-14 名单导入表头定位（前 10 行）', () {
    test('带标题行的表格：标题不再被当姓名导入', () {
      final names = TransferService.parseStudentsRows(const [
        ['七年级3班名单'],
        [],
        ['序号', '姓名'],
        ['1', '张三'],
        ['2', '李四'],
      ]);

      expect(names, ['张三', '李四']);
    });

    test('没有表头时按第一列导入（原行为不变）', () {
      final names = TransferService.parseStudentsRows(const [
        ['张三'],
        ['李四'],
      ]);

      expect(names, ['张三', '李四']);
    });
  });

  group('P1-15 考勤导入表头锚定', () {
    test('单关键词行不再误锚定：错序列表头也能正确解析', () {
      final parsed = TransferService.parseAttendanceRows(const [
        ['学生姓名'],
        ['学生姓名', '考勤状态', '日期'],
        ['张三', '迟到', '2026-10-04'],
      ]);

      expect(parsed.records, hasLength(1));
      final record = parsed.records.single;
      expect(record.studentName, '张三');
      expect(record.status, '迟到');
      expect(record.date, '2026-10-04');
    });

    test('本程序导出的考勤表（前置说明行 + 完整表头）仍可解析', () {
      final parsed = TransferService.parseAttendanceRows(const [
        ['考勤日期：2026年10月4日'],
        ['应到 40 人 · 实到 39 人'],
        ['异常情况：迟到 1 人次'],
        ['日期', '学生姓名', '时间段', '考勤状态', '登记时间'],
        ['2026-10-04', '张三', '全天', '迟到', '08:00:00'],
        ['2026-10-04', '李四', '全天', '出勤', ''],
      ]);

      expect(parsed.records, hasLength(1), reason: '"出勤"展示行应被忽略');
      expect(parsed.records.single.studentName, '张三');
      expect(parsed.records.single.periodKey, AttendanceRecord.allDayKey);
    });
  });
}
