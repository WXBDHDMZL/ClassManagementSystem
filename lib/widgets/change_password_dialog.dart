/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_data_provider.dart';
import '../services/auth_service.dart';
import '../services/security_service.dart';
import './record_list.dart';
import '../constants/app_theme.dart';

/// 修改密码对话框：验证当前密码后设置新密码（管理密码或管理密码）。
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({
    super.key,
    this.requireCurrent = true,
  });

  /// 是否需要先验证当前密码（首次设置密码时传 false）。
  final bool requireCurrent;

  /// 弹出对话框；返回是否修改/设置成功。
  static Future<bool> show(
    BuildContext context, {
    bool requireCurrent = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ChangePasswordDialog(
        requireCurrent: requireCurrent,
      ),
    );
    return result ?? false;
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  /// 是否明文显示（修复 4.5：一体机触控屏上盲打两遍易出错）。
  bool _showPassword = false;

  /// 正在提交中（性能批 M6：校验/哈希移入后台 isolate 需短暂等待，
  /// 防止等待期间重复点按叠加多次提交）。
  bool _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _submitting = true;
    try {
      final provider = Provider.of<AppDataProvider>(context, listen: false);
      final settings = provider.appData.settings;
      const label = '管理密码';
      final enabled = AuthService.isEnabled(settings, AuthCredential.operation);

      if (widget.requireCurrent && enabled) {
        if (_currentController.text.trim().isEmpty) {
          showTopSnackBar(context, '请输入当前$label', isError: true);
          return;
        }
        final current = await AuthService.verify(
          settings,
          AuthCredential.operation,
          _currentController.text,
        );
        if (!mounted) return;
        if (!current.success) {
          showTopSnackBar(
            context,
            current.locked
                ? '尝试次数过多，请 ${current.remainingSeconds} 秒后再试'
                : '当前密码错误',
            isError: true,
          );
          return;
        }
      }
      final error = SecurityService.validateNewPassword(
        _newController.text,
        _confirmController.text,
      );
      if (error != null) {
        showTopSnackBar(context, error, isError: true);
        return;
      }
      if (widget.requireCurrent && enabled) {
        // 新哈希带随机盐，哈希串不可直接比较；用验证接口判断“新旧相同”。
        final same = await AuthService.verify(
          settings,
          AuthCredential.operation,
          _newController.text,
        );
        if (!mounted) return;
        if (same.success) {
          showTopSnackBar(context, '新密码与当前密码相同', isError: true);
          return;
        }
      }

      final newHash =
          await SecurityService.hashPasswordAsync(_newController.text);
      if (!mounted) return;
      provider.setPasswordHash(newHash);
      showTopSnackBar(
        context,
        widget.requireCurrent ? '$label已修改' : '$label已设置',
      );
      Navigator.pop(context, true);
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);
    const label = '管理密码';
    return AlertDialog(
      title: Text(widget.requireCurrent ? '修改$label' : '设置$label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '管理密码用于进入班主任管理和打开安全设置；'
            '修改他人记录、导入和调整设置等敏感操作会先要求进入班主任管理。'
            '密码只在本机加密保存，忘记后可用恢复码重置。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          if (widget.requireCurrent) ...[
            _buildField(_currentController, '当前$label', autofocus: true),
            const SizedBox(height: 12),
          ],
          _buildField(
            _newController,
            '新密码（${SecurityService.minPasswordLength}-'
                '${SecurityService.maxPasswordLength} 位）',
          ),
          const SizedBox(height: 12),
          _buildField(
            _confirmController,
            '确认新密码',
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.requireCurrent ? '确定修改' : '确定设置'),
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: !_showPassword,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        // 修复（4.5）：一体机触控屏上"改密码要盲打两遍"极易出错，
        // 提供显示/隐藏切换；只改属性不重建输入框，焦点不丢。
        suffixIcon: IconButton(
          icon: Icon(
            _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
          tooltip: _showPassword ? '隐藏密码' : '显示密码',
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
    );
  }
}
