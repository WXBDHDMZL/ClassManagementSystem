// 错钥识别（审计 A-02）与"空库不得覆盖唯一备份"（审计 A-01）的行为测试。
//
// 背景：LRX3 的 HMAC 校验失败无法区分"密钥不对"与"文件损坏"。5.0.1 及以前
// 一律按损坏处理 —— 隔离主文件、起空库、继续允许写入，最终把可抢救数据
// 逼进没有入口的 `.corrupt_*`。这里验证修复后的行为：
//   · 有指纹且不匹配 → 判定"密钥不对"，主文件原地不动、拒绝写入；
//   · 没有指纹（旧数据/指纹被删）→ 保持旧判定（损坏隔离），不会突然变成打不开；
//   · 隔离 + 空库期间，`.bak` 不被空库顶掉，录入数据后恢复轮转。
//
// 全部在 mock 的临时文档目录里跑，绝不触碰真实数据文件。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:class_management_system/models/app_data.dart';
import 'package:class_management_system/services/storage_crypto.dart';
import 'package:class_management_system/services/storage_key_id.dart';
import 'package:class_management_system/services/storage_service.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;
  late Uint8List keyA;
  late Uint8List keyB;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = createStorageTestRoot('cms_key_mismatch');
    storage = StorageService();
    keyA = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    keyB = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));
    StorageService.debugDataKeyOverride = keyA;
    StorageService.debugResetKey();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? tempDir.parent.path
          : null,
    );
  });

  tearDown(() async {
    StorageService.debugDataKeyOverride =
        Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    StorageService.debugResetKey();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await deleteStorageTestRoot(tempDir);
  });

  File mainFile() => File('${tempDir.path}/class_management_data.enc');
  File backupFile() => File('${mainFile().path}.bak');
  File keyIdFile() => File('${mainFile().path}${StorageKeyId.fileSuffix}');

  List<File> corruptFiles() => tempDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('.enc.corrupt_'))
      .toList();

  /// 用 [key] 造一份合法 LRX3 密文（明文为 [json]）。
  String encodeWith(Uint8List key, String json) =>
      StorageCrypto.encodeV3(json, key);

  group('A-02 错钥识别', () {
    test('密钥不匹配：判定 keyMismatch，主文件不隔离、不重置、拒绝写入', () async {
      // 先用 keyA 正常存一份数据（保存过程会写下 `.keyid` 指纹）。
      await storage.loadData();
      final ok = await storage.saveData(
        AppData.fromJson(const {'students': ['张三', '李四']}),
      );
      expect(ok, isTrue);
      expect(await keyIdFile().exists(), isTrue, reason: '保存成功应写下密钥指纹');
      final mainBefore = await mainFile().readAsBytes();

      // 模拟"换机/换用户后换回旧 .keyid，但 .enc 是新密钥写的"这类错配。
      StorageService.debugDataKeyOverride = keyB;
      StorageService.debugResetKey();

      // 必须用"加载时用的那个实例"验收写入行为：阻断状态是实例内的。
      final mismatched = StorageService();
      final result = await mismatched.loadData();

      expect(result.keyMismatch, isTrue, reason: '指纹不匹配必须判定为错钥');
      expect(result.resetToEmpty, isFalse, reason: '错钥不是损坏，不得重置');
      expect(result.restoredFromBackup, isFalse);
      expect(await mainFile().exists(), isTrue, reason: '错钥时主文件必须原地保留');
      expect(corruptFiles(), isEmpty, reason: '错钥时不得隔离主文件');
      expect(await mainFile().readAsBytes(), mainBefore,
          reason: '错钥时主文件内容不得被任何操作改动');

      final blocked = await mismatched.saveData(
        AppData.fromJson(const {'students': ['覆盖尝试']}),
      );
      expect(blocked, isFalse, reason: '错钥状态下必须拒绝写入');
      expect(await mainFile().readAsBytes(), mainBefore,
          reason: '拒绝写入时主文件保持原样');
    });

    test('错钥后用户选择以空库继续：原文件被隔离保留，之后可正常写入', () async {
      await storage.loadData();
      await storage.saveData(AppData.fromJson(const {'students': ['张三']}));
      StorageService.debugDataKeyOverride = keyB;
      StorageService.debugResetKey();

      final mismatched = StorageService();
      final loaded = await mismatched.loadData();
      expect(loaded.keyMismatch, isTrue);

      expect(await mismatched.discardKeyMismatchAndStartEmpty(), isTrue);
      expect(await mainFile().exists(), isFalse, reason: '确认后原文件移走，给新库让路');
      expect(corruptFiles(), hasLength(1), reason: '原文件必须作为隔离副本保留');

      expect(
        await mismatched.saveData(
          AppData.fromJson(const {'students': ['新库学生']}),
        ),
        isTrue,
      );
      final reloaded = await StorageService().loadData();
      expect(reloaded.data.students, contains('新库学生'));
    });

    test('没有指纹（旧数据）时保持旧判定：损坏隔离而非错钥', () async {
      await mainFile().writeAsString('明显不是 LRX3 的内容');
      expect(await keyIdFile().exists(), isFalse);

      final result = await StorageService().loadData();

      expect(result.keyMismatch, isFalse, reason: '没有指纹时不能凭空判定错钥');
      expect(result.resetToEmpty, isTrue);
      expect(corruptFiles(), hasLength(1));
    });

    test('指纹内容非法时按缺失处理，不阻断启动', () async {
      await mainFile().writeAsString('损坏内容');
      await keyIdFile().writeAsString('这不是合法指纹');

      final result = await StorageService().loadData();

      expect(result.keyMismatch, isFalse);
      expect(result.resetToEmpty, isTrue);
    });

    test('指纹文件缺失但密钥匹配：正常加载不受影响', () async {
      await mainFile().writeAsString(
        encodeWith(keyA, '{"students":["王五"]}'),
      );

      final result = await StorageService().loadData();

      expect(result.keyMismatch, isFalse);
      expect(result.resetToEmpty, isFalse);
      expect(result.data.students, contains('王五'));
    });
  });

  group('A-01 隔离期空库不得覆盖唯一备份', () {
    /// 造出"主文件损坏 + `.bak` 存在但内容不可用"的场景。
    Future<void> prepareQuarantine() async {
      await mainFile().writeAsString('损坏内容!!!');
      // `.bak` 是合法 LRX3 但明文不是合法 JSON：`_tryLoadFile` 返回 null，
      // 于是走"主文件与备份都解不开"的隔离分支。
      await backupFile().writeAsString(
        encodeWith(keyA, '这不是 JSON 内容'),
      );
      final loaded = await storage.loadData();
      expect(loaded.resetToEmpty, isTrue);
      expect(corruptFiles(), hasLength(1));
    }

    test('空库连续保存两次，`.bak` 保持不变（旧版第二次就被空库顶掉）', () async {
      await prepareQuarantine();
      final backupBefore = await backupFile().readAsBytes();

      expect(await storage.releaseQuarantineForEmptyLibrary(), isTrue);

      // 第一次保存：主文件不存在 → 不参与 .bak 轮转。
      expect(await storage.saveData(AppData.empty()), isTrue);
      // 第二次保存：旧版此时会 copyAtomic 把空库覆盖到 .bak。
      expect(await storage.saveData(AppData.empty()), isTrue);

      expect(await backupFile().readAsBytes(), backupBefore,
          reason: '库为空且存在隔离文件时，`.bak` 必须原样保留');
    });

    test('录入新数据后恢复 `.bak` 轮转', () async {
      await prepareQuarantine();
      final backupBefore = await backupFile().readAsBytes();
      expect(await storage.releaseQuarantineForEmptyLibrary(), isTrue);

      expect(await storage.saveData(AppData.empty()), isTrue);
      expect(await storage.saveData(AppData.empty()), isTrue);
      expect(await backupFile().readAsBytes(), backupBefore);

      // 有了真实数据就不再是"空库"，轮转必须恢复。
      expect(
        await storage.saveData(AppData.fromJson(const {'students': ['新录入']})),
        isTrue,
      );
      expect(await backupFile().readAsBytes(), isNot(backupBefore),
          reason: '录入数据后 .bak 应恢复轮转');
      expect(corruptFiles(), hasLength(1), reason: '隔离副本始终不被自动删除');
    });

    test('没有隔离文件时 `.bak` 照常轮转（保护不误伤）', () async {
      await storage.loadData();
      expect(await storage.saveData(AppData.empty()), isTrue);
      final firstBackupExists = await backupFile().exists();
      expect(await storage.saveData(AppData.empty()), isTrue);
      expect(await backupFile().exists(), isTrue);
      // 第一次写入时主文件还不存在，所以第一次保存后 .bak 是否出现取决于
      // 之前状态；这里只要求"第二次保存后一定有一份 .bak"且内容非空。
      expect(await backupFile().length(), greaterThan(0));
      expect(firstBackupExists || await backupFile().exists(), isTrue);
    });
  });
}
