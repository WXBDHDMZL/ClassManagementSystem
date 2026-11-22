/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 窗口设置页（启动尺寸、关闭行为）。
class WindowSettingsPage extends StatelessWidget {
  const WindowSettingsPage({super.key});

  Future<void> _setStartupTarget(
    BuildContext context,
    AppDataProvider provider,
    StartupTarget target,
  ) async {
    final settings = provider.appData.settings;
    if (settings.startupTarget == target) return;
    if (settings.autoStart) {
      final ok = await DesktopService.setAutoStartEnabled(
        true,
        target: target,
      );
      if (!context.mounted) return;
      if (!ok) {
        showTopSnackBar(
          context,
          '切换开机启动目标失败，请检查系统权限后重试',
          isError: true,
        );
        return;
      }
    }
    provider.setStartupTarget(target);
    if (!context.mounted) return;
    showTopSnackBar(
      context,
      target == StartupTarget.ball ? '开机启动目标已设为悬浮球' : '开机启动目标已设为托盘',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('关闭窗口时'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(CloseActionType.ask, '每次询问'),
              MapEntry(CloseActionType.exit, '直接退出程序'),
              MapEntry(CloseActionType.minimizeToTray, '最小化到托盘'),
              MapEntry(CloseActionType.minimizeToBall, '最小化到悬浮球'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: settings.closeAction == entry.key,
                onPressed: () => provider.setCloseAction(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const SettingsHint(
          '选择"最小化到悬浮球"后，窗口将以桌面小球形式常驻，单击小球即可恢复；'
          '悬浮球也可在托盘菜单里随时切换。',
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('启动时'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(StartupWindowMode.remember, '记住上次的大小与位置'),
              MapEntry(StartupWindowMode.defaultSize, '每次都用默认大小'),
              MapEntry(StartupWindowMode.maximized, '启动即最大化'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: settings.startupWindowMode == entry.key,
                onPressed: () => provider.setStartupWindowMode(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const SettingsHint('选择"记住上次"时，退出程序前会记录窗口大小与位置，并记住是否处于最大化。'),
        const SizedBox(height: 20),
        const SettingsSectionTitle('开机自动启动'),
        // 修复（审查 三-10）：开关值来自 provider，`setAutoStart` 会
        // notifyListeners 驱动重建，此前额外套一层 StatefulBuilder + setLocalState
        // 属重复机制（易误改、掩盖真实数据源）。
        SwitchListTile(
          value: provider.appData.settings.autoStart,
          onChanged: (value) async {
            final target = provider.appData.settings.startupTarget;
            final ok = await DesktopService.setAutoStartEnabled(
              value,
              target: target,
            );
            if (!context.mounted) return;
            if (!ok) {
              showTopSnackBar(
                context,
                '设置开机自动启动失败，请检查系统权限后重试',
                isError: true,
              );
              return;
            }
            provider.setAutoStart(value);
            showTopSnackBar(
              context,
              value
                  ? '已开启：开机后自动启动并进入'
                      '${target == StartupTarget.ball ? '悬浮球' : '托盘'}'
                  : '已关闭开机自动启动',
            );
          },
          title: Text('随 Windows 启动', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '开启后，开机时程序会自动启动，并进入下面选择的目标；'
            '仅对当前 Windows 账户生效。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedTextColor(theme, 0.65),
              height: 1.4,
            ),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        Text('启动后进入', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(StartupTarget.tray, '托盘'),
              MapEntry(StartupTarget.ball, '悬浮球'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: settings.startupTarget == entry.key,
                onPressed: () async {
                  await _setStartupTarget(context, provider, entry.key);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        const SettingsHint(
          '选择“悬浮球”时，开机后主窗口不弹出，直接在桌面显示悬浮球；'
          '托盘图标仍保留。开启上面的开关后生效。',
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('悬浮球外观'),
        const SettingsHint(
          '拖动滑块调节悬浮球的透明度：数值越低越透明，越高越接近实心。'
          '悬浮球也可从托盘菜单或开机启动进入，因此这里始终可调。',
        ),
        Row(
          children: [
            Icon(Icons.opacity, size: 16, color: theme.colorScheme.onSurface),
            Expanded(
              child: CommitSlider(
                value: provider.appData.settings.ballOpacity,
                min: AppSettings.minBallOpacity,
                max: AppSettings.maxBallOpacity,
                divisions: 13,
                labelBuilder: (v) => '${(v * 100).round()}%',
                onCommit: (v) => provider.setBallOpacity(v),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '${(provider.appData.settings.ballOpacity * 100).round()}%',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: settings.ballPositionLocked,
          onChanged: provider.setBallPositionLocked,
          title: Text('锁定悬浮球位置', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '开启后左键拖动不会移动悬浮球，避免误触。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedTextColor(theme, 0.65),
            ),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}
