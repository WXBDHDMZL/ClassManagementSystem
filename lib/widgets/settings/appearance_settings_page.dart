/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 外观（主题/字号）与记录设置页。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final current = settings.themeMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('外观模式'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(ThemeModeType.light, '浅色'),
              MapEntry(ThemeModeType.dark, '深色'),
              MapEntry(ThemeModeType.system, '跟随系统'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: current == entry.key,
                onPressed: () => provider.setThemeMode(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const SettingsHint(
          '选择"跟随系统"时，将随 Windows 的深浅色设置自动切换；'
          '悬浮球与托盘菜单也会一起跟随当前主题。',
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('界面字号'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(0.85, '小'),
              MapEntry(1.0, '标准'),
              MapEntry(1.15, '大'),
              MapEntry(1.3, '特大'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: (settings.uiScale - entry.key).abs() < 0.01,
                onPressed: () {
                  provider.setUiScale(entry.key);
                  showTopSnackBar(context, '界面字号已切换为「${entry.value}」');
                },
              ),
          ],
        ),
        const SettingsHint(
          '整体缩放界面文字（含列表、对话框与统计），适合一体机远距离观看。',
        ),
      ],
    );
  }
}

/// 记录设置：默认操作类型与是否自动预选时段。
class RecordSettingsPage extends StatelessWidget {
  const RecordSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final muted = mutedTextColor(theme, 0.65);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('默认操作类型'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(0, '表扬'),
              MapEntry(1, '批评'),
              MapEntry(2, '沿用上次类型'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: settings.recordDefaultType == entry.key,
                onPressed: () => provider.setRecordDefaults(
                  defaultType: entry.key,
                  autoSelectPeriod: settings.autoSelectPeriod,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const SettingsHint('打开学生记录窗口时，默认选中的操作类型。'),
        const SizedBox(height: 20),
        const SettingsSectionTitle('时段选择'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SettingsChoiceButton(
              label: '按当前时刻自动预选',
              selected: settings.autoSelectPeriod,
              onPressed: () => provider.setRecordDefaults(
                defaultType: settings.recordDefaultType,
                autoSelectPeriod: true,
              ),
            ),
            SettingsChoiceButton(
              label: '手动选择时段',
              selected: !settings.autoSelectPeriod,
              onPressed: () => provider.setRecordDefaults(
                defaultType: settings.recordDefaultType,
                autoSelectPeriod: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const SettingsHint('时段的名称与时间范围可在"时间段"设置页中自定义。'),
        const SizedBox(height: 20),
        const SettingsSectionTitle('启用的记录类型'),
        SwitchListTile(
          value: provider.appData.settings.praiseEnabled,
          // 两者至少保留一个：只剩一种类型时，禁止关闭最后一个开关。
          onChanged: settings.criticismEnabled
              ? (value) => provider.setRecordTypesEnabled(praise: value)
              : null,
          title: Text('表扬', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '关闭后记录对话框只记录批评；历史记录与统计保持不变',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: provider.appData.settings.criticismEnabled,
          onChanged: settings.praiseEnabled
              ? (value) => provider.setRecordTypesEnabled(criticism: value)
              : null,
          title: Text('批评', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '关闭后记录对话框只记录表扬；两者至少保留一个',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 16),
        const SettingsSectionTitle('原因排序'),
        SwitchListTile(
          value: provider.appData.settings.reasonSortByUsage,
          onChanged: provider.setReasonSortByUsage,
          title: Text('按使用频率自动排序', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '开启后，记录对话框的原因按历史使用次数从多到少排列；'
            '关闭则按"名单与原因库 → 原因管理"里的手动顺序',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}

/// 考勤设置：考勤功能开关与考勤状态项（可增删改名，改名同步历史考勤）。
