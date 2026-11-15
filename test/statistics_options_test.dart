// 统计口径可配置（设置 → 日常使用 → 统计口径）：
// 需关注学生阈值与排行 Top N 的序列化、非法值回退、服务层计算与看板文案。

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/statistics_dialog.dart';
import 'package:class_management_system/utils/app_clock.dart';

StudentRecord _record(String name, String type) => StudentRecord(
  id: '$name-$type-${DateTime.now().microsecondsSinceEpoch}',
  studentName: name,
  operationType: type,
  reasons: '测试',
  periodKey: 'class',
  periodName: '上课',
  remark: '',
  timestamp: '08:00:00',
  date: StatisticsService.todayString(AppClock.now()),
);

void main() {
  test('统计口径：序列化往返一致', () {
    final settings = AppSettings(
      themeMode: ThemeModeType.system,
      attentionThreshold: 5,
      rankingTopN: 20,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.attentionThreshold, 5);
    expect(restored.rankingTopN, 20);
  });

  test('统计口径：旧数据缺字段时回退出厂值（阈值 3、Top 10）', () {
    final restored = AppSettings.fromJson({'themeMode': 0});

    expect(restored.attentionThreshold, 3);
    expect(restored.rankingTopN, 10);
    expect(
      StatisticsService.defaultAttentionThreshold,
      AppSettings.defaultAttentionThreshold,
      reason: '服务层默认值必须与设置项的出厂值同源，避免两处数字打架',
    );
  });

  test('统计口径：非法或超范围的值回退出厂值', () {
    expect(AppSettings.fromJson({'attentionThreshold': 0}).attentionThreshold, 3);
    expect(
      AppSettings.fromJson({'attentionThreshold': 999}).attentionThreshold,
      3,
    );
    expect(
      AppSettings.fromJson({'attentionThreshold': 'abc'}).attentionThreshold,
      3,
    );
    expect(AppSettings.fromJson({'rankingTopN': 1}).rankingTopN, 10);
    expect(AppSettings.fromJson({'rankingTopN': 999}).rankingTopN, 10);
    // 边界值应当被接受
    expect(AppSettings.fromJson({'attentionThreshold': 1}).attentionThreshold, 1);
    expect(
      AppSettings.fromJson({'attentionThreshold': 20}).attentionThreshold,
      20,
    );
    expect(AppSettings.fromJson({'rankingTopN': 3}).rankingTopN, 3);
    expect(AppSettings.fromJson({'rankingTopN': 50}).rankingTopN, 50);
  });

  test('统计口径：阈值真正作用到 attentionStudents', () {
    final records = [
      _record('张三', '批评'),
      _record('张三', '批评'),
      _record('李四', '批评'),
    ];

    expect(
      StatisticsService.attentionStudents(records).map((item) => item.name),
      isEmpty,
      reason: '默认阈值 3 次时两人都不够',
    );
    expect(
      StatisticsService.attentionStudents(
        records,
        threshold: 2,
      ).map((item) => item.name).toList(),
      ['张三'],
    );
    expect(
      StatisticsService.attentionStudents(
        records,
        threshold: 1,
      ).map((item) => item.name).toList(),
      ['张三', '李四'],
    );
  });

  testWidgets('统计看板：排行文案与需关注阈值跟随设置', (tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    provider.setStatisticsOptions(attentionThreshold: 2, rankingTopN: 5);
    provider.addRecord('张三', '表扬', ['助人为乐'], 'class', '');
    provider.addRecord('张三', '批评', ['讲话'], 'class', '');
    provider.addRecord('张三', '批评', ['讲话'], 'class', '');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: StatisticsDialog())),
        ),
      ),
    );
    await tester.pump();

    // 阈值在概览页；排行在排行页。
    expect(tester.takeException(), isNull);
    expect(find.textContaining('张三 · 批评 2 次'), findsOneWidget);
    await tester.tap(find.text('排行'));
    await tester.pumpAndSettle();
    expect(find.text('表扬 Top 5'), findsOneWidget);
    expect(find.text('批评 Top 5'), findsOneWidget);
  });

  testWidgets('统计看板只保留一张趋势图，不再提供柱形/饼图切换', (tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.addRecord('张三', '批评', ['讲话'], 'class', '');
    provider.addRecord('李四', '表扬', ['助人为乐'], 'class', '');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: StatisticsDialog())),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('折线图'), findsNothing);
    expect(find.text('柱形图'), findsNothing);
    expect(find.text('饼图'), findsNothing);
    expect(find.text('显示全部项目'), findsNothing);
  });

  testWidgets('统计看板：长区间自动按周聚合', (tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = AppClock.now();
    final start = StatisticsService.dateString(
      today.subtract(const Duration(days: 40)),
    );
    final end = StatisticsService.dateString(today);
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.addRecord(
      '张三',
      '表扬',
      ['认真听讲'],
      'class',
      '',
      date: start,
    );
    provider.addRecord(
      '李四',
      '批评',
      ['上课说话'],
      'class',
      '',
      date: end,
    );
    provider.setStatisticsRange(2, start: start, end: end);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: StatisticsDialog())),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('按周'), findsOneWidget);
  });

  testWidgets('统计看板：默认口径仍是 Top 10 与阈值 3', (tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    provider.addRecord('张三', '表扬', ['助人为乐'], 'class', '');
    provider.addRecord('张三', '批评', ['讲话'], 'class', '');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: StatisticsDialog())),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 阈值 3：1 次批评不应进入需关注名单（概览页）。
    expect(find.text('本区间没有需要重点关注的学生'), findsOneWidget);
    await tester.tap(find.text('排行'));
    await tester.pumpAndSettle();
    expect(find.text('表扬 Top 10'), findsOneWidget);
    expect(find.text('批评 Top 10'), findsOneWidget);
  });
}
