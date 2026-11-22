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

import 'attendance_record.dart';
import 'identity.dart';
import '../constants/time_periods.dart';

import '../utils/app_date.dart';
// N-5：只依赖零 Flutter 依赖的错误通道，避免数据层反向依赖 UI 层。

/// 主题模式：浅色 / 深色 / 跟随系统
enum ThemeModeType { light, dark, system }

/// 关闭窗口时的行为：每次询问 / 直接退出程序 / 最小化到托盘 / 最小化到悬浮球
/// （枚举值顺序即持久化索引，新增项只能追加，不能插入到中间）
enum CloseActionType { ask, exit, minimizeToTray, minimizeToBall }

/// 启动时的窗口状态：记住上次（含是否最大化）/ 每次默认大小 / 启动即最大化
enum StartupWindowMode { remember, defaultSize, maximized }

/// 开机自启动后进入：系统托盘 / 桌面悬浮球
/// （枚举值顺序即持久化索引，新增项只能追加）
enum StartupTarget { tray, ball }

/// 自动备份频率：仅手动 / 每次退出 / 每天 / 每 3 天 / 每周
/// （枚举值顺序即持久化索引，新增项只能追加）
enum BackupFrequency { manual, onExit, daily, everyThreeDays, weekly }

/// 用户设置：主题模式、关闭窗口行为、悬浮球位置、导出路径与管理密码。
class AppSettings {
  final ThemeModeType themeMode;
  final String exportPath;
  final CloseActionType closeAction;

  /// 悬浮球上次停留位置（屏幕物理像素）；-1 表示尚未设置，首次显示在屏幕右下角。
  final int ballX;
  final int ballY;

  /// 管理密码的 SHA-256 哈希；空字符串表示使用出厂默认密码。
  final String passwordHash;

  /// 找回密码用的恢复码哈希（空 = 未设置）。
  /// 只存加盐哈希，不存明文；成功使用一次后清空。
  final String recoveryCodeHash;

  /// 恢复码创建日期（yyyy-MM-dd，仅用于界面提示，不做过期判断）。
  final String recoveryCodeCreatedAt;

  /// 是否已设置恢复码。
  bool get recoveryCodeEnabled => recoveryCodeHash.isNotEmpty;

  /// 启动时的窗口状态。
  final StartupWindowMode startupWindowMode;

  /// 上次退出时的窗口大小与位置（逻辑像素）；-1 表示尚未记录。
  final int windowX;
  final int windowY;
  final int windowWidth;
  final int windowHeight;

  /// 上次退出时窗口是否处于最大化。
  final bool windowMaximized;

  /// 备份文件保存目录；空字符串表示文档目录下的"班级管理系统\备份"。
  final String backupPath;

  /// 自动备份频率（默认每天一次）。
  final BackupFrequency backupFrequency;

  /// 自动备份保留份数（3-50，默认 10）。
  final int backupKeepCount;
  static const int defaultBackupKeepCount = 10;
  static const int minBackupKeepCount = 3;
  static const int maxBackupKeepCount = 50;

  /// 上次备份日期（yyyy-MM-dd）；空表示从未备份。
  final String backupLastAt;

  /// 自定义时段列表（可增删）：[{key, label}, ...]；空表示出厂 9 段。
  final List<Map<String, String>> periods;

  /// 记录对话框默认操作类型：0=表扬 1=批评 2=上次用过的。
  final int recordDefaultType;

  /// 上次记录使用的操作类型（0=表扬 1=批评），供"上次用过的"默认值使用。
  final int lastOperationType;

  /// 记录对话框是否按当前时刻自动预选时段。
  final bool autoSelectPeriod;

  /// 是否启用管理密码（总开关）。
  final bool passwordEnabled;

  /// 开机自动启动（随 Windows 启动）。
  final bool autoStart;

  /// 开机自启动后进入托盘还是悬浮球（autoStart 为 false 时仅作下次的偏好）。
  final StartupTarget startupTarget;

  /// 界面整体字号缩放（0.85~1.3，1.0 为标准）。
  final double uiScale;

  /// 是否启用"表扬"记录（关闭后记录对话框不再提供表扬）。
  final bool praiseEnabled;

  /// 是否启用"批评"记录（关闭后记录对话框不再提供批评）。
  final bool criticismEnabled;

  /// 原因是否按使用频率自动排序（关闭 = 按原因库里的手动顺序）。
  final bool reasonSortByUsage;

  /// 统计看板上次使用的区间：0=本周 1=本月 2=自定义 3=近7天 4=近30天
  /// 5=本学期 6=全部记录。
  final int statisticsRange;

  /// 上次自定义区间的起止（yyyy-MM-dd）。
  final String statisticsRangeStart;
  final String statisticsRangeEnd;

  /// 导出文件名前缀（可为空）。
  final String exportFilePrefix;

  /// 记录导出包含的列（键：date/name/type/reason/period/time/remark）。
  final List<String> recordExportColumns;

  /// 是否启用考勤功能（默认关闭）。
  final bool attendanceEnabled;

  /// 可选考勤状态（如 迟到/早退/请假/缺勤），可在设置中增删改名。
  final List<String> attendanceStatuses;

  /// 哪些状态算"未到"（减少"实到"人数，如 请假/缺勤；迟到/早退不算）。
  final List<String> attendanceAbsentStatuses;

  /// 考勤状态 → 批评原因的同步映射（空值表示该状态不生成批评记录）。
  final Map<String, String> attendanceSyncMap;

  /// 每周起始日：1=周一 2=周二 … 6=周六 7=周日（默认周一）。
  final int weekStart;

  /// "需关注学生"的批评次数阈值（按区间长度分三档，均可调）：
  /// 一周（本周 / 近 7 天）默认 3 次；一个月（本月 / 近 30 天）默认 8 次；
  /// 一学期及以上（本学期 / 全部记录）默认 20 次。
  final int attentionThreshold;
  final int attentionMonthThreshold;
  final int attentionSemesterThreshold;

  /// 统计排行显示条数：表扬 / 批评 / 考勤异常三个排行共用（默认 10）。
  final int rankingTopN;

  /// 悬浮球不透明度（0.35–1.0，默认 0.88）。
  final double ballOpacity;

  /// 是否锁定悬浮球位置：锁定后左键拖动不会移动球。
  final bool ballPositionLocked;

  /// 悬浮球不透明度范围与出厂默认值。
  static const double minBallOpacity = 0.35;
  static const double maxBallOpacity = 1.0;
  static const double defaultBallOpacity = 0.88;

  /// 顶栏天气地区（Open-Meteo）：城市名称为空表示尚未设置。
  final String weatherCityName;
  final String weatherCityAdmin;
  final double weatherLatitude;
  final double weatherLongitude;

  /// 是否在顶栏显示天气（默认关闭，关闭时不请求天气服务）。
  final bool showWeather;

  /// 是否在主页学生网格上方显示姓名搜索框（默认开启）。
  final bool studentSearchEnabled;

  /// 启动时是否自动检查 GitHub 上的正式发布版本（默认开启）。
  final bool checkUpdateOnStartup;

  /// 用户选择“跳过此版本”时记录的版本号（空表示没有跳过）。
  final String skippedUpdateTag;

  /// 是否启用“操作身份”：默认关闭；关闭时隐藏身份入口、不写记录人。
  final bool identityFeatureEnabled;

  /// 可选的操作身份列表（班主任固定保留）。
  final List<Identity> identities;

  /// 非班主任身份闲置多少分钟后自动退出；0 表示不自动退出。
  final int identityIdleMinutes;

  /// 是否启用“记录人署名 + 班主任管理”。关闭时保持旧的身份/权限行为。
  /// 一次班主任管理的保持时长（分钟）。
  final int managementSessionMinutes;

  /// 记录人可修改/删除自己记录的时长（分钟）；0 表示关闭本人窗口。
  final int selfEditWindowMinutes;

  static const int defaultIdentityIdleMinutes = 5;
  static const int defaultManagementSessionMinutes = 15;
  static const int defaultSelfEditWindowMinutes = 10;

  static const List<int> managementSessionMinuteOptions = [5, 10, 15, 30, 60];
  static const List<int> selfEditWindowMinuteOptions = [0, 5, 10, 15, 30, 60];

  /// 闲置时长的可选值（最后一项 0 = 不自动退出）。
  static const List<int> identityIdleMinuteOptions = [1, 3, 5, 10, 15, 30, 0];

  AppSettings({
    required this.themeMode,
    this.exportPath = '',
    this.closeAction = CloseActionType.ask,
    this.ballX = -1,
    this.ballY = -1,
    this.passwordHash = '',
    this.recoveryCodeHash = '',
    this.recoveryCodeCreatedAt = '',
    this.startupWindowMode = StartupWindowMode.remember,
    this.windowX = -1,
    this.windowY = -1,
    this.windowWidth = -1,
    this.windowHeight = -1,
    this.windowMaximized = false,
    this.backupPath = '',
    this.backupFrequency = BackupFrequency.daily,
    this.backupKeepCount = defaultBackupKeepCount,
    this.backupLastAt = '',
    this.periods = const [],
    this.recordDefaultType = 1,
    this.lastOperationType = 0,
    this.autoSelectPeriod = true,
    this.passwordEnabled = false,
    this.autoStart = false,
    this.startupTarget = StartupTarget.tray,
    this.uiScale = 1.0,
    this.praiseEnabled = true,
    this.criticismEnabled = true,
    this.reasonSortByUsage = false,
    this.statisticsRange = 0,
    this.statisticsRangeStart = '',
    this.statisticsRangeEnd = '',
    this.exportFilePrefix = '',
    this.recordExportColumns = defaultRecordExportColumns,
    this.attendanceEnabled = false,
    this.attendanceStatuses = defaultAttendanceStatuses,
    this.attendanceAbsentStatuses = defaultAttendanceAbsentStatuses,
    this.attendanceSyncMap = defaultAttendanceSyncMap,
    this.weekStart = 1,
    this.attentionThreshold = defaultAttentionThreshold,
    this.attentionMonthThreshold = defaultAttentionMonthThreshold,
    this.attentionSemesterThreshold = defaultAttentionSemesterThreshold,
    this.rankingTopN = defaultRankingTopN,
    this.ballOpacity = defaultBallOpacity,
    this.ballPositionLocked = false,
    this.weatherCityName = '',
    this.weatherCityAdmin = '',
    this.weatherLatitude = 0,
    this.weatherLongitude = 0,
    this.showWeather = false,
    this.studentSearchEnabled = true,
    this.checkUpdateOnStartup = true,
    this.skippedUpdateTag = '',
    this.identityFeatureEnabled = false,
    this.identities = Identity.defaults,
    this.identityIdleMinutes = defaultIdentityIdleMinutes,
    this.managementSessionMinutes = defaultManagementSessionMinutes,
    this.selfEditWindowMinutes = defaultSelfEditWindowMinutes,
  });

  /// "需关注学生"阈值的取值范围与出厂默认值：
  /// 一周 1–20（默认 3）、一个月 1–40（默认 8）、一学期 1–100（默认 20）。
  static const int minAttentionThreshold = 1;
  static const int maxAttentionThreshold = 20;
  static const int defaultAttentionThreshold = 3;
  static const int minAttentionMonthThreshold = 1;
  static const int maxAttentionMonthThreshold = 40;
  static const int defaultAttentionMonthThreshold = 8;
  static const int minAttentionSemesterThreshold = 1;
  static const int maxAttentionSemesterThreshold = 100;
  static const int defaultAttentionSemesterThreshold = 20;

  /// 排行条数的取值范围与出厂默认值（三个排行共用，3–50，默认 10）。
  static const int minRankingTopN = 3;
  static const int maxRankingTopN = 50;
  static const int defaultRankingTopN = 10;

  /// 出厂同步映射：迟到/早退同步同名批评原因，缺勤同步"旷课"；
  /// 请假等合理缺勤不生成批评记录。
  static const Map<String, String> defaultAttendanceSyncMap = {
    '迟到': '迟到',
    '早退': '早退',
    '缺勤': '旷课',
  };

  /// 记录导出的全部列（顺序即导出顺序）。
  static const List<String> defaultRecordExportColumns = [
    'date',
    'name',
    'type',
    'reason',
    'period',
    'time',
    'remark',
  ];

  /// 记录导出列的中文标题。
  static const Map<String, String> recordExportColumnTitles = {
    'date': '日期',
    'name': '学生姓名',
    'type': '操作项目',
    'reason': '原因',
    'period': '时间段',
    'time': '时间',
    'remark': '备注',
    'recordedBy': '记录人',
  };

  /// 出厂"计入未到"的状态：请假 / 缺勤（迟到、早退是"到了但不合规范"，不减实到）。
  static const List<String> defaultAttendanceAbsentStatuses = ['请假', '缺勤'];

  /// 按状态名推断是否算"未到"：名称里含"假"或"缺"的视为未到
  /// （新增自定义状态项时的默认值，可在"设置 → 时间与考勤 → 考勤"里逐个改）。
  static bool guessAbsentByName(String status) {
    final value = status.trim();
    return value.contains('假') || value.contains('缺');
  }

  /// 出厂考勤状态（与 AttendanceRecord.defaultStatuses 保持一致）。
  static const List<String> defaultAttendanceStatuses = [
    '迟到',
    '早退',
    '请假',
    '缺勤',
  ];

  /// 复制并替换部分字段：新增字段时各处调用无需逐个补齐，避免漏字段。
  AppSettings copyWith({
    ThemeModeType? themeMode,
    String? exportPath,
    CloseActionType? closeAction,
    int? ballX,
    int? ballY,
    String? passwordHash,
    String? recoveryCodeHash,
    String? recoveryCodeCreatedAt,
    StartupWindowMode? startupWindowMode,
    int? windowX,
    int? windowY,
    int? windowWidth,
    int? windowHeight,
    bool? windowMaximized,
    String? backupPath,
    BackupFrequency? backupFrequency,
    int? backupKeepCount,
    String? backupLastAt,
    List<Map<String, String>>? periods,
    int? recordDefaultType,
    int? lastOperationType,
    bool? autoSelectPeriod,
    bool? passwordEnabled,
    bool? autoStart,
    StartupTarget? startupTarget,
    double? uiScale,
    bool? praiseEnabled,
    bool? criticismEnabled,
    bool? reasonSortByUsage,
    int? statisticsRange,
    String? statisticsRangeStart,
    String? statisticsRangeEnd,
    String? exportFilePrefix,
    List<String>? recordExportColumns,
    bool? attendanceEnabled,
    List<String>? attendanceStatuses,
    List<String>? attendanceAbsentStatuses,
    Map<String, String>? attendanceSyncMap,
    int? weekStart,
    int? attentionThreshold,
    int? attentionMonthThreshold,
    int? attentionSemesterThreshold,
    int? rankingTopN,
    double? ballOpacity,
    bool? ballPositionLocked,
    String? weatherCityName,
    String? weatherCityAdmin,
    double? weatherLatitude,
    double? weatherLongitude,
    bool? showWeather,
    bool? studentSearchEnabled,
    bool? checkUpdateOnStartup,
    String? skippedUpdateTag,
    bool? identityFeatureEnabled,
    List<Identity>? identities,
    int? identityIdleMinutes,
    int? managementSessionMinutes,
    int? selfEditWindowMinutes,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      exportPath: exportPath ?? this.exportPath,
      closeAction: closeAction ?? this.closeAction,
      ballX: ballX ?? this.ballX,
      ballY: ballY ?? this.ballY,
      passwordHash: passwordHash ?? this.passwordHash,
      recoveryCodeHash: recoveryCodeHash ?? this.recoveryCodeHash,
      recoveryCodeCreatedAt:
          recoveryCodeCreatedAt ?? this.recoveryCodeCreatedAt,
      startupWindowMode: startupWindowMode ?? this.startupWindowMode,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      windowMaximized: windowMaximized ?? this.windowMaximized,
      backupPath: backupPath ?? this.backupPath,
      backupFrequency: backupFrequency ?? this.backupFrequency,
      backupKeepCount: backupKeepCount ?? this.backupKeepCount,
      backupLastAt: backupLastAt ?? this.backupLastAt,
      periods: periods ?? this.periods,
      recordDefaultType: recordDefaultType ?? this.recordDefaultType,
      lastOperationType: lastOperationType ?? this.lastOperationType,
      autoSelectPeriod: autoSelectPeriod ?? this.autoSelectPeriod,
      passwordEnabled: passwordEnabled ?? this.passwordEnabled,
      autoStart: autoStart ?? this.autoStart,
      startupTarget: startupTarget ?? this.startupTarget,
      uiScale: uiScale ?? this.uiScale,
      praiseEnabled: praiseEnabled ?? this.praiseEnabled,
      criticismEnabled: criticismEnabled ?? this.criticismEnabled,
      reasonSortByUsage: reasonSortByUsage ?? this.reasonSortByUsage,
      statisticsRange: statisticsRange ?? this.statisticsRange,
      statisticsRangeStart: statisticsRangeStart ?? this.statisticsRangeStart,
      statisticsRangeEnd: statisticsRangeEnd ?? this.statisticsRangeEnd,
      exportFilePrefix: exportFilePrefix ?? this.exportFilePrefix,
      recordExportColumns: recordExportColumns ?? this.recordExportColumns,
      attendanceEnabled: attendanceEnabled ?? this.attendanceEnabled,
      attendanceStatuses: attendanceStatuses ?? this.attendanceStatuses,
      attendanceAbsentStatuses:
          attendanceAbsentStatuses ?? this.attendanceAbsentStatuses,
      attendanceSyncMap: attendanceSyncMap ?? this.attendanceSyncMap,
      weekStart: weekStart ?? this.weekStart,
      attentionThreshold: attentionThreshold ?? this.attentionThreshold,
      attentionMonthThreshold:
          attentionMonthThreshold ?? this.attentionMonthThreshold,
      attentionSemesterThreshold:
          attentionSemesterThreshold ?? this.attentionSemesterThreshold,
      rankingTopN: rankingTopN ?? this.rankingTopN,
      ballOpacity: ballOpacity ?? this.ballOpacity,
      ballPositionLocked: ballPositionLocked ?? this.ballPositionLocked,
      weatherCityName: weatherCityName ?? this.weatherCityName,
      weatherCityAdmin: weatherCityAdmin ?? this.weatherCityAdmin,
      weatherLatitude: weatherLatitude ?? this.weatherLatitude,
      weatherLongitude: weatherLongitude ?? this.weatherLongitude,
      showWeather: showWeather ?? this.showWeather,
      studentSearchEnabled:
          studentSearchEnabled ?? this.studentSearchEnabled,
      checkUpdateOnStartup:
          checkUpdateOnStartup ?? this.checkUpdateOnStartup,
      skippedUpdateTag: skippedUpdateTag ?? this.skippedUpdateTag,
      identityFeatureEnabled:
          identityFeatureEnabled ?? this.identityFeatureEnabled,
      identities: identities ?? this.identities,
      identityIdleMinutes:
          identityIdleMinutes ?? this.identityIdleMinutes,
      managementSessionMinutes:
          managementSessionMinutes ?? this.managementSessionMinutes,
      selfEditWindowMinutes:
          selfEditWindowMinutes ?? this.selfEditWindowMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    // 使用 index 而非 name 序列化，避免代码混淆后枚举名被重命名导致解析失败。
    return {
      'themeMode': themeMode.index,
      'exportPath': exportPath,
      'closeAction': closeAction.index,
      'ballX': ballX,
      'ballY': ballY,
      'passwordHash': passwordHash,
      'recoveryCodeHash': recoveryCodeHash,
      'recoveryCodeCreatedAt': recoveryCodeCreatedAt,
      'startupWindowMode': startupWindowMode.index,
      'windowX': windowX,
      'windowY': windowY,
      'windowWidth': windowWidth,
      'windowHeight': windowHeight,
      'windowMaximized': windowMaximized,
      'backupPath': backupPath,
      'backupFrequency': backupFrequency.index,
      'backupKeepCount': backupKeepCount,
      'backupLastAt': backupLastAt,
      'periods': periods,
      'recordDefaultType': recordDefaultType,
      'lastOperationType': lastOperationType,
      'autoSelectPeriod': autoSelectPeriod,
      'passwordEnabled': passwordEnabled,
      'autoStart': autoStart,
      'startupTarget': startupTarget.index,
      'uiScale': uiScale,
      'praiseEnabled': praiseEnabled,
      'criticismEnabled': criticismEnabled,
      'reasonSortByUsage': reasonSortByUsage,
      'statisticsRange': statisticsRange,
      'statisticsRangeStart': statisticsRangeStart,
      'statisticsRangeEnd': statisticsRangeEnd,
      'exportFilePrefix': exportFilePrefix,
      'recordExportColumns': recordExportColumns,
      'attendanceEnabled': attendanceEnabled,
      'attendanceStatuses': attendanceStatuses,
      'attendanceAbsentStatuses': attendanceAbsentStatuses,
      'attendanceSyncMap': attendanceSyncMap,
      'weekStart': weekStart,
      'attentionThreshold': attentionThreshold,
      'attentionMonthThreshold': attentionMonthThreshold,
      'attentionSemesterThreshold': attentionSemesterThreshold,
      'rankingTopN': rankingTopN,
      'ballOpacity': ballOpacity,
      'ballPositionLocked': ballPositionLocked,
      'weatherCityName': weatherCityName,
      'weatherCityAdmin': weatherCityAdmin,
      'weatherLatitude': weatherLatitude,
      'weatherLongitude': weatherLongitude,
      'showWeather': showWeather,
      'studentSearchEnabled': studentSearchEnabled,
      'checkUpdateOnStartup': checkUpdateOnStartup,
      'skippedUpdateTag': skippedUpdateTag,
      'identityFeatureEnabled': identityFeatureEnabled,
      'identities': [for (final identity in identities) identity.toJson()],
      'identityIdleMinutes': identityIdleMinutes,
      'managementSessionMinutes': managementSessionMinutes,
      'selfEditWindowMinutes': selfEditWindowMinutes,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: _parseThemeMode(json['themeMode']),
      exportPath: (json['exportPath'] ?? '').toString(),
      closeAction: _parseCloseAction(json['closeAction']),
      ballX: _parseCoordinate(json['ballX']),
      ballY: _parseCoordinate(json['ballY']),
      passwordHash: _parsePasswordHash(json['passwordHash']),
      recoveryCodeHash: _parsePasswordHash(json['recoveryCodeHash']),
      recoveryCodeCreatedAt:
          _parseDateText(json['recoveryCodeCreatedAt']),
      startupWindowMode: _parseStartupWindowMode(json['startupWindowMode']),
      windowX: _parseCoordinate(json['windowX']),
      windowY: _parseCoordinate(json['windowY']),
      windowWidth: _parseCoordinate(json['windowWidth']),
      windowHeight: _parseCoordinate(json['windowHeight']),
      windowMaximized: json['windowMaximized'] == true,
      backupPath: (json['backupPath'] ?? '').toString(),
      backupFrequency: _parseBackupFrequency(json['backupFrequency']),
      backupKeepCount: _parseBackupKeepCount(json['backupKeepCount']),
      backupLastAt: (json['backupLastAt'] ?? '').toString(),
      periods: _parsePeriodList(json['periods']),
      recordDefaultType: _parseChoice(json['recordDefaultType'], 3, fallback: 1),
      lastOperationType: _parseChoice(json['lastOperationType'], 2),
      autoSelectPeriod: json['autoSelectPeriod'] != false,
      passwordEnabled: json['passwordEnabled'] == true,
      autoStart: json['autoStart'] == true,
      startupTarget: _parseStartupTarget(json['startupTarget']),
      uiScale: _parseUiScale(json['uiScale']),
      praiseEnabled: json['praiseEnabled'] != false,
      criticismEnabled: json['criticismEnabled'] != false,
      reasonSortByUsage: json['reasonSortByUsage'] == true,
      // 修复（审计 P1-6）：区间枚举共 7 项（含"全部记录"=6），此前只放行 0-5，
      // 选"全部记录"后重启会被回退成"本周"。
      statisticsRange: _parseChoice(json['statisticsRange'], 7),
      statisticsRangeStart: _parseDateText(json['statisticsRangeStart']),
      statisticsRangeEnd: _parseDateText(json['statisticsRangeEnd']),
      exportFilePrefix: (json['exportFilePrefix'] ?? '').toString(),
      recordExportColumns: _parseKeyList(
        json['recordExportColumns'],
        defaultRecordExportColumns,
        extra: const ['recordedBy'],
      ),
      attendanceEnabled: json['attendanceEnabled'] == true,
      attendanceStatuses: _parseStatusList(json['attendanceStatuses']),
      attendanceAbsentStatuses: _parseAbsentStatuses(
        json['attendanceAbsentStatuses'],
        _parseStatusList(json['attendanceStatuses']),
      ),
      attendanceSyncMap: _parseSyncMap(json['attendanceSyncMap']),
      weekStart: _parseWeekStart(json['weekStart']),
      attentionThreshold: _parseRange(
        json['attentionThreshold'],
        minAttentionThreshold,
        maxAttentionThreshold,
        defaultAttentionThreshold,
      ),
      attentionMonthThreshold: _parseRange(
        json['attentionMonthThreshold'],
        minAttentionMonthThreshold,
        maxAttentionMonthThreshold,
        defaultAttentionMonthThreshold,
      ),
      attentionSemesterThreshold: _parseRange(
        json['attentionSemesterThreshold'],
        minAttentionSemesterThreshold,
        maxAttentionSemesterThreshold,
        defaultAttentionSemesterThreshold,
      ),
      rankingTopN: _parseRange(
        json['rankingTopN'],
        minRankingTopN,
        maxRankingTopN,
        defaultRankingTopN,
      ),
      ballOpacity: _parseDouble(
        json['ballOpacity'],
        minBallOpacity,
        maxBallOpacity,
        defaultBallOpacity,
      ),
      ballPositionLocked: json['ballPositionLocked'] == true,
      weatherCityName: (json['weatherCityName'] ?? '').toString(),
      weatherCityAdmin: (json['weatherCityAdmin'] ?? '').toString(),
      weatherLatitude: _parseWeatherCoordinate(json['weatherLatitude'], -90, 90),
      weatherLongitude:
          _parseWeatherCoordinate(json['weatherLongitude'], -180, 180),
      showWeather: json['showWeather'] == true,
      studentSearchEnabled: json['studentSearchEnabled'] != false,
      checkUpdateOnStartup: json['checkUpdateOnStartup'] != false,
      skippedUpdateTag: (json['skippedUpdateTag'] ?? '').toString(),
      identityFeatureEnabled: json['identityFeatureEnabled'] == true,
      identities: _parseIdentities(json['identities']),
      identityIdleMinutes:
          _parseIdentityIdleMinutes(json['identityIdleMinutes']),
      managementSessionMinutes: _parseManagementSessionMinutes(
        json['managementSessionMinutes'],
      ),
      selfEditWindowMinutes: _parseSelfEditWindowMinutes(
        json['selfEditWindowMinutes'],
      ),
    );
  }

  /// 身份列表：损坏/为空时回退出厂列表，并保证班主任身份固定存在且唯一。
  static List<Identity> _parseIdentities(dynamic value) {
    final parsed = <Identity>[];
    var headTeacherNickname = '';
    if (value is List) {
      for (final item in value) {
        if (item is! Map) continue;
        final identity = Identity.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (identity.id.isEmpty || identity.name.isEmpty) continue;
        if (identity.isHeadTeacher ||
            identity.id == Identity.defaultHeadTeacher.id) {
          headTeacherNickname = identity.nickname;
          continue;
        }
        if (parsed.any((existing) => existing.id == identity.id)) continue;
        parsed.add(identity);
      }
    }
    return [
      Identity.defaultHeadTeacher.copyWith(nickname: headTeacherNickname),
      ...parsed,
    ];
  }

  static int _parseManagementSessionMinutes(dynamic value) {
    if (value is int && managementSessionMinuteOptions.contains(value)) {
      return value;
    }
    return defaultManagementSessionMinutes;
  }

  static int _parseSelfEditWindowMinutes(dynamic value) {
    if (value is int && selfEditWindowMinuteOptions.contains(value)) {
      return value;
    }
    return defaultSelfEditWindowMinutes;
  }

  static int _parseIdentityIdleMinutes(dynamic value) {
    if (value is int && identityIdleMinuteOptions.contains(value)) {
      return value;
    }
    return defaultIdentityIdleMinutes;
  }

  /// 天气坐标：类型/范围不合法时回退到 0（城市名为空时不会发起天气请求）。
  static double _parseWeatherCoordinate(
    dynamic value,
    double min,
    double max,
  ) {
    if (value is num) {
      final coordinate = value.toDouble();
      if (coordinate >= min && coordinate <= max) return coordinate;
    }
    return 0;
  }

  /// 限定取值范围的整数设置：类型不对或超出范围时回退为出厂默认值。
  static int _parseRange(dynamic value, int min, int max, int fallback) {
    if (value is int && value >= min && value <= max) return value;
    return fallback;
  }

  /// 解析小数设置（悬浮球不透明度）：越界或类型不对时用出厂默认。
  static double _parseDouble(
    dynamic value,
    double min,
    double max,
    double fallback,
  ) {
    final parsed = value is num ? value.toDouble() : null;
    if (parsed == null || parsed < min || parsed > max) return fallback;
    return parsed;
  }

  /// "计入未到"的状态列表：只保留状态项里存在的名称；
  /// 字段缺失（旧数据）时按名称启发式推断默认值。
  static List<String> _parseAbsentStatuses(
    dynamic value,
    List<String> statuses,
  ) {
    if (value is List) {
      final list = <String>[];
      for (final item in value) {
        if (item is! String) continue;
        final status = item.trim();
        if (status.isEmpty || !statuses.contains(status)) continue;
        if (!list.contains(status)) list.add(status);
      }
      return list;
    }
    return [
      for (final status in statuses)
        if (guessAbsentByName(status)) status,
    ];
  }

  /// 界面字号：限制在 0.85~1.3，非法值回退 1.0。
  static double _parseUiScale(dynamic value) {
    if (value is num) {
      final scale = value.toDouble();
      if (scale >= 0.85 && scale <= 1.3) return scale;
    }
    return 1.0;
  }

  /// 日期文本：只接受真实存在的 yyyy-MM-dd（N1 修复：此前只查形状，
  /// 2026-13-45 会被当作合法的统计区间），其它回退空字符串。
  static String _parseDateText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (isValidYmdDate(text)) return text;
    return '';
  }

  /// 导出列键列表：只保留白名单内的键且不重复；
  /// 缺失或全部非法时回退为默认全集。
  static List<String> _parseKeyList(
    dynamic value,
    List<String> defaults, {
    List<String> extra = const [],
  }) {
    final allowed = [...defaults, ...extra];
    if (value is List) {
      final seen = <String>{};
      for (final item in value) {
        if (item is! String) continue;
        if (!allowed.contains(item) || !seen.add(item)) continue;
      }
      // 保持固定顺序，导出时的列序与表序始终稳定。
      if (seen.isNotEmpty) {
        return [
          for (final key in allowed)
            if (seen.contains(key)) key,
        ];
      }
    }
    return defaults;
  }

  /// 考勤状态列表：只接受非空字符串，跳过"出勤"（保留词）并去重；
  /// 缺失或全部非法时回退出厂状态。
  static List<String> _parseStatusList(dynamic value) {
    if (value is List) {
      final seen = <String>{};
      final list = <String>[];
      for (final item in value) {
        if (item is! String) continue;
        final status = item.trim();
        if (status.isEmpty ||
            status == AttendanceRecord.presentStatus ||
            !seen.add(status)) {
          continue;
        }
        list.add(status);
      }
      if (list.isNotEmpty) return list;
    }
    return defaultAttendanceStatuses;
  }

  /// 同步映射：只保留"字符串→非空字符串"的条目；字段缺失时用出厂映射。
  static Map<String, String> _parseSyncMap(dynamic value) {
    if (value is! Map) return defaultAttendanceSyncMap;
    final map = <String, String>{};
    value.forEach((key, val) {
      if (key is! String || val is! String) return;
      final status = key.trim();
      final reason = val.trim();
      if (status.isNotEmpty && reason.isNotEmpty) map[status] = reason;
    });
    return map;
  }

  /// 每周起始日：1~7，非法或缺省回退周一。
  static int _parseWeekStart(dynamic value) {
    if (value is int && value >= 1 && value <= 7) return value;
    return 1;
  }

  /// 旧数据缺该字段时回退为"每天一次"。
  static BackupFrequency _parseBackupFrequency(dynamic value) {
    if (value is int && value >= 0 && value < BackupFrequency.values.length) {
      return BackupFrequency.values[value];
    }
    return BackupFrequency.daily;
  }

  static int _parseBackupKeepCount(dynamic value) {
    if (value is! int) return defaultBackupKeepCount;
    if (value < minBackupKeepCount) return minBackupKeepCount;
    if (value > maxBackupKeepCount) return maxBackupKeepCount;
    return value;
  }

  /// 旧版本数据没有该字段：回退为"记住上次"。
  static StartupTarget _parseStartupTarget(dynamic value) {
    if (value is int &&
        value >= 0 &&
        value < StartupTarget.values.length) {
      return StartupTarget.values[value];
    }
    return StartupTarget.tray;
  }

  static StartupWindowMode _parseStartupWindowMode(dynamic value) {
    if (value is int &&
        value >= 0 &&
        value < StartupWindowMode.values.length) {
      return StartupWindowMode.values[value];
    }
    return StartupWindowMode.remember;
  }

  /// 自定义时段列表：只接受 {key,label} 形式的条目。
  static List<Map<String, String>> _parsePeriodList(dynamic value) {
    if (value is! List) return const [];
    final periods = <Map<String, String>>[];
    // 修复（审计 P2-28）：与 sanitizePeriods 同口径 —— 标签必须通过与设置页
    // 相同的格式校验（validatePeriodLabel），且 key 去重（first-wins），
    // 避免落库的脏数据在运行时被静默丢弃、两处口径不一致。
    final seenKeys = <String>{};
    for (final item in value) {
      if (item is! Map) continue;
      final key = item['key'];
      final label = item['label'];
      if (key is! String || label is! String) continue;
      if (key.isEmpty || label.trim().isEmpty) continue;
      if (validatePeriodLabel(label) != null) continue;
      if (!seenKeys.add(key)) continue;
      periods.add({'key': key, 'label': label});
    }
    return periods;
  }

  /// 旧版本数据没有该字段：回退为空字符串（即出厂默认密码）。
  static String _parsePasswordHash(dynamic value) {
    if (value is String) return value;
    return '';
  }

  static CloseActionType _parseCloseAction(dynamic value) {
    if (value is int && value >= 0 && value < CloseActionType.values.length) {
      return CloseActionType.values[value];
    }
    return CloseActionType.ask;
  }

  /// 悬浮球坐标：非法或缺省一律回退为 -1（未设置）。
  static int _parseCoordinate(dynamic value) {
    if (value is int) return value;
    return -1;
  }

  /// 限定范围的整数选项：非法或缺省时回退为 0。
  static int _parseChoice(dynamic value, int optionCount, {int fallback = 0}) {
    if (value is int && value >= 0 && value < optionCount) return value;
    return fallback;
  }

  static ThemeModeType _parseThemeMode(dynamic value) {
    if (value is int &&
        value >= 0 &&
        value < ThemeModeType.values.length) {
      return ThemeModeType.values[value];
    }
    return ThemeModeType.system;
  }

  factory AppSettings.defaultSettings() {
    return AppSettings(
      themeMode: ThemeModeType.system,
    );
  }
}