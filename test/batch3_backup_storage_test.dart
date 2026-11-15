// Batch 3 回归：.bak 同长度损坏保护、备份列表包含 .bak、saveNow 与自动备份失败提示。
//
// 背景（历史缺陷记录）：
//  - B-08 `.bak` 只比长度，外部同长度损坏会顶掉最后一份可用备份；backupTo 非原子；
//  - B-09 恢复 UI 选不到 `.bak`；自动备份失败无提示；
//  - B-10 关键操作前不自动备份；成功提示先于异步落盘。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/models/student_record.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

StudentRecord _rec(String id, String name) {
  return StudentRecord(
    id: id,
    studentName: name,
    operationType: '表扬',
    reasons: '认真',
    periodKey: 'class',
    periodName: '上课',
    remark: '',
    timestamp: '08:00:00',
    date: '2026-10-01',
  );
}

AppData _data(String id, String name) => AppData(
      recordsByDate: {
        '2026-10-01': [_rec(id, name)],
      },
      settings: AppSettings.defaultSettings(),
    );

void main() {
  late Directory tempDir;
  late String mainPath;
  late StorageService storage;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_batch3');
    mainPath = '${tempDir.path}/class_management_data.enc';
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

  test('B-08 主文件被同长度篡改时，不覆盖最后一份可用 .bak', () async {
    expect(await storage.saveData(_data('a1', '第一份')), isTrue);
    expect(await storage.saveData(_data('b1', '第二份')), isTrue);
    // 此时 .bak 应是第一份数据。
    final mainFile = File(mainPath);
    final length = await mainFile.length();
    await mainFile.writeAsBytes(List<int>.filled(length, 0x41));

    expect(await storage.saveData(_data('c1', '第三份')), isTrue);

    final bakText = await File('$mainPath.bak').readAsString();
    final bak = await storage.decodeForTest(bakText);
    expect(bak, isNotNull, reason: '.bak 不应被同长度损坏内容覆盖');
    final names = bak!.recordsByDate.values
        .expand((records) => records)
        .map((record) => record.studentName);
    expect(names, contains('第一份'));
    expect(names, isNot(contains('第三份')));
  });

  test('B-08 backupTo 原子写入且内容可解析', () async {
    expect(await storage.saveData(_data('a1', '第一份')), isTrue);
    final target = '${tempDir.path}/手动备份.enc';
    expect(await storage.backupTo(target), isTrue);

    final text = await File(target).readAsString();
    final decoded = await storage.decodeForTest(text);
    expect(decoded?.recordsByDate['2026-10-01']?.single.studentName, '第一份');
  });

  test('B-09 备份列表包含主文件的 .bak（恢复出厂后可挽回）', () async {
    expect(await storage.saveData(_data('a1', '第一份')), isTrue);
    expect(await storage.saveData(_data('b1', '第二份')), isTrue);

    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(_data('c1', '当前'));
    final list = await provider.listBackupFiles();
    expect(
      list.any((entry) => entry.name.contains('.bak')),
      isTrue,
      reason: '从备份恢复的列表必须能看到主文件 .bak',
    );
  });

  test('B-10 saveNow 等待落盘并返回成功', () async {
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(_data('a1', '第一份'));
    expect(await provider.saveNow(), isTrue);
    expect(File(mainPath).existsSync(), isTrue);
  });

  test('B-10 saveNow 写盘失败时返回 false（不谎报成功）', () async {
    final blocker = File('${tempDir.path}/blocker')
      ..writeAsStringSync('not a directory');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? blocker.path
          : null,
    );

    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(_data('a1', '第一份'));
    expect(await provider.saveNow(), isFalse);
  });

  test('B-09 自动备份失败会记录原因，供主界面提示', () async {
    final blocker = File('${tempDir.path}/blocker')
      ..writeAsStringSync('not a directory');
    final provider = AppDataProvider();
    addTearDown(provider.dispose);
    provider.loadForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings.defaultSettings().copyWith(
          backupPath: '${blocker.path}/sub',
          backupFrequency: BackupFrequency.daily,
          backupLastAt: '',
        ),
      ),
    );

    final result = await provider.runScheduledBackup();
    expect(result, isNull);
    expect(provider.autoBackupError, isNotNull);
    expect(provider.autoBackupError, contains('备份失败'));
  });
}
