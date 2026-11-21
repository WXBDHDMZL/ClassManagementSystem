/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_theme.dart';
import '../providers/app_data_provider.dart';
import '../services/weather_service.dart';

/// 天气地区选择：搜索城市并写入设置；只发送城市名/坐标，不涉及学生数据。
class WeatherCityDialog extends StatefulWidget {
  const WeatherCityDialog({super.key});

  @override
  State<WeatherCityDialog> createState() => _WeatherCityDialogState();
}

class _WeatherCityDialogState extends State<WeatherCityDialog> {
  final WeatherService _service = WeatherService();
  final TextEditingController _controller = TextEditingController();
  List<WeatherCity> _results = const [];
  bool _loading = false;
  bool _searched = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _searched = true;
      _failed = false;
      _results = const [];
    });
    try {
      final results = await _service.searchCities(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _select(WeatherCity city) {
    Provider.of<AppDataProvider>(context, listen: false).setWeatherLocation(
      name: city.name,
      admin: city.admin,
      latitude: city.latitude,
      longitude: city.longitude,
    );
    Navigator.pop(context);
  }

  void _clear() {
    Provider.of<AppDataProvider>(context, listen: false)
        .setWeatherLocation(name: '');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<AppDataProvider>(context).appData.settings;
    final muted = mutedTextColor(theme, 0.62);

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('选择天气地区',
                        style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '天气数据来自 Open-Meteo；地区搜索来自 OpenStreetMap，支持镇、乡、村。'
                '只上传搜索词与坐标，不涉及任何学生数据。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
              ),
              if (settings.weatherCityName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '当前：${settings.weatherCityName}'
                  '${settings.weatherCityAdmin.isEmpty ? '' : ' · ${settings.weatherCityAdmin}'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: '输入城市、镇或乡名，例如：北京、三墩镇、乌镇',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _loading ? null : _search,
                    tooltip: '搜索',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '搜索失败，请检查网络后重试',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else if (_searched && !_loading && _results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '没有找到城市，换个名称试试',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              if (_results.isNotEmpty)
                SizedBox(
                  height: 260,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final city = _results[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_city, size: 20),
                        title: Text(city.name),
                        subtitle: city.subtitle.isEmpty
                            ? null
                            : Text(
                                city.subtitle,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted),
                              ),
                        onTap: () => _select(city),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (settings.weatherCityName.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.location_off_outlined, size: 18),
                      label: const Text('清除地区'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
