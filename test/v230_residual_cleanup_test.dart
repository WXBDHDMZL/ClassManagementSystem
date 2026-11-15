// 第 11 轮「清残余」回归（V2.30.32）。
//
//   覆盖可单测的残余修复：
//   G-3  addRecord 非法日期不产生脏桶键、重复 recordId 自动换新；
//   G-15 出厂原因库补上"早退"（与出厂同步映射一致）；
//   G-19 resetPeriodsForTest 能把时段全局状态复位；
//   G-29 parseReasonsRows 通过 onSkipped 回传跳过行数（不再静默丢）；
//   G-31 年份口径与下游统一（2101 非法 / 2100 合法）；
//   N-4  replaceStudents 空名单返回 false 且不改动名单。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/constants/reasons.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/utils/app_date.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_residual_dir');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.path
          : null,
    );
    provider = AppDataProvider();
    resetPeriodsForTest(); // G-19：每个用例从出厂时段开始，避免互相串态
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

  group('G-3 addRecord 校验下沉', () {
    test('非法 date 不产生脏桶键（回退到归属日）', () {
      provider.mergeStudents(['张三']);
      provider.addRecord('张三', '批评', ['迟到'], 'class', '',
          date: '2026-99-99');
      expect(
        provider.appData.recordsByDate.containsKey('2026-99-99'),
        isFalse,
        reason: '非法日期不应成为记录桶键',
      );
    });

    test('传入重复 recordId 时自动换新 id（不撞号）', () {
      provider.mergeStudents(['张三']);
      provider.addRecord('张三', '批评', ['迟到'], 'class', '',
          date: '2026-10-04', recordId: 'dup');
      provider.addRecord('张三', '批评', ['迟到'], 'class', '',
          date: '2026-10-04', recordId: 'dup');
      final same = provider
          .getRecordsForDate('2026-10-04')
          .where((r) => r.id == 'dup')
          .length;
      expect(same, 1, reason: '重复注入的 id 只能存在一条');
    });
  });

  group('G-15 出厂原因与同步映射一致', () {
    test('批评原因库含"早退"', () {
      expect(criticismReasons['_common'], contains('早退'));
    });
  });

  group('G-19 时段全局状态可复位', () {
    test('applyCustomPeriods 后 resetPeriodsForTest 回到多段出厂时段', () {
      applyCustomPeriods([
        {'key': 'class', 'label': '08:00-12:30 上课'},
      ]);
      expect(effectivePeriods().length, 1);
      resetPeriodsForTest();
      expect(effectivePeriods().length, greaterThan(1));
    });
  });

  group('G-29 原因导入跳过行数可见', () {
    test('不可识别的行计入 skipped 并回传', () {
      var skipped = -1;
      final rows = TransferService.parseReasonsRows([
        ['表扬', '全时段通用', '助人为乐'],
        ['表扬', '不存在的时段XYZ', '认真'],
        ['乱类型', '全时段通用', '什么'],
      ], onSkipped: (n) => skipped = n);
      expect(rows.length, 1);
      expect(skipped, 2);
    });
  });

  group('G-31 年份口径统一', () {
    test('2100 合法、2101 非法，且与下游常量一致', () {
      expect(kMinSupportedYear, 1900);
      expect(kMaxSupportedYear, 2100);
      expect(isValidYmdDate('2100-12-31'), isTrue);
      expect(isValidYmdDate('2101-01-01'), isFalse);
    });
  });

  group('N-4 空名单替换有反馈', () {
    test('全部为空的名单返回 false 且不改动现有名单', () {
      provider.mergeStudents(['张三']);
      final ok = provider.replaceStudents(['  ', '']);
      expect(ok, isFalse);
      expect(provider.appData.students, contains('张三'));
    });
  });
}
