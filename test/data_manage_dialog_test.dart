// 名单管理 / 原因管理对话框（list_library_dialogs.dart）交互测试。
//
// 背景（复核报告 #41）：这两个对话框此前没有任何测试覆盖（覆盖率约 1%），
// 名单/原因库的增删改入口全靠人工点。这里补齐核心交互：
//  - 名单：新增（成功/重名/空名拦截）、删除（二次确认）、改名、清空名单；
//  - 原因库：新增（成功/重复/空拦截）、删除（二次确认）、改名、
//    表扬/批评切换、时段分组切换。
//
// 三条关键测试约束（踩坑记录，改动前必读）：
//  1. **不要 mock path_provider**：mock 之后 provider 的串行写盘链会真正进入
//     文件 IO——"fake zone 微任务 ↔ 真实 IO 事件"交替推进的链在用例收尾时
//     无法走完，testWidgets 会挂在收尾阶段（did not complete，60 秒超时，
//     且后续所有用例全部连锁失败）。不 mock 时写盘链停在 path_provider
//     这一步（无害），与 attendance_sync_ui_test 等现有 UI 测试同模式。
//     代价是 tearDown 不能 flushWrites（会 await 那条挂起的链）。
//  2. **provider 的写操作不在同步路径上通知界面**，而是异步写盘完成后才
//     notifyListeners（见 _save 实现）。断言"界面已反映新数据"必须用
//     _rebuild 强制重建界面；纯数据断言直接读 provider（同步）。
//  3. **对话框列表装在固定高度的滚动容器里**，测试名单固定为 3 人
//     （providerWithStudents 的默认值），默认原因库仍远超可视条数——操作列表第一条
//     （find.xxx().first）、断言用动态取值，不要硬编码名单/原因内容。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/time_periods.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/list_library_dialogs.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

Future<void> _pumpDialog(
  WidgetTester tester,
  AppDataProvider provider,
  Widget dialog,
) async {
  // 原因管理对话框比默认 800×600 测试视口高（多出表扬/批评切换与时段分组），
  // 底部的"新增"输入行会被推出视口导致 tap 落空——放大视口让整框可见。
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(provider, dialog));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 强制重建对话框界面，让它读到 provider 的最新数据。
/// 界面上的"共 N 人"计数与列表条目要等写盘后的 notifyListeners 才刷新，
/// 测试里等不到这条异步链（见文件头说明 1、2），直接重建来验证渲染结果。
/// 注意：重建会丢弃旧的 Overlay（顶部提示条），提示条断言必须放在重建前。
Future<void> _rebuild(
  WidgetTester tester,
  AppDataProvider p,
  Widget dialog,
) async {
  await tester.pumpWidget(_wrap(p, dialog));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 用例中段清理：让已显示的顶部提示条（2 秒后被定时器移除）走完生命周期，
/// 避免它的残留影响同一用例里后续重建界面的断言。
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
}

/// 用例收尾：先推进 fake 时间让顶部提示条的 2 秒移除定时器触发，
/// 再卸载整棵 widget 树清掉 Overlay 等残留状态。
/// （提示条的 Future.delayed 若不触发，testWidgets 收尾会报
/// "A Timer is still pending even after the widget tree was disposed"。）
Future<void> _settleDown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  group('名单管理对话框', () {
    testWidgets('新增学生成功（头部计数与提示更新）；重复姓名被拦下', (tester) async {
      final p = providerWithStudents();
      final before = p.appData.students.length;
      await _pumpDialog(tester, p, const StudentManageDialog());

      expect(find.text('共 $before 人（可拖动排序）'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '张三');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      // 提示条挂 Overlay、不依赖异步 notify，先于重建断言。
      expect(find.text('已添加学生'), findsOneWidget);
      // 头部计数要等写盘后的 notify 才刷新：重建界面使其反映最新数据。
      await _rebuild(tester, p, const StudentManageDialog());
      expect(p.appData.students, contains('张三'));
      expect(find.text('共 ${before + 1} 人（可拖动排序）'), findsOneWidget);

      // 同名再添加 → 拦截 + 错误提示（两条提示文案不同，可同时存在）。
      await tester.enterText(find.byType(TextField), '张三');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(p.appData.students.where((n) => n == '张三'), hasLength(1));
      expect(find.text('姓名已存在'), findsOneWidget);

      await _settleDown(tester);
    });

    testWidgets('空姓名被拦下（与 validateStudentName 同一口径）', (tester) async {
      final p = providerWithStudents();
      final before = p.appData.students.length;
      await _pumpDialog(tester, p, const StudentManageDialog());

      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(p.appData.students, hasLength(before));
      expect(find.text('姓名不能为空'), findsOneWidget);

      await _settleDown(tester);
    });

    testWidgets('删除学生需二次确认，确认后移除并提示', (tester) async {
      final p = providerWithStudents();
      // 操作测试名单的第一条（列表首项必然可见），名字动态取、不硬编码。
      final first = p.appData.students.first;
      await _pumpDialog(tester, p, const StudentManageDialog());

      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pump();
      expect(
        find.text('确定从名单中删除「$first」吗？该学生已有的历史记录与考勤记录不会被删除。'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ElevatedButton, '确定'));
      await tester.pump();
      expect(p.appData.students, isNot(contains(first)));
      expect(find.text('已删除'), findsOneWidget);

      await _settleDown(tester);
    });

    testWidgets('修改姓名生效，名单中出现新名字', (tester) async {
      final p = providerWithStudents();
      final first = p.appData.students.first;
      await _pumpDialog(tester, p, const StudentManageDialog());

      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pump();
      // 输入对话框弹出，初值 = 旧名。
      final promptField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(promptField, findsOneWidget);
      await tester.enterText(promptField, '张三丰');
      await tester.tap(find.widgetWithText(ElevatedButton, '确定'));
      await tester.pump();

      expect(p.appData.students, contains('张三丰'));
      expect(p.appData.students, isNot(contains(first)));
      expect(find.text('已修改，历史记录与考勤记录中的姓名同步更新'), findsOneWidget);

      await _settleDown(tester);
    });

    testWidgets('清空名单需二次确认，确认后名单为空', (tester) async {
      final p = providerWithStudents();
      await _pumpDialog(tester, p, const StudentManageDialog());

      await tester.tap(find.text('清空名单'));
      await tester.pump();
      expect(
        find.text('将清空当前名单（历史记录与考勤记录不受影响）。确定继续吗？'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ElevatedButton, '确定'));
      await tester.pump();
      expect(p.appData.students, isEmpty);
      expect(find.text('名单已清空'), findsOneWidget);

      await _settleDown(tester);
    });
  });

  group('原因管理对话框', () {
    testWidgets('新增原因成功；重复与空原因被拦下并提示', (tester) async {
      final p = AppDataProvider();
      final before =
          (p.appData.reasons.praise['_common'] ?? const <String>[]).length;
      await _pumpDialog(tester, p, const ReasonManageDialog());

      await tester.enterText(find.byType(TextField), '课堂发言特别积极');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        contains('课堂发言特别积极'),
      );
      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        hasLength(before + 1),
      );
      expect(find.text('已添加原因'), findsOneWidget);

      // 重复 → 拦截。
      await tester.enterText(find.byType(TextField), '课堂发言特别积极');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(find.text('原因不能为空或已存在'), findsOneWidget);

      // 空 → 同样拦截。统一通知会对相同文案+类型去重，只保留一条可见提示。
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(find.text('原因不能为空或已存在'), findsOneWidget);

      await _settleDown(tester);
    });

    testWidgets('删除原因需二次确认，确认后移除并提示', (tester) async {
      final p = AppDataProvider();
      // 操作默认"全时段通用"分组的第一条，内容动态取、不硬编码。
      final first =
          (p.appData.reasons.praise['_common'] ?? const <String>[]).first;
      await _pumpDialog(tester, p, const ReasonManageDialog());

      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pump();
      expect(find.text('确定删除原因「$first」吗？该操作不可撤销。'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, '确定'));
      await tester.pump();
      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        isNot(contains(first)),
      );
      expect(find.text('已删除原因'), findsOneWidget);

      // 界面也要真的不再显示该原因（依赖写盘后的 notify → 重建验证）。
      await _drainTimers(tester);
      await _rebuild(tester, p, const ReasonManageDialog());
      expect(find.text(first), findsNothing);

      await _settleDown(tester);
    });

    testWidgets('修改原因生效，列表显示新原因', (tester) async {
      final p = AppDataProvider();
      final first =
          (p.appData.reasons.praise['_common'] ?? const <String>[]).first;
      await _pumpDialog(tester, p, const ReasonManageDialog());

      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pump();
      final promptField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(promptField, findsOneWidget);
      await tester.enterText(promptField, '测试原因乙');
      await tester.tap(find.widgetWithText(ElevatedButton, '确定'));
      await tester.pump();

      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        contains('测试原因乙'),
      );
      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        isNot(contains(first)),
      );
      expect(find.text('已修改原因'), findsOneWidget);

      await _settleDown(tester);
    });

    testWidgets('切换表扬/批评后，新增原因写入对应分组', (tester) async {
      final p = AppDataProvider();
      final praiseFirst =
          (p.appData.reasons.praise['_common'] ?? const <String>[]).first;
      await _pumpDialog(tester, p, const ReasonManageDialog());

      // 切到批评：列表不再显示表扬分组的内容。
      await tester.tap(find.text('批评'));
      await tester.pump();
      expect(find.text(praiseFirst), findsNothing);

      // 批评组里新增 → 只进批评库，不进表扬库。
      await tester.enterText(find.byType(TextField), '测试原因丙');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(
        (p.appData.reasons.criticism['_common'] ?? const <String>[]),
        contains('测试原因丙'),
      );
      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        isNot(contains('测试原因丙')),
      );

      await _settleDown(tester);
    });

    testWidgets('切换时段分组后，标题跟随且新增写入该时段', (tester) async {
      final p = AppDataProvider();
      await _pumpDialog(tester, p, const ReasonManageDialog());

      // 取当前生效的第一个时段（文案动态算，不硬编码，防止时段标签调整时用例失真）。
      final periodKey = effectivePeriods().first['key']!;
      final chipLabel = getTimePeriodShortName(periodKey);

      await tester.tap(find.text(chipLabel));
      await tester.pump();
      expect(find.text('「全时段通用」原因（可拖动排序）'), findsNothing);
      expect(find.text('「$chipLabel」原因（可拖动排序）'), findsOneWidget);

      // 在该时段下新增 → 写进时段专属分组，而不是通用组。
      await tester.enterText(find.byType(TextField), '测试原因丁');
      await tester.tap(find.widgetWithText(ElevatedButton, '新增'));
      await tester.pump();
      expect(
        (p.appData.reasons.praise[periodKey] ?? const <String>[]),
        contains('测试原因丁'),
      );
      expect(
        (p.appData.reasons.praise['_common'] ?? const <String>[]),
        isNot(contains('测试原因丁')),
      );

      await _settleDown(tester);
    });
  });
}
