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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/storage_crypto.dart';
import 'package:class_management_system/services/storage_service.dart';

void main() {
  final storage = StorageService();

  test('主程序读到 LRX2 数据时暂停写入，不隔离也不覆盖', () async {
    final dataPath = await storage.dataFilePath;
    final file = File(dataPath);
    await file.parent.create(recursive: true);
    // 只需魔数即可触发旧格式分支；无需构造完整 HMAC。
    final legacy = base64Encode([
      ...StorageCrypto.magicV2,
      ...List<int>.filled(64, 0),
    ]);
    await file.writeAsString(legacy);

    final result = await storage.loadData();
    expect(result.unsupportedFormat, isTrue);
    expect(result.loadFailed, isFalse);
    expect(result.data.students, isEmpty);
    expect(await file.readAsString(), legacy);
    expect(await storage.saveData(result.data), isFalse);
  });

  test('V3 主文件 + V2 备份且缺钥时明确拒绝旧格式', () async {
    final dataPath = await storage.dataFilePath;
    final keyFile = File('$dataPath.key');
    final mainFile = File(dataPath);
    final backupFile = File('$dataPath.bak');
    await mainFile.parent.create(recursive: true);
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final encrypted = StorageCrypto.encodeV3('{"students":[]}', key);
    await mainFile.writeAsString(encrypted);
    // 只需 LRX2 魔数即可触发旧格式识别。
    await backupFile.writeAsString(
      base64Encode([
        ...StorageCrypto.magicV2,
        ...List<int>.filled(64, 0),
      ]),
    );
    if (await keyFile.exists()) await keyFile.delete();

    final previousOverride = StorageService.debugDataKeyOverride;
    StorageService.debugDataKeyOverride = null;
    StorageService.debugResetKey();
    try {
      await expectLater(
        StorageService.initializeKey(),
        throwsA(isA<UnsupportedStorageFormatException>()),
      );
      expect(await keyFile.exists(), isFalse);
      expect(await mainFile.readAsString(), encrypted);
    } finally {
      StorageService.debugDataKeyOverride = previousOverride;
      StorageService.debugResetKey();
    }
  });

  test('LRX3 数据缺少密钥时暂停写入，不生成新钥也不覆盖', () async {
    final dataPath = await storage.dataFilePath;
    final keyFile = File('$dataPath.key');
    final file = File(dataPath);
    await file.parent.create(recursive: true);
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final encrypted = StorageCrypto.encodeV3('{"students":[]}', key);
    await file.writeAsString(encrypted);
    if (await keyFile.exists()) await keyFile.delete();

    final previousOverride = StorageService.debugDataKeyOverride;
    StorageService.debugDataKeyOverride = null;
    StorageService.debugResetKey();
    try {
      final result = await storage.loadData();
      expect(result.keyUnavailable, isTrue);
      expect(result.loadFailed, isFalse);
      expect(result.data.students, isEmpty);
      expect(await file.readAsString(), encrypted);
      expect(await keyFile.exists(), isFalse);
      expect(await storage.saveData(result.data), isFalse);
    } finally {
      StorageService.debugDataKeyOverride = previousOverride;
      StorageService.debugResetKey();
    }
  });
}
