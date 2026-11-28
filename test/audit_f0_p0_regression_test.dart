/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.7
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';
import 'package:class_management_system/services/github_update_service.dart';
import 'package:class_management_system/services/transfer_service.dart';
import 'package:class_management_system/widgets/update_available_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧数据包缺少必备字段时必须整包拒绝', () {
    final raw = jsonEncode(<String, Object?>{
      'format': TransferService.packageFormat,
      'version': TransferService.packageVersion,
      'records': <Object?>[],
      'students': <String>[],
    });

    // V5.0.0 只接受 version=2 且字段齐全的数据包。
    expect(TransferService.parsePackage(raw), isNull);
  });

  testWidgets('更新弹窗渲染 Release Notes 的版本内容', (tester) async {
    final release = GitHubReleaseInfo(
      tagName: 'v4.14.0',
      title: 'V4.14.0',
      notes: '## 主要变化\n\n'
          '- 此前会出现记录消失的问题，现在改为按归属日保存。\n'
          '- 旧数据无需迁移。',
      assets: <GitHubAsset>[
        GitHubAsset(
          name: 'ClassManagementSystem_Setup_v4.14.0.exe',
          downloadUrl: Uri.parse(
            'https://github.com/WXBDHDMZL/ClassManagementSystem/'
            'releases/download/v4.14.0/ClassManagementSystem_Setup_v4.14.0.exe',
          ),
          size: 1024,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await showUpdateAvailableDialog(context, release: release);
                },
                child: const Text('打开更新提示'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开更新提示'));
    await tester.pumpAndSettle();

    expect(find.text('版本内容'), findsOneWidget);
    expect(find.textContaining('此前会出现'), findsOneWidget);
    expect(find.textContaining('旧数据无需迁移'), findsOneWidget);
  });

  test('未授权时不得改写管理密码哈希', () {
    AuthService.resetForTest();
    final provider = AppDataProvider();
    provider.appData.settings = provider.appData.settings.copyWith(
      passwordEnabled: true,
      passwordHash: 'old-hash',
    );

    provider.setPasswordHash('new-hash');

    expect(
      provider.appData.settings.passwordHash,
      'old-hash',
      reason: '没有管理授权时，setPasswordHash 不能直接改写密码。',
    );
  });
}
