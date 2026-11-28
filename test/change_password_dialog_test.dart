// 修改管理密码对话框测试：错误当前密码被拒绝；流程正确时密码哈希被更新。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/change_password_dialog.dart';

import 'test_helpers.dart';

/// 落盘成功的桩：widget 测试跑在 FakeAsync 下，真实文件 IO 的完成回调
/// 送不回来会让整测试挂死，所以对话框测试只验"等结果再提示"的时序，
/// 真实持久化由本文件末尾的 provider 级用例覆盖。
class _SavingProvider extends AppDataProvider {
  @override
  Future<bool> saveNow() async => true;
}

/// 落盘失败的 provider：模拟磁盘不可写时改密码的反馈（审计 A-19）。
class _UnwritableProvider extends AppDataProvider {
  @override
  Future<bool> saveNow() async => false;
}

Future<AppDataProvider> _pumpDialog(
  WidgetTester tester, {
  required String storedPassword,
  AppDataProvider? override,
}) async {
  final provider = override ?? _SavingProvider();
  await tester.runAsync(() async {
    provider.setPasswordEnabled(true);
    await provider.setPasswordHash(
      SecurityService.hashPassword(storedPassword),
    );
  });
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

  testWidgets('落盘失败：明确提示写入失败，不谎报修改成功', (tester) async {
    // 审计 A-19：密码改动落盘失败时，界面必须报错而不是"已修改"。
    final provider = await _pumpDialog(
      tester,
      storedPassword: 'abcd1234',
      override: _UnwritableProvider(),
    );

    await _enter(tester, 0, 'abcd1234');
    await _enter(tester, 1, 'xyz9876');
    await _enter(tester, 2, 'xyz9876');
    await tester.tap(find.text('确定修改'));
    await pumpUntilRealAsync(
      tester,
      () => find.textContaining('写入磁盘失败').evaluate().isNotEmpty,
    );

    expect(find.textContaining('写入磁盘失败'), findsOneWidget);
    expect(find.text('管理密码已修改'), findsNothing);
    expect(provider.appData.settings.passwordHash, isNotEmpty);
    await _settleSnackBar(tester);
  });

  test('落盘成功：重新加载后新密码仍然有效（真实临时数据目录）', () async {
    final tempDir = createStorageTestRoot('cms_password_persist');
    addTearDown(() => deleteStorageTestRoot(tempDir));

    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    await provider.initialize();
    provider.setPasswordEnabled(true);

    final saved = await provider.setPasswordHash(
      SecurityService.hashPassword('xyz9876'),
    );
    expect(saved, isTrue, reason: 'A-19：落盘成功必须返回 true');
    await flushWrites(provider);

    final reloaded = AppDataProvider();
    addTearDown(reloaded.dispose);
    await reloaded.initialize();
    expect(
      SecurityService.verifyPassword(
        'xyz9876',
        storedHash: reloaded.appData.settings.passwordHash,
      ),
      isTrue,
      reason: 'A-19：改密码必须先落盘，重启后仍应是新密码',
    );
  });

  test('落盘失败：setPasswordHash 返回 false，不谎报成功', () async {
    final provider = _UnwritableProvider();
    addTearDown(provider.dispose);
    provider.setPasswordEnabled(true);

    final saved = await provider.setPasswordHash(
      SecurityService.hashPassword('xyz9876'),
    );
    expect(saved, isFalse, reason: 'A-19：没写进磁盘就不能返回成功');
  });
}
