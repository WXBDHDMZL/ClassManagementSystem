// 行为测试：主文件损坏且无可用备份时，加载失败必须先隔离原文件，
// 后续保存不得覆盖唯一可抢救的损坏副本（BACKLOG B-02 / D-013）。
//
// 全部走 mock 的临时文档目录，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_corrupt_isolation');
    storage = StorageService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
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

  List<File> corruptFiles() => tempDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('.enc.corrupt_'))
      .toList();

  group('B-02 损坏主文件隔离', () {
    test('主文件损坏且无备份：原文件被隔离保留，不被静默丢弃', () async {
      const corruptContent = '损坏内容，绝不能丢!!!';
      await mainFile().writeAsString(corruptContent);

      final result = await storage.loadData();

      expect(result.resetToEmpty, isTrue);
      expect(await mainFile().exists(), isFalse,
          reason: '损坏主文件应先被移走，给后续保存让路');
      final quarantined = corruptFiles();
      expect(quarantined, hasLength(1), reason: '必须保留恰好一份损坏副本');
      expect(await quarantined.single.readAsString(), corruptContent,
          reason: '隔离后的内容必须与原始损坏内容逐字节一致');
    });

    test('隔离后确认前拒绝保存，确认后才重建主文件，损坏副本仍在', () async {
      await mainFile().writeAsString('损坏内容!!!');
      final loaded = await storage.loadData();
      expect(loaded.resetToEmpty, isTrue);

      // 旧期望：这里直接断言 saveData 返回 true 并重建主文件。
      // 新期望（审计 A-01）：隔离后**必须等用户显式确认**，否则第一次自动
      // 保存就会把空库写进主文件、第二次再把 `.bak` 顶掉，最后一份可抢救
      // 数据只剩没有入口的 `.corrupt_*`。
      final blocked = await storage.saveData(
        AppData.fromJson(const {'students': ['新数据张三']}),
      );
      expect(blocked, isFalse, reason: '确认前必须拒绝写入');
      expect(await mainFile().exists(), isFalse, reason: '拒绝写入时不得重建主文件');
      expect(corruptFiles(), hasLength(1), reason: '拒绝写入不得动损坏副本');

      // 用户显式确认（对话框输入"确认以空库继续"）后才放行。
      expect(await storage.releaseQuarantineForEmptyLibrary(), isTrue);

      final ok = await storage.saveData(
        AppData.fromJson(const {'students': ['新数据张三']}),
      );
      expect(ok, isTrue);
      expect(await mainFile().exists(), isTrue);
      final reloaded = await StorageService().loadData();
      expect(reloaded.data.students, contains('新数据张三'));
      expect(corruptFiles(), hasLength(1),
          reason: '新数据重建主文件时不得顺手删掉损坏副本');
    });

    test('主文件损坏 + .bak 完好：仍走备份恢复，不产生损坏副本', () async {
      final backupText = await storage.encodeForTest(
        AppData.fromJson(const {'students': ['备份里的李四']}),
      );
      await File('${mainFile().path}.bak').writeAsString(backupText);
      await mainFile().writeAsString('损坏内容!!!');

      final result = await storage.loadData();

      expect(result.restoredFromBackup, isTrue);
      expect(result.data.students, contains('备份里的李四'));
      expect(corruptFiles(), isEmpty,
          reason: '能从备份恢复时不该额外隔离主文件');
    });

    test('主文件正常：不产生损坏副本', () async {
      await mainFile().writeAsString(
        await storage.encodeForTest(
          AppData.fromJson(const {'students': ['正常张三']}),
        ),
      );

      final result = await storage.loadData();

      expect(result.restoredFromBackup, isFalse);
      expect(result.resetToEmpty, isFalse);
      expect(corruptFiles(), isEmpty);
    });
  });
}
