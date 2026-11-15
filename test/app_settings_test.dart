// 设置模型测试：closeAction / 悬浮球位置的序列化、旧版本数据兼容与非法值回退。

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_settings.dart';

void main() {
  test('设置项序列化为 index 并可正确还原（含悬浮球位置）', () {
    final settings = AppSettings(
      themeMode: ThemeModeType.dark,
      exportPath: r'D:\导出',
      closeAction: CloseActionType.minimizeToBall,
      ballX: 1200,
      ballY: 640,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.themeMode, ThemeModeType.dark);
    expect(restored.exportPath, r'D:\导出');
    expect(restored.closeAction, CloseActionType.minimizeToBall);
    expect(restored.ballX, 1200);
    expect(restored.ballY, 640);
  });

  test('开机启动目标可序列化，非法值回退托盘', () {
    final settings = AppSettings(
      themeMode: ThemeModeType.system,
      startupTarget: StartupTarget.ball,
    );
    expect(
      AppSettings.fromJson(settings.toJson()).startupTarget,
      StartupTarget.ball,
    );
    expect(
      AppSettings.fromJson({'themeMode': 0, 'startupTarget': 99})
          .startupTarget,
      StartupTarget.tray,
    );
  });

  test('四种关闭行为按枚举索引持久化，互不串位', () {
    expect(CloseActionType.ask.index, 0);
    expect(CloseActionType.exit.index, 1);
    expect(CloseActionType.minimizeToTray.index, 2);
    expect(CloseActionType.minimizeToBall.index, 3);
    expect(
      AppSettings.fromJson({'closeAction': 2}).closeAction,
      CloseActionType.minimizeToTray,
    );
  });

  test('旧版本数据缺少新字段时回退（每次询问、球位置未设置）', () {
    final restored = AppSettings.fromJson({
      'themeMode': 0,
      'exportPath': '',
    });

    expect(restored.closeAction, CloseActionType.ask);
    expect(restored.ballX, -1);
    expect(restored.ballY, -1);
  });

  test('closeAction 为非法值时回退为“每次询问”', () {
    expect(
      AppSettings.fromJson({'closeAction': 99}).closeAction,
      CloseActionType.ask,
    );
    expect(
      AppSettings.fromJson({'closeAction': 'tray'}).closeAction,
      CloseActionType.ask,
    );
  });

  test('悬浮球坐标为非法值时回退为未设置（-1）', () {
    final restored = AppSettings.fromJson({
      'ballX': 'abc',
      'ballY': null,
    });

    expect(restored.ballX, -1);
    expect(restored.ballY, -1);
  });

  test('时段自定义、启动窗口状态与窗口位置都能完整往返', () {
    final settings = AppSettings(
      themeMode: ThemeModeType.system,
      periodLabels: const {'class': '08:10-12:00 第一课堂'},
      startupWindowMode: StartupWindowMode.maximized,
      windowX: 100,
      windowY: 60,
      windowWidth: 1360,
      windowHeight: 800,
      windowMaximized: true,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.periodLabels['class'], '08:10-12:00 第一课堂');
    expect(restored.startupWindowMode, StartupWindowMode.maximized);
    expect(restored.windowX, 100);
    expect(restored.windowY, 60);
    expect(restored.windowWidth, 1360);
    expect(restored.windowHeight, 800);
    expect(restored.windowMaximized, isTrue);
  });

  test('学生搜索开关默认开启，并完整往返', () {
    final defaults = AppSettings(themeMode: ThemeModeType.system);
    expect(defaults.studentSearchEnabled, isTrue);

    final disabled = AppSettings(
      themeMode: ThemeModeType.system,
      studentSearchEnabled: false,
    );
    expect(
      AppSettings.fromJson(disabled.toJson()).studentSearchEnabled,
      isFalse,
    );
  });

  test('悬浮球位置锁定默认关闭，并完整往返', () {
    final defaults = AppSettings(themeMode: ThemeModeType.system);
    expect(defaults.ballPositionLocked, isFalse);

    final restored = AppSettings.fromJson(
      AppSettings(
        themeMode: ThemeModeType.system,
        ballPositionLocked: true,
      ).toJson(),
    );
    expect(restored.ballPositionLocked, isTrue);
  });

  test('旧数据缺新字段时回退：无自定义时段、启动记住上次、窗口位置未记录', () {
    final restored = AppSettings.fromJson({'themeMode': 0});

    expect(restored.periodLabels, isEmpty);
    expect(restored.startupWindowMode, StartupWindowMode.remember);
    expect(restored.windowWidth, -1);
    expect(restored.windowMaximized, isFalse);
  });

  test('时段标签非法条目被忽略，只保留字符串键值', () {
    final restored = AppSettings.fromJson({
      'periodLabels': {'class': '08:10-12:00 第一课堂', 'meal': 5, 7: 'x'},
    });

    expect(restored.periodLabels.length, 1);
    expect(restored.periodLabels['class'], '08:10-12:00 第一课堂');
  });
}
