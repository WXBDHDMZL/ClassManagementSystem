// 审计 A-01 / A-18a：启动进入"数据阻断"后，界面不得再出现"看起来成功、
// 其实没写盘"的假成功。本文件从 provider 视角验收：
//   · 阻断时数据入口一律拒绝（返回 null/0/false），磁盘不被改动；
//   · 每次拒绝都给用户一条可见提示（blockedActionNotice），且不重复轰炸；
//   · 用户确认"以空库继续"之后才恢复可写，并能真正落盘；
//   · 错钥（A-02）同样阻断，且在用户确认前主文件一个字节都不动。
//
// 全部在 mock 的临时文档目录里跑，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late Uint8List keyA;
  late Uint8List keyB;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_startup_block');
    keyA = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    keyB = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));
    StorageService.debugDataKeyOverride = keyA;
    StorageService.debugResetKey();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
  });

  tearDown(() async {
    StorageService.debugDataKeyOverride =
        Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    StorageService.debugResetKey();
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

  group('损坏隔离（A-01）', () {
    test('启动即阻断：记录入口拒绝写入、磁盘不变、提示可见', () async {
      await mainFile().writeAsString('损坏内容!!!');
      final provider = AppDataProvider();
      addTearDown(provider.dispose);

      await provider.initialize();

      expect(provider.storageWriteBlocked, isTrue);
      expect(provider.needsEmptyLibraryConfirm, isTrue);
      expect(provider.keyMismatchBlocked, isFalse);
      expect(provider.startupNoticeIsError, isTrue);
      expect(provider.startupNotice, contains('隔离'));
      expect(await mainFile().exists(), isFalse);

      final added = provider.addRecord('张三', '表扬', ['认真听讲'], 'class', '');
      expect(added, isNull, reason: '阻断态下不得返回"新增成功"');
      expect(await mainFile().exists(), isFalse, reason: '拒绝写入时不得重建主文件');
      expect(corruptFiles(), hasLength(1), reason: '隔离副本必须保留');

      expect(await provider.saveNow(), isFalse, reason: '强制保存也必须被拒绝');
      expect(provider.blockedActionNotice, isNotNull,
          reason: '拒绝写入必须给出用户可见的提示');
    });

    test('同一次阻断期间的多次拒绝只提示一次，消费后可再次提示', () async {
      await mainFile().writeAsString('损坏内容!!!');
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      await provider.initialize();

      provider.addRecord('张三', '表扬', ['认真听讲'], 'class', '');
      final serialAfterFirst = provider.blockedActionNoticeSerial;
      expect(serialAfterFirst, greaterThan(0));

      provider.addRecord('李四', '批评', ['迟到'], 'class', '');
      provider.clearAttendance('2026-11-21');
      expect(provider.blockedActionNoticeSerial, serialAfterFirst,
          reason: '同一次阻断未消费前不得重复递增，避免连续弹提示');

      provider.clearBlockedActionNotice();
      expect(provider.blockedActionNotice, isNull);

      provider.addRecord('王五', '表扬', ['主动帮助同学'], 'class', '');
      expect(provider.blockedActionNoticeSerial, greaterThan(serialAfterFirst),
          reason: '提示被消费后再次拒绝应重新提示');
    });

    test('阻断态下"恢复出厂"与"清理备份"被拒绝', () async {
      await mainFile().writeAsString('损坏内容!!!');
      // 造一份备份，确认阻断时它不会被清掉（可能是唯一可恢复的数据）。
      final backupDir = Directory('${tempDir.path}/备份');
      await backupDir.create(recursive: true);
      final backup = File('${backupDir.path}/班级管理系统_备份_20260101_000000.enc');
      await backup.writeAsString('备份内容占位');

      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      await provider.initialize();

      expect(await provider.factoryReset(), isFalse,
          reason: '阻断态不得恢复出厂（会删唯一可恢复的备份与隔离文件）');
      expect(await provider.clearAllBackups(), 0, reason: '阻断态不得清理备份');
      expect(await backup.exists(), isTrue, reason: '备份必须原样保留');
    });

    test('确认"以空库继续"后恢复可写，并真正落盘', () async {
      await mainFile().writeAsString('损坏内容!!!');
      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      await provider.initialize();
      expect(provider.storageWriteBlocked, isTrue);

      expect(await provider.confirmEmptyLibrary(), isTrue);
      expect(provider.storageWriteBlocked, isFalse);
      expect(provider.needsEmptyLibraryConfirm, isFalse);
      expect(provider.startupNoticeIsError, isFalse);

      final added = provider.addRecord('张三', '表扬', ['认真听讲'], 'class', '');
      expect(added, isNotNull, reason: '确认后必须恢复正常写入');
      await flushWrites(provider);

      expect(await mainFile().exists(), isTrue);
      final reloaded = await StorageService().loadData();
      final names = reloaded.data.recordsByDate.values
          .expand((records) => records)
          .map((record) => record.studentName)
          .toList();
      expect(names, contains('张三'), reason: '确认后新增的记录必须真的落盘');
      expect(corruptFiles(), hasLength(1), reason: '确认后也不得删除隔离副本');
    });
  });

  group('错钥阻断（A-02）', () {
    test('密钥不匹配：阻断写入、主文件逐字节不变、提示指明换回密钥', () async {
      // 先用 keyA 正常存一份数据（保存过程会写下 keyA 的指纹）。
      await StorageService().loadData();
      expect(
        await StorageService().saveData(
          AppData.fromJson(const {'students': ['张三']}),
        ),
        isTrue,
      );

      // 换成 keyB：主文件仍是 keyA 写的，指纹也是 keyA 的 → 错钥。
      StorageService.debugDataKeyOverride = keyB;
      StorageService.debugResetKey();
      final before = await mainFile().readAsBytes();

      final provider = AppDataProvider();
      addTearDown(provider.dispose);
      await provider.initialize();

      expect(provider.keyMismatchBlocked, isTrue);
      expect(provider.storageWriteBlocked, isTrue);
      expect(provider.startupNotice, contains('密钥不匹配'));
      expect(await mainFile().readAsBytes(), before,
          reason: '错钥时主文件必须逐字节保持原样');
      expect(corruptFiles(), isEmpty, reason: '错钥不是损坏，不得隔离');

      expect(provider.addRecord('李四', '表扬', ['认真听讲'], 'class', ''), isNull);
      expect(await provider.saveNow(), isFalse);
      expect(provider.blockedActionNotice, contains('密钥'),
          reason: '提示必须告诉用户"换回原密钥"而不是笼统的"写入被拒绝"');
    });
  });
}
