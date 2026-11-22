// 班级管理系统 - 主页冒烟测试：
// 验证应用能正常启动、渲染标题栏与今日记录面板，并保证标题栏布局正确
// （标题水平居中、左上角设置按钮不与标题重叠）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/main.dart';
import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/statistics_dialog.dart';

void main() {
  testWidgets('主页冒烟测试：标题与今日记录面板正常显示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AppDataProvider())],
        child: const MyApp(),
      ),
    );
    // 逐步推进虚拟时间：等待数据加载完成与启动遮罩淡出移除
    // （启动进度圈为无限动画，不能使用 pumpAndSettle 等待）。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // 顶栏标题
    final titleFinder = find.text('班级管理系统');
    expect(titleFinder, findsOneWidget);

    // 标题应水平居中：Stack 默认按左上角对齐子项，曾导致标题偏左。
    final screenWidth = tester.getSize(find.byType(Scaffold).first).width;
    final titleCenterX = tester.getCenter(titleFinder).dx;
    expect(
      (titleCenterX - screenWidth / 2).abs(),
      lessThan(2),
      reason: '标题未水平居中',
    );

    // 左上角设置按钮不应与标题重叠。
    final iconFinder = find.byIcon(Icons.settings);
    expect(iconFinder, findsOneWidget);
    expect(
      tester.getRect(iconFinder).right <= tester.getRect(titleFinder).left,
      isTrue,
      reason: '设置按钮与标题重叠',
    );

    // 右侧今日记录面板
    expect(find.text('今日记录'), findsOneWidget);
    expect(find.text('暂无记录'), findsOneWidget);

    // 出厂名单为空：不再内置任何真实学生姓名，主页显示引导而不是批量入口。
    expect(find.textContaining('暂无学生'), findsOneWidget);
    expect(find.text('批量'), findsNothing);

    // 天气默认关闭：未开启时不显示入口，也不发起请求。
    expect(find.text('设置天气地区'), findsNothing);
  });

  testWidgets('启用操作身份后右上角显示未选择操作身份', (WidgetTester tester) async {
    final provider = AppDataProvider();
    provider.setIdentityFeatureEnabled(true);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: const MyApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('未选择操作身份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('界面字号放到最大（特大）时主界面不溢出', (WidgetTester tester) async {
    final provider = AppDataProvider();
    provider.setUiScale(1.3);

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: const MyApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // 布局溢出会以异常抛出
    expect(tester.takeException(), isNull);

    // 统计看板在特大字号下同样不应溢出（直接渲染，避免依赖点击命中）
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: StatisticsDialog()),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
  });
}
