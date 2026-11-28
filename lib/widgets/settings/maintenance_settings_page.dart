/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

part of '../settings_pages.dart';

/// 日志与维护页：数据文件位置、打开数据文件夹、日志查看/导出/清理。
class MaintenanceSettingsPage extends StatelessWidget {
  const MaintenanceSettingsPage({super.key});

  Future<void> _openFolder(BuildContext context, Directory directory) async {
    try {
      if (!await directory.exists()) await directory.create(recursive: true);
      await Process.run('explorer', [directory.path]);
    } on Object catch (e) {
      if (context.mounted) {
        showTopSnackBar(context, '打开文件夹失败：$e', isError: true);
      }
    }
  }

  Future<void> _cleanupLogs(
    BuildContext context,
    AppDataProvider provider,
  ) async {
    final verified = await _verifyForAction(
      context,
      provider,
      PasswordAction.logCleanup,
      '清理日志会删除历史日志，请先进入班主任管理。',
    );
    if (!verified || !context.mounted) return;
    final confirmed = await confirmDestructive(
      context,
      title: '清理旧日志',
      message: '将删除 6 个月前的操作日志与错误日志条目，'
          '最近 6 个月的日志保留。此操作不可撤销，确定继续吗？',
      confirmLabel: '确定清理',
    );
    if (confirmed != true || !context.mounted) return;
    final cutoff = AppClock.now().subtract(const Duration(days: 183));
    final file = LogFileService.fileIn(
      await LocalStoragePaths.logDirectory(),
    );
    final int removed;
    try {
      removed = await LogFileService.pruneBefore(file, cutoff);
    } on Object catch (e) {
      // 审计 A-23：清理旧日志此前没有兜底，IO 异常直接从 onPressed 逃逸，
      // 用户只看到按钮没反应。这里给出可见失败反馈。
      if (!context.mounted) return;
      showTopSnackBar(context, '清理旧日志失败：$e', isError: true);
      return;
    }
    if (!context.mounted) return;
    showTopSnackBar(context, '已清理 $removed 条旧日志');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);
    final provider = Provider.of<AppDataProvider>(context);
    final totalRecords = provider.totalRecordCount;
    final totalAttendance =
        AttendanceFeature.enabled ? provider.totalAttendanceCount : 0;
    final coveredDays = provider.appData.recordsByDate.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('数据文件'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                '位置',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            Expanded(
              child: _DataPathText(
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '共 $totalRecords 条记录，覆盖 $coveredDays 天'
          '${AttendanceFeature.enabled ? '；另有 $totalAttendance 条考勤异常记录' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SettingsActionButton(
              label: '打开数据文件夹',
              onPressed: () async {
                final root = await LocalStoragePaths.root();
                if (context.mounted) await _openFolder(context, root);
              },
            ),
            SettingsActionButton(
              label: '打开日志文件夹',
              onPressed: () async {
                final logs = await LocalStoragePaths.logDirectory();
                if (context.mounted) await _openFolder(context, logs);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        const SettingsHint(
          '数据、备份、日志都集中在「文档\\班级管理系统」。'
          '整机迁移请使用「手动备份」并同时保留 .enc 与 .pkey 文件；'
          '自动备份只能在本机当前 Windows 用户下恢复。',
        ),
        const SizedBox(height: 22),
        const SettingsSectionTitle('运行日志'),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: '查看操作日志',
                onPressed: () => OperationLogDialog.show(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsActionButton(
                label: '导出操作日志',
                onPressed: () => _exportOperationLog(context, provider),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SettingsActionButton(
                label: '导出错误日志',
                onPressed: () => _exportErrorLog(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _cleanupLogs(context, provider),
                child: Text(
                  '清理 6 个月前日志',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const SettingsHint(
          '日志在磁盘上均为加密文件；查看/导出时解密为明文，导出内容可能含学生姓名，请妥善保管。',
        ),
      ],
    );
  }
}
