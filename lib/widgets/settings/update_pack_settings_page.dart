/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../settings_pages.dart';

/// 程序更新设置页：选择官方安装包并覆盖升级。
class UpdatePackSettingsPage extends StatefulWidget {
  const UpdatePackSettingsPage({super.key});

  @override
  State<UpdatePackSettingsPage> createState() => _UpdatePackSettingsPageState();
}

class _UpdatePackSettingsPageState extends State<UpdatePackSettingsPage> {
  bool _checking = false;

  Future<bool> _confirmUpdateAction(String reason) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    return _verifyForAction(
      context,
      provider,
      PasswordAction.updateRun,
      reason,
    );
  }

  /// 联网检查 GitHub 上的最新正式版。
  Future<void> _checkForUpdate() async {
    if (_checking) return;
    final verified = await _confirmUpdateAction('检查更新会访问 GitHub，请先进入班主任管理。');
    if (!verified || !mounted) return;
    setState(() => _checking = true);
    try {
      final release = await GitHubUpdateService.fetchLatestRelease();
      if (!mounted) return;
      if (!GitHubUpdateService.isNewerVersion(
        release.tagName,
        AppVersion.version,
      )) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('检查更新'),
            content: const Text('当前已是最新（${AppVersion.version}）。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      final asset = release.installerAsset;
      if (asset == null) {
        showTopSnackBar(context, '该版本没有可用的安装包', isError: true);
        return;
      }
      final notes = release.notes.isEmpty ? '（没有发布说明）' : release.notes;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('发现可用更新 ${release.tagName}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('当前版本：${AppVersion.version}'),
                  Text('可用版本：${release.tagName}'),
                  Text(
                    '安装包：${asset.name}'
                    '（${GitHubUpdateService.formatBytes(asset.size)}）',
                  ),
                  const SizedBox(height: 12),
                  Text(notes),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('稍后'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('下载并安装'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await _downloadAndInstall(release, asset);
      }
    } on GitHubUpdateException catch (e) {
      if (mounted) {
        showTopSnackBar(context, '检查更新失败：${e.message}', isError: true);
      }
    } on Object catch (e) {
      if (mounted) showTopSnackBar(context, '检查更新失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 下载、校验并交给安装器执行。
  Future<void> _downloadAndInstall(
    GitHubReleaseInfo release,
    GitHubAsset asset,
  ) async {
    final progress = ValueNotifier<({int received, int total})>(
      (received: 0, total: asset.size),
    );
    BuildContext? progressContext;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        progressContext = dialogContext;
        return AlertDialog(
          title: const Text('正在下载更新包'),
          content: SizedBox(
            width: 420,
            child: ValueListenableBuilder<({int received, int total})>(
              valueListenable: progress,
              builder: (context, value, child) {
                final total = value.total;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: total > 0 ? value.received / total : null,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      total > 0
                          ? '${GitHubUpdateService.formatBytes(value.received)}'
                                ' / ${GitHubUpdateService.formatBytes(total)}'
                          : GitHubUpdateService.formatBytes(value.received),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    try {
      final targetDir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}班级管理系统_更新',
      );
      await targetDir.create(recursive: true);
      final file = await GitHubUpdateService.downloadAsset(
        asset,
        targetDir: targetDir,
        onProgress: (received, total) {
          progress.value = (received: received, total: total);
        },
      );
      var digest = asset.digest;
      if (digest == null || !digest.toLowerCase().startsWith('sha256:')) {
        final checksumAsset = release.checksumAssetFor(asset);
        if (checksumAsset != null) {
          final text = await GitHubUpdateService.downloadText(checksumAsset);
          final parsed = GitHubUpdateService.parseChecksum(text, asset.name);
          if (parsed != null) digest = 'sha256:$parsed';
        }
      }
      if (digest == null || !digest.toLowerCase().startsWith('sha256:')) {
        throw const GitHubUpdateException('该版本未提供安装包校验值，已取消更新');
      }
      final verified = await GitHubUpdateService.verifyFileSha256(
        file,
        digest.substring(7),
      );
      if (!verified) {
        await file.delete();
        throw const GitHubUpdateException('安装包校验失败，文件可能不完整');
      }
      final contextForDialog = progressContext;
      if (contextForDialog != null && contextForDialog.mounted) {
        Navigator.of(contextForDialog).pop();
      }
      await dialogFuture;
      if (!mounted) return;
      await UpdateLauncher.launchAfterExit(file.path);
      if (!mounted) return;
      showTopSnackBar(context, '正在退出并自动更新，请稍候');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await DesktopService.instance.quitApp();
    } on Object catch (e) {
      final contextForDialog = progressContext;
      if (contextForDialog != null && contextForDialog.mounted) {
        Navigator.of(contextForDialog).pop();
      }
      if (mounted) showTopSnackBar(context, '更新失败：$e', isError: true);
    } finally {
      progress.dispose();
    }
  }

  /// 选择本地安装包并启动它（必须先退出本程序，安装程序才能替换文件）。
  /// 运行更新包会退出程序并覆盖安装，按“程序更新”策略校验密码。
  Future<void> _pickInstaller() async {
    final verified = await _confirmUpdateAction('运行更新包会退出程序并覆盖安装，请先进入班主任管理。');
    if (!verified || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择更新包（安装程序）',
      type: FileType.custom,
      allowedExtensions: ['exe', 'msi'],
    );
    final path = picked?.files.first.path;
    if (path == null || !mounted) return;
    final name = path.split(RegExp(r'[/\\]')).last;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('安装更新包'),
        content: Text(
          '即将运行安装程序：\n$name\n\n'
          '程序内更新会自动安装，本程序会先退出，安装成功后自动重新打开；'
          '安装失败或取消管理员授权时，程序也会重新打开并提示。\n\n'
          '如出现 Windows 管理员授权提示，请选择允许。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('开始更新'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await UpdateLauncher.launchAfterExit(path);
      if (!mounted) return;
      showTopSnackBar(context, '正在退出并自动更新，请稍候');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await DesktopService.instance.quitApp();
    } on Object catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, '启动更新程序失败：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionTitle('程序更新'),
        const SettingsHint(
          '可以直接联网检查 GitHub 上的正式发布版本，也可以选择本地安装包（.exe / .msi）更新：'
          '程序会先退出，自动完成安装，并在安装成功后重新打开。'
          '安装失败或取消管理员授权时，程序会重新打开并提示，'
          '详情可查看 %TEMP%\\班级管理系统_更新日志.txt。'
          '记录与设置保存在文档目录，不受影响。',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SettingsActionButton(
              label: _checking ? '正在检查…' : '检查更新',
              onPressed: _checking ? null : _checkForUpdate,
            ),
            const SizedBox(width: 10),
            SettingsActionButton(label: '选择更新包', onPressed: _pickInstaller),
          ],
        ),
      ],
    );
  }
}
