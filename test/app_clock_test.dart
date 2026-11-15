/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.6
 * 创建日期 (Created): 2026-11-15
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

// 时钟抽象回归：冻结时钟后，所有“今天/现在”语义必须跟着冻结，
// 否则跨午夜跑用例会偶发失败（这正是引入 AppClock 的原因）。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/operation_log_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/utils/app_clock.dart';

void main() {
  tearDown(AppClock.resetForTest);

  test('默认返回真实时间', () {
    final before = DateTime.now();
    final now = AppClock.now();
    final after = DateTime.now();
    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
    expect(AppClock.isFrozenForTest, isFalse);
  });

  test('冻结后 now/today 都跟随固定时刻', () {
    AppClock.freezeForTest(DateTime(2026, 3, 1, 23, 59, 30));
    expect(AppClock.now(), DateTime(2026, 3, 1, 23, 59, 30));
    expect(AppClock.today(), DateTime(2026, 3, 1));
    expect(AppClock.isFrozenForTest, isTrue);
  });

  test('冻结跨午夜后，今日记录随日期切换', () {
    final provider = AppDataProvider();
    provider.appData.setStudents(const ['学生1']);
    AppClock.freezeForTest(DateTime(2026, 3, 1, 23, 59, 30));
    provider.addRecord(
      '学生1',
      '表扬',
      const ['助人为乐'],
      'class',
      '',
      date: '2026-03-01',
    );
    expect(provider.getTodayRecords(), hasLength(1));

    // 时钟推进到第二天：昨天的记录不再算“今日”。
    AppClock.freezeForTest(DateTime(2026, 3, 2, 0, 0, 10));
    expect(provider.getTodayRecords(), isEmpty);
    expect(
      provider.appData.recordsByDate['2026-03-01'],
      hasLength(1),
    );
  });

  test('操作日志时间戳使用冻结时钟', () {
    AppClock.freezeForTest(DateTime(2026, 5, 6, 7, 8, 9));
    final line = OperationLogService.formatLogLine(AppClock.now(), '测试', '明细');
    expect(line.startsWith('2026-05-06 07:08:09'), isTrue);
  });

  test('统计的今日字符串使用冻结时钟', () {
    AppClock.freezeForTest(DateTime(2026, 12, 31, 8));
    expect(
      StatisticsService.todayString(AppClock.now()),
      '2026-12-31',
    );
  });
}
