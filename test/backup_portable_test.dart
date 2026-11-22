/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.7
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/services/storage_service.dart';

void main() {
  final storage = StorageService();
  final initialKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUp(() {
    StorageService.debugResetKey();
    StorageService.debugDataKeyOverride = initialKey;
  });

  tearDown(() {
    StorageService.debugResetKey();
    StorageService.debugDataKeyOverride = initialKey;
  });

  test('便携备份在换钥后仍可恢复', () async {
    final data = AppData(
      recordsByDate: const {},
      settings: AppSettings(themeMode: ThemeModeType.dark),
      students: const ['测试学生'],
    );
    expect(await storage.saveData(data), isTrue);

    final dir = await Directory.systemTemp.createTemp('cms_portable_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final backupPath = '${dir.path}/backup.enc';
    const password = 'StrongPass123!';
    expect(await storage.backupTo(backupPath, password: password), isTrue);
    expect(await File('$backupPath.pkey').exists(), isTrue);

    // 模拟换机：换一份本机密钥后，无法用新钥直接解旧备份。
    StorageService.debugResetKey();
    StorageService.debugDataKeyOverride = Uint8List.fromList(
      List<int>.filled(32, 0x42),
    );

    final error = await storage.restoreFrom(
      backupPath,
      backupPassword: password,
    );
    expect(error, isNull);
    final result = await storage.loadData();
    expect(result.loadFailed, isFalse);
    expect(result.data.students, ['测试学生']);
    expect(result.data.settings.themeMode, ThemeModeType.dark);
  });

  test('便携备份口令错误时拒绝恢复', () async {
    final data = AppData.empty();
    expect(await storage.saveData(data), isTrue);
    final dir = await Directory.systemTemp.createTemp('cms_portable_bad_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final backupPath = '${dir.path}/backup.enc';
    expect(
      await storage.backupTo(backupPath, password: 'StrongPass123!'),
      isTrue,
    );

    final error = await storage.restoreFrom(
      backupPath,
      backupPassword: 'WrongPass123!',
    );
    expect(error, contains('备份口令错误'));
  });

  test('没有口令牌的普通备份仍可按本机密钥恢复', () async {
    final data = AppData(
      recordsByDate: const {},
      settings: AppSettings(themeMode: ThemeModeType.light),
      students: const ['本机学生'],
    );
    expect(await storage.saveData(data), isTrue);
    final dir = await Directory.systemTemp.createTemp('cms_local_backup_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final backupPath = '${dir.path}/backup.enc';
    expect(await storage.backupTo(backupPath), isTrue);
    expect(await File('$backupPath.pkey').exists(), isFalse);

    final error = await storage.restoreFrom(backupPath);
    expect(error, isNull);
    final result = await storage.loadData();
    expect(result.loadFailed, isFalse);
    expect(result.data.students, ['本机学生']);
  });
}
