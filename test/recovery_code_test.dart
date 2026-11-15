/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';
import 'package:class_management_system/services/security_service.dart';

import 'test_bootstrap.dart';

void main() {
  late Directory docsDir;

  setUp(() async {
    docsDir = createTestDocumentsDir('cms_recovery_');
    installTestPathProvider(docsDir);
    AuthService.resetForTest();
    AuthService.debugStorageDirectory = docsDir;
  });

  tearDown(() async {
    AuthService.resetForTest();
    AuthService.debugStorageDirectory = null;
    uninstallTestPathProvider();
    await deleteTestDocumentsDir(docsDir);
  });

  group('恢复码（密码找回）', () {
    test('恢复码生成：分组、字符集、归一化与随机性', () {
      final first = SecurityService.generateRecoveryCode();
      final second = SecurityService.generateRecoveryCode();
      expect(first, isNot(second));
      expect(first.split('-'), hasLength(5));
      for (final part in first.split('-')) {
        expect(part, hasLength(4));
      }
      expect(
        SecurityService.normalizeRecoveryCode(' $first '),
        first.replaceAll('-', ''),
      );
      expect(
        SecurityService.normalizeRecoveryCode(first.toLowerCase()),
        first.replaceAll('-', ''),
      );
      // 不包含易混字符。
      expect(first.contains(RegExp(r'[01OIL]')), isFalse);
    });

    test('恢复码生效后可校验，错误码被拒绝；哈希不含明文', () async {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      final code = SecurityService.generateRecoveryCode();
      await provider.setRecoveryCode(code);
      final settings = provider.appData.settings;

      expect(settings.recoveryCodeEnabled, isTrue);
      expect(settings.recoveryCodeCreatedAt, isNotEmpty);
      expect(settings.recoveryCodeHash, isNot(contains(code)));
      expect(
        settings.recoveryCodeHash,
        isNot(contains(SecurityService.normalizeRecoveryCode(code))),
      );

      final ok = await AuthService.verify(
        settings,
        AuthCredential.recoveryCode,
        SecurityService.normalizeRecoveryCode(code),
      );
      expect(ok.success, isTrue);
      final bad = await AuthService.verify(
        settings,
        AuthCredential.recoveryCode,
        'WRONG-CODE',
      );
      expect(bad.success, isFalse);
    });

    test('重置后管理密码可用、恢复码作废、锁定清零', () async {
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      provider.loadForTest(
        AppData(
          recordsByDate: const {},
          settings: AppSettings.defaultSettings().copyWith(
            passwordEnabled: true,
            passwordHash: SecurityService.hashPassword('oldpass123'),
          ),
        ),
      );
      final code = SecurityService.generateRecoveryCode();
      await provider.setRecoveryCode(code);

      // 先制造锁定状态，确认重置后能正常验证。
      for (var i = 0; i < 5; i++) {
        await AuthService.verify(
          provider.appData.settings,
          AuthCredential.operation,
          '错误密码',
        );
      }
      final locked = await AuthService.verify(
        provider.appData.settings,
        AuthCredential.operation,
        '新密码123',
      );
      expect(locked.locked, isTrue);

      final saved = await provider.resetPasswordsWithRecoveryCode('新密码123');
      expect(saved, isTrue);
      final settings = provider.appData.settings;
      expect(settings.passwordEnabled, isTrue);
      expect(settings.recoveryCodeEnabled, isFalse, reason: '恢复码一次性');
      expect(
        (await AuthService.verify(
          settings,
          AuthCredential.operation,
          '新密码123',
        ))
            .success,
        isTrue,
        reason: '重置后原锁定应被清除',
      );
    });

    test('恢复码字段可持久化；旧数据默认未设置', () {
      final settings = AppSettings.fromJson(const {});
      expect(settings.recoveryCodeEnabled, isFalse);
      final json = settings.copyWith(
        recoveryCodeHash: 'p2:100000:abc:def',
        recoveryCodeCreatedAt: '2026-10-24',
      ).toJson();
      expect(json['recoveryCodeHash'], 'p2:100000:abc:def');
      expect(json['recoveryCodeCreatedAt'], '2026-10-24');
    });
  });
}
