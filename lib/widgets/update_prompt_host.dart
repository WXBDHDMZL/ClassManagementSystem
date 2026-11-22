/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-11-21
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_data_provider.dart';
import '../services/github_update_service.dart';
import '../services/update_check_service.dart';
import 'update_available_dialog.dart';

/// 在应用根部监听启动检查结果，有可用版本时弹出更新提示。
///
/// 启动到托盘或悬浮球时不弹窗，避免提示出现在隐藏的主窗口里；此时仍可
/// 从「设置 → 关于」手动检查。
class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  final Set<String> _promptedTags = <String>{};
  bool _prompting = false;

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AppDataProvider, bool>(
      (provider) => provider.appData.settings.checkUpdateOnStartup,
    );
    final skippedTag = context.select<AppDataProvider, String>(
      (provider) => provider.appData.settings.skippedUpdateTag,
    );
    return ValueListenableBuilder<GitHubReleaseInfo?>(
      valueListenable: UpdateCheckService.availableRelease,
      builder: (context, release, child) {
        if (release != null &&
            enabled &&
            release.tagName != skippedTag &&
            !_startsInBackground) {
          _schedulePrompt(release);
        }
        return widget.child;
      },
    );
  }

  void _schedulePrompt(GitHubReleaseInfo release) {
    if (_prompting || _promptedTags.contains(release.tagName)) return;
    _promptedTags.add(release.tagName);
    _prompting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // 等启动遮罩淡出后再弹，避免提示盖住首屏加载。
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        final settings = context.read<AppDataProvider>().appData.settings;
        if (!settings.checkUpdateOnStartup ||
            settings.skippedUpdateTag == release.tagName) {
          return;
        }
        await promptForUpdate(context, release);
      } finally {
        if (mounted) _prompting = false;
      }
    });
  }

  bool get _startsInBackground {
    final target = Platform.environment['CMS_STARTUP_TARGET'];
    if (target == 'tray' || target == 'ball') return true;
    final arguments = Platform.executableArguments;
    return arguments.contains('--tray') || arguments.contains('--ball');
  }
}
