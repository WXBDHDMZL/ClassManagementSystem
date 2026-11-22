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

/// 关于页的更新区域：检查 GitHub 正式发布版本、下载并安装。
class AboutUpdateSection extends StatefulWidget {
  const AboutUpdateSection({super.key});

  @override
  State<AboutUpdateSection> createState() => _AboutUpdateSectionState();
}

class _AboutUpdateSectionState extends State<AboutUpdateSection> {
  bool _checking = false;

  /// 联网检查 GitHub 上的最新正式版。
  Future<void> _checkForUpdate() async {
    if (_checking) return;
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
            content: const Text('当前已是最新版（${AppVersion.version}）。'),
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
      await promptForUpdate(context, release);
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
                      onPressed: () => promptForUpdate(context, release),
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
