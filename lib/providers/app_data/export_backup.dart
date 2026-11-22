/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V5.0.0
 * 创建日期 (Created): 2026-07-25
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */
part of '../app_data_provider.dart';

/// AppDataProvider——备份域（备份目录/轮换/执行/恢复、写盘队列冲刷、导出前缀）。
///
/// `_ProviderBase` 的一个功能域（mixin 方法就是真正的类成员，
/// 可跨域调用、触发 notifyListeners；on 同 library 基类，其
/// 私有成员在此直接可见）。
mixin _ExportBackupDomain on _ProviderBase {
  /// 保存自动备份频率。
  void setBackupFrequency(BackupFrequency frequency) {
    _appData.settings = _appData.settings.copyWith(backupFrequency: frequency);
    _log('备份设置', '自动备份频率改为 $frequency');
    _save();
  }

  /// 保存自动备份保留份数（3-50）。
  void setBackupKeepCount(int count) {
    final value = count.clamp(
      AppSettings.minBackupKeepCount,
      AppSettings.maxBackupKeepCount,
    );
    _appData.settings = _appData.settings.copyWith(backupKeepCount: value);
    _log('备份设置', '自动备份保留 $value 份');
    _save();
  }

  /// 给导出文件名加前缀（设置里可配置，如"五年3班_"）。
  String withExportPrefix(String fileName) => '${_exportPrefix()}$fileName';

  /// 等待已排队的写盘任务全部完成（退出程序前调用，确保最后一次修改不丢失）。
  Future<void> flushPendingSaves() => _pendingSave;

  /// 立即保存并等待写盘完成（B-10）。
  ///
  /// 返回是否成功；UI 在“成功提示”前必须 await 它，避免落盘失败仍显示成功。
  @override
  Future<bool> saveNow() async {
    if (_isLoading) return false;
    // 审计 P2-5：批次挂起期间 _save() 只会置 _savePending，真正写盘要等
    // 批次结束才入队；此时 await 旧链尾会"假成功"。返回 false 让调用方
    // 明确知道当前不能保证已落盘（现有调用点都不在批次内，属防御）。
    if (_suspendSaveDepth > 0) return false;
    _save();
    await _pendingSave;
    return !_lastSaveFailed;
  }

  /// 备份目录：用户设置的备份路径；未设置时为 `文档/班级管理系统/备份`。
  Future<String> backupDirectory() async {
    final custom = _appData.settings.backupPath;
    if (custom.isNotEmpty) return custom;
    final directory = await LocalStoragePaths.backupDirectory();
    return directory.path;
  }

  /// 备份文件名：带日期与秒，多次备份不会互相覆盖。
  String buildBackupFileName(DateTime now) {
    return '${AppDataProvider.backupFilePrefix}_'
        '${now.year}${twoDigit(now.month)}${twoDigit(now.day)}_'
        '${twoDigit(now.hour)}${twoDigit(now.minute)}${twoDigit(now.second)}.enc';
  }

  /// 执行一次备份：每次生成一份带时间的备份文件，并自动保留最近 [AppDataProvider.backupKeepCount] 份。
  /// 失败同样会写进操作日志，避免"以为备份了、其实没备份"。
  Future<BackupResult> performBackup({String? password}) async {
    String targetPath = '';
    try {
      final directory = await backupDirectory();
      final targetDir = Directory(directory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      // 同一秒内连续备份（如“操作前自动备份”紧接手动备份）会生成同名文件并
      // 互相覆盖；按秒顺延到第一个不存在的名字，保持时间戳格式不变。
      var stamp = AppClock.now();
      targetPath = '$directory/${buildBackupFileName(stamp)}';
      while (await File(targetPath).exists()) {
        stamp = stamp.add(const Duration(seconds: 1));
        targetPath = '$directory/${buildBackupFileName(stamp)}';
      }
      // 先等排队的写盘任务完成，再落盘，避免与其它保存并发写同一个文件。
      await flushPendingSaves();
      final saved = await _storageService.saveData(_appData);
      if (!saved) {
        _log('备份失败', '数据写入失败');
        return const BackupResult.failure('备份失败：数据写入失败');
      }
      final ok = await _storageService.backupTo(targetPath, password: password);
      if (!ok) {
        _log('备份失败', '无法写入备份位置：$targetPath');
        return const BackupResult.failure('备份失败：无法写入备份位置');
      }
      // 日志快照与数据备份同名同时间戳；失败不影响数据备份本身。
      // 先等日志写队列落盘，否则快照可能缺少备份前刚产生的最后几条。
      await OperationLogService.flush();
      await flushErrorLogs();
      await _copyLogSnapshot(targetPath);
      _appData.settings = _appData.settings.copyWith(
        backupLastAt: _getTodayString(),
      );
      _log('备份', targetPath);
      await _pruneBackups(directory);
      _save();
      return BackupResult.success(targetPath);
    } catch (e) {
      _log('备份失败', '$e');
      return BackupResult.failure('备份失败：$e');
    }
  }

  /// 把当前日志复制为备份旁的 `.logs` 快照。
  ///
  /// 日志是次要数据，快照失败只记录错误，不影响数据备份。
  Future<void> _copyLogSnapshot(String backupPath) async {
    try {
      // 从主数据文件所在目录推导日志目录，避免再次走 path_provider。
      final dataPath = await _storageService.dataFilePath;
      final logFile = File(
        '${File(dataPath).parent.path}${Platform.pathSeparator}'
        '${LocalStoragePaths.logFolderName}${Platform.pathSeparator}'
        '${LogFileService.fileName}',
      );
      // 日志文件尚不存在时跳过快照：不要为了“凑一份”而在真实日志目录
      // 创建空文件，也不生成 0 字节的假日志快照。
      if (!await logFile.exists()) return;
      await AtomicFile.copyAtomic(logFile.path, '$backupPath.logs');
    } on Object catch (e) {
      appendErrorLog('app_data_provider', '备份日志快照失败 $e', StackTrace.current);
    }
  }

  /// 把备份旁的日志快照合并进当前日志。
  ///
  /// 返回 null 表示成功，否则返回错误说明。只补充缺的条目，不删除现有日志。
  Future<String?> restoreLogsFromSnapshot(String backupPath) async {
    try {
      final snapshot = File('$backupPath.logs');
      if (!await snapshot.exists()) return '该备份没有日志快照';
      await OperationLogService.flush();
      await flushErrorLogs();
      final added = await LogFileService.mergeSnapshot(snapshot);
      _log('恢复日志', '${backupPath.split(RegExp(r'[/\\]')).last} · 新增 $added 条');
      return null;
    } on Object catch (e) {
      appendErrorLog('app_data_provider', '恢复日志失败 $e', StackTrace.current);
      return '日志合并失败：$e';
    }
  }

  /// 是否为“从备份恢复”列表中的备份文件。
  ///
  /// 清理与列表必须用**同一个判定**：列表里能选中的备份，清理时就必须能删掉，
  /// 否则恢复出厂勾选“同时清除全部备份”后仍能一键恢复出完整旧数据。
  static bool _isBackupFile(String name) =>
      name.endsWith('.enc') && !name.endsWith('.enc.bak');

  /// 删除备份目录中的全部备份文件（恢复出厂“同时清除全部备份”用）。
  ///
  /// 覆盖范围与 `listBackupFiles` 一致（含手动改名的备份），
  /// 并连带删除对应的 `.logs` 日志快照；不碰目录中的其它文件。返回删除份数。
  Future<int> clearAllBackups() async {
    var removed = 0;
    try {
      final directory = await backupDirectory();
      final dir = Directory(directory);
      if (!await dir.exists()) return 0;
      // 审计 P1-4：备份路径可以被用户改成数据目录、文档根目录或桌面 ——
      // 这些目录里还有本程序的主数据文件与其它软件的 *.enc。只要目标目录
      // 是数据目录本身或其上级，就只清理带本程序备份前缀的文件，绝不把
      // 主数据文件（及 .bak）或陌生 .enc 当备份删掉。
      final dataPath = await _storageService.dataFilePath;
      final dataDir = File(dataPath).parent.path;
      final normalizedDir = directory.replaceAll('\\', '/').toLowerCase();
      final normalizedDataDir = dataDir.replaceAll('\\', '/').toLowerCase();
      final inDataArea =
          normalizedDir == normalizedDataDir ||
          normalizedDataDir.startsWith('$normalizedDir/');
      final mainName = dataPath.split(RegExp(r'[/\\]')).last;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(RegExp(r'[/\\]')).last;
        if (name == mainName || name == '$mainName.bak') continue;
        final isBackup =
            _isBackupFile(name) &&
            (!inDataArea ||
                name.startsWith('${AppDataProvider.backupFilePrefix}_') ||
                name == '${AppDataProvider.backupFilePrefix}.enc');
        final isLogSnapshot = name.endsWith('.enc.logs');
        final isPortableKey = name.endsWith('.enc.pkey');
        if (!isBackup && !isLogSnapshot && !isPortableKey) continue;
        final isOurSidecar =
            name.startsWith('${AppDataProvider.backupFilePrefix}_') ||
            name == '${AppDataProvider.backupFilePrefix}.enc.pkey' ||
            name == '${AppDataProvider.backupFilePrefix}.enc.logs';
        if ((isLogSnapshot || isPortableKey) && inDataArea && !isOurSidecar) {
          continue;
        }
        try {
          await entity.delete();
          if (isBackup) removed++;
        } on Object catch (e) {
          appendErrorLog('app_data_provider', '删除备份失败 $e', StackTrace.current);
        }
      }
      if (removed > 0) {
        _appData.settings = _appData.settings.copyWith(backupLastAt: '');
        _log('清理备份', '删除全部备份 $removed 份');
        _save();
      }
    } on Object catch (e) {
      debugPrint('清除全部备份失败：$e');
      appendErrorLog('app_data_provider', e, StackTrace.current);
    }
    return removed;
  }

  /// 删除主数据旁的“上一份自动备份” `.bak`（恢复出厂勾选清除备份时用）。
  ///
  /// 正常保存都会先把旧主文件复制成 `.bak`；若不清掉，用户选择“清除全部
  /// 备份”后仍能从列表里一键恢复出完整的旧数据。
  Future<bool> clearDataBackup() async {
    try {
      final filePath = await _storageService.dataFilePath;
      final bak = File('$filePath.bak');
      if (!await bak.exists()) return false;
      await bak.delete();
      _log('清理备份', '删除上一份自动备份 .bak');
      return true;
    } on Object catch (e) {
      appendErrorLog('app_data_provider', e, StackTrace.current);
      return false;
    }
  }

  /// 只保留用户设置的最近 `settings.backupKeepCount` 份自动备份。
  /// 只处理带时间戳的自动备份；旧版固定名备份不会被删，避免误删用户手里已有的那份。
  Future<void> _pruneBackups(String directory) async {
    final keepCount = _appData.settings.backupKeepCount;
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) return;
      // 收集"自动备份"文件：名称形如 班级管理系统_备份_yyyyMMdd_HHmmss.enc。
      // 必须完整匹配时间戳格式才参与清理——手动复制的改名件（如
      // "班级管理系统_备份_我的手动备份.enc"）没有可靠时间戳，混进
      // 字典序排序会干扰"从新到旧"判定，甚至被误删。
      final pattern = RegExp(
        '^${AppDataProvider.backupFilePrefix}_(\\d{8})_(\\d{6})\\.enc',
      );
      final files = <MapEntry<String, File>>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(RegExp(r'[/\\]')).last;
        final m = pattern.firstMatch(name);
        // m.end == name.length 等价于整名匹配（等价于正则结尾锚点）。
        if (m == null || m.end != name.length) continue;
        files.add(MapEntry(name, entity));
      }
      if (files.length <= keepCount) return;
      // 按**文件名**从新到旧排序：名称内含时间戳，字典序即时序。
      // 比按修改时间更确定——文件系统时间精度、复制/同步行为都不会影响结果。
      files.sort((a, b) => b.key.compareTo(a.key));
      for (final entry in files.skip(keepCount)) {
        try {
          await entry.value.delete();
          final snapshot = File('${entry.value.path}.logs');
          if (await snapshot.exists()) await snapshot.delete();
          final portableKey = File('${entry.value.path}.pkey');
          if (await portableKey.exists()) await portableKey.delete();
        } catch (e) {
          // 单个旧文件删不掉不影响本次备份，但留痕便于排查。
          appendErrorLog(
            'app_data_provider',
            '删除过期备份失败 $e',
            StackTrace.current,
          );
        }
      }
    } catch (e) {
      debugPrint('清理过期备份失败：$e');
      appendErrorLog('app_data_provider', e, StackTrace.current);
    }
  }

  /// 最近一次“启动时自动备份”失败的原因；成功/未到期时清空。
  /// 供主界面在启动后提示，避免“以为备份了、其实没备份”（B-09）。
  String? _autoBackupError;
  String? get autoBackupError => _autoBackupError;

  /// 启动时按设置的频率自动备份：仅手动与"每次退出"不在此触发，
  /// 到间隔（每天 / 每 3 天 / 每周）才备份；返回本次备份路径（未备份返回 null）。
  Future<String?> runScheduledBackup() async {
    // 加载阶段已经确认原文件读取异常时，绝不能自动备份空库：
    // 那会把“空库”写进备份文件，连最后的可恢复副本也一起毁掉。
    if (_storageWriteBlocked) return null;
    final settings = _appData.settings;
    final intervalDays = switch (settings.backupFrequency) {
      BackupFrequency.manual || BackupFrequency.onExit => 0,
      BackupFrequency.daily => 1,
      BackupFrequency.everyThreeDays => 3,
      BackupFrequency.weekly => 7,
    };
    if (intervalDays <= 0) return null;
    final last = settings.backupLastAt;
    if (last.isNotEmpty) {
      final lastDate = StatisticsService.parseDate(last);
      if (lastDate != null) {
        final now = AppClock.now();
        // 用 UTC 日期算天数差，避开夏令时/时区调整导致 inDays 少一天。
        final todayUtc = DateTime.utc(now.year, now.month, now.day);
        final lastUtc = DateTime.utc(
          lastDate.year,
          lastDate.month,
          lastDate.day,
        );
        if (todayUtc.difference(lastUtc).inDays < intervalDays) return null;
      }
    }
    final result = await performBackup();
    if (!result.isSuccess) {
      _autoBackupError = result.error ?? '备份失败';
      notifyListeners();
      return null;
    }
    if (_autoBackupError != null) {
      _autoBackupError = null;
      notifyListeners();
    }
    return result.savedPath;
  }

  /// 列出备份目录下的备份文件（按修改时间从新到旧），供"从备份恢复"选择。
  Future<List<BackupFileInfo>> listBackupFiles() async {
    try {
      final directory = await backupDirectory();
      final dir = Directory(directory);
      final files = <BackupFileInfo>[];
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          final name = entity.path.split(RegExp(r'[/\\]')).last;
          if (!name.endsWith('.enc') || name.endsWith('.enc.bak')) continue;
          // V5.0.0：旧版固定名备份不列入可恢复列表（文件保留，不静默删除）。
          if (name == '${AppDataProvider.backupFilePrefix}.enc') continue;
          final stat = await entity.stat();
          files.add(
            BackupFileInfo(
              path: entity.path,
              name: name,
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
              hasLogSnapshot: await File('${entity.path}.logs').exists(),
            ),
          );
        }
      }
      // B-09：主数据文件的 `.bak` 是"上一份自动备份"，恢复出厂后想挽回
      // 只能靠它；此前列表直接排除 `.enc.bak`，UI 实际上选不到。
      try {
        final dataPath = await _storageService.dataFilePath;
        final bak = File('$dataPath.bak');
        if (await bak.exists()) {
          final stat = await bak.stat();
          files.add(
            BackupFileInfo(
              path: bak.path,
              name: '上一份自动备份（.bak）',
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
            ),
          );
        }
      } catch (e) {
        appendErrorLog(
          'app_data_provider',
          e,
          StackTrace.current,
          context: '读取主文件 .bak 信息失败',
        );
      }
      files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      return files;
    } catch (e) {
      debugPrint('读取备份列表失败：$e');
      appendErrorLog('app_data_provider', e, StackTrace.current);
      return const [];
    }
  }

  /// 该备份是否带有便携口令信封（`.pkey`）。
  Future<bool> isPortableBackup(String sourcePath) =>
      _storageService.isPortableBackup(sourcePath);

  /// 从指定备份文件恢复：成功返回 null，否则返回提示文案。
  /// 校验不通过时不会改动现有数据；恢复成功后会重新加载内存数据。
  Future<String?> restoreBackupFrom(
    String sourcePath, {
    String? backupPassword,
  }) async {
    if (!_authorizedFor('data', action: PasswordAction.backupRestore)) {
      return '未授权：请先进入班主任管理';
    }
    try {
      // 修复（审查 P1-1）：**先等排队中的保存落盘，再恢复**。
      // 此前漏了这一步（performBackup 一直有）：若此刻还有一次 _save() 在队列里，
      // 它会在恢复完成**之后**把旧数据写回去，把刚恢复的数据覆盖掉（数据丢失）。
      await flushPendingSaves();
      // 修复（审计 P2-34）：恢复窗口期挂起写盘 —— 否则期间任何 _save()（界面
      // 变更触发）会排在恢复之后把**旧内存**写回，静默覆盖刚恢复的数据。
      // 报告 H9：改用嵌套计数（与 _batch 共用同一机制，可安全嵌套）。
      _suspendSaveDepth++;
      String? error;
      var restored = false;
      try {
        // 校验并覆盖主文件（校验失败不会覆盖）。
        error = await _storageService.restoreFrom(
          sourcePath,
          backupPassword: backupPassword,
        );
        if (error != null) {
          _log('从备份恢复失败', '$sourcePath · $error');
          return error;
        }
        final result = await _storageService.loadData();
        // 恢复写入成功不代表立刻读得回来：磁盘/权限/杀软都可能在此时让
        // loadData 退回空库或再走一次 .bak。此时必须报错，绝不能把空库
        // 当成“恢复成功”继续使用。
        if (result.loadFailed ||
            result.resetToEmpty ||
            result.restoredFromBackup ||
            result.unsupportedFormat ||
            result.keyUnavailable ||
            result.backupRestoreWriteFailed) {
          _log('从备份恢复失败', '$sourcePath · 恢复后数据读取校验失败');
          return '恢复后数据读取校验失败：备份文件已写入，但读取校验未通过，'
              '数据可能已变更；请检查磁盘空间或文件权限，'
              '必要时用主数据旁的 .bak 复核';
        }
        _appData = result.data;
        restored = true;
        // 先套用备份里的自定义时段，保证恢复后的时段解释与备份一致。
        _applySettingsPeriods();
      } finally {
        _suspendSaveDepth--;
        final pending = _savePending;
        _savePending = false;
        // 审计 P1-5/原 P2-4：恢复失败时 _appData 仍是旧内存，窗口期内排队的
        // 写盘请求不能无条件丢弃，否则这些已改内存的数据永不落盘；恢复成功
        // 时旧请求才作废（旧内存已被替换）。
        if (!restored && pending) _save();
      }
      _repairDuplicateIds();
      _lastSaveFailed = false;
      // X-14 修复：恢复后**必须失效派生缓存**（指纹、记录/考勤计数）——
      // 此前只换数据不失效，设置页与统计里的总条数仍显示恢复前的旧值，
      // 直到下一次真正的保存才纠正。
      _invalidateDerivedCaches();
      _log('从备份恢复', sourcePath);
      // 备份里的身份/密码设置可能不同：结束旧管理会话，再重算身份。
      _resetAccessStateAfterDataChange();
      _syncIdentitySession();
      notifyListeners();
      return null;
    } catch (e) {
      return '恢复失败：$e';
    }
  }
}
