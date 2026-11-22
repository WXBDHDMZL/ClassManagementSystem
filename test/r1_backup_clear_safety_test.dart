/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.1
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  AppDataProvider? provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    provider = null;
    tempDir = createStorageTestRoot('cms_backup_clear_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tempDir.parent.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await flushWrites(provider);
    await deleteStorageTestRoot(tempDir);
  });

  test('备份目录等于数据目录时，清除全部备份不会删主数据或陌生 .enc', () async {
    final p = AppDataProvider();
    provider = p;
    p.setBackupPath(tempDir.path);

    final main = File('${tempDir.path}/class_management_data.enc')
      ..writeAsStringSync('main-data');
    final foreign = File('${tempDir.path}/other_app.enc')
      ..writeAsStringSync('foreign');
    final backup = File('${tempDir.path}/班级管理系统_备份_20260101_120000.enc')
      ..writeAsStringSync('backup');

    final removed = await p.clearAllBackups();

    expect(removed, 1);
    expect(await main.exists(), isTrue, reason: '主数据文件不能被当成备份删除');
    expect(await foreign.exists(), isTrue, reason: '陌生 .enc 不能被误删');
    expect(await backup.exists(), isFalse, reason: '本程序备份应被清理');
  });
}
