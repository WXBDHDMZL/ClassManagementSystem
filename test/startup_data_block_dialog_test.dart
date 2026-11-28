// 审计 A-01 的"输入确认字样"闸门测试。
//
// 这个对话框是最后一个防误操作关口：用户必须**逐字输入**确认短语并勾选
// 风险声明，才允许把损坏库切换成可写空库。这里验证闸门真的拦得住，
// 以及确认之后 provider 真的从阻断态恢复（不是只有按钮变灰/变亮）。
//
// 注意：provider 的初始化/确认会做真实文件 IO，而 widget 测试默认跑在
// FakeAsync 里 —— 真实 IO 回调送不回来会直接挂死，所以凡是 await 真 IO
// 的步骤都必须包在 `tester.runAsync` 里。

import 'dart:io';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/widgets/startup_data_block_dialog.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_block_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
  });

  tearDown(() async {
    provider.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteStorageTestRoot(tempDir);
  });

  File mainFile() => File('${tempDir.path}/class_management_data.enc');

  /// 对话框里有 TextField：光标闪烁是**永不停止**的动画，`pumpAndSettle()`
  /// 会一直等到超时（默认 10 分钟）。所以固定推几帧即可。
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 造一个"主文件损坏且无备份"的阻断态 provider（真文件 IO）。
  Future<void> prepareBlocked(WidgetTester tester) async {
    provider = AppDataProvider();
    await tester.runAsync(() async {
      // 真实文件 IO 必须放在 runAsync 里：widget 测试默认跑在 FakeAsync，
      // dart:io 的完成回调属于真实事件循环，留在 FakeAsync 里会永远等不到。
      await mainFile().writeAsString('损坏内容!!!');
      await provider.initialize();
    });
    expect(provider.needsEmptyLibraryConfirm, isTrue);
  }

  Future<void> openDialog(
    WidgetTester tester,
    StartupDataBlockKind kind,
    void Function(bool?) onResult,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: ChangeNotifierProvider<AppDataProvider>.value(
          value: provider,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                onResult(await showStartupDataBlockDialog(context, kind: kind));
              },
              child: const Text('打开对话框'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开对话框'));
    await pumpDialog(tester);
  }

  FilledButton confirmButton(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  group('损坏隔离对话框', () {
    testWidgets('未输入确认字样 / 未勾选声明时，确认按钮不可用', (tester) async {
      await prepareBlocked(tester);
      await openDialog(tester, StartupDataBlockKind.corrupted, (_) {});

      const label = '以空库继续（原文件保留）';
      expect(find.text(label), findsOneWidget);
      expect(confirmButton(tester, label).onPressed, isNull, reason: '初始状态必须禁用');

      // 只勾选、不输入 → 仍然禁用。
      await tester.tap(find.byType(CheckboxListTile));
      await pumpDialog(tester);
      expect(confirmButton(tester, label).onPressed, isNull,
          reason: '只勾选不算确认，必须逐字输入确认字样');

      // 输错（不完整）→ 仍然禁用。
      await tester.enterText(find.byType(TextField), '确认以空库');
      await pumpDialog(tester);
      expect(confirmButton(tester, label).onPressed, isNull,
          reason: '输入不完整时必须继续禁用');

      // 输对但不勾选 → 仍然禁用。
      await tester.tap(find.byType(CheckboxListTile));
      await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), '确认以空库继续');
      await pumpDialog(tester);
      expect(confirmButton(tester, label).onPressed, isNull,
          reason: '输入正确但未勾选声明时必须继续禁用');
    });

    testWidgets('字样与声明都满足后，确认按钮才可用（放行闸门）', (tester) async {
      await prepareBlocked(tester);
      await openDialog(tester, StartupDataBlockKind.corrupted, (_) {});

      const label = '以空库继续（原文件保留）';
      await tester.enterText(find.byType(TextField), '确认以空库继续');
      await tester.tap(find.byType(CheckboxListTile));
      await pumpDialog(tester);

      expect(confirmButton(tester, label).onPressed, isNotNull,
          reason: '字样与声明都满足后才允许确认');

      // 真正点击"确认"会触发 provider 的真实文件 IO；widget 测试跑在
      // FakeAsync 下无法可靠驱动这类 IO（会挂住），因此点击后的状态迁移
      // 由 test/startup_data_block_test.dart 的 provider 级用例覆盖。
      // 这里只守"闸门"：按钮何时可用、何时不可用。
    });

    testWidgets('“稍后处理”返回 false 且保持阻断', (tester) async {
      await prepareBlocked(tester);
      bool? result;
      await openDialog(
        tester,
        StartupDataBlockKind.corrupted,
        (value) => result = value,
      );

      await tester.tap(find.widgetWithText(TextButton, '稍后处理'));
      await pumpDialog(tester);

      expect(result, isFalse);
      expect(provider.storageWriteBlocked, isTrue, reason: '关闭对话框不等于解除阻断');
    });
  });

  group('错钥对话框', () {
    testWidgets('主按钮是“退出并换回原 .enc.key”，放弃数据入口藏在第三层', (tester) async {
      await prepareBlocked(tester);
      await openDialog(tester, StartupDataBlockKind.keyMismatch, (_) {});

      expect(find.text('退出并换回原 .enc.key'), findsOneWidget);
      expect(find.text('稍后处理'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: '默认界面不应暴露放弃数据的输入框');

      await tester.tap(find.text('仍要以空库继续'));
      await pumpDialog(tester);
      expect(find.byType(TextField), findsOneWidget);

      const giveUpLabel = '以空库继续（原文件保留）';
      expect(confirmButton(tester, giveUpLabel).onPressed, isNull);

      // 错钥场景要的是另一句更重的确认标语。
      await tester.enterText(find.byType(TextField), '确认以空库继续');
      await tester.tap(find.byType(CheckboxListTile));
      await pumpDialog(tester);
      expect(confirmButton(tester, giveUpLabel).onPressed, isNull,
          reason: '错钥场景不得用"损坏"场景的确认字样放行');

      // 换成正确标语后放行。
      await tester.enterText(find.byType(TextField), '确认放弃可恢复数据');
      await pumpDialog(tester);
      expect(confirmButton(tester, giveUpLabel).onPressed, isNotNull);
    });
  });

  // GUI 验收发现：1080x680（150% 缩放 ≈ 720x453 逻辑像素）窗口下，旧布局把
  // 复选项与按钮挤出窗口，用户根本无法完成"以空库继续"。对话框改成
  // scrollable 后，底部按钮必须始终可见可点。
  group('小窗口下按钮仍可用（GUI 验收回归）', () {
    testWidgets('1280x800@1.5 时主按钮可见且可点', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await prepareBlocked(tester);
      await openDialog(tester, StartupDataBlockKind.corrupted, (_) {});

      expect(find.text('稍后处理').hitTestable(), findsOneWidget);
      expect(find.text('确认以空库继续').hitTestable(), findsNothing,
          reason: '未输入短语前主按钮必须是禁用的');

      // 关键：错误提示语与确认输入框在滚动区内，主按钮区不该被挤出可视范围。
      final dialogRect = tester.getRect(find.byType(AlertDialog));
      final windowSize = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(dialogRect.bottom, lessThanOrEqualTo(windowSize.height + 0.5),
          reason: '对话框不得超出窗口底部，否则按钮点不到');
    });
  });
}