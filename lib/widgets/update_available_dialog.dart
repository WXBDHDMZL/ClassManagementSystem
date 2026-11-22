/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../constants/app_version.dart';
import '../providers/app_data_provider.dart';
import '../services/desktop_service.dart';
import '../services/github_update_service.dart';
import '../services/update_launcher.dart';
import '../utils/release_notes.dart';
import 'app_notification.dart';

/// 更新弹窗的操作结果。
enum UpdateAvailableAction { later, skip, install }

/// 显示更新弹窗；返回 null 表示用户直接关闭了弹窗。
Future<UpdateAvailableAction?> showUpdateAvailableDialog(
  BuildContext context, {
  required GitHubReleaseInfo release,
  bool allowSkip = true,
}) {
  return showDialog<UpdateAvailableAction>(
    context: context,
    builder: (dialogContext) =>
        _UpdateAvailableDialog(release: release, allowSkip: allowSkip),
  );
}

/// 显示更新弹窗，并按用户选择执行跳过或下载安装。
Future<void> promptForUpdate(
  BuildContext context,
  GitHubReleaseInfo release, {
  bool allowSkip = true,
}) async {
  final action = await showUpdateAvailableDialog(
    context,
    release: release,
    allowSkip: allowSkip,
  );
  if (!context.mounted) return;
  if (action == null || action == UpdateAvailableAction.later) return;
  if (action == UpdateAvailableAction.skip) {
    context.read<AppDataProvider>().setSkippedUpdateTag(release.tagName);
    return;
  }
  await downloadAndInstallUpdate(context, release);
}

/// 下载、校验并启动安装器；安装前会退出当前程序。
Future<void> downloadAndInstallUpdate(
  BuildContext context,
  GitHubReleaseInfo release,
) async {
  final asset = release.installerAsset;
  if (asset == null) {
    showTopSnackBar(context, '该版本暂未提供安装包', isError: true);
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<({int received, int total})>((
    received: 0,
    total: asset.size,
  ));
  // 先建目录：这一步在弹进度框之前完成，避免“对话框还没渲染就抛异常”
  // 留下一个 barrierDismissible=false 且没有按钮的死框（审计 P1-16）。
  final targetDir = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}班级管理系统_更新',
  );
  try {
    await targetDir.create(recursive: true);
  } on Object catch (e) {
    if (context.mounted) {
      showTopSnackBar(context, '更新失败：$e', isError: true);
    }
    return;
  }
  if (!context.mounted) return;
  BuildContext? progressContext;
  var progressDialogOpen = true;
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      progressContext = dialogContext;
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.downloading, size: 20),
            SizedBox(width: 8),
            Text('正在下载安装包'),
          ],
        ),
        content: SizedBox(
          width: 360,
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
    // 等首帧把进度框真正挂到树上，再开始可能同步抛错的下载调用。
    await WidgetsBinding.instance.endOfFrame;
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
    final signatureAsset = release.signatureAssetFor(asset);
    if (signatureAsset == null) {
      await file.delete();
      throw const GitHubUpdateException('该版本未提供安装包签名，已取消更新');
    }
    final signature = await GitHubUpdateService.downloadText(signatureAsset);
    final signatureOk = await GitHubUpdateService.verifyFileSignature(
      file,
      signature,
    );
    if (!signatureOk) {
      await file.delete();
      throw const GitHubUpdateException('安装包签名校验失败，已取消更新');
    }
    final contextForDialog = progressContext;
    if (progressDialogOpen &&
        contextForDialog != null &&
        contextForDialog.mounted) {
      progressDialogOpen = false;
      navigator.pop();
    }
    await dialogFuture;
    await UpdateLauncher.launchAfterExit(file.path);
    if (context.mounted) {
      showTopSnackBar(context, '正在退出并自动安装，请稍候');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await DesktopService.instance.quitApp();
  } on Object catch (e) {
    if (progressDialogOpen) {
      progressDialogOpen = false;
      // 即使 builder 尚未执行（progressContext 为 null），showDialog 的路由
      // 也已经压栈，必须 pop 掉，否则进度框会永久卡死。
      navigator.pop();
      await dialogFuture;
    }
    if (context.mounted) {
      showTopSnackBar(context, '更新失败：$e', isError: true);
    }
  } finally {
    progress.dispose();
  }
}

class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({
    required this.release,
    required this.allowSkip,
  });

  final GitHubReleaseInfo release;
  final bool allowSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final asset = release.installerAsset;
    final visibleNotes = ReleaseNotes.forApp(release.notes);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              gradient: theme.semantic.brandGradient,
            ),
            child: Icon(
              Icons.system_update_alt,
              size: 22,
              color: theme.semantic.onBrand,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '发现可用版本',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '可以从 GitHub 获取安装包并自动安装',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _VersionChip(label: '当前版本', value: AppVersion.version),
                Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
                _VersionChip(
                  label: '可用版本',
                  value: release.tagName,
                  highlighted: true,
                ),
              ],
            ),
            if (asset != null) ...[
              const SizedBox(height: 8),
              Text(
                '安装包 ${asset.name} · '
                '${GitHubUpdateService.formatBytes(asset.size)}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            if (visibleNotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '版本内容',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: _ReleaseNotesText(notes: visibleNotes),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, UpdateAvailableAction.later),
          child: const Text('稍后'),
        ),
        if (allowSkip)
          TextButton(
            onPressed: () => Navigator.pop(context, UpdateAvailableAction.skip),
            child: const Text('跳过此版本'),
          ),
        FilledButton(
          onPressed: asset == null
              ? null
              : () => Navigator.pop(context, UpdateAvailableAction.install),
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}

/// 把 GitHub Release 正文按轻量 Markdown 呈现为可滚动文本。
///
/// 只处理标题、列表与 **加粗**，不引入 Markdown 依赖；未知语法原样显示。
class _ReleaseNotesText extends StatelessWidget {
  const _ReleaseNotesText({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      height: 1.55,
      color: theme.colorScheme.onSurface,
    );
    final children = <Widget>[];
    final normalized = notes.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final raw in normalized.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        children.add(const SizedBox(height: 5));
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: children.isEmpty ? 0 : 6,
              bottom: 2,
            ),
            child: Text(
              heading.group(2)!.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: level == 1 ? 14 : 13,
              ),
            ),
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(line);
      if (bullet != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: base),
                Expanded(child: _richLine(bullet.group(1)!.trim(), base)),
              ],
            ),
          ),
        );
        continue;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _richLine(line, base),
        ),
      );
    }
    while (children.isNotEmpty && children.last is SizedBox) {
      children.removeLast();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _richLine(String text, TextStyle? style) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = highlighted
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final foreground = highlighted
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: highlighted
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
