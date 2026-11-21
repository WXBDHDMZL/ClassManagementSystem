/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.1
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'package:crypto/crypto.dart';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart';
import '../models/app_data.dart';
import 'error_log_service.dart';
import 'local_storage_paths.dart';

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

  /// V3.7.x：从旧版文档根目录一次性迁移成功。
  final bool migratedFromLegacyLayout;

  /// V3.7.x：检测到旧版数据但无法读取/迁移；此时必须阻止写空库。
  final bool legacyLayoutUnreadable;

  const DataLoadResult({
    required this.data,
    this.restoredFromBackup = false,
    this.backupRestoreWriteFailed = false,
    this.resetToEmpty = false,
    this.migratedFromLegacyLayout = false,
    this.legacyLayoutUnreadable = false,
  });
}

/// 本地加密存储服务：
/// 数据按 LRX2 格式（随机盐 + HMAC-SHA256 密钥流 + 完整性标签）写入应用文档目录；
/// 每次保存前自动备份上一份到 .bak，主文件损坏时自动从备份恢复。
///
/// **安全边界的诚实说明（2026-10-03 审查 7.4）**：加密密钥内置在程序里
/// （见 [_dataKey]），所以这份"加密"**不构成机密性保证** ——
/// 拿到 exe 的人可以逆出密钥并解开 .enc 文件。它实际挡住的是：
/// 误打开看到明文、随手用文本编辑器改坏文件；LRX2 格式的 HMAC 标签还能
/// 识破"文件被篡改"。本项目真正的隐私边界是**数据只存在本机、不上传服务器**。
class StorageService {
  /// 测试专用：损坏文件隔离（rename）故障注入（B-20）。
  ///
  /// 默认走 `File.rename`；测试可注入一个始终抛错的实现，验证
  /// “隔离失败 → 保存被拒、主文件不被覆盖”的分支（此前无法稳定复现）。
  @visibleForTesting
  static Future<void> Function(File source, String target)? debugIsolateOverride;

  /// 应用内置数据密钥（本地单机程序，无需用户口令即可自动读写）。
  ///
  /// 以两份分量异或的形式保存，避免在源码和发行产物中留下可直接检索的
  /// 个人标识（单一编码可被一次异或还原）；仅用于兼容既有 LRX2 数据，
  /// 不改变加密强度。
  static const List<int> _keyShareA = <int>[
    78, 7, 122, 180, 197, 184, 170, 213, 155, 42,
    91, 46, 179, 180, 200, 205, 116, 161, 50, 236,
    243, 190, 25, 225, 12, 62, 133, 175, 48, 39,
    21, 140, 235, 127, 41, 223, 132, 212,
  ];
  static const List<int> _keyShareB = <int>[
    13, 107, 27, 199, 182, 245, 205, 161, 200, 83,
    40, 113, 129, 132, 250, 251, 43, 237, 71, 131,
    161, 203, 112, 153, 101, 97, 214, 202, 83, 85,
    112, 248, 160, 26, 80, 254, 196, 247,
  ];
  static final String _dataKey = String.fromCharCodes(
    List<int>.generate(
      _keyShareA.length,
      (i) => _keyShareA[i] ^ _keyShareB[i],
    ),
  );

  // ---------------- 新版格式（LRX2）：每文件加盐 + 完整性校验 ----------------
  // 结构：魔数(4) + 盐(16) + 随机数(16) + 密文(N) + HMAC 标签(32)
  // 流加密：HMAC-SHA256(加密密钥, 盐|随机数|计数器) 作为密钥流（计数器从 0 递增）。
  // 完整性：HMAC-SHA256(校验密钥, 头部+密文)，解码前先校验，损坏/被篡改直接判为不可用。
  static const List<int> _magicV2 = [0x4C, 0x52, 0x58, 0x32]; // "LRX2"
  static const int _saltLength = 16;
  static const int _nonceLength = 16;
  static const int _tagLength = 32;
  static const int _blockSize = 32;

  static Uint8List _deriveKey(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  /// 由"盐 + 随机数"派生出本次文件的两把子密钥（加密 / 校验）。
  static (Uint8List, Uint8List) _deriveSubKeys(Uint8List salt) {
    final master = _deriveKey('$_dataKey|${base64Encode(salt)}');
    final encKey = Uint8List.fromList(
      Hmac(sha256, master).convert(utf8.encode('enc')).bytes,
    );
    final macKey = Uint8List.fromList(
      Hmac(sha256, master).convert(utf8.encode('mac')).bytes,
    );
    return (encKey, macKey);
  }

  /// 密钥流：HMAC-SHA256(encKey, salt|nonce|counter)，逐块产生。
  static Uint8List _keystream(
    Uint8List encKey,
    Uint8List salt,
    Uint8List nonce,
    int length,
  ) {
    final result = Uint8List(length);
    final prefix = Uint8List.fromList([...salt, ...nonce]);
    var offset = 0;
    var counter = 0;
    while (offset < length) {
      final block = Hmac(sha256, encKey)
          .convert([...prefix, ..._uint32(counter)])
          .bytes;
      for (var i = 0; i < _blockSize && offset < length; i++, offset++) {
        result[offset] = block[i];
      }
      counter++;
    }
    return result;
  }

  static List<int> _uint32(int value) => [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  static String _encodeData(String plainText) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => random.nextInt(256)),
    );
    final (encKey, macKey) = _deriveSubKeys(salt);
    final data = Uint8List.fromList(utf8.encode(plainText));
    final stream = _keystream(encKey, salt, nonce, data.length);
    final cipher = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      cipher[i] = data[i] ^ stream[i];
    }
    final body = Uint8List.fromList([..._magicV2, ...salt, ...nonce, ...cipher]);
    final tag = Hmac(sha256, macKey).convert(body).bytes;
    return base64Encode([...body, ...tag]);
  }

  static String? _decodeData(String encodedText) {
    try {
      final bytes = base64Decode(encodedText);
      if (bytes.length >= 4 && _startsWith(bytes, _magicV2)) {
        if (bytes.length < 4 + _saltLength + _nonceLength + _tagLength) {
          return null;
        }
        final body = bytes.sublist(0, bytes.length - _tagLength);
        final tag = bytes.sublist(bytes.length - _tagLength);
        final salt = Uint8List.fromList(
          bytes.sublist(4, 4 + _saltLength),
        );
        final nonce = Uint8List.fromList(
          bytes.sublist(4 + _saltLength, 4 + _saltLength + _nonceLength),
        );
        final cipher = bytes.sublist(4 + _saltLength + _nonceLength,
            bytes.length - _tagLength);
        final (encKey, macKey) = _deriveSubKeys(salt);
        // 先校验完整性：损坏或被改动的文件直接判为不可用（走 .bak 恢复）。
        final expected = Hmac(sha256, macKey).convert(body).bytes;
        if (!_constantTimeEquals(expected, tag)) return null;
        final stream = _keystream(encKey, salt, nonce, cipher.length);
        final plain = Uint8List(cipher.length);
        for (var i = 0; i < cipher.length; i++) {
          plain[i] = cipher[i] ^ stream[i];
        }
        return utf8.decode(plain);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static bool _startsWith(List<int> bytes, List<int> magic) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// 定长比较，避免时序差异。
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// 通用本地文本加密（日志/锁定状态）。
  ///
  /// 把任意本地文本编码为与主数据文件相同的 LRX2 密文。
  static String encodeLocalText(String plainText) => _encodeData(plainText);

  /// 解码 [encodeLocalText] 生成的文本；不是密文/已损坏返回 null。
  static String? decodeLocalText(String encodedText) =>
      _decodeData(encodedText.trim());

  /// 是否是本程序写出的 LRX2 密文（用于识别加密文本文件）。
  static bool looksLikeEncryptedText(String text) {
    try {
      final bytes = base64Decode(text.trim());
      return bytes.length >= _magicV2.length && _startsWith(bytes, _magicV2);
    } on FormatException catch (_) {
      return false;
    }
  }

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
    final filePath = await dataFilePath;
    final loaded = await _tryLoadFile(filePath);
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
    final backup = await _tryLoadFile('$filePath.bak');
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
    // V3.7.x：新目录完全无数据时，检查一次旧版文档根目录，避免升级后
    // 直接显示空库、首次保存再生成一份新的空库。
    if (!fileExisted) {
      final migrated = await _migrateLegacyLayoutIfAvailable(filePath);
      if (migrated != null) return migrated;
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
        appendErrorLog('storage_service', e, StackTrace.current,
            context: '损坏主文件隔离失败，已阻止自动覆盖');
      }
    }
    // 文件存在但解析失败、且无可用备份，视为数据重置；完全不存在则是首次启动。
    return DataLoadResult(
      data: AppData.empty(),
      resetToEmpty: fileExisted,
    );
  }

  /// V3.7.x：把旧版文档根目录的数据一次性复制到新目录。
  ///
  /// 只在“新主文件/新备份都不存在”时调用；旧文件保留，不做删除。
  Future<DataLoadResult?> _migrateLegacyLayoutIfAvailable(String newPath) async {
    final legacyFile = await LocalStoragePaths.legacyDataFile();
    final legacyBackup = await LocalStoragePaths.legacyBackupFile();
    final mainExists = await legacyFile.exists();
    final backupExists = await legacyBackup.exists();
    if (!mainExists && !backupExists) return null;

    AppData? legacyLoaded;
    String? sourcePath;
    if (mainExists) {
      legacyLoaded = await _tryLoadFile(legacyFile.path);
      if (legacyLoaded != null) sourcePath = legacyFile.path;
    }
    // 主文件缺失或损坏时，旧版加载逻辑本来会回退 .bak；迁移也照此处理，
    // 否则“只剩旧备份”的机器仍会显示空库。
    if (legacyLoaded == null && backupExists) {
      legacyLoaded = await _tryLoadFile(legacyBackup.path);
      if (legacyLoaded != null) sourcePath = legacyBackup.path;
    }
    if (legacyLoaded == null || sourcePath == null) {
      _mainFileParsable = false;
      appendErrorLog(
        'storage_service',
        '文档目录数据无法读取，已阻止生成新空库',
        null,
        context: legacyFile.path,
      );
      return DataLoadResult(
        data: AppData.empty(),
        legacyLayoutUnreadable: true,
      );
    }

    try {
      await LocalStoragePaths.ensureRoot();
      final content = await File(sourcePath).readAsString();
      await AtomicFile.writeString(newPath, content);
    } catch (e) {
      _mainFileParsable = false;
      appendErrorLog('storage_service', e, StackTrace.current,
          context: '文档目录数据转移失败，已阻止生成新空库');
      return DataLoadResult(
        data: AppData.empty(),
        legacyLayoutUnreadable: true,
      );
    }

    // 主数据已经迁移成功；旧备份只是锦上添花，失败不能反过来判定迁移失败。
    try {
      if (backupExists && await _tryLoadFile(legacyBackup.path) != null) {
        await AtomicFile.writeString(
          '$newPath.bak',
          await legacyBackup.readAsString(),
        );
      }
    } catch (e) {
      debugPrint('备份复制失败（不影响主数据）：$e');
      appendErrorLog('storage_service', e, StackTrace.current,
          context: '备份复制失败，主数据已转移');
    }

    _mainFileParsable = true;
    try {
      _lastWrittenLength = await File(newPath).length();
    } catch (_) {
      _lastWrittenLength = -1;
    }
    _lastWrittenDigest = await _digestOfFile(newPath);
    return DataLoadResult(
      data: legacyLoaded,
      migratedFromLegacyLayout: true,
    );
  }

  /// 读取并解析数据文件；文件不存在、解密失败或内容损坏时返回 null。
  Future<AppData?> _tryLoadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final decrypted = _decodeData(content);
      if (decrypted == null) return null;
      final json = jsonDecode(decrypted) as Map<String, dynamic>;
      return AppData.fromJson(json);
    } catch (e) {
      debugPrint('Error loading $path: $e');
      appendErrorLog('storage_service', e, StackTrace.current);
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
  Future<bool> backupTo(String targetPath) async {
    try {
      final filePath = await dataFilePath;
      final file = File(filePath);
      if (!await file.exists()) return false;
      final target = File(targetPath);
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
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

  /// 从备份文件恢复数据。
  /// 依次逐层校验：Base64 → 魔数（LRX2）→ 解密与完整性校验 → JSON → AppData，
  /// **全部校验通过后**才把当前数据另存为 .bak 并用备份覆盖主文件，
  /// 保证校验失败时绝不改动现有数据。
  /// 成功返回 null；失败返回中文错误原因。
  Future<String?> restoreFrom(String sourcePath) async {
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

    // 第一层：Base64 解码 + 魔数校验，确认是本系统生成的数据文件。
    Uint8List bytes;
    try {
      bytes = base64Decode(content);
    } catch (e) {
      return '文件格式不正确';
    }
    if (bytes.length < 4 || !_startsWith(bytes, _magicV2)) {
      return '文件格式不正确';
    }
    // 第二层：解密 + 完整性校验（LRX2 先验 HMAC 再解密）。
    final decrypted = _decodeData(content);
    if (decrypted == null) return '数据文件已损坏';
    // 第三层：JSON 解析与数据结构解析。
    try {
      final json = jsonDecode(decrypted);
      if (json is! Map<String, dynamic>) return '数据文件已损坏';
      AppData.fromJson(json);
    } catch (e) {
      return '数据文件已损坏';
    }

    // 校验全部通过，执行覆盖（先保留当前数据为 .bak）。
    try {
      final filePath = await dataFilePath;
      final mainFile = File(filePath);
      // 正在恢复的源就是 .bak 时，不能先用当前主文件覆盖它——否则写主文件
      // 一旦失败，用户选中的那份备份已经被毁掉。
      final sourceIsBak = sourcePath == '$filePath.bak';
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
        (_) => AtomicFile.writeString(filePath, content),
      );
      _saveChain = restore.then((_) {}, onError: (_) {});
      await restore;
      // 恢复写入后同步缓存，避免下一次保存把新内容误判为“外部篡改”。
      _mainFileParsable = true;
      _lastWrittenDigest = _digestOfText(content);
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