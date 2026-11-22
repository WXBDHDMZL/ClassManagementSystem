/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'backup_crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/app_data.dart';
import 'error_log_service.dart';
import 'local_storage_paths.dart';
import 'storage_crypto.dart';
import 'storage_key_store.dart';

/// 数据加载结果：区分正常加载、从备份恢复、重置为空三种情况，
/// 供 UI 向用户给出相应提示。
class DataLoadResult {
  final AppData data;

  /// 主文件损坏、已从备份恢复并成功写回主文件。
  final bool restoredFromBackup;

  /// 主文件损坏、备份可用，但把备份写回主文件失败。
  ///
  /// 此时内存里是备份数据，但磁盘主文件仍是坏的；必须暂停保存并提示用户，
  /// 否则本次会话的新数据会在关闭后全部丢失。
  final bool backupRestoreWriteFailed;

  /// 主文件与备份均不可用，数据被重置为空。
  final bool resetToEmpty;

  /// 检测到 5.0 不支持的旧版数据（LRX2 或旧目录布局）。
  ///
  /// 主程序不再包含旧格式的解密/迁移能力；必须明确拒绝，不能按空库继续。
  final bool unsupportedFormat;

  /// 读取数据目录/文件本身发生异常（权限、同步盘、杀软占用等）。
  ///
  /// 与“文件内容损坏”不同：此时原文件可能完好，必须暂停一切写入，
  /// 绝不能按空库继续运行并把空库覆盖到主文件或备份。
  final bool loadFailed;

  /// 数据密钥文件缺失/损坏，或无法由当前 Windows 用户解密。
  ///
  /// 此时绝不能生成新钥（会永久解不开原数据），也不能按空库写回。
  final bool keyUnavailable;

  const DataLoadResult({
    required this.data,
    this.restoredFromBackup = false,
    this.backupRestoreWriteFailed = false,
    this.resetToEmpty = false,
    this.unsupportedFormat = false,
    this.loadFailed = false,
    this.keyUnavailable = false,
  });
}

/// 读到 5.0 不支持的旧版数据时抛出；主程序不再包含旧格式兼容能力。
class UnsupportedStorageFormatException implements Exception {
  const UnsupportedStorageFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'UnsupportedStorageFormatException: $reason';
}

/// 数据密钥缺失/损坏/无法由当前 Windows 用户解密时抛出。
///
/// 这不是“文件损坏”，绝不能生成新钥或按空库继续覆盖原数据。
class DataKeyUnavailableException implements Exception {
  const DataKeyUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'DataKeyUnavailableException: $reason';
}

/// 本地加密存储服务：
/// 数据按 LRX3 格式（本机随机密钥 + 随机盐 + HMAC-SHA256 密钥流 + 完整性标签）
/// 写入应用文档目录；
/// 每次保存前自动备份上一份到 .bak，主文件损坏时自动从备份恢复。
///
/// **安全边界说明**：数据密钥由 DPAPI 绑定到当前 Windows 用户与本机，
/// 磁盘上不保存明文密钥；它能阻止其他用户/复制到别机后直接解密，但
/// 不防"以当前用户身份运行的程序"。HMAC 标签用于识破文件被篡改。
/// 本项目真正的隐私边界仍是**数据只存在本机、不上传服务器**。
class StorageService {
  /// 测试专用：损坏文件隔离（rename）故障注入（B-20）。
  ///
  /// 默认走 `File.rename`；测试可注入一个始终抛错的实现，验证
  /// “隔离失败 → 保存被拒、主文件不被覆盖”的分支（此前无法稳定复现）。
  @visibleForTesting
  static Future<void> Function(File source, String target)?
  debugIsolateOverride;

  /// 本机随机数据密钥（32 字节），由 Windows DPAPI 保护后存于
  /// `数据文件路径.key`。主程序不含任何内置密钥。
  static Uint8List? _dataKeyBytes;

  /// 测试专用：注入固定 32 字节密钥，避免测试触碰 DPAPI / 真实密钥文件。
  @visibleForTesting
  static Uint8List? debugDataKeyOverride;

  /// 测试专用：清空已初始化的密钥，便于模拟换机/换用户后重新初始化。
  @visibleForTesting
  static void debugResetKey() {
    _dataKeyBytes = null;
  }

  /// 初始化本机数据密钥。必须在读取/写入加密数据之前调用。
  ///
  /// 5.0 只支持 LRX3：存在数据但没有密钥时一律拒绝新建，避免新钥解不开原数据。
  /// 旧版 LRX2 或旧目录布局直接抛 [UnsupportedStorageFormatException]，
  /// 不能生成新钥后继续运行。
  static Future<void> initializeKey() async {
    if (_dataKeyBytes != null) return;
    final override = debugDataKeyOverride;
    if (override != null) {
      if (override.length != 32) {
        throw StateError('测试数据密钥必须是 32 字节');
      }
      _dataKeyBytes = Uint8List.fromList(override);
      return;
    }
    await LocalStoragePaths.ensureRoot();
    final dataPath = (await LocalStoragePaths.dataFile()).path;
    final keyFile = File('$dataPath.key');
    final mainFile = File(dataPath);
    final backupFile = File('$dataPath.bak');
    final dataExists = await mainFile.exists() || await backupFile.exists();
    if (!dataExists) {
      final legacyMain = await LocalStoragePaths.legacyDataFile();
      final legacyBackup = await LocalStoragePaths.legacyBackupFile();
      if (await legacyMain.exists() || await legacyBackup.exists()) {
        throw const UnsupportedStorageFormatException('不兼容的数据目录布局');
      }
    } else if (!await keyFile.exists()) {
      // 没有密钥时先识别 LRX2：它需要的是迁移工具，而不是“密钥损坏”。
      for (final file in [mainFile, backupFile]) {
        if (!await file.exists()) continue;
        if (_isLegacyData(await file.readAsString())) {
          throw const UnsupportedStorageFormatException('LRX2 加密数据');
        }
      }
    }
    try {
      _dataKeyBytes = await StorageKeyStore(
        keyFile,
      ).loadOrCreate(createIfMissing: !dataExists);
    } on FormatException catch (e) {
      throw DataKeyUnavailableException(e.message.toString());
    } on Object catch (e) {
      throw DataKeyUnavailableException('数据密钥无法读取：$e');
    }
  }

  static Uint8List _requireDataKey() {
    final key = _dataKeyBytes ?? debugDataKeyOverride;
    if (key == null) {
      throw StateError('数据密钥尚未初始化');
    }
    return key;
  }

  static String _encodeData(String plainText) =>
      StorageCrypto.encodeV3(plainText, _requireDataKey());

  static String? _decodeData(String encodedText) =>
      StorageCrypto.decodeV3(encodedText, _requireDataKey());

  static bool _isLegacyData(String text) {
    try {
      final bytes = base64Decode(text.trim());
      return StorageCrypto.isV2(bytes);
    } on FormatException catch (_) {
      return false;
    }
  }

  /// 通用本地文本加密（日志/锁定状态）。
  ///
  /// 把任意本地文本编码为与主数据文件相同的 LRX3 密文。
  static String encodeLocalText(String plainText) => _encodeData(plainText);

  /// 解码 [encodeLocalText] 生成的文本；不是密文/已损坏返回 null。
  static String? decodeLocalText(String encodedText) =>
      _decodeData(encodedText.trim());

  /// 是否是本程序写出的 LRX3 密文（用于识别加密文本文件）。
  static bool looksLikeEncryptedText(String text) =>
      StorageCrypto.looksEncrypted(text);

  // ---------------- 以下三个方法仅供单元测试使用 ----------------

  /// 测试用：编码 AppData（不落盘）。
  Future<String> encodeForTest(AppData data) async =>
      _encodeData(jsonEncode(data.toJson()));

  /// 测试用：解码文本为 AppData（失败返回 null）。
  Future<AppData?> decodeForTest(String text) async {
    final json = _decodeData(text);
    if (json == null) return null;
    final map = jsonDecode(json) as Map<String, dynamic>;
    return AppData.fromJson(map);
  }

  /// 测试用：解码为 JSON 字符串。
  Future<String?> decodeRawForTest(String text) async => _decodeData(text);

  /// 数据文件绝对路径（"关于"中展示、手动备份时使用）。
  Future<String> get dataFilePath async {
    await LocalStoragePaths.ensureRoot();
    return (await LocalStoragePaths.dataFile()).path;
  }

  Future<DataLoadResult> loadData() async {
    try {
      await initializeKey();
      final result = await _loadDataOrThrow();
      // 成功加载后才解除写入限制；上一次失败留下的 flag 不应跨成功加载存在。
      _writesBlocked = false;
      return result;
    } on UnsupportedStorageFormatException catch (e, s) {
      _writesBlocked = true;
      _mainFileParsable = false;
      _lastWrittenLength = -1;
      _lastWrittenDigest = null;
      appendErrorLog(
        'storage_service',
        e,
        s,
        context: '检测到 5.0 不支持的数据格式，已暂停保存',
      );
      return DataLoadResult(data: AppData.empty(), unsupportedFormat: true);
    } on DataKeyUnavailableException catch (e, s) {
      _writesBlocked = true;
      _mainFileParsable = false;
      _lastWrittenLength = -1;
      _lastWrittenDigest = null;
      appendErrorLog(
        'storage_service',
        e,
        s,
        context: '数据密钥缺失或无法解密，已暂停保存以保护原数据',
      );
      return DataLoadResult(
        data: AppData.empty(),
        keyUnavailable: true,
      );
    } on Object catch (e, s) {
      // 读取目录/文件本身失败：原文件状态未知，暂停全部写入。
      // 这里绝不能返回“空库 + 可写”，否则启动自动备份会立即把空库
      // 覆盖到主文件和 .bak（审计 P0-1 已复现）。
      _writesBlocked = true;
      _mainFileParsable = false;
      _lastWrittenLength = -1;
      _lastWrittenDigest = null;
      appendErrorLog('storage_service', e, s, context: '读取数据文件失败，已暂停保存以保护原文件');
      return DataLoadResult(data: AppData.empty(), loadFailed: true);
    }
  }

  /// 读取数据；任何 IO/解密异常都会向上抛，由 [loadData] 统一转为
  /// “加载失败、暂停写入”，不要在这里吞成 null 当成“文件损坏”。
  Future<DataLoadResult> _loadDataOrThrow() async {
    final filePath = await dataFilePath;
    final loaded = await _tryLoadFile(filePath, throwOnReadError: true);
    if (loaded != null) {
      _mainFileParsable = true;
      _lastWrittenLength = await File(filePath).length();
      _lastWrittenDigest = await _digestOfFile(filePath);
      return DataLoadResult(data: loaded);
    }
    final fileExisted = await File(filePath).exists();
    // 主文件存在却解析不出来 → 标记不可解析（下次保存不覆盖 .bak）。
    _mainFileParsable = !fileExisted;
    _lastWrittenLength = -1;
    _lastWrittenDigest = null;
    // 主文件缺失或损坏时，尝试用上一份备份恢复。
    final backup = await _tryLoadFile('$filePath.bak', throwOnReadError: true);
    if (backup != null) {
      var restoredToMain = false;
      try {
        final backupContent = await File('$filePath.bak').readAsString();
        // 修复（审查四 S-3）：恢复写主文件同样走原子写并接在保存队列队尾，
        // 与 saveData 串行 —— 此前普通 writeAsString 既非原子、也不进队列，
        // 恢复瞬间与自动保存交错会把"恢复前旧数据"盖回主文件。
        final previous = _saveChain;
        final restore = previous.then(
          (_) => AtomicFile.writeString(filePath, backupContent),
        );
        _saveChain = restore.then((_) {}, onError: (_) {});
        await restore;
        _mainFileParsable = true;
        _lastWrittenLength = await File(filePath).length();
        _lastWrittenDigest = _digestOfText(backupContent);
        restoredToMain = true;
      } catch (e) {
        // 写回失败时主文件仍是坏内容：保持 _mainFileParsable=false，
        // 由调用方进入错误态并暂停保存，绝不能谎报“已恢复”。
        debugPrint('Error restoring backup: $e');
        appendErrorLog('storage_service', e, StackTrace.current);
      }
      return DataLoadResult(
        data: backup,
        restoredFromBackup: restoredToMain,
        backupRestoreWriteFailed: !restoredToMain,
      );
    }
    // 5.0 不再迁移旧版目录布局；检测到旧数据时明确拒绝，避免生成空库。
    if (!fileExisted) {
      final legacyMain = await LocalStoragePaths.legacyDataFile();
      final legacyBackup = await LocalStoragePaths.legacyBackupFile();
      if (await legacyMain.exists() || await legacyBackup.exists()) {
        throw const UnsupportedStorageFormatException('不兼容的数据目录布局');
      }
    }
    if (fileExisted) {
      final corrupt =
          '$filePath.corrupt_${DateTime.now().millisecondsSinceEpoch}';
      try {
        final isolator = debugIsolateOverride;
        if (isolator != null) {
          await isolator(File(filePath), corrupt);
        } else {
          await File(filePath).rename(corrupt);
        }
      } catch (e) {
        appendErrorLog(
          'storage_service',
          e,
          StackTrace.current,
          context: '损坏主文件隔离失败，已阻止自动覆盖',
        );
      }
    }
    // 文件存在但解析失败、且无可用备份，视为数据重置；完全不存在则是首次启动。
    return DataLoadResult(data: AppData.empty(), resetToEmpty: fileExisted);
  }

  /// 读取并解析数据文件；文件不存在、解密失败或内容损坏时返回 null。
  ///
  /// [throwOnReadError] 为 true 时，**读盘本身失败**（权限、占用、同步盘
  /// 瞬时错误等）向上抛出，由 [loadData] 转为"加载失败、暂停写入"；只有
  /// "文件不存在/内容损坏"才返回 null。此前两者同返 null，会把一次读盘
  /// 瞬断当作数据损坏，进而用旧 .bak 覆盖完好的主文件（审计 P1-3）。
  Future<AppData?> _tryLoadFile(
    String path, {
    bool throwOnReadError = false,
  }) async {
    final file = File(path);
    bool exists;
    try {
      exists = await file.exists();
    } on Object catch (e, s) {
      if (throwOnReadError) rethrow;
      debugPrint('Error checking $path: $e');
      appendErrorLog('storage_service', e, s);
      return null;
    }
    if (!exists) return null;

    String content;
    try {
      content = await file.readAsString();
    } on Object catch (e, s) {
      if (throwOnReadError) rethrow;
      debugPrint('Error reading $path: $e');
      appendErrorLog('storage_service', e, s);
      return null;
    }

    if (_isLegacyData(content)) {
      throw const UnsupportedStorageFormatException('LRX2 加密数据');
    }
    try {
      final decrypted = _decodeData(content);
      if (decrypted == null) return null;
      final json = jsonDecode(decrypted) as Map<String, dynamic>;
      return AppData.fromJson(json);
    } catch (e, s) {
      debugPrint('Error parsing $path: $e');
      appendErrorLog('storage_service', e, s);
      return null;
    }
  }

  /// 保存成功返回 true；失败返回 false（不抛异常），由调用方提示用户。
  ///
  /// 所有 saveData 调用共享同一条串行队列（P1-4 修复：此前 performBackup 的
  /// 直写可能与用户操作触发的保存并发，互相踩踏 .tmp 与 .bak 保护）。
  Future<bool> saveData(AppData data) {
    final previous = _saveChain;
    final run = previous.then((_) => _saveDataNow(data));
    _saveChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _saveChain = Future<void>.value();

  /// 主文件是否已被确认"可解析"（修复 6.2，2026-10-03 审查）。
  /// 保存时用它代替"每次保存都把旧文件完整解密+解析一遍"——后者让单次保存的
  /// CPU/IO 直接翻倍（叠加加密自身开销后成为最大的卡顿来源）。
  /// 语义：加载成功或写入成功后为 true；主文件存在却解析不出来时为 false
  /// （此时保存**不覆盖 .bak**，保住最后一份可用备份）。
  bool _mainFileParsable = true;

  /// 加载阶段发生 IO 异常后置 true：拒绝一切保存，直到下一次成功加载。
  bool _writesBlocked = false;

  /// 外部（如 provider 初始化 catch）主动暂停写入，避免空库覆盖原文件。
  void blockWrites(String reason) {
    _writesBlocked = true;
    _mainFileParsable = false;
    _lastWrittenLength = -1;
    _lastWrittenDigest = null;
    appendErrorLog('storage_service', reason, null, context: '数据加载异常，已暂停保存');
  }

  /// 本程序上次写入主文件后的**字节长度**（-1 = 未知）。
  ///
  /// 与 [_mainFileParsable] 配合做"轻量一致性校验"：只有长度与上次写入一致，
  /// 才能确信文件没被外部改动过（正常路径只多一次 stat，成本极低）。
  /// 长度不符（外部替换/损坏/截断）或标记不可解析时，才退回完整解密解析确认。
  /// —— 这条校验保证了"运行期文件被外部破坏 → 保存时不会把坏内容覆盖进 .bak"
  /// （backup_restore_test 的"主文件已损坏时不覆盖 .bak"用例在守这一点）。
  int _lastWrittenLength = -1;

  /// 上次写入主文件内容的 SHA-256（B-08）。
  ///
  /// 仅比较长度无法发现"外部把主文件替换成同长度损坏内容"：此时长度一致，
  /// 保存会误以为主文件仍是自己写的，把损坏内容覆盖进 `.bak`，毁掉最后一份
  /// 可用备份。这里用内容摘要做第二道校验（不一致时退回完整解析确认）。
  String? _lastWrittenDigest;

  static String _digestOfText(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  Future<String?> _digestOfFile(String path) async {
    try {
      return sha256.convert(await File(path).readAsBytes()).toString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _saveDataNow(AppData data) async {
    if (_writesBlocked) {
      appendErrorLog(
        'storage_service',
        '数据加载失败后已暂停保存，拒绝写入',
        null,
        context: '保护原文件，避免空库覆盖',
      );
      return false;
    }
    try {
      final filePath = await dataFilePath;
      final file = File(filePath);
      if (!await file.exists()) {
        final legacyFile = await LocalStoragePaths.legacyDataFile();
        final legacyBackup = await LocalStoragePaths.legacyBackupFile();
        final hasLegacyData =
            await legacyFile.exists() || await legacyBackup.exists();
        if (hasLegacyData) {
          appendErrorLog(
            'storage_service',
            '文档目录仍有数据未转移，已阻止保存空库',
            null,
            context: legacyFile.path,
          );
          return false;
        }
      }
      if (!_mainFileParsable && await file.exists()) {
        appendErrorLog('storage_service', '损坏主文件未隔离，已阻止自动覆盖', null);
        return false;
      }
      final json = jsonEncode(data.toJson());
      final encrypted = _encodeData(json);
      // 写新数据前保留上一份备份，防止文件损坏导致数据全部丢失。
      // 只有"当前主文件确实能解析"时才覆盖 .bak，避免把损坏内容顶掉
      // 最后一份可用备份。
      final length = await file.exists() ? await file.length() : 0;
      if (length > 0) {
        // 修复（6.2）：先用"长度与上次写入是否一致"做廉价判断；
        // B-08：长度一致也需要内容摘要一致——外部同长度篡改会让长度检查失效。
        var canOverwriteBackup =
            _mainFileParsable && _lastWrittenLength == length;
        if (canOverwriteBackup) {
          final digest = await _digestOfFile(filePath);
          canOverwriteBackup =
              digest != null &&
              _lastWrittenDigest != null &&
              digest == _lastWrittenDigest;
        }
        // 只有“从未记录过摘要”（首次运行/旧版本残留）时才允许靠解析兜底。
        // 摘要已知却不一致，说明主文件被外部替换成了另一份合法数据；此时
        // 再靠“能解析”覆盖 .bak，会把最后一份可用备份顶掉（B-08 想防的正是这个）。
        if (!canOverwriteBackup && _lastWrittenDigest == null) {
          canOverwriteBackup = (await _tryLoadFile(filePath)) != null;
        }
        if (canOverwriteBackup) {
          // 第 1 轮 X-1 修复：备份拷贝必须独立 try —— 此前它与下面的主文件写入
          // 共用外层 try，磁盘满或 .bak 被杀软/他进程占用时 copy 抛错会让**整次保存
          // 失败、主文件根本不写**，明明可写的数据反而丢失。
          // 备份失败只记日志：主文件能写就一定要写。
          try {
            // G-21：改原子复制（临时文件 + rename）—— 此前 `file.copy` 直接覆盖，
            // 中途掉电会留下截断的 .bak。
            await AtomicFile.copyAtomic(filePath, '$filePath.bak');
          } catch (e) {
            debugPrint('覆盖 .bak 失败（不影响主文件写入）：$e');
            appendErrorLog('storage_service', e, StackTrace.current);
          }
        } else {
          debugPrint('主文件当前无法解析，跳过覆盖 .bak 以保留可用备份');
        }
      }
      // 原子写（P1-4 修复）：统一走 AtomicFile（唯一临时文件 + rename 直接覆盖
      // + Windows 偶发拒绝访问的退避重试）。此前"先删主文件再改名"存在主文件
      // 消失的时间窗，掉电/进程被杀会丢主文件；两套实现也已合并为一套。
      await AtomicFile.writeString(filePath, encrypted);
      // 刚写入的内容必然合法：主文件恢复为"可解析"，并记下新长度/摘要。
      _mainFileParsable = true;
      _lastWrittenDigest = _digestOfText(encrypted);
      try {
        _lastWrittenLength = await file.length();
      } catch (_) {
        _lastWrittenLength = -1;
      }
      return true;
    } catch (e) {
      debugPrint('Error saving data: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
      return false;
    }
  }

  /// 将当前数据文件复制到 [targetPath]，成功返回 true。
  /// 调用方应确保数据已落盘（可先调用 [saveData]）。
  ///
  /// [password] 为空时生成普通本机备份（仍由本机 DPAPI 密钥保护）；非空时
  /// 额外写一个 `targetPath.pkey` 口令信封，使 `.enc` + `.pkey` 可在另一台
  /// 机器上恢复。`pkey` 与 `.enc` 必须一起保存，缺一不可。
  Future<bool> backupTo(String targetPath, {String? password}) async {
    try {
      final filePath = await dataFilePath;
      final file = File(filePath);
      if (!await file.exists()) return false;
      final target = File(targetPath);
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      if (password != null && password.isNotEmpty) {
        final content = await file.readAsString();
        final bytes = base64Decode(content.trim());
        if (!StorageCrypto.isV3(bytes)) return false;
        final envelope = BackupCrypto.wrapKey(_requireDataKey(), password);
        final keySidecar = '$targetPath.pkey';
        try {
          await AtomicFile.writeString(keySidecar, envelope);
          await AtomicFile.copyAtomic(filePath, targetPath);
        } on Object {
          // 两个文件必须成对；任一步失败都不留下半份便携备份。
          final sidecar = File(keySidecar);
          if (await sidecar.exists()) await sidecar.delete();
          rethrow;
        }
        return true;
      }
      // B-08：备份复制也走原子写（临时文件 + rename），避免中途掉电留下
      // 截断的备份文件；此前 `file.copy` 直接覆盖。
      await AtomicFile.copyAtomic(filePath, targetPath);
      return true;
    } catch (e) {
      debugPrint('Error backing up data: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
      return false;
    }
  }

  /// 是否为带口令信封的便携备份。
  Future<bool> isPortableBackup(String sourcePath) async =>
      File('$sourcePath.pkey').exists();

  /// 从备份文件恢复数据。
  /// 依次逐层校验：Base64 → 魔数（LRX3）→ 解密与完整性校验 → JSON → AppData，
  /// **全部校验通过后**才把当前数据另存为 .bak 并用备份覆盖主文件，
  /// 保证校验失败时绝不改动现有数据。
  ///
  /// 若备份旁存在 `.pkey` 口令信封，则 [backupPassword] 必须提供；恢复时用
  /// 信封里的数据密钥解密，再用本机当前密钥重新加密写回主文件。
  /// 成功返回 null；失败返回中文错误原因。
  Future<String?> restoreFrom(
    String sourcePath, {
    String? backupPassword,
  }) async {
    final String raw;
    try {
      final file = File(sourcePath);
      if (!await file.exists()) return '备份文件不存在';
      raw = await file.readAsString();
    } catch (e) {
      debugPrint('Error reading backup file: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
      return '无法读取备份文件';
    }

    // 统一按"去首尾空白"处理：Base64 文本里的换行/空格不参与校验，
    // 否则被编辑过或经同步工具转存的备份会读不出来。
    final content = raw.trim();

    // 便携备份：先解出口令包裹的数据密钥；口令错误时不解密、不写盘。
    Uint8List? portableKey;
    final keySidecar = File('$sourcePath.pkey');
    if (await keySidecar.exists()) {
      if (backupPassword == null || backupPassword.isEmpty) {
        return '此备份需要备份口令，请输入后再恢复';
      }
      String envelope;
      try {
        envelope = await keySidecar.readAsString();
      } catch (e) {
        appendErrorLog('storage_service', e, StackTrace.current);
        return '无法读取备份密钥文件';
      }
      portableKey = BackupCrypto.unwrapKey(envelope, backupPassword);
      if (portableKey == null) return '备份口令错误或密钥文件已损坏';
    }

    // 第一层：Base64 解码 + 魔数校验，确认是本系统生成的数据文件。
    Uint8List bytes;
    try {
      bytes = base64Decode(content);
    } catch (e) {
      return '文件格式不正确';
    }
    if (StorageCrypto.isV2(bytes)) {
      return '这是需要转换的加密备份，请先运行数据转换工具后再恢复';
    }
    if (!StorageCrypto.isV3(bytes)) {
      return '文件格式不正确';
    }
    // 第二层：解密 + 完整性校验（LRX3 先验 HMAC 再解密）。
    final decrypted = portableKey == null
        ? _decodeData(content)
        : StorageCrypto.decodeV3(content, portableKey);
    if (decrypted == null) return '数据文件已损坏';
    // 第三层：JSON 解析与数据结构解析。
    try {
      final json = jsonDecode(decrypted);
      if (json is! Map<String, dynamic>) return '数据文件已损坏';
      AppData.fromJson(json);
    } catch (e) {
      return '数据文件已损坏';
    }
    // 便携备份里的密文用备份带出的数据密钥加密；写回主文件前必须换成本机
    // 当前密钥，否则下次 loadData 会解不开。
    final output = portableKey == null ? content : _encodeData(decrypted);

    // 校验全部通过，执行覆盖（先保留当前数据为 .bak）。
    try {
      final filePath = await dataFilePath;
      final mainFile = File(filePath);
      // 正在恢复的源就是 .bak 时，不能先用当前主文件覆盖它——否则写主文件
      // 一旦失败，用户选中的那份备份已经被毁掉。审计 P2-1：路径必须按
      // 绝对路径归一化比较（大小写/短路径/符号链接/从"浏览其它位置"选中
      // .bak 时，字符串精确比较会漏判并先毁掉用户选中的备份）。
      String normalize(String path) =>
          File(path).absolute.path.replaceAll('\\', '/').toLowerCase();
      final sourceIsBak = normalize(sourcePath) == normalize('$filePath.bak');
      if (!sourceIsBak &&
          await mainFile.exists() &&
          await mainFile.length() > 0) {
        // 修复（审计 P2-39）：.bak 也走原子复写（与 saveData 的 G-21 同口径），
        // 中断不再留下截断的备份。
        await AtomicFile.copyAtomic(filePath, '$filePath.bak');
      }
      // 修复（审查四 S-3）：覆盖主文件改原子写并接在保存队列队尾，
      // 与 saveData 串行（同上，避免与自动保存交错覆盖）。
      final previous = _saveChain;
      final restore = previous.then(
        (_) => AtomicFile.writeString(filePath, output),
      );
      _saveChain = restore.then((_) {}, onError: (_) {});
      await restore;
      // 恢复写入后同步缓存，避免下一次保存把新内容误判为“外部篡改”。
      _mainFileParsable = true;
      _lastWrittenDigest = _digestOfText(output);
      try {
        _lastWrittenLength = await mainFile.length();
      } catch (_) {
        _lastWrittenLength = -1;
      }
      return null;
    } catch (e) {
      debugPrint('Error restoring from backup: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
      return '恢复失败：无法写入数据文件';
    }
  }
}
