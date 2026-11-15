// 悬浮球右键“快速记录”回归：表扬/批评都走多选，选中多人时按批量记录处理，
// 并在记录对话框里预选对应类型。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/main.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/desktop_service.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    );

/// 数据改动后等写盘链与通知走完（测试环境无存储目录，保存会失败但通知仍会到达）。
Future<void> _settleData(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('悬浮球快速批评：可多选学生，批量对话框预选批评类型', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    provider.mergeStudents(['测试甲', '测试乙']);
    // 默认类型固定为表扬；若预选批评失效，下面的批评原因就不会出现。
    provider.setRecordDefaults(defaultType: 0, autoSelectPeriod: false);

    await tester.pumpWidget(_wrap(provider, const HomePage()));
    await tester.pump();

    final handler = DesktopService.instance.onBallMenuAction;
    expect(handler, isNotNull, reason: '主页应注册悬浮球菜单回调');
    unawaited(handler!(BallMenuAction.quickCriticize));
    await tester.pumpAndSettle();

    expect(find.text('快速批评：选择学生（可多选）'), findsOneWidget);
    expect(find.text('已选 0 人'), findsOneWidget);

    // 名单较长时列表按需构建，先搜索出测试学生再勾选。
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      '测试',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, '测试甲'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '测试乙'));
    await tester.pump();
    expect(find.text('已选 2 人'), findsOneWidget);

    await tester.tap(find.text('确认（2 人）'));
    await tester.pumpAndSettle();

    expect(find.text('为 测试甲、测试乙 操作'), findsOneWidget);

    final reason = provider.appData.reasons.forPeriod('批评', '_common').first;
    final chip = find.widgetWithText(FilterChip, reason);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();

    await tester.tap(find.text('确认'));
    await _settleData(tester);

    final records = provider.getTodayRecords();
    expect(records, hasLength(2));
    expect(
      records.map((record) => record.studentName),
      containsAll(['测试甲', '测试乙']),
    );
    expect(
      records.every((record) => record.operationType == '批评'),
      isTrue,
      reason: '快速批评应预选批评，不能落成默认的表扬',
    );
    expect(find.text('撤销'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('悬浮球快速表扬：类型已停用时明确拦截，不打开记录对话框', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    provider.mergeStudents(['测试甲']);
    provider.setRecordTypesEnabled(praise: false, criticism: true);

    await tester.pumpWidget(_wrap(provider, const HomePage()));
    await tester.pump();

    final handler = DesktopService.instance.onBallMenuAction;
    expect(handler, isNotNull);
    unawaited(handler!(BallMenuAction.quickPraise));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('已在设置 → 记录与名单 → 记录设置中停用'),
      findsOneWidget,
    );
    expect(find.text('快速表扬：选择学生（可多选）'), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
