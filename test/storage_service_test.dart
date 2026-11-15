// 存储层测试：新版加密格式（LRX2）往返、
// 篡改/损坏检测、以及原子写替换。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/services/storage_service.dart';

void main() {
  final storage = StorageService();

  test('保存后能原样读回（新版 LRX2 格式）', () async {
    final data = AppData(
      recordsByDate: const {},
      settings: AppSettings(themeMode: ThemeModeType.dark),
      students: const ['张三', '李四'],
    );

    // 直接走服务内部的编解码链路（不写真实文档目录）。
    final text = await storage.encodeForTest(data);
    final restored = await storage.decodeForTest(text);
    expect(restored, isNotNull);
    expect(restored!.students, ['张三', '李四']);
    expect(restored.settings.themeMode, ThemeModeType.dark);
  });

  test('旧数据缺少 students 字段时不会回填真实名单', () {
    final data = AppData.fromJson(<String, dynamic>{
      'recordsByDate': <String, dynamic>{},
      'settings': <String, dynamic>{},
    });

    expect(data.students, isEmpty);
  });

  test('空名单往返仍为空，不会被旧出厂名单回填', () async {
    final data = AppData.empty();
    expect(data.students, isEmpty);

    final text = await storage.encodeForTest(data);
    final restored = await storage.decodeForTest(text);

    expect(restored, isNotNull);
    expect(restored!.students, isEmpty);
  });

  test('新版格式带每文件随机盐：同一份数据两次编码结果不同', () async {
    final data = AppData.empty();
    final a = await storage.encodeForTest(data);
    final b = await storage.encodeForTest(data);
    expect(a, isNot(b));
  });

  test('篡改密文会被完整性校验拒绝（返回 null）', () async {
    final text = await storage.encodeForTest(AppData.empty());
    final bytes = base64Decode(text);
    // 改动末尾的校验标签
    bytes[bytes.length - 1] ^= 0xFF;
    expect(await storage.decodeForTest(base64Encode(bytes)), isNull);

    // 改动中间的密文
    final bytes2 = base64Decode(text);
    if (bytes2.length > 60) {
      bytes2[50] ^= 0x01;
      expect(await storage.decodeForTest(base64Encode(bytes2)), isNull);
    }
  });

  test('非本程序的文件返回 null（不做误判）', () async {
    expect(await storage.decodeForTest(base64Encode(utf8.encode('hello'))),
        isNull);
    expect(await storage.decodeForTest('not-base64!!!'), isNull);
  });

  test('原子写：临时文件被替换成主文件，内容可读', () async {
    final dir = Directory.systemTemp.createTempSync('cms_storage_test');
    final target = File('${dir.path}/data.enc');
    final text = await storage.encodeForTest(AppData.empty());

    await target.writeAsString('旧内容');
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(text, flush: true);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);

    expect(await target.exists(), isTrue);
    expect(await temp.exists(), isFalse);
    expect(await storage.decodeForTest(await target.readAsString()), isNotNull);
  });
}
