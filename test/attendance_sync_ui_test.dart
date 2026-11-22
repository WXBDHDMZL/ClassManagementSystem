// 回归测试：考勤同步生成的批评记录（时间段=全天）在记录列表里的删除/编辑、
// 以及在考勤窗口里的撤销，都不应抛异常（曾出现"删除后黑屏"的崩溃）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/models/attendance_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/services/statistics_service.dart';
import 'package:class_management_system/widgets/attendance_dialog.dart';
import 'package:class_management_system/widgets/record_list.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

AppDataProvider _providerWithSyncedRecord() {
  final provider = AppDataProvider();
  provider.mergeStudents(const ['张三']);
  provider.setAttendanceEnabled(true);
  provider.setAttendance('张三', '迟到', date: _today());
  return provider;
}

/// 考勤对话框默认日期 = 记录/考勤的**归属日**（X-12：跨零点时段的凌晨部分
/// 归属前一天）。用例必须与生产同口径 —— 否则每天 00:00–06:20 会被误判成
/// "对话框没渲染"（对话框默认落在前一天，而这里却按自然日登记/断言）。
String _today() {
  final now = AppClock.now();
  return StatisticsService.dateString(
    attributionDay(now, matchPeriodByMinutes(now.hour * 60 + now.minute)),
  );
}

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('记录列表：删除同步生成的考勤记录不报错', (tester) async {
    final provider = _providerWithSyncedRecord();
    expect(provider.getRecordsForDate(_today()).length, 1);

    await tester.pumpWidget(
      _wrap(
        provider,
        RecordList(records: provider.getRecordsForDate(_today())),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pump();
    await tester.pump();
    expect(find.text('确定删除'), findsNothing);

    expect(tester.takeException(), isNull);
    expect(provider.getRecordsForDate(_today()), isEmpty);
    // S-1：删派生批评记录保留老师手工登记的考勤
    expect(provider.getAttendanceForDate(_today()), isNotEmpty);
    // 收尾：等提示条计时器结束，避免 fake timer 断言失败
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('记录列表：开启密码后走密码框删除同步记录也不报错', (tester) async {
    final provider = _providerWithSyncedRecord();
    provider.setPasswordHash(SecurityService.hashPassword('1234'));
    provider.setPasswordEnabled(true);

    await tester.pumpWidget(
      _wrap(
        provider,
        RecordList(records: provider.getRecordsForDate(_today())),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pump();
    await tester.pump();
    expect(find.text('确定删除'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确认'));
    // 性能批 M6：两次密码校验都走后台 isolate（密码框一次、删除前一次）。
    await pumpUntilRealAsync(
      tester,
      () => provider.getRecordsForDate(_today()).isEmpty,
    );

    expect(tester.takeException(), isNull);
    expect(provider.getRecordsForDate(_today()), isEmpty);
    // S-1：删派生批评记录保留老师手工登记的考勤。
    expect(provider.getAttendanceForDate(_today()), isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
    provider.exitManagementMode();
  });

  testWidgets('考勤窗口：撤销全天记录（含同步记录）不报错', (tester) async {
    final provider = _providerWithSyncedRecord();

    await tester.pumpWidget(_wrap(provider, const AttendanceDialog()));
    await tester.pump();

    // 撤销按钮（× 在 InputChip 上）
    final chip = find.byType(InputChip);
    expect(chip, findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.pump();

    // 二次确认
    expect(find.text('确定撤销'), findsOneWidget);
    await tester.tap(find.text('确定撤销'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(provider.getAttendanceForDate(_today()), isEmpty);
    expect(provider.getRecordsForDate(_today()), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('考勤窗口：全天记录能正常渲染时间段与状态（不黑屏）', (tester) async {
    final provider = _providerWithSyncedRecord();

    await tester.pumpWidget(_wrap(provider, const AttendanceDialog()));
    await tester.pump();

    expect(find.text(AttendanceRecord.allDayLabel), findsOneWidget);
    expect(find.textContaining('迟到（1）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('启用操作身份后，先选记录人再打开考勤', (tester) async {
    final provider = _providerWithSyncedRecord();
    provider.setIdentityFeatureEnabled(true);
    expect(provider.activeIdentity, isNull);

    await tester.pumpWidget(
      _wrap(
        provider,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AttendanceDialog.show(context),
            child: const Text('打开考勤'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开考勤'));
    await tester.pumpAndSettle();

    expect(find.text('选择操作身份'), findsOneWidget);
    expect(find.text('考勤'), findsNothing, reason: '未选记录人时不应打开考勤窗口');

    await tester.tap(find.text('班长'));
    await tester.pumpAndSettle();

    expect(provider.activeIdentity?.name, '班长');
    expect(find.text('选择操作身份'), findsNothing);
    expect(find.text('考勤'), findsOneWidget);
    // 清理身份闲置计时器与提示条计时器，避免测试结束时报 pending timer。
    provider.clearActiveIdentity();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('考勤窗口显示当前记录人，异常记录也标注记录人', (tester) async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setAttendanceEnabled(true);
    provider.mergeStudents(['张三']);
    provider.setIdentityFeatureEnabled(true);
    provider.setIdentityIdleMinutes(0);
    provider.setActiveIdentity('class_monitor');
    provider.setAttendance('张三', '迟到', date: _today());

    await tester.pumpWidget(_wrap(provider, const AttendanceDialog()));
    await tester.pump();

    // 顶部身份横幅 + 异常记录 chip 各一处。
    expect(find.text('记录人：班长'), findsNWidgets(2));
  });

  testWidgets('考勤窗口打开后身份过期，登记前会再次要求选记录人', (tester) async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setAttendanceEnabled(true);
    provider.mergeStudents(['张三']);
    provider.setIdentityFeatureEnabled(true);
    provider.setIdentityIdleMinutes(0);
    provider.setActiveIdentity('class_monitor');

    await tester.pumpWidget(_wrap(provider, const AttendanceDialog()));
    await tester.pump();
    provider.clearActiveIdentity();
    await tester.pump();
    expect(find.text('请选择本次记录人'), findsOneWidget);

    await tester.tap(find.text('登记考勤'));
    await tester.pumpAndSettle();
    expect(find.text('选择操作身份'), findsOneWidget);
    expect(find.text('选择学生（可多选）'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('关闭'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择学生（可多选）'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('未选记录人时取消身份选择，不打开考勤', (tester) async {
    final provider = _providerWithSyncedRecord();
    provider.setIdentityFeatureEnabled(true);

    await tester.pumpWidget(
      _wrap(
        provider,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AttendanceDialog.show(context),
            child: const Text('打开考勤'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开考勤'));
    await tester.pumpAndSettle();
    expect(find.text('选择操作身份'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(provider.activeIdentity, isNull);
    expect(find.text('考勤'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
