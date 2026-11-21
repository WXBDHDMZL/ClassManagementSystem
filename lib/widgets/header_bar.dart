/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_notification.dart';
import 'identity_picker_dialog.dart';
import 'password_action_guard.dart';
import 'weather_city_dialog.dart';
import '../constants/app_theme.dart';
import '../models/identity.dart';
import '../providers/app_data_provider.dart';
import '../services/weather_service.dart';
import '../utils/app_date.dart';
import '../utils/app_clock.dart';

/// 顶部标题栏：标题与日期时间整体居中，设置入口固定于左上角。
class HeaderBar extends StatefulWidget {
  final VoidCallback? onSettingsPressed;

  const HeaderBar({
    super.key,
    this.onSettingsPressed,
  });

  @override
  State<HeaderBar> createState() => _HeaderBarState();
}

class _HeaderBarState extends State<HeaderBar> {
  static const List<String> _weekdays = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  Timer? _timer;
  String _dateTimeText = _formatDateTime(AppClock.now());

  @override
  void initState() {
    super.initState();
    // 每秒检查一次，仅在分钟变化时才刷新，保证时间准确且重建开销极小。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final text = _formatDateTime(AppClock.now());
      if (text != _dateTimeText && mounted) {
        setState(() => _dateTimeText = text);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 格式：2026年09月25日 星期五 14:32
  static String _formatDateTime(DateTime now) {
    final month = twoDigit(now.month);
    final day = twoDigit(now.day);
    final hour = twoDigit(now.hour);
    final minute = twoDigit(now.minute);
    return '${now.year}年$month月$day日 '
        '${_weekdays[now.weekday - 1]} $hour:$minute';
  }

  Future<void> _toggleManagement(BuildContext context) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (provider.isManagementMode) {
      provider.exitManagementMode();
      showTopSnackBar(context, '已退出班主任管理');
      return;
    }
    final ok = await ensureManagementMode(
      context,
      provider,
      message: '进入班主任管理后可修改他人记录、导入数据或调整设置。',
    );
    if (ok && context.mounted) {
      showTopSnackBar(
        context,
        '已进入班主任管理（${provider.appData.settings.managementSessionMinutes} 分钟）',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identityEnabled = context.select<AppDataProvider, bool>(
      (provider) => provider.appData.settings.identityFeatureEnabled,
    );
    final activeIdentity = context.select<AppDataProvider, Identity?>(
      (provider) => provider.activeIdentity,
    );
    final managementActive = context.select<AppDataProvider, bool>(
      (provider) => provider.isManagementMode,
    );
    final showWeather = context.select<AppDataProvider, bool>(
      (provider) => provider.appData.settings.showWeather,
    );

    return Container(
      height: 80,
      // 说明：高度 80 是主界面顶栏的固定高度，天气与日期同一行显示。
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.semantic.subtleBorder)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 必须用 Positioned.fill 铺满，否则 Stack 会按左上角对齐该子项，
          // 导致标题偏左并与左上角的设置按钮重叠。
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '班级管理系统',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _dateTimeText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedTextColor(theme, 0.6),
                      ),
                    ),
                    if (showWeather) ...[
                      const SizedBox(width: 10),
                      const Flexible(child: _WeatherSummary()),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (identityEnabled)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: _IdentityChip(identity: activeIdentity)),
            ),
          if (widget.onSettingsPressed != null)
            Positioned(
              left: 0,
              top: 6,
              child: IconButton(
                icon: const Icon(Icons.settings),
                onPressed: widget.onSettingsPressed,
                tooltip: '设置',
              ),
            ),
          Positioned(
              left: widget.onSettingsPressed != null ? 44 : 0,
              top: 6,
              child: IconButton(
                icon: Icon(
                  managementActive
                      ? Icons.admin_panel_settings
                      : Icons.lock_outline,
                  color: managementActive ? theme.colorScheme.primary : null,
                ),
                onPressed: () => _toggleManagement(context),
                tooltip: managementActive ? '退出班主任管理' : '进入班主任管理',
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶栏右上角的当前记录人入口。
class _IdentityChip extends StatelessWidget {
  const _IdentityChip({required this.identity});

  final Identity? identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final none = identity == null;
    final foreground =
        none ? theme.colorScheme.error : theme.colorScheme.primary;
    return Tooltip(
      message: '切换操作身份',
      child: Material(
        color: none
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.40)
            : theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showIdentityPicker(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, maxWidth: 168),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    none
                        ? Icons.person_search_outlined
                        : Icons.person_pin_circle_outlined,
                    size: 18,
                    color: foreground,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      identity?.displayLabel ?? '未选择操作身份',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏天气：随设置的地区拉取当前天气，点击可更换地区。
class _WeatherSummary extends StatefulWidget {
  const _WeatherSummary();

  @override
  State<_WeatherSummary> createState() => _WeatherSummaryState();
}

class _WeatherSummaryState extends State<_WeatherSummary> {
  final WeatherService _service = WeatherService();
  Timer? _refreshTimer;
  String _cityKey = '';
  String _cityName = '';
  double _latitude = 0;
  double _longitude = 0;
  bool _loading = false;
  bool _failed = false;
  WeatherSnapshot? _snapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings =
        Provider.of<AppDataProvider>(context).appData.settings;
    final key = '${settings.weatherCityName}|${settings.weatherLatitude}|'
        '${settings.weatherLongitude}';
    if (key == _cityKey) return;
    _cityKey = key;
    _refreshTimer?.cancel();
    _snapshot = null;
    _failed = false;
    _cityName = settings.weatherCityName;
    _latitude = settings.weatherLatitude;
    _longitude = settings.weatherLongitude;
    if (_cityName.isEmpty) {
      _loading = false;
      return;
    }
    _loading = true;
    unawaited(_fetch());
    // Open-Meteo 当前天气约每 15 分钟更新一次，刷新间隔与数据源保持一致。
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_fetch()),
    );
  }

  Future<void> _fetch() async {
    final key = _cityKey;
    if (_cityName.isEmpty) return;
    try {
      final snapshot = await _service.fetchCurrent(_latitude, _longitude);
      if (!mounted || key != _cityKey) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _failed = snapshot == null;
      });
    } catch (_) {
      if (!mounted || key != _cityKey) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _chooseCity() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const WeatherCityDialog(),
    );
  }

  IconData _iconFor(WeatherSnapshot? snapshot) {
    if (snapshot == null) return Icons.cloud_off_outlined;
    switch (WeatherService.kindForCode(snapshot.code)) {
      case WeatherKind.clear:
        return snapshot.isDay
            ? Icons.wb_sunny_outlined
            : Icons.nightlight_outlined;
      case WeatherKind.partlyCloudy:
        return snapshot.isDay
            ? Icons.wb_cloudy_outlined
            : Icons.nights_stay_outlined;
      case WeatherKind.cloudy:
        return Icons.cloud_outlined;
      case WeatherKind.fog:
        return Icons.foggy;
      case WeatherKind.drizzle:
      case WeatherKind.rain:
      case WeatherKind.showers:
        return Icons.water_drop_outlined;
      case WeatherKind.freezingRain:
      case WeatherKind.snow:
        return Icons.ac_unit;
      case WeatherKind.thunderstorm:
        return Icons.thunderstorm_outlined;
      case WeatherKind.unknown:
        return Icons.cloud_queue;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedTextColor(theme, 0.64);
    final String label;
    final IconData icon;
    if (_cityName.isEmpty) {
      icon = Icons.add_location_alt_outlined;
      label = '设置天气地区';
    } else if (_loading && _snapshot == null) {
      icon = Icons.cloud_queue;
      label = '天气获取中…';
    } else if (_snapshot == null) {
      icon = Icons.cloud_off_outlined;
      label = _failed ? '天气暂不可用' : '天气获取中…';
    } else {
      final snapshot = _snapshot!;
      icon = _iconFor(snapshot);
      label = '$_cityName ${WeatherService.descriptionForCode(snapshot.code)} '
          '${snapshot.temperature.toStringAsFixed(1)}°C';
    }

    return Tooltip(
      message: '点击更换天气地区',
      child: InkWell(
        onTap: _chooseCity,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
