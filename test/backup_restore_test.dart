// 备份 / 恢复测试（补交接说明 §10 的测试缺口）：
// 覆盖"失败场景"——备份不存在、格式不对、内容被篡改、主文件损坏走 .bak 恢复等，
// 并保证任何校验失败都不会改动用户现有数据。
// 用临时目录 + mock 的文档目录，绝不触碰真实数据文件。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/models/app_settings.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  final storage = StorageService();
  late Directory tempDir;
  late String mainPath;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_backup_test');
    mainPath = '${tempDir.path}/class_management_data.enc';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? tempDir.parent.path : null,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    // N-1：等写盘链清空再删目录，避免 Windows 上文件句柄占用导致偶发失败。
    await deleteStorageTestRoot(tempDir);
  });

  // ---------------- 恢复失败场景 ----------------

  test('恢复：备份文件不存在', () async {
    final error = await storage.restoreFrom('${tempDir.path}/缺失.enc');
    expect(error, '备份文件不存在');
  });

  test('恢复：不是本程序的文件被拒绝', () async {
    final file = File('${tempDir.path}/other.enc');
    await file.writeAsString('hello world');
    expect(await storage.restoreFrom(file.path), '文件格式不正确');
  });

  test('恢复：空文件被拒绝', () async {
    final file = File('${tempDir.path}/empty.enc');
    await file.writeAsString('');
    expect(await storage.restoreFrom(file.path), '文件格式不正确');
  });

  test('恢复：本版本（LRX3）导出的备份可以恢复（回归保护）', () async {
    // 用当前版本的编码链路生成备份内容，写入"备份文件"。
    final backupText = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.dark),
        students: const ['张三', '李四'],
      ),
    );
    final backup = File('${tempDir.path}/当前版本备份.enc');
    await backup.writeAsString(backupText);

    final error = await storage.restoreFrom(backup.path);
    expect(error, isNull, reason: 'LRX3 备份必须能被恢复，否则用户的备份形同虚设');

    // 主文件已写入，且能被正常读回。
    final result = await storage.loadData();
    expect(result.restoredFromBackup, isFalse);
    expect(result.resetToEmpty, isFalse);
    expect(result.data.students, ['张三', '李四']);
    expect(result.data.settings.themeMode, ThemeModeType.dark);
  });

  test('恢复：备份内容带首尾空白也能恢复（读取时先 trim）', () async {
    final backupText = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.light),
        students: const ['张三'],
      ),
    );
    final backup = File('${tempDir.path}/带空白.enc');
    await backup.writeAsString('\n$backupText\n');

    expect(await storage.restoreFrom(backup.path), isNull);
    final result = await storage.loadData();
    expect(result.data.students, ['张三']);
  });

  test('恢复：被篡改的备份被拒绝，且不改动现有数据', () async {
    // 先放一份"现有数据"在主文件里。
    final current = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        students: const ['现有同学'],
      ),
    );
    await File(mainPath).writeAsString(current);

    // 备份内容合法但被改动一个字节 → HMAC 校验必须拦下。
    final backupText = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        students: const ['恶意内容'],
      ),
    );
    final bytes = base64Decode(backupText);
    bytes[bytes.length - 1] ^= 0xFF;
    final backup = File('${tempDir.path}/被篡改.enc');
    await backup.writeAsString(base64Encode(bytes));

    expect(await storage.restoreFrom(backup.path), '数据文件已损坏');
    // 主文件必须原封不动。
    expect(await File(mainPath).readAsString(), current);
    final result = await storage.loadData();
    expect(result.data.students, ['现有同学']);
  });

  test('恢复：成功时把原主文件留为 .bak', () async {
    final old = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        students: const ['旧主文件'],
      ),
    );
    await File(mainPath).writeAsString(old);

    final backup = File('${tempDir.path}/新备份.enc');
    await backup.writeAsString(
      await storage.encodeForTest(
        AppData(
          recordsByDate: const {},
          settings: AppSettings(themeMode: ThemeModeType.system),
          students: const ['新备份'],
        ),
      ),
    );

    expect(await storage.restoreFrom(backup.path), isNull);
    expect(await File('$mainPath.bak').readAsString(), old);
    expect((await storage.loadData()).data.students, ['新备份']);
  });

  // ---------------- 加载（启动）失败场景 ----------------

  test('加载：主文件损坏时自动从 .bak 恢复', () async {
    await File(mainPath).writeAsString('这不是合法数据');
    final good = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        students: const ['备份里的同学'],
      ),
    );
    await File('$mainPath.bak').writeAsString(good);

    final result = await storage.loadData();
    expect(result.restoredFromBackup, isTrue);
    expect(result.resetToEmpty, isFalse);
    expect(result.data.students, ['备份里的同学']);
    // 恢复后主文件应被备份内容覆盖，下次启动不再依赖 .bak。
    expect(await File(mainPath).readAsString(), good);
  });

  test('加载：主文件损坏且无可用备份 → 重置为空并标记 resetToEmpty', () async {
    await File(mainPath).writeAsString('损坏内容');

    final result = await storage.loadData();
    expect(result.resetToEmpty, isTrue);
    expect(result.restoredFromBackup, isFalse);
    expect(result.data.students, isEmpty); // 新版出厂名单为空
  });

  test('加载：文件不存在（首次启动）不标记为重置', () async {
    final result = await storage.loadData();
    expect(result.resetToEmpty, isFalse);
    expect(result.restoredFromBackup, isFalse);
  });

  test('保存：主文件已损坏时不覆盖 .bak（保住最后一份可用备份）', () async {
    final good = await storage.encodeForTest(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        students: const ['好备份'],
      ),
    );
    await File('$mainPath.bak').writeAsString(good);
    await File(mainPath).writeAsString('主文件坏了');

    final ok = await storage.saveData(
      AppData(
        recordsByDate: const {},
        settings: AppSettings(themeMode: ThemeModeType.system),
        students: const ['新写入'],
      ),
    );

    expect(ok, isTrue);
    // 坏主文件不能把好备份顶掉。
    expect(await File('$mainPath.bak').readAsString(), good);
    expect((await storage.loadData()).data.students, ['新写入']);
  });

  test('保存：磁盘不可写时返回 false 且不抛异常', () async {
    // 用一个"父路径是文件"的非法目标，制造写入失败。
    final blocker = File('${tempDir.path}/blocker');
    await blocker.writeAsString('x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? '${blocker.path}/sub'
          : null,
    );

    final ok = await storage.saveData(AppData.empty());
    expect(ok, isFalse);
  });

  test('备份：目标目录不存在时会自动创建', () async {
    await File(mainPath).writeAsString(
      await storage.encodeForTest(AppData.empty()),
    );
    final target = '${tempDir.path}/新建目录/备份.enc';

    expect(await storage.backupTo(target), isTrue);
    expect(await File(target).exists(), isTrue);
  });

  test('备份：主数据文件不存在时返回 false', () async {
    expect(await storage.backupTo('${tempDir.path}/随便.enc'), isFalse);
  });
}
