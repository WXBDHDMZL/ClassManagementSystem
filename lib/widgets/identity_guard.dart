/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_data_provider.dart';
import './app_notification.dart';
import './identity_picker_dialog.dart';

/// 修改2：身份功能开启时，写操作统一要求先选择操作身份。
///
/// 返回 true 表示可以继续（功能未开启 / 已有身份 / 用户刚选了身份）；
/// 查看与导出不调用本函数，保持免身份。
Future<bool> ensureIdentityForAction(
  BuildContext context, {
  required String action,
}) async {
  final provider = Provider.of<AppDataProvider>(context, listen: false);
  if (!provider.identityFeatureEnabled) return true;
  if (provider.activeIdentity != null) return true;
  showTopSnackBar(context, '进行“$action”前请先选择操作身份');
  await showIdentityPicker(context);
  return provider.activeIdentity != null;
}
