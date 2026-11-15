// 记录对话框测试：原因折叠（默认只显示常用若干条，可展开）与
// 时间段跟随自定义（含考勤同步记录的"全天"）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/record_dialog.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('原因较多时默认折叠，点"展开全部"后显示全部', (tester) async {
    final provider = AppDataProvider();
    final periodLabels = {
      for (final item in effectivePeriods()) item['label']!.split(' ').last,
    };

    await tester.pumpWidget(
      _wrap(provider, const RecordDialog(studentName: '张三')),
    );
    await tester.pump();

    // 时间段与原因都用 FilterChip：按"标签不是时段名"筛出原因项
    int reasonChipCount() => tester
        .widgetList<FilterChip>(find.byType(FilterChip))
        .where((chip) => !periodLabels.contains((chip.label as Text).data))
        .length;

    final expectedTotal = provider.appData.reasons
        .forPeriod('批评', 'class')
        .length;
    expect(expectedTotal, greaterThan(8));

    // 默认只显示 8 个原因
    expect(reasonChipCount(), 8);
    expect(find.textContaining('展开全部'), findsOneWidget);

    await tester.tap(find.textContaining('展开全部'));
    await tester.pump();

    expect(reasonChipCount(), greaterThan(8));
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('主界面批量追加不传日期时，按所选时段归属日落库', (tester) async {
    final provider = AppDataProvider();
    provider.mergeStudents(['张三', '李四']);

    await tester.pumpWidget(
      _wrap(
        provider,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showAppendRecordDialog(context, students: const ['张三', '李四']),
            child: const Text('批量'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('批量'));
    await tester.pumpAndSettle();

    // 选跨零点时段“就寝”，并使用该时段的默认批评原因。
    // 当前时刻可能已经自动落到“就寝”；若已选中，先切到别的时段再选，
    // 否则点击会取消选择，导致对应用原因不可见（时间相关的老测试脆弱点）。
    final sleepChip = find.widgetWithText(FilterChip, '就寝');
    await tester.ensureVisible(sleepChip);
    if (tester.widget<FilterChip>(sleepChip).selected) {
      final morningChip = find.widgetWithText(FilterChip, '早读');
      await tester.ensureVisible(morningChip);
      await tester.tap(morningChip);
      await tester.pump();
    }
    await tester.ensureVisible(sleepChip);
    await tester.tap(sleepChip);
    await tester.pump();

    final reasonChip = find.widgetWithText(FilterChip, '不按时就寝');
    await tester.ensureVisible(reasonChip);
    await tester.tap(reasonChip);
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    final expected = StatisticsService.dateString(
      attributionDay(AppClock.now(), 'sleep'),
    );
    expect(
      provider.getRecordsForDate(expected),
      hasLength(2),
      reason: '批量追加应使用所选时段的归属日，而不是固定自然日',
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('编辑考勤同步生成的记录：时间段显示"全天"且被选中', (tester) async {
    final provider = AppDataProvider();
    provider.mergeStudents(const ['张三']);
    provider.setAttendanceEnabled(true);
    final today = StatisticsService.todayString(AppClock.now());
    provider.setAttendance('张三', '迟到', date: today);
    final record = provider.getRecordsForDate(today).single;
    expect(record.periodKey, AttendanceRecord.allDayKey);

    await tester.pumpWidget(
      _wrap(
        provider,
        RecordDialog(
          studentName: record.studentName,
          editRecord: record,
          targetDate: today,
        ),
      ),
    );
    await tester.pump();

    expect(find.text(AttendanceRecord.allDayLabel), findsOneWidget);
    final allDayChip = tester.widget<FilterChip>(
      find.ancestor(
        of: find.text(AttendanceRecord.allDayLabel),
        matching: find.byType(FilterChip),
      ),
    );
    expect(allDayChip.selected, isTrue);
  });
}
