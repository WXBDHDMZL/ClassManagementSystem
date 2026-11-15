// atomic_file 回归测试（审查 L10 补缺；命名遵循"被测模块名"约定 L11）。
//
// 这是数据安全的核心不变量，此前无任何守护：
//   1. 原子写入成功后临时文件不残留；
//   2. 同一路径的并发写入严格串行（最终为最后一次内容）；
//   3. **rename 失败（杀软/索引器占用）时原文件内容绝不被截断**、
//      临时文件被清理、异常如实上抛；
//   4. rename 短暂失败后重试可成功（占用解除场景）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/atomic_file.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cms_atomic_test');
    AtomicFile.debugRenameOverride = null;
  });

  tearDown(() async {
    AtomicFile.debugRenameOverride = null;
    await deleteDirectoryWithRetry(tempDir);
  });

  List<FileSystemEntity> tmpFiles() => tempDir
      .listSync()
      .where((e) => e.path.endsWith('.tmp'))
      .toList();

  test('写入 bytes：内容落盘，且临时文件不残留', () async {
    final path = '${tempDir.path}/a.bin';
    await AtomicFile.writeBytes(path, [1, 2, 3]);

    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    expect(tmpFiles(), isEmpty);
  });

  test('同一路径并发写入：按调用顺序串行，最终为最后一次的内容', () async {
    final path = '${tempDir.path}/b.txt';
    final futures = [
      for (var i = 1; i <= 20; i++) AtomicFile.writeString(path, '第 $i 次'),
    ];
    await Future.wait(futures);

    expect(File(path).readAsStringSync(), '第 20 次', reason: '最后一次写入应胜出');
    expect(tmpFiles(), isEmpty);
  });

  test('rename 始终失败：原文件不被截断、临时文件被清理、异常上抛', () async {
    final path = '${tempDir.path}/c.txt';
    File(path).writeAsStringSync('旧内容');
    AtomicFile.debugRenameOverride = (temp, target) async {
      throw const FileSystemException('注入故障：目标被短暂占用');
    };

    await expectLater(
      AtomicFile.writeString(path, '新内容'),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      File(path).readAsStringSync(),
      '旧内容',
      reason: 'rename 失败绝不能触碰原文件（原子写的存在意义）',
    );
    expect(tmpFiles(), isEmpty, reason: '重试耗尽后必须清理临时文件，防止 .tmp 堆积');
  });

  test('rename 前两次失败、第三次成功：写入最终完成（占用解除场景）', () async {
    final path = '${tempDir.path}/d.txt';
    var attempts = 0;
    AtomicFile.debugRenameOverride = (temp, target) async {
      attempts++;
      if (attempts < 3) {
        throw const FileSystemException('注入故障：暂时占用');
      }
      await temp.rename(target);
    };

    await AtomicFile.writeString(path, '重试后成功');

    expect(attempts, 3, reason: '两次失败后第三次应放行');
    expect(File(path).readAsStringSync(), '重试后成功');
    expect(tmpFiles(), isEmpty);
  });

  test('copyAtomic：把源文件原子复制到目标（原内容完整）', () async {
    final source = File('${tempDir.path}/src.txt')..writeAsStringSync('来源内容');
    final dest = '${tempDir.path}/dst.txt';
    File(dest).writeAsStringSync('旧目标');

    await AtomicFile.copyAtomic(source.path, dest);

    expect(File(dest).readAsStringSync(), '来源内容');
    expect(tmpFiles(), isEmpty);
  });
}
