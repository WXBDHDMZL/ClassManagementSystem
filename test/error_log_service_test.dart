// 错误日志服务回归测试（审查 L10 补缺；命名遵循"被测模块名"约定 L11）。
//
// error_log_service 是全应用错误处理的唯一落盘通道，此前仅通过 error_sink
// 间接覆盖。这里通过 debugLogDirectoryOverride 注入临时目录，覆盖四组契约：
//   1. 条目格式（时间/环境/模块/场景/错误/堆栈）与串行队列保序；
//   2. 限流窗口（5 秒内完全相同的条目只记一次，不同条目照常写入）；
//   3. 写盘失败静默降级（绝不波及主流程），恢复后继续写入；
//   4. 按月文件名与文件枚举（供"导出错误日志"读取）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/services/encrypted_text_file.dart';
import 'package:class_management_system/services/error_log_service.dart';

import 'test_helpers.dart';

String _logPath(Directory dir) =>
    '${dir.path}${Platform.pathSeparator}班级管理系统_日志.txt';

/// 日志落盘已加密，断言/读取要用解密后的文本。
Future<String> _readLog(Directory dir) =>
    EncryptedTextFile.readAllText(File(_logPath(dir)));

int _countOccurrences(String content, String needle) {
  var count = 0;
  var index = content.indexOf(needle);
  while (index >= 0) {
    count++;
    index = content.indexOf(needle, index + needle.length);
  }
  return count;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cms_error_log_test');
    debugLogDirectoryOverride = tempDir;
  });

  tearDown(() async {
    // 先把队列写完再摘目录，避免写盘句柄与删除竞态。
    await flushErrorLogWrites();
    debugLogDirectoryOverride = null;
    await deleteDirectoryWithRetry(tempDir);
  });

  test('条目格式：时间/环境/模块/场景/错误/堆栈齐全，且按调用顺序追加', () async {
    appendErrorLog(
      'test_a',
      StateError('第一条-格式用例'),
      StackTrace.current,
      context: '场景甲',
    );
    appendErrorLog('test_b', '第二条文本错误-格式用例', null);
    await flushErrorLogWrites();

    final content = await _readLog(tempDir);
    expect(content, contains('模块  test_a'));
    expect(content, contains('场景  场景甲'));
    expect(content, contains('错误  Bad state: 第一条-格式用例'));
    expect(content, contains('模块  test_b'));
    expect(content, contains('（无堆栈）'), reason: '未提供堆栈时应如实标注');
    expect(content, contains('环境  '), reason: '每条都应带运行环境摘要');
    expect(
      content.indexOf('模块  test_a'),
      lessThan(content.indexOf('模块  test_b')),
      reason: '串行队列必须保序（先调用的先写入）',
    );
  });

  test('并发追加多条：全部写入且顺序与调用一致', () async {
    for (var i = 1; i <= 15; i++) {
      appendErrorLog('order_tag', '并发序-$i-唯一串', null);
    }
    await flushErrorLogWrites();

    final content = await _readLog(tempDir);
    var lastIndex = -1;
    for (var i = 1; i <= 15; i++) {
      final index = content.indexOf('并发序-$i-唯一串');
      expect(index, greaterThan(lastIndex), reason: '第 $i 条应出现在第 ${i - 1} 条之后');
      lastIndex = index;
    }
  });

  test('限流：5 秒内完全相同的条目只记一次，不同条目照常写入', () async {
    const unique = '限流-9f1c-完全相同的错误';
    appendErrorLog('throttle_tag', unique, null);
    appendErrorLog('throttle_tag', unique, null);
    appendErrorLog('throttle_tag', '限流-9f1c-另一条不同错误', null);
    await flushErrorLogWrites();

    final content = await _readLog(tempDir);
    expect(
      _countOccurrences(content, '错误  $unique'),
      1,
      reason: '同一 tag + 同一错误在窗口内只允许一条',
    );
    expect(_countOccurrences(content, '限流-9f1c-另一条不同错误'), 1);
  });

  test('写盘失败（目录路径被文件占位）：静默降级不抛出，恢复后继续写入', () async {
    // 故障注入：把日志目录指向一个"文件"路径 —— 在其中建文件必然失败。
    final blocker = File('${tempDir.path}/被占作文件的路径')
      ..writeAsStringSync('x');
    debugLogDirectoryOverride = Directory(blocker.path);

    appendErrorLog('fail_tag', '写不进去的错误-降级用例', null);
    // 不抛即通过：整个调用链对写盘失败必须完全静默。
    await flushErrorLogWrites();

    // 恢复正确目录后，新条目照常写入（队列未被故障卡死）。
    debugLogDirectoryOverride = tempDir;
    appendErrorLog('recover_tag', '恢复后的错误-降级用例', null);
    await flushErrorLogWrites();

    final content = await _readLog(tempDir);
    expect(content, contains('恢复后的错误-降级用例'));
    expect(content, isNot(contains('写不进去的错误-降级用例')));
  });

  test('单文件：路径固定为合并日志，旧分类文件不再单独枚举', () async {
    appendErrorLog('file_tag', '枚举-单文件-唯一串', null);
    await flushErrorLogWrites();

    // 旧版分类文件与无关 txt 均不应被当作当前日志。
    File('${tempDir.path}/班级管理系统_错误日志_2021-01.txt')
        .writeAsStringSync('旧月份');
    File('${tempDir.path}/无关文件.txt').writeAsStringSync('不应被枚举');

    final files = await allErrorLogFiles();
    expect(files.length, 1, reason: '只返回合并日志文件');
    expect(files.single.path, _logPath(tempDir));
    expect(await errorLogFilePath(), _logPath(tempDir));
  });
}
