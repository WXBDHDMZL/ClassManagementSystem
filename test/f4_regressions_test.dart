import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/password_policy.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/auth_service.dart';
import 'package:class_management_system/services/github_update_service.dart';
import 'package:class_management_system/services/security_service.dart';

import 'test_bootstrap.dart';

void main() {
  setUp(() {
    AuthService.resetForTest();
  });

  tearDown(() {
    AuthService.resetForTest();
  });

  test('Excel 导出属于班主任管理动作', () {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings.defaultSettings().copyWith(passwordEnabled: true),
      ),
    );

    expect(provider.actionRequiresManagement(PasswordAction.recordExport), isTrue);
    expect(
      provider.actionRequiresManagement(PasswordAction.recordAddSingle),
      isFalse,
    );
  });

  test('恢复码重置在 provider 层再次校验，错误码不改密码', () async {
    final docsDir = createTestDocumentsDir('cms_f4_recovery_');
    installTestPathProvider(docsDir);
    addTearDown(() async {
      uninstallTestPathProvider();
      await deleteTestDocumentsDir(docsDir);
    });

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
    AuthService.grantManagement(const Duration(minutes: 1));
    await provider.setRecoveryCode(code);
    AuthService.clearManagementGrant();

    final before = provider.appData.settings.passwordHash;
    final rejected = await provider.resetPasswordsWithRecoveryCode(
      'newpass123',
      recoveryCode: 'WRONG-CODE',
    );
    expect(rejected, isFalse);
    expect(provider.appData.settings.passwordHash, before);

    final accepted = await provider.resetPasswordsWithRecoveryCode(
      'newpass123',
      recoveryCode: code,
    );
    expect(accepted, isTrue);
    expect(provider.appData.settings.recoveryCodeEnabled, isFalse);
  });

  test('更新包签名校验：正确签名通过，篡改或错误公钥拒绝', () async {
    final temp = await Directory.systemTemp.createTemp('cms_f4_sig_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/setup.exe');
    await file.writeAsBytes(List<int>.generate(4096, (i) => i % 251));

    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final digest = await sha256.bind(file.openRead()).first;
    final signature = await algorithm.sign(digest.bytes, keyPair: keyPair);
    final publicB64 = base64Encode(publicKey.bytes);
    final signatureB64 = base64Encode(signature.bytes);

    expect(
      await GitHubUpdateService.verifyFileSignature(
        file,
        signatureB64,
        publicKeyBase64: publicB64,
      ),
      isTrue,
    );

    await file.writeAsString('tampered', mode: FileMode.append);
    expect(
      await GitHubUpdateService.verifyFileSignature(
        file,
        signatureB64,
        publicKeyBase64: publicB64,
      ),
      isFalse,
    );

    final otherKey = await algorithm.newKeyPair();
    final otherPublic = await otherKey.extractPublicKey();
    expect(
      await GitHubUpdateService.verifyFileSignature(
        file,
        signatureB64,
        publicKeyBase64: base64Encode(otherPublic.bytes),
      ),
      isFalse,
    );
  });
}
