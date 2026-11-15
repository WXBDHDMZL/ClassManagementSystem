// 本轮全面审计修复项的回归保护：
// ① 停用某个记录类型后，记录对话框不会按被停用的类型提交；
// ② 手动取消"计入未到"不会被静默还原；
// ③ 导出排序统一为"日期 + 时间"升序。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/record_dialog.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('停用批评后：记录对话框按表扬提交，不生成被停用的类型', (tester) async {
    // 记录对话框较高，放大视口并滚到确认按钮，避免"按钮在视口外点不到"。
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    // 出厂默认"默认操作类型"就是批评；这里停用批评后再打开对话框。
    provider.setRecordTypesEnabled(criticism: false);
    provider.setRecordDefaults(defaultType: 1, autoSelectPeriod: false);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: testApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const RecordDialog(studentName: '张三'),
                ),
                child: const Text('打开记录'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开记录'));
    await tester.pumpAndSettle();

    // 停用的"批评"不再作为选项；原因列表也应是表扬的原因（"讲话"是批评原因）。
    expect(find.widgetWithText(ElevatedButton, '批评'), findsNothing);
    expect(find.text('讲话'), findsNothing);
    expect(find.widgetWithText(FilterChip, '助人为乐'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '助人为乐'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    final records = provider.getTodayRecords();
    expect(records, hasLength(1));
    expect(records.first.operationType, '表扬');
    expect(records.first.reasons, '助人为乐');

    // 让提示条的定时器跑完，避免测试结束时残留 Timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('手动取消"计入未到"后，新增状态项不会把它改回来', () {
    final provider = AppDataProvider();
    // 出厂：请假 / 缺勤 计入未到。
    expect(provider.appData.settings.attendanceAbsentStatuses, contains('请假'));

    // 用户手动把"请假"改为"到校"（不减实到）。
    provider.setAttendanceAbsentStatuses(const ['缺勤']);
    expect(provider.appData.settings.attendanceAbsentStatuses, ['缺勤']);

    // 之后新增一个状态项（会走 setAttendanceStatuses 重新保存状态列表）。
    provider.setAttendanceStatuses([
      ...provider.appData.settings.attendanceStatuses,
      '事假',
    ]);

    final absent = provider.appData.settings.attendanceAbsentStatuses;
    expect(absent, isNot(contains('请假')), reason: '用户的手动设置不能被名称启发式改回来');
    expect(absent, contains('缺勤'));
    expect(absent, contains('事假'), reason: '新增状态按名称含"假"自动计入未到');
  });

  test('导出排序：统一按日期 + 时间升序（与记录导出口径一致）', () {
    StudentRecord make(String date, String time) => StudentRecord(
      id: '$date $time',
      studentName: '张三',
      operationType: '表扬',
      reasons: '助人为乐',
      periodKey: 'class',
      periodName: '上课',
      remark: '',
      timestamp: time,
      date: date,
    );

    final sorted = StatisticsService.sortByDateAndTime([
      make('2026-09-02', '09:00:00'),
      make('2026-09-01', '10:00:00'),
      make('2026-09-01', '08:00:00'),
    ]);

    expect(sorted.map((record) => '${record.date} ${record.timestamp}').toList(), [
      '2026-09-01 08:00:00',
      '2026-09-01 10:00:00',
      '2026-09-02 09:00:00',
    ]);
  });
}
