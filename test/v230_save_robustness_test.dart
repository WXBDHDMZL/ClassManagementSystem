// 第 1 轮回归：保存路径健壮性（X-1 / G-1）。
//
// X-1：`_saveDataNow` 里"覆盖 .bak"与"写主文件"原先共用同一个 try —— 磁盘满
//      或 .bak 被杀软/他进程占用时 copy 抛错会让**整次保存失败、主文件根本不写**，
//      明明可写的数据反而丢失。这里用"把 .bak 路径占成目录"稳定复现该场景
//      （文件 copy 到已存在的目录必然失败）。
//
// G-1：`_save()` 落盘后**无条件**再通知一次，叠加首次通知形成"每操作两轮全量
//      rebuild"。修复后仅当失败态翻转才通知 —— 第三条用例专门守住"失败提示不能
//      被一起优化掉"，否则等于用一个静默 bug 换一个性能收益。
//
// 模式沿用 data_recovery_test：test()（非 testWidgets）+ mock path_provider，
// 全部走临时目录，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;

  /// 把 path_provider 的"文档目录"指向 [path]。
  void mockDocuments(String path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? path
          : null,
    );
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_save_robust');
    mockDocuments(tempDir.parent.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteStorageTestRoot(tempDir);
  });

  File mainFile() => File('${tempDir.path}/class_management_data.enc');

  test('X-1：.bak 覆盖失败时，主文件仍必须保存成功', () async {
    final provider = AppDataProvider();
    await provider.flushPendingSaves();
    expect(provider.addStudent('先建主文件同学'), isTrue);
    await provider.flushPendingSaves();
    expect(await mainFile().exists(), isTrue);

    // 把 .bak 路径占成一个目录 → 覆盖备份必然失败。
    Directory('${mainFile().path}.bak').createSync(recursive: true);

    expect(provider.addStudent('主文件仍要写入同学'), isTrue);
    await provider.flushPendingSaves();

    expect(provider.saveFailed, isFalse,
        reason: '.bak 写不了不该让整次保存失败（原实现会连带丢弃主文件写入）');
    final reloaded = await StorageService().loadData();
    expect(reloaded.data.students, contains('主文件仍要写入同学'),
        reason: '主文件必须真的写进去了，不能只是内存里改了');
  });

  test('G-1：一次成功保存只通知一次', () async {
    final provider = AppDataProvider();
    await provider.flushPendingSaves();

    var notifies = 0;
    provider.addListener(() => notifies++);

    provider.addStudent('只通知一次同学');
    await provider.flushPendingSaves();

    expect(provider.saveFailed, isFalse);
    expect(notifies, 1,
        reason: '成功且此前也成功 → 第二次通知只会引发多余的全量 rebuild');
  });

  test('G-1 防回归：保存失败时仍要通知，且 saveFailed 置位', () async {
    // 文档目录指向"父路径是文件"的位置 → 建目录与写盘必然失败（且失败得很快）。
    final blocker = File('${tempDir.path}/blocker')..writeAsStringSync('x');
    mockDocuments('${blocker.path}/sub');
    addTearDown(() => mockDocuments(tempDir.path));

    final provider = AppDataProvider();
    await provider.flushPendingSaves();

    var notifies = 0;
    provider.addListener(() => notifies++);

    provider.addStudent('写盘失败同学');
    await provider.flushPendingSaves();

    expect(provider.saveFailed, isTrue, reason: '失败必须置位，主界面横幅靠它');
    expect(notifies, greaterThanOrEqualTo(2),
        reason: '首次通知 + 失败态翻转通知，少一个用户就看不到失败提示');
  });
}
