/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

part of '../settings_pages.dart';

/// 外观与窗口：主题、字号、关闭/启动行为、悬浮球与天气地区。
///
/// 合并原「主题」「窗口」两个入口，减少设置首页菜单层级。
class AppearanceWindowSettingsPage extends StatelessWidget {
  const AppearanceWindowSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppearanceSettingsPage(),
        const Divider(height: 32),
        const WindowSettingsPage(),
        const Divider(height: 32),
        const SettingsSectionTitle('主页学生搜索'),
        SwitchListTile(
          value: settings.studentSearchEnabled,
          onChanged: provider.setStudentSearchEnabled,
          title: Text('显示学生搜索框', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '关闭后主页学生网格上方不显示搜索框，名单始终完整显示。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedTextColor(theme, 0.65),
            ),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const Divider(height: 32),
        const SettingsSectionTitle('天气地区'),
        SwitchListTile(
          value: settings.showWeather,
          onChanged: provider.setShowWeather,
          title: Text('在顶栏显示天气', style: theme.textTheme.bodyMedium),
          subtitle: Text(
            '关闭时不显示天气，也不会向天气服务发起请求。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedTextColor(theme, 0.65),
            ),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        SettingsHint(
          settings.weatherCityName.isEmpty
              ? '尚未设置天气地区；设置并开启后顶栏会显示当前天气。'
              : '当前地区：${settings.weatherCityName}'
                  '${settings.weatherCityAdmin.isEmpty ? '' : '（${settings.weatherCityAdmin}）'}',
        ),
        const SizedBox(height: 8),
        SettingsActionButton(
          label: settings.weatherCityName.isEmpty ? '设置天气地区' : '更换天气地区',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const WeatherCityDialog(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '只向天气服务发送城市名称/坐标，不包含学生姓名、记录或名单。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: mutedTextColor(theme, 0.6),
          ),
        ),
      ],
    );
  }
}
