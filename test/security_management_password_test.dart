// 回归：在安全页修改统一管理密码。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/settings_pages.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('可修改统一管理密码', (tester) async {
    final hash = SecurityService.hashPassword('headpass123');
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(AppData(
      recordsByDate: const {},
      settings: AppSettings.fromJson({
        'themeMode': 0,
        'passwordEnabled': true,
        'passwordHash': hash,
      }),
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: testApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: SecuritySettingsPage()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('修改管理密码'), findsOneWidget);
    await tester.tap(find.text('修改管理密码'));
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, '当前管理密码'),
      'headpass123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '新密码（6-20 位）'),
      'newpass123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '确认新密码'),
      'newpass123',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '确定修改'));
    await pumpUntilRealAsync(
      tester,
      () => find.text('管理密码已修改').evaluate().isNotEmpty,
    );

    final settings = provider.appData.settings;
    expect(settings.passwordEnabled, isTrue);
    expect(settings.passwordHash, isNotEmpty);
    expect(
      SecurityService.verifyPassword(
        'newpass123',
        storedHash: settings.passwordHash,
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 3));
  });
}
