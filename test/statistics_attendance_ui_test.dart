// 统计看板已与考勤解耦：即使底层存在考勤数据，统计页也不展示考勤板块。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/attendance_feature.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/statistics_dialog.dart';
import 'package:class_management_system/utils/app_clock.dart';

String _today() => StatisticsService.todayString(AppClock.now());

Widget _wrap(AppDataProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: StatisticsDialog())),
      ),
    );

void main() {
  setUp(() => AttendanceFeature.enabledForTests = false);
  tearDown(() => AttendanceFeature.enabledForTests = true);

  testWidgets('统计看板不展示考勤板块', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.addRecord('张三', '表扬', ['认真听讲'], 'class', '');
    provider.setAttendance('张三', '迟到', date: _today());

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('考勤'), findsNothing);
    expect(find.textContaining('异常次数'), findsNothing);
    expect(find.textContaining('状态分布'), findsNothing);
  });

  testWidgets('只有考勤没有记录：统计页显示空态', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setAttendance('张三', '缺勤', date: _today());

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('该范围内暂无记录'), findsOneWidget);
    final exportButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('导出报表'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(exportButton.onPressed, isNull);
  });
}
