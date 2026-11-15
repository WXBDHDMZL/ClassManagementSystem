/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';

import '../models/password_policy.dart';
import '../providers/app_data_provider.dart';
import '../services/auth_service.dart';
import 'password_prompt_dialog.dart';

/// 班主任管理验证：开启新身份模型时，敏感操作统一进入 15 分钟管理模式。
///
Future<bool> ensureManagementMode(
  BuildContext context,
  AppDataProvider provider, {
  String message = '该操作需要进入班主任管理，请输入管理密码。',
}) async {
  if (provider.isManagementMode) return true;
  final settings = provider.appData.settings;
  if (!settings.passwordEnabled) {
    provider.enterManagementMode();
    return true;
  }
  final verified = await PasswordPromptDialog.verify(
    context,
    message: message,
    credential: AuthCredential.operation,
    customLabel: '管理密码',
  );
  if (!verified) return false;
  provider.enterManagementMode();
  return true;
}

/// 动作级验证：V3.0.0 固定新权限模型。
///
/// 普通模式动作（新增记录、历史追加、考勤登记）直接放行，由身份权限控制；
/// 其余敏感动作统一进入班主任管理。旧的逐动作密码开关不再参与运行。
Future<bool> ensurePasswordForAction(
  BuildContext context,
  AppDataProvider provider,
  PasswordAction action, {
  required String message,
}) async {
  if (!provider.appData.settings.passwordEnabled) return true;
  if (!provider.actionRequiresManagement(action)) return true;
  return ensureManagementMode(context, provider, message: message);
}

/// 页面级验证：V3.0.0 固定为“进入敏感页面需要班主任管理”。
Future<bool> ensurePasswordForPage(
  BuildContext context,
  AppDataProvider provider, {
  required String title,
}) async {
  if (!provider.appData.settings.passwordEnabled) return true;
  return ensureManagementMode(
    context,
    provider,
    message: '进入「$title」需要先进入班主任管理。',
  );
}
