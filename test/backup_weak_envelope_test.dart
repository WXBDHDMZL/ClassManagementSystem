/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-28
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/services/backup_crypto.dart';
import 'package:class_management_system/services/error_log_service.dart';
import 'package:class_management_system/services/storage_crypto.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  final localKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  const password = 'StrongPass123!';

  setUp(() {
    StorageService.debugResetKey();
    StorageService.debugDataKeyOverride = localKey;
  });

  tearDown(() async {
    await flushErrorLogs();
    StorageService.debugResetKey();
    StorageService.debugDataKeyOverride = localKey;
  });

  test('A-20 旧版本写出的弱信封仍能恢复，并在错误日志里留警告', () async {
    final tempDir = createStorageTestRoot('cms_weak_envelope');
    addTearDown(() => deleteStorageTestRoot(tempDir));

    final storage = StorageService();
    await StorageService.initializeKey();
    final loaded = await storage.loadData();
    expect(loaded.loadFailed, isFalse);

    // 造一份"旧版本"便携备份：数据密钥 32 字节，但信封只有 1 万轮。
    final portableKey = Uint8List.fromList(List<int>.filled(32, 0x24));
    final data = AppData.empty();
    final cipher = StorageCrypto.encodeV3(jsonEncode(data.toJson()), portableKey);

    final backupPath = '${tempDir.path}/old_portable.enc';
    await File(backupPath).writeAsString(cipher);
    await File('$backupPath.pkey').writeAsString(
      BackupCrypto.wrapKeyForTest(
        portableKey,
        password,
        rounds: BackupCrypto.minIterations,
      ),
    );

    final error = await storage.restoreFrom(backupPath, backupPassword: password);
    expect(error, isNull, reason: 'A-20：弱信封是合法旧备份，不能拒绝恢复');

    await flushErrorLogs();
    final log = await exportErrorLogText();
    expect(
      log,
      contains('密钥派生强度低于当前标准'),
      reason: 'A-20：强度偏低要在日志里留痕，便于排障时判断备份来源',
    );
  });
}
