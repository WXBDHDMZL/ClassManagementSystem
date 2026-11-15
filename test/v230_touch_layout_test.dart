// 触控与缩放专项回归（V2.30.26，第 7 轮：X-8 / X-20 / X-21 / X-22 / X-23 / X-24）。
//
//   X-8  学生卡片单元高度设 44 下限（触控点按区），溢出时兜底可滚动；
//   X-20 系统字号 × 应用字号**叠加**（不再覆盖系统无障碍缩放）；
//   X-21 网格只是"读"provider，不再重复注册订阅（G-50 已修，见交接说明纠偏）；
//   X-22 拖动排序手柄命中区放大到 44×44；
//   X-23 撤销考勤 chip 不再用 compact 密度、删除图标放大；
//   X-24 状态标签宽度随字号缩放，特大字号不再折行错位。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/main.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/attendance_dialog.dart';
import 'package:class_management_system/widgets/list_library_dialogs.dart';
import 'package:class_management_system/widgets/student_card.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_touch_layout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.path
          : null,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteDirectoryWithRetry(tempDir);
  });

  Future<void> pumpApp(WidgetTester tester, AppDataProvider provider) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: const MyApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('X-8：学生卡片触控高度不低于 44 且不溢出', (tester) async {
    final provider = providerWithStudents(syntheticStudents(12));
    await flushWrites(provider);
    await pumpApp(tester, provider);
    expect(tester.takeException(), isNull, reason: '网格不应溢出/抛异常');

    final cards = find.byType(StudentCard);
    expect(cards, findsWidgets, reason: '测试名单应渲染出卡片');
    for (var i = 0; i < cards.evaluate().length; i++) {
      final size = tester.getSize(cards.at(i));
      expect(
        size.height,
        greaterThanOrEqualTo(44.0 - 0.01),
        reason: '第 $i 张卡片高度 ${size.height} 低于触控下限 44',
      );
    }
  });

  test('X-20：composeTextScaler 叠加系统与应用字号', () {
    expect(
      composeTextScaler(const TextScaler.linear(1.5), 1.2).scale(10),
      closeTo(18.0, 0.001),
      reason: '系统 1.5 × 应用 1.2 = 1.8',
    );
    expect(
      composeTextScaler(TextScaler.noScaling, 1.0).scale(10),
      closeTo(10.0, 0.001),
    );
  });

  testWidgets('X-22：拖动排序手柄命中区至少 44×44', (tester) async {
    final provider = providerWithStudents(syntheticStudents(5));
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: StudentManageDialog()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final handles = find.byType(ReorderableDragStartListener);
    expect(handles, findsWidgets, reason: '名单页应有拖动排序手柄');
    for (var i = 0; i < handles.evaluate().length; i++) {
      final size = tester.getSize(handles.at(i));
      expect(size.width, greaterThanOrEqualTo(44.0 - 0.01));
      expect(size.height, greaterThanOrEqualTo(44.0 - 0.01));
    }
  });

  testWidgets('X-23 / X-24：考勤对话框特大字号下不溢出、chip 非紧凑', (tester) async {
    final provider = AppDataProvider();
    provider.mergeStudents(['张三']);
    final now = AppClock.now();
    final today = StatisticsService.dateString(now);
    final yesterday = StatisticsService.dateString(
      DateTime(now.year, now.month, now.day - 1),
    );
    // 归属日可能是今天或（凌晨）昨天，两天都登记，避免用例受运行时刻影响。
    provider.setAttendanceForStudents(['张三'], '迟到', date: today);
    provider.setAttendanceForStudents(['张三'], '迟到', date: yesterday);

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: AttendanceDialog()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull, reason: '特大字号下不应溢出');

    final chips = find.byType(InputChip);
    expect(chips, findsWidgets, reason: '已登记的异常应显示为可撤销的 chip');
    final chip = tester.widget<InputChip>(chips.first);
    expect(chip.visualDensity, isNot(VisualDensity.compact),
        reason: 'X-23：compact 密度会把 × 命中区压到不足 44');
    final icon = chip.deleteIcon;
    expect(icon, isA<Icon>());
    expect((icon! as Icon).size!, greaterThanOrEqualTo(20));
  });
}
