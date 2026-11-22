/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 备份设置页。
class BackupSettingsPage extends StatelessWidget {
  const BackupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final settings = provider.appData.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('备份位置'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('backup_path_${settings.backupPath}'),
                initialValue: settings.backupPath,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.card,
                  ),
                  hintText: r'默认：文档目录下的"班级管理系统\备份"',
                  hintStyle: TextStyle(color: mutedTextColor(theme, 0.5)),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  fillColor: theme.colorScheme.surfaceContainer,
                  filled: true,
                ),
                style: TextStyle(color: theme.colorScheme.onSurface),
                readOnly: true,
              ),
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: '更改',
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath(
                  dialogTitle: '选择备份保存位置',
                );
                if (result == null || !context.mounted) return;
                provider.setBackupPath(result);
                showTopSnackBar(context, '备份位置已更新');
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        const SettingsHint(
          '备份是加密的数据文件，恢复时会整体覆盖现有数据。'
          '每次备份生成一份带时间的文件，按下面的份数自动清理过期备份。',
        ),
        const SizedBox(height: 10),
        Text(
          '保留最近 ${settings.backupKeepCount} 份自动备份',
          style: theme.textTheme.bodySmall?.copyWith(
            color: mutedTextColor(theme, 0.65),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final count in const [5, 10, 20, 30])
              SettingsChoiceButton(
                label: '$count 份',
                selected: settings.backupKeepCount == count,
                onPressed: () => provider.setBackupKeepCount(count),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionTitle('自动备份'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              MapEntry(BackupFrequency.manual, '仅手动备份'),
              MapEntry(BackupFrequency.onExit, '每次退出时'),
              MapEntry(BackupFrequency.daily, '每天一次'),
              MapEntry(BackupFrequency.everyThreeDays, '每 3 天一次'),
              MapEntry(BackupFrequency.weekly, '每周一次'),
            ])
              SettingsChoiceButton(
                label: entry.value,
                selected: settings.backupFrequency == entry.key,
                onPressed: () => provider.setBackupFrequency(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SettingsHint(
          settings.backupLastAt.isEmpty
              ? '还没有备份过。'
              : '上次备份：${settings.backupLastAt}',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: '立即备份',
                onPressed: () => _performBackup(context, provider),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsActionButton(
                label: '从备份恢复',
                onPressed: () => _restoreFromBackup(context, provider),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SettingsSectionTitle('危险操作'),
        SettingsHint(
          '恢复出厂会清空全部记录${AttendanceFeature.enabled ? '与考勤' : ''}，并恢复出厂学生名单、原因库与默认设置；'
          '管理密码与操作身份设置也会被清除。'
          '执行前会自动备份，仍可通过"从备份恢复"挽回。',
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _factoryReset(context, provider),
            icon: Icon(Icons.restart_alt, color: theme.colorScheme.error),
            label: Text(
              '恢复出厂设置',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}

/// 名单与原因库：进入后即可维护（改名会同步历史记录）。
