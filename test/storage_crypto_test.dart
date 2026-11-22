/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.13.7
 * 创建日期 (Created): 2026-11-22
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/storage_crypto.dart';
import 'package:class_management_system/services/storage_key_store.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  test('LRX3 往返并带每文件随机盐', () {
    const plain = '{"students":["张三"],"note":"换行\\n测试"}';
    final a = StorageCrypto.encodeV3(plain, key);
    final b = StorageCrypto.encodeV3(plain, key);

    expect(StorageCrypto.looksEncrypted(a), isTrue);
    expect(a, isNot(b));
    expect(StorageCrypto.decodeV3(a, key), plain);
    expect(StorageCrypto.decodeV3(b, key), plain);
  });

  test('LRX3 篡改与错误密钥都被拒绝', () {
    final text = StorageCrypto.encodeV3('hello', key);
    final bytes = base64Decode(text);
    bytes[bytes.length - 1] ^= 0xFF;
    expect(StorageCrypto.decodeV3(base64Encode(bytes), key), isNull);

    final wrong = Uint8List.fromList(List<int>.filled(32, 7));
    expect(StorageCrypto.decodeV3(text, wrong), isNull);
    expect(StorageCrypto.decodeV3('not-base64', key), isNull);
  });

  test('LRX2 魔数只被识别为旧格式，不会被 V3 解码', () {
    final fakeV2 = base64Encode([
      ...StorageCrypto.magicV2,
      ...List<int>.filled(16 + 16 + 32, 0),
    ]);
    expect(StorageCrypto.isV2(base64Decode(fakeV2)), isTrue);
    expect(StorageCrypto.decodeV3(fakeV2, key), isNull);
  });

  test('Windows DPAPI 密钥可重复读取，损坏时不重建', () async {
    if (!Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('cms_key_store_');
    try {
      final file = File('${dir.path}\\class_management_data.enc.key');
      final store = StorageKeyStore(file);

      final first = await store.loadOrCreate();
      expect(first.length, 32);
      final second = await store.loadOrCreate();
      expect(second, first);

      await file.writeAsString('broken');
      await expectLater(store.loadOrCreate(), throwsFormatException);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('密钥文件缺失且禁止创建时拒绝生成新钥', () async {
    final dir = await Directory.systemTemp.createTemp('cms_key_missing_');
    try {
      final file = File('${dir.path}\\class_management_data.enc.key');
      final store = StorageKeyStore(file);
      await expectLater(
        store.loadOrCreate(createIfMissing: false),
        throwsFormatException,
      );
      expect(await file.exists(), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
