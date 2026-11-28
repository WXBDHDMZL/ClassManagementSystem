// 设置面板新布局：左侧分组导航、默认统计口径、页面切换与门禁拦截。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/app_version.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/security_service.dart';
import 'package:class_management_system/widgets/settings_panel.dart';

import 'test_helpers.dart';

Widget _wrap(AppDataProvider provider) => ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 920,
              height: 660,
              child: SettingsPanel(onClose: () {}),
            ),
          ),
        ),
      ),
    );

/// 模拟真实窗口：不额外套固定尺寸，让 Dialog 自己按屏幕边界收缩。
Widget _wrapResponsive(AppDataProvider provider) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: testApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SettingsPanel(onClose: () {})),
      ),
    );

Future<void> _pumpPanel(WidgetTester tester, AppDataProvider provider) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(provider));
  await tester.pump();
}

void main() {
  testWidgets('设置面板：分组入口可见，默认打开统计口径', (tester) async {
    final provider = AppDataProvider();
    await _pumpPanel(tester, provider);

    expect(find.text('日常使用'), findsOneWidget);
    expect(find.text('记录与名单'), findsOneWidget);
    expect(find.text('时间与考勤'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('统计口径'), findsWidgets);
    expect(find.text('每周起始日'), findsOneWidget);
    expect(find.text('需关注学生阈值'), findsOneWidget);
    // 未启用管理密码时，分组标题不应再宣称“需管理密码”。
    expect(find.text('需管理密码'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板：切换外观与窗口后显示页面内容', (tester) async {
    final provider = AppDataProvider();
    await _pumpPanel(tester, provider);

    await tester.tap(find.text('外观与窗口').first);
    await tester.pumpAndSettle();

    expect(find.text('外观模式'), findsOneWidget);
    expect(find.text('界面字号'), findsOneWidget);
    expect(find.text('每周起始日'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板：关于固定在底部，可打开版本信息', (tester) async {
    final provider = AppDataProvider();
    await _pumpPanel(tester, provider);

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.text('班级管理系统'), findsWidgets);
    expect(find.textContaining(AppVersion.version), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板：系统与安全分组可滚动到日志与维护', (tester) async {
    final provider = AppDataProvider();
    await _pumpPanel(tester, provider);

    final sidebar = find
        .descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('日志与维护'),
      120,
      scrollable: sidebar,
    );
    // scrollUntilVisible 只保证进入视口边缘；再向上带一点，
    // 避免入口贴在弹窗底边导致点击命中不到。
    await tester.drag(sidebar, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(find.text('系统与安全'), findsOneWidget);

    await tester.tap(find.text('日志与维护'));
    await tester.pumpAndSettle();
    expect(find.text('打开数据文件夹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板：记录设置需要密码，取消后保持当前页', (tester) async {
    final provider = AppDataProvider();
    await provider.setPasswordHash(SecurityService.hashPassword('1234'));
    provider.setPasswordEnabled(true);
    await _pumpPanel(tester, provider);
    expect(find.text('需管理密码'), findsWidgets);

    await tester.tap(find.text('记录设置'));
    await tester.pumpAndSettle();

    expect(find.text('请输入管理密码'), findsOneWidget);
    expect(find.text('进入「记录设置」需要先进入班主任管理。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 仍停在默认的统计口径，不能出现空白内容区或误开记录页。
    expect(find.text('每周起始日'), findsOneWidget);
    expect(find.text('原因排序'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板：管理会话结束或超时后锁定安全页，重新验证后恢复', (tester) async {
    final provider = AppDataProvider();
    await provider.setPasswordHash(SecurityService.hashPassword('1234'));
    provider.setPasswordEnabled(true);
    await _pumpPanel(tester, provider);

    final sidebar = find
        .descendant(
          of: find.byType(SettingsPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('安全与密码'),
      120,
      scrollable: sidebar,
    );
    await tester.drag(sidebar, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('安全与密码'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确认'));
    expect(
      await pumpUntilRealAsync(tester, () => provider.isManagementMode),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('关闭管理密码'), findsOneWidget);

    provider.exitManagementMode();
    await tester.pumpAndSettle();
    expect(find.text('管理会话已结束'), findsOneWidget);
    expect(find.text('关闭管理密码'), findsNothing);

    await tester.tap(find.byKey(const Key('settings-session-unlock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确认'));
    expect(
      await pumpUntilRealAsync(tester, () => provider.isManagementMode),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('关闭管理密码'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 重新验证会再次启动 15 分钟管理会话；先确认未提前到期，再推进到
    // 自然到期，验证真实定时器路径也会清掉会话并锁定页面。
    await tester.pump(const Duration(minutes: 14, seconds: 59));
    expect(provider.isManagementMode, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(provider.isManagementMode, isFalse);
    expect(find.text('管理会话已结束'), findsOneWidget);
    expect(find.text('关闭管理密码'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置面板：1366×768、150% 缩放下不溢出', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);

    final provider = AppDataProvider();
    await tester.pumpWidget(_wrapResponsive(provider));
    await tester.pumpAndSettle();

    expect(find.text('日常使用'), findsOneWidget);
    expect(find.text('统计口径'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('外观与窗口').first);
    await tester.pumpAndSettle();
    expect(find.text('外观模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
