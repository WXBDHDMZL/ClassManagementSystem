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

import 'package:class_management_system/services/local_storage_paths.dart';

void main() {
  late Directory docs;
  String norm(String path) => path.replaceAll('\\', '/');

  setUp(() {
    docs = Directory.systemTemp.createTempSync('cms_layout_');
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  test('固定布局：数据/日志/备份都在「班级管理系统」下', () async {
    expect(
      norm((await LocalStoragePaths.dataFile(documentsDirectory: docs.path)).path),
      norm('${docs.path}/班级管理系统/class_management_data.enc'),
    );
    expect(
      norm((await LocalStoragePaths.authGuardFile(documentsDirectory: docs.path))
          .path),
      norm('${docs.path}/班级管理系统/class_management_auth_guard.json'),
    );
    expect(
      norm((await LocalStoragePaths.logDirectory(documentsDirectory: docs.path))
          .path),
      norm('${docs.path}/班级管理系统/日志'),
    );
    expect(
      norm((await LocalStoragePaths.backupDirectory(
        documentsDirectory: docs.path,
      ))
          .path),
      norm('${docs.path}/班级管理系统/备份'),
    );
  });

  test('ensureRoot 与目录创建：按需创建，不碰旧文档根目录', () async {
    final root = await LocalStoragePaths.ensureRoot(documentsDirectory: docs.path);
    expect(await root.exists(), isTrue);
    expect(norm(root.path), norm('${docs.path}/班级管理系统'));

    final backup = await LocalStoragePaths.backupDirectory(
      documentsDirectory: docs.path,
      create: true,
    );
    expect(await backup.exists(), isTrue);
    expect(
      await Directory('${docs.path}/班级管理系统_备份').exists(),
      isFalse,
      reason: '不再创建或回退旧版备份目录',
    );
  });
}
