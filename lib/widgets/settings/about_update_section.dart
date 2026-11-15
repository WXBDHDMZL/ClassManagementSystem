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

/// 关于页的更新区域：检查 GitHub 正式发布版本、下载并安装。
class AboutUpdateSection extends StatefulWidget {
  const AboutUpdateSection({super.key});

  @override
  State<AboutUpdateSection> createState() => _AboutUpdateSectionState();
}

class _AboutUpdateSectionState extends State<AboutUpdateSection> {
  bool _checking = false;

  Future<bool> _confirmUpdateAction(String reason) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    return _verifyForAction(
      context,
      provider,
      PasswordAction.updateRun,
      reason,
      requireIdentity: false,
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
      await _promptInstall(release);
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

  /// 展示可用版本信息，确认后下载安装。
  Future<void> _promptInstall(GitHubReleaseInfo release) async {
    final asset = release.installerAsset;
    if (asset == null) {
      showTopSnackBar(context, '该版本没有可用的安装包', isError: true);
      return;
    }
    final notes = release.notes.isEmpty ? '（没有发布说明）' : release.notes;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('发现可用版本 ${release.tagName}'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<GitHubReleaseInfo?>(
          valueListenable: UpdateCheckService.availableRelease,
          builder: (context, release, child) {
            if (release == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.55,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.system_update_alt,
                      size: 18,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '发现可用版本 ${release.tagName}',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final verified = await _confirmUpdateAction(
                          '安装更新会退出程序并覆盖安装，请先进入班主任管理。',
                        );
                        if (verified && mounted) {
                          await _promptInstall(release);
                        }
                      },
                      child: const Text('查看'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SettingsHint(
          '联网检查 GitHub 上的正式发布版本，下载后校验安装包再自动安装；'
          '程序会先退出，安装成功后重新打开。记录与设置保存在文档目录，不受影响。',
        ),
        const SizedBox(height: 10),
        SettingsActionButton(
          label: _checking ? '正在检查…' : '检查更新',
          onPressed: _checking ? null : _checkForUpdate,
        ),
      ],
    );
  }
}
