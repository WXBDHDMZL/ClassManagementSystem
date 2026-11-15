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
part of '../settings_pages.dart';

/// 立即备份/出厂重置/从备份恢复（含 _RestorePickDialog）与记录导入。
/// 立即备份（每次生成一份带时间的备份，按设置保留最近若干份）。
Future<void> _performBackup(
  BuildContext context,
  AppDataProvider provider,
) async {
  final verified = await ensurePasswordForAction(
    context,
    provider,
    PasswordAction.backupManual,
    message: '手动备份会写入一份本机数据备份，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;
  final result = await provider.performBackup();
  if (!context.mounted) return;
  if (!result.isSuccess) {
    showTopSnackBar(context, result.error!, isError: true);
    return;
  }
  showTopSnackBar(context, '备份成功: ${result.savedPath}');
}

/// 恢复出厂：密码校验 + 两次确认后清空数据并恢复出厂内容。
Future<void> _factoryReset(
  BuildContext context,
  AppDataProvider provider,
) async {
  final verified = await _verifyForAction(
    context,
    provider,
    PasswordAction.factoryReset,
    '恢复出厂会清空全部数据，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;

  final firstConfirmed = await confirmDestructive(
    context,
    title: '恢复出厂设置',
    message:
        '将清空全部记录${AttendanceFeature.enabled ? '与考勤' : ''}，并恢复出厂学生名单、原因库与默认设置。\n'
        '管理密码与操作身份设置也会被清除。\n'
        '此操作不可撤销，建议先导出备份。确定继续吗？',
    confirmLabel: '继续',
  );
  if (!firstConfirmed || !context.mounted) return;

  final secondConfirmed = await confirmDestructiveWithOption(
    context,
    title: '再次确认',
    message: '真的要清空全部数据并恢复出厂设置吗？',
    optionLabel: '同时清除全部备份与日志',
    optionHint: '会删除备份目录中的全部备份文件（含本次恢复前自动生成的备份）与本机运行日志。',
    cancelLabel: '再想想',
    confirmLabel: '确认恢复出厂',
  );
  if (secondConfirmed == null || !secondConfirmed.confirmed || !context.mounted) {
    return;
  }
  final clearBackupsAndLogs = secondConfirmed.option;
  // B-10：破坏性操作前自动备份；失败则中止。
  if (!await _autoBackupBeforeDestructive(context, provider)) return;
  if (!context.mounted) return;
  // 备份位置可能是用户自定义目录；恢复出厂会重置设置，若不保留该路径，
  // 刚生成的自动备份会在“从备份恢复”列表里消失（只能手动浏览找回）。
  final backupPath = provider.appData.settings.backupPath;
  provider.factoryReset();
  if (backupPath.isNotEmpty) provider.setBackupPath(backupPath);
  final saved = await provider.saveNow();
  if (!context.mounted) return;
  if (!saved) {
    showTopSnackBar(context, '数据落盘失败，请检查磁盘空间或文件权限', isError: true);
    return;
  }
  // 恢复出厂会关闭开机启动；同步清理注册表，避免下次开机仍自动启动。
  await DesktopService.reconcileAutoStart(false, StartupTarget.tray);
  if (clearBackupsAndLogs) {
    await provider.clearAllBackups();
    // 主数据旁的 .bak 不算“备份目录里的文件”，但同样保存着完整的旧数据；
    // 既然用户选择清除全部备份，就必须一并删掉，否则仍可一键恢复。
    await provider.clearDataBackup();
    await OperationLogService.flush();
    await flushErrorLogs();
    await LogFileService.deleteAllLogs(
      await LocalStoragePaths.logDirectory(),
    );
  }
  if (!context.mounted) return;
  showTopSnackBar(
    context,
    clearBackupsAndLogs ? '已恢复出厂设置，并清除全部备份与日志' : '已恢复出厂设置',
  );
}

/// 从备份恢复：先选备份文件（默认列出备份位置里的文件，也可浏览其它位置），
/// 再输入管理密码并确认，最后整体覆盖恢复。
Future<void> _restoreFromBackup(
  BuildContext context,
  AppDataProvider provider,
) async {
  final backups = await provider.listBackupFiles();
  if (!context.mounted) return;

  final sourcePath = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _RestorePickDialog(backups: backups),
  );
  if (sourcePath == null || !context.mounted) return;

  final verified = await _verifyForAction(
    context,
    provider,
    PasswordAction.backupRestore,
    '从备份恢复会覆盖现有全部数据，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;

  final logSnapshot = File('$sourcePath.logs');
  final hasLogSnapshot = await logSnapshot.exists();
  if (!context.mounted) return;
  var restoreLogs = false;
  if (hasLogSnapshot) {
    final result = await confirmDestructiveWithOption(
      context,
      title: '从备份恢复',
      message: '恢复将覆盖当前全部记录与设置，且不可撤销。\n'
          '备份里的管理密码与操作身份设置也会一并恢复。确定继续吗？',
      optionLabel: '同时恢复日志',
      optionHint: '把备份里的日志合并进当前日志，只补充缺少的条目，不会删除较新的日志。',
      confirmLabel: '确定恢复',
    );
    if (result == null || !result.confirmed || !context.mounted) return;
    restoreLogs = result.option;
  } else {
    final confirmed = await confirmDestructive(
      context,
      title: '从备份恢复',
      message: '恢复将覆盖当前全部记录与设置，且不可撤销。\n'
          '备份里的管理密码与操作身份设置也会一并恢复。确定继续吗？',
      confirmLabel: '确定恢复',
    );
    if (!confirmed || !context.mounted) return;
  }
  // B-10：覆盖前先自动备份当前数据；失败则中止，避免无退路。
  if (!await _autoBackupBeforeDestructive(context, provider)) return;
  if (!context.mounted) return;
  final error = await provider.restoreBackupFrom(sourcePath);
  String? logError;
  if (error == null) {
    // 恢复后确认落盘，再显示成功（避免“提示成功但写盘失败”）。
    final saved = await provider.saveNow();
    if (!context.mounted) return;
    if (!saved) {
      showTopSnackBar(context, '恢复后保存失败，请检查磁盘空间或文件权限', isError: true);
      return;
    }
    // 备份里可能包含不同的开机启动设置，恢复后立即同步注册表。
    await DesktopService.reconcileAutoStart(
      provider.appData.settings.autoStart,
      provider.appData.settings.startupTarget,
    );
    if (restoreLogs) {
      logError = await provider.restoreLogsFromSnapshot(sourcePath);
    }
  }
  if (!context.mounted) return;
  final message = error ??
      (logError != null
          ? '已从备份恢复数据；$logError'
          : restoreLogs
              ? '已从备份恢复数据与日志'
              : '已从备份恢复数据');
  showTopSnackBar(context, message, isError: error != null || logError != null);
}

/// 选择要恢复的备份文件：列出备份位置里的文件，也可以浏览其它位置。
class _RestorePickDialog extends StatelessWidget {
  const _RestorePickDialog({required this.backups});

  final List<BackupFileInfo> backups;

  String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.65);

    return AlertDialog(
      title: const Text('选择要恢复的备份'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (backups.isEmpty)
              Text(
                '备份位置里还没有备份文件，可点下面的"浏览其他备份文件"选择。',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: backups.length,
                  itemBuilder: (context, index) {
                    final backup = backups[index];
                    final time = backup.modifiedAt.toString().split('.').first;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.archive_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        backup.name,
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        '$time · ${_sizeText(backup.sizeBytes)}'
                        '${backup.hasLogSnapshot ? ' · 含日志' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, backup.path),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final picked = await FilePicker.platform.pickFiles(
                    dialogTitle: '选择备份文件',
                    type: FileType.custom,
                    allowedExtensions: ['enc'],
                  );
                  final path = picked?.files.first.path;
                  if (path == null || !context.mounted) return;
                  Navigator.pop(context, path);
                },
                child: const Text('浏览其他备份文件…'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 导入记录：输入密码 → 选择表格 → 解析预览 → 确认写入。
Future<void> _importRecords(
  BuildContext context,
  AppDataProvider provider,
) async {
  final verified = await _verifyForAction(
    context,
    provider,
    PasswordAction.recordImport,
    '导入记录会向数据里追加内容，请先进入班主任管理。',
  );
  if (!verified || !context.mounted) return;

  final picked = await _pickTableFile(context, dialogTitle: '选择要导入的记录表格');
  if (picked == null || !context.mounted) return;

  final existing = provider.getRecordsForDates(provider.getHistoryDates());
  // CSV 只接受 UTF-8：非 UTF-8（Excel 默认另存的 GBK/ANSI）直接报错并给出
  // "另存为 CSV UTF-8" 的指引，绝不能 allowMalformed 静默导入乱码。
  final ImportPreview preview;
  if (picked.isCsv) {
    final String text;
    try {
      text = TransferService.decodeCsv(picked.bytes);
    } on FormatException catch (e) {
      if (!context.mounted) return;
      showTopSnackBar(context, e.message, isError: true);
      return;
    }
    // 性能批 H4：解析（含全表判重）移入后台 isolate，大文件不再冻结界面；
    // 异常语义不变（解析内部已兜底为 ImportPreview.error）。
    preview = await ImportService.parseCsvTextAsync(text, existing: existing);
  } else {
    preview = await ImportService.parseExcelBytesAsync(
      picked.bytes,
      existing: existing,
    );
  }

  if (!context.mounted) return;
  if (preview.hasError) {
    showTopSnackBar(context, preview.error!, isError: true);
    return;
  }
  if (!preview.hasData) {
    showTopSnackBar(
      context,
      preview.duplicates.isEmpty ? '表格里没有可导入的记录' : '表格里的记录与现有记录完全相同，无需导入',
      isError: true,
    );
    return;
  }
  await ImportRecordsDialog.show(
    context,
    fileName: picked.name,
    preview: preview,
  );
}

/// 数据文件路径文本：缓存异步查询结果，文本可选中以便复制。
