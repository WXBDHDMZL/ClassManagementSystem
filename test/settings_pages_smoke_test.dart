// 设置页界面冒烟测试：安全页 8 个开关、
// 数据页"恢复出厂设置"在末尾、导出路径可清除。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/settings_panel.dart';
import 'package:class_management_system/widgets/settings_pages.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

/// 让页面里的 FutureBuilder / Slider 等完成首帧。
Future<void> _pump(WidgetTester tester, AppDataProvider provider, Widget page) async {
  await tester.pumpWidget(_wrap(provider, page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('设置面板：子页内容必须可滚动（回归：曾溢出画到面板外）', (tester) async {
    // 回归背景：V2.22.0 给首页列表加"记住滚动位置"时，把子页面原本的
    // SingleChildScrollView 包裹弄丢了 —— 子页内容直接超出面板可视高度往下画，
    // 看起来就是"没渲染到的位置却有内容"。这里用贴近真实窗口的小视口复现。
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: testApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                height: 660,
                child: SettingsPanel(onClose: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 进入"记录设置"子页（内容高度超过面板）
    await tester.tap(find.text('记录设置'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: '子页不能溢出面板：内容必须包在可滚动容器里',
    );
    expect(find.text('原因排序'), findsOneWidget);

    // 往下滚到深处也应无异常。面板内有侧栏和内容两个滚动区，
    // 这里明确指定内容区的 Scrollable，避免 scrollUntilVisible 找到多个。
    await tester.scrollUntilVisible(
      find.text('原因排序'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPanel),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    expect(tester.takeException(), isNull);
  });


  testWidgets('安全页：未启用密码时显示"设置管理密码"入口', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const SecuritySettingsPage());

    expect(find.text('设置管理密码'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('数据页：恢复出厂已移走，导出数据包入口存在', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const DataSettingsPage());

    expect(find.text('恢复出厂设置'), findsNothing);
    for (final label in const ['导出路径', '表格与数据包', '导出数据包']) {
      expect(find.text(label), findsOneWidget, reason: '缺少：$label');
    }
    // 分类导入已收敛：只保留记录与学生名单导入，其余走数据包。
    expect(find.text('考勤状态设置'), findsNothing);
    expect(find.text('原因库'), findsNothing);
    expect(find.text('时间段设置'), findsNothing);
    expect(find.text('定期自动导出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('备份页：恢复出厂位于危险操作区', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const BackupSettingsPage());

    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('恢复出厂设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据页：导出路径为空时"清除"按钮不可点', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const DataSettingsPage());

    expect(find.text('清除'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('清除'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull, reason: '没有设置导出路径时无需清除');
  });

  testWidgets('主题页：有界面字号选项（小/标准/大/特大）', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const AppearanceSettingsPage());

    expect(find.text('界面字号'), findsOneWidget);
    for (final label in const ['小', '标准', '大', '特大']) {
      expect(find.text(label), findsOneWidget);
    }
    // V2.34.0：学生卡片字号调节已取消，字号继续随卡片尺寸自动缩放。
    expect(find.text('学生卡片字号'), findsNothing);
    // 切换字号后写回设置
    await tester.tap(find.text('大'));
    await tester.pump();
    expect(provider.appData.settings.uiScale, 1.15);
    expect(tester.takeException(), isNull);
    // 等提示条计时器结束，避免 fake timer 断言失败
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('记录页：有"启用的记录类型"与"原因排序"开关', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const RecordSettingsPage());

    expect(find.text('启用的记录类型'), findsOneWidget);
    // "表扬/批评"既出现在默认类型按钮里，也出现在启用开关标题上
    expect(find.text('表扬'), findsWidgets);
    expect(find.text('批评'), findsWidgets);
    expect(find.text('原因排序'), findsOneWidget);
    expect(find.text('按使用频率自动排序'), findsOneWidget);
    // 统计口径在独立「统计」页，记录页不再混入。
    expect(find.text('统计口径'), findsNothing);

    // 关闭批评（顺序：表扬 / 批评 / 原因排序，取第 2 个开关）
    await tester.tap(find.byType(SwitchListTile).at(1));
    await tester.pump();
    expect(provider.appData.settings.criticismEnabled, isFalse);
    // 表扬已是唯一启用的类型，不能再关闭，开关应置灰而不是静默无效。
    final praiseSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '表扬'),
    );
    expect(praiseSwitch.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口页：有"开机自动启动"开关', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const WindowSettingsPage());

    expect(find.text('开机自动启动'), findsOneWidget);
    expect(find.text('随 Windows 启动'), findsOneWidget);
    // V2.34.0：开机启动目标可选托盘 / 悬浮球。
    expect(find.text('启动后进入'), findsOneWidget);
    expect(find.text('托盘'), findsOneWidget);
    expect(find.text('悬浮球'), findsOneWidget);
    // 悬浮球可从托盘或开机启动进入，透明度不能只在“关闭到悬浮球”时可见。
    expect(find.text('悬浮球外观'), findsOneWidget);
    await tester.tap(find.text('最小化到托盘'));
    await tester.pump();
    expect(find.text('悬浮球外观'), findsOneWidget);
    // V2.34.0：只保留透明度滑块，磨砂玻璃开关已移除。
    expect(find.text('磨砂玻璃效果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('身份页：有开关、身份列表与闲置退出', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const IdentitySettingsPage());

    expect(find.text('启用操作身份'), findsOneWidget);
    expect(find.text('身份列表'), findsOneWidget);
    expect(find.text('班主任'), findsOneWidget);
    expect(find.text('新增身份'), findsOneWidget);
    expect(find.text('身份闲置退出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据页：有导出选项（前缀/列）', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const DataSettingsPage());

    expect(find.text('导出选项'), findsOneWidget);
    expect(find.text('高级导出选项'), findsOneWidget);
    expect(find.text('记录导出的列'), findsNothing);
    await tester.tap(find.text('高级导出选项'));
    await tester.pumpAndSettle();
    expect(find.text('记录导出的列'), findsOneWidget);
    expect(find.text('统计报表包含的工作表'), findsNothing);
    expect(find.text('定期自动导出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('备份页：有自动备份与危险操作，不含定期自动导出', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const BackupSettingsPage());

    expect(find.text('备份位置'), findsOneWidget);
    expect(find.text('自动备份'), findsOneWidget);
    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('定期自动导出'), findsNothing);
    for (final label in const ['仅手动备份', '每次退出时', '每周一次']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('安全页：可生成恢复码，保存后显示已设置', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const SecuritySettingsPage());

    expect(find.text('密码找回'), findsOneWidget);
    expect(find.text('生成恢复码'), findsOneWidget);

    await tester.tap(find.text('生成恢复码'));
    await tester.pumpAndSettle();
    expect(find.text('恢复码（只显示一次）'), findsOneWidget);

    await tester.tap(find.text('我已抄写/保存恢复码'));
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(ElevatedButton, '保存恢复码');
    await tester.tap(saveButton);
    // setRecoveryCode 内部用 isolate 做 PBKDF2，pumpAndSettle 不会等待它完成。
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (provider.appData.settings.recoveryCodeEnabled) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    expect(provider.appData.settings.recoveryCodeEnabled, isTrue);
    expect(find.text('重新生成恢复码'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 等 showTopSnackBar 的 2 秒计时器结束，避免测试结束时有 pending timer。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('统计页：需关注阈值与排行条数独立成页', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const StatisticsSettingsPage());

    expect(find.text('需关注学生阈值'), findsOneWidget);
    expect(find.text('一周（本周 / 近 7 天）'), findsOneWidget);
    expect(find.text('排行显示条数'), findsOneWidget);
    expect(find.text('Top ${provider.appData.settings.rankingTopN}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日志与维护页：数据文件夹与日志操作齐全', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const MaintenanceSettingsPage());

    expect(find.text('打开数据文件夹'), findsOneWidget);
    expect(find.text('打开日志文件夹'), findsOneWidget);
    expect(find.text('查看操作日志'), findsOneWidget);
    expect(find.text('清理 6 个月前日志'), findsOneWidget);
    // 程序更新已降级到维护页。
    expect(find.text('程序更新'), findsOneWidget);
    expect(find.text('选择更新包'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记录设置：主页学生搜索已移到外观页', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const RecordSettingsPage());

    expect(find.text('主页学生搜索'), findsNothing);
    expect(provider.appData.settings.studentSearchEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外观与窗口：合并页含主页搜索与天气设置', (tester) async {
    final provider = AppDataProvider();
    await _pump(tester, provider, const AppearanceWindowSettingsPage());

    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('关闭窗口时'), findsOneWidget);
    expect(find.text('主页学生搜索'), findsOneWidget);
    expect(find.text('显示学生搜索框'), findsOneWidget);
    expect(find.text('天气地区'), findsOneWidget);
    expect(find.text('设置天气地区'), findsOneWidget);
    expect(find.text('在顶栏显示天气'), findsOneWidget);
    expect(provider.appData.settings.studentSearchEnabled, isTrue);

    final searchSwitch = find.widgetWithText(SwitchListTile, '显示学生搜索框');
    await tester.ensureVisible(searchSwitch);
    await tester.pumpAndSettle();
    await tester.tap(searchSwitch);
    await tester.pump();

    expect(provider.appData.settings.studentSearchEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}
