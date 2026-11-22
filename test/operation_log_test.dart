// 操作日志测试：行格式、追加写入、超限时保留尾部、尾部读取顺序。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/operation_log_service.dart';

void main() {
  test('日志行格式：时间 + 操作 + 明细（明细为空时不留多余空格）', () {
    final time = DateTime(2026, 9, 26, 18, 40, 12);
    expect(
      OperationLogService.formatLogLine(time, '删除记录', '张三 · 批评 · 迟到'),
      '2026-09-26 18:40:12  删除记录  张三 · 批评 · 迟到',
    );
    expect(
      OperationLogService.formatLogLine(time, '恢复出厂'),
      '2026-09-26 18:40:12  恢复出厂',
    );
  });

  test('追加写入：多行按顺序保存，尾部读取返回新→旧', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('cms_log_test').path}/log.txt',
    );
    await OperationLogService.appendLineTo(file, '第一行');
    await OperationLogService.appendLineTo(file, '第二行');
    await OperationLogService.appendLineTo(file, '第三行');

    final tail = await OperationLogService.readTail(file);
    expect(tail, ['第三行', '第二行', '第一行']);
    final raw = await file.readAsString();
    expect(raw, isNot(contains('第二行')), reason: '日志落盘必须是密文');
    expect(await EncryptedTextFile.readAllText(file), contains('第二行'));
  });

  test('尾部读取限制条数：只取最近 N 条', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('cms_log_test2').path}/log.txt',
    );
    for (var i = 1; i <= 10; i++) {
      await OperationLogService.appendLineTo(file, '第 $i 行');
    }

    final tail = await OperationLogService.readTail(file, maxLines: 3);
    expect(tail, ['第 10 行', '第 9 行', '第 8 行']);
  });

  test('日志全量保留：写入很多行也不截断', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('cms_log_test3').path}/log.txt',
    );
    for (var i = 1; i <= 300; i++) {
      await OperationLogService.appendLineTo(file, '第 $i 行');
    }

    final tail = await OperationLogService.readTail(file);
    expect(tail.length, 300);
    expect(tail.first, '第 300 行');
    expect(tail.last, '第 1 行');
    expect(await EncryptedTextFile.readAllText(file), contains('第 1 行'));
  });
}
