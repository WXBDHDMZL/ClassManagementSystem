/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

// ignore_for_file: avoid_print
//
// 本机离线恢复工具（方案 B；不进入安装包、不在程序内运行）。
//
// 用途：用户完全忘记管理密码时，由能访问本机文件的人运行一次：
//   - 备份正式数据文件与锁定状态文件；
//   - 用程序自己的加密格式解码；
//   - 把管理密码重置为指定新密码，清空恢复码与锁定；
//   - 重新加密写回，并复核可解码。
//
// 运行方式（在项目根目录；程序必须完全退出）：
//   set CMS_RECOVERY_FILE=C:\Users\你\Documents\班级管理系统\class_management_data.enc
//   set CMS_RECOVERY_PASSWORD=新密码123
//   flutter test tools/local_recovery/recover_password_test.dart
//
// 只用于作者/本机维护，不随安装包分发。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/services/atomic_file.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/services/storage_service.dart';

void main() {
  test('本机离线重置密码（需通过环境变量指定数据文件）', () async {
    final path = Platform.environment['CMS_RECOVERY_FILE']?.trim() ?? '';
    final newPassword =
        Platform.environment['CMS_RECOVERY_PASSWORD']?.trim() ?? '';
    if (path.isEmpty || newPassword.isEmpty) {
      print(
        '未执行：请设置 CMS_RECOVERY_FILE（数据文件路径）与 '
        'CMS_RECOVERY_PASSWORD（新密码，6-20 位）。',
      );
      return;
    }
    if (newPassword.length < 6 || newPassword.length > 20) {
      fail('新密码需为 6-20 位');
    }

    final file = File(path);
    if (!await file.exists()) {
      fail('数据文件不存在：$path');
    }
    final original = await file.readAsString();
    final storage = StorageService();
    final data = await storage.decodeForTest(original);
    if (data == null) {
      fail('数据文件无法解码（可能已损坏或不是本程序的数据文件）');
    }

    final hash = SecurityService.hashPassword(newPassword);
    final next = AppData(
      students: data.students,
      recordsByDate: data.recordsByDate,
      attendanceByDate: data.attendanceByDate,
      reasons: data.reasons,
      settings: data.settings.copyWith(
        passwordEnabled: true,
        passwordHash: hash,
        recoveryCodeHash: '',
        recoveryCodeCreatedAt: '',
      ),
    );
    final encoded = await storage.encodeForTest(next);
    final check = await storage.decodeForTest(encoded);
    if (check == null) {
      fail('重新编码后复核失败，已中止，未写入任何文件');
    }

    if (Platform.environment['CMS_RECOVERY_DRY_RUN'] == '1') {
      print('演练成功：文件可解码、可重新编码；未写入。');
      return;
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final backupPath = '$path.recovery_backup_$stamp';
    await file.copy(backupPath);

    // 锁定状态文件只含计数；一并备份后删除，避免新密码仍被旧锁定挡住。
    final guard = File('${file.parent.path}/class_management_auth_guard.json');
    if (await guard.exists()) {
      await guard.copy('$backupPath.auth_guard');
      await guard.delete();
    }

    await AtomicFile.writeString(path, encoded);
    print('恢复完成：管理密码已重置为指定新密码；恢复码已清空。');
    print('原数据备份：$backupPath');
  });
}
