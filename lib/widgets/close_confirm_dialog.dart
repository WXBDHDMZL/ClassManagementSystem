/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.10.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../constants/app_theme.dart';

/// 关闭确认结果：用户选择的行为与是否记住该选择。
class CloseConfirmResult {
  final CloseActionType action;
  final bool remember;

  const CloseConfirmResult(this.action, this.remember);
}

/// 关闭窗口确认对话框：选择"退出程序"或"最小化到托盘"。
/// 勾选"记住我的选择"后，下次关闭不再询问（可在设置面板中修改）。
class CloseConfirmDialog extends StatefulWidget {
  const CloseConfirmDialog({super.key});

  /// 弹出对话框并等待用户选择；点击"取消"返回 null（窗口保持打开）。
  static Future<CloseConfirmResult?> show(BuildContext context) {
    return showDialog<CloseConfirmResult>(
      context: context,
      builder: (context) => const CloseConfirmDialog(),
    );
  }

  @override
  State<CloseConfirmDialog> createState() => _CloseConfirmDialogState();
}

class _CloseConfirmDialogState extends State<CloseConfirmDialog> {
  bool _remember = false;

  void _confirm(CloseActionType action) {
    Navigator.pop(context, CloseConfirmResult(action, _remember));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);

    return AlertDialog(
      title: const Text('关闭窗口'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '退出程序：结束运行并关闭后台。\n'
            '最小化到托盘：程序继续在后台运行，数据照常保存，'
            '可从托盘图标随时恢复到窗口。\n'
            '最小化到悬浮球：窗口收缩成桌面上的小圆球，单击圆球即可恢复窗口。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _remember,
            onChanged: (value) => setState(() => _remember = value ?? false),
            title: Text(
              '记住我的选择，不再询问',
              style: theme.textTheme.bodyMedium,
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => _confirm(CloseActionType.minimizeToTray),
          child: const Text('最小化到托盘'),
        ),
        TextButton(
          onPressed: () => _confirm(CloseActionType.minimizeToBall),
          child: const Text('最小化到悬浮球'),
        ),
        ElevatedButton(
          onPressed: () => _confirm(CloseActionType.exit),
          child: const Text('退出程序'),
        ),
      ],
    );
  }
}
