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

import 'dart:async';
import 'dart:io';

import '../utils/app_date.dart';
import '../utils/record_text.dart';
import 'package:flutter/foundation.dart';
import '../models/app_data.dart';
import '../models/student_record.dart';
import '../models/app_settings.dart';
import '../models/identity.dart';
import '../models/attendance_record.dart';
import '../models/reason_library.dart';
import '../models/password_policy.dart';
import '../services/app_data_reader.dart';
import '../services/auth_service.dart';
import '../services/operation_log_service.dart';
import '../services/statistics_service.dart';
import '../services/local_storage_paths.dart';
import '../services/storage_service.dart';
import '../services/transfer_service.dart';
import '../constants/time_periods.dart';
import '../constants/attendance_feature.dart';
import '../services/error_log_service.dart';
import '../services/atomic_file.dart';
import '../services/log_file_service.dart';
import '../services/security_service.dart';
import '../utils/app_clock.dart';
import '../utils/today_boundary.dart';

part 'app_data/records.dart';
part 'app_data/settings.dart';
part 'app_data/import_restore.dart';
part 'app_data/attendance.dart';
part 'app_data/export_backup.dart';
part 'app_data/roster.dart';

/// 备份文件信息（供"从备份恢复"列表展示）。
class BackupFileInfo {
  const BackupFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    this.hasLogSnapshot = false,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;

  /// 同时间戳的 `.logs` 日志快照是否存在。
  final bool hasLogSnapshot;
}

/// 备份结果：成功时 [savedPath] 为写入的完整路径，
/// 失败时 [error] 为给用户看的提示文案。
class BackupResult {
  const BackupResult.success(this.savedPath) : error = null;
  const BackupResult.failure(this.error) : savedPath = null;

  final String? savedPath;
  final String? error;

  bool get isSuccess => error == null;
}

/// 某天的考勤统计：未登记的学生视为出勤，因此只有异常记录才落库。
class AttendanceStats {
  const AttendanceStats({
    required this.total,
    required this.abnormalStudents,
    required this.absentStudents,
    required this.recordCount,
    required this.byStatus,
    required this.offRosterCount,
  });

  /// 应到人数（名单内学生数）。
  final int total;

  /// 名单内当天有异常记录的学生数（去重）。
  final int abnormalStudents;

  /// 名单内"算作未到"的学生数（请假/缺勤等，去重）；实到 = 应到 − 它。
  final int absentStudents;

  /// 当天的异常记录条数（同一学生不同时间段可有多条）。
  final int recordCount;

  /// 各异常状态的人次（含名单外学生）。
  final Map<String, int> byStatus;

  /// 名单外学生（已从名单移除但留有考勤）的异常条数。
  final int offRosterCount;

  /// 实到人数 = 应到 − 算作未到的人数（迟到/早退仍算到），不低于 0。
  int get presentCount {
    final value = total - absentStudents;
    return value < 0 ? 0 : value;
  }
}

/// `AppDataProvider` 的基类：持有全部状态字段与跨域基础设施
/// （initialize、写盘队列 `_save`/`_batch`、操作日志 `_log`、数据指纹、
/// 净化工具与时间/ID 小工具），供 6 个域 mixin `on` 它访问。
abstract class _ProviderBase extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  /// 数据文件路径（修复 审查 四-5）：由 provider 统一暴露，
  /// 界面不再自己 `StorageService()` 新建服务（便于测试替身与集中管理）。
  Future<String> get dataFilePath => _storageService.dataFilePath;
  AppData _appData = AppData.empty();
  bool _isLoading = true;

  /// 串行化写盘队列：避免批量追加时并发写同一文件导致损坏。
  Future<void> _pendingSave = Future<void>.value();
  int _idCounter = 0;

  /// 最近一次成功新增记录的撤销快照（运行期，不持久化）。
  _RecordUndo? _lastRecordUndo;

  bool get isLoading => _isLoading;
  AppData get appData => _appData;

  /// 由 `_ExportBackupDomain` 实现；其他设置域在“成功提示”前等待落盘。
  Future<bool> saveNow();

  // -------------------- 操作身份（运行期，不持久化） --------------------

  String? _activeIdentityId;

  /// 身份闲置退出分两段计时：
  /// - 基础计时：从选择身份起固定 N 分钟，期间触摸不会让它重来；
  /// - 最后 1 分钟：进入后每次触摸都把退出时间推到该次触摸之后 1 分钟。
  Timer? _identityBaseTimer;
  Timer? _identityFinalMinuteTimer;
  Timer? _identityGraceTimer;
  bool _identityInFinalMinute = false;

  // -------------------- 班主任管理会话（运行期，不持久化） --------------------
  Timer? _managementTimer;
  bool _identityBaseElapsed = false;

  /// 进入班主任管理前使用的普通操作身份；退出/超时后恢复。
  String? _preManagementIdentityId;

  bool get identityFeatureEnabled => _appData.settings.identityFeatureEnabled;

  /// 当前操作身份；程序启动默认无身份，关闭功能时也为空。
  Identity? get activeIdentity {
    final id = _activeIdentityId;
    if (id == null) return null;
    for (final identity in _appData.settings.identities) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  /// 当前记录人快照（写入记录用）；功能关闭或无身份时为空。
  String get currentRecordedBy =>
      identityFeatureEnabled ? (activeIdentity?.displayLabel ?? '') : '';

  /// 当前记录人身份 ID；身份功能关闭或未选择时为空。
  String get currentIdentityId =>
      identityFeatureEnabled ? (activeIdentity?.id ?? '') : '';

  /// 是否正处于班主任管理会话（内存会话，重启/超时/手动退出即失效）。
  /// 启用操作身份时，必须当前身份是班主任；未启用操作身份时仍可作为独立管理会话。
  bool get isManagementMode {
    if (!AuthService.hasManagementGrant) return false;
    if (!identityFeatureEnabled) return true;
    return activeIdentity?.isHeadTeacher == true;
  }

  /// 安全设置是否允许修改：未启用管理密码时允许首次设置；
  /// 启用后必须处于班主任管理会话，或刚在当前会话中验证过管理密码。
  bool get _canManageSecuritySettings =>
      !_appData.settings.passwordEnabled ||
      isManagementMode ||
      AuthService.hasFreshSecuritySettingsVerification;

  Duration? get managementRemaining => AuthService.managementRemaining;

  /// 认证成功后进入班主任管理：切换到班主任操作身份并开启管理会话。
  void enterManagementMode() {
    if (identityFeatureEnabled && activeIdentity?.isHeadTeacher != true) {
      _preManagementIdentityId = _activeIdentityId;
      final head = _appData.settings.identities
          .where((identity) => identity.isHeadTeacher)
          .firstOrNull;
      if (head != null) {
        _activeIdentityId = head.id;
        _startIdentityIdleCountdown();
      }
    }
    final minutes = _appData.settings.managementSessionMinutes;
    AuthService.grantManagement(Duration(minutes: minutes));
    // 班主任管理期间由管理会话计时，不再叠加身份闲置计时；
    // 否则默认 5 分钟身份闲置会把管理会话提前结束。
    _cancelIdentityTimers();
    _managementTimer?.cancel();
    _managementTimer = Timer(Duration(minutes: minutes), _expireManagementMode);
    _log('安全验证', '进入班主任管理（$minutes 分钟）');
    notifyListeners();
  }

  /// 任意触摸/鼠标操作调用：班主任管理在最后 N 分钟闲置后失效。
  /// 每次操作把到期时间往后推，不主动 notify（避免每次点击都重建界面）。
  void touchManagementActivity() {
    if (!isManagementMode) return;
    final minutes = _appData.settings.managementSessionMinutes;
    AuthService.grantManagement(Duration(minutes: minutes));
    _managementTimer?.cancel();
    _managementTimer = Timer(Duration(minutes: minutes), _expireManagementMode);
  }

  void _expireManagementMode() {
    _managementTimer = null;
    final hadGrant = AuthService.hasManagementGrant;
    _clearManagementAccessState();
    if (hadGrant) _log('安全验证', '班主任管理会话超时');
    _restoreIdentityAfterManagement();
    notifyListeners();
  }

  void exitManagementMode() {
    final hadGrant = AuthService.hasManagementGrant;
    _clearManagementAccessState();
    if (hadGrant) _log('安全验证', '退出班主任管理');
    _restoreIdentityAfterManagement();
    notifyListeners();
  }

  /// 清掉管理会话本身，保留 `_preManagementIdentityId` 供退出时恢复身份。
  void _clearManagementAccessState() {
    _managementTimer?.cancel();
    _managementTimer = null;
    AuthService.clearManagementGrant();
  }

  /// 数据整体替换/恢复后：结束管理会话和当前身份，避免旧会话跨数据生效。
  void _resetAccessStateAfterDataChange({bool restorePrevious = false}) {
    _lastRecordUndo = null;
    _clearManagementAccessState();
    if (restorePrevious) {
      _restoreIdentityAfterManagement();
    } else {
      _preManagementIdentityId = null;
      _activeIdentityId = null;
      _cancelIdentityTimers();
    }
  }

  void _restoreIdentityAfterManagement() {
    final restore = _preManagementIdentityId;
    _preManagementIdentityId = null;
    if (restore != null &&
        identityFeatureEnabled &&
        restore != 'head_teacher' &&
        _appData.settings.identities.any(
          (identity) => identity.id == restore,
        )) {
      _activeIdentityId = restore;
      _startIdentityIdleCountdown();
      return;
    }
    if (activeIdentity?.isHeadTeacher == true) {
      _activeIdentityId = null;
      _cancelIdentityTimers();
    }
  }

  bool get _normalIdentityPermissionActive =>
      identityFeatureEnabled &&
      !isManagementMode &&
      _appData.settings.passwordEnabled;

  /// 当前记录人是否可在普通模式新增记录（班主任管理/密码关闭时放行）。
  bool get canActiveIdentityAddRecord {
    if (!_normalIdentityPermissionActive) return true;
    return activeIdentity?.allowAddRecord ?? false;
  }

  /// 当前记录人是否可在普通模式登记考勤。
  bool get canActiveIdentityRegisterAttendance {
    if (!_normalIdentityPermissionActive) return true;
    return activeIdentity?.allowAttendanceRegister ?? false;
  }

  /// 普通模式下，当前记录人是否有权修改/删除该记录。
  /// 班主任管理、密码功能关闭时直接放行；旧记录没有 owner，只能班主任管理处理。
  bool canMutateRecord(StudentRecord record) {
    if (isManagementMode) return true;
    if (!_appData.settings.passwordEnabled) return true;
    final identity = activeIdentity;
    if (identity == null || !identity.allowSelfEdit) return false;
    if (record.createdByIdentityId.isEmpty ||
        record.createdByIdentityId != identity.id) {
      return false;
    }
    final createdAt = DateTime.tryParse(record.createdAtIso);
    if (createdAt == null) return false;
    final minutes = _appData.settings.selfEditWindowMinutes;
    if (minutes <= 0) return false;
    final age = AppClock.now().difference(createdAt);
    return !age.isNegative && age <= Duration(minutes: minutes);
  }

  /// 自动退出是否对当前身份生效（班主任默认不退出）。
  bool get _identityAutoExitEnabled {
    if (!identityFeatureEnabled) return false;
    final identity = activeIdentity;
    if (identity == null) return false;
    return _appData.settings.identityIdleMinutes > 0;
  }

  void setActiveIdentity(String? identityId) {
    if (!identityFeatureEnabled) {
      _activeIdentityId = null;
      _cancelIdentityTimers();
      return;
    }
    if (identityId != null &&
        !_appData.settings.identities.any((e) => e.id == identityId)) {
      return;
    }
    if (activeIdentity?.isHeadTeacher == true &&
        identityId != 'head_teacher' &&
        AuthService.hasManagementGrant) {
      _managementTimer?.cancel();
      _managementTimer = null;
      AuthService.clearManagementGrant();
      _preManagementIdentityId = null;
    }
    _activeIdentityId = identityId;
    _startIdentityIdleCountdown();
    notifyListeners();
  }

  void clearActiveIdentity() {
    if (_activeIdentityId == null && !AuthService.hasManagementGrant) return;
    // 用户主动退出身份时，管理会话也必须一起结束；否则 grant/timer/pre
    // 会在后台残留，计时器到点还可能把旧身份恢复回来。
    _clearManagementAccessState();
    _preManagementIdentityId = null;
    _activeIdentityId = null;
    _cancelIdentityTimers();
    notifyListeners();
  }

  /// 任意触摸/鼠标活动调用：
  /// 基础时长未满且不在最后一分钟时不影响退出；进入最后一分钟后，
  /// 每次操作都重新开始 1 分钟倒计时。
  void touchIdentityActivity() {
    if (_activeIdentityId == null) return;
    if (!_identityAutoExitEnabled) return;
    if (!_identityBaseElapsed && !_identityInFinalMinute) return;
    _identityGraceTimer?.cancel();
    _identityGraceTimer = Timer(
      const Duration(minutes: 1),
      _expireIdentitySession,
    );
  }

  void _startIdentityIdleCountdown() {
    _cancelIdentityTimers();
    // 班主任管理由 management timer 负责，不再叠加身份闲置计时。
    if (isManagementMode && activeIdentity?.isHeadTeacher == true) return;
    if (!_identityAutoExitEnabled) return;
    final minutes = _appData.settings.identityIdleMinutes;
    if (minutes == 1) {
      _identityInFinalMinute = true;
    } else {
      _identityFinalMinuteTimer = Timer(Duration(minutes: minutes - 1), () {
        _identityFinalMinuteTimer = null;
        _identityInFinalMinute = true;
      });
    }
    _identityBaseTimer = Timer(Duration(minutes: minutes), () {
      _identityBaseTimer = null;
      _identityBaseElapsed = true;
      _identityInFinalMinute = false;
      // 最后一分钟内有触摸：等那次操作后的 1 分钟走完再退出。
      if (_identityGraceTimer != null) return;
      _expireIdentitySession();
    });
  }

  void _expireIdentitySession() {
    final hadIdentity = _activeIdentityId != null;
    final wasHead = activeIdentity?.isHeadTeacher == true;
    _cancelIdentityTimers();
    _activeIdentityId = null;
    if (wasHead) {
      _managementTimer?.cancel();
      _managementTimer = null;
      AuthService.clearManagementGrant();
      _preManagementIdentityId = null;
    }
    if (hadIdentity) notifyListeners();
  }

  void _cancelIdentityTimers() {
    _identityBaseTimer?.cancel();
    _identityFinalMinuteTimer?.cancel();
    _identityGraceTimer?.cancel();
    _identityBaseTimer = null;
    _identityFinalMinuteTimer = null;
    _identityGraceTimer = null;
    _identityInFinalMinute = false;
    _identityBaseElapsed = false;
  }

  /// 设置变化后同步会话：功能关闭、身份被删、密码被关闭或身份列表更新时立即生效。
  void _syncIdentitySession() {
    if (!identityFeatureEnabled) {
      _activeIdentityId = null;
      _clearManagementAccessState();
      _preManagementIdentityId = null;
    } else {
      final identity = activeIdentity;
      if (identity == null ||
          (identity.isHeadTeacher && !_appData.settings.passwordEnabled)) {
        _activeIdentityId = null;
        _clearManagementAccessState();
        _preManagementIdentityId = null;
      }
    }
    // 班主任管理期间只由管理计时器负责；普通身份才启动闲置计时。
    // 否则任何设置变化都会意外重建身份闲置计时，提前结束管理。
    if (isManagementMode && activeIdentity?.isHeadTeacher == true) {
      _cancelIdentityTimers();
    } else {
      _startIdentityIdleCountdown();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelIdentityTimers();
    _clearManagementAccessState();
    _preManagementIdentityId = null;
    super.dispose();
  }

  /// 是否已释放。
  ///
  /// 写盘是异步链：用例/界面在保存真正落盘前就 `dispose()` 是常态，随后
  /// 队列里的任务仍会走到 `notifyListeners()`。`ChangeNotifier` 在 debug 下
  /// 会直接断言失败（`used after being disposed`），在生产里则是无意义的重建。
  /// 统一在这里吞掉，比在十几处调用点各加判断更可靠。
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// 测试专用：直接装入一份数据并跑一遍启动期修复（id 重复修复等），
  /// 用于复现"旧数据加载后被改写"这类只有启动路径才会发生的问题。
  /// **不写盘**，避免测试触碰真实数据文件。
  @visibleForTesting
  void loadForTest(AppData data) {
    _appData = data;
    _lastRecordUndo = null;
    // 同 initialize：替换数据后派生缓存必须失效（M5 自查补强）。
    _invalidateDerivedCaches();
    _isLoading = false;
    // 先套用自定义时段，再修复重复 ID。
    _applySettingsPeriods();
    _repairDuplicateIds();
  }

  /// 让 settings 里的自定义时段生效；空列表表示出厂时段。
  void _applySettingsPeriods() {
    applyCustomPeriods(_appData.settings.periods);
  }

  /// 最近一次保存是否失败（供 UI 提示用户，避免数据静默丢失）。
  bool _lastSaveFailed = false;
  bool get saveFailed => _lastSaveFailed;

  /// 启动时数据异常提示（备份恢复/重置情况）。
  String? _startupNotice;
  bool _startupNoticeIsError = false;

  /// 存储层读取失败后为 true：除拒绝写入外，也跳过启动自动备份。
  bool _storageWriteBlocked = false;
  String? get startupNotice => _startupNotice;
  bool get startupNoticeIsError => _startupNoticeIsError;

  Future<void> initialize() async {
    try {
      final result = await _storageService.loadData();
      // 数据目录读取失败时优先让上面的 loadData 进入 loadFailed 分支；
      // 锁定状态读取本身是尽力而为，不能抢占“暂停保存”的提示。
      await AuthService.ensureLoaded();
      _appData = result.data;
      _lastRecordUndo = null;
      if (result.loadFailed) {
        _storageWriteBlocked = true;
        _startupNotice =
            '数据读取失败，已暂停保存以保护原文件。'
            '请检查文件权限或同步盘状态后重启程序。';
        _startupNoticeIsError = true;
      } else if (result.unsupportedFormat) {
        _storageWriteBlocked = true;
        _startupNotice =
            '检测到 5.0 不支持的数据格式，已暂停保存。'
            '请使用创建这份数据的版本打开，或联系维护者。';
        _startupNoticeIsError = true;
      } else if (result.keyUnavailable) {
        _storageWriteBlocked = true;
        _startupNotice =
            '数据密钥丢失或无法由当前 Windows 用户解密，已暂停保存。'
            '请使用原 Windows 用户/原电脑打开，或用备份恢复；不要删除数据文件。';
        _startupNoticeIsError = true;
      } else if (result.backupRestoreWriteFailed) {
        _storageWriteBlocked = true;
        _startupNotice =
            '数据文件损坏，备份可读取但写回失败；'
            '为避免覆盖，已暂停保存。请保留原文件并联系维护者。';
        _startupNoticeIsError = true;
      } else if (result.restoredFromBackup) {
        _startupNotice = '数据文件损坏，已自动从备份恢复';
        _startupNoticeIsError = false;
      } else if (result.resetToEmpty) {
        _startupNotice = '数据文件损坏且无可用备份，现有数据已重置';
        _startupNoticeIsError = true;
      }
      if (AuthService.legacyStateUnsupported && _startupNotice == null) {
        _startupNotice =
            '检测到无法识别的密码锁定记录，已备份为 .lrx2_legacy；'
            '失败次数和锁定时间已失效，请重新设置管理密码。';
        _startupNoticeIsError = false;
      }
    } catch (e, s) {
      // 数据加载失败绝不能静默：用户看到"数据已重置"时，错误日志里
      // 必须能找到根因（解密失败？文件损坏？磁盘问题？）。
      _appData = AppData.empty();
      _lastRecordUndo = null;
      _storageWriteBlocked = true;
      _storageService.blockWrites('启动加载数据异常，已暂停保存');
      _startupNotice =
          '数据读取失败，已暂停保存以保护原文件。'
          '请检查文件权限或同步盘状态后重启程序。';
      _startupNoticeIsError = true;
      appendErrorLog(
        'app_data_provider',
        e,
        s,
        context: '启动加载数据：读取异常，已暂停保存（原文件未改动）',
      );
    }
    // 先套用自定义时段，再做数据完整性修复。
    _applySettingsPeriods();
    // 修复历史数据中可能存在的重复记录 ID，避免编辑/删除误伤其他记录。
    _repairDuplicateIds();
    // 性能批 M5 自查补强：initialize 会整体替换 `_appData`（正常启动时界面
    // 尚未创建、缓存为空；但若未来出现"二次 initialize"等路径，缓存必须失效，
    // 否则派生数据会停留在替换前）。与其余替换点（_save / 恢复 / 重置）同口径。
    _invalidateDerivedCaches();
    _isLoading = false;
    notifyListeners();
  }

  /// 记录在"搬运既有数据"时的归属日期（R-1）：
  /// 优先用记录自身 date，为空时退回它所在的**桶键**。
  ///
  /// **绝不能**退回 [_getTodayString]——那会把历史记录的日期静默改写成今天
  /// （旧数据的 `date` 字段本就为空，一旦重建就"被穿越到今天"，
  /// 导出日期错、且该记录在今天的桶里查不到从而编辑/删除失效）。
  String _recordRelativeDate(StudentRecord record, String bucketDate) =>
      (record.date == null || record.date!.isEmpty) ? bucketDate : record.date!;

  /// 旧版本批量追加在同一毫秒内会生成相同 ID。
  /// 启动时为重复 ID 的后续记录重新分配唯一 ID 并落盘（记录与考勤一并修复）。
  void _repairDuplicateIds() {
    final seen = <String>{};
    var changed = false;
    // P2-8 修复：记录 ID 变更时同步记录映射表，考勤的 syncedRecordId 一并回写，
    // 避免"删除同步记录不撤销考勤"的悬空链接。
    final idRemap = <String, String>{};
    for (final date in _appData.recordsByDate.keys.toList()) {
      final records = _appData.recordsByDate[date]!;
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        var id = record.id;
        while (id.isEmpty || !seen.add(id)) {
          id = _generateId();
          changed = true;
        }
        if (id != record.id) {
          idRemap[record.id] = id;
          // N-2：id 修复也走唯一入口，保证全程序只有一份记录构造实现。
          records[i] = _buildRecord(
            id: id,
            studentName: record.studentName,
            operationType: record.operationType,
            reasons: record.reasons.split('、'),
            periodKey: record.periodKey,
            remark: record.remark,
            // R-1：兜底用**外层桶键**（记录真正的归属日期），绝不能退回"今天"——
            // 那会把历史记录的日期静默改写成当前日期。
            // 主防线在 AppData.fromJson：加载时已用桶键回填 date，正常情况下
            // 这里 record.date 不会是空；此处的桶键兜底保证"即便有漏网"也不写错。
            date: _recordRelativeDate(record, date),
            timestamp: record.timestamp,
            isAppended: record.isAppended,
            isImported: record.isImported,
            isBatch: record.isBatch,
            // id 修复是"搬运既有数据"，原始时段标签与空键都要原样保留。
            periodNameOverride: record.periodName,
            normalizePeriodKey: false,
            recordedBy: record.recordedBy,
            createdByIdentityId: record.createdByIdentityId,
            createdAtIso: record.createdAtIso,
          );
        }
      }
    }
    if (idRemap.isNotEmpty) {
      for (final date in _appData.attendanceByDate.keys.toList()) {
        final records = _appData.attendanceByDate[date]!;
        for (var i = 0; i < records.length; i++) {
          final linked = records[i].syncedRecordId;
          final mapped = idRemap[linked];
          if (linked.isNotEmpty && mapped != null) {
            // 保留时间段等字段，仅回写同步关联指向的新记录 ID。
            records[i] = records[i].copyWith(syncedRecordId: mapped);
            changed = true;
          }
        }
      }
    }
    for (final date in _appData.attendanceByDate.keys.toList()) {
      final records = _appData.attendanceByDate[date]!;
      for (var i = 0; i < records.length; i++) {
        final record = records[i];
        var id = record.id;
        while (id.isEmpty || !seen.add(id)) {
          id = _generateId();
          changed = true;
        }
        if (id != record.id) {
          // 保留时间段与同步关联，避免修复动作本身损坏数据。
          records[i] = record.copyWith(id: id);
        }
      }
    }
    if (changed) {
      _save();
    }
  }

  /// 记录一条操作日志（不阻塞主流程）；启用操作身份时自动带记录人。
  void _log(String action, [String detail = '']) {
    final identity = identityFeatureEnabled ? activeIdentity : null;
    final prefix = identity == null ? '' : '【${identity.displayLabel}】 ';
    OperationLogService.log(action, '$prefix$detail');
  }

  /// 批量变更期间挂起逐条写盘的**嵌套深度**（报告 H9：此前是 bool，内层
  /// _batch 结束会提前解除外层挂起；改为计数后可安全嵌套，整批只落盘一次）。
  int _suspendSaveDepth = 0;
  bool _savePending = false;

  /// 在批量变更中执行 [action]，结束后只落盘一次（可嵌套）。
  void _batch(void Function() action) {
    _suspendSaveDepth++;
    try {
      action();
    } finally {
      _suspendSaveDepth--;
      if (_suspendSaveDepth == 0 && _savePending) {
        _savePending = false;
        _save();
      }
    }
  }

  /// provider 层写操作门禁：对应密码开关开启时，必须有一次成功验证
  /// （5 分钟会话授权）或处于内部派生写入（考勤同步）中。
  ///
  /// 说明：这不是操作系统级安全边界（本地进程仍可改数据文件），但它保证
  /// 绕过 UI 直接调用 provider 的写路径不会静默成功，属于纵深防御。
  int _internalWriteDepth = 0;

  /// 已授权复合流程的嵌套深度：进入时只校验一次动作，内部的子写入
  /// （名单/记录/考勤/时段等）不再重复弹门禁。必须在 UI 完成密码验证后使用。
  int _authorizedActionDepth = 0;

  /// 公开给 UI：该动作是否需要班主任管理（V3 固定规则）。
  bool actionRequiresManagement(PasswordAction action) =>
      _appData.settings.passwordEnabled && !_normalModeActions.contains(action);

  /// 普通模式允许、不需要班主任管理的动作。其余写动作一律需要班主任管理。
  static const Set<PasswordAction> _normalModeActions = {
    PasswordAction.recordAddSingle,
    PasswordAction.recordAddBatch,
    PasswordAction.recordAppend,
    PasswordAction.attendanceRegister,
  };

  /// 数据层写门禁：V3.0.0 固定为新权限模型。
  /// - 密码功能关闭：放行；
  /// - 班主任管理有效：放行；
  /// - 普通模式动作（新增/追加/考勤登记）：放行，身份权限在各自路径判断；
  /// - 其余敏感动作：必须有班主任管理。
  bool _authorizedFor(String area, {PasswordAction? action}) {
    if (_internalWriteDepth > 0 || _authorizedActionDepth > 0) return true;
    if (!_appData.settings.passwordEnabled) return true;
    if (isManagementMode) return true;
    if (action != null && _normalModeActions.contains(action)) return true;
    final label = action?.name ?? area;
    OperationLogService.log('安全验证', '拒绝未授权的 $label 写操作（provider 门禁）');
    return false;
  }

  bool _actionRequired(PasswordAction action) =>
      _appData.settings.passwordEnabled && !_normalModeActions.contains(action);

  /// 复合流程的显式授权作用域：先校验 [action]，成功后在作用域内放行
  /// 所有子写入。返回 null 表示该动作未授权，调用方应停止流程。
  T? runWithAuthorizedAction<T>(PasswordAction action, T Function() body) {
    // 入口动作本身未启用时，不建立放行作用域；子动作仍按各自门禁执行，
    // 避免“父动作关闭 → 绕过所有子动作保护”。
    if (!_actionRequired(action) && !isManagementMode) {
      return body();
    }
    if (!_authorizedFor('', action: action)) return null;
    _authorizedActionDepth++;
    try {
      return body();
    } finally {
      _authorizedActionDepth--;
    }
  }

  /// `void` 复合流程的快捷入口；返回 false 表示未授权。
  bool runWithAuthorizedActionVoid(
    PasswordAction action,
    void Function() body,
  ) {
    if (!_actionRequired(action) && !isManagementMode) {
      body();
      return true;
    }
    if (!_authorizedFor('', action: action)) return false;
    _authorizedActionDepth++;
    try {
      body();
      return true;
    } finally {
      _authorizedActionDepth--;
    }
  }

  T _runInternalWrite<T>(T Function() action) {
    _internalWriteDepth++;
    try {
      return action();
    } finally {
      _internalWriteDepth--;
    }
  }

  void _save() {
    if (_suspendSaveDepth > 0) {
      _savePending = true;
      return;
    }
    // 第 1 轮修复：指纹与计数缓存**必须在首次通知之前**失效 —— 此前顺序相反，
    // 首轮 rebuild 读到的是过期缓存（统计数据短暂停留旧值），要等落盘后的第二次
    // 通知才被纠正。
    _invalidateDerivedCaches();
    // 修复（审查 三-1）：**先通知界面，再落盘** —— 此前通知被推迟到全库加密
    // 写盘之后，用户改动与界面刷新之间隔了一次磁盘 IO（数据量大时可感知延迟）。
    notifyListeners();
    final task = _pendingSave.then((_) async {
      final ok = await _storageService.saveData(_appData);
      final changed = _lastSaveFailed != !ok;
      _lastSaveFailed = !ok;
      // 第 1 轮 G-1 修复：仅当失败态**翻转**时才再通知。主界面"保存失败"横幅与
      // toast 都以 saveFailed 为数据源，翻转时必须通知；而"成功且此前也成功"时
      // 这次通知只会引发一轮多余的全量 rebuild（高频操作下可感知）。
      if (changed) notifyListeners();
    });
    // 修复（审查 P1-2）：任务链必须带 onError 兜底 —— 否则一旦某次保存抛错，
    // `_pendingSave` 会进入错误态，此后所有 `.then(...)` 回调都不再执行，
    // 表现为"界面一切正常、数据却再也不落盘"的静默停摆。
    _pendingSave = task.catchError((Object e, StackTrace s) {
      debugPrint('保存数据失败：$e');
      final changed = !_lastSaveFailed;
      _lastSaveFailed = true;
      if (changed) notifyListeners();
    });
    // 显式声明"故意不等待"：写盘在队列里串行执行，结果由 saveFailed 标志与
    // 主界面横幅呈现；退出前由 flushPendingSaves() 统一等待（见其注释）。
    unawaited(_pendingSave);
  }

  String _sanitizeReasonText(String text) => RecordText.normalizeReason(text);

  /// 数据指纹：由数据**自身内容**计算的廉价哈希（记录/考勤条数 + 关键字段滚动哈希）。
  ///
  /// 用途：统计看板等"结果缓存"据此判断是否需要重算。
  /// 设计说明（重要）：**不要**改用"每次变更自增的版本号"——那需要挂到十几条
  /// 变更路径（新增/编辑/删除/导入/恢复/批量/考勤…）上，漏一条就会静默
  /// 显示过期数据；也不能用"有记录的天数"这类近似量（同一天内增删改都看不出来）。
  String? _fingerprintCache;

  String get dataFingerprint {
    // 修复（审查 六-2）：本 getter 要遍历全部记录 + 考勤，而看板在**每次
    // build** 都会调用它（数据攒一年后每帧都很贵）。
    // 性能批 M5：此前还带一层"500ms 时间窗到期即重算"的保护 —— 它的代价是
    // 看板持续重建时每 500ms 就白白重算一次全量哈希；正确性其实完全由
    // `_save()` 里的 `_invalidateDerivedCaches()` 保证（所有变更都必须经 `_save()`
    // 落盘与通知，否则数据本身就不持久化，不存在"漏挂"的数据路径）。
    // 现与计数缓存口径统一：缓存只在脏标记失效，不再按时间过期。
    final cached = _fingerprintCache;
    if (cached != null) return cached;
    final value = _computeFingerprint();
    _fingerprintCache = value;
    return value;
  }

  String _computeFingerprint() {
    var hash = 17;
    var count = 0;
    for (final records in _appData.recordsByDate.values) {
      for (final record in records) {
        count++;
        hash = 0x1fffffff & (hash * 31 + record.id.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.studentName.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.operationType.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.reasons.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.periodKey.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.timestamp.hashCode);
        // 修复（1.1，2026-10-03 审查）：`date` 此前被漏掉，而统计的"记录天数"
        // 口径正是按 `record.date` 去重计数——一条记录被改到另一日期桶、
        // 其余六个字段恰好不变时（重导入同 id 记录、改名重建记录），
        // 指纹不变 → 统计看板的取数缓存键不变 → 看板静默显示旧天数。
        hash = 0x1fffffff & (hash * 31 + (record.date?.hashCode ?? 0));
        // 其余会改变界面展示的字段同样纳入，避免改备注/身份后缓存不刷新。
        hash = 0x1fffffff & (hash * 31 + record.periodName.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.remark.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.recordedBy.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.createdByIdentityId.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.createdAtIso.hashCode);
        hash = 0x1fffffff & (hash * 31 + (record.isAppended ? 1 : 0));
        hash = 0x1fffffff & (hash * 31 + (record.isImported ? 1 : 0));
        hash = 0x1fffffff & (hash * 31 + (record.isBatch ? 1 : 0));
      }
    }
    var attendanceCount = 0;
    for (final records in _appData.attendanceByDate.values) {
      for (final record in records) {
        attendanceCount++;
        hash = 0x1fffffff & (hash * 31 + record.id.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.status.hashCode);
        hash = 0x1fffffff & (hash * 31 + record.periodKey.hashCode);
        // 同上：考勤日期同样参与统计口径，一并纳入指纹。
        hash = 0x1fffffff & (hash * 31 + record.date.hashCode);
      }
    }
    // 修复（审查四 S-2）：考勤统计口径还依赖名单（应到人数、名单内外判定）与
    // "计入未到"名单 —— 这两者此前不在指纹里，增删学生/改"计入未到"后，
    // 看板缓存键不变，会静默显示旧的应到/实到数字。
    for (final s in _appData.students) {
      hash = 0x1fffffff & (hash * 31 + s.hashCode);
    }
    for (final st in _appData.settings.attendanceAbsentStatuses) {
      hash = 0x1fffffff & (hash * 31 + st.hashCode);
    }
    for (final k in _appData.settings.attendanceSyncMap.keys) {
      hash = 0x1fffffff & (hash * 31 + k.hashCode);
    }
    return '$count-$attendanceCount-$hash';
  }

  /// 原因文本净化（P2-6/P3-2 修复）：trim、去掉空项、禁用顿号。
  /// 原因列表以"顿号"拼接存储，原因本身若含顿号会让拆分/统计/同步映射全部错位；
  /// 同步映射值含顿号还会让原因串无上限膨胀（实测 2→4→6 段）。
  ///
  /// **[clip] 与长度上限的关系（R-2 澄清）**：记录内的原因**只有"新录入/编辑"
  /// 才裁剪**（[clip] = true），**搬运既有数据时原样保留**（[clip] = false）。
  /// 这与时段键的处理是同一个道理（见 [_buildRecord] 的 `normalizePeriodKey`）：
  /// 导入/改名/id 修复是对老数据的搬运，静默改写老师当初录入的内容，比"留一条偏长
  /// 的原因"危害更大（原因库侧 [addReason] / [renameReason] 与同步映射则一律裁剪，
  /// 因为那是"新建内容"）。界面侧 [RecordDialog] 也用 `maxLength` 提前拦住输入。
  List<String> _sanitizeReasonList(List<String> reasons, {bool clip = true}) {
    return [
      for (final reason in reasons)
        if (reason.trim().replaceAll('、', '，').isNotEmpty)
          clip
              ? AppDataProvider.clipReason(reason.trim().replaceAll('、', '，'))
              : reason.trim().replaceAll('、', '，'),
    ];
  }

  /// 净化整个原因库（导入/替换等外部来源统一走这里）：
  /// 与记录侧 [_sanitizeReasonList] 同口径 —— trim、去空、禁用顿号、限长
  ///（原因库属于"新建内容"，一律裁剪）。此前"替换导入"绕过净化，
  /// 含顿号的原因会破坏"顿号拼接存储"的不变量。
  ReasonLibrary _sanitizedReasonLibrary(ReasonLibrary lib) {
    final praise = <String, List<String>>{};
    for (final entry in lib.praise.entries) {
      praise[entry.key] = _sanitizeReasonList(entry.value);
    }
    final criticism = <String, List<String>>{};
    for (final entry in lib.criticism.entries) {
      criticism[entry.key] = _sanitizeReasonList(entry.value);
    }
    return ReasonLibrary(praise: praise, criticism: criticism);
  }

  String _getTodayString() {
    final now = AppClock.now();
    return formatYmd(now);
  }

  /// “今日”按**当前归属日**取：跨零点时段的凌晨部分（如 00:30 的就寝）
  /// 归属前一天，与 addRecord/考勤的落库日期保持一致；否则记录会写进
  /// 前一天，却从今日列表/角标/导出里消失。
  ///
  /// 仅用于今日列表/角标/今日导出；备份时间、恢复码创建日等仍用
  /// [_getTodayString]（真实日历日）。
  String _attributionTodayString() {
    return attributionDateString(AppClock.now());
  }

  /// 当前归属日（yyyy-MM-dd），供“今日”展示/导出复用。
  String get todayAttributionDate => _attributionTodayString();

  /// X-12：按"当前时刻 + 时段"计算**归属日**（yyyy-MM-dd）。
  /// 跨零点时段的凌晨部分（如 00:30 的就寝）回退到前一天（入睡那天）。
  String _attributionDateFor(String periodKey) =>
      _formatDate(attributionDay(AppClock.now(), periodKey));

  String _getCurrentTime() {
    final now = AppClock.now();
    // 精确到秒（与导出/导入格式一致，不能用毫秒，否则文件不兼容）。
    // 注意：同一秒内的多条记录时间戳相同——顺序由列表插入顺序稳定保证，
    // 不依赖时间戳区分先后。
    return '${twoDigit(now.hour)}:${twoDigit(now.minute)}:${twoDigit(now.second)}';
  }

  /// 最近一次生成 ID 用的毫秒值（防止系统时间回拨导致 ID 重复）。
  int _lastIdMillis = 0;

  String _generateId() {
    // 毫秒时间戳 + 自增计数，避免批量追加同一毫秒内 ID 冲突。
    // 计数器同时避开"系统时间回拨"：比当前计数器小的时间戳会主动往上抬。
    _idCounter++;
    final millis = DateTime.now().millisecondsSinceEpoch;
    if (millis <= _lastIdMillis) {
      _lastIdMillis++;
    } else {
      _lastIdMillis = millis;
    }
    return '${_lastIdMillis}_$_idCounter';
  }

  /// 记录 id 是否已存在（G-3：防止外部注入的 recordId 与既有记录撞号）。
  /// 审计 P2-30：从记录域上移到基类，供 [_generateUniqueRecordId] 与各域复用。
  bool _recordIdExists(String id) {
    for (final list in _appData.recordsByDate.values) {
      for (final record in list) {
        if (record.id == id) return true;
      }
    }
    return false;
  }

  /// 生成不与现有记录撞号的 id（审计 P2-30）：毫秒时间戳+自增计数在跨重启后
  /// 可能从头再来，此前只能靠启动期的重复 ID 修复兜底；这里生成后循环查重，
  /// 撞了就再生成（正常路径零开销）。
  String _generateUniqueRecordId() {
    var id = _generateId();
    while (_recordIdExists(id)) {
      id = _generateId();
    }
    return id;
  }

  String _formatDate(DateTime date) {
    return formatYmd(date);
  }

  /// 统一失效所有派生缓存（指纹、计数）——由 `_save()` 在数据变更后调用。
  void _invalidateDerivedCaches() {
    _fingerprintCache = null;
    _totalRecordCountCache = null;
    _totalAttendanceCountCache = null;
  }

  /// 记录总条数（修复 审查 六-3）：带缓存 —— 设置页每次重建都会显示它，
  /// 而它是 O(全部记录)。缓存由 `_invalidateDerivedCaches()` 统一失效。
  int get totalRecordCount {
    final cached = _totalRecordCountCache;
    if (cached != null) return cached;
    var count = 0;
    for (final list in _appData.recordsByDate.values) {
      count += list.length;
    }
    _totalRecordCountCache = count;
    return count;
  }

  int? _totalRecordCountCache;

  /// 考勤总条数（同上，避免界面每次重建都展开全量考勤列表）。
  int get totalAttendanceCount {
    final cached = _totalAttendanceCountCache;
    if (cached != null) return cached;
    var count = 0;
    for (final list in _appData.attendanceByDate.values) {
      count += list.length;
    }
    _totalAttendanceCountCache = count;
    return count;
  }

  int? _totalAttendanceCountCache;

  List<StudentRecord> getRecordsForDates(List<String> dates) {
    final dateSet = dates.toSet();
    final allRecords = <StudentRecord>[];
    for (final date in dates) {
      for (final record in _appData.recordsByDate[date] ?? const []) {
        // 审计 P2-20：记录自身的日期才是归属日。桶键与 record.date 不一致
        // （历史导入/手工改期遗留）时，不能把区间外的记录混进统计。
        final recordDate = record.date;
        if (recordDate != null &&
            recordDate.isNotEmpty &&
            !dateSet.contains(recordDate)) {
          continue;
        }
        allRecords.add(record);
      }
    }
    // 先按日期、再按时间排序（原来只按时间，跨日期会交错）。
    allRecords.sort((a, b) {
      final byDate = (b.date ?? '').compareTo(a.date ?? '');
      if (byDate != 0) return byDate;
      return b.timestamp.compareTo(a.timestamp);
    });
    return allRecords;
  }

  /// 某天的记录列表（**只读副本**）。
  ///
  /// 修复（1.4，2026-10-03 审查）：此前直接返回内部列表本体，调用方一句
  /// `list.clear()` / `.sort()` 就会静默改写内部数据——既不落盘也不通知 UI。
  /// 这里统一返回 `List.unmodifiable`，误改会立即抛错而不是损坏数据。
  List<StudentRecord> getRecordsForDate(String date) {
    return List<StudentRecord>.unmodifiable(
      _appData.recordsByDate[date] ?? const [],
    );
  }

  /// 今日记录列表（**只读副本**，理由同 [getRecordsForDate]）。
  List<StudentRecord> getTodayRecords() {
    final today = _attributionTodayString();
    return List<StudentRecord>.unmodifiable(
      _appData.recordsByDate[today] ?? const [],
    );
  }

  List<String> getHistoryDates() {
    return _appData.recordsByDate.keys.toList()..sort((a, b) => b.compareTo(a));
  }

  /// 与统计模块共用同一日期区间口径：超长区间取结束日往前最近
  /// [kMaxDateRangeDays] 天，避免“历史选中区间”丢掉最近日期。
  List<String> getDatesBetween(String startDate, String endDate) {
    return StatisticsService.datesBetween(startDate, endDate);
  }

  /// 构造一条记录：**记录构造的唯一入口**（原因净化、空时段键规整、备注默认值、
  /// 姓名/备注/原因长度上限都在这里）。
  ///
  /// **契约**：`app_data_provider.dart` 内**不允许**出现任何手写的 `StudentRecord(...)`
  /// 构造（除本方法外）——新增/编辑/导入/改名/考勤同步/id 修复**全部**必须经由此处。
  /// 此前因存在 6 处手写构造，出现"新增截断、编辑与导入不截断"的两套规则（N-2），
  /// 且 isImported / 考勤同步 / 空时段键三处也曾各自漂移。回归测试见
  /// `test/comprehensive_fixes_test.dart` 的"长度上限全路径一致"与"无手写构造"用例。
  ///
  /// [periodNameOverride]：**仅**导入/改名等"搬运既有数据"的场景使用——
  /// 外部表格里可能只有原始时段名（如"上午上课"）而没有可识别的 periodKey，
  /// 此时必须保留原样标签，不能按 periodKey 重算成"全天"（那会把老师的原意洗掉）。
  /// 为空时按 [periodKey] 正常推算。
  ///
  /// [normalizePeriodKey]：是否把空时段键规整为 all_day。
  /// - **新录入/编辑**（老师当场选时段）传 true —— 这是 P1-2 的修复：
  ///   避免"考勤侧 all_day / 记录侧空串"并存导致编辑时判"时段不同"、重复考勤。
  /// - **搬运既有数据**（导入 / 改名 / id 修复）传 false —— 这些记录的
  ///   `periodKey.isEmpty` 是"时段无法识别"的**有效信号**，界面靠它退回显示
  ///   保存的原始时段名（见 `periodNameForRecord`）。若强行规整成 all_day，
  ///   标签会被重算成"全天"，原始信息就丢了（daily_flow ⑥ 的回归）。
  StudentRecord _buildRecord({
    required String id,
    required String studentName,
    required String operationType,
    required List<String> reasons,
    required String periodKey,
    required String remark,
    required String date,
    required String timestamp,
    required bool isAppended,
    bool isImported = false,
    bool isBatch = false,
    String? periodNameOverride,
    bool normalizePeriodKey = true,
    String recordedBy = '',
    String createdByIdentityId = '',
    String createdAtIso = '',
  }) {
    // P1-2 根因修复：空时段键在创建时统一规整为 all_day。
    // 此前"考勤侧 all_day / 记录侧空串"并存，编辑记录时重对齐必然判"时段不同"，
    // 把考勤的时段键改写为空串，进而产生同日重复考勤与次数重复统计。
    final normalizedKey = (normalizePeriodKey && periodKey.isEmpty)
        ? AttendanceRecord.allDayKey
        : periodKey;
    final name = AppDataProvider.clipStudentName(studentName);
    final clippedRemark = AppDataProvider.clipRemark(remark);
    final periodName =
        (periodNameOverride != null && periodNameOverride.isNotEmpty)
        ? periodNameOverride
        : getTimePeriodName(normalizedKey);
    return StudentRecord(
      id: id,
      studentName: name,
      operationType: operationType,
      // R-2：原因长度上限与时段键同一条边界——"新录入/编辑"才裁剪，
      // "搬运既有数据"（normalizePeriodKey == false）原样保留老师的原始内容。
      reasons: _sanitizeReasonList(reasons, clip: normalizePeriodKey).join('、'),
      periodKey: normalizedKey,
      periodName: periodName,
      remark: clippedRemark.isNotEmpty
          ? clippedRemark
          : (isBatch ? '批量' : (isAppended ? '追加' : '')),
      timestamp: timestamp,
      isAppended: isAppended,
      isImported: isImported,
      isBatch: isBatch,
      date: date,
      recordedBy: recordedBy,
      createdByIdentityId: createdByIdentityId,
      createdAtIso: createdAtIso,
    );
  }

  /// 删除记录，成功返回 true；未找到时返回 false 供 UI 提示。
  bool deleteRecord(String recordId, {String? date}) {
    final hits = <({String date, StudentRecord record, int index})>[];
    if (date != null) {
      final list = _appData.recordsByDate[date];
      if (list != null) {
        for (var i = 0; i < list.length; i++) {
          if (list[i].id == recordId) {
            hits.add((date: date, record: list[i], index: i));
          }
        }
      }
    }
    // 指定桶没命中时降级为全表按 id 查找：历史数据的 record.date 可能与
    // 所在桶键不一致，只查单桶会让这类记录永远删不掉。
    if (hits.isEmpty) {
      for (final entry in _appData.recordsByDate.entries) {
        for (var i = 0; i < entry.value.length; i++) {
          if (entry.value[i].id == recordId) {
            hits.add((date: entry.key, record: entry.value[i], index: i));
          }
        }
      }
    }
    if (hits.isEmpty) return false;
    // 审计 P2-7：重复 id 脏数据可能跨学生/跨日期命中多条；逐条校验身份与
    // 时间窗，不能只校验第一条就删掉其余无权删除的记录。
    final allowedHits = hits
        .where((hit) => canMutateRecord(hit.record))
        .toList(growable: false);
    if (allowedHits.isEmpty) {
      _log('安全验证', '拒绝删除记录：非本人/超出窗口/无班主任管理');
      return false;
    }
    if (allowedHits.length != hits.length) {
      _log('安全验证', '部分同 id 记录无权删除，已跳过 ${hits.length - allowedHits.length} 条');
    }
    // 修复（审查三 1.1）：此前 removeWhere 会删掉全部同 id 记录、日志却只记
    // indexWhere 找到的第一条 —— 重复 id 时日志与实际删除量不符。
    // 现在先收集全部命中，再按对象引用逐条删除（只删通过校验的那几条）。
    for (final hit in allowedHits) {
      final list = _appData.recordsByDate[hit.date];
      if (list == null) continue;
      final currentIndex = list.indexWhere((r) => identical(r, hit.record));
      if (currentIndex >= 0) {
        list.removeAt(currentIndex);
      }
      if (list.isEmpty) {
        _appData.recordsByDate.remove(hit.date);
      }
      _removeLinkedAttendance(hit.date, recordId);
      // 修复（审计 P2-35）：同上，兜底记录自带 date 的挂载。
      final recordDate = hit.record.date;
      if (recordDate != null &&
          recordDate.isNotEmpty &&
          recordDate != hit.date) {
        _removeLinkedAttendance(recordDate, recordId);
      }
      _log(
        '删除记录',
        '${hit.date} · ${hit.record.studentName} · ${hit.record.operationType} · '
            '${hit.record.reasons} · ${hit.record.timestamp}',
      );
    }
    _lastRecordUndo = _RecordUndo.delete(hits);
    _save();
    return true;
  }

  /// 记录 → 考勤：新增的批评记录带了同步原因时登记考勤，并建立关联，
  /// 避免"考勤同步"再生成一条重复记录。
  void _syncRecordToAttendance(StudentRecord record) {
    if (!AttendanceFeature.enabled) return;
    if (record.operationType != '批评') return;
    final date = record.date;
    if (date == null || date.isEmpty) return;
    final status = _mappedStatusOfReasons(record.reasons);
    if (status.isEmpty) return;
    setAttendanceForStudents(
      [record.studentName],
      status,
      date: date,
      // 记录未选时段（periodKey 为空）时按"全天"登记，避免出现空时段考勤。
      periodKey: record.periodKey.isEmpty
          ? AttendanceRecord.allDayKey
          : record.periodKey,
      // B-06：派生考勤沿用源记录的时段显示名快照（若为空则按当前名称取）。
      periodName: record.periodName,
      syncedRecordId: record.id,
      // 修复（审查四 S-1）：这条考勤确由该记录派生 —— 标记方向，删记录时才撤销它。
      syncedFromRecord: true,
      // 与记录同一套身份逻辑：派生考勤沿用源记录的记录人快照。
      recordedBy: record.recordedBy,
      // P2-16：撤销删除记录重建派生考勤时沿用源记录的登记时间，
      // 不重新取当前时间（避免"撤销后时间变了"的误导）。
      timestamp: record.timestamp.isEmpty ? null : record.timestamp,
    );
  }

  /// 记录被删除时同步撤销其关联的考勤。
  void _removeLinkedAttendance(String date, String recordId) {
    if (!AttendanceFeature.enabled) return;
    final list = _appData.attendanceByDate[date];
    if (list == null) return;
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final record = list[i];
      if (record.syncedRecordId != recordId) continue;
      if (record.syncedFromRecord) {
        // 修复（审查四 S-1）：只撤销**由该记录派生**的考勤。
        list.removeAt(i);
        i--;
      } else {
        // 修复（审计 P1-7）：手工登记的考勤（考勤→记录方向）绝不删除，
        // 但要解除关联 —— 否则会留下指向已删记录的悬空链接。
        list[i] = record.copyWith(syncedRecordId: '');
      }
      changed = true;
    }
    if (!changed) return;
    if (list.isEmpty) _appData.attendanceByDate.remove(date);
  }

  /// 记录被编辑后重新对齐考勤：原因不再同步时撤销考勤，否则更新状态。
  /// 编辑记录后重新对齐考勤；返回 true 表示已对齐，false 表示目标时段撞键、
  /// 考勤保留在原时段（调用方需把记录的时段一并回退，避免"记录写新时段、
  /// 考勤留旧时段"的两侧不一致）。
  bool _resyncRecordEdit(String date, StudentRecord record) {
    if (!AttendanceFeature.enabled) return true;
    // P2-17：record.date 可能与桶键不一致（历史脏数据/导入异常），只查桶键
    // 会找不到关联考勤，导致改原因时不撤销旧考勤。先在桶键找，找不到再按
    // record.date 兜底，并把后续操作切到实际所在的桶。
    var bucketDate = date;
    final primaryLink = _findAttendanceLinkedTo(bucketDate, record.id);
    if (primaryLink == null) {
      // P2-17：桶键找不到时按 record.date 兜底（历史数据的 record.date 可能
      // 与桶键不一致），并把后续操作切到实际所在的桶。
      if (record.date != null &&
          record.date!.isNotEmpty &&
          record.date != date) {
        final alt = _findAttendanceLinkedTo(record.date!, record.id);
        if (alt != null) {
          bucketDate = record.date!;
          return _resyncRecordEditAt(bucketDate, record, alt);
        }
      }
      // 之前没有关联：若新原因命中映射，则补登记一次。
      _syncRecordToAttendance(record);
      return true;
    }
    return _resyncRecordEditAt(bucketDate, record, primaryLink);
  }

  /// [ _resyncRecordEdit] 的桶内实现：关联考勤已定位到 [link]（实际所在桶
  /// 记在 [date]），按原因与时段对齐考勤；返回 true 表示已对齐，false 表示
  /// 目标时段撞键、考勤保留在原时段。
  bool _resyncRecordEditAt(
    String date,
    StudentRecord record,
    AttendanceRecord link,
  ) {
    final status = record.operationType == '批评'
        ? _mappedStatusOfReasons(record.reasons)
        : '';
    final list = _appData.attendanceByDate[date];
    if (list == null) return true;
    final index = list.indexWhere((r) => r.id == link.id);
    if (index == -1) return true;
    if (status.isEmpty) {
      // X-5 修复：**按方向**决定去留 —— 只有"由该记录派生"的考勤
      //（syncedFromRecord == true）才随记录撤销；"考勤→记录"方向下老师手工
      // 登记的考勤（记录由它派生，方向标记保持 false）只解除关联、绝不删除。
      // 此前不看方向直接 `removeAt`：编辑一条派生记录把原因改到不再同步时，
      // 会把这条老师手工登记的考勤一起删掉。
      if (link.syncedFromRecord) {
        // 由该记录派生的考勤：原因不再命中映射（含改成表扬）时随记录撤销。
        list.removeAt(index);
        if (list.isEmpty) _appData.attendanceByDate.remove(date);
      } else if (link.syncedRecordId.isNotEmpty) {
        // 老师手工登记的考勤：只解除关联，绝不删除。
        list[index] = link.copyWith(syncedRecordId: '');
      }
      return true;
    }
    // P1-2 修复：新建时空时段会被规整为 all_day，而记录侧可能仍是空串；
    // 不规整的话这里必然判"时段不同"，把考勤的时段键改成空串，造成同日
    // 重复考勤与次数重复统计。比较与写回统一使用规整后的目标键。
    final targetKey = record.periodKey.isEmpty
        ? AttendanceRecord.allDayKey
        : record.periodKey;
    // 修复（审计 P2-37）：改时段可能与"另一条同学生同时段"的考勤撞唯一键。
    // 只清理**孤儿派生**的冲突条目（来源记录已不存在）；手工登记或仍被其它
    // 记录链接的条目保持不动 —— 撞键时放弃本次搬移（保留原时段），
    // 绝不静默删除手工数据。
    var movePeriod = true;
    if (link.periodKey != targetKey) {
      final conflictIndex = list.indexWhere(
        (r) =>
            r.id != link.id &&
            r.studentName == record.studentName &&
            r.periodKey == targetKey,
      );
      if (conflictIndex != -1) {
        final conflict = list[conflictIndex];
        // 只有"派生且来源已丢失"的条目才算可清理的孤儿；手工条目（无论有无
        // 关联）一律保留 —— 宁可放弃搬移，也不静默覆盖手工数据。
        final orphan =
            conflict.syncedFromRecord &&
            (conflict.syncedRecordId.isEmpty ||
                !_recordIdExists(conflict.syncedRecordId));
        if (orphan) {
          list.removeAt(conflictIndex);
        } else {
          movePeriod = false;
          _log(
            '修改记录',
            '${record.studentName} 目标时段已有考勤（${conflict.status}），'
                '保留该条并放弃时段搬移',
          );
        }
      }
    }
    // P1-8/P2-37（复查修正）：撞键时**不搬时段但照常对齐状态** —— 考勤留在
    // 原时段并更新为新原因映射的状态；同时返回 movePeriod=false，调用方据此把
    // 记录时段回退到原时段，两侧保持一致。若这里撞键直接 return false 不更新
    // 状态，会出现"记录新原因、考勤旧状态"的脱节。
    final effectiveKey = movePeriod ? targetKey : link.periodKey;
    // P1-9：搬移时段时同步刷新显示名快照 —— 此前只写 periodKey，
    // periodLabel 优先用旧快照，导出/界面会显示搬移前的时段名。
    final effectivePeriodName = getTimePeriodName(effectiveKey);
    final target = list.indexWhere((r) => r.id == link.id);
    if (target == -1) {
      list.add(
        link.copyWith(
          status: status,
          periodKey: effectiveKey,
          periodName: effectivePeriodName,
          timestamp: _getCurrentTime(),
          syncedRecordId: record.id,
        ),
      );
      return movePeriod;
    }
    list[target] = list[target].copyWith(
      status: status,
      periodKey: effectiveKey,
      periodName: effectivePeriodName,
      timestamp: _getCurrentTime(),
      syncedRecordId: record.id,
    );
    return movePeriod;
  }

  /// 新增原因到指定分组，成功返回 true。
  bool addReason(String operationType, String periodKey, String reason) {
    if (!_authorizedFor('library', action: PasswordAction.reasonModify)) {
      return false;
    }
    final value = _sanitizeReasonText(reason);
    if (value.isEmpty) return false;
    if (!_appData.reasons.addReason(operationType, periodKey, value)) {
      return false;
    }
    _log(
      '原因库',
      '新增原因 $value（$operationType · ${getTimePeriodName(periodKey)}）',
    );
    _save();
    return true;
  }

  /// 记录本次使用的操作类型（供"默认类型=上次用过的"使用，不额外触发保存）。
  void rememberOperationType(String operationType) {
    _appData.settings = _appData.settings.copyWith(
      lastOperationType: operationType == '批评' ? 1 : 0,
    );
  }

  /// 今日角标计数（审查三 4.2）：从 main.dart 的 UI 聚合下沉而来 ——
  /// 此前 widget 直接读内部可变列表并在 UI 里写"表扬/批评"二分规则。
  /// 返回 {学生名: (表扬次数, 批评次数)}，仅含今日有记录的学生。
  Map<String, ({int praise, int criticize})> todayCountsByStudent() {
    final today = _attributionTodayString();
    final result = <String, ({int praise, int criticize})>{};
    for (final r in _appData.recordsByDate[today] ?? const <StudentRecord>[]) {
      final current = result.putIfAbsent(
        r.studentName,
        () => (praise: 0, criticize: 0),
      );
      final praise = StatisticsService.isPraiseType(r.operationType);
      if (praise == null) continue;
      result[r.studentName] = praise
          ? (praise: current.praise + 1, criticize: current.criticize)
          : (praise: current.praise, criticize: current.criticize + 1);
    }
    return result;
  }

  /// 导出文件名前缀（形如 "五年3班_"），无前缀时返回空串。
  String _exportPrefix() {
    // P2-20 修复：剥离路径分隔符与非法字符、折叠 ..，防止前缀把导出文件
    // 写到导出目录之外（自伤型路径逃逸）。
    final raw = _appData.settings.exportFilePrefix.trim();
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll('..', '');
    // 修复（审查三 4.4）：Windows 保留设备名（CON/PRN/AUX/NUL/COM1~9/LPT1~9）
    // 不能作文件名 —— 前缀设成 CON 会让每次导出都失败。命中时回退到默认前缀。
    const reserved = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    if (reserved.contains(cleaned.toUpperCase())) return '班级管理系统';
    return cleaned;
  }

  bool _deleteRecordFromDate(
    String recordId,
    String date, {
    String logAction = '删除记录',
  }) {
    final records = _appData.recordsByDate[date];
    if (records == null) return false;
    final index = records.indexWhere((r) => r.id == recordId);
    final removed = index == -1 ? null : records[index];
    final before = records.length;
    records.removeWhere((r) => r.id == recordId);
    if (records.length == before) return false;
    if (records.isEmpty) {
      _appData.recordsByDate.remove(date);
    }
    // 删掉的是"考勤同步"生成的记录时，同步撤销对应考勤。
    _removeLinkedAttendance(date, recordId);
    // 修复（审计 P2-35）：记录自带 date 与桶键发散时（历史导入数据的边界），
    // 考勤可能挂在记录自身的 date 下 —— 一并尝试撤销，避免留下幽灵考勤。
    final ownDate = removed?.date;
    if (ownDate != null && ownDate.isNotEmpty && ownDate != date) {
      _removeLinkedAttendance(ownDate, recordId);
    }
    if (removed != null) {
      _log(
        logAction,
        '$date · ${removed.studentName} · ${removed.operationType} · '
        '${removed.reasons} · ${removed.timestamp}',
      );
    }
    _save();
    return true;
  }

  /// 在当天的考勤里按关联 id 找到对应的考勤记录。
  AttendanceRecord? _findAttendanceLinkedTo(String date, String recordId) {
    final list = _appData.attendanceByDate[date];
    if (list == null) return null;
    for (final record in list) {
      if (record.syncedRecordId == recordId) return record;
    }
    return null;
  }

  /// 考勤 → 批评记录：状态有同步映射时生成/更新对应批评记录，
  /// 状态不再需要批评时删除自动生成的同步记录（老师手录的仅解除关联）。
  /// “批评”类型停用时只更新/清理已有同步记录，不再新增 —— 否则关掉批评后
  /// 登记考勤仍会冒出批评记录，与记录类型开关矛盾。
  void _syncAttendanceToRecords(
    String date,
    Iterable<String> studentNames,
    String periodKey,
  ) {
    if (!AttendanceFeature.enabled) return;
    for (final name in studentNames) {
      final attendance = getAttendanceOf(name, date, periodKey: periodKey);
      final reason = attendance == null
          ? ''
          : attendanceSyncReasonFor(attendance.status);
      final linked = _findLinkedRecord(date, name, attendance);
      if (reason.isEmpty) {
        if (linked != null) {
          // 修复（审计 P0-1）：只允许删除"考勤同步"自动生成的记录；老师手工
          // 录入的批评记录（记录→考勤方向的源头）绝不删除，仅解除关联。
          if (linked.remark == AppDataProvider.attendanceSyncMarker) {
            _removeRecordsByIds(date, {linked.id});
          }
          _linkAttendanceToRecord(date, name, periodKey, '');
        }
        continue;
      }
      if (linked == null) {
        if (!_appData.settings.criticismEnabled) {
          // 已有同步记录仍按上面的逻辑更新/撤销；只是不再新生成。
          continue;
        }
        final id = _generateUniqueRecordId();
        // N-2：考勤同步生成的记录同样走唯一入口，避免规则分裂。
        _recordsOf(date).add(
          _buildRecord(
            id: id,
            studentName: name,
            operationType: '批评',
            reasons: <String>[reason],
            periodKey: periodKey,
            remark: AppDataProvider.attendanceSyncMarker,
            date: date,
            timestamp: _getCurrentTime(),
            isAppended: false,
            // 派生记录继承考勤记录的记录人，避免身份切换后两边对不上。
            recordedBy: (attendance?.recordedBy.isNotEmpty ?? false)
                ? attendance!.recordedBy
                : currentRecordedBy,
            createdByIdentityId: currentIdentityId,
            createdAtIso: AppClock.now().toIso8601String(),
          ),
        );
        _linkAttendanceToRecord(date, name, periodKey, id);
        continue;
      }
      // B-01：老师手工录入的记录（记录→考勤方向的源头）不归考勤侧改写原因；
      // 只有 remark == attendanceSyncMarker 的自动生成记录才允许按当前状态重写。
      if (linked.remark != AppDataProvider.attendanceSyncMarker) {
        _linkAttendanceToRecord(date, name, periodKey, linked.id);
        continue;
      }
      // 已有自动生成的同步记录：只更新"考勤对应的那条原因"，
      // 保留老师手工补的其它原因与备注（原来整体重写会把这些丢掉）。
      final mapped = _mappedReasonsOf(linked.reasons);
      final kept = linked.reasons
          .split('、')
          .where(
            (item) => item.trim().isNotEmpty && !mapped.contains(item.trim()),
          )
          .toList();
      final newReasons = [...kept, reason].join('、');
      if (linked.reasons != newReasons) {
        final list = _recordsOf(date);
        final index = list.indexWhere((r) => r.id == linked.id);
        if (index != -1) {
          // N-2：同样走唯一入口（原因已由 _sanitizeReasonList 净化，这里再统一一次
          // 确保与新增路径规则完全一致）。
          list[index] = _buildRecord(
            id: linked.id,
            studentName: linked.studentName,
            operationType: linked.operationType,
            reasons: newReasons.split('、'),
            periodKey: periodKey,
            remark: linked.remark,
            date: linked.date ?? date,
            timestamp: linked.timestamp,
            isAppended: linked.isAppended,
            isImported: linked.isImported,
            isBatch: linked.isBatch,
            recordedBy: linked.recordedBy,
            createdByIdentityId: linked.createdByIdentityId,
            createdAtIso: linked.createdAtIso,
          );
        }
      }
      _linkAttendanceToRecord(date, name, periodKey, linked.id);
    }
  }

  /// 记录原因里第一个命中同步映射的考勤状态（没有返回空）。
  String _mappedStatusOfReasons(String reasons) {
    for (final reason in reasons.split('、')) {
      final status = attendanceStatusForReason(reason);
      if (status.isNotEmpty) return status;
    }
    return '';
  }

  /// 把考勤记录与批评记录互相关联（便于撤销时同步清理）。
  void _linkAttendanceToRecord(
    String date,
    String studentName,
    String periodKey,
    String recordId,
  ) {
    final list = _appData.attendanceByDate[date];
    if (list == null) return;
    final index = list.indexWhere(
      (r) => r.studentName == studentName && r.periodKey == periodKey,
    );
    if (index == -1) return;
    if (list[index].syncedRecordId == recordId) return;
    list[index] = list[index].copyWith(syncedRecordId: recordId);
  }

  /// 批量登记某天某时间段的考勤状态（一次写盘）：status 为空表示撤销。
  /// 返回实际发生变化的条数（状态未变化的学生不计入）；
  /// 有同步映射的状态会同时在批评记录里生成/更新对应记录。
  int setAttendanceForStudents(
    Iterable<String> studentNames,
    String status, {
    required String date,
    String periodKey = AttendanceRecord.allDayKey,
    String periodName = '',
    String syncedRecordId = '',
    bool syncedFromRecord = false,
    String? recordedBy,
    // P2-16：撤销删除记录重建派生考勤时沿用源记录的登记时间（默认取当前时间）。
    String? timestamp,
    // “覆盖重复”导入时，旧考勤可能已被删除记录时解除关联、看起来像人工登记；
    // 此时必须允许按导入记录重新登记，否则记录改了而考勤仍停在旧状态。
    bool overwriteManualAttendance = false,
    PasswordAction action = PasswordAction.attendanceRegister,
  }) {
    if (!_authorizedFor('attendance', action: action)) return 0;
    if (action == PasswordAction.attendanceRegister &&
        _internalWriteDepth == 0 &&
        !canActiveIdentityRegisterAttendance) {
      _log('安全验证', '拒绝考勤登记：当前身份无普通模式考勤登记权限');
      return 0;
    }
    final value = status.trim();
    final names = studentNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return 0;
    final time = timestamp ?? _getCurrentTime();
    var changed = 0;
    // 撤销登记时把"考勤同步"自动生成的批评记录一并删掉（老师手录的保留），
    // 先收集它们的 id。
    final orphanRecordIds = <String>{};
    for (final name in names) {
      // 一致性修复（1.2，2026-10-03 审查）：先把桶与命中位置**查出来但不建桶**——
      // 旧实现无条件 putIfAbsent，撤销/无命中的学生也会留下一个空桶，
      // `getAttendanceDates()` 就会把该日期当成"有考勤的日期"返回，
      // UI 上出现空的考勤日期入口（全班全量撤销时必然触发）。
      final existing = _appData.attendanceByDate[date];
      final index = existing == null
          ? -1
          : existing.indexWhere(
              (r) => r.studentName == name && r.periodKey == periodKey,
            );
      if (value.isEmpty) {
        if (index == -1) continue;
        final removed = existing!.removeAt(index);
        // 修复（审计 P0-1）：仅清理"考勤同步"自动生成的关联记录；老师手工
        // 录入的批评记录即使被链接，撤销考勤时也保留（只解除关联、不删数据）。
        if (removed.syncedRecordId.isNotEmpty &&
            _isAttendanceGeneratedRecord(date, removed.syncedRecordId)) {
          orphanRecordIds.add(removed.syncedRecordId);
        }
        if (existing.isEmpty) _appData.attendanceByDate.remove(date);
        changed++;
        continue;
      }
      final list =
          existing ?? _appData.attendanceByDate.putIfAbsent(date, () => []);
      if (index == -1) {
        list.add(
          AttendanceRecord(
            id: _generateId(),
            studentName: name,
            status: value,
            date: date,
            periodKey: periodKey,
            // B-06：登记时保存显示名快照；调用方未传时按当前时段名取。
            periodName: periodName.isNotEmpty
                ? periodName
                : getTimePeriodName(periodKey),
            timestamp: time,
            syncedRecordId: syncedRecordId,
            syncedFromRecord: syncedFromRecord,
            // 不传时用当前身份；记录派生考勤传源记录的记录人快照。
            recordedBy: recordedBy ?? currentRecordedBy,
          ),
        );
        changed++;
        continue;
      }
      if (list[index].status == value &&
          (syncedRecordId.isEmpty ||
              list[index].syncedRecordId == syncedRecordId)) {
        continue;
      }
      // P2-7 修复：已有人工登记（无关联记录）的考勤，不允许被"批评记录同步"
      // 静默改写状态或抢占关联——场景是先登记"请假"，又录了一条映射到考勤的
      // 批评，不应无声变成"迟到"。人工操作优先，跳过并留痕。
      if (syncedRecordId.isNotEmpty &&
          list[index].syncedRecordId.isEmpty &&
          !overwriteManualAttendance) {
        _log(
          '考勤同步',
          '$name 已有人工登记（${list[index].status}），'
              '跳过来自批评记录的改写（$value）',
        );
        continue;
      }
      // 审计 P1-7：考勤已关联到**另一条**记录时，新记录同步不得抢占关联——
      // 否则先登记"缺勤"（自动建批评并回填链接）后，再录一条映射"迟到"的批评
      // 会把这格考勤静默改成迟到、链接被新记录抢走，原自动记录从此无来源、
      // 永久计入批评统计。保留既有关联，跳过并留痕。
      if (syncedRecordId.isNotEmpty &&
          list[index].syncedRecordId.isNotEmpty &&
          list[index].syncedRecordId != syncedRecordId) {
        _log(
          '考勤同步',
          '$name 已有记录派生考勤（${list[index].status}），'
              '跳过来自另一条批评记录的改写（$value）',
        );
        continue;
      }
      // 说明（复查 #4）：手工改写一条"记录派生"考勤时，仍保留其派生关联
      //（syncedFromRecord 与 syncedRecordId 不变）——这是有意取舍：该考勤的来源
      // 就是那条批评记录，删记录时随之撤销是合理联动，而非误删手工数据。
      list[index] = list[index].copyWith(
        status: value,
        timestamp: time,
        // B-12：改写考勤时同步更新“谁改的”和显示名快照。
        // 未启用操作身份（currentRecordedBy 为空）时保留原记录人，避免把
        // 历史上留下的人名清空；显式传入 recordedBy（记录派生同步）优先。
        recordedBy:
            recordedBy ??
            (currentRecordedBy.isNotEmpty
                ? currentRecordedBy
                : list[index].recordedBy),
        periodName: periodName.isNotEmpty ? periodName : list[index].periodName,
        syncedRecordId: syncedRecordId.isEmpty
            ? list[index].syncedRecordId
            : syncedRecordId,
        // 覆盖重复导入时把这格考勤重新挂到新记录上；普通人工改状态
        // （syncedRecordId 为空）仍保留原来源标记。
        syncedFromRecord: syncedRecordId.isNotEmpty
            ? syncedFromRecord
            : list[index].syncedFromRecord,
      );
      changed++;
    }
    if (changed > 0) {
      if (orphanRecordIds.isNotEmpty) {
        _removeRecordsByIds(date, orphanRecordIds);
      }
      // 同步到批评记录（新增/更新/删除对应记录），再整体落盘。
      _runInternalWrite(() => _syncAttendanceToRecords(date, names, periodKey));
      final periodLabel = getTimePeriodName(periodKey);
      for (final name in names) {
        final record = getAttendanceOf(name, date, periodKey: periodKey);
        if (value.isEmpty) {
          _log('考勤撤销', '$date · $periodLabel · $name');
        } else if (record != null) {
          _log('考勤登记', '$date · $periodLabel · $name · ${record.status}');
        }
      }
      _save();
    }
    return changed;
  }

  /// 某天的考勤记录（**只读副本**，无记录时返回空列表；理由同 [getRecordsForDate]）。
  List<AttendanceRecord> getAttendanceForDate(String date) {
    return List<AttendanceRecord>.unmodifiable(
      _appData.attendanceByDate[date] ?? const [],
    );
  }

  /// 某学生某天某时间段的考勤记录；未登记返回 null。
  AttendanceRecord? getAttendanceOf(
    String studentName,
    String date, {
    String periodKey = AttendanceRecord.allDayKey,
  }) {
    for (final record in getAttendanceForDate(date)) {
      if (record.studentName == studentName && record.periodKey == periodKey) {
        return record;
      }
    }
    return null;
  }

  /// 某状态同步的批评原因（未配置返回空字符串，表示不生成批评记录）。
  String attendanceSyncReasonFor(String status) =>
      _appData.settings.attendanceSyncMap[status] ?? '';

  /// 批评原因反查考勤状态（未配置返回空字符串）。
  String attendanceStatusForReason(String reason) {
    final value = reason.trim();
    if (value.isEmpty) return '';
    for (final entry in _appData.settings.attendanceSyncMap.entries) {
      if (entry.value == value) return entry.key;
    }
    return '';
  }

  /// 找到与某条考勤对应的批评记录：优先按链接 id，其次按"同步标记 + 同一时段"。
  StudentRecord? _findLinkedRecord(
    String date,
    String studentName,
    AttendanceRecord? attendance,
  ) {
    final records = _appData.recordsByDate[date];
    if (records == null || attendance == null) return null;
    final linkId = attendance.syncedRecordId;
    if (linkId.isNotEmpty) {
      for (final record in records) {
        if (record.id == linkId) return record;
      }
    }
    // 回退：按"同步标记 + 同一学生同一时间段"找，链接丢失时也不会重复生成。
    for (final record in records) {
      if (record.studentName == studentName &&
          record.periodKey == attendance.periodKey &&
          record.remark == AppDataProvider.attendanceSyncMarker) {
        return record;
      }
    }
    return null;
  }

  /// 一条记录里所有"可被同步替换"的原因：当前映射的**值**（新口径）∪ 映射的
  /// **键**（旧口径，如默认 迟到→迟到 时期写入的原因名）。审计 P2-38：用户改过
  /// 映射后，旧原因此前不被识别，会与新原因并存（"迟到、迟到X"）被重复统计。
  Set<String> _mappedReasonsOf(String reasons) {
    final map = _appData.settings.attendanceSyncMap;
    final result = <String>{};
    for (final reason in reasons.split('、')) {
      final value = reason.trim();
      if (value.isEmpty) continue;
      if (map.containsValue(value) || map.containsKey(value)) {
        result.add(value);
      }
    }
    return result;
  }

  List<StudentRecord> _recordsOf(String date) =>
      _appData.recordsByDate.putIfAbsent(date, () => <StudentRecord>[]);

  void _removeRecordsByIds(String date, Set<String> ids, {Set<String>? altDates}) {
    void removeIn(String bucket) {
      final records = _appData.recordsByDate[bucket];
      if (records == null) return;
      records.removeWhere((record) => ids.contains(record.id));
      if (records.isEmpty) _appData.recordsByDate.remove(bucket);
    }

    removeIn(date);
    if (altDates != null) {
      for (final alt in altDates) {
        if (alt != date) removeIn(alt);
      }
    }
  }

  /// 全表按 id 找到记录所在的桶键（找不到返回 null）。
  /// 用于跨桶清理：record.date 与桶键可能不一致（历史脏数据）。
  String? _recordDateForId(String recordId) {
    for (final entry in _appData.recordsByDate.entries) {
      if (entry.value.any((r) => r.id == recordId)) return entry.key;
    }
    return null;
  }

  /// 某条记录是否由"考勤同步"自动生成（备注带同步标记）。
  /// 只有这类记录允许被考勤侧联动删除；老师手工录入的一律保留。
  /// 在 [date] 桶（找不到时按 [altDate] 桶兜底）内判断某条记录是否
  /// "考勤同步"自动生成的派生记录（remark 标记"考勤同步"）。
  bool _isAttendanceGeneratedRecord(String date, String recordId,
      [String? altDate]) {
    for (final bucket in {date, if (altDate != null && altDate != date) altDate}) {
      final records = _appData.recordsByDate[bucket];
      if (records == null) continue;
      for (final record in records) {
        if (record.id == recordId) {
          return record.remark == AppDataProvider.attendanceSyncMarker;
        }
      }
    }
    return false;
  }
}

/// 班级数据总 provider：域 mixin 提供各功能域方法，static 常量与裁剪
/// 工具（[maxNameLength] 等）必须留在本类——static 不被 mixin/继承
/// 暴露，外部 `AppDataProvider.clipReason` 的引用全部指向这里。
///
/// 同时实现 [AppDataReader]（审查 H5）：桌面服务依赖该接口而非
/// 本具体类，services 层不再反向 import providers。
class AppDataProvider extends _ProviderBase
    with
        _RecordsDomain,
        _SettingsDomain,
        _ImportRestoreDomain,
        _AttendanceDomain,
        _ExportBackupDomain,
        _RosterDomain
    implements AppDataReader {
  /// 同步生成的批评记录在备注里留下的标记（便于教师识别来源）。
  static const String attendanceSyncMarker = '考勤同步';

  /// 单个原因/映射值的净化（P2-6：原因库与同步映射的入口统一走它）。
  /// B-3：同时限制长度——原因是"顿号拼接存储"，超长文本会放大该设计的代价。
  static const int maxReasonLength = RecordText.maxReasonLength;

  /// 单条原因的裁剪（与 [_sanitizeReasonText] 的截断口径一致，供记录侧复用）。
  static String clipReason(String reason) => RecordText.clipReason(reason);

  /// B-3（N-2）：学生姓名与备注的长度上限。
  /// 姓名与备注是**全程序统一口径**：新增/编辑/导入/改名/考勤同步等
  /// **所有**写入路径都必须经过 [clipStudentName] / [clipRemark]，
  /// 不允许任何一处手写 `StudentRecord(...)` 绕过（曾因此出现"新增截断、
  /// 编辑与导入不截断"的两种规则并存）。名单侧 [addStudent] 也用 [maxNameLength]，
  /// 否则名单里的名字与记录里的名字会不相等，考勤会把该生算成"名单外学生"。
  ///
  /// 注：**原因**的长度口径不同——见 [_sanitizeReasonList] 的 `clip` 说明
  /// （只对"新录入/编辑"裁剪，搬运既有数据时原样保留）。R-2 之前这里的注释
  /// 把原因也写成"全程序统一截断"，与实际实现不符，已更正。
  static const int maxNameLength = RecordText.maxNameLength;
  static const int maxRemarkLength = RecordText.maxRemarkLength;

  /// 姓名裁剪（全程序统一入口）。
  static String clipStudentName(String name) => RecordText.clipName(name);

  /// 备注裁剪（全程序统一入口）。
  static String clipRemark(String remark) => RecordText.clipRemark(remark);

  /// 备份文件名前缀：实际文件形如 `班级管理系统_备份_20260930_1838.enc`。
  static const String backupFilePrefix = '班级管理系统_备份';

  /// 自动保留的备份份数：超出后自动删除最旧的（可在"从备份恢复"里选择任意一份）。
  static const int backupKeepCount = 10;

  /// 名单姓名校验（N-3）：与记录侧同一上限，避免"名单里的名字 ≠ 记录里的名字"。
  /// 返回 null 表示通过，否则返回给界面直接显示的原因。
  static String? validateStudentName(String name) {
    final value = name.trim();
    if (value.isEmpty) return '姓名不能为空';
    if (value.length > AppDataProvider.maxNameLength) {
      return '姓名不能超过 ${AppDataProvider.maxNameLength} 个字（当前 ${value.length} 个字）';
    }
    return null;
  }
}
