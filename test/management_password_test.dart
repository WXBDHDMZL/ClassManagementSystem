// 单管理密码回归：统一字段与失败锁定。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/services/auth_service.dart';
import 'package:class_management_system/services/local_storage_paths.dart';
import 'package:class_management_system/services/security_service.dart';

void main() {
  setUp(AuthService.resetForTest);
  tearDown(AuthService.resetForTest);

  test('统一管理密码验证成功，只使用 passwordHash', () async {
    final hash = SecurityService.hashPassword('abcd1234');
    final settings = AppSettings.fromJson({
      'themeMode': 0,
      'passwordEnabled': true,
      'passwordHash': hash,
    });

    expect(settings.passwordHash, hash);
    expect(settings.passwordEnabled, isTrue);
    expect(
      (await AuthService.verify(
        settings,
        AuthCredential.operation,
        'abcd1234',
      )).success,
      isTrue,
    );
  });

  test('旧版多余密码字段不会参与运行', () {
    final settings = AppSettings.fromJson(const {
      'themeMode': 0,
      'passwordEnabled': true,
      'passwordHash': 'current-hash',
      'headTeacherPasswordHash': 'legacy-head-hash',
      'passwordRelationMode': 1,
      'passwordForRecords': false,
      'passwordActions': ['recordDelete'],
    });

    expect(settings.passwordHash, 'current-hash');
    expect(settings.passwordEnabled, isTrue);
    expect(settings.toJson().containsKey('headTeacherPasswordHash'), isFalse);
    expect(settings.toJson().containsKey('passwordRelationMode'), isFalse);
    expect(settings.toJson().containsKey('passwordForRecords'), isFalse);
    expect(settings.toJson().containsKey('passwordActions'), isFalse);
  });

  test('连续错误 5 次后锁定，正确密码也暂时被拒绝；重置后恢复', () async {
    final hash = SecurityService.hashPassword('abcd1234');
    final settings = AppSettings.fromJson({
      'themeMode': 0,
      'passwordEnabled': true,
      'passwordHash': hash,
    });

    for (var i = 0; i < 4; i++) {
      expect(
        (await AuthService.verify(
          settings,
          AuthCredential.operation,
          '错误',
        )).success,
        isFalse,
      );
    }
    final locked = await AuthService.verify(
      settings,
      AuthCredential.operation,
      '错误',
    );
    expect(locked.locked, isTrue);
    expect(locked.remainingSeconds, greaterThan(0));
    expect(
      (await AuthService.verify(
        settings,
        AuthCredential.operation,
        'abcd1234',
      )).success,
      isFalse,
    );

    // 完整重置 = 清内存 + 清落盘状态。
    // `resetForTest()` 只清内存（batch6 用它模拟“重启后仍锁定”），锁定状态
    // 现在会真正落盘，因此这里必须同时删掉状态文件，否则读回来的仍是锁定期。
    final guardFile = await LocalStoragePaths.authGuardFile();
    if (await guardFile.exists()) await guardFile.delete();
    AuthService.resetForTest();
    expect(
      (await AuthService.verify(
        settings,
        AuthCredential.operation,
        'abcd1234',
      )).success,
      isTrue,
    );
  });

  test('审计 P3：并发提交错误密码也逐个计数，第 5 次立即锁定', () async {
    // 旧实现把"读失败计数 → +1 → 写回"放在 PBKDF2 await 之后，5 个并发请求
    // 都读到同一个旧值、都写回 1，锁定阈值被完全绕过（10 次并发只记 1 次）。
    // 现在改为 await 之前同步登记，因此并发也必须计数。
    final hash = SecurityService.hashPassword('abcd1234');
    final settings = AppSettings.fromJson({
      'themeMode': 0,
      'passwordEnabled': true,
      'passwordHash': hash,
    });
    addTearDown(() async {
      final guardFile = await LocalStoragePaths.authGuardFile();
      if (await guardFile.exists()) await guardFile.delete();
    });

    final results = await Future.wait([
      for (var i = 0; i < AuthService.maxFailuresBeforeLock; i++)
        AuthService.verify(settings, AuthCredential.operation, '错误'),
    ]);

    expect(
      results.where((result) => result.locked),
      isNotEmpty,
      reason: '并发错误达到阈值必须触发锁定，而不是各自只记 1 次',
    );
    expect(AuthService.lockRemaining(AuthCredential.operation), isNotNull);
    expect(
      (await AuthService.verify(
        settings,
        AuthCredential.operation,
        'abcd1234',
      )).success,
      isFalse,
      reason: '锁定期间正确密码同样应被拒绝',
    );
  });
}
