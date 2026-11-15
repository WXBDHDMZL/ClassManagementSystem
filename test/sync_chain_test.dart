// 同步链与整包还原回归测试（V2.30.14，审查四 S-1 / S-8）。
//
// 目的：把"删派生批评不误删手工考勤"与"整包还原校验下沉"钉住，
// 避免像 B-1 那样"修复注释存在、实际行为又退化"。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/transfer_service.dart';

void main() {
  group('S-1：同步链方向标记', () {
    test('删除"考勤同步"派生的批评记录，不删老师手工登记的考勤', () {
      final provider = AppDataProvider();
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});

      // 老师先手工登记"迟到"考勤 → 自动生成一条派生批评记录。
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');

      final records = provider.getRecordsForDate('2026-10-04');
      expect(records, hasLength(1), reason: '手工考勤应生成一条派生批评记录');

      // 删除这条派生批评记录 —— 手工考勤必须保留（这是 S-1 的核心）。
      provider.deleteRecord(records.first.id, date: '2026-10-04');

      final kept = provider.getAttendanceOf('张三', '2026-10-04');
      expect(kept, isNotNull, reason: '删派生批评记录后，手工登记的考勤必须保留');
      expect(kept!.status, '迟到');
    });

    test('删除"批评记录"派生的考勤，仍会随记录撤销（记录→考勤方向不变）', () {
      final provider = AppDataProvider();
      provider.mergeStudents(['李四']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});

      // 记录→考勤：录一条带同步原因的批评，自动生成派生考勤。
      provider.addRecord('李四', '批评', ['迟到'], 'class', '', date: '2026-10-05');

      final records = provider.getRecordsForDate('2026-10-05');
      expect(records, hasLength(1));
      expect(
        provider.getAttendanceOf('李四', records.first.date!, periodKey: 'class'),
        isNotNull,
        reason: '批评记录应派生一条考勤',
      );

      // 删除这条记录 → 它派生的考勤应被撤销（syncedFromRecord == true）。
      provider.deleteRecord(records.first.id, date: records.first.date);

      expect(
        provider.getAttendanceOf('李四', records.first.date!, periodKey: 'class'),
        isNull,
        reason: '记录派生的考勤应随记录删除',
      );
    });
  });

  group('记录类型开关与考勤同步', () {
    test('“批评”停用时，登记考勤不再新生成批评记录', () {
      final provider = AppDataProvider();
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.setRecordTypesEnabled(criticism: false);

      final changed = provider.setAttendanceForStudents(
        ['张三'],
        '迟到',
        date: '2026-10-04',
      );

      expect(changed, 1);
      expect(provider.getAttendanceOf('张三', '2026-10-04'), isNotNull);
      expect(
        provider.getRecordsForDate('2026-10-04'),
        isEmpty,
        reason: '批评类型已停用，不应再生成同步批评记录',
      );
    });

    test('“批评”停用后，已有同步记录仍随考勤修改与撤销', () {
      final provider = AppDataProvider();
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到', '请假': '请假'});
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04'), hasLength(1));

      provider.setRecordTypesEnabled(criticism: false);
      provider.setAttendanceForStudents(['张三'], '请假', date: '2026-10-04');

      var records = provider.getRecordsForDate('2026-10-04');
      expect(records, hasLength(1), reason: '已有同步记录应继续随考勤更新');
      expect(records.single.reasons, '请假');

      provider.setAttendanceForStudents(['张三'], '', date: '2026-10-04');
      records = provider.getRecordsForDate('2026-10-04');
      expect(records, isEmpty, reason: '撤销考勤时同步记录仍应一并删除');
    });
  });

  group('S-8：整包还原校验下沉', () {
    test('脏名单（重复/空格/超长）被清洗，空名单不回落真实名单', () async {
      final provider = AppDataProvider();
      await provider.restoreFromPackage(
        PackageData(
          records: const [],
          students: ['张三', ' 李四 ', '张三', '啊' * 35],
          reasons: ReasonLibrary(
            praise: {
              '_common': ['认真'],
            },
            criticism: {
              '_common': ['迟到'],
            },
          ),
          periodLabels: const {},
        ),
      );

      // 张三去重、李四 trim、超长剔除；空名单不回落真实名单。
      expect(provider.appData.students, ['张三', '李四']);
    });

    test('考勤保留词状态被跳过、空时段规整为全天', () async {
      final provider = AppDataProvider();
      await provider.restoreFromPackage(
        PackageData(
          records: const [],
          students: const ['张三', '李四'],
          reasons: ReasonLibrary(
            praise: const {},
            criticism: {
              '_common': ['迟到'],
            },
          ),
          periodLabels: const {},
          attendance: [
            const AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '出勤', // 保留词，应被跳过
              date: '2026-10-04',
              timestamp: '08:00:00',
            ),
            const AttendanceRecord(
              id: 'a2',
              studentName: '李四',
              status: '迟到',
              date: '2026-10-04',
              timestamp: '08:00:00',
            ),
          ],
        ),
      );

      final list = provider.getAttendanceForDate('2026-10-04');
      expect(list, hasLength(1), reason: '保留词"出勤"的考勤应被跳过');
      expect(list.first.studentName, '李四');
      expect(list.first.periodKey, AttendanceRecord.allDayKey);
    });

    test('N-2：包内状态全非法时回退出厂状态（不进入无状态破态）', () async {
      final provider = AppDataProvider();
      await provider.restoreFromPackage(
        PackageData(
          records: const [],
          students: const ['张三'],
          reasons: ReasonLibrary(
            praise: const {},
            criticism: {
              '_common': ['迟到'],
            },
          ),
          periodLabels: const {},
          attendanceStatuses: const ['出勤'], // 只有保留词 → 过滤后为空
        ),
      );

      expect(provider.appData.settings.attendanceStatuses, isNotEmpty);
      expect(
        provider.appData.settings.attendanceStatuses,
        AppSettings.defaultAttendanceStatuses,
      );
    });

    test('复查#1：不同日期的同学生同时段考勤不被误判重复', () async {
      final provider = AppDataProvider();
      await provider.restoreFromPackage(
        PackageData(
          records: const [],
          students: const ['张三'],
          reasons: ReasonLibrary(
            praise: const {},
            criticism: {
              '_common': ['迟到'],
            },
          ),
          periodLabels: const {},
          attendance: [
            const AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '迟到',
              date: '2026-10-05',
              timestamp: '08:00:00',
            ),
            const AttendanceRecord(
              id: 'a2',
              studentName: '张三',
              status: '迟到',
              date: '2026-10-06',
              timestamp: '08:00:00',
            ),
          ],
        ),
      );

      // 两天各保留一条（此前去重键漏日期，第二条会被误判重复丢弃）。
      expect(provider.getAttendanceForDate('2026-10-05'), hasLength(1));
      expect(provider.getAttendanceForDate('2026-10-06'), hasLength(1));
    });

    test('含顿号的原因被净化，避免 join/split 错位', () async {
      final provider = AppDataProvider();
      await provider.restoreFromPackage(
        PackageData(
          records: const [],
          students: const ['张三'],
          reasons: ReasonLibrary(
            praise: {
              '_common': ['含顿号、的原因'],
            },
            criticism: const {},
          ),
          periodLabels: const {},
        ),
      );

      final cleaned = provider.appData.reasons.praise['_common']!;
      expect(cleaned.single.contains('、'), isFalse);
    });
  });
}
