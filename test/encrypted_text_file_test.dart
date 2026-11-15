/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/storage_service.dart';

void main() {
  group('本地文本加密（LRX2）', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('cms_enc_text_');
    });

    tearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    test('逐行加密：磁盘不含明文，读取能还原', () async {
      final file = File('${temp.path}/log.txt');
      await EncryptedTextFile.appendLine(file, '第一行 张三 迟到');
      await EncryptedTextFile.appendLine(file, '第二行 李四 请假');

      final raw = await file.readAsString();
      expect(raw, isNot(contains('张三')));
      expect(raw, isNot(contains('第一行')));
      expect(StorageService.looksLikeEncryptedText(raw.split('\n').first), isTrue);

      expect(
        await EncryptedTextFile.readLines(file),
        ['第一行 张三 迟到', '第二行 李四 请假'],
      );
    });

    test('旧明文行不再读取，只读取新追加的密文', () async {
      final file = File('${temp.path}/legacy.txt');
      await file.writeAsString('旧明文一\n旧明文二\n');

      await EncryptedTextFile.appendLine(file, '新记录');

      final raw = await file.readAsString();
      expect(raw, isNot(contains('新记录')));
      expect(await EncryptedTextFile.readLines(file), ['新记录']);
    });

    test('多行错误块作为一条记录加密，导出时可还原换行', () async {
      final file = File('${temp.path}/error.txt');
      const block = '时间  2026-10-24\n模块  test\n错误  bad';
      await EncryptedTextFile.appendLine(file, block);
      expect(await EncryptedTextFile.readAllText(file), contains(block));
      final raw = await file.readAsString();
      expect(raw, isNot(contains('模块')));
    });

    test('损坏密文行被跳过，不抛异常', () async {
      final file = File('${temp.path}/bad.txt');
      await file.writeAsString('TFJYMg==损坏\n');
      expect(await EncryptedTextFile.readLines(file), isEmpty);
    });
  });
}
