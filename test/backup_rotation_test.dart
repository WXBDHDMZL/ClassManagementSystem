// 备份行为回归：每次备份生成独立文件、自动保留最近 10 份、旧版固定名备份不被误删。
// 背景：用户反馈"选了每次退出备份，但看起来并没有备份"——原因是备份文件名固定，
// 每次都覆盖同一个文件，看起来永远只有一份。改动后每次都是带时间戳的新文件。
// 用临时目录 + mock 的文档目录，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/log_file_service.dart';

import 'test_helpers.dart';
import 'package:class_management_system/utils/app_clock.dart';

void main() {
  late Directory tempDir;
  // 每个用例把自己的 provider 挂到这里，tearDown 时先等它的写盘结束再删目录。
  AppDataProvider? provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    provider = null;
    tempDir = createStorageTestRoot('cms_backup_rotation');
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
    // N-1：performBackup 结尾是 fire-and-forget 的写盘，若不等它结束就删目录，
    // Windows 会因文件句柄被占用而拒绝删除（errno 32）→ 用例在 tearDown 偶发失败。
    await flushWrites(provider);
    await deleteStorageTestRoot(tempDir);
  });

  test('备份文件名带日期与秒：多次备份不会互相覆盖', () {
    final p = AppDataProvider();
    provider = p;
    expect(
      p.buildBackupFileName(DateTime(2026, 9, 30, 18, 38, 5)),
      '班级管理系统_备份_20260930_183805.enc',
    );
    expect(
      p.buildBackupFileName(DateTime(2026, 9, 30, 18, 38, 5)),
      isNot(p.buildBackupFileName(DateTime(2026, 9, 30, 18, 38, 6))),
      reason: '同一分钟内连点两次也要生成两份，而不是覆盖',
    );
  });

  test('自动备份只保留最近 10 份，旧版固定名备份不被误删', () async {
    // 确定性版本：轮换按**文件名**（内含时间戳）排序，不再依赖文件修改时间——
    // 后者受文件系统时间精度影响，曾造成偶发失败。
    final p = AppDataProvider();
    provider = p;
    final dir = Directory('${tempDir.path}/备份')
      ..createSync(recursive: true);

    // 造 12 份较早的自动备份（名称里的日期递增，最早为 09-01，最晚为 09-12）
    for (var index = 1; index <= 12; index++) {
      File(
        '${dir.path}/班级管理系统_备份_202609${index.toString().padLeft(2, '0')}_120000.enc',
      ).writeAsStringSync('old-$index');
    }
    // 旧版固定名备份：必须保留
    final legacy = File('${dir.path}/班级管理系统_备份.enc')
      ..writeAsStringSync('legacy');

    final result = await p.performBackup();
    expect(result.isSuccess, isTrue, reason: result.error ?? '');

    final automatic = dir
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.path.split(RegExp(r'[/\\]')).last;
          return name.startsWith('${AppDataProvider.backupFilePrefix}_') &&
              name.endsWith('.enc');
        })
        .map((file) => file.path.split(RegExp(r'[/\\]')).last)
        .toList()
      ..sort();

    expect(
      automatic.length,
      AppDataProvider.backupKeepCount,
      reason: '自动备份应只保留最近 ${AppDataProvider.backupKeepCount} 份；实际保留：$automatic',
    );
    // 保留的应该是最新的 10 个名字：最早的 3 个（09-01/09-02/09-03）必须被清掉
    expect(
      automatic.contains('班级管理系统_备份_20260901_120000.enc'),
      isFalse,
      reason: '最旧的应被清理；实际保留：$automatic',
    );
    expect(
      automatic.contains('班级管理系统_备份_20260903_120000.enc'),
      isFalse,
      reason: '第 3 旧的应被清理；实际保留：$automatic',
    );
    expect(
      automatic.contains('班级管理系统_备份_20260904_120000.enc'),
      isTrue,
      reason: '第 10 新的应被保留；实际保留：$automatic',
    );
    expect(legacy.existsSync(), isTrue, reason: '旧版固定名备份不能被自动清理');

    final savedName = (result.savedPath ?? '').split(RegExp(r'[/\\]')).last;
    expect(
      savedName.isNotEmpty && automatic.contains(savedName),
      isTrue,
      reason: '本次刚生成的备份必须还在；实际保留：$automatic',
    );
  });

  test('手动改名的备份不参与轮换：不被误删，也不占用保留名额', () async {
    final p = AppDataProvider();
    provider = p;
    final dir = Directory('${tempDir.path}/备份')
      ..createSync(recursive: true);

    // 11 份正常的带时间戳备份（备份后共 12 份，应清掉最旧 2 份）
    for (var index = 1; index <= 11; index++) {
      File(
        '${dir.path}/班级管理系统_备份_202609${index.toString().padLeft(2, '0')}_120000.enc',
      ).writeAsStringSync('old-$index');
    }
    // 手动复制的改名件（没有时间戳）与时间戳格式不完整的文件：
    // 都不能被当成"自动备份"参与清理，否则用户自己保存的备份可能被误删。
    final renamed = File('${dir.path}/班级管理系统_备份_我的手动备份.enc')
      ..writeAsStringSync('renamed');
    final malformed = File('${dir.path}/班级管理系统_备份_2026099_120000.enc')
      ..writeAsStringSync('malformed');

    final result = await p.performBackup();
    expect(result.isSuccess, isTrue, reason: result.error ?? '');

    expect(renamed.existsSync(), isTrue, reason: '改名件不是自动备份，不能被误删');
    expect(malformed.existsSync(), isTrue, reason: '时间戳格式不完整的文件不能被误删');

    // 只统计"完整时间戳格式"的文件：应恰好保留最近 10 份。
    final tsPattern = RegExp(r'^班级管理系统_备份_\d{8}_\d{6}\.enc');
    final kept = dir.listSync().whereType<File>().map(
      (file) => file.path.split(RegExp(r'[/\\]')).last,
    ).toList();
    final timestamped = kept.where((name) {
      final m = tsPattern.firstMatch(name);
      return m != null && m.end == name.length;
    }).toList();

    expect(
      timestamped.length,
      AppDataProvider.backupKeepCount,
      reason: '改名件不占保留名额，时间戳备份应恰好保留 '
          '${AppDataProvider.backupKeepCount} 份；实际：$kept',
    );
    expect(
      timestamped.contains('班级管理系统_备份_20260901_120000.enc'),
      isFalse,
      reason: '最旧的仍应被清理；实际保留：$kept',
    );
  });

  test('每次备份都是一份新文件（连备三次得到三份）', () async {
    final p = AppDataProvider();
    provider = p;
    final dir = Directory('${tempDir.path}/备份');

    // 备份文件名精确到秒，所以要等"秒"变化再备下一次，避免同一秒内名称相同。
    // 不能用固定 sleep：并发跑测试时容易踩到同一秒里，出现偶发失败。
    Future<void> backupAtNextSecond() async {
      await p.performBackup();
      final second = AppClock.now().second;
      var guard = 0;
      while (AppClock.now().second == second && guard < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        guard++;
      }
    }

    await backupAtNextSecond();
    await backupAtNextSecond();
    await backupAtNextSecond();

    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.endsWith('.logs'))
        .toList();
    expect(files.length, 3, reason: '三次备份应当有三份文件，而不是覆盖成一份');
    expect(
      files.map((file) => file.path.split(RegExp(r'[/\\]')).last).toSet().length,
      3,
      reason: '文件名各不相同',
    );
  });

  test('保留份数可配置：设为 3 时只保留 3 份自动备份', () async {
    final p = AppDataProvider();
    provider = p;
    p.setBackupKeepCount(3);
    final dir = Directory('${tempDir.path}/备份')
      ..createSync(recursive: true);
    for (var index = 1; index <= 5; index++) {
      File(
        '${dir.path}/班级管理系统_备份_202609${index.toString().padLeft(2, '0')}_120000.enc',
      ).writeAsStringSync('old-$index');
    }

    final result = await p.performBackup();
    expect(result.isSuccess, isTrue, reason: result.error ?? '');

    final automatic = dir
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.path.split(RegExp(r'[/\\]')).last;
          return name.startsWith('${AppDataProvider.backupFilePrefix}_') &&
              name.endsWith('.enc');
        })
        .toList();
    expect(automatic.length, 3, reason: '保留份数由设置控制');
  });

  test('备份生成日志快照，轮换时连同快照一起清理', () async {
    final p = AppDataProvider();
    provider = p;
    final dir = Directory('${tempDir.path}/备份')
      ..createSync(recursive: true);
    final logDir = Directory('${tempDir.path}/日志')..createSync(recursive: true);
    await LogFileService.append(
      LogFileService.fileIn(logDir),
      LogFileService.prefixOperation,
      '2026-11-15 09:00:00  测试日志',
    );
    for (var index = 1; index <= 12; index++) {
      final name =
          '班级管理系统_备份_202609${index.toString().padLeft(2, '0')}_120000.enc';
      File('${dir.path}/$name').writeAsStringSync('old-$index');
      File('${dir.path}/$name.logs').writeAsStringSync('old-log-$index');
    }

    final result = await p.performBackup();
    expect(result.isSuccess, isTrue, reason: result.error ?? '');

    final snapshot = File('${result.savedPath}.logs');
    expect(await snapshot.exists(), isTrue, reason: '本次备份应带日志快照');

    final keptBackups = dir.listSync().whereType<File>().where((file) {
      final name = file.path.split(RegExp(r'[/\\]')).last;
      return name.startsWith('${AppDataProvider.backupFilePrefix}_') &&
          name.endsWith('.enc');
    }).toList();
    expect(keptBackups.length, AppDataProvider.backupKeepCount);
    for (final file in keptBackups) {
      expect(
        await File('${file.path}.logs').exists(),
        isTrue,
        reason: '保留的每份备份都应有日志快照：${file.path}',
      );
    }
    expect(
      await File('${dir.path}/班级管理系统_备份_20260901_120000.enc.logs')
          .exists(),
      isFalse,
      reason: '被轮换掉的旧备份，其日志快照也应删除',
    );
  });

  test('清除全部备份时一并删除日志快照', () async {
    final p = AppDataProvider();
    provider = p;
    final dir = Directory('${tempDir.path}/备份')
      ..createSync(recursive: true);
    File('${dir.path}/班级管理系统_备份_20260901_120000.enc')
        .writeAsStringSync('data');
    File('${dir.path}/班级管理系统_备份_20260901_120000.enc.logs')
        .writeAsStringSync('logs');
    File('${dir.path}/手动备份.enc').writeAsStringSync('manual');
    File('${dir.path}/其他文件.txt').writeAsStringSync('keep');

    final removed = await p.clearAllBackups();
    expect(removed, 2,
        reason: '清理范围必须与“从备份恢复”列表一致：列表里能选中的备份都要删掉，'
            '日志快照不计入份数');
    expect(File('${dir.path}/手动备份.enc').existsSync(), isFalse,
        reason: '手动改名的备份同样出现在恢复列表里，必须一并删除');
    expect(dir.listSync().whereType<File>().map((f) => f.path.endsWith('.logs')),
        isNot(contains(true)));
    expect(File('${dir.path}/其他文件.txt').existsSync(), isTrue,
        reason: '备份目录中的其它文件不能删除');
  });

  test('从备份恢复日志只补齐缺少的条目，不删除较新的日志', () async {
    final p = AppDataProvider();
    provider = p;
    final logDir = Directory('${tempDir.path}/日志')..createSync(recursive: true);
    final logFile = File('${logDir.path}/班级管理系统_日志.txt');
    await LogFileService.append(
      logFile,
      LogFileService.prefixOperation,
      '2026-09-01 10:00:00  操作  备份前',
    );

    final result = await p.performBackup();
    expect(result.isSuccess, isTrue, reason: result.error ?? '');
    final backupPath = result.savedPath!;
    expect(await File('$backupPath.logs').exists(), isTrue);

    await LogFileService.append(
      logFile,
      LogFileService.prefixOperation,
      '2026-09-02 10:00:00  操作  备份后',
    );

    final error = await p.restoreLogsFromSnapshot(backupPath);
    expect(error, isNull);
    final entries = await LogFileService.readEntries(
      logFile,
      LogFileService.prefixOperation,
    );
    expect(entries.any((e) => e.contains('备份前')), isTrue);
    expect(entries.any((e) => e.contains('备份后')), isTrue,
        reason: '恢复日志只能合并，不能覆盖较新的条目');
  });
}
