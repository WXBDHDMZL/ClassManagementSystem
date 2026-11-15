/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V2.34.2
 * 创建日期 (Created): 2026-10-17
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/weather_service.dart';
import 'package:class_management_system/widgets/weather_city_dialog.dart';

void main() {
  group('天气代码映射', () {
    test('常见天气代码有中文描述与分类', () {
      expect(WeatherService.descriptionForCode(0), '晴');
      expect(WeatherService.descriptionForCode(61), '小雨');
      expect(WeatherService.descriptionForCode(95), '雷阵雨');
      expect(WeatherService.descriptionForCode(999), '未知天气');

      expect(WeatherService.kindForCode(0), WeatherKind.clear);
      expect(WeatherService.kindForCode(3), WeatherKind.cloudy);
      expect(WeatherService.kindForCode(45), WeatherKind.fog);
      expect(WeatherService.kindForCode(65), WeatherKind.rain);
      expect(WeatherService.kindForCode(75), WeatherKind.snow);
      expect(WeatherService.kindForCode(95), WeatherKind.thunderstorm);
      expect(WeatherService.kindForCode(999), WeatherKind.unknown);
    });
  });

  testWidgets('天气地区对话框可正常渲染', (tester) async {
    final provider = AppDataProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: WeatherCityDialog()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('选择天气地区'), findsOneWidget);
    expect(find.text('输入城市、镇或乡名，例如：北京、三墩镇、乌镇'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Photon 结果可解析到镇级，并过滤幼儿园等无关地点', () {
    const raw = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "osm_key": "place",
        "osm_value": "town",
        "type": "district",
        "name": "三墩镇",
        "city": "杭州市",
        "state": "浙江省",
        "country": "中国"
      },
      "geometry": {"type": "Point", "coordinates": [120.0799906, 30.3237201]}
    },
    {
      "type": "Feature",
      "properties": {
        "osm_key": "amenity",
        "osm_value": "kindergarten",
        "type": "house",
        "name": "三墩镇中心幼儿园",
        "city": "杭州市",
        "state": "浙江省",
        "country": "中国"
      },
      "geometry": {"type": "Point", "coordinates": [120.0337126, 30.3334305]}
    }
  ]
}
''';
    final cities = WeatherService.parsePhotonResponse(raw);
    expect(cities, hasLength(1));
    expect(cities.single.name, '三墩镇');
    expect(cities.single.admin, '浙江省 · 杭州市');
    expect(cities.single.latitude, closeTo(30.3237201, 0.0001));
  });

  group('天气地区设置', () {
    test('城市与坐标可完整序列化/反序列化', () {
      final settings =
          AppSettings(themeMode: ThemeModeType.system).copyWith(
        weatherCityName: '北京',
        weatherCityAdmin: '北京市',
        weatherLatitude: 39.9075,
        weatherLongitude: 116.39723,
        showWeather: true,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.weatherCityName, '北京');
      expect(restored.weatherCityAdmin, '北京市');
      expect(restored.weatherLatitude, closeTo(39.9075, 0.0001));
      expect(restored.weatherLongitude, closeTo(116.39723, 0.0001));
      expect(restored.showWeather, isTrue);
    });

    test('非法坐标回退为 0，旧数据缺少字段也能正常读取', () {
      final invalid = AppSettings.fromJson({
        'themeMode': 0,
        'weatherLatitude': 120,
        'weatherLongitude': -200,
      });
      expect(invalid.weatherLatitude, 0);
      expect(invalid.weatherLongitude, 0);
      expect(invalid.weatherCityName, '');

      final legacy = AppSettings.fromJson({'themeMode': 0});
      expect(legacy.weatherCityName, '');
      expect(legacy.weatherLatitude, 0);
    });
  });
}
