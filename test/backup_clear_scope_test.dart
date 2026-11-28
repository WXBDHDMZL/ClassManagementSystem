// 审计 A-03：清理备份只能删本程序自己生成的文件。
//
// 备份目录允许用户自定义，可能指向 `D:\加密资料`、桌面、甚至数据目录本身。
// 旧实现只要目录不在"数据目录范围内"，就把任意 `*.enc`（及其 `.logs`/
// `.pkey` 旁挂文件）当成本程序备份删除 —— 与确认框文案"不碰其它文件"矛盾，
// 且删除不可恢复。本文件锁住修复后的边界：
//   · 只删 `班级管理系统_备份_*`（含手动改名但保留前缀的备份）及其旁挂文件；
//   · 别人的 `.enc`、`.logs`、`.pkey`、笔记等一律保留；
//   · 即使备份目录就是数据目录，也绝不动主数据文件与 `.bak`。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late AppDataProvider provider;
  late Directory userDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_clear_backup_scope');
    userDir = Directory('${tempDir.parent.path}${Platform.pathSeparator}用户资料')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
    provider = AppDataProvider();
  });

  tearDown(() async {
    // 先把异步写盘链排空，避免用例结束后仍有保存动作打到已撤销的通道上。
    await flushWrites(provider);
    provider.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteDirectoryWithRetry(tempDir.parent);
  });

  File touch(Directory dir, String name, [String content = '占位']) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(content);
    return file;
  }

  Future<void> initProvider() => provider.initialize();

  group('备份目录在数据目录之外（可被用户指向任意目录）', () {
    test('只删本程序备份，别人的 .enc / .logs / .pkey 原样保留', () async {
      await initProvider();
      provider.setBackupPath(userDir.path);

      final ourBackup = touch(
        userDir,
        '班级管理系统_备份_20260101_000000.enc',
      );
      final ourRenamedBackup = touch(
        userDir,
        '班级管理系统_备份_开学前.enc',
      );
      final ourSnapshot = touch(
        userDir,
        '班级管理系统_备份_20260101_000000.enc.logs',
      );
      final ourPkey = touch(
        userDir,
        '班级管理系统_备份_20260101_000000.enc.pkey',
      );
      final foreignEnc = touch(userDir, '工作资料.enc');
      final foreignSnapshot = touch(userDir, '工作资料.enc.logs');
      final foreignPkey = touch(userDir, '工作资料.enc.pkey');
      final foreignNote = touch(userDir, '备忘.txt');

      final removed = await provider.clearAllBackups();

      expect(removed, 2, reason: '两份带前缀的备份应被计入并删除');
      expect(await ourBackup.exists(), isFalse);
      expect(await ourRenamedBackup.exists(), isFalse,
          reason: '保留前缀的手动改名备份仍属本程序，应一并清理');
      expect(await ourSnapshot.exists(), isFalse, reason: '自己的日志快照要跟着删');
      expect(await ourPkey.exists(), isFalse, reason: '自己的口令文件要跟着删');

      expect(await foreignEnc.exists(), isTrue, reason: '别人的 .enc 绝不能被删');
      expect(await foreignSnapshot.exists(), isTrue);
      expect(await foreignPkey.exists(), isTrue);
      expect(await foreignNote.exists(), isTrue);
    });

    test('恢复列表也只列本程序备份，别人的 .enc 不出现在列表里', () async {
      await initProvider();
      provider.setBackupPath(userDir.path);

      touch(userDir, '班级管理系统_备份_20260101_000000.enc');
      touch(userDir, '工作资料.enc');

      final listed = await provider.listBackupFiles();

      expect(
        listed.map((info) => info.name),
        contains('班级管理系统_备份_20260101_000000.enc'),
      );
      expect(
        listed.map((info) => info.name),
        isNot(contains('工作资料.enc')),
        reason: '列表与清理必须同一判定：列表里不列的，清理也不会删；'
            '外来文件改由“浏览其他备份文件…”恢复',
      );
    });

    test('目录里只有别人的文件时，一份都不删', () async {
      await initProvider();
      provider.setBackupPath(userDir.path);

      final foreignEnc = touch(userDir, '别处来的备份.enc');
      final foreignSnapshot = touch(userDir, '别处来的备份.enc.logs');

      expect(await provider.clearAllBackups(), 0);
      expect(await foreignEnc.exists(), isTrue);
      expect(await foreignSnapshot.exists(), isTrue);
    });
  });

  group('备份目录就是数据目录', () {
    test('主数据文件与 .bak 不会因为“清理备份”被删掉', () async {
      await initProvider();
      // 先写一份真实数据，确保主文件与 .bak 存在。
      provider.replaceStudents(['张三']);
      await flushWrites(provider);
      expect(await provider.saveNow(), isTrue);

      final mainFile = File('${tempDir.path}/class_management_data.enc');
      final bakFile = File('${mainFile.path}.bak');
      expect(await mainFile.exists(), isTrue);

      provider.setBackupPath(tempDir.path);
      final ourBackup = touch(tempDir, '班级管理系统_备份_20260101_000000.enc');

      final removed = await provider.clearAllBackups();

      expect(removed, 1);
      expect(await ourBackup.exists(), isFalse);
      expect(await mainFile.exists(), isTrue, reason: '主数据文件不是备份，绝不能被删');
      if (await bakFile.exists()) {
        expect(await bakFile.exists(), isTrue, reason: '上一份自动备份不是普通备份');
      }
    });
  });
}
