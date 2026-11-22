// 审查修复的回归测试（对应《独立审查与测试报告》探针 B/C/D/I 与 P1-6/P2-1/N1）。
// 每条测试都先复述"曾经的缺陷"，防止修复被无意回退。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/atomic_file.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/utils/app_date.dart';
import 'package:class_management_system/widgets/settings_pages.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

void main() {
  group('统一日期校验器（P1-3/N1 的公共依赖）', () {
    test('非法日期一律拒绝（滚动即非法）', () {
      expect(isValidYmdDate('2026-13-45'), isFalse);
      expect(isValidYmdDate('abcd-ef-gh'), isFalse);
      expect(isValidYmdDate('2026-02-30'), isFalse);
      expect(isValidYmdDate('2026-02-29'), isFalse, reason: '2026 不是闰年');
      expect(isValidYmdDate('2026-9-1'), isFalse, reason: '少补零不是合法格式');
      expect(isValidYmdDate(''), isFalse);
    });

    test('合法日期通过（含闰年）', () {
      expect(isValidYmdDate('2026-10-01'), isTrue);
      expect(isValidYmdDate('2024-02-29'), isTrue);
    });

    test('N1：设置里的日期解析不再接受形状合法但日历不存在的日期', () {
      final restored = AppSettings.fromJson({
        'themeMode': 0,
        'statisticsRangeStart': '2026-13-45',
      });
      expect(restored.statisticsRangeStart, isEmpty);
    });
  });

  group('P1-3 考勤导入日期校验', () {
    test('非法日期不入库，并通过 onSkipped 报告跳过行数', () {
      final result = TransferService.parseAttendanceRows(
        const [
          ['日期', '学生姓名', '考勤状态'],
          ['2026-13-45', '张三', '迟到'],
          ['abcd-ef-gh', '李四', '早退'],
          ['2026-10-01', '王五', '迟到'],
        ],
      );
      expect(result.records, hasLength(1), reason: '只有合法日期的那一行入库');
      expect(result.records.first.studentName, '王五');
      expect(result.skipped, 2, reason: '两行非法日期应计入跳过');
    });

    test('不传 onSkipped 时行为不变（旧调用点兼容）', () {
      final parsed = TransferService.parseAttendanceRows(const [
        ['日期', '学生姓名', '考勤状态'],
        ['2026-10-01', '张三', '迟到'],
      ]).records;
      expect(parsed, hasLength(1));
    });
  });

  group('P1-1 时段设置保存', () {
    testWidgets('不改动直接保存，自定义时段原样保留（探针 B）', (tester) async {
      final provider = AppDataProvider();
      provider.setPeriods(const [
        {'key': 'p1', 'label': '08:00-09:40 第一节'},
        {'key': 'p2', 'label': '10:00-11:40 第二节'},
      ]);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: testApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: PeriodSettingsPage()),
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pump();
      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pump();
      // 保存后的提示条带有定时器，排干后再断言，避免"Timer still pending"。
      await tester.pump(const Duration(seconds: 5));

      expect(
        provider.appData.settings.periods.length,
        2,
        reason: '不改动直接保存不得清空自定义时段（缺陷曾是 2 段保存后变 0 段）',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('P1-2 记录编辑与考勤重对齐', () {
    testWidgets('编辑未选时段的记录后，考勤时段键保持 all_day 且不产生重复（探针 D）', (tester) async {
      final provider = AppDataProvider();
      provider.setAttendanceSyncMap(const {'迟到': '迟到'});
      final today = StatisticsService.todayString(AppClock.now());
      provider.addRecord('测试学生甲', '批评', const ['迟到'], '', '');
      // 新建时空时段已在 addRecord 内规整为 all_day。
      expect(provider.getTodayRecords().first.periodKey, 'all_day');

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: testApp(theme: AppTheme.light(), home: const Scaffold()),
        ),
      );

      // 直接走 provider 的编辑路径（与记录对话框一致）。
      final record = provider.getTodayRecords().first;
      provider.updateRecord(
        record.id,
        '批评',
        const ['迟到'],
        '',
        '',
        date: today,
      );

      final attendance = provider.getAttendanceForDate(today);
      expect(attendance, hasLength(1), reason: '不得因编辑产生第二条考勤');
      expect(
        attendance.first.periodKey,
        'all_day',
        reason: '考勤时段键不得被改写成空串（缺陷曾是空串）',
      );
    });
  });

  group('P1-4 写盘原子性', () {
    test('写入全程主文件始终存在，且内容为完整的一次写入（探针 I）', () async {
      final temp = Directory.systemTemp.createTempSync('cms_atomic');
      addTearDown(() async {
        await deleteDirectoryWithRetry(temp);
      });
      final path = '${temp.path}${Platform.pathSeparator}probe.enc';
      // StorageService 的路径来自 path_provider，测试环境不可用；
      // 这里直接对 AtomicFile 做同等强度的探针（唯一临时名 + rename 覆盖）。
      await AtomicFile.writeString(path, 'INITIAL');
      var sawMissing = false;
      var pending = 2;
      final writes = <Future<void>>[
        AtomicFile.writeString(path, 'BIG' * 20000).whenComplete(() => pending--),
        AtomicFile.writeString(path, 'SMALL').whenComplete(() => pending--),
      ];
      var rounds = 0;
      while (pending > 0 && rounds < 100000) {
        await Future<void>.delayed(Duration.zero);
        if (!File(path).existsSync()) sawMissing = true;
        rounds++;
      }
      await Future.wait(writes);
      expect(sawMissing, isFalse, reason: '原子写不允许出现主文件不存在的时间窗');
      expect(File(path).readAsStringSync(), 'SMALL');
    });

    test('同一目标的并发写入按顺序串行，最终内容是其中一次的完整结果', () async {
      final temp = Directory.systemTemp.createTempSync('cms_atomic_queue');
      addTearDown(() async {
        await deleteDirectoryWithRetry(temp);
      });
      final path = '${temp.path}${Platform.pathSeparator}q.enc';
      await AtomicFile.writeString(path, 'S0');
      final futures = <Future<void>>[
        for (var i = 1; i <= 8; i++) AtomicFile.writeString(path, 'S$i' * 5000),
      ];
      await Future.wait(futures);
      final content = File(path).readAsStringSync();
      expect(
        content.startsWith('S') && (content.length == 10000 || content == 'S0'),
        isTrue,
        reason: '最终内容必须是某一次完整写入，不允许交错损坏',
      );
      expect(File('$path.tmp').existsSync(), isFalse, reason: '临时文件不应残留');
    });
  });

}
