/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../providers/app_data_provider.dart';
import '../services/desktop_service.dart';
import 'app_notification.dart';

/// 启动期"数据阻断"对话框（审计 A-01 / A-02）。
///
/// 两种情形对应两种语义，**不能混用**：
/// - [StartupDataBlockKind.corrupted]：主文件与 `.bak` 都读不出来，原文件已
///   隔离成 `.corrupt_*`。这里要用户显式确认后才能开始写空库。
/// - [StartupDataBlockKind.keyMismatch]：数据文件很可能完好，只是密钥对不上。
///   主按钮是"退出并换回原密钥"，"以空库继续"藏在第三层并需二次输入。
enum StartupDataBlockKind { corrupted, keyMismatch }

/// 弹出启动期数据阻断对话框。返回 true 表示用户已确认可以写空库。
Future<bool> showStartupDataBlockDialog(
  BuildContext context, {
  required StartupDataBlockKind kind,
}) async {
  final provider = context.read<AppDataProvider>();
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _StartupDataBlockDialog(kind: kind, provider: provider),
  );
  return result ?? false;
}

class _StartupDataBlockDialog extends StatefulWidget {
  const _StartupDataBlockDialog({required this.kind, required this.provider});

  final StartupDataBlockKind kind;
  final AppDataProvider provider;

  @override
  State<_StartupDataBlockDialog> createState() =>
      _StartupDataBlockDialogState();
}

class _StartupDataBlockDialogState extends State<_StartupDataBlockDialog> {
  /// 损坏态：确认以空库继续所需的字样。
  static const String _emptyLibraryPhrase = '确认以空库继续';

  /// 密钥不匹配态：放弃可恢复数据所需的字样（更重的语义，字样也不同）。
  static const String _giveUpPhrase = '确认放弃可恢复数据';

  final TextEditingController _controller = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;
  String? _error;

  bool get _isKeyMismatch => widget.kind == StartupDataBlockKind.keyMismatch;

  /// 是否已经进入"仍要以空库继续"的第三层（仅密钥不匹配态需要）。
  bool _showGiveUp = false;

  String get _expectedPhrase =>
      _isKeyMismatch ? _giveUpPhrase : _emptyLibraryPhrase;

  bool get _canConfirm =>
      !_busy &&
      _acknowledged &&
      _controller.text.trim() == _expectedPhrase;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmEmptyLibrary() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.provider.confirmEmptyLibrary();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = '切换失败：请关闭占用数据文件的程序后重试';
    });
    if (!ok) return;
    // 先弹提示再关对话框：pop 之后本 State 的 context 已失活。
    showTopSnackBar(
      context,
      '已切换为空库：原数据文件已隔离保留，未被删除',
      isError: true,
    );
    Navigator.pop(context, true);
  }

  Future<void> _quitForOriginalKey() async {
    Navigator.pop(context, false);
    await DesktopService.instance.quitWithoutSaving(
      reason: '数据密钥与数据文件不匹配，用户选择退出并换回原密钥',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.7);
    final quarantined = widget.provider.quarantinedPath;

    return AlertDialog(
      // GUI 验收发现：1280x800 窗口下（含 150% 缩放）内容超过可用高度，
      // 按钮被挤出窗口导致用户无法完成确认。scrollable 让标题+正文滚动，
      // 底部按钮始终可见可点。
      scrollable: true,
      title: Text(_isKeyMismatch ? '数据密钥与数据文件不匹配' : '数据文件损坏，已隔离保留'),
      content: ConstrainedBox(
        // GUI 验收发现：写死 520 在 1280x800（150% 缩放 ≈ 853 逻辑宽）下会
        // 超出可用宽度、右侧文字被裁掉。改成上限 520、可用空间更窄时自动收缩。
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isKeyMismatch
                    ? '数据文件没有损坏的迹象，但它是用另一把数据密钥加密的'
                        '（通常是数据密钥文件被替换，或被更早的备份覆盖）。\n'
                        '程序已暂停写入并保留全部原文件。'
                    : '主数据文件与上一份自动备份都无法解密，程序已把原文件改名'
                        '隔离保存（没有删除）。\n'
                        '在确认之前，程序不会写入任何数据，也不会覆盖上一份备份。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  height: 1.6,
                ),
              ),
              if (quarantined != null && quarantined.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(
                  '被隔离的原文件：$quarantined',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _isKeyMismatch
                    ? '建议：先退出程序，把原来的 class_management_data.enc.key '
                        '换回来再启动；或用设置里的"从备份恢复"。'
                    : '建议：先用设置里的"从备份恢复"还原数据；'
                        '若确认没有可用备份，再选择以空库继续。',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (!_isKeyMismatch || _showGiveUp) ...[
                const SizedBox(height: 16),
                Text(
                  '请输入「$_expectedPhrase」以继续：',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '按提示文字原样输入',
                  ),
                ),
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _acknowledged = value ?? false),
                  title: Text(
                    '我已了解：在录入新数据之前，程序不会覆盖上一份备份',
                    style: theme.textTheme.bodyMedium,
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _buildActions(theme),
    );
  }

  List<Widget> _buildActions(ThemeData theme) {
    final actions = <Widget>[];
    if (_isKeyMismatch) {
      actions.add(
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  Navigator.pop(context, false);
                },
          child: const Text('稍后处理'),
        ),
      );
      if (!_showGiveUp) {
        actions.add(
          TextButton(
            onPressed: _busy ? null : () => setState(() => _showGiveUp = true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('仍要以空库继续'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: _busy ? null : _quitForOriginalKey,
            child: const Text('退出并换回原 .enc.key'),
          ),
        );
      } else {
        actions.add(
          FilledButton(
            onPressed: _canConfirm ? _confirmEmptyLibrary : null,
            child: Text(_busy ? '处理中…' : '以空库继续（原文件保留）'),
          ),
        );
      }
      return actions;
    }
    actions.add(
      TextButton(
        onPressed: _busy
            ? null
            : () {
                Navigator.pop(context, false);
              },
        child: const Text('稍后处理'),
      ),
    );
    actions.add(
      FilledButton(
        onPressed: _canConfirm ? _confirmEmptyLibrary : null,
        child: Text(_busy ? '处理中…' : '以空库继续（原文件保留）'),
      ),
    );
    return actions;
  }
}
