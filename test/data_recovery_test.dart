// 数据兼容与损坏恢复专项回归。
//
// 背景（V2.28.1 测试深化）：程序的命根是"数据不出本机"——主文件
// class_management_data.enc 一旦损坏，唯一救星是每次保存前自动保留的 .bak。
// 此前 storage_service_test 只测了编解码层（6 项），**loadData 的三态恢复链、
// .bak 的"坏主文件不顶掉好备份"保护、
// 恢复失败时的数据保全**全部没有测试。本文件补齐，全部走 mock 的临时文档目录，
// 绝不触碰真实数据文件。
//
// 模式沿用 backup_rotation_test：test()（非 testWidgets）+ mock path_provider。
// test() 里没有 fake zone，真实 IO 正常推进，不存在 testWidgets 的收尾死锁问题。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/providers/app_data_provider.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_data_recovery');
    storage = StorageService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
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
  File bakFile() => File('${tempDir.path}/class_management_data.enc.bak');

  // ---------- 组 A：loadData 三态恢复链 ----------

  test('主文件完好：正常加载，不走恢复也不重置', () async {
    final data = AppData.fromJson(const {
      'students': ['张三'],
    });
    await mainFile().writeAsString(await storage.encodeForTest(data));

    final result = await storage.loadData();

    expect(result.restoredFromBackup, isFalse);
    expect(result.resetToEmpty, isFalse);
    expect(result.data.students, contains('张三'));
  });

  test('主文件不存在：首次启动，返回空数据而非"重置"', () async {
    final result = await storage.loadData();
    expect(result.resetToEmpty, isFalse,
        reason: '文件都没有，谈不上"损坏重置"，不该吓用户');
  });

  test('主文件损坏 + .bak 完好：自动从备份恢复，主文件被回写为备份内容', () async {
    final backupData = AppData.fromJson(const {
      'students': ['备份里的张三'],
    });
    final backupText = await storage.encodeForTest(backupData);
    await bakFile().writeAsString(backupText);
    await mainFile().writeAsString('这段是损坏的乱码内容!!!');

    final result = await storage.loadData();

    expect(result.restoredFromBackup, isTrue);
    expect(result.data.students, contains('备份里的张三'));
    // 关键：主文件已被备份内容覆盖，下次启动直接正常加载，不会反复触发恢复。
    expect(await mainFile().readAsString(), backupText);
  });

  test('主文件损坏 + 无 .bak：判为"数据重置"（提示用户，而不是静默装没事）', () async {
    await mainFile().writeAsString('损坏内容!!!');
    final result = await storage.loadData();
    expect(result.resetToEmpty, isTrue);
  });

  test('主文件与 .bak 都损坏：仍判为"数据重置"，程序以空数据启动', () async {
    await mainFile().writeAsString('损坏!!!');
    await bakFile().writeAsString('备份也损坏!!!');
    final result = await storage.loadData();
    expect(result.resetToEmpty, isTrue);
  });

  // ---------- 组 B：.bak 保护（坏主文件不顶掉最后一份好备份） ----------

  test('主文件正常时保存：旧主文件先被保留为 .bak', () async {
    final old = AppData.fromJson(const {'students': ['旧数据张三']});
    final fresh = AppData.fromJson(const {'students': ['新数据李四']});
    await mainFile().writeAsString(await storage.encodeForTest(old));

    final ok = await storage.saveData(fresh);
    expect(ok, isTrue);
    expect(await bakFile().exists(), isTrue);
    expect(await storage.decodeForTest(await bakFile().readAsString()),
        isNotNull, reason: '.bak 里应是可解析的旧数据');
    expect((await storage.decodeForTest(await bakFile().readAsString()))!
        .students, contains('旧数据张三'));
  });

  test('主文件损坏后保存：.bak 保持最后的好备份，不被坏内容顶掉', () async {
    final lastGood = AppData.fromJson(const {'students': ['好备份王五']});
    await mainFile().writeAsString(await storage.encodeForTest(lastGood));
    // 先正常保存一次：此刻 .bak 里被保留的正是"王五"那份数据。
    await storage.saveData(
        AppData.fromJson(const {'students': ['中间数据孙七']}));
    expect((await storage.decodeForTest(await bakFile().readAsString()))!
        .students, contains('好备份王五'));

    // 用户用别的方式把主文件弄坏了（比如拷贝中断）。
    await mainFile().writeAsString('中途损坏的内容!!!');

    // 再保存：主文件当前解析不了 → 绝不能把坏内容顶掉 .bak。
    final ok = await storage.saveData(
        AppData.fromJson(const {'students': ['新数据赵六']}));

    expect(ok, isTrue);
    // .bak 必须还是那份好的旧数据——它现在是唯一救星。
    final bak = await storage.decodeForTest(await bakFile().readAsString());
    expect(bak, isNotNull);
    expect(bak!.students, contains('好备份王五'),
        reason: '坏主文件不得覆盖 .bak 里的最后好备份');
    // 新数据正常写入主文件。
    expect(await mainFile().readAsString(), isNot('中途损坏的内容!!!'));
  });

  // ---------- 组 D：恢复失败路径（失败时绝不破坏现有数据） ----------

  test('恢复到不存在的文件路径：返回错误文案，内存数据保持原样', () async {
    final provider = AppDataProvider();
    await provider.flushPendingSaves();
    final before = provider.appData.students.toList();

    final error = await provider
        .restoreBackupFrom('${tempDir.path}/根本不存在的备份.enc');

    expect(error, isNotNull, reason: '必须给用户明确提示而不是静默');
    expect(provider.appData.students, before,
        reason: '失败的恢复不能动现有数据');
  });

  test('恢复一个乱码文件：返回错误文案，主文件与内存数据都不被破坏', () async {
    final provider = AppDataProvider();
    await provider.flushPendingSaves();
    final before = provider.appData.students.toList();
    final junk = File('${tempDir.path}/坏备份.enc');
    await junk.writeAsString('not a backup at all!!!');

    final error = await provider.restoreBackupFrom(junk.path);

    expect(error, isNotNull);
    expect(provider.appData.students, before);
    if (await mainFile().exists()) {
      expect(await storage.decodeForTest(await mainFile().readAsString()),
          isNotNull, reason: '校验失败的主文件覆盖绝不能发生');
    }
  });

  test('目标位置被目录占用时保存：返回 false 而不是抛异常炸掉调用方', () async {
    // 造"写不进去"：主文件路径被一个同名目录占着，rename 覆盖必然失败。
    Directory('${tempDir.path}/class_management_data.enc').createSync();

    final ok = await storage.saveData(AppData.fromJson(const {'students': ['甲']}));
    expect(ok, isFalse, reason: '失败必须以返回值告知调用方（由界面提示用户）');
  });
}
