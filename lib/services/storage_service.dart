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
import 'storage_key_id.dart';
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

  /// 主文件与 `.bak` 都解不开，且旁挂密钥指纹证明"密钥不是写这份数据的那把"
  /// （审计 A-02）。
  ///
  /// 与 [resetToEmpty] 的区别：数据**没有损坏**，换回原 `.enc.key` 即可完整
  /// 恢复。因此这里既不隔离原文件，也不允许按空库继续。
  final bool keyMismatch;

  /// 主文件不存在（或被误删），但唯一的 `.bak` 存在且解不开（审计 P1-1）。
  ///
  /// 这是"最危险的一次启动"：磁盘上还剩一份可能可以人工抢救的备份，
  /// 若按"首次启动"放行，用户录入数据后第二次保存就会把空库写进 `.bak`
  /// （已实证复现）。因此必须阻断写入，并在用户确认以空库继续时先把这份
  /// `.bak` 改名隔离保留。
  final bool backupUnreadable;

  /// 本次启动被隔离的损坏文件路径（`*.corrupt_<毫秒>`）。
  ///
  /// 只用于提示文案；用户确认以空库继续后，该文件仍留在磁盘上供人工抢救。
  final String? quarantinedPath;

  const DataLoadResult({
    required this.data,
    this.restoredFromBackup = false,
    this.backupRestoreWriteFailed = false,
    this.resetToEmpty = false,
    this.unsupportedFormat = false,
    this.loadFailed = false,
    this.keyUnavailable = false,
    this.keyMismatch = false,
    this.backupUnreadable = false,
    this.quarantinedPath,
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

  /// 测试专用：替换一次 `loadData()` 的返回值。
  ///
  /// 审计补强（P1-5）：需要稳定复现「恢复已经写盘、但紧接着读取校验失败」
  /// 这一磁盘/权限级故障。真实触发要求文件在写完到读回之间被改动，靠
  /// 文件系统难以稳定构造；这里允许测试直接给出一次失败结果。
  /// 只在 `loadData()` 入口生效一次，用完必须置回 null。
  ///
  /// 生产安全性（提交前收尾）：字段本身是 `static`，没有任何生产调用点
  /// （`grep -rn debugLoadOverride lib` 只命中本文件的声明与下面那处读取）；
  /// `loadData()` 读取时用 `kReleaseMode` 短路，release 构建里常量折叠成
  /// `null`，即使有人通过反射/插件把值写进来也不会改变真实加载行为。
  @visibleForTesting
  static DataLoadResult Function()? debugLoadOverride;

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
      // 审计复核（P2-10 的衍生问题）：独占创建是「先建 0 字节文件占位，再
      // rename 覆盖上内容」，进程恰好死在两步之间会永久留下空密钥文件。旧实现
      // 「先写临时文件再改名」不会留下空文件。此时若连主文件/备份都不存在，
      // 就没有任何数据需要这把钥保护 —— 丢弃空占位、重建一把即可自愈；
      // 一旦存在数据文件，仍然抛错交给用户处理（绝不用新钥覆盖旧数据）。
      if (!dataExists && await _isEmptyKeyPlaceholder(keyFile)) {
        try {
          await keyFile.delete();
          _dataKeyBytes = await StorageKeyStore(
            keyFile,
          ).loadOrCreate(createIfMissing: true);
          appendErrorLog('storage_service', '发现空的密钥占位文件且无数据文件，已重建数据密钥', null);
          return;
        } on Object catch (retryError, retryStack) {
          appendErrorLog(
            'storage_service',
            retryError,
            retryStack,
            context: '重建数据密钥失败',
          );
          throw DataKeyUnavailableException('数据密钥无法读取：$retryError');
        }
      }
      throw DataKeyUnavailableException(e.message.toString());
    } on Object catch (e) {
      throw DataKeyUnavailableException('数据密钥无法读取：$e');
    }
  }

  /// 密钥文件存在且为空（独占占位后进程被打断留下的中间态）。
  static Future<bool> _isEmptyKeyPlaceholder(File keyFile) async {
    try {
      return await keyFile.length() == 0;
    } on Object catch (_) {
      return false;
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
    // 审计补强（P1-5）：测试注入的失败结果，只在入口生效一次。
    // release 构建里 `kReleaseMode` 恒为 true，整段被常量折叠掉。
    final injected = kReleaseMode ? null : debugLoadOverride;
    if (injected != null) return injected();
    try {
      await initializeKey();
      final result = await _loadDataOrThrow();
      // 重启后重新扫描隔离文件（解码 A-01 保护条件）：用户手工删除
      // `*.corrupt_*` 之后，`.bak` 保护会自动解除，无需额外操作。
      // 注意必须放在 `_loadDataOrThrow()` **之后**：这里要读数据目录，
      // 若提前扫描，一次目录瞬时读失败会被扫描吞掉，反而把"加载失败、
      // 暂停写入"掩盖成"加载成功"（storage_load_failure_test 覆盖）。
      await _scanQuarantineFiles();
      if (result.resetToEmpty ||
          result.keyMismatch ||
          result.keyUnavailable ||
          result.backupUnreadable) {
        // 审计 A-01：隔离或错钥都**不是**可继续写入的状态 —— 必须等用户
        // 明确确认（或换回原密钥）。此前这里直接 `_writesBlocked = false`，
        // 于是"空库 + 可写"在第二次保存时把唯一的 `.bak` 也覆盖掉。
        _writesBlocked = true;
        _mainFileParsable = false;
        _lastWrittenLength = -1;
        _lastWrittenDigest = null;
        return result;
      }
      // 成功加载后才解除写入限制；上一次失败留下的 flag 不应跨成功加载存在。
      _writesBlocked = false;
      // 加载成功即可确认密钥与数据匹配：顺手校正指纹（A-02 规则 3）。
      await _refreshKeyId();
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
      return DataLoadResult(data: AppData.empty(), keyUnavailable: true);
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
    // 审计 A-02 补充（GUI 验收发现）：`.bak` 能解开时此前会直接把它写回主文件，
    // 于是"用户还原了旧的 .enc、而 .bak 是本机较新的一份"会静默丢掉旧数据，
    // 而且永远走不到下面的指纹判定。指纹只能由本机密钥算出，对不上就说明
    // 主文件不是当前密钥加密的 —— 此时必须停下来让用户换回原 `.enc.key`，
    // 不能拿 `.bak` 顶上去。
    if (fileExisted && await _keyIdMismatch()) {
      appendErrorLog(
        'storage_service',
        '数据密钥与文件指纹不匹配：主文件未隔离、未重置、未用 .bak 覆盖',
        null,
        context: 'loadData 判定 keyMismatch（早于 .bak 恢复）',
      );
      return DataLoadResult(data: AppData.empty(), keyMismatch: true);
    }
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
        // 审计 B-34：指纹缺失（旧数据）或内容损坏时，`.bak` + 当前密钥能解开，
        // 说明密钥本身没问题，直接自动恢复并留痕，避免用户面对"打不开"。
        appendErrorLog(
          'storage_service',
          '主文件无法解密，已用备份恢复并写回主文件',
          null,
          context: '$filePath.bak',
        );
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
      // 审计 P1-1：主文件不在，但 `.bak` **存在且解不开**。这不是首次启动，
      // 而是"主文件被误删/被隔离，只剩一份读不出来的备份"——最坏的情况下
      // 这份 `.bak` 正是唯一可人工抢救的数据。此前这里返回
      // `resetToEmpty: fileExisted == false`，于是被当成首次启动放行：
      // 用户录入数据后第二次保存就会满足"主文件可解析 + 长度/摘要一致"，
      // 把新建的空库写进 `.bak`，最后一份备份也没了（已实证复现）。
      final backupExists = await File('$filePath.bak').exists();
      if (backupExists) {
        _unreadableBackupProtected = true;
        _quarantinePresent = true;
        appendErrorLog(
          'storage_service',
          '主文件缺失且唯一的备份无法解密，已暂停写入以保护备份',
          null,
          context: '$filePath.bak',
        );
        return DataLoadResult(data: AppData.empty(), backupUnreadable: true);
      }
    }
    String? quarantinedPath;
    // 审计 B-34（方案 1）：区分"内容损坏"与"密钥不对"。
    // 主文件是一份**格式合法的 LRX3 密文**却用当前密钥解不开时，问题在密钥
    // （换机、换 Windows 用户、`.enc.key` 被覆盖），数据本身很可能完好；
    // 这种情况必须以 `keyUnavailable` 停下来并暂停写入，而不是当成内容损坏
    // 让用户"确认以空库继续"。非密文内容（截断、写成纯文本等）仍按原逻辑
    // 走 `resetToEmpty`（`test/storage_key_mismatch_test.dart` 固化了该判定）。
    var sealedButUndecryptable = false;
    if (fileExisted) {
      try {
        sealedButUndecryptable = StorageCrypto.looksEncrypted(
          await File(filePath).readAsString(),
        );
      } on Object catch (e, s) {
        appendErrorLog('storage_service', e, s, context: '判定主文件内容形态失败');
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
        quarantinedPath = corrupt;
        _quarantinePresent = true;
        _lastQuarantinePath = corrupt;
      } catch (e) {
        appendErrorLog(
          'storage_service',
          e,
          StackTrace.current,
          context: '损坏主文件隔离失败，已阻止自动覆盖',
        );
      }
      appendErrorLog(
        'storage_service',
        sealedButUndecryptable
            ? '主文件是合法密文但当前密钥无法解密，已隔离并暂停写入（换回原 Windows '
                  '用户/原 .enc.key 后可继续使用该隔离文件）'
            : '主文件与备份均无法解密，已暂停写入并等待用户确认',
        null,
        context: quarantinedPath ?? '$filePath（隔离失败，原文件保留）',
      );
    }
    if (sealedButUndecryptable) {
      // 数据被原样保留在隔离文件里，且**没有**用新密钥重建任何文件。
      return DataLoadResult(
        data: AppData.empty(),
        keyUnavailable: true,
        quarantinedPath: quarantinedPath,
      );
    }
    // 文件存在但解析失败、且无可用备份，视为数据重置（需用户确认后才可写）；
    // 文件完全不存在则是首次启动，可正常写入。
    return DataLoadResult(
      data: AppData.empty(),
      resetToEmpty: fileExisted,
      quarantinedPath: quarantinedPath,
    );
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

  /// 本次运行检测到损坏隔离文件（`*.corrupt_*`），或本次加载刚隔离出一份
  /// （审计 A-01）。
  ///
  /// 用途只有一条：在"库还是空的"期间**不覆盖 `.bak`**，避免用户确认以空库
  /// 继续后，第二次保存把仅剩的可用备份顶掉。库一旦有数据即恢复正常轮转。
  bool _quarantinePresent = false;

  /// 最近一次发现的隔离文件路径（仅用于日志/提示）。
  String? _lastQuarantinePath;

  /// 主文件缺失、唯一 `.bak` 又解不开（审计 P1-1）。
  ///
  /// 此时磁盘上还剩一份**可能可以人工抢救**的备份，绝不能被当成"首次启动"
  /// 放行——否则用户录入数据后第二次保存就会把它顶掉（已实证复现）。
  /// 用户确认以空库继续时，这份备份会被改名成 `*.corrupt_<毫秒>` 保留。
  bool _unreadableBackupProtected = false;

  /// 指纹写入失败，等下一次保存重试（审计 A-02 规则 3）。
  bool _pendingKeyIdRefresh = false;

  /// 本次运行已确认指纹与当前密钥一致（避免每次保存都多读一次小文件）。
  bool _keyIdVerified = false;

  /// "库为空时暂不覆盖 .bak"只记一次日志，避免每次保存刷屏。
  bool _backupProtectionNoted = false;

  /// 本次运行是否存在损坏隔离文件（是否处于"备份保护期"）。
  bool get quarantinePresent => _quarantinePresent;

  /// 最近一次发现的隔离文件路径。
  String? get lastQuarantinePath => _lastQuarantinePath;

  /// 外部（如 provider 初始化 catch）主动暂停写入，避免空库覆盖原文件。
  void blockWrites(String reason) {
    _writesBlocked = true;
    _mainFileParsable = false;
    _lastWrittenLength = -1;
    _lastWrittenDigest = null;
    appendErrorLog('storage_service', reason, null, context: '数据加载异常，已暂停保存');
  }

  /// 用户确认"以空库继续"后解除写入阻断（审计 A-01）。
  ///
  /// 前置条件由调用方保证：数据文件已被隔离（磁盘上不存在可解析的主文件）。
  /// 若隔离本身失败（原文件仍在），这里**不会**解除"损坏文件不得覆盖"的
  /// 保护，保存会继续被 [_saveDataNow] 拒绝 —— 宁可让用户去删文件，也不能
  /// 用空库盖掉唯一可抢救的副本。
  ///
  /// `.bak` 保护不在这里解除：它由 [quarantinePresent] 与"库是否为空"共同
  /// 决定，用户录入第一条数据后自动恢复轮转。
  Future<bool> releaseQuarantineForEmptyLibrary() async {
    final filePath = await dataFilePath;
    final exists = await File(filePath).exists();
    // 审计 P1-1：主文件缺失但唯一 `.bak` 解不开时，用户确认"以空库继续"
    // 必须先把这份备份改名保留，否则放行后的第二次保存会把它顶掉。
    if (_unreadableBackupProtected) {
      final backup = File('$filePath.bak');
      if (await backup.exists()) {
        final target =
            '$filePath.bak.corrupt_${DateTime.now().millisecondsSinceEpoch}';
        try {
          await backup.rename(target);
          _lastQuarantinePath = target;
          _quarantinePresent = true;
        } on Object catch (e, s) {
          appendErrorLog(
            'storage_service',
            e,
            s,
            context: '无法解密的主文件缺失备份隔离失败，已保持写入阻断',
          );
          return false;
        }
      }
      _unreadableBackupProtected = false;
    }
    _writesBlocked = false;
    _mainFileParsable = !exists;
    _lastWrittenLength = -1;
    _lastWrittenDigest = null;
    appendErrorLog(
      'storage_service',
      exists ? '用户确认以空库继续，但原文件仍在磁盘上：保存仍被拒绝' : '用户确认以空库继续；在此之前不会覆盖 .bak',
      null,
      context: '隔离后解除写入阻断',
    );
    return !exists;
  }

  /// 错钥状态下用户选择"放弃可恢复数据、以空库继续"（审计 A-02 规则 5）。
  ///
  /// 仍然**不删除**任何字节：原主文件被改名为 `*.corrupt_<毫秒>` 保留，用户
  /// 换回原 `.enc.key` 后人工恢复仍可行。
  Future<bool> discardKeyMismatchAndStartEmpty() async {
    final filePath = await dataFilePath;
    final file = File(filePath);
    if (await file.exists()) {
      final target =
          '$filePath.corrupt_${DateTime.now().millisecondsSinceEpoch}';
      try {
        await file.rename(target);
        _quarantinePresent = true;
        _lastQuarantinePath = target;
      } on Object catch (e, s) {
        appendErrorLog(
          'storage_service',
          e,
          s,
          context: '错钥状态下隔离原数据失败，已保持写入阻断',
        );
        return false;
      }
    }
    return releaseQuarantineForEmptyLibrary();
  }

  /// 指纹文件路径（与主数据同目录、后缀 [StorageKeyId.fileSuffix]）。
  Future<File> _keyIdFile() async =>
      File('${await dataFilePath}${StorageKeyId.fileSuffix}');

  /// 指纹是否与当前数据密钥不匹配（缺失/非法都按"不匹配"以外处理）。
  Future<bool> _keyIdMismatch() async {
    try {
      final recorded = await StorageKeyId.read(await _keyIdFile());
      if (recorded == null) return false;
      return recorded != StorageKeyId.compute(_requireDataKey());
    } on Object catch (e, s) {
      // 指纹读不出来（权限/磁盘）：退回旧判定，绝不让辅助文件阻断启动。
      appendErrorLog('storage_service', e, s, context: '读取数据密钥指纹失败，按缺失处理');
      return false;
    }
  }

  /// 校正旁挂指纹（A-02 规则 3/4）。
  ///
  /// 写失败只记日志并置 [_pendingKeyIdRefresh]，下一次保存重试；
  /// **不影响主数据保存结果**。
  Future<void> _refreshKeyId() async {
    if (_keyIdVerified && !_pendingKeyIdRefresh) return;
    try {
      final file = await _keyIdFile();
      final current = StorageKeyId.compute(_requireDataKey());
      final recorded = await StorageKeyId.read(file);
      if (recorded == current) {
        _pendingKeyIdRefresh = false;
        _keyIdVerified = true;
        return;
      }
      final ok = await StorageKeyId.write(file, current);
      _pendingKeyIdRefresh = !ok;
      _keyIdVerified = ok;
      if (!ok) {
        appendErrorLog(
          'storage_service',
          '数据密钥指纹写入失败（下次保存重试，不影响数据保存）',
          null,
          context: file.path,
        );
      }
    } on Object catch (e, s) {
      _pendingKeyIdRefresh = true;
      _keyIdVerified = false;
      appendErrorLog('storage_service', e, s, context: '刷新数据密钥指纹失败');
    }
  }

  /// 扫描数据目录里是否存在 `*.corrupt_*` 隔离文件（A-01 保护条件）。
  Future<void> _scanQuarantineFiles() async {
    try {
      final filePath = await dataFilePath;
      final name = filePath.split(RegExp(r'[/\\]')).last;
      final prefix = '$name.corrupt_';
      final dir = File(filePath).parent;
      String? found;
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          final base = entity.path.split(RegExp(r'[/\\]')).last;
          if (base.startsWith(prefix)) {
            found = entity.path;
            break;
          }
        }
      }
      _quarantinePresent = found != null;
      _lastQuarantinePath = found;
    } on Object catch (e, s) {
      // 扫描失败时保持原值：宁可多保护一次 .bak，也不要静默放开轮转。
      appendErrorLog('storage_service', e, s, context: '扫描损坏隔离文件失败');
    }
  }

  /// 库内业务数据是否为空（A-01 保护条件的另一半）。
  ///
  /// 只看记录/考勤/名单，不看设置：用户确认空库后可能先改设置，那不代表
  /// 数据已重建，`.bak` 仍需保留。
  static bool _isEmptyLibraryFor(AppData data) {
    bool allEmpty(Iterable<List<dynamic>> buckets) =>
        buckets.every((list) => list.isEmpty);
    if (data.students.isNotEmpty) return false;
    if (!allEmpty(data.recordsByDate.values)) return false;
    if (!allEmpty(data.attendanceByDate.values)) return false;
    return true;
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
      // 审计 P2-7：备份轮转的中间态标记 —— 快照写成 `.bak.next` 后，只有主文件
      // 写入成功才把它 rename 成 `.bak`；主文件写失败则丢弃快照，`.bak` 保持
      // 仍是上一份可用备份（旧实现先覆盖 `.bak` 再写主文件，主写失败就丢档）。
      var backupRotationPending = false;
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
        // 审计 A-01：本次运行隔离过损坏文件，而库里仍是空的 —— 此时主文件
        // 就是"用户确认后新建的空库"，覆盖 `.bak` 会把最后一份可用备份顶掉。
        // 用户录入第一条数据后（库非空）自动恢复轮转，无需额外开关。
        if (canOverwriteBackup &&
            _quarantinePresent &&
            _isEmptyLibraryFor(data)) {
          canOverwriteBackup = false;
          if (!_backupProtectionNoted) {
            _backupProtectionNoted = true;
            appendErrorLog(
              'storage_service',
              '库为空且存在隔离文件：暂不覆盖 .bak（录入数据后自动恢复）',
              null,
              context: _lastQuarantinePath ?? '',
            );
          }
        }
        if (canOverwriteBackup) {
          // 第 1 轮 X-1 修复：备份拷贝必须独立 try —— 此前它与下面的主文件写入
          // 共用外层 try，磁盘满或 .bak 被杀软/他进程占用时 copy 抛错会让**整次保存
          // 失败、主文件根本不写**，明明可写的数据反而丢失。
          // 备份失败只记日志：主文件能写就一定要写。
          // 审计 P2-7：轮转顺序改为「先把旧主文件快照到 .bak.next → 主文件写成功
          // → 再把快照 rename 成 .bak」。此前先 copyAtomic 再 writeString，主文件
          // 写失败时 .bak 已被升级成新数据，「上一份备份」的回滚点丢一档。
          // 快照仍取旧主文件内容，保持 .bak = 上一版的既有语义。
          try {
            await AtomicFile.copyAtomic(filePath, '$filePath.bak.next');
            backupRotationPending = true;
          } catch (e) {
            debugPrint('备份快照失败（不影响主文件写入）：$e');
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
      // 主文件已就位，把之前的旧版快照提升为正式 `.bak`。
      if (backupRotationPending) {
        try {
          await AtomicFile.copyAtomic('$filePath.bak.next', '$filePath.bak');
          backupRotationPending = false;
        } on Object catch (e, s) {
          debugPrint('提升 .bak 快照失败（主文件已写入成功）：$e');
          appendErrorLog('storage_service', e, s);
        }
      }
      // 刚写入的内容必然合法：主文件恢复为"可解析"，并记下新长度/摘要。
      _mainFileParsable = true;
      _lastWrittenDigest = _digestOfText(encrypted);
      try {
        _lastWrittenLength = await file.length();
      } catch (_) {
        _lastWrittenLength = -1;
      }
      // 审计 A-02 规则 3：写盘成功后再校正一次指纹。失败只置待重试标记，
      // 不影响本次保存的返回值（指纹是辅助判定，不能反过来让保存失败）。
      await _refreshKeyId();
      return true;
    } catch (e) {
      debugPrint('Error saving data: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
      // 审计 P2-7：主文件写失败时丢弃未提升的快照，避免留下 `.bak.next` 垃圾；
      // `.bak` 保持为上一份可用备份不变。
      try {
        final next = File('${await dataFilePath}.bak.next');
        if (await next.exists()) await next.delete();
      } on Object catch (_) {
        // 清理失败不影响保存结果。
      }
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
        // 审计 A-20：PBKDF2 放到后台 isolate，避免创建便携备份时卡住界面。
        final envelope = await BackupCrypto.wrapKeyAsync(
          _requireDataKey(),
          password,
        );
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
      // 审计 A-20：旧版本写出的信封可能迭代数偏低，仍然放行但记录警告；
      // 迭代数低于 minIterations 或高于 maxIterations 的信封直接拒绝。
      if (BackupCrypto.isWeakEnvelope(envelope)) {
        appendErrorLog(
          'storage_service',
          '便携备份的密钥派生强度低于当前标准（仍可恢复）',
          null,
          context: 'iterations=${BackupCrypto.iterationsOf(envelope)}',
        );
      }
      portableKey = await BackupCrypto.unwrapKeyAsync(envelope, backupPassword);
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
    if (decrypted == null) {
      // 审计 A-02：本机备份 + 指纹不符 = 这份备份不是用本机密钥加密的，
      // 直接说"密钥不匹配"（用户可换回原 .key），不要笼统报"数据损坏"。
      if (portableKey == null && await _keyIdMismatch()) {
        return '恢复包密钥不匹配';
      }
      return '数据文件已损坏';
    }
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
      // 审计 P2-9：`absolute.path` 只做字符串拼接，解析不了 8.3 短名与符号
      // 链接（Windows 上 `resolveSymbolicLinks` 走 GetFinalPathNameByHandle，
      // 会一并还原成长路径）。解析失败（文件不存在/无权限）时退回绝对路径。
      Future<String> normalize(String path) async {
        String resolved;
        try {
          resolved = await File(path).resolveSymbolicLinks();
        } on Object catch (_) {
          resolved = File(path).absolute.path;
        }
        return resolved.replaceAll('\\', '/').toLowerCase();
      }

      final sourceIsBak =
          await normalize(sourcePath) == await normalize('$filePath.bak');
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
      // 审计 A-01/A-02 状态迁移：恢复成功是阻断态下唯一合法的自救路径，
      // 这里必须解除写入阻断、按目录重扫隔离文件、并按恢复后的密钥校正指纹。
      _writesBlocked = false;
      await _scanQuarantineFiles();
      _keyIdVerified = false;
      await _refreshKeyId();
      return null;
    } catch (e) {
      debugPrint('Error restoring from backup: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
      return '恢复失败：无法写入数据文件';
    }
  }
}
