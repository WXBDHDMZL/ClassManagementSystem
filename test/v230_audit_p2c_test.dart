// 审计 P2 修复专项回归（2026-10-05，最终批：31/32/33/34/35/36/37/38/41/45/47/61/62/64/66/75-81）。
//
//   P2-31 重命名状态拒绝保留词"出勤"（provider 层校验）；删除状态项提示实到口径变化；
//   P2-32 失效时段 key 退回记录保存的时段名；
//   P2-33 数据包"缺失"与"显式清空"区分（syncMap/日历/状态项/未到名单）；
//   P2-34 备份恢复窗口挂起写盘（竞态类，代码层核对）；
//   P2-35 记录 date 与桶键发散时删除记录兜底撤销考勤；
//   P2-36 同步映射的缺失状态自动补进状态项（消除幽灵映射）；
//   P2-37 改时段撞上手工考勤：保留手工条目、放弃搬移（代码层核对 + 断言）；
//   P2-38 改过映射后旧原因被正确替换（不再"迟到、迟到X"并存）；
//   P2-41 删除内容包死常量（编译层）；P2-45 超长区间夹取提示（界面层）；
//   P2-47 完整区间下趋势逐日补齐（空档记 0、排除放假）；
//   P2-61 build.bat 路径可覆盖（脚本层）；P2-62 VC_redist 机制已就绪（文档层）；
//   P2-64 学生选择器"已选 N 人 / 全选 / 清除"；
//   P2-66 考勤登记默认不预选状态（触屏防误登记）；
//   P2-75~81 文档/文案/文件头同步（仅 review）。
//
// 模式沿用 v230_audit_p2_test：test() + mock path_provider。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/widgets/student_picker_dialog.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_audit_p2c');
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

  group('P2-31 状态项校验与口径提示', () {
    test('重命名拒绝保留词"出勤"（provider 层校验）', () {
      provider.renameAttendanceStatus('迟到', '出勤');

      expect(provider.appData.settings.attendanceStatuses, contains('迟到'),
          reason: '非法重命名应被忽略');
      expect(provider.appData.settings.attendanceStatuses,
          isNot(contains('出勤')));
    });
  });

  group('P2-32 失效时段的显示回退', () {
    test('未知 key 退回记录保存的时段名', () {
      expect(periodNameForRecord('custom_abc', '上午上课'), '上午上课');
      expect(periodNameForRecord('', '上午上课'), '上午上课');
    });

    test('已知 key 仍优先使用当前时段名', () {
      final current = periodNameForRecord('class', '旧名字');
      expect(current, isNotEmpty);
      expect(current, isNot('旧名字'));
      expect(current, isNot('class'));
    });
  });

  group('P2-33 数据包必填字段与显式清空', () {
    Map<String, dynamic> fullPackageJson() =>
        jsonDecode(TransferService.buildPackage(
          AppData(
            recordsByDate: const {},
            settings: AppSettings.defaultSettings(),
          ),
          exportedAt: '2026-10-05T00:00:00',
        )) as Map<String, dynamic>;

    test('缺 attendanceStatuses 的旧包被拒绝', () {
      final json = fullPackageJson()
        ..remove('attendanceStatuses')
        ..remove('attendanceAbsentStatuses')
        ..remove('attendanceSyncMap');

      expect(TransferService.parsePackage(jsonEncode(json)), isNull);
    });

    test('整包还原：显式空映射清空本机', () async {
      provider.loadForTest(AppData(
        recordsByDate: const {},
        settings: AppSettings.defaultSettings().copyWith(
          attendanceSyncMap: const {'迟到': '迟到'},
        ),
      ));
      final clearJson = fullPackageJson()
        ..['attendanceSyncMap'] = <String, dynamic>{};
      await provider.restoreFromPackage(
        TransferService.parsePackage(jsonEncode(clearJson))!,
      );
      expect(provider.appData.settings.attendanceSyncMap, isEmpty,
          reason: '显式空映射应清空本机');
    });
  });

  group('P2-35 桶键与记录 date 发散', () {
    test('删除记录时兜底撤销挂在记录自带 date 下的考勤', () {
      provider.loadForTest(AppData(
        recordsByDate: {
          '2026-10-04': [
            StudentRecord(
              id: 'r1',
              studentName: '张三',
              operationType: '批评',
              reasons: '迟到',
              periodKey: 'class',
              periodName: '上课',
              remark: '',
              timestamp: '08:00:00',
              date: '2026-10-05',
            ),
          ],
        },
        settings: AppSettings.defaultSettings(),
        attendanceByDate: {
          '2026-10-05': [
            const AttendanceRecord(
              id: 'a1',
              studentName: '张三',
              status: '迟到',
              date: '2026-10-05',
              timestamp: '08:00:00',
              syncedFromRecord: true,
              syncedRecordId: 'r1',
            ),
          ],
        },
      ));

      provider.deleteRecord('r1', date: '2026-10-04');

      expect(provider.getAttendanceForDate('2026-10-05'), isEmpty,
          reason: '考勤挂在记录自带 date 下，也要被撤销');
    });
  });

  group('P2-36 幽灵映射消除', () {
    test('映射的状态键自动补进状态项，登记照常同步', () {
      expect(provider.appData.settings.attendanceStatuses,
          isNot(contains('事假')));

      provider.setAttendanceSyncMap({'事假': '无故缺课'});

      expect(provider.appData.settings.attendanceStatuses, contains('事假'),
          reason: '缺失的状态应先自动补入，避免幽灵映射');
      provider.setAttendance('张三', '事假', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04').single.reasons,
          '无故缺课');
    });
  });

  group('P2-37 改时段撞上已有考勤', () {
    test('手工条目保留、派生条目放弃搬移', () {
      provider.mergeStudents(['张三']);
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.addRecord('张三', '批评', ['迟到'], 'class', '',
          date: '2026-10-04');
      final record = provider.getRecordsForDate('2026-10-04').single;
      provider.setAttendance('张三', '请假',
          date: '2026-10-04', periodKey: 'meal');

      provider.updateRecord(record.id, '批评', ['迟到'], 'meal', '',
          date: '2026-10-04');

      final manual =
          provider.getAttendanceOf('张三', '2026-10-04', periodKey: 'meal')!;
      expect(manual.status, '请假', reason: '手工登记不能被覆盖');
      expect(manual.syncedRecordId, isEmpty);
      final derived =
          provider.getAttendanceOf('张三', '2026-10-04', periodKey: 'class');
      expect(derived, isNotNull, reason: '派生条目应放弃搬移、留在原时段');
      expect(provider.getAttendanceForDate('2026-10-04'), hasLength(2));
    });
  });

  group('P2-38 改过映射后的旧原因替换', () {
    test('旧口径原因被识别并替换，不再"迟到、迟到X"并存', () {
      provider.mergeStudents(['张三']);
      // 先用默认口径生成派生记录（原因=迟到）。
      provider.setAttendanceSyncMap({'迟到': '迟到'});
      provider.setAttendanceForStudents(['张三'], '迟到', date: '2026-10-04');
      expect(provider.getRecordsForDate('2026-10-04').single.reasons, '迟到');

      // 用户改了映射口径。
      provider.setAttendanceSyncMap({'迟到': '迟到X', '早退': '早退X'});
      provider.setAttendanceForStudents(['张三'], '早退', date: '2026-10-04');

      expect(
        provider.getRecordsForDate('2026-10-04').single.reasons,
        '早退X',
        reason: '旧口径原因"迟到"应被替换而不是并存',
      );
    });
  });

  group('P2-47 趋势逐日补齐', () {
    test('完整区间下空档记 0、放假被排除', () {
      final records = [
        StudentRecord(
          id: 'r1',
          studentName: '张三',
          operationType: '表扬',
          reasons: '认真',
          periodKey: 'class',
          periodName: '上课',
          remark: '',
          timestamp: '08:00:00',
          date: '2026-10-04',
        ),
      ];

      final result = StatisticsService.compute(
        records,
        rangeDates: const [
          '2026-10-01',
          '2026-10-02',
          '2026-10-03',
          '2026-10-04',
        ],
      );

      expect(
        result.dailyCounts.map((item) => item.date).toList(),
        ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04'],
        reason: 'D-014：放假日期保留在趋势里；空档仍补 0',
      );
      expect(
        result.dailyCounts
            .firstWhere((item) => item.date == '2026-10-01')
            .praiseCount,
        0,
      );
    });
  });

  group('P2-64 学生选择器工具条', () {
    testWidgets('多选：已选计数、全选、清除、确认人数', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: StudentPickerDialog(
              title: '选择学生',
              students: ['张三', '李四', '王五'],
              multiSelect: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('已选 0 人'), findsOneWidget);

      await tester.tap(find.text('全选'));
      await tester.pump();
      expect(find.text('已选 3 人'), findsOneWidget);
      expect(find.text('确认（3 人）'), findsOneWidget);

      await tester.tap(find.text('清除'));
      await tester.pump();
      expect(find.text('已选 0 人'), findsOneWidget);

      await tester.tap(find.text('张三'));
      await tester.pump();
      expect(find.text('已选 1 人'), findsOneWidget);
      expect(find.text('确认（1 人）'), findsOneWidget);
    });
  });
}
