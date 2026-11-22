// 行为测试：数据目录读取异常（同步盘/杀软/权限瞬时失败）绝不能被当成
// “数据损坏”去重置，也不能让后续自动备份把空库覆盖到主文件或 .bak。
//
// 全部走 mock 的临时文档目录与合成数据，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_load_failure');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await deleteStorageTestRoot(tempDir);
  });

  File mainFile() => File('${tempDir.path}/class_management_data.enc');

  void mockDocuments({bool throwOnce = false}) {
    var shouldThrow = throwOnce;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method != 'getApplicationDocumentsDirectory') return null;
            if (shouldThrow) {
              shouldThrow = false;
              throw PlatformException(code: 'boom');
            }
            return tempDir.parent.path;
          },
        );
  }

  Future<void> seedData() async {
    mockDocuments();
    final seeded = AppData.fromJson(const {
      'students': ['张三'],
      'recordsByDate': {
        '2026-11-21': [
          {
            'id': 'r1',
            'studentName': '张三',
            'operationType': '表扬',
            'reasons': '课堂表现好',
            'periodKey': 'class',
            'periodName': '上课',
            'remark': '',
            'timestamp': '09:00:00',
            'date': '2026-11-21',
          },
        ],
      },
    });
    expect(await StorageService().saveData(seeded), isTrue);
  }

  test('读取文档目录异常：loadData 标记加载失败，不重置也不隔离原文件', () async {
    await seedData();
    final before = await mainFile().readAsBytes();

    mockDocuments(throwOnce: true);
    final storage = StorageService();
    final result = await storage.loadData();

    expect(result.loadFailed, isTrue);
    expect(result.resetToEmpty, isFalse);
    expect(await mainFile().readAsBytes(), before, reason: '读盘异常时主文件必须逐字节保持原样');
    expect(
      tempDir.listSync().where((e) => e.path.contains('.corrupt_')),
      isEmpty,
      reason: '读盘异常不是文件损坏，不能把好文件改名隔离',
    );
  });

  test('读取文档目录异常后：saveData 拒绝写入，空库不会覆盖主文件', () async {
    await seedData();
    final before = await mainFile().readAsBytes();

    mockDocuments(throwOnce: true);
    final storage = StorageService();
    await storage.loadData();

    final saved = await storage.saveData(AppData.empty());
    expect(saved, isFalse, reason: '加载失败后必须拒绝一切保存');
    expect(await mainFile().readAsBytes(), before);
  });

  test('provider 初始化失败：提示暂停保存，启动自动备份不产生空备份', () async {
    await seedData();
    final before = await mainFile().readAsBytes();

    mockDocuments(throwOnce: true);
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    await provider.initialize();

    expect(provider.startupNoticeIsError, isTrue);
    expect(provider.startupNotice, contains('暂停保存'));

    await provider.runScheduledBackup();
    expect(await mainFile().readAsBytes(), before, reason: '启动自动备份不得写入空库');
    final backupDir = Directory('${tempDir.path}/备份');
    expect(
      backupDir.existsSync() ? backupDir.listSync() : const [],
      isEmpty,
      reason: '加载失败时不应生成自动备份文件',
    );
  });
}
