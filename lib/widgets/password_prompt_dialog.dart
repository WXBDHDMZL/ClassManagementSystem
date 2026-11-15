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
import 'package:provider/provider.dart';

import '../providers/app_data_provider.dart';
import '../services/auth_service.dart';
import './recovery_code_dialog.dart';
import './record_list.dart';
import '../constants/app_theme.dart';

/// 密码验证对话框：改动数据前统一先校验密码。
///
/// 默认验证管理密码；可通过 [credential] 指定管理密码。
class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({
    super.key,
    required this.message,
    this.credential = AuthCredential.operation,
    this.customLabel,
  });

  /// 提示文案，例如"修改学生名单需要输入管理密码"。
  final String message;

  /// 要验证的密码类型（合并模式下两者等价）。
  final AuthCredential credential;

  /// 可选显示名：例如班主任管理统一显示“管理密码”。
  final String? customLabel;

  /// 弹出验证框：密码正确返回 true，取消或错误返回 false。
  static Future<bool> verify(
    BuildContext context, {
    required String message,
    AuthCredential credential = AuthCredential.operation,
    String? customLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PasswordPromptDialog(
        message: message,
        credential: credential,
        customLabel: customLabel,
      ),
    );
    return result ?? false;
  }

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  /// 密码是否明文显示（修复 4.5：教室一体机是触控屏，纯盲打极易出错）。
  bool _obscure = true;

  /// 正在校验中（性能批 M6：校验移入后台 isolate 需短暂等待，
  /// 防止等待期间重复点"确认"叠加多次校验）。
  bool _verifying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying) return;
    _verifying = true;
    try {
      final provider = Provider.of<AppDataProvider>(context, listen: false);
      final settings = provider.appData.settings;
      final result = await AuthService.verify(
        settings,
        widget.credential,
        _controller.text,
      );
      if (!mounted) return;
      if (result.success) {
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      // 修复（4.6）：密码错误时**清空输入框**并保持焦点 —— 此前保留错误密码，
      // 输错后要手动全选删除；同时避免"多次尝试"时把上一次的内容叠进去。
      _controller.clear();
      if (result.locked) {
        showTopSnackBar(
          context,
          '尝试次数过多，请 ${result.remainingSeconds} 秒后再试',
          isError: true,
        );
      } else {
        final remaining =
            AuthService.maxFailuresBeforeLock - AuthService.failureCount(widget.credential);
        showTopSnackBar(
          context,
          remaining > 0 ? '密码错误（再错 $remaining 次将临时锁定）' : '密码错误',
          isError: true,
        );
      }
    } finally {
      _verifying = false;
    }
  }

  Future<void> _forgotPassword() async {
    final changed = await RecoveryCodeDialog.show(context);
    if (!mounted) return;
    if (changed) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);
    final label =
        widget.customLabel ?? AuthService.label(widget.credential);
    return AlertDialog(
      title: Text('请输入$label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              // 修复（4.5）：显示/隐藏切换 —— 只改 obscureText 属性，
              // 不重建输入框，焦点与已输入内容都不受影响。
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _forgotPassword,
          child: const Text('忘记密码'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

/// 通用密码输入对话框：只负责"收集一段密码文本"，校验与后续动作交给调用方。
///
/// 为什么单独做成 StatefulWidget（V2.27.7）：
/// 此前三处（记录编辑 / 记录删除 / 追加记录）的写法是
/// `final c = TextEditingController(); await showDialog(...); c.dispose();`
/// ——`await` 在路由被 pop 时立刻返回，而退场动画还要跑约 200ms；
/// 若这期间主题/MediaQuery 变化触发路由子树重建，TextField 会去用已 dispose 的
/// 控制器（debug 断言/异常）。把控制器交给 State 持有后，释放时机与路由子树
/// 的生命周期严格对齐，问题从根上消失，同时也消掉了三处重复代码。
///
/// 用法：
/// ```dart
/// final password = await PasswordInputDialog.ask(
///   context, title: '请输入密码以修改', message: '请输入密码以修改',
/// );
/// if (password == null) return;      // 用户取消
/// ```
class PasswordInputDialog extends StatefulWidget {
  const PasswordInputDialog({
    super.key,
    required this.message,
    this.title,
  });

  /// 密码框上方的提示文案。
  final String message;

  /// 可选的标题（显示为加粗首行）；不传则只显示 [message]。
  final String? title;

  /// 弹出密码框；用户点"确认"或回车返回输入内容，取消返回 null。
  static Future<String?> ask(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => PasswordInputDialog(message: message, title: title),
    );
  }

  @override
  State<PasswordInputDialog> createState() => _PasswordInputDialogState();
}

class _PasswordInputDialogState extends State<PasswordInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.title != null) ...[
              Text(
                widget.title!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
            ],
            Text(widget.message),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text('确认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
