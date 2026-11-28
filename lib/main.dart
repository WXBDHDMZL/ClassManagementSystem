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

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import './providers/app_data_provider.dart';
import './services/desktop_service.dart';
import './services/error_log_service.dart';
import './services/local_storage_paths.dart';
import './services/storage_service.dart';
import './services/operation_log_service.dart';
import './services/update_check_service.dart';
import './models/password_policy.dart';
import './widgets/header_bar.dart';
import './widgets/student_card.dart';
import './widgets/student_picker_dialog.dart';
import './widgets/record_dialog.dart';
import './widgets/record_list.dart';
import './widgets/history_dialog.dart';
import './widgets/statistics_dialog.dart';
import './widgets/app_notification.dart';
import './widgets/identity_guard.dart';
import './widgets/password_action_guard.dart';
import './widgets/change_password_dialog.dart';
import './widgets/settings_panel.dart';
import './widgets/startup_data_block_dialog.dart';
import './widgets/update_prompt_host.dart';
import './constants/app_theme.dart';
import './models/app_settings.dart';
import 'utils/day_rollover.dart';
import 'utils/grid_layout.dart';

/// 全局导航上下文：托盘与关闭询问在没有组件上下文时也要弹出对话框。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// X-20：把"系统字号缩放 × 应用界面字号"合成为最终 textScaler。
///
/// 抽成函数便于单测；此前直接 `TextScaler.linear(uiScale)` **覆盖**了系统缩放，
/// 用户在系统里调大字号对本程序无效。
TextScaler composeTextScaler(TextScaler system, double uiScale) =>
    TextScaler.linear(system.scale(1.0) * uiScale);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 把本程序自己的 AGPL 许可证也注册到 Flutter 的许可页，和第三方组件
  // 一起供用户查看；LICENSE.txt 通过 pubspec.yaml 的 assets 打进程序。
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['班级管理系统'], text);
  });
  // 数据目录固定为「文档/班级管理系统」；启动时先确保目录存在，
  // 避免全新安装或目录被删后，首次保存因父目录不存在而失败。
  try {
    await LocalStoragePaths.ensureRoot();
    // 先初始化本机数据密钥，再安装错误日志——日志本身也要用该密钥加密。
    await StorageService.initializeKey();
    // 运行期异常写入文档目录下的错误日志，便于排查"界面异常/黑屏"类问题。
    installErrorLog();
  } catch (e, s) {
    appendErrorLog('main', e, s, context: '启动：初始化数据密钥/创建数据目录');
  }
  // 发布模式下某个界面构建出错时，显示友好提示而不是灰色/红色错误面板——
  // 用户看到的是"这一页出了问题但数据安全"，而不是"程序崩了"。
  ErrorWidget.builder = (details) {
    // 错误可能发生在 MaterialApp 之外：自带 Directionality，避免友好页自身再抛错。
    return const Directionality(
    textDirection: TextDirection.ltr,
    child: Material(
      color: Color(0xFF263238),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.warningDark, size: 40),
              SizedBox(height: 12),
              Text(
                '这一页显示出了问题，但你的数据是安全的',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                '错误已记录，可返回上一页继续使用；'
                '若反复出现，请在"关于 → 查看操作日志"里查看详情。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  };
  final provider = AppDataProvider();
  // 先加载数据：窗口状态（记住上次 / 最大化）需要在窗口显示前应用。
  // initialize 内部已兜住数据加载失败；这里再兜一层，确保任何启动期异常
  // 都有日志可查，而不是程序无声退出（排查"双击没反应"的关键线索）。
  // 启动目标（--tray / --ball / CMS_STARTUP_TARGET）先行解析：
  // "隐藏启动"时绝不能先按记忆尺寸/最大化应用窗口后再隐藏（出现启动闪窗），
  // 见 R4 审计 P2-53。
  final startupArguments = Platform.executableArguments;
  final startupTarget = Platform.environment['CMS_STARTUP_TARGET'];
  final startsToBall =
      startupTarget == 'ball' || _startsToBall(startupArguments);
  final startsToTray =
      startupTarget == 'tray' || _startsToTray(startupArguments);
  final hiddenStartup = startsToBall || startsToTray;
  try {
    await provider.initialize();
  } catch (e, s) {
    appendErrorLog('main', e, s, context: '启动：数据初始化阶段（initialize）');
  }
  // 启动标记：写进操作日志，把日志按"一次一次运行"分段——
  // 排查"崩溃前做了什么"时先找到最近的启动标记，再往下看时间线。
  OperationLogService.log('程序启动', environmentLine());
  // 后台任务：按频率自动备份（不阻塞启动）。
  unawaited(provider.runScheduledBackup());
  // 桌面集成（系统托盘 + 关闭拦截 + 悬浮球）：初始化失败不影响主功能，
  // 窗口关闭行为回退为"直接退出程序"。
  try {
    await DesktopService.instance.initialize(
      provider: provider,
      navigatorKey: appNavigatorKey,
    );
    // 隐藏启动（--tray/--ball）时跳过"按记忆窗口应用尺寸/最大化"，
    // 避免托盘就绪前先弹出主窗口再隐藏（启动闪窗，审计 P2-53）。
    if (!hiddenStartup) {
      await DesktopService.instance.applyStartupWindowMode(
        provider.appData.settings,
      );
    }
    // 修复（审计 P1-25）：按设置校正开机启动项（外部删除/移动程序后
    // 注册表与实际保持一致），不阻塞启动。
    unawaited(DesktopService.reconcileAutoStart(
      provider.appData.settings.autoStart,
      provider.appData.settings.startupTarget,
    ));
  } catch (e) {
    debugPrint('桌面集成初始化失败，关闭窗口将直接退出程序：$e');
    appendErrorLog('main', e, StackTrace.current);
  }
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: provider)],
      child: const MyApp(),
    ),
  );

  // 启动时静默检查更新：不阻塞界面，有可用版本时在「关于」中提示。
  if (provider.appData.settings.checkUpdateOnStartup) {
    unawaited(UpdateCheckService.checkInBackground());
  }

  // 开机自启动：--tray 进托盘，--ball 直接进入悬浮球；两者原生首帧都不显示主窗口。
  // 这里不再等 Flutter 首帧回调 —— 窗口被原生隐藏时首帧回调可能不触发，
  // 会导致主窗口和悬浮球都不可见。启动目标只依赖窗口管理器与托盘，直接执行。
  // P2-14：托盘初始化失败时把主窗口显示出来，避免后台空跑、没有任何界面。
  if (hiddenStartup) {
    try {
      if (!DesktopService.instance.trayReady) {
        await DesktopService.instance.showMainWindow();
      } else if (startsToBall) {
        await DesktopService.instance.enterBallMode();
      } else {
        await DesktopService.instance.hideToTray();
      }
    } catch (e, s) {
      appendErrorLog('main', e, s, context: '开机启动目标（托盘/悬浮球）');
      await DesktopService.instance.showMainWindow();
    }
  }
}

/// 是否以"开机自启动"方式启动（由启动项的 `--tray` / `--ball` 参数决定）。
bool _startsToTray(List<String> arguments) =>
    arguments.contains('--tray');

bool _startsToBall(List<String> arguments) =>
    arguments.contains('--ball');

/// 滚动行为：允许触屏、鼠标、触控板、触控笔"按住拖动"滚动列表。
/// 一体机（触控屏）上如果没有这层配置，鼠标/触控板拖动会失效，只能用滚轮。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppNoticeController _notifications = AppNoticeController();

  @override
  void dispose() {
    _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 性能修复（H3）：此前这里用 Consumer<AppDataProvider> 订阅**整个** provider，
    // 任意数据变更（每条记录/考勤的增删改、自动备份等）都会重建整个 MaterialApp。
    // 本组件实际只用到两项设置，改为 context.select 精确订阅：非这两项变化时
    // 完全不再触发本树重建（子树内的页面各有自己的订阅，不受影响）。
    final themeMode = context.select<AppDataProvider, ThemeModeType>(
      (provider) => provider.appData.settings.themeMode,
    );
    final uiScale = context.select<AppDataProvider, double>(
      (provider) => provider.appData.settings.uiScale,
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      // 任意触摸/鼠标操作都重置操作身份与班主任管理的闲置计时。
      onPointerDown: (_) {
        final provider = context.read<AppDataProvider>();
        provider.touchIdentityActivity();
        provider.touchManagementActivity();
      },
      child: MaterialApp(
      title: '班级管理系统',
      navigatorKey: appNavigatorKey,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      scrollBehavior: const AppScrollBehavior(),
      // 界面字号整体缩放（设置 → 日常使用 → 外观与窗口）。
      // X-20 修复：**叠加**而不是覆盖系统字号 —— 此前 `TextScaler.linear`
      // 直接丢弃了系统无障碍字体缩放，系统调大字号对本程序无效。
      builder: (context, child) {
        final content = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: composeTextScaler(
              MediaQuery.textScalerOf(context),
              uiScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
        // 通知层放在 Navigator 外侧，确保永远盖在所有路由与对话框之上。
        return AppNotificationScope(
          controller: _notifications,
          child: AppNotificationHost(child: content),
        );
      },
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // 显式映射主题模式：不使用 byName，避免混淆后枚举名变化导致崩溃。
      themeMode: switch (themeMode) {
        ThemeModeType.light => ThemeMode.light,
        ThemeModeType.dark => ThemeMode.dark,
        ThemeModeType.system => ThemeMode.system,
      },
        home: const UpdatePromptHost(child: _RootPage()),
      ),
    );
  }
}

class _RootPage extends StatefulWidget {
  const _RootPage();

  @override
  State<_RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<_RootPage> with WidgetsBindingObserver {
  bool _isDataLoaded = false;
  bool _splashRemoved = false;

  /// B-09：启动自动备份失败只提示一次（成功/未到期时自动复位）。
  bool _autoBackupNoticeShown = false;
  AppDataProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _provider?.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 跟随系统主题时，系统深浅色变化要同步到悬浮球与系统菜单。
    DesktopService.instance.applyNativeTheme();
  }

  Future<void> _loadData() async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    _provider = provider;
    // 正常启动时数据已在 main() 里加载（窗口状态需要提前应用），此处只兜底。
    if (provider.isLoading) {
      await provider.initialize();
    }
    if (!mounted) return;
    setState(() {
      _isDataLoaded = true;
    });
    // 数据异常提示：主文件损坏后从备份恢复 / 数据被重置。
    final notice = provider.startupNotice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showTopSnackBar(
            context,
            notice,
            isError: provider.startupNoticeIsError,
          );
        }
      });
    }
    provider.addListener(_onDataChanged);
    _syncSaveFailureNotice(provider);
    _checkAutoBackupNotice(provider);
    // 名单已就绪：按名单推算最小窗口尺寸（默认窗口大小也取它）。
    _syncMinimumWindowSize(provider);
    // 审计 A-01/A-02：启动期数据阻断必须让用户显式处理，不能只弹一条
    // 一次性 toast 就继续跑（那样第一条改动就会把空库写进磁盘）。
    _scheduleDataBlockDialog(provider);
    // 托盘不可用时告知用户：此时关闭窗口只会直接退出程序。
    if (DesktopService.instance.initialized &&
        !DesktopService.instance.trayReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showTopSnackBar(context, '系统托盘初始化失败，关闭窗口将直接退出程序', isError: true);
        }
      });
    }
    // 淡出动画结束后移除遮罩，避免进度圈在后台空转。
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _splashRemoved = true);
      }
    });
  }

  /// 弹启动期数据阻断对话框（只弹一次；用户选"稍后处理"后仍保持阻断，
  /// 后续任何写入尝试都会由 provider 提示）。
  void _scheduleDataBlockDialog(AppDataProvider provider) {
    if (!provider.keyMismatchBlocked && !provider.needsEmptyLibraryConfirm) {
      return;
    }
    if (_dataBlockDialogShown) return;
    _dataBlockDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final kind = provider.keyMismatchBlocked
          ? StartupDataBlockKind.keyMismatch
          : StartupDataBlockKind.corrupted;
      await showStartupDataBlockDialog(context, kind: kind);
    });
  }

  /// 阻断态提示是否已弹过（按 provider 的序号判重）。
  int _lastBlockedNoticeSerial = 0;

  /// 阻断态下用户尝试写数据时，把 provider 的提示显示出来（不静默）。
  void _syncBlockedActionNotice(AppDataProvider provider) {
    if (provider.blockedActionNoticeSerial == _lastBlockedNoticeSerial) return;
    _lastBlockedNoticeSerial = provider.blockedActionNoticeSerial;
    final message = provider.blockedActionNotice;
    if (message == null) return;
    provider.clearBlockedActionNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showTopSnackBar(context, message, isError: true);
    });
  }

  /// 保存失败时用置顶常驻胶囊持续提醒；保存恢复后自动撤掉。
  void _syncSaveFailureNotice(AppDataProvider provider) {
    if (!mounted) return;
    final notifications = AppNotificationScope.maybeOf(context);
    if (notifications == null) return;
    if (provider.saveFailed) {
      notifications.showPinned(
        '数据写入失败：最近的改动可能未保存。请检查磁盘空间；'
        '详情见“关于 → 查看操作日志”。',
      );
    } else {
      notifications.clearPinned();
    }
  }

  /// 保存失败时提示用户（每次失败只提示一次，恢复成功后重置）。
  void _onDataChanged() {
    if (!mounted) return;
    final provider = _provider;
    if (provider == null) return;
    // 名单变化时重新推算最小窗口尺寸。
    _syncMinimumWindowSize(provider);
    _syncSaveFailureNotice(provider);
    _checkAutoBackupNotice(provider);
    _syncBlockedActionNotice(provider);
  }

  /// 上次据以推算最小窗口尺寸的名单指纹。
  int? _minWindowKey;

  /// 启动期数据阻断对话框是否已弹过（避免每次 rebuild 重复弹）。
  bool _dataBlockDialogShown = false;

  /// B-09：启动自动备份失败时提示一次；成功/未到期后复位。
  void _checkAutoBackupNotice(AppDataProvider provider) {
    final error = provider.autoBackupError;
    if (error == null) {
      _autoBackupNoticeShown = false;
      return;
    }
    if (_autoBackupNoticeShown) return;
    _autoBackupNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showTopSnackBar(context, '自动备份失败：$error', isError: true);
    });
  }

  /// 按当前名单推算最小窗口尺寸并下发（幂等：名单没变就跳过）。
  void _syncMinimumWindowSize(AppDataProvider provider) {
    final students = provider.appData.students;
    final searchEnabled = provider.appData.settings.studentSearchEnabled;
    final key = Object.hash(Object.hashAll(students), searchEnabled);
    if (_minWindowKey == key) return;
    _minWindowKey = key;
    unawaited(
      DesktopService.instance.applyMinimumWindowSize(
        computeMinimumWindowSize(
          students: students,
          extraCells: students.isEmpty ? const [] : const ['批量'],
          searchEnabled: searchEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 唯一的 MaterialApp 已位于 MyApp，此处仅负责启动加载与过渡。
    return Stack(
      children: [
        const HomePage(),
        if (!_splashRemoved)
          AnimatedOpacity(
            opacity: _isDataLoaded ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: const _SplashOverlay(),
          ),
      ],
    );
  }
}

class _SplashOverlay extends StatelessWidget {
  const _SplashOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}



class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _selectedStudent;
  final double _rightPanelWidth = kRightPanelWidth;
  final TextEditingController _studentSearchController = TextEditingController();
  final FocusNode _studentSearchFocusNode = FocusNode();
  String _studentSearchQuery = '';
  bool _settingsOpen = false;

  /// 修改4：跨天后主界面“今日记录”必须立即换到新的一天。
  /// 顶部日期本身由 HeaderBar 的计时器刷新，这里负责数据与列表。
  late final DayRolloverTracker _dayTracker;
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dayTracker = DayRolloverTracker();
    _scheduleDayCheck();
    DesktopService.instance.onBallMenuAction = _handleBallMenuAction;
    if (kReleaseMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptFactoryPasswordIfNeeded();
      });
    }
  }

  bool _factoryPasswordPrompted = false;

  /// 出厂默认密码是公开在源码里的固定哈希，不能长期作为真实密码使用。
  /// 首次以 Release 启动时主动要求设置一次管理密码；用户取消则本次不再打扰，
  /// 但安全设置页仍会持续提示“仍在使用出厂默认密码”。
  Future<void> _promptFactoryPasswordIfNeeded() async {
    if (!mounted || _factoryPasswordPrompted) return;
    final settings =
        Provider.of<AppDataProvider>(context, listen: false).appData.settings;
    if (!settings.passwordEnabled || settings.passwordHash.isNotEmpty) return;
    _factoryPasswordPrompted = true;
    final changed = await ChangePasswordDialog.show(
      context,
      requireCurrent: false,
    );
    if (!mounted || changed) return;
    showTopSnackBar(
      context,
      '仍在使用出厂默认密码，请在设置 → 安全设置中修改。',
      isError: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    _studentSearchController.dispose();
    _studentSearchFocusNode.dispose();
    if (DesktopService.instance.onBallMenuAction == _handleBallMenuAction) {
      DesktopService.instance.onBallMenuAction = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 系统休眠/锁屏期间计时器可能不触发；恢复时补一次检查，避免仍显示昨天。
    if (state == AppLifecycleState.resumed) _checkDayChanged();
  }

  void _scheduleDayCheck() {
    _dayTimer?.cancel();
    // 归属日不等于自然日：默认就寝时段在 06:20 才切换，不能等到 0 点。
    // 多等 1 秒，确保触发时已越过边界。
    final delay = _dayTracker.untilNextChange() + const Duration(seconds: 1);
    _dayTimer = Timer(delay, _checkDayChanged);
  }

  void _checkDayChanged() {
    if (!mounted) return;
    if (_dayTracker.check()) {
      setState(() {});
      // 悬浮球菜单的“今日”摘要不会随日期自动更新；跨天时主动重算一次，
      // 避免程序持续运行到第二天后仍显示昨天的表扬/批评数量。
      unawaited(DesktopService.instance.applyBallMenuState());
    }
    _scheduleDayCheck();
  }

  /// 学生网格第一格的“批量”入口（非学生单元格）的 key。
  static const String _batchCellKey = '__batch_cell__';

  /// 悬浮球右键菜单的业务动作：球已由 DesktopService 收起，这里打开对应界面。
  Future<void> _handleBallMenuAction(BallMenuAction action) async {
    if (!mounted) return;
    switch (action) {
      case BallMenuAction.quickPraise:
        await _quickRecord('表扬');
      case BallMenuAction.quickCriticize:
        await _quickRecord('批评');
      case BallMenuAction.todayRecords:
        // 主窗口已经恢复，右侧今日记录面板就是该入口。
        break;
      case BallMenuAction.history:
        await showDialog<void>(
          context: context,
          builder: (context) => const HistoryDialog(),
        );
      case BallMenuAction.statistics:
        await showDialog<void>(
          context: context,
          builder: (context) => const StatisticsDialog(),
        );
      case BallMenuAction.settings:
        unawaited(_showSettings());
      case BallMenuAction.open:
      case BallMenuAction.hideToTray:
      case BallMenuAction.exit:
      case BallMenuAction.togglePositionLock:
        // 这些动作由 DesktopService 直接处理，不会走到这里。
        break;
    }
  }

  /// 悬浮球快速记录：与批量入口共用多选；只选 1 人时仍按单条新增处理。
  Future<void> _quickRecord(String operationType) async {
    if (!mounted) return;
    final settings = Provider.of<AppDataProvider>(context, listen: false)
        .appData
        .settings;
    final enabled = operationType == '表扬'
        ? settings.praiseEnabled
        : settings.criticismEnabled;
    if (!enabled) {
      // 原生菜单可能停留在旧状态（例如刚在设置里停用表扬），这里再做一次
      // 防御：给出明确提示，绝不静默改成另一种记录类型。
      showTopSnackBar(
        context,
        '「$operationType」已在设置 → 记录与名单 → 记录设置中停用，'
        '请先启用该类型或改用另一种。',
        isError: true,
      );
      return;
    }
    await _selectStudentsAndStartRecord(
      title: '快速$operationType：选择学生（可多选）',
      initialOperationType: operationType,
    );
  }

  Future<void> _handleBatchTap() async {
    await _selectStudentsAndStartRecord(title: '选择要批量记录的学生（可多选）');
  }

  /// 多选学生后按人数选择门禁口径，并打开预选类型的记录对话框。
  Future<void> _selectStudentsAndStartRecord({
    required String title,
    String? initialOperationType,
  }) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (provider.appData.students.isEmpty) {
      showTopSnackBar(context, '请先在设置中添加学生名单', isError: true);
      return;
    }
    final selected = await StudentPickerDialog.show(
      context,
      title: title,
      students: provider.appData.students,
      multiSelect: true,
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    // 批量写多条比单条新增影响大：与历史页“追加”保持同一门禁口径。
    // 只选中 1 人时仍走单条新增逻辑，按单条新增规则处理。
    if (selected.length >= 2) {
      if (!await ensureIdentityForAction(context, action: '批量记录')) return;
      if (!mounted) return;
      if (!await ensurePasswordForAction(
        context,
        provider,
        PasswordAction.recordAddBatch,
        message: '批量新增记录会一次写入多条，请先进入班主任管理。',
      )) {
        return;
      }
    } else {
      if (!await ensurePasswordForAction(
        context,
        provider,
        PasswordAction.recordAddSingle,
        message: '新增记录前请先进入班主任管理。',
      )) {
        return;
      }
    }
    // 不传日期：由 Provider 按所选时段计算归属日 —— 凌晨 00:30 记的就寝
    // 属于前一天，与单条记录及考勤的默认日期一致。
    if (!mounted) return;
    await showAppendRecordDialog(
      context,
      students: selected,
      initialOperationType: initialOperationType,
    );
  }

  Widget _buildBatchCell(double fontSize) {
    final theme = Theme.of(context);
    return Semantics(
      key: const ValueKey<String>(_batchCellKey),
      button: true,
      label: '批量记录（可多选学生）',
      child: GestureDetector(
        onTap: _handleBatchTap,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.45),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.18),
            ),
            borderRadius: AppRadius.card,
          ),
          child: Center(
            child: Text(
              '批量',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleStudentTap(String name) {
    if (_selectedStudent == name) {
      setState(() => _selectedStudent = null);
    } else {
      setState(() => _selectedStudent = name);
      _openSingleRecord(name);
    }
  }

  Future<void> _openSingleRecord(String name) async {
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    if (!await ensurePasswordForAction(
      context,
      provider,
      PasswordAction.recordAddSingle,
      message: '新增记录前请先进入班主任管理。',
    )) {
      if (mounted) setState(() => _selectedStudent = null);
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => RecordDialog(studentName: name),
    );
    if (mounted) setState(() => _selectedStudent = null);
  }

  void _clearStudentSearch() {
    _studentSearchController.clear();
    setState(() => _studentSearchQuery = '');
    _studentSearchFocusNode.requestFocus();
  }

  List<String> _filteredStudents(List<String> students) {
    final query = _studentSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return students;
    return students
        .where((name) => name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Widget _buildStudentSearchField(ThemeData theme) {
    final hasQuery = _studentSearchQuery.trim().isNotEmpty;
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _studentSearchController,
        focusNode: _studentSearchFocusNode,
        onChanged: (value) => setState(() => _studentSearchQuery = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索学生姓名',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: hasQuery
              ? IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clearStudentSearch,
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainer.withValues(alpha: 0.45),
          border: OutlineInputBorder(
            borderRadius: AppRadius.card,
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.18),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.card,
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.18),
            ),
          ),
        ),
      ),
    );
  }

  /// 自适应学生网格：枚举列数选择最接近 2.5:1 的布局，
  /// 使名单中的卡片在任何分辨率/缩放下精确铺满区域、全部可见、无需滚动。
  /// 卡片不会过小：窗口最小尺寸由原生层限制（见 windows/runner/main.cpp）。
  Widget _buildStudentsGrid(
    BoxConstraints constraints,
    List<String> allStudents, {
    required bool searchEnabled,
  }) {
    // 名单为空时给出引导，避免网格计算除零。
    if (allStudents.isEmpty) {
      return Center(
        child: Text(
          '暂无学生，请在「设置 → 记录与名单 → 名单与原因库」中添加',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final visibleStudents =
        searchEnabled ? _filteredStudents(allStudents) : allStudents;
    final searching =
        searchEnabled && _studentSearchQuery.trim().isNotEmpty;
    final showBatchCell = !searching;
    if (visibleStudents.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配学生',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    const spacing = 8.0;
    final availableWidth = constraints.maxWidth;
    final availableHeight = constraints.maxHeight;

    // 布局计算与"按名单推算最小窗口"共用同一实现（utils/grid_layout.dart）。
    // 它把"无需滚动（单元高度达触控下限）"当作硬约束，因此正常情况下
    // 网格铺满区域、没有滚动条。
    // 布局始终按完整名单计算，搜索时只渲染命中项，避免结果少时卡片被放大。
    final cellCount = allStudents.length + 1;
    final grid = selectStudentGrid(
      studentCount: cellCount,
      availableWidth: availableWidth,
      availableHeight: availableHeight,
    );
    final bestColumns = grid.columns;
    final bestCellWidth = grid.cellWidth;
    final cellHeight = grid.cellHeight;
    // 只有当所有列数都放不下（窗口被拖到极窄/极矮）时才兜底允许滚动，
    // 避免底部卡片被裁掉。
    final needScroll = !grid.fits;

    // 字号随卡片尺寸缩放（与"推算最小窗口"共用同一口径）。
    final fontSize = gridFontSize(bestCellWidth, cellHeight);

    // 今日角标计数（V2.30.0）已下沉到 provider（修复 审查三 4.2）：
    // 此前 widget 直接读内部可变列表、且用 counts[0]/[1] 位置即语义的脆弱写法。
    // X-21：本方法只是"读"，用 listen:false 避免再注册一个订阅（父级已订阅）。
    final provider = Provider.of<AppDataProvider>(context, listen: false);
    final todayCounts = provider.todayCountsByStudent();

    return GridView.builder(
      padding: EdgeInsets.zero,
      // 正常情况下高度与可用空间一致、无需滚动；仅当触控下限导致溢出时兜底可滚动。
      physics: needScroll
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: bestColumns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        mainAxisExtent: cellHeight,
      ),
      itemCount: visibleStudents.length + (showBatchCell ? 1 : 0),
      // 审查 L2：名单增删/重排时用姓名做 key（名单内唯一），卡片元素不随位置
      // 错位；findChildIndexCallback 让框架按 key 定位新下标，避免整片重建。
      findChildIndexCallback: (Key key) {
        final value = (key as ValueKey<String>).value;
        if (value == _batchCellKey) return showBatchCell ? 0 : null;
        final index = visibleStudents.indexOf(value);
        return index < 0 ? null : index + (showBatchCell ? 1 : 0);
      },
      itemBuilder: (context, index) {
        if (showBatchCell && index == 0) {
          return _buildBatchCell(fontSize);
        }
        final name = visibleStudents[index - (showBatchCell ? 1 : 0)];
        final counts = todayCounts[name];
        return StudentCard(
          key: ValueKey<String>(name),
          name: name,
          isSelected: _selectedStudent == name,
          onTap: () => _handleStudentTap(name),
          fontSize: fontSize,
          todayPraise: counts?.praise ?? 0,
          todayCriticism: counts?.criticize ?? 0,
        );
      },
    );
  }

  Future<void> _showSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    try {
      await showDialog(
        context: context,
        builder: (context) =>
            SettingsPanel(onClose: () => Navigator.pop(context)),
      );
    } finally {
      _settingsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppDataProvider>(context);
    final searchEnabled = provider.appData.settings.studentSearchEnabled;
    if (!searchEnabled && _studentSearchQuery.isNotEmpty) {
      // 设置关闭搜索后清掉残留筛选，避免重新开启时仍处于旧筛选。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final stillDisabled = !Provider.of<AppDataProvider>(
          context,
          listen: false,
        ).appData.settings.studentSearchEnabled;
        if (!stillDisabled) return;
        _studentSearchController.clear();
        if (_studentSearchQuery.isNotEmpty) {
          setState(() => _studentSearchQuery = '');
        }
      });
    }

    return Scaffold(
      body: Column(
        children: [
          HeaderBar(onSettingsPressed: _showSettings),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: AppRadius.sheet,
                        border: Border.all(
                          color: theme.semantic.subtleBorder,
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (searchEnabled) ...[
                              _buildStudentSearchField(theme),
                              const SizedBox(height: 12),
                            ],
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    _buildStudentsGrid(
                                      constraints,
                                      provider.appData.students,
                                      searchEnabled: searchEnabled,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: _rightPanelWidth,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Expanded(
                        child: RecordList(records: provider.getTodayRecords()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.semantic.subtleBorder)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '© 2026 WXBDHDMZL',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mutedTextColor(theme, 0.5),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
