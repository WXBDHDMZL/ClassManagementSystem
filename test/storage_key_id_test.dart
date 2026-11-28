// 数据密钥指纹（旁挂 `.keyid` 文件）的单元测试 —— 审计 A-02。
//
// 指纹只用于区分"密钥不对"与"文件损坏"，本身不含密钥材料、不是安全边界：
// 所以这里只验证"算得稳、判得准、读写不抛"。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/storage_key_id.dart';

import 'test_helpers.dart';

void main() {
  Uint8List keyOf(int seed) =>
      Uint8List.fromList(List<int>.generate(32, (i) => (i + seed) & 0xFF));

  group('StorageKeyId.compute', () {
    test('同一个密钥总是算出同一个指纹', () {
      final key = keyOf(1);
      expect(StorageKeyId.compute(key), StorageKeyId.compute(key));
    });

    test('不同密钥算出不同指纹', () {
      expect(StorageKeyId.compute(keyOf(1)), isNot(StorageKeyId.compute(keyOf(2))));
    });

    test('指纹是 16 位小写十六进制', () {
      final id = StorageKeyId.compute(keyOf(7));
      expect(id, hasLength(16));
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('指纹与密钥本身可区分（不含密钥字节的明文）', () {
      final key = keyOf(3);
      final id = StorageKeyId.compute(key);
      // 指纹是 HMAC 式摘要，不应等于密钥前 8 字节的十六进制。
      final rawPrefix = key
          .take(8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(id, isNot(rawPrefix));
    });
  });

  group('StorageKeyId.parse / isValidContent', () {
    test('接受带前缀的合法内容（允许首尾空白与换行）', () {
      const valid = '${StorageKeyId.prefix}0123456789abcdef';
      expect(StorageKeyId.isValidContent(valid), isTrue);
      expect(StorageKeyId.isValidContent('$valid\n'), isTrue);
      expect(StorageKeyId.parse('  $valid  '), '0123456789abcdef');
    });

    test('拒绝缺少前缀的内容', () {
      expect(StorageKeyId.isValidContent('0123456789abcdef'), isFalse);
      expect(StorageKeyId.parse('0123456789abcdef'), isNull);
    });

    test('拒绝长度不对的指纹', () {
      expect(StorageKeyId.isValidContent('${StorageKeyId.prefix}0123456'), isFalse);
      expect(
        StorageKeyId.isValidContent('${StorageKeyId.prefix}0123456789abcdef0'),
        isFalse,
      );
      expect(StorageKeyId.parse('${StorageKeyId.prefix}0123456'), isNull);
    });

    test('拒绝非十六进制字符', () {
      expect(
        StorageKeyId.isValidContent('${StorageKeyId.prefix}0123456789abcdeZ'),
        isFalse,
      );
    });

    test('拒绝空内容', () {
      expect(StorageKeyId.isValidContent(''), isFalse);
      expect(StorageKeyId.isValidContent('   '), isFalse);
      expect(StorageKeyId.parse(''), isNull);
    });
  });

  group('StorageKeyId.read / write', () {
    late Directory tempDir;

    setUp(() {
      tempDir = createStorageTestRoot('cms_keyid');
    });

    tearDown(() async {
      await deleteStorageTestRoot(tempDir);
    });

    File keyIdFile() =>
        File('${tempDir.path}/class_management_data.enc${StorageKeyId.fileSuffix}');

    test('文件不存在时返回 null（不抛异常）', () async {
      expect(await StorageKeyId.read(keyIdFile()), isNull);
    });

    test('写入后能原值读回', () async {
      final keyId = StorageKeyId.compute(keyOf(9));
      expect(await StorageKeyId.write(keyIdFile(), keyId), isTrue);
      expect(await keyIdFile().exists(), isTrue);
      expect(await StorageKeyId.read(keyIdFile()), keyId);
    });

    test('再次写入会覆盖旧值', () async {
      final first = StorageKeyId.compute(keyOf(1));
      final second = StorageKeyId.compute(keyOf(2));
      expect(await StorageKeyId.write(keyIdFile(), first), isTrue);
      expect(await StorageKeyId.write(keyIdFile(), second), isTrue);
      expect(await StorageKeyId.read(keyIdFile()), second);
    });

    test('内容被改坏时读回 null（视为缺失，不阻断启动）', () async {
      await keyIdFile().writeAsString('乱码内容');
      expect(await StorageKeyId.read(keyIdFile()), isNull);
    });

    test('父目录不存在时会自动创建后写入（AtomicFile 既有行为）', () async {
      final nested = File('${tempDir.path}/新建子目录/x.keyid');
      expect(nested.parent.existsSync(), isFalse);
      expect(
        await StorageKeyId.write(nested, StorageKeyId.compute(keyOf(4))),
        isTrue,
      );
      expect(nested.parent.existsSync(), isTrue, reason: '写入会自动补建父目录');
      expect(await StorageKeyId.read(nested), StorageKeyId.compute(keyOf(4)));
    });
  });
}
