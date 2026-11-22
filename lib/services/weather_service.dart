/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 城市搜索结果。天气数据来自 Open-Meteo，只发送城市名/坐标，不涉及学生数据。
class WeatherCity {
  const WeatherCity({
    required this.name,
    required this.admin,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String admin;
  final String country;
  final double latitude;
  final double longitude;

  String get subtitle {
    final parts = <String>[
      if (admin.isNotEmpty && admin != name) admin,
      if (country.isNotEmpty) country,
    ];
    return parts.join(' · ');
  }
}

/// 当前天气。temperature 为摄氏度，code 为 WMO 天气代码。
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperature,
    required this.code,
    required this.isDay,
  });

  final double temperature;
  final int code;
  final bool isDay;
}

enum WeatherKind {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  freezingRain,
  snow,
  showers,
  thunderstorm,
  unknown,
}

/// Open-Meteo 天气服务：无需 API Key；城市搜索与当前天气各一个接口。
class WeatherService {
  static const String _photonBase = 'photon.komoot.io';
  static const String _geocodingBase = 'geocoding-api.open-meteo.com';
  static const String _forecastBase = 'api.open-meteo.com';

  /// 搜索地区：优先 Photon（OpenStreetMap，支持镇/乡/村），
  /// 失败或无结果时回退到 Open-Meteo 的城市库。
  Future<List<WeatherCity>> searchCities(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    try {
      final results = await _searchPhoton(keyword);
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('Photon 地区搜索失败，回退 Open-Meteo：$e');
    }
    return _searchOpenMeteo(keyword);
  }

  Future<List<WeatherCity>> _searchPhoton(String keyword) async {
    final uri = Uri.https(_photonBase, '/api/', {
      'q': keyword,
      'limit': '15',
    });
    final raw = await _get(uri);
    return parsePhotonResponse(raw);
  }

  /// 解析 Photon 的 GeoJSON：只保留城市/镇/乡/村等居民点与管理边界，
  /// 过滤掉幼儿园、公交站、铁路等恰好同名的无关地点。
  static List<WeatherCity> parsePhotonResponse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];
    const allowedTypes = {
      'city',
      'town',
      'village',
      'hamlet',
      'suburb',
      'neighbourhood',
      'district',
      'county',
      'state',
      'province',
      'region',
      'locality',
    };
    final cities = <WeatherCity>[];
    final seen = <String>{};
    for (final feature in features) {
      if (feature is! Map<String, dynamic>) continue;
      final properties = feature['properties'];
      final geometry = feature['geometry'];
      if (properties is! Map<String, dynamic> ||
          geometry is! Map<String, dynamic>) {
        continue;
      }
      final name = (properties['name'] ?? '').toString().trim();
      final coordinates = geometry['coordinates'];
      if (name.isEmpty || coordinates is! List || coordinates.length < 2) {
        continue;
      }
      final longitude = (coordinates[0] as num?)?.toDouble();
      final latitude = (coordinates[1] as num?)?.toDouble();
      if (latitude == null || longitude == null) continue;
      final osmKey = (properties['osm_key'] ?? '').toString();
      final type = (properties['type'] ?? '').toString();
      if (osmKey != 'place' &&
          osmKey != 'boundary' &&
          !allowedTypes.contains(type)) {
        continue;
      }
      final adminParts = <String>[];
      for (final key in const ['state', 'city', 'county', 'district']) {
        final value = (properties[key] ?? '').toString().trim();
        if (value.isEmpty || value == name) continue;
        if (!adminParts.contains(value)) adminParts.add(value);
      }
      final admin = adminParts.join(' · ');
      final city = WeatherCity(
        name: name,
        admin: admin,
        country: (properties['country'] ?? '').toString(),
        latitude: latitude,
        longitude: longitude,
      );
      final dedupeKey = '${city.name}|${city.admin}|'
          '${city.latitude.toStringAsFixed(4)}|'
          '${city.longitude.toStringAsFixed(4)}';
      if (!seen.add(dedupeKey)) continue;
      cities.add(city);
      if (cities.length >= 12) break;
    }
    return cities;
  }

  Future<List<WeatherCity>> _searchOpenMeteo(String keyword) async {
    final uri = Uri.https(_geocodingBase, '/v1/search', {
      'name': keyword,
      'count': '8',
      'language': 'zh',
      'format': 'json',
    });
    final raw = await _get(uri);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const [];
    final results = decoded['results'];
    if (results is! List) return const [];
    final cities = <WeatherCity>[];
    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] ?? '').toString().trim();
      final latitude = (item['latitude'] as num?)?.toDouble();
      final longitude = (item['longitude'] as num?)?.toDouble();
      if (name.isEmpty || latitude == null || longitude == null) continue;
      cities.add(
        WeatherCity(
          name: name,
          admin: (item['admin1'] ?? '').toString(),
          country: (item['country'] ?? '').toString(),
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    return cities;
  }

  Future<WeatherSnapshot?> fetchCurrent(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.https(_forecastBase, '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'current': 'temperature_2m,weather_code,is_day',
      'timezone': 'auto',
    });
    final raw = await _get(uri);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final current = decoded['current'];
    if (current is! Map<String, dynamic>) return null;
    final temperature = (current['temperature_2m'] as num?)?.toDouble();
    final code = (current['weather_code'] as num?)?.toInt();
    if (temperature == null || code == null) return null;
    return WeatherSnapshot(
      temperature: temperature,
      code: code,
      isDay: (current['is_day'] as num?)?.toInt() == 1,
    );
  }

  Future<String> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ClassManagementSystem/2.33.1 (desktop)',
      );
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('天气接口返回 ${response.statusCode}', uri: uri);
      }
      return body;
    } catch (e) {
      debugPrint('天气请求失败：$e');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static WeatherKind kindForCode(int code) {
    switch (code) {
      case 0:
        return WeatherKind.clear;
      case 1:
      case 2:
        return WeatherKind.partlyCloudy;
      case 3:
        return WeatherKind.cloudy;
      case 45:
      case 48:
        return WeatherKind.fog;
      case 51:
      case 53:
      case 55:
        return WeatherKind.drizzle;
      case 56:
      case 57:
      case 66:
      case 67:
        return WeatherKind.freezingRain;
      case 61:
      case 63:
      case 65:
        return WeatherKind.rain;
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return WeatherKind.snow;
      case 80:
      case 81:
      case 82:
        return WeatherKind.showers;
      case 95:
      case 96:
      case 99:
        return WeatherKind.thunderstorm;
      default:
        return WeatherKind.unknown;
    }
  }

  static String descriptionForCode(int code) {
    switch (code) {
      case 0:
        return '晴';
      case 1:
        return '大部晴朗';
      case 2:
        return '多云';
      case 3:
        return '阴';
      case 45:
      case 48:
        return '雾';
      case 51:
        return '小毛毛雨';
      case 53:
        return '毛毛雨';
      case 55:
        return '大毛毛雨';
      case 56:
        return '冻毛毛雨';
      case 57:
        return '强冻毛毛雨';
      case 61:
        return '小雨';
      case 63:
        return '中雨';
      case 65:
        return '大雨';
      case 66:
        return '冻雨';
      case 67:
        return '强冻雨';
      case 71:
        return '小雪';
      case 73:
        return '中雪';
      case 75:
        return '大雪';
      case 77:
        return '米雪';
      case 80:
        return '小阵雨';
      case 81:
        return '中阵雨';
      case 82:
        return '强阵雨';
      case 85:
        return '小阵雪';
      case 86:
        return '大阵雪';
      case 95:
        return '雷阵雨';
      case 96:
      case 99:
        return '雷暴伴冰雹';
      default:
        return '未知天气';
    }
  }
}
