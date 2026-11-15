/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-10-05 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// 破坏性操作确认弹窗（统一骨架：取消 + 红色确认按钮）。
///
/// 审查报告 M9：此前这套骨架在 11 处逐字符重复（只有文案不同），且曾实际发生
/// "某处漏了红色确认按钮"的不一致（只能靠人工逐处 review 发现）。统一到这里，
/// **新增破坏性确认一律走本函数**，不要再手写 AlertDialog 骨架。
///
/// 例外：确认按钮需**动态禁用**或用非静态文案时，本函数暂不支持，可手写但须：
/// ①确认按钮用 `dangerButtonStyle(theme)` 保证红色；②返回语义仍是
/// `confirmed == true` 才算确认。
///
/// 返回：用户点确认返回 true；点取消、或对话框被其它途径关闭（返回 null）
/// 一律为 false —— 与各处原有 `confirmed != true` 语义完全一致。
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool confirmEnabled = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed:
              confirmEnabled ? () => Navigator.pop(dialogContext, true) : null,
          style: dangerButtonStyle(Theme.of(dialogContext)),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// 带一个可选项的破坏性确认框。
///
/// 用于“执行 X 的同时，是否也做 Y”这类场景：开关默认关闭，
/// 返回 null 表示取消；否则返回用户是否确认、以及可选项是否勾选。
Future<({bool confirmed, bool option})?> confirmDestructiveWithOption(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String optionLabel,
  String? optionHint,
  String cancelLabel = '取消',
}) async {
  var option = false;
  return showDialog<({bool confirmed, bool option})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: option,
              onChanged: (value) => setState(() => option = value ?? false),
              title: Text(optionLabel),
              subtitle: optionHint == null ? null : Text(optionHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(cancelLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              (confirmed: true, option: option),
            ),
            style: dangerButtonStyle(Theme.of(dialogContext)),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}
