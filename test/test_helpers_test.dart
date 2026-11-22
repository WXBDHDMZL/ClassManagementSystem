// 测试公用工具的回归用例（复核报告 V2.27.2 的 N-1）。
//
// 这条用例存在的意义：证明"带重试的删除"真的能解决"文件句柄被占用导致
// tearDown 偶发失败"的问题，而不是"看起来加了重试但其实没生效"。
// 做法：**人为制造锁**——在临时目录里开一个文件流（持有句柄），
// 然后启动一个"稍后释放锁"的动作，断言 deleteDirectoryWithRetry 最终能删掉目录。
// 对照组：不加重试的 deleteSync 在同一时机**必然抛出**（这也是原缺陷的机制）。
//
// ⚠️ 时序前提（V2.27.5 修正，务必保留）：**两条用例都必须用
// `await file.open(mode: FileMode.append)` 确定性持有句柄**，绝不要改回
// `openWrite()`。`openWrite()` 是**异步**打开句柄的，紧随其后的删除常会抢在
// 句柄建立之前成功执行，于是"句柄被占用"这个前提根本不成立：
//   - 对照组会因"没抛"而失败；
//   - 第一个用例更糟 —— 首次删除成功后，写流上的写入会抛
//     `PathNotFoundException`（路径已不存在），异常未被捕获 → 用例卡死 30 秒超时。
// 这条坑 V2.27.3 与 V2.27.4 各踩过一次（两次都只修了对照组、漏了另一条）。
// 另外：第一个用例还要求句柄**真的在中途释放**（用 Timer 在 300ms 后关闭），
// 否则重试耗尽后目录仍在，断言同样失败。
//
// ⚠️ 平台前提：本对照组依赖 Windows 的"文件被占用即拒绝删除"语义
// （Linux/macOS 上删除被占用文件会成功）→ 已用 `Platform.isWindows` 守卫，
// 非 Windows 平台自动跳过。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  test('deleteDirectoryWithRetry 能等到文件句柄释放后再删除', () async {
    // ⚠️ 时序前提（V2.27.5 修正，务必保留）：
    // 本用例要验证的是"重试**等到句柄释放**后把目录删掉"。因此有两条硬要求：
    //  1. 句柄必须**确定性**持有 —— 用 `await file.open(mode: FileMode.append)`，
    //     它返回时句柄一定已建立。**不要改回 `openWrite()`**：那是异步打开，
    //     重试的第一次删除常抢在句柄建立前就成功，于是"释放后才能删"这个前提
    //     根本不成立，用例会变成偶发失败（V2.27.3/V2.27.4 两次踩过，且
    //     首次删除成功后继续 write 会抛 PathNotFoundException → 直接卡死 30 秒）。
    //  2. 句柄必须**真的在中途释放** —— 用 `Timer` 在 300ms 后关闭它，
    //     重试（40×50ms=2s）期间它会释放，删除才可能成功。
    //     若句柄全程不释放，重试耗尽后目录仍在，断言同样失败。
    final dir = Directory.systemTemp.createTempSync('cms_retry_delete');
    final file = File('${dir.path}${Platform.pathSeparator}locked.tmp')
      ..writeAsStringSync('x');

    final handle = await file.open(mode: FileMode.append); // 确定性持句柄

    // 300ms 后释放（模拟"写盘链稍后才结束"）。
    final release = Future<void>.delayed(
      const Duration(milliseconds: 300),
      () => handle.close(),
    );

    // 带重试：应当等到句柄释放后把目录删掉。
    await deleteDirectoryWithRetry(dir, attempts: 40);
    await release;

    // 兜底清理（句柄已关，此时删除必然成功）。
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}

    expect(dir.existsSync(), isFalse,
        reason: '重试删除应当等到句柄释放后成功，而不是把偶发失败甩给 tearDown');
  });

  test('对照：不重试的 deleteSync 在句柄被占用时会抛出（原缺陷机制）', () async {
    // 该对照依赖 Windows 的文件占用语义，其它平台跳过（见文件头说明）。
    if (!Platform.isWindows) {
      return;
    }

    final dir = Directory.systemTemp.createTempSync('cms_retry_control');
    final file = File('${dir.path}${Platform.pathSeparator}locked.tmp')
      ..writeAsStringSync('x');

    // **确定性**持有句柄：await open(FileMode.append) 返回时句柄一定已建立，
    // 不依赖 openWrite 那种"写和删赛跑"的时序（那正是 V2.27.3 这条用例 flaky 的原因）。
    final handle = await file.open(mode: FileMode.append);
    expect(dir.existsSync(), isTrue);

    var threw = false;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      threw = true;
    }

    await handle.close();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}

    // Windows 上句柄被占用时必定抛 PathAccessException；这是 N-1 偶发的根因。
    expect(threw, isTrue,
        reason: '本用例用来证明"不加重试就会偶发失败"，是 N-1 的机制复现');
  });
}
