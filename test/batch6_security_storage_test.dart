// Batch 6 回归：隔离失败时禁止覆盖、密码锁定跨重启持久化。
//
// 背景（历史缺陷记录）：
//  - B-20 损坏主文件“隔离失败”分支无法稳定复现，保存是否被正确拒绝缺少测试；
//  - B-23 连续输错后的锁定只在内存，重启即可继续尝试。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/services/auth_service.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late String mainPath;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_batch6');
    mainPath = '${tempDir.path}/class_management_data.enc';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
  });

  tearDown(() async {
    StorageService.debugIsolateOverride = null;
    AuthService.debugStorageDirectory = null;
    AuthService.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteStorageTestRoot(tempDir);
  });

  test('B-20 隔离失败：主文件保留，后续保存被拒且不覆盖内容', () async {
    final file = File(mainPath);
    await file.writeAsString('这不是本程序的数据');
    final before = await file.readAsString();

    StorageService.debugIsolateOverride =
        (source, target) async => throw const FileSystemException('被占用');

    final storage = StorageService();
    final result = await storage.loadData();
    expect(result.resetToEmpty, isTrue);
    expect(await file.exists(), isTrue, reason: '隔离失败时不能删除原文件');
    expect(await file.readAsString(), before);

    final saved = await storage.saveData(AppData.empty());
    expect(saved, isFalse, reason: '损坏文件未隔离成功前必须拒绝保存');
    expect(await file.readAsString(), before, reason: '主文件不能被空数据覆盖');
  });

  test('B-23 连续失败锁定：重启（重置内存）后仍处于锁定期', () async {
    AuthService.debugStorageDirectory = tempDir;
    AuthService.resetForTest();
    final settings = AppSettings(
      themeMode: ThemeModeType.system,
      passwordEnabled: true,
      passwordHash: SecurityService.hashPassword('abcd1234'),
    );

    for (var i = 0; i < 4; i++) {
      final result = await AuthService.verify(
        settings,
        AuthCredential.operation,
        '错误密码',
      );
      expect(result.locked, isFalse);
    }
    final fifth = await AuthService.verify(
      settings,
      AuthCredential.operation,
      '错误密码',
    );
    expect(fifth.locked, isTrue);

    // 模拟重启：清空内存，但保留落盘状态文件。
    AuthService.resetForTest();
    final afterRestart = await AuthService.verify(
      settings,
      AuthCredential.operation,
      'abcd1234',
    );
    expect(afterRestart.locked, isTrue, reason: '重启后不能绕过锁定');
    expect(afterRestart.success, isFalse);

    final stateFile = File('${tempDir.path}/class_management_auth_guard.json');
    expect(await stateFile.exists(), isTrue, reason: '锁定状态应落盘');
    final raw = await stateFile.readAsString();
    expect(
      raw,
      isNot(contains('failures')),
      reason: '锁定状态文件也必须加密，不能留明文 JSON',
    );
  });
}
