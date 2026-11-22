/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_data_provider.dart';
import '../services/auth_service.dart';
import '../services/security_service.dart';
import '../constants/app_theme.dart';
import 'record_list.dart' show showTopSnackBar;

/// 忘记密码：用恢复码重置管理密码（一次性恢复码）。
class RecoveryCodeDialog extends StatefulWidget {
  const RecoveryCodeDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const RecoveryCodeDialog(),
    );
    return result ?? false;
  }

  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final settings = provider.appData.settings;
    if (!settings.recoveryCodeEnabled) {
      showTopSnackBar(
        context,
        '尚未设置恢复码；请用之前的密码登录后在'
        '「设置 → 系统与安全 → 安全与密码」中生成，'
        '或使用本机离线恢复工具',
        isError: true,
      );
      return;
    }
    _submitting = true;
    try {
      final normalized = SecurityService.normalizeRecoveryCode(
        _codeController.text,
      );
      if (normalized.isEmpty) {
        showTopSnackBar(context, '请输入恢复码', isError: true);
        return;
      }
      final result = await AuthService.verify(
        settings,
        AuthCredential.recoveryCode,
        normalized,
      );
      if (!mounted) return;
      if (!result.success) {
        showTopSnackBar(
          context,
          result.locked
              ? '恢复码尝试次数过多，请 ${result.remainingSeconds} 秒后再试'
              : '恢复码错误',
          isError: true,
        );
        return;
      }
      final error = SecurityService.validateNewPassword(
        _passwordController.text,
        _confirmController.text,
      );
      if (error != null) {
        showTopSnackBar(context, error, isError: true);
        return;
      }
      final saved = await provider.resetPasswordsWithRecoveryCode(
        _passwordController.text,
        recoveryCode: _codeController.text,
      );
      if (!mounted) return;
      if (!saved) {
        showTopSnackBar(context, '密码重置后保存失败，请检查磁盘空间', isError: true);
        return;
      }
      showTopSnackBar(
        context,
        '密码已重置，恢复码已作废；请登录后重新生成恢复码',
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
    return AlertDialog(
      title: const Text('忘记密码'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用之前生成的恢复码重置密码。恢复码只在本机校验，'
                '重置成功后立即作废；管理密码会一起改为下面的新密码。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _codeController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '恢复码',
                  hintText: '例如：ABCD-EFGH-IJKL-MNOP-QRST',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '新密码（6-20 位）',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('重置密码'),
        ),
      ],
    );
  }
}
