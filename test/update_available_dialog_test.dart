// 更新弹窗：紧凑卡片内容、操作结果与跳过版本的持久化。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/constants/app_theme.dart';
import 'package:class_management_system/constants/app_version.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/github_update_service.dart';
import 'package:class_management_system/services/update_check_service.dart';
import 'package:class_management_system/widgets/update_available_dialog.dart';
import 'package:class_management_system/widgets/update_prompt_host.dart';

import 'test_helpers.dart';

GitHubReleaseInfo _release({bool withInstaller = true}) {
  return GitHubReleaseInfo(
    tagName: 'v4.11.0',
    title: 'V4.11.0',
    notes: '# 版本内容示例\n\n- 新增名单导入\n- **修复** 统计细节',
    assets: [
      if (withInstaller)
        GitHubAsset(
          name: 'ClassManagementSystem_Setup_v4.11.0.exe',
          downloadUrl: Uri.parse(
            'https://github.com/WXBDHDMZL/ClassManagementSystem/releases/download/v4.11.0/ClassManagementSystem_Setup_v4.11.0.exe',
          ),
          size: 12 * 1024 * 1024,
        ),
    ],
  );
}

AppDataProvider _testProvider() {
  final provider = AppDataProvider();
  provider.appData.setStudents(const ['学生1']);
  return provider;
}

void main() {
  setUp(UpdateCheckService.resetForTest);
  tearDown(UpdateCheckService.resetForTest);

  testWidgets('更新弹窗显示版本和三个操作，不渲染发布正文', (tester) async {
    late UpdateAvailableAction? action;
    await tester.pumpWidget(
      testApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                action = await showUpdateAvailableDialog(
                  context,
                  release: _release(),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('发现可用版本'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text(AppVersion.version), findsOneWidget);
    expect(find.text('可用版本'), findsOneWidget);
    expect(find.text('v4.11.0'), findsOneWidget);
    expect(find.text('版本内容'), findsNothing);
    expect(find.textContaining('新增名单导入'), findsNothing);
    expect(
      find.textContaining('ClassManagementSystem_Setup_v4.11.0.exe'),
      findsOneWidget,
    );
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('跳过此版本'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);

    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();
    expect(action, UpdateAvailableAction.skip);
  });

  testWidgets('稍后返回 later；没有安装包时立即更新不可点', (tester) async {
    late UpdateAvailableAction? action;
    await tester.pumpWidget(
      testApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                action = await showUpdateAvailableDialog(
                  context,
                  release: _release(withInstaller: false),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final installButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '立即更新'),
    );
    expect(installButton.onPressed, isNull);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(action, UpdateAvailableAction.later);
  });

  testWidgets('选择跳过此版本会写入设置并持久化', (tester) async {
    final provider = _testProvider();
    addTearDown(() async {
      await flushWrites(provider);
      provider.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: testApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => promptForUpdate(context, _release()),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();

    expect(provider.appData.settings.skippedUpdateTag, 'v4.11.0');
  });

  testWidgets('已跳过的版本不会在启动后自动弹出', (tester) async {
    final provider = _testProvider();
    provider.setSkippedUpdateTag('v4.11.0');
    addTearDown(() async {
      await flushWrites(provider);
    });
    UpdateCheckService.availableRelease.value = _release();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: testApp(
          theme: AppTheme.dark(),
          home: const UpdatePromptHost(child: Scaffold(body: Text('主界面'))),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('发现可用版本'), findsNothing);
    expect(find.text('主界面'), findsOneWidget);
  });

  testWidgets('未跳过的版本会在启动后自动弹出', (tester) async {
    final provider = _testProvider();
    addTearDown(() async {
      await flushWrites(provider);
    });
    UpdateCheckService.availableRelease.value = _release();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppDataProvider>.value(
        value: provider,
        child: testApp(
          theme: AppTheme.dark(),
          home: const UpdatePromptHost(child: Scaffold(body: Text('主界面'))),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('发现可用版本'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
  });
}
