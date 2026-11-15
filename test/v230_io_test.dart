// V2.30.1 数据包导入导出回归。
// 校历与设置方案相关用例已随功能移除。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/transfer_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cms_v230io');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.path
          : null,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteDirectoryWithRetry(tempDir);
  });

  test('数据包导出/解析基础回归（不含已撤销的小组与事件字段）', () async {
    final provider = AppDataProvider();
    await provider.flushPendingSaves();

    final pkg = TransferService.parsePackage(
      TransferService.buildPackage(provider.appData, exportedAt: '2026-10-03'),
    );
    expect(pkg, isNotNull);
    expect(pkg!.students, provider.appData.students);
    // 旧数据包（无小组/事件字段）解析不受影响
    final legacy = TransferService.parsePackage('''
{"format": "class_management_system.package", "version": 1,
 "students": ["甲"], "reasons": {}, "periodLabels": {}}
''');
    expect(legacy, isNotNull);
    expect(legacy!.students, ['甲']);
  });
}
