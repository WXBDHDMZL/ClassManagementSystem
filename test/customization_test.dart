// 新增自定义项测试：设置序列化兼容、启用类型至少留一个、
// 原因使用频率排序、导出列勾选、统计区间记忆。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/record_dialog.dart';

void main() {
  group('新增自定义项的序列化', () {
    test('界面字号/启用类型/原因排序/区间记忆/导出选项可完整往返', () {
      final settings = AppSettings(
        themeMode: ThemeModeType.system,
        uiScale: 1.15,
        praiseEnabled: false,
        criticismEnabled: true,
        reasonSortByUsage: true,
        statisticsRange: 5,
        statisticsRangeStart: '2026-08-01',
        statisticsRangeEnd: '2026-09-26',
        exportFilePrefix: '五年3班_',
        recordExportColumns: const ['date', 'name', 'reason'],
        autoStart: true,
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.uiScale, 1.15);
      expect(restored.praiseEnabled, isFalse);
      expect(restored.criticismEnabled, isTrue);
      expect(restored.reasonSortByUsage, isTrue);
      expect(restored.statisticsRange, 5);
      expect(restored.statisticsRangeStart, '2026-08-01');
      expect(restored.exportFilePrefix, '五年3班_');
      expect(restored.recordExportColumns, ['date', 'name', 'reason']);
      expect(restored.autoStart, isTrue);
    });

    test('旧数据缺字段时回退默认：字号 1.0、两类型启用、全部导出列/表', () {
      final restored = AppSettings.fromJson({'themeMode': 0});

      expect(restored.uiScale, 1.0);
      expect(restored.praiseEnabled, isTrue);
      expect(restored.criticismEnabled, isTrue);
      expect(restored.reasonSortByUsage, isFalse);
      expect(restored.statisticsRange, 0);
      expect(restored.autoStart, isFalse);
      expect(restored.recordExportColumns,
          AppSettings.defaultRecordExportColumns);
    });

    test('非法值被纠正：字号超范围回退、导出列只保留白名单且顺序固定', () {
      final restored = AppSettings.fromJson({
        'uiScale': 3.0,
        'recordExportColumns': ['name', 'unknown', 'date', 'name'],
        'statisticsRange': 99,
      });

      expect(restored.uiScale, 1.0);
      // 白名单过滤 + 去重 + 按默认顺序排列
      expect(restored.recordExportColumns, ['date', 'name']);
      expect(restored.statisticsRange, 0);
    });
  });

  group('启用类型与原因排序', () {
    test('不能同时停用表扬与批评（至少保留一个）', () {
      final provider = AppDataProvider();

      provider.setRecordTypesEnabled(praise: false);
      expect(provider.appData.settings.praiseEnabled, isFalse);
      expect(provider.appData.settings.criticismEnabled, isTrue);

      // 再停用批评 → 应被拒绝，保持批评仍启用
      provider.setRecordTypesEnabled(criticism: false);
      expect(provider.appData.settings.criticismEnabled, isTrue);
    });

    test('停用当前默认类型时自动切到仍启用的类型', () {
      final provider = AppDataProvider();

      provider.setRecordDefaults(defaultType: 0, autoSelectPeriod: false);
      provider.setRecordTypesEnabled(praise: false);
      expect(provider.appData.settings.recordDefaultType, 1);

      provider.setRecordTypesEnabled(praise: true);
      provider.setRecordDefaults(defaultType: 1, autoSelectPeriod: false);
      provider.setRecordTypesEnabled(criticism: false);
      expect(provider.appData.settings.recordDefaultType, 0);
    });

    test('原因使用次数统计：按顿号拆分、忽略空值', () {
      final provider = AppDataProvider();
      provider.addRecord('张三', '批评', ['迟到', '讲话'], 'class', '');
      provider.addRecord('李四', '批评', ['迟到'], 'class', '');

      final counts = provider.reasonUsageCounts();

      expect(counts['迟到'], 2);
      expect(counts['讲话'], 1);
    });

    testWidgets('开启"按使用频率排序"后，记录对话框里高频原因排在前面', (tester) async {
      final provider = AppDataProvider();
      // 让"迟到"成为高频原因（它在库内顺序里很靠后）
      provider.addRecord('张三', '批评', ['迟到'], 'class', '');
      provider.addRecord('李四', '批评', ['迟到'], 'class', '');
      provider.setReasonSortByUsage(true);
      // 阈值只有 8 个可见，高频原因必须在首屏

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: RecordDialog(studentName: '张三'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final chips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .map((chip) => (chip.label as Text).data)
          .toList();

      // 原因区默认只显示 8 个（前 9 个 FilterChip 是时间段），
      // 高频原因"迟到"必须落在可见的前 8 个原因里。
      expect(chips.contains('迟到'), isTrue);
      final reasonChips = chips.skip(9).take(8).toList();
      expect(reasonChips.first, '迟到');
    });
  });

  group('导出选项与统计区间', () {
    test('导出文件名前缀工具方法与设置联动', () {
      final provider = AppDataProvider();
      expect(provider.withExportPrefix('统计报表_2026-09-01'), '统计报表_2026-09-01');

      provider.setExportOptions(filePrefix: '五年3班_');
      expect(
        provider.withExportPrefix('统计报表_2026-09-01'),
        '五年3班_统计报表_2026-09-01',
      );
    });

    test('统计区间记忆：保存与读取一致', () {
      final provider = AppDataProvider();

      provider.setStatisticsRange(4, start: '2026-08-28', end: '2026-09-26');

      expect(provider.appData.settings.statisticsRange, 4);
      expect(provider.appData.settings.statisticsRangeStart, '2026-08-28');
      expect(provider.appData.settings.statisticsRangeEnd, '2026-09-26');
    });
  });
}
