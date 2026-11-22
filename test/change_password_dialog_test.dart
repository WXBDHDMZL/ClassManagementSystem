// 修改管理密码对话框测试：错误当前密码被拒绝；流程正确时密码哈希被更新。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/change_password_dialog.dart';

import 'test_helpers.dart';

Future<AppDataProvider> _pumpDialog(
  WidgetTester tester, {
  required String storedPassword,
}) async {
  final provider = AppDataProvider();
  provider.setPasswordEnabled(true);
  provider.setPasswordHash(SecurityService.hashPassword(storedPassword));
  await tester.pumpWidget(
    ChangeNotifierProvider<AppDataProvider>.value(
      value: provider,
      child: testApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ChangePasswordDialog.show(context),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return provider;
}

Future<void> _enter(WidgetTester tester, int index, String text) async {
  await tester.enterText(find.byType(TextField).at(index), text);
}

/// 等提示框的 2 秒自动关闭定时器跑完，避免测试结束时仍有挂起任务。
Future<void> _settleSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('当前密码错误：提示且不修改密码', (tester) async {
    final provider = await _pumpDialog(tester, storedPassword: 'abcd1234');
    final originalHash = provider.appData.settings.passwordHash;

    await _enter(tester, 0, '错误密码');
    await _enter(tester, 1, 'newpass123');
    await _enter(tester, 2, 'newpass123');
    await tester.tap(find.text('确定修改'));
    // 性能批 M6：密码校验走后台 isolate，需交替推进真实事件循环与假异步队列。
    await pumpUntilRealAsync(
      tester,
      () => find.text('当前密码错误').evaluate().isNotEmpty,
    );

    expect(find.text('当前密码错误'), findsOneWidget);
    expect(provider.appData.settings.passwordHash, originalHash);
    await _settleSnackBar(tester);
  });

  testWidgets('新密码不符合规则：提示且不修改密码', (tester) async {
    final provider = await _pumpDialog(tester, storedPassword: 'abcd1234');

    await _enter(tester, 0, 'abcd1234');
    await _enter(tester, 1, 'abc');
    await _enter(tester, 2, 'abc');
    await tester.tap(find.text('确定修改'));
    await pumpUntilRealAsync(
      tester,
      () => find.text('新密码需为 6-20 位').evaluate().isNotEmpty,
    );

    expect(find.text('新密码需为 6-20 位'), findsOneWidget);
    // V2.30.2：新哈希带随机盐，哈希串之间不可比较——断言"旧密码仍能校验通过"。
    expect(
      SecurityService.verifyPassword(
        'abcd1234',
        storedHash: provider.appData.settings.passwordHash,
      ),
      isTrue,
      reason: '校验失败时不应修改密码',
    );
    await _settleSnackBar(tester);
  });

  testWidgets('修改成功：提示并保存新密码哈希', (tester) async {
    final provider = await _pumpDialog(tester, storedPassword: 'abcd1234');

    await _enter(tester, 0, 'abcd1234');
    await _enter(tester, 1, 'xyz9876');
    await _enter(tester, 2, 'xyz9876');
    await tester.tap(find.text('确定修改'));
    // 成功路径要连续跑三次后台计算：验当前密码 → 验"新旧不同" → 生成新哈希。
    await pumpUntilRealAsync(
      tester,
      () => find.text('管理密码已修改').evaluate().isNotEmpty,
    );

    expect(find.text('管理密码已修改'), findsOneWidget);
    // V2.30.2：带盐哈希不可比，直接断言新密码可校验通过。
    expect(
      SecurityService.verifyPassword(
        'xyz9876',
        storedHash: provider.appData.settings.passwordHash,
      ),
      isTrue,
      reason: '修改成功应当保存用户输入的新密码',
    );
    // 新密码可用、旧密码失效
    expect(
      SecurityService.verifyPassword(
        'xyz9876',
        storedHash: provider.appData.settings.passwordHash,
      ),
      isTrue,
    );
    expect(
      SecurityService.verifyPassword(
        'abcd1234',
        storedHash: provider.appData.settings.passwordHash,
      ),
      isFalse,
    );
    await _settleSnackBar(tester);
  });
}
