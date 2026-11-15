// 回归测试：记录列表的"编辑/删除"在关闭密码保护时不能把主页路由弹掉
// （曾导致整个窗口黑屏：未弹密码框却执行了 Navigator.pop）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/history_dialog.dart';
import 'package:class_management_system/widgets/password_prompt_dialog.dart';
import 'package:class_management_system/widgets/record_dialog.dart';
import 'package:class_management_system/widgets/record_list.dart';

import 'test_helpers.dart';

AppDataProvider _provider({required bool withPassword}) {
  final provider = AppDataProvider();
  provider.addRecord('张三', '批评', ['迟到'], 'class', '');
  if (withPassword) {
    provider.setPasswordHash(SecurityService.hashPassword('1234'));
    provider.setPasswordEnabled(true);
  }
  return provider;
}

Widget _wrap(AppDataProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const Text('页面标记'),
              Expanded(
                child: RecordList(records: provider.getTodayRecords()),
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets('无密码时删除记录：不再二次确认，删除后可撤销', (tester) async {
    final provider = _provider(withPassword: false);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pump();
    await tester.pump();

    expect(find.text('确定删除'), findsNothing);
    expect(tester.takeException(), isNull);
    // 关键断言：主页与记录列表没有被 pop 掉
    expect(find.text('页面标记'), findsOneWidget);
    expect(find.byType(RecordList), findsOneWidget);
    expect(provider.getTodayRecords(), isEmpty);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(provider.getTodayRecords(), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('无密码时编辑记录：列表仍在且编辑窗口打开', (tester) async {
    final provider = _provider(withPassword: false);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('页面标记'), findsOneWidget);
    expect(find.byType(RecordDialog), findsOneWidget);
  });

  testWidgets('有密码时删除记录：验密后列表仍在，记录被删除', (tester) async {
    final provider = _provider(withPassword: true);

    await tester.pumpWidget(_wrap(provider));
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
      () => provider.getTodayRecords().isEmpty,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('页面标记'), findsOneWidget);
    expect(find.byType(RecordList), findsOneWidget);
    expect(provider.getTodayRecords(), isEmpty);
    await tester.pump(const Duration(seconds: 3));
    provider.exitManagementMode();
  });

  testWidgets('有密码时删除：取消密码框不会删除记录', (tester) async {
    final provider = _provider(withPassword: true);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pump();
    await tester.pump();
    expect(find.text('确定删除'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(provider.getTodayRecords().length, 1);
    expect(find.byType(RecordList), findsOneWidget);
    provider.exitManagementMode();
  });

  testWidgets('无密码时追加记录：不弹密码框直接进入日期选择', (tester) async {
    final provider = _provider(withPassword: false);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    // 追加入口在历史记录对话框里：这里只验证"无需密码"时不会出现密码输入框
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('V3 追加记录不需要密码，直接进入日期选择', (tester) async {
    final provider = _provider(withPassword: true);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();

    await tester.tap(find.text('历史记录'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HistoryDialog), findsOneWidget);

    await tester.tap(find.text('追加记录'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PasswordPromptDialog), findsNothing);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.byType(HistoryDialog), findsOneWidget);
  });

  // ── PasswordInputDialog：控制器生命期（V2.27.7）────────────────────────────
  //
  // 背景：此前三处密码框是"外部建 controller → await showDialog → 外部 dispose"，
  // 而 await 在路由 pop 时立刻返回、退场动画还要跑约 200ms；若这期间主题/
  // MediaQuery 变化触发路由子树重建，TextField 会用到已 dispose 的 controller。
  // 现在 controller 由弹窗自身 State 持有，释放时机与路由子树严格对齐。
  //
  // 下面两条用例把"关闭后仍发生重建"这个场景**真的演一遍**（改主题触发重建），
  // 并断言全程无异常。若把 controller 的持有方式改回外部 dispose，这里会红。

  testWidgets('密码框：关闭后在退场动画期间重建主题，不抛异常', (tester) async {
    String? result;

    await tester.pumpWidget(
      testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await PasswordInputDialog.ask(context, message: '请输入密码');
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(PasswordInputDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.tap(find.text('确认'));
    // 关闭后只推进一帧：此时路由正在退场，子树可能还在参与重建。
    await tester.pump();
    expect(result, 'abcd', reason: '确认应回传输入内容');

    // 关键：在退场动画还没跑完时切换主题，强制路由子树重建。
    await tester.pumpWidget(
      testApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await PasswordInputDialog.ask(context, message: '请输入密码');
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.takeException(),
      isNull,
      reason: '退场期间重建不应因 controller 已释放而报错',
    );
  });

  testWidgets('密码框：取消返回 null，且重复打开不会串上一次的输入', (tester) async {
    final results = <String?>[];

    await tester.pumpWidget(
      testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  results.add(
                    await PasswordInputDialog.ask(context, message: '请输入密码'),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    // 第一次：输入后取消 → null
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '第一次');
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(results.last, isNull, reason: '取消应返回 null');

    // 第二次：直接确定 → 应为空字符串（不能残留上一次的"第一次"）
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('第一次'),
      findsNothing,
      reason: '每次打开都应是全新的空输入框，不能串上一次的内容',
    );
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(results.last, '');

    expect(tester.takeException(), isNull);
  });
}
