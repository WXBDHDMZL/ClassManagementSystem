/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.0
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 关于页：版本、更新检查、项目与许可信息。
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  Future<void> _openProjectPage(BuildContext context) async {
    final url = AppVersion.sourceCodeUrl;
    if (url.isEmpty) return;
    try {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
    } on Object catch (e) {
      if (context.mounted) {
        showTopSnackBar(context, '打开项目地址失败：$e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: AppRadius.card,
                gradient: theme.semantic.brandGradient,
              ),
              child: Icon(
                Icons.school,
                color: theme.semantic.onBrand,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '班级管理系统',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Class Management System',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SettingsSectionTitle('版本'),
        _infoRow(theme, muted, '应用版本', AppVersion.version),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            '启动时检查更新',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            '启动时自动检查 GitHub 上的正式发布版本，有可用版本时在本页提示',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          value: settings.checkUpdateOnStartup,
          onChanged: (value) => provider.setCheckUpdateOnStartup(value),
        ),
        const SizedBox(height: 4),
        const AboutUpdateSection(),
        const SizedBox(height: 20),
        const SettingsSectionTitle('项目'),
        _linkRow(
          context,
          theme,
          muted,
          '项目地址',
          AppVersion.sourceCodeUrl,
          onTap: () => _openProjectPage(context),
        ),
        _infoRow(theme, muted, '开源许可证', 'AGPL-3.0-only'),
        _infoRow(theme, muted, '开发作者', 'WXBDHDMZL'),
        _infoRow(theme, muted, '版权声明', '© 2026 WXBDHDMZL｜AGPL-3.0-only'),
        const SizedBox(height: 16),
        const SettingsSectionTitle('功能简介'),
        Text(
          '用于记录学生的表扬与批评表现，可按自定义时段归档，支持历史查询、'
          '事后追加、自定义原因与备注、Excel 导出与统计。'
          '程序可最小化到系统托盘或桌面悬浮球在后台常驻；'
          '名单、原因库、时段与记录都支持表格导入导出。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        Text(
          '记录、名单与设置只保存在本机的「班级管理系统」文件夹，不会上传；'
          '天气查询仅发送所选地区名称或坐标。'
          '主数据为 .enc 文件，同目录的 .bak 为上一份自动备份；'
          '日志在「日志」子目录中以单个加密文件记录每次增删改的时间与内容，可用于核对数据变更。'
          '换电脑或重装前，备份整个「班级管理系统」文件夹即可保留全部记录。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => const TermsOfServiceDialog(),
          ),
          child: const Text('开源许可与使用说明'),
        ),
        // 第三方组件由 Flutter 的 LicensePage 汇总展示。
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: '班级管理系统',
            applicationVersion: AppVersion.version,
          ),
          child: const Text('开源组件许可'),
        ),
      ],
    );
  }

  Widget _infoRow(ThemeData theme, Color muted, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(
    BuildContext context,
    ThemeData theme,
    Color muted,
    String label,
    String value, {
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
