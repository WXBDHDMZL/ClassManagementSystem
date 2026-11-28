// 安全页敏感动作的二次验证：关闭管理密码、生成恢复码、
// 恢复码在管理会话结束后自动关闭。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/settings_pages.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: SecuritySettingsPage()),
        ),
      ),
    );

Future<AppDataProvider> _pumpPage(WidgetTester tester) async {
  final provider = AppDataProvider();
  await provider.setPasswordHash(SecurityService.hashPassword('1234'));
  provider.setPasswordEnabled(true);
  await tester.pumpWidget(_wrap(provider));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return provider;
}

Future<void> _enterPassword(WidgetTester tester) async {
  expect(find.text('请输入管理密码'), findsOneWidget);
  await tester.enterText(find.byType(TextField), '1234');
  await tester.tap(find.text('确认'));
  await tester.pump();
}

void main() {
  testWidgets('关闭管理密码：取消二次验证不会关闭，验证成功才关闭', (tester) async {
    final provider = await _pumpPage(tester);

    await tester.tap(find.text('关闭管理密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定关闭'));
    await tester.pumpAndSettle();
    expect(find.text('关闭管理密码前，请再次输入当前管理密码。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(provider.appData.settings.passwordEnabled, isTrue);

    await tester.tap(find.text('关闭管理密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定关闭'));
    await tester.pumpAndSettle();
    await _enterPassword(tester);
    expect(
      await pumpUntilRealAsync(
        tester,
        () => !provider.appData.settings.passwordEnabled,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(provider.appData.settings.passwordEnabled, isFalse);
    expect(find.text('设置管理密码'), findsOneWidget);

    // 等提示条计时器结束，避免测试结束时留下定时器。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('生成恢复码：取消验证不会生成，验证成功才显示一次性恢复码', (tester) async {
    final provider = await _pumpPage(tester);
    // 真实入口一定在管理会话内；恢复码弹窗会拒绝在会话外展示。
    provider.enterManagementMode();
    await tester.pump();

    await tester.tap(find.text('生成恢复码'));
    await tester.pumpAndSettle();
    expect(find.text('生成恢复码前，请再次输入当前管理密码。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(provider.appData.settings.recoveryCodeEnabled, isFalse);

    await tester.tap(find.text('生成恢复码'));
    await tester.pumpAndSettle();
    await _enterPassword(tester);
    expect(
      await pumpUntilRealAsync(
        tester,
        () => find.text('恢复码（只显示一次）').evaluate().isNotEmpty,
      ),
      isTrue,
    );
    // 密码框退场动画可能还没走完，等路由栈稳定后再断言。
    await tester.pumpAndSettle();
    expect(find.text('生成恢复码前，请再次输入当前管理密码。'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(provider.appData.settings.recoveryCodeEnabled, isFalse);

    provider.exitManagementMode();
    await tester.pump();
  });

  testWidgets('恢复码：验证通过但会话已失效时不展示恢复码', (tester) async {
    final provider = await _pumpPage(tester);
    // 不进入管理会话，模拟密码验证通过、但会话在弹窗打开前已失效。
    expect(provider.isManagementMode, isFalse);

    await tester.tap(find.text('生成恢复码'));
    await tester.pumpAndSettle();
    await _enterPassword(tester);
    expect(
      await pumpUntilRealAsync(
        tester,
        () => find.text('管理会话已结束，请重新验证后再生成恢复码。')
            .evaluate()
            .isNotEmpty,
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(find.text('恢复码（只显示一次）'), findsNothing);
    expect(find.text('管理会话已结束，请重新验证后再生成恢复码。'), findsOneWidget);
    expect(provider.appData.settings.recoveryCodeEnabled, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('恢复码弹窗：管理会话结束后自动关闭', (tester) async {
    final provider = await _pumpPage(tester);
    provider.enterManagementMode();
    await tester.pump();

    await tester.tap(find.text('生成恢复码'));
    await tester.pumpAndSettle();
    await _enterPassword(tester);
    expect(
      await pumpUntilRealAsync(
        tester,
        () => find.text('恢复码（只显示一次）').evaluate().isNotEmpty,
      ),
      isTrue,
    );

    provider.exitManagementMode();
    await tester.pumpAndSettle();
    expect(find.text('恢复码（只显示一次）'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
