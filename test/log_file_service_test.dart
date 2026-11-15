/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.3
 * 创建日期 (Created): 2026-11-14
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/log_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    LogFileService.disableProtectionForTests = true;
    dir = await Directory.systemTemp.createTemp('cms_log_file_test');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('识别旧日志文件名', () {
    expect(LogFileService.isLegacyLogFile('班级管理系统_操作日志.txt'), isTrue);
    expect(
      LogFileService.isLegacyLogFile('班级管理系统_操作日志_2026-10.txt'),
      isTrue,
    );
    expect(
      LogFileService.isLegacyLogFile('班级管理系统_错误日志_2026-11.txt'),
      isTrue,
    );
    expect(LogFileService.isLegacyLogFile('班级管理系统_日志.txt'), isFalse);
    expect(
      LogFileService.isLegacyLogFile('班级管理系统_操作日志_DEV_2026-10.txt'),
      isFalse,
    );
    expect(LogFileService.isLegacyLogFile('无关文件.txt'), isFalse);
  });

  test('append 写入单文件，readEntries 只返回对应类别', () async {
    final file = LogFileService.fileIn(dir);
    await LogFileService.append(
      file,
      LogFileService.prefixOperation,
      '2026-10-01 10:00:00  新增记录  张三',
    );
    await LogFileService.append(
      file,
      LogFileService.prefixError,
      '时间  2026-10-01 11:00:00\n错误  测试错误',
    );

    final operations = await LogFileService.readEntries(
      file,
      LogFileService.prefixOperation,
    );
    final errors = await LogFileService.readEntries(
      file,
      LogFileService.prefixError,
    );

    expect(operations, hasLength(1));
    expect(operations.single, contains('新增记录'));
    expect(errors, hasLength(1));
    expect(errors.single, contains('测试错误'));
    // 磁盘上是加密行，不应出现明文。
    final raw = await file.readAsString();
    expect(raw.contains('新增记录'), isFalse);
  });

  test('mergeLegacyLogs 合并旧文件并按时间排序，旧文件归档', () async {
    final oldOperation = File('${dir.path}/班级管理系统_操作日志_2026-10.txt');
    final oldError = File('${dir.path}/班级管理系统_错误日志_2026-09.txt');
    await EncryptedTextFile.appendLine(
      oldOperation,
      '2026-10-02 09:00:00  十月操作',
    );
    await EncryptedTextFile.appendLine(
      oldOperation,
      '2026-10-01 09:00:00  十月较早操作',
    );
    await EncryptedTextFile.appendLine(
      oldError,
      '时间  2026-09-30 08:00:00\n错误  九月错误',
    );

    final merged = await LogFileService.mergeLegacyLogs(dir);

    expect(merged, 2);
    final file = LogFileService.fileIn(dir);
    expect(await file.exists(), isTrue);
    final entries = await EncryptedTextFile.readLines(file);
    expect(entries, hasLength(3));
    expect(entries.first, contains('九月错误'), reason: '最早的时间排在最前');
    expect(entries[1], contains('十月较早操作'));
    expect(entries.last, contains('十月操作'));
    expect(await oldOperation.exists(), isFalse, reason: '旧文件应移入归档');
    final archives = dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('历史归档_'))
        .toList();
    expect(archives, hasLength(1));
    expect(
      File('${archives.single.path}/班级管理系统_操作日志_2026-10.txt').existsSync(),
      isTrue,
    );
  });

  test('mergeLegacyLogs 重复执行不会重复合并', () async {
    await EncryptedTextFile.appendLine(
      File('${dir.path}/班级管理系统_操作日志.txt'),
      '2026-10-01 09:00:00  只合并一次',
    );
    expect(await LogFileService.mergeLegacyLogs(dir), 1);
    expect(await LogFileService.mergeLegacyLogs(dir), 0);
    final entries = await EncryptedTextFile.readLines(
      LogFileService.fileIn(dir),
    );
    expect(entries.where((e) => e.contains('只合并一次')), hasLength(1));
  });

  test('pruneBefore 只删除截止时间前的条目', () async {
    final file = LogFileService.fileIn(dir);
    await LogFileService.append(
      file,
      LogFileService.prefixOperation,
      '2026-01-01 08:00:00  很旧的操作',
    );
    await LogFileService.append(
      file,
      LogFileService.prefixOperation,
      '2026-10-01 08:00:00  新的操作',
    );
    await LogFileService.append(
      file,
      LogFileService.prefixError,
      '时间  2026-01-02 08:00:00\n错误  很旧的错误',
    );

    final removed = await LogFileService.pruneBefore(
      file,
      DateTime(2026, 6, 1),
    );

    expect(removed, 2);
    final operations = await LogFileService.readEntries(
      file,
      LogFileService.prefixOperation,
    );
    final errors = await LogFileService.readEntries(
      file,
      LogFileService.prefixError,
    );
    expect(operations, hasLength(1));
    expect(operations.single, contains('新的操作'));
    expect(errors, isEmpty);
  });

  test('deleteAllLogs 删除合并文件与归档目录', () async {
    final file = LogFileService.fileIn(dir);
    await LogFileService.append(
      file,
      LogFileService.prefixOperation,
      '2026-10-01 08:00:00  待删除',
    );
    final archive = Directory('${dir.path}/历史归档_20261001_080000');
    await archive.create(recursive: true);
    await File('${archive.path}/班级管理系统_操作日志.txt').writeAsString('旧');

    final removed = await LogFileService.deleteAllLogs(dir);

    expect(removed, greaterThanOrEqualTo(2));
    expect(await file.exists(), isFalse);
    expect(await archive.exists(), isFalse);
  });

  test('mergeSnapshot 只补充缺少的条目并按时间合并', () async {
    final target = LogFileService.fileIn(dir);
    final snapshot = File('${dir.path}${Platform.pathSeparator}snapshot.logs');
    await LogFileService.append(
      target,
      LogFileService.prefixOperation,
      '2026-10-02 09:00:00  新增记录  乙',
    );
    await LogFileService.append(
      snapshot,
      LogFileService.prefixOperation,
      '2026-10-01 08:00:00  新增记录  甲',
    );
    await LogFileService.append(
      snapshot,
      LogFileService.prefixOperation,
      '2026-10-02 09:00:00  新增记录  乙',
    );
    await LogFileService.append(
      snapshot,
      LogFileService.prefixError,
      '时间  2026-10-03 10:00:00\n错误  示例',
    );

    final added = await LogFileService.mergeSnapshot(snapshot, target: target);
    expect(added, 2, reason: '只有甲和错误条目是当前日志没有的');

    final all = await EncryptedTextFile.readLines(target);
    expect(all, hasLength(3));
    expect(all.first, contains('甲'));
    expect(all.last, contains('示例'));
    // 再次合并同一快照不会重复追加。
    expect(await LogFileService.mergeSnapshot(snapshot, target: target), 0);
  });
}
