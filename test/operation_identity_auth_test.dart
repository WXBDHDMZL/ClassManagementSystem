// V3 身份选择：记录人只做署名，不再要求旧独立密码。
// 旧版“班主任身份需要密码”的行为已删除。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/identity_picker_dialog.dart';

Widget _wrap(AppDataProvider provider) => ChangeNotifierProvider<
      AppDataProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: IdentityPickerDialog()),
      ),
    );

void main() {
  testWidgets('有管理密码时，选择班主任操作身份会要求验证', (tester) async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    await provider.setPasswordHash(SecurityService.hashPassword('1234'));
    provider.setPasswordEnabled(true);
    provider.setIdentityFeatureEnabled(true);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();
    await tester.tap(find.text('班主任'));
    await tester.pump();
    await tester.pump();

    expect(find.text('请输入管理密码'), findsOneWidget);
    expect(provider.activeIdentity, isNull);
    provider.clearActiveIdentity();
  });

  testWidgets('无密码时选择班主任记录人直接生效', (tester) async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.setIdentityFeatureEnabled(true);

    await tester.pumpWidget(_wrap(provider));
    await tester.pump();
    await tester.tap(find.text('班主任'));
    await tester.pump();

    expect(provider.activeIdentity?.isHeadTeacher, isTrue);
    expect(provider.isManagementMode, isTrue);
    provider.exitManagementMode();
    provider.clearActiveIdentity();
  });
}
