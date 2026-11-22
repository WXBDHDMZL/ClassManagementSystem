// 5.0 回归：旧版文档根目录布局不再迁移，必须明确拒绝且不能生成空库。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory docs;
  late StorageService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docs = Directory.systemTemp.createTempSync('cms_v5_legacy_layout');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? docs.path
              : null,
        );
    service = StorageService();
    StorageService.debugResetKey();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    StorageService.debugResetKey();
    await deleteDirectoryWithRetry(docs);
  });

  File legacyFile() =>
      File('${docs.path}${Platform.pathSeparator}class_management_data.enc');
  File legacyBackup() => File('${legacyFile().path}.bak');
  File newFile() => File(
    '${docs.path}${Platform.pathSeparator}班级管理系统'
    '${Platform.pathSeparator}class_management_data.enc',
  );

  test('旧布局主文件不再迁移，明确返回不支持并拒绝保存', () async {
    await legacyFile().writeAsString('old-layout-data');

    final result = await service.loadData();

    expect(result.unsupportedFormat, isTrue);
    expect(result.loadFailed, isFalse);
    expect(await newFile().exists(), isFalse);
    expect(await service.saveData(AppData.empty()), isFalse);
    expect(await legacyFile().exists(), isTrue, reason: '不得删除旧文件');
  });

  test('仅有旧布局备份时同样拒绝，不生成新空库', () async {
    await legacyBackup().writeAsString('old-layout-backup');

    final result = await service.loadData();

    expect(result.unsupportedFormat, isTrue);
    expect(await newFile().exists(), isFalse);
    final saved = await service.saveData(AppData.empty());
    expect(saved, isFalse);
    expect(await newFile().exists(), isFalse);
  });

  test('Provider 启动提示为旧版不支持错误', () async {
    await legacyFile().writeAsString('old-layout-data');
    final provider = AppDataProvider();

    await provider.initialize();

    expect(provider.startupNoticeIsError, isTrue);
    expect(provider.startupNotice, contains('不支持'));
    expect(await newFile().exists(), isFalse);
  });
}
