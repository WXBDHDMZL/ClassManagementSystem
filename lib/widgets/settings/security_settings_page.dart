/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.7
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

part of '../settings_pages.dart';

/// 安全设置页（V3）：只管理一个“管理密码”。
///
/// 管理密码用于进入班主任管理和打开安全设置。
class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({super.key});

  bool _hasManagementPassword(AppSettings settings) =>
      settings.passwordEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final muted = mutedTextColor(theme, 0.65);
    final configured = _hasManagementPassword(settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('管理密码'),
        SettingsHint(
          configured
              ? '管理密码用于进入班主任管理、打开安全设置。'
                  '密码只在本机加密保存，忘记后可用恢复码重置。'
              : '尚未设置管理密码。设置后，修改他人记录、导入、'
                  '修改设置等敏感操作需要先进入班主任管理。',
        ),
        if (configured && settings.passwordHash.isEmpty) ...[
          const SizedBox(height: 8),
          const SettingsHint(
            '⚠️ 当前仍在使用出厂默认密码，建议立即修改为只有你知道的密码。',
          ),
        ],
        const SizedBox(height: 12),
        if (!configured)
          SettingsActionButton(
            label: '设置管理密码',
            onPressed: () => _setManagementPassword(context, provider),
          )
        else
          Row(
            children: [
              Expanded(
                child: SettingsActionButton(
                  label: '修改管理密码',
                  onPressed: () => _changeManagementPassword(context, provider),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _disableManagementPassword(context, provider),
                  child: Text(
                    '关闭管理密码',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        ..._buildRecoverySection(context, provider, theme, muted),
        const SizedBox(height: 20),
        const SettingsHint(
          '查看今日/历史记录、数据统计与普通导出不受密码限制。'
          '关闭管理密码后，敏感操作将不再要求验证，请谨慎操作。',
        ),
      ],
    );
  }

  List<Widget> _buildRecoverySection(
    BuildContext context,
    AppDataProvider provider,
    ThemeData theme,
    Color muted,
  ) {
    final settings = provider.appData.settings;
    final enabled = settings.recoveryCodeEnabled;
    return [
      const SettingsSectionTitle('密码找回'),
      SettingsHint(
        enabled
            ? '已设置恢复码（创建于 ${settings.recoveryCodeCreatedAt.isEmpty ? '未知日期' : settings.recoveryCodeCreatedAt}）。'
                '忘记管理密码时，可在密码框点“忘记密码”，用恢复码重置。'
            : '尚未设置恢复码。生成后请抄写/打印保存；忘记管理密码时可一次性重置。',
      ),
      const SizedBox(height: 12),
      if (!enabled)
        SettingsActionButton(
          label: '生成恢复码',
          onPressed: () => _generateRecoveryCode(context, provider),
        )
      else
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: '重新生成恢复码',
                onPressed: () => _generateRecoveryCode(context, provider),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _disableRecoveryCode(context, provider),
                child: Text(
                  '关闭恢复码',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '恢复码只显示一次；使用成功后立即作废，需要重新生成。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ),
    ];
  }

  Future<void> _setManagementPassword(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    final ok = await ChangePasswordDialog.show(
      context,
      requireCurrent: false,
    );
    if (!ok || !context.mounted) return;
    if (!provider.appData.settings.passwordEnabled) {
      provider.setPasswordEnabled(true);
    }
    if (context.mounted) showTopSnackBar(context, '管理密码已设置');
  }

  Future<void> _changeManagementPassword(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    // 仍在使用出厂默认密码（哈希为空）时无需验证旧密码：它不是用户设置的，
    // 一旦丢失或未知，强制验证会让用户永远无法改密。
    final settings = provider.appData.settings;
    final usingFactoryPassword =
        settings.passwordEnabled && settings.passwordHash.isEmpty;
    final ok = await ChangePasswordDialog.show(
      context,
      requireCurrent: !usingFactoryPassword,
    );
    if (!ok || !context.mounted) return;
    if (!provider.appData.settings.passwordEnabled) {
      provider.setPasswordEnabled(true);
    }
    if (context.mounted) showTopSnackBar(context, '管理密码已修改');
  }

  Future<void> _disableManagementPassword(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: '关闭管理密码',
      message: '关闭后，进入班主任管理将不再要求密码；'
          '修改他人记录、导入和设置等敏感操作会直接放行。确定关闭吗？',
      confirmLabel: '确定关闭',
    );
    if (!confirmed || !context.mounted) return;
    final verified = await _verifyCurrentManagementPassword(
      context,
      '关闭管理密码前，请再次输入当前管理密码。',
    );
    if (!verified || !context.mounted) return;
    // 先关闭开关再清空哈希：中途失败时不会留下“启用密码但哈希为空”的
    // 出厂默认状态，用户仍可凭原密码进入并重试。
    provider.setPasswordEnabled(false);
    provider.setPasswordHash('');
    provider.exitManagementMode();
    if (context.mounted) showTopSnackBar(context, '已关闭管理密码');
  }

  Future<void> _generateRecoveryCode(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    final verified = await _verifyCurrentManagementPassword(
      context,
      '生成恢复码前，请再次输入当前管理密码。',
    );
    if (!verified || !context.mounted) return;
    if (provider.appData.settings.passwordEnabled &&
        !provider.isManagementMode) {
      showTopSnackBar(
        context,
        '管理会话已结束，请重新验证后再生成恢复码。',
        isError: true,
      );
      return;
    }
    final code = SecurityService.generateRecoveryCode();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _RecoveryCodeDialog(code: code),
    );
    if (confirmed != true || !context.mounted) return;
    await provider.setRecoveryCode(code);
    if (!context.mounted) return;
    showTopSnackBar(context, '恢复码已保存，请妥善保管');
  }

  Future<void> _disableRecoveryCode(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: '关闭恢复码',
      message: '关闭后，忘记管理密码将无法通过恢复码找回。确定关闭吗？',
      confirmLabel: '确定关闭',
    );
    if (confirmed != true || !context.mounted) return;
    final verified = await _verifyCurrentManagementPassword(
      context,
      '关闭恢复码前，请再次输入当前管理密码。',
    );
    if (!verified || !context.mounted) return;
    provider.clearRecoveryCode();
    if (context.mounted) showTopSnackBar(context, '已关闭恢复码');
  }
}

/// 关闭/生成恢复码等安全动作前的再次验证。
///
/// 密码关闭时没有可验证的凭据，直接放行；密码开启时必须重新输入，
/// 不能复用“已在管理会话中”这个条件，否则页面开着时仍可直接操作。
Future<bool> _verifyCurrentManagementPassword(
  BuildContext context,
  String message,
) async {
  final provider = Provider.of<AppDataProvider>(context, listen: false);
  if (!provider.appData.settings.passwordEnabled) return true;
  return PasswordPromptDialog.verify(
    context,
    message: message,
    credential: AuthCredential.operation,
    customLabel: '管理密码',
  );
}

/// 恢复码一次性展示对话框。
///
/// 管理会话在弹窗打开期间结束时立即关闭，避免恢复码在已锁定的页面
/// 之上继续暴露；密码关闭时不触发该行为。
class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog({required this.code});

  final String code;

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  late final AppDataProvider _provider;
  bool _acknowledged = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _provider = Provider.of<AppDataProvider>(context, listen: false);
    _provider.addListener(_handleProviderChanged);
    // 验证密码与实际打开弹窗之间可能隔着一次路由动画；若管理会话在
    // 此期间结束，首帧也要主动关闭，不能只等后续状态通知。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closeIfSessionEnded();
    });
  }

  @override
  void dispose() {
    _provider.removeListener(_handleProviderChanged);
    super.dispose();
  }

  void _handleProviderChanged() {
    _closeIfSessionEnded();
  }

  void _closeIfSessionEnded() {
    if (_closing || !mounted) return;
    final settings = _provider.appData.settings;
    if (!settings.passwordEnabled || _provider.isManagementMode) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('恢复码（只显示一次）'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请抄写或打印保存。关闭本窗口后将无法再次查看。'),
            const SizedBox(height: 12),
            SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.code));
              },
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('复制恢复码'),
            ),
            CheckboxListTile(
              value: _acknowledged,
              onChanged: (value) =>
                  setState(() => _acknowledged = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text('我已抄写/保存恢复码'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _acknowledged
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('保存恢复码'),
        ),
      ],
    );
  }
}
