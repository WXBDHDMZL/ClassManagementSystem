/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.11.0
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 统一本地存储布局：所有程序内部文件都放在文档目录下的「班级管理系统」文件夹内。
///
/// 布局：
/// ```
/// 文档/班级管理系统/
///   class_management_data.enc
///   class_management_data.enc.bak
///   class_management_auth_guard.json
///   备份/                      自动备份
///   日志/                      操作日志、错误日志
/// ```
class LocalStoragePaths {
  LocalStoragePaths._();

  static const String rootFolderName = '班级管理系统';
  static const String backupFolderName = '备份';
  static const String logFolderName = '日志';
  static const String dataFileName = 'class_management_data.enc';
  static const String authGuardFileName = 'class_management_auth_guard.json';

  static Future<Directory> _documents({String? documentsDirectory}) async {
    if (documentsDirectory != null && documentsDirectory.isNotEmpty) {
      return Directory(documentsDirectory);
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<Directory> root({String? documentsDirectory}) async {
    final docs = await _documents(documentsDirectory: documentsDirectory);
    return Directory('${docs.path}${Platform.pathSeparator}$rootFolderName');
  }

  static Future<Directory> ensureRoot({String? documentsDirectory}) async {
    final dir = await root(documentsDirectory: documentsDirectory);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _subdirectory(
    String name, {
    String? documentsDirectory,
    bool create = false,
  }) async {
    final docs = await _documents(documentsDirectory: documentsDirectory);
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}$rootFolderName'
      '${Platform.pathSeparator}$name',
    );
    if (create && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> backupDirectory({
    String? documentsDirectory,
    bool create = false,
  }) => _subdirectory(
    backupFolderName,
    documentsDirectory: documentsDirectory,
    create: create,
  );

  static Future<Directory> logDirectory({
    String? documentsDirectory,
    bool create = false,
  }) => _subdirectory(
    logFolderName,
    documentsDirectory: documentsDirectory,
    create: create,
  );

  static Future<File> dataFile({String? documentsDirectory}) async {
    final dir = await root(documentsDirectory: documentsDirectory);
    return File('${dir.path}${Platform.pathSeparator}$dataFileName');
  }

  /// V3.7.x：旧版直接放在文档根目录的数据文件。
  ///
  /// 仅用于升级时一次性只读检测/复制；新版本不会继续使用旧位置。
  static Future<File> legacyDataFile({String? documentsDirectory}) async {
    final docs = await _documents(documentsDirectory: documentsDirectory);
    return File('${docs.path}${Platform.pathSeparator}$dataFileName');
  }

  static Future<File> legacyBackupFile({String? documentsDirectory}) async {
    final docs = await _documents(documentsDirectory: documentsDirectory);
    return File(
      '${docs.path}${Platform.pathSeparator}$dataFileName.bak',
    );
  }

  static Future<File> authGuardFile({String? documentsDirectory}) async {
    final dir = await root(documentsDirectory: documentsDirectory);
    return File('${dir.path}${Platform.pathSeparator}$authGuardFileName');
  }
}
