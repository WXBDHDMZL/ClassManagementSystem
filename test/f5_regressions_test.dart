import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/reason_library.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/utils/app_clock.dart';

void main() {
  tearDown(AppClock.resetForTest);

  test('跨零点记录在凌晨仍出现在今日列表和角标中', () {
    AppClock.freezeForTest(DateTime(2026, 11, 22, 0, 30));
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(AppData.empty());

    final record = provider.addRecord('张三', '表扬', const ['认真'], 'sleep', '');
    expect(record, isNotNull);
    expect(record!.date, '2026-11-21');

    expect(provider.getRecordsForDate('2026-11-22'), isEmpty);
    expect(
      provider.getTodayRecords().map((item) => item.id),
      contains(record.id),
    );
    expect(provider.todayCountsByStudent()['张三']?.praise, 1);
  });

  test('非跨零点时段仍使用日历当天', () {
    AppClock.freezeForTest(DateTime(2026, 11, 22, 12, 30));
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(AppData.empty());

    final record = provider.addRecord('李四', '批评', const ['迟到'], 'class', '');
    expect(record, isNotNull);
    expect(record!.date, '2026-11-22');
    expect(provider.getTodayRecords().map((item) => item.id), contains(record.id));
  });

  test('未进入管理会话时替换/恢复原因库返回失败', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings.defaultSettings().copyWith(passwordEnabled: true),
      ),
    );

    final library = ReasonLibrary(
      praise: const {'class': ['认真']},
      criticism: const {'class': ['迟到']},
    );
    expect(provider.setReasons(library), isFalse);
    expect(provider.resetReasons(), isFalse);
  });
}
