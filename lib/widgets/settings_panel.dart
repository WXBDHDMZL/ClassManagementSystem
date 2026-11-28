/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.2
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';

import '../constants/app_version.dart';
import '../constants/attendance_feature.dart';
import '../services/security_service.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../providers/app_data_provider.dart';
import './password_action_guard.dart';
import './settings_pages.dart';
import '../constants/app_theme.dart';

/// 设置分组：管理组统一在标题上标锁，入口本身不再重复挂锁。
enum _SettingsGroup {
  daily('日常使用', false),
  records('记录与名单', true),
  timeAttendance('时间与考勤', true),
  data('数据管理', true),
  system('系统与安全', true),
  about('关于', false);

  const _SettingsGroup(this.label, this.requiresPassword);

  final String label;
  final bool requiresPassword;

  /// 侧栏分组标题。考勤入口隐藏时，分组不再提考勤。
  String get displayLabel =>
      this == _SettingsGroup.timeAttendance && !AttendanceFeature.enabled
      ? '时间'
      : label;
}

/// 设置入口。权限放在入口元数据上，侧栏与验证逻辑共用，避免两处漂移。
enum _SettingsSection {
  statistics('统计口径', Icons.insights_outlined, _SettingsGroup.daily, false),
  appearance('外观与窗口', Icons.palette_outlined, _SettingsGroup.daily, false),
  record('记录设置', Icons.edit_note_outlined, _SettingsGroup.records, true),
  listLibrary('名单与原因库', Icons.people_outline, _SettingsGroup.records, true),
  periods('时间段', Icons.schedule_outlined, _SettingsGroup.timeAttendance, true),
  attendance(
    '考勤',
    Icons.how_to_reg_outlined,
    _SettingsGroup.timeAttendance,
    true,
  ),
  data('导出与导入', Icons.folder_outlined, _SettingsGroup.data, true),
  backup('备份与恢复', Icons.backup_outlined, _SettingsGroup.data, true),
  identity('操作身份', Icons.badge_outlined, _SettingsGroup.system, true),
  security('安全与密码', Icons.lock_outline, _SettingsGroup.system, true),
  maintenance(
    '日志与维护',
    Icons.folder_open_outlined,
    _SettingsGroup.system,
    true,
  ),
  about('关于', Icons.info_outline, _SettingsGroup.about, false);

  const _SettingsSection(
    this.title,
    this.icon,
    this.group,
    this.requiresPassword,
  );

  final String title;
  final IconData icon;
  final _SettingsGroup group;
  final bool requiresPassword;
}

/// 设置面板：左侧分组导航，右侧显示当前设置页。
///
/// 保留单一面板内的主从布局，不另开窗口；管理组入口在切换前统一验证，
/// 取消密码时保持当前页，不出现空白内容区。
class SettingsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const SettingsPanel({
    super.key,
    required this.onClose,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  /// 默认打开免密码的统计口径，避免一进设置就弹密码框。
  _SettingsSection _selectedSection = _SettingsSection.statistics;

  Iterable<_SettingsSection> _sectionsFor(_SettingsGroup group) {
    return _SettingsSection.values.where((section) {
      if (section.group != group) return false;
      if (section == _SettingsSection.attendance &&
          !AttendanceFeature.enabled) {
        return false;
      }
      return true;
    });
  }

  /// 切换入口。验证成功后才改变选中项；取消时停留在原页面。
  Future<void> _selectSection(_SettingsSection section) async {
    if (section == _selectedSection) return;
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!await _authorize(section, provider)) return;
    if (!mounted) return;
    setState(() => _selectedSection = section);
  }

  Future<bool> _authorize(
    _SettingsSection section,
    AppDataProvider provider,
  ) async {
    if (!section.requiresPassword) return true;
    switch (section) {
      case _SettingsSection.identity:
        return ensureManagementMode(
          context,
          provider,
          message: '管理操作身份需要先进入班主任管理。',
        );
      case _SettingsSection.security:
        return ensureManagementMode(
          context,
          provider,
          message: '进入安全设置需要先进入班主任管理。',
        );
      default:
        return ensurePasswordForPage(
          context,
          provider,
          title: section.title,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.of(context).size;
    final width = clampDialogWidth(screen, 920);
    final height = clampDialogHeight(screen, 660);

    // 只订阅 settings：侧栏摘要与门禁状态都来自设置，记录变化不应重建面板。
    final settings = context.select<AppDataProvider, AppSettings>(
      (provider) => provider.appData.settings,
    );
    final managementActive = context.select<AppDataProvider, bool>(
      (provider) => provider.isManagementMode,
    );
    final locked = settings.passwordEnabled &&
        _selectedSection.requiresPassword &&
        !managementActive;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      backgroundColor: theme.colorScheme.surface,
      child: SizedBox(
        width: width,
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSidebar(theme, passwordEnabled: settings.passwordEnabled),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            Expanded(
              child: _buildContentPane(theme, settings, locked: locked),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme, {required bool passwordEnabled}) {
    final muted = mutedTextColor(theme, 0.6);
    return Container(
      width: 244,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设置',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '班级管理系统 ${AppVersion.version}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              children: [
                for (final group in _SettingsGroup.values)
                  if (group != _SettingsGroup.about) ...[
                    _groupHeader(
                      theme,
                      group,
                      passwordEnabled: passwordEnabled,
                    ),
                    for (final section in _sectionsFor(group))
                      _sidebarEntry(theme, section),
                  ],
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: _sidebarEntry(theme, _SettingsSection.about),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(
    ThemeData theme,
    _SettingsGroup group, {
    required bool passwordEnabled,
  }) {
    final muted = mutedTextColor(theme, 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Row(
        children: [
          Text(
            group.displayLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: theme.colorScheme.primary,
            ),
          ),
          if (group.requiresPassword && passwordEnabled) ...[
            const SizedBox(width: 5),
            Icon(Icons.lock_outline, size: 12, color: muted),
            const SizedBox(width: 3),
            Text(
              '需管理密码',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sidebarEntry(ThemeData theme, _SettingsSection section) {
    final selected = section == _selectedSection;
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => _selectSection(section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 18,
                  color: selected
                      ? theme.colorScheme.onSecondaryContainer
                      : mutedTextColor(theme, 0.7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentPane(
    ThemeData theme,
    AppSettings settings, {
    required bool locked,
  }) {
    final section = _selectedSection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locked
                          ? '管理会话已结束，此页面已锁定。'
                          : _sectionSummary(section, settings),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedTextColor(theme, 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                tooltip: '关闭',
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        Expanded(
          child: locked
              ? _buildLockedPage(theme)
              : SingleChildScrollView(
                  key: ValueKey<_SettingsSection>(section),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: _buildSectionPage(section),
                ),
        ),
      ],
    );
  }

  Widget _buildLockedPage(ThemeData theme) {
    final muted = mutedTextColor(theme, 0.65);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_clock_outlined,
              size: 42,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '管理会话已结束',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '为保护名单与记录，此页面已暂时隐藏。重新验证管理密码后可继续操作。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('settings-session-unlock'),
              onPressed: _unlockCurrentSection,
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('重新验证'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unlockCurrentSection() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!await _authorize(_selectedSection, provider)) return;
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildSectionPage(_SettingsSection section) {
    return switch (section) {
      _SettingsSection.statistics => const StatisticsSettingsPage(),
      _SettingsSection.appearance => const AppearanceWindowSettingsPage(),
      _SettingsSection.record => const RecordSettingsPage(),
      _SettingsSection.listLibrary => const ListLibrarySettingsPage(),
      _SettingsSection.periods => const PeriodSettingsPage(),
      _SettingsSection.attendance => const AttendanceSettingsPage(),
      _SettingsSection.data => const DataSettingsPage(),
      _SettingsSection.backup => const BackupSettingsPage(),
      _SettingsSection.identity => const IdentitySettingsPage(),
      _SettingsSection.security => const SecuritySettingsPage(),
      _SettingsSection.maintenance => const MaintenanceSettingsPage(),
      _SettingsSection.about => const AboutSettingsPage(),
    };
  }

  String _sectionSummary(_SettingsSection section, AppSettings settings) {
    switch (section) {
      case _SettingsSection.statistics:
        final weekStart = switch (settings.weekStart) {
          DateTime.sunday => '每周日',
          DateTime.saturday => '每周六',
          _ => '每周一',
        };
        return '$weekStart · 需关注阈值 · 排行 Top ${settings.rankingTopN}';
      case _SettingsSection.appearance:
        final scale = (settings.uiScale * 100).round();
        return '${_themeSummary(settings.themeMode)} · 字号 $scale% · '
            '搜索框${settings.studentSearchEnabled ? '已开' : '已关'} · '
            '${_closeSummary(settings.closeAction)} · '
            '${settings.showWeather ? '天气已开启' : '天气已关闭'}';
      case _SettingsSection.record:
        return _recordSummary(settings);
      case _SettingsSection.listLibrary:
        return '学生名单、表扬 / 批评原因';
      case _SettingsSection.periods:
        return '自定义各时段的名称与时间范围';
      case _SettingsSection.attendance:
        return _attendanceSummary(settings);
      case _SettingsSection.data:
        return '记录表格导入导出、学生名单导入、数据包';
      case _SettingsSection.backup:
        return _backupSummary(settings);
      case _SettingsSection.identity:
        return settings.identityFeatureEnabled
            ? '已启用 · ${settings.identities.length} 个身份'
            : '未启用（记录不标注身份）';
      case _SettingsSection.security:
        if (!settings.passwordEnabled) return '未设置管理密码';
        if (SecurityService.isUsingFactoryPassword(settings.passwordHash)) {
          return '正在使用出厂默认管理密码，建议尽快修改';
        }
        return '已设置管理密码';
      case _SettingsSection.maintenance:
        return '数据文件位置、日志查看/导出/清理';
      case _SettingsSection.about:
        return '班级管理系统 ${AppVersion.version}';
    }
  }

  String _themeSummary(ThemeModeType mode) {
    switch (mode) {
      case ThemeModeType.light:
        return '浅色';
      case ThemeModeType.dark:
        return '深色';
      case ThemeModeType.system:
        return '跟随系统';
    }
  }

  String _closeSummary(CloseActionType action) {
    switch (action) {
      case CloseActionType.ask:
        return '关闭时询问';
      case CloseActionType.exit:
        return '关闭即退出';
      case CloseActionType.minimizeToTray:
        return '最小化到托盘';
      case CloseActionType.minimizeToBall:
        return '最小化到悬浮球';
    }
  }

  String _recordSummary(AppSettings settings) {
    final type = switch (settings.recordDefaultType) {
      1 => '默认批评',
      2 => '默认上次类型',
      _ => '默认表扬',
    };
    return '$type · ${settings.autoSelectPeriod ? '自动预选时段' : '手动选时段'}';
  }

  String _attendanceSummary(AppSettings settings) {
    if (!settings.attendanceEnabled) return '已关闭';
    final count = settings.attendanceStatuses.length;
    return '默认全员到齐 · $count 个状态项';
  }

  String _backupSummary(AppSettings settings) {
    final frequency = switch (settings.backupFrequency) {
      BackupFrequency.manual => '仅手动备份',
      BackupFrequency.onExit => '每次退出备份',
      BackupFrequency.daily => '每天自动备份',
      BackupFrequency.everyThreeDays => '每 3 天自动备份',
      BackupFrequency.weekly => '每周自动备份',
    };
    if (settings.backupLastAt.isEmpty) return frequency;
    return '$frequency · 上次 ${settings.backupLastAt}';
  }
}
