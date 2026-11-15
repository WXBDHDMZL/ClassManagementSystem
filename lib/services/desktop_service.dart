/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-07-25 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/app_settings.dart';
import '../utils/app_date.dart';
import '../utils/grid_layout.dart';
import '../widgets/close_confirm_dialog.dart';
import 'app_data_reader.dart';
import 'error_log_service.dart';
import '../utils/app_clock.dart';

/// 悬浮球右键菜单动作（由原生菜单经 MethodChannel 回传）。
enum BallMenuAction {
  open,
  quickPraise,
  quickCriticize,
  todayRecords,
  history,
  statistics,
  settings,
  hideToTray,
  exit,
  togglePositionLock,
}

/// 桌面集成服务：系统托盘常驻、窗口关闭行为（每次询问 / 直接退出 /
/// 最小化到托盘 / 最小化到悬浮球）。
/// 悬浮球是原生层创建的独立分层小窗口（见 windows/runner/ball_window.cpp），
/// 通过 [MethodChannel] `class_management_system/ball` 控制显隐与事件回传。
/// 重复启动的单实例保护由原生层实现（windows/runner/main.cpp）。
class DesktopService with TrayListener, WindowListener {
  DesktopService._();

  static final DesktopService instance = DesktopService._();

  /// 托盘图标：相对资源路径，tray_manager 会自动换算为可执行文件旁的绝对路径。
  static const String _trayIconAsset = 'assets/icons/tray.ico';

  /// 原生悬浮球控制通道。
  static const MethodChannel _ballChannel =
      MethodChannel('class_management_system/ball');

  AppDataReader? _provider;
  GlobalKey<NavigatorState>? _navigatorKey;

  /// 是否处于悬浮球模式（主窗口隐藏、球显示）。
  bool _ballActive = false;
  bool get ballActive => _ballActive;

  /// 是否已完成初始化（测试环境下不会初始化，用于跳过桌面相关的提示）。
  bool _initialized = false;
  bool get initialized => _initialized;

  /// 托盘是否可用：不可用时关闭窗口保持"直接退出"，避免隐藏后无法恢复。
  bool _trayReady = false;
  bool get trayReady => _trayReady;

  /// 悬浮球右键菜单中的业务动作（打开/收起/退出由本服务直接处理）。
  /// 主界面注册后，先退出球模式，再交给界面打开记录对话框/历史/统计/设置。
  Future<void> Function(BallMenuAction action)? onBallMenuAction;

  /// 已进入退出流程：放行窗口关闭，避免再次触发询问。
  bool _quitting = false;
  Timer? _quitWatchdog;

  /// 关闭询问框正在显示：避免连点关闭按钮弹出多个询问框。
  bool _closeDialogShowing = false;

  /// 最近一次同步给原生的深色模式值（null 表示尚未同步）。
  bool? _appliedDarkMode;

  /// 最小窗口尺寸（逻辑像素）：按**名单**自动推算，保证学生姓名完整显示。
  /// 初始值取"推算公式"的下限；`initialize` 与名单变化时会重新推算并下发。
  /// 注意：window_manager 插件会截走 WM_GETMINMAXINFO（自己 return 0），
  /// 因此 main.cpp 里的 SetMinimumSize 实际不生效，必须由这里下发给插件。
  Size _minimumWindowSize = kMinWindowFloor;

  /// 当前生效的最小窗口尺寸。
  Size get minimumWindowSize => _minimumWindowSize;

  /// 把尺寸限制到不小于当前最小窗口尺寸（程序化 setBounds/setSize
  /// 不受"拖动最小尺寸"限制，恢复记忆尺寸时需要自己夹一下）。
  Size clampToMinimum(Size size) => Size(
        size.width < _minimumWindowSize.width ? _minimumWindowSize.width : size.width,
        size.height < _minimumWindowSize.height
            ? _minimumWindowSize.height
            : size.height,
      );

  /// 把目标尺寸夹到显示器可用工作区：小屏/高缩放下不允许下限超过屏幕，
  /// 否则窗口底部内容不可达。
  ///
  /// 多显示器时按 [anchor]（窗口左上角）落在哪块屏就夹到哪块屏；取不到位置
  /// （启动早期、插件不可用）时退回可用区最小的那块屏 —— 下限只要不超最小屏，
  /// 换到任何屏都不会露出屏外。
  static Future<Size> _clampSizeToWorkArea(Size size, {Offset? anchor}) async {
    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      Rect visibleOf(Display display) {
        final position = display.visiblePosition;
        final visible = display.visibleSize ?? display.size;
        return Rect.fromLTWH(
          position?.dx ?? 0,
          position?.dy ?? 0,
          visible.width,
          visible.height,
        );
      }

      final rects = [for (final display in displays) visibleOf(display)];
      if (rects.isEmpty) {
        final display = await ScreenRetriever.instance.getPrimaryDisplay();
        final visible = display.visibleSize ?? display.size;
        return Size(
          size.width > visible.width ? visible.width : size.width,
          size.height > visible.height ? visible.height : size.height,
        );
      }
      Rect target;
      if (anchor != null) {
        target = rects.firstWhere(
          (rect) => rect.contains(anchor),
          orElse: () => rects.reduce(
            (a, b) => a.width * a.height <= b.width * b.height ? a : b,
          ),
        );
      } else {
        target = rects.reduce(
          (a, b) => a.width * a.height <= b.width * b.height ? a : b,
        );
      }
      return Size(
        size.width > target.width ? target.width : size.width,
        size.height > target.height ? target.height : size.height,
      );
    } on Object catch (e) {
      debugPrint('读取显示器工作区失败：$e');
      return size;
    }
  }

  /// 当前窗口左上角；取不到时返回 null（启动早期尚未建窗）。
  static Future<Offset?> _currentWindowAnchor() async {
    try {
      final position = await windowManager.getPosition();
      return Offset(position.dx, position.dy);
    } on Object catch (_) {
      return null;
    }
  }

  /// 按名单重新推算最小窗口尺寸并下发（幂等：尺寸未变化时直接返回）。
  /// 当前窗口若小于新下限，会先把窗口放大到下限（最大化状态不动）。
  Future<void> applyMinimumWindowSize(Size size) async {
    size = await _clampSizeToWorkArea(size, anchor: await _currentWindowAnchor());
    if (size == _minimumWindowSize) return;
    _minimumWindowSize = size;
    if (!_initialized) return;
    try {
      await windowManager.setMinimumSize(size);
      final current = await windowManager.getSize();
      if (current.width < size.width || current.height < size.height) {
        if (!await windowManager.isMaximized() &&
            !await windowManager.isFullScreen()) {
          await windowManager.setSize(Size(
            current.width < size.width ? size.width : current.width,
            current.height < size.height ? size.height : current.height,
          ));
        }
      }
    } catch (e) {
      debugPrint('更新最小窗口尺寸失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '按名单更新最小窗口尺寸');
    }
  }

  /// 开机自启动在注册表中的项名。
  static const String _autoStartKey = 'ClassManagementSystem';

  /// 把尺寸限制到不小于 [minimumWindowSize]（程序化 setBounds/setSize
  /// 不受"拖动最小尺寸"限制，恢复记忆尺寸时需要自己夹一下）。
  /// （已改为实例方法，见上方 [clampToMinimum]。）

  /// 初始化托盘、悬浮球通道与窗口关闭拦截。
  /// 初始化失败会向上抛出，由调用方降级为"关闭窗口即退出程序"的原有行为。
  Future<void> initialize({
    required AppDataReader provider,
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _provider = provider;
    _navigatorKey = navigatorKey;

    await windowManager.ensureInitialized();
    // 最小窗口尺寸：按当前名单推算（保证姓名完整显示），两条保障并用。
    // ① 通过插件设置拖动最小尺寸（原生 WM_GETMINMAXINFO 被插件截走，
    //    main.cpp 里的 SetMinimumSize 实际不生效，必须走插件）；
    _minimumWindowSize = await _clampSizeToWorkArea(
      computeMinimumWindowSize(
        students: provider.appData.students,
        extraCells: provider.appData.students.isEmpty ? const [] : const ['批量'],
        searchEnabled: provider.appData.settings.studentSearchEnabled,
      ),
    );
    await windowManager.setMinimumSize(_minimumWindowSize);
    // ② onWindowResized 里再用 clampToMinimum 夹一次（见该回调），
    //    防止某些路径绕过拖动限制把窗口缩得过小。
    _initialized = true;
    _ballChannel.setMethodCallHandler(_handleBallCall);
    // 主题变化时把深浅色同步给原生（悬浮球与系统菜单跟随应用主题）。
    _provider?.addListener(_onProviderChanged);
    await applyNativeTheme();
    // 修复（审计 P2-49）：启动时也把悬浮球外观下发一次 —— 此前只有"数据变化"
    // 触发的通知才会补发，本次会话第一次显球仍是默认外观。
    await applyBallStyle();

    // 先建托盘：托盘失败时下面的关闭拦截不会被启用，程序保持"关闭即退出"。
    await trayManager.setIcon(_trayIconAsset);
    await trayManager.setToolTip('班级管理系统（单击托盘图标可恢复窗口）');
    trayManager.addListener(this);
    _trayReady = true;
    await _updateTrayMenu();
    await applyBallMenuState();

    // 接管窗口关闭：由 Flutter 层按设置决定退出还是最小化。
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  /// 仅供单元测试使用：把单例状态复位并摘掉已注册的监听器，
  /// 避免用例之间互相影响（DesktopService 是单例，状态会跨用例残留）。
  @visibleForTesting
  void debugReset() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _ballChannel.setMethodCallHandler(null);
    _provider?.removeListener(_onProviderChanged);
    _provider = null;
    _navigatorKey = null;
    _ballActive = false;
    _initialized = false;
    _trayReady = false;
    _quitting = false;
    _closeDialogShowing = false;
    _appliedDarkMode = null;
    _appliedBallOpacity = null;
    _appliedBallMenuOpacity = null;
    _appliedBallMenuTrayReady = null;
    _appliedBallMenuTodayPraise = null;
    _appliedBallMenuTodayCriticize = null;
    _appliedBallMenuPositionLocked = null;
    _appliedBallMenuPraiseEnabled = null;
    _appliedBallMenuCriticismEnabled = null;
    onBallMenuAction = null;
  }

  /// 读取当前是否已设置开机自动启动（注册表 Run 项）。
  static Future<bool> isAutoStartEnabled() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        _autoStartKey,
      ]);
      return result.exitCode == 0 &&
          result.stdout.toString().contains(_autoStartKey);
    } catch (e) {
      debugPrint('读取启动项失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '查询开机自启动状态');
      return false;
    }
  }

  /// 设置/取消开机自动启动：写入 HKCU\...\Run。
  /// [target] 决定启动参数：托盘用 `--tray`，悬浮球用 `--ball`；
  /// 两者都会让主窗口在开机时不弹出。
  static Future<bool> setAutoStartEnabled(
    bool enabled, {
    StartupTarget target = StartupTarget.tray,
  }) async {
    try {
      const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
      if (enabled) {
        final exe = Platform.resolvedExecutable;
        final flag = target == StartupTarget.ball ? '--ball' : '--tray';
        final result = await Process.run('reg', [
          'add',
          key,
          '/v',
          _autoStartKey,
          '/t',
          'REG_SZ',
          '/d',
          '"$exe" $flag',
          '/f',
        ]);
        return result.exitCode == 0;
      }
      final result = await Process.run('reg', [
        'delete',
        key,
        '/v',
        _autoStartKey,
        '/f',
      ]);
      // 项不存在时 reg 返回非 0，同样视为已关闭。
      return result.exitCode == 0 || !await isAutoStartEnabled();
    } catch (e) {
      debugPrint('设置启动项失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '设置开机自启动（写/删注册表）');
      return false;
    }
  }

  /// 显示主窗口：从托盘图标、托盘菜单或悬浮球恢复时统一走这里。
  Future<void> showMainWindow() async {
    if (_ballActive) {
      await exitBallMode();
      return;
    }
    await _restoreMainWindow();
  }

  /// 由原生恢复并显示主窗口，等 Flutter 下一帧后再让窗口可见，
  /// 避免最小化恢复时短暂露出空白白底（DWM cloak）。
  Future<void> _restoreMainWindow() async {
    try {
      await _ballChannel.invokeMethod('showMainWindow');
      await windowManager.focus();
    } on Object catch (e) {
      // 原生方法不可用时退回窗口管理器路径，保证窗口一定能回来。
      debugPrint('原生恢复主窗口失败，回退窗口管理器：$e');
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    }
  }

  /// 最小化到托盘：立即隐藏窗口，程序继续在后台运行并保持数据落盘。
  Future<void> hideToTray() async {
    await windowManager.hide();
  }

  /// 从悬浮球右键菜单"收起到托盘"：只隐藏球，不显示主窗口。
  Future<void> hideBallToTray() async {
    if (!_ballActive) return;
    if (!_trayReady) {
      // 托盘不可用时菜单项本应禁用；这里再兜底一次，避免球消失后无法恢复。
      await showMainWindow();
      return;
    }
    try {
      await _ballChannel.invokeMethod('hideBall');
      _ballActive = false;
    } on Object catch (e) {
      // 隐藏失败时球仍在桌面上，不能把状态当成已收起：保持球模式，
      // 这样托盘菜单仍显示"退出悬浮球"，用户可以重试或正常退出。
      debugPrint('收起到托盘时隐藏悬浮球失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '收起到托盘（隐藏悬浮球）');
    }
    await _updateTrayMenu();
  }

  /// 最小化到悬浮球：显示原生小球（置顶、不进任务栏），主窗口隐藏。
  /// 球位置优先使用上次记忆的坐标，越界时由原生层夹回默认位置。
  Future<void> enterBallMode() async {
    if (_ballActive) return;
    try {
      // 先隐藏主窗口再显示半透明小球；小球不采集桌面内容，无需等待画面稳定。
      await windowManager.hide();
      await _ballChannel.invokeMethod('showBall', <String, int>{
        'x': _provider?.appData.settings.ballX ?? -1,
        'y': _provider?.appData.settings.ballY ?? -1,
      });
    } catch (e) {
      // 球显示失败时把主窗口恢复回来，不让用户失去界面。
      debugPrint('显示悬浮球失败：$e');
      await showMainWindow();
      return;
    }
    _ballActive = true;
    await _updateTrayMenu();
    await applyBallMenuState();
  }

  /// 退出悬浮球模式：隐藏球并恢复主窗口。
  Future<void> exitBallMode() async {
    if (!_ballActive) return;
    _ballActive = false;
    try {
      await _ballChannel.invokeMethod('hideBall');
    } catch (e) {
      debugPrint('隐藏悬浮球失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '退出悬浮球模式（收球并恢复主窗口）');
    }
    // 主窗口可能是在最小化状态下进的球模式：由原生统一还原、显示，
    // 并等下一帧就绪后再取消 DWM 隐形，避免白闪。
    await _restoreMainWindow();
    await _updateTrayMenu();
  }

  /// 启动时应用窗口状态（在窗口显示前调用）：
  /// 记住上次（含是否最大化）/ 默认大小 / 启动即最大化。
  Future<void> applyStartupWindowMode(AppSettings settings) async {
    try {
      switch (settings.startupWindowMode) {
        case StartupWindowMode.maximized:
          await windowManager.maximize();
        case StartupWindowMode.remember:
          if (settings.windowMaximized) {
            await windowManager.maximize();
            return;
          }
          final width = settings.windowWidth;
          final height = settings.windowHeight;
          if (width <= 0 || height <= 0) {
            // 首次启动（没有记忆尺寸）：默认大小 = 当前推算出的最小尺寸。
            await windowManager.setSize(_minimumWindowSize);
            return;
          }
          final x = settings.windowX;
          final y = settings.windowY;
          final size = clampToMinimum(
            Size(width.toDouble(), height.toDouble()),
          );
          // 修复（审计 P1-24）：-1 才是"未记录"哨兵 —— 负坐标（左侧/上方
          // 副屏）是合法位置，此前被误判为未记录；恢复前再把窗口夹回
          // 屏幕可见区，避免显示器变化后窗口落在屏外看不见。
          if (x != -1 && y != -1 && x.abs() < 30000 && y.abs() < 30000) {
            final safeBounds = await clampToDisplays(
              Rect.fromLTWH(x.toDouble(), y.toDouble(), size.width, size.height),
            );
            await windowManager.setBounds(safeBounds);
          } else {
            await windowManager.setSize(size);
          }
        case StartupWindowMode.defaultSize:
          // 默认大小 = 按名单推算的最小尺寸（保证学生姓名完整显示）。
          await windowManager.setSize(_minimumWindowSize);
      }
    } catch (e) {
      debugPrint('应用启动窗口状态失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '启动时应用窗口状态');
    }
  }

  /// 退出前记录窗口大小与位置（仅"记住上次"模式；球模式下窗口是隐藏的，不记录）。
  Future<void> rememberWindowBounds() async {
    final settings = _provider?.appData.settings;
    if (settings == null) return;
    if (settings.startupWindowMode != StartupWindowMode.remember) return;
    if (_ballActive) return;
    try {
      // 修复（审计 P1-24）：最小化时 getBounds 返回的是停靠坐标（约 -32000）
      // 与图标尺寸，直接记忆会把上次的位置/尺寸写坏；该状态跳过本次记录。
      if (await windowManager.isMinimized()) return;
      final maximized = await windowManager.isMaximized();
      final bounds = await windowManager.getBounds();
      final size = clampToMinimum(bounds.size);
      _provider?.setWindowBounds(
        bounds.left.round(),
        bounds.top.round(),
        size.width.round(),
        size.height.round(),
        maximized: maximized,
      );
    } catch (e) {
      debugPrint('记录窗口大小与位置失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '退出前记录窗口大小与位置');
    }
  }

  /// 审计 P1-24：把恢复的窗口矩形夹到"所有显示器可见区"内 —— 显示器被拔掉/
  /// 分辨率变小后，记忆坐标可能完全在屏外（窗口看不见也拖不回来）；此时退回
  /// 主显示器左上角内侧。至少保留 100×50 逻辑像素在某个屏内才算"可见"。
  /// 插件不可用（测试环境）或平台异常时原样返回，不影响启动。
  static Future<Rect> clampToDisplays(Rect bounds) async {
    try {
      final displays = await ScreenRetriever.instance.getAllDisplays();
      Rect visibleOf(Display display) {
        final position = display.visiblePosition;
        final size = display.visibleSize ?? display.size;
        return Rect.fromLTWH(
          position?.dx ?? 0,
          position?.dy ?? 0,
          size.width,
          size.height,
        );
      }

      final rects = [for (final display in displays) visibleOf(display)];
      if (rects.isEmpty) return bounds;
      final visibleEnough = rects.any((rect) {
        final overlap = rect.intersect(bounds);
        return overlap.width >= 100 && overlap.height >= 50;
      });
      if (visibleEnough) {
        // 记忆的窗口可能比当前工作区更大（换到小屏/高缩放），
        // 先夹到重叠最多的那块屏，避免窗口超出屏幕。
        var target = rects.first;
        var bestArea = 0.0;
        for (final rect in rects) {
          final overlap = rect.intersect(bounds);
          final area = overlap.width * overlap.height;
          if (area > bestArea) {
            bestArea = area;
            target = rect;
          }
        }
        final width = bounds.width > target.width ? target.width : bounds.width;
        final height =
            bounds.height > target.height ? target.height : bounds.height;
        final left = bounds.left
            .clamp(target.left, target.right - width)
            .toDouble();
        final top = bounds.top
            .clamp(target.top, target.bottom - height)
            .toDouble();
        return Rect.fromLTWH(left, top, width, height);
      }
      Rect primary;
      try {
        primary = visibleOf(await ScreenRetriever.instance.getPrimaryDisplay());
      } catch (_) {
        primary = rects.first;
      }
      return Rect.fromLTWH(
        primary.left + 40,
        primary.top + 40,
        bounds.width,
        bounds.height,
      );
    } catch (e) {
      debugPrint('显示器可见性检查失败：$e');
      return bounds;
    }
  }

  /// 审计 P1-25：按设置校正开机启动项 —— 开启时重写注册表（顺带修复
  /// "程序被移动后启动项仍指向旧 exe"），关闭时清理残留；失败不打扰用户。
  static Future<void> reconcileAutoStart(
    bool enabled,
    StartupTarget target,
  ) async {
    try {
      if (enabled) {
        await setAutoStartEnabled(true, target: target);
      } else if (await isAutoStartEnabled()) {
        await setAutoStartEnabled(false);
      }
    } catch (e) {
      debugPrint('校正开机自启动失败：$e');
    }
  }

  /// 退出程序：先等待写盘队列完成，再移除托盘图标与悬浮球并走正常关闭流程。
  Future<void> quitApp() async {
    if (_quitting) return;
    _quitting = true;
    // 保险丝（V2.30.11，修复"关窗后进程挂起"）：先建计时器再等待保存队列，
    // 否则磁盘/杀软导致 flushPendingSaves 永久阻塞时兜底永远不会触发。
    _quitWatchdog = Timer(const Duration(seconds: 10), () {
      exit(0);
    });
    try {
      // 先记录窗口状态（内部排队保存，随后由 flush 落盘）。
      await rememberWindowBounds();
      // 设置为"每次退出时"备份就顺手备份一次（内部会先落盘再复制）。
      if (_provider?.appData.settings.backupFrequency ==
          BackupFrequency.onExit) {
        await _provider?.performBackup();
      }
      await _provider?.flushPendingSaves();
      // 托盘清理失败不能影响退出流程。
      try {
        await trayManager.destroy();
      } catch (e) {
        debugPrint('移除托盘图标失败：$e');
        appendErrorLog('desktop_service', e, StackTrace.current,
            context: '退出程序：恢复窗口阶段');
      }
      // 退出前收起悬浮球，避免进程结束后球残留在桌面上。
      if (_ballActive) {
        try {
          await _ballChannel.invokeMethod('hideBall');
        } catch (e) {
          debugPrint('隐藏悬浮球失败：$e');
          appendErrorLog('desktop_service', e, StackTrace.current,
              context: '退出程序：结束进程阶段');
        }
        _ballActive = false;
      }
      await windowManager.setPreventClose(false);
      // 必须走窗口正常关闭流程（WM_CLOSE → 销毁窗口 → 引擎正常退出）：
      // 直接调 destroy()（PostQuitMessage）实测会让进程多存活约 10 秒才结束。
      await windowManager.close();
      // 修复（审计 P2-50）：兜底统一交给上面的 10 秒看门狗（exit）——
      // 不再调用 destroy()（实测拖慢退出），也删掉此前的 800ms 强制结束
      //（在测试环境会在用例中途把进程杀掉；生产上 close 卡住同样由看门狗兜底）。
    } catch (e) {
      // 退出失败时恢复标记，允许用户再次尝试关闭；并取消保险丝，
      // 避免用户继续正常使用却被计时器误杀（修复 审查四 S-4）。
      _quitWatchdog?.cancel();
      _quitWatchdog = null;
      _quitting = false;
      debugPrint('退出程序失败：$e');
      // 修复（审计 P2-50）：托盘可能已在前面被销毁，失败回滚时重建回来 ——
      // 否则用户继续使用却没有托盘（无法最小化到托盘/从托盘恢复）。
      if (_trayReady) {
        try {
          await trayManager.setIcon(_trayIconAsset);
          await trayManager.setToolTip('班级管理系统（单击托盘图标可恢复窗口）');
          await _updateTrayMenu();
        } catch (e2) {
          debugPrint('重建托盘图标失败：$e2');
        }
      }
    }
  }

  // -------------------- 主题同步 --------------------

  /// 已下发的悬浮球不透明度，避免重复下发。
  double? _appliedBallOpacity;

  /// 已下发的右键菜单状态，避免每次数据变化都重复走通道。
  double? _appliedBallMenuOpacity;
  bool? _appliedBallMenuTrayReady;
  int? _appliedBallMenuTodayPraise;
  int? _appliedBallMenuTodayCriticize;
  bool? _appliedBallMenuPositionLocked;
  bool? _appliedBallMenuPraiseEnabled;
  bool? _appliedBallMenuCriticismEnabled;

  /// 提示服务监听数据变化：主题或悬浮球外观被修改时同步给原生界面。
  /// 报告 M8：同步 void 回调不受 unawaited_futures 约束（只查 async 体），
  /// 显式 unawaited 与项目规约（G-56）一致，失败路径可观测。
  void _onProviderChanged() {
    unawaited(applyNativeTheme());
    unawaited(applyBallStyle());
    unawaited(applyBallMenuState());
  }

  /// 把当前深浅色同步到原生（悬浮球圆底配色、托盘右键菜单与标题栏）。
  /// 遍历所有主题来源（固定深色/浅色、跟随系统），值未变化时不重复下发。
  Future<void> applyNativeTheme() async {
    final isDark = _resolveDarkMode();
    if (_appliedDarkMode == isDark) return;
    try {
      await _ballChannel.invokeMethod('setDarkMode', isDark);
      _appliedDarkMode = isDark;
    } catch (e) {
      debugPrint('同步深色模式到原生界面失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '应用原生窗口主题（明暗模式）');
    }
  }

  /// 把悬浮球不透明度同步到原生界面；值未变化时不重复下发。
  Future<void> applyBallStyle() async {
    final settings = _provider?.appData.settings;
    if (settings == null) return;
    final opacity = settings.ballOpacity;
    if (opacity == _appliedBallOpacity) return;
    try {
      await _ballChannel.invokeMethod('setBallStyle', <String, dynamic>{
        'opacity': opacity,
      });
      _appliedBallOpacity = opacity;
    } catch (e) {
      debugPrint('同步悬浮球外观失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '应用悬浮球不透明度');
    }
  }

  /// 把右键菜单需要的轻量状态（不透明度勾选项/托盘可用/今日摘要/悬浮球行为）同步给原生。
  Future<void> applyBallMenuState() async {
    final settings = _provider?.appData.settings;
    if (settings == null) return;
    final opacity = settings.ballOpacity;
    final today = formatYmd(AppClock.now());
    final records = _provider?.getRecordsForDates([today]) ?? const [];
    var todayPraise = 0;
    var todayCriticize = 0;
    for (final record in records) {
      if (record.operationType == '表扬') {
        todayPraise++;
      } else if (record.operationType == '批评') {
        todayCriticize++;
      }
    }
    if (opacity == _appliedBallMenuOpacity &&
        _trayReady == _appliedBallMenuTrayReady &&
        todayPraise == _appliedBallMenuTodayPraise &&
        todayCriticize == _appliedBallMenuTodayCriticize &&
        settings.ballPositionLocked == _appliedBallMenuPositionLocked &&
        settings.praiseEnabled == _appliedBallMenuPraiseEnabled &&
        settings.criticismEnabled == _appliedBallMenuCriticismEnabled) {
      return;
    }
    try {
      await _ballChannel.invokeMethod('setBallMenuState', <String, dynamic>{
        'opacity': opacity,
        'trayReady': _trayReady,
        'todayPraise': todayPraise,
        'todayCriticize': todayCriticize,
        'positionLocked': settings.ballPositionLocked,
        'praiseEnabled': settings.praiseEnabled,
        'criticismEnabled': settings.criticismEnabled,
      });
      _appliedBallMenuOpacity = opacity;
      _appliedBallMenuTrayReady = _trayReady;
      _appliedBallMenuTodayPraise = todayPraise;
      _appliedBallMenuTodayCriticize = todayCriticize;
      _appliedBallMenuPositionLocked = settings.ballPositionLocked;
      _appliedBallMenuPraiseEnabled = settings.praiseEnabled;
      _appliedBallMenuCriticismEnabled = settings.criticismEnabled;
    } on Object catch (e) {
      debugPrint('同步悬浮球菜单状态失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '应用悬浮球右键菜单状态');
    }
  }

  /// 解析当前生效的深浅色：固定模式按设置，跟随系统按系统亮度。
  bool _resolveDarkMode() {
    switch (_provider?.appData.settings.themeMode ?? ThemeModeType.system) {
      case ThemeModeType.dark:
        return true;
      case ThemeModeType.light:
        return false;
      case ThemeModeType.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  // -------------------- 悬浮球事件 --------------------

  /// 把原生菜单动作转成 Dart 行为；未知动作只记日志，不影响程序。
  Future<void> _dispatchBallMenuAction(
    Object? rawAction,
    Object? rawValue,
  ) async {
    BallMenuAction? action;
    switch (rawAction) {
      case 'open':
        action = BallMenuAction.open;
      case 'quickPraise':
        action = BallMenuAction.quickPraise;
      case 'quickCriticize':
        action = BallMenuAction.quickCriticize;
      case 'todayRecords':
        action = BallMenuAction.todayRecords;
      case 'history':
        action = BallMenuAction.history;
      case 'statistics':
        action = BallMenuAction.statistics;
      case 'settings':
        action = BallMenuAction.settings;
      case 'hideToTray':
        action = BallMenuAction.hideToTray;
      case 'exit':
        action = BallMenuAction.exit;
      case 'setOpacity':
        final value = rawValue;
        if (value is num) {
          _provider?.setBallOpacity(value.toDouble());
          await applyBallStyle();
          await applyBallMenuState();
        }
        return;
      case 'togglePositionLock':
        final settings = _provider?.appData.settings;
        if (settings != null) {
          _provider?.setBallPositionLocked(!settings.ballPositionLocked);
          await applyBallMenuState();
        }
        return;
      default:
        debugPrint('未知的悬浮球菜单动作：$rawAction');
        return;
    }

    switch (action) {
      case BallMenuAction.open:
        await showMainWindow();
      case BallMenuAction.hideToTray:
        await hideBallToTray();
      case BallMenuAction.exit:
        await quitApp();
      case BallMenuAction.quickPraise:
      case BallMenuAction.quickCriticize:
      case BallMenuAction.todayRecords:
      case BallMenuAction.history:
      case BallMenuAction.statistics:
      case BallMenuAction.settings:
        await exitBallMode();
        final handler = onBallMenuAction;
        if (handler != null) {
          await handler(action);
        }
      case BallMenuAction.togglePositionLock:
        // 已在上面直接处理，不进入业务回调。
        break;
    }
  }

  /// 处理原生球窗口回传的事件。
  Future<void> _handleBallCall(MethodCall call) async {
    // 修复（审计 P2-58）：入站事件（球窗口/单实例唤醒）统一兜底 —— 此前失败
    // 会被框架编码成错误信封静默丢弃、没有本地日志，排查无迹可寻。
    try {
      switch (call.method) {
        case 'wakeup':
          // 单实例二次启动的唤醒（闪烁修复）：统一在这里"先收球、再显示主窗口"。
          // 悬浮球模式：收球并显示主窗口；最小化：还原；都做一次前置聚焦。
          if (_ballActive) {
            await exitBallMode();
          } else {
            await _restoreMainWindow();
          }
        case 'onBallClicked':
          // 单击球：恢复主窗口。
          await exitBallMode();
        case 'onBallMoved':
          final arguments = call.arguments;
          if (arguments is Map) {
            final x = arguments['x'];
            final y = arguments['y'];
            if (x is int && y is int) {
              _provider?.setBallPosition(x, y);
            }
          }
        case 'onBallMenuCommand':
          final arguments = call.arguments;
          if (arguments is Map) {
            await _dispatchBallMenuAction(
              arguments['action'],
              arguments['value'],
            );
          }
      }
    } catch (e) {
      debugPrint('处理悬浮球事件失败（${call.method}）：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '处理悬浮球事件（${call.method}）');
    }
  }

  // -------------------- 窗口事件 --------------------

  @override
  void onWindowResized() async {
    try {
      final size = await windowManager.getSize();
      final clamped = clampToMinimum(size);
      if (clamped != size) {
        await windowManager.setSize(clamped);
      }
    } catch (e) {
      debugPrint('窗口尺寸校正失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '窗口尺寸变化（最小尺寸钳制）');
    }
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    _handleCloseRequest();
  }

  /// 窗口最小化（任务栏最小化按钮/Win+D）时也进入悬浮球模式，
  /// 保证最小化后仍能从桌面悬浮球恢复；关闭行为仍由 onWindowClose 处理。
  @override
  void onWindowMinimize() {
    if (_quitting || _ballActive) return;
    unawaited(enterBallMode());
  }

  @override
  void onWindowEvent(String eventName) {
    // 原生侧把主窗口显示出来时（例如重复启动程序唤起已有窗口），
    // 同步收起悬浮球，避免"主窗口与球同时存在"的错乱状态。
    if (eventName == 'show' && _ballActive) {
      exitBallMode();
    }
  }

  /// 按当前设置处理关闭请求。
  Future<void> _handleCloseRequest() async {
    final provider = _provider;
    if (provider == null) {
      await quitApp();
      return;
    }
    switch (provider.appData.settings.closeAction) {
      case CloseActionType.exit:
        await quitApp();
      case CloseActionType.minimizeToTray:
        await hideToTray();
      case CloseActionType.minimizeToBall:
        await enterBallMode();
      case CloseActionType.ask:
        await _askAndApply(provider);
    }
  }

  /// 弹出询问框并按用户选择执行；勾选"记住"时同步保存设置。
  Future<void> _askAndApply(AppDataReader provider) async {
    if (_closeDialogShowing) return;
    final context = _navigatorKey?.currentContext;
    if (context == null) {
      // 拿不到界面上下文时不再询问，直接退出，避免窗口关不掉。
      await quitApp();
      return;
    }

    // 关闭请求可能来自任务栏缩略图上的 ✗：此时主窗口往往处于最小化或被遮挡状态，
    // 确认框会弹在一个看不见的窗口里（看起来就像"点了关闭没反应"）。
    // 先把主窗口恢复、显示并拿到焦点，再弹确认框。悬浮球模式下主窗口本就隐藏，跳过。
    if (!_ballActive) {
      await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    }
    if (!context.mounted) {
      // 窗口在等待期间被销毁（极少发生）：按直接退出处理，避免窗口关不掉。
      await quitApp();
      return;
    }

    _closeDialogShowing = true;
    final CloseConfirmResult? result;
    try {
      result = await CloseConfirmDialog.show(context);
    } finally {
      _closeDialogShowing = false;
    }

    if (result == null) return; // 取消：窗口保持打开
    if (result.remember) {
      provider.setCloseAction(result.action);
    }
    switch (result.action) {
      case CloseActionType.exit:
        await quitApp();
      case CloseActionType.minimizeToTray:
        await hideToTray();
      case CloseActionType.minimizeToBall:
        await enterBallMode();
      case CloseActionType.ask:
        break;
    }
  }

  // -------------------- 托盘事件 --------------------

  @override
  void onTrayIconMouseDown() {
    showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showMainWindow();
      case 'ball':
        if (_ballActive) {
          exitBallMode();
        } else {
          enterBallMode();
        }
      case 'exit':
        quitApp();
    }
  }

  // -------------------- 内部工具 --------------------

  /// 托盘菜单随球模式状态更新文案，用户能看出当前处于哪种模式。
  Future<void> _updateTrayMenu() async {
    final inBall = _ballActive;
    try {
      await trayManager.setContextMenu(
        Menu(items: [
          MenuItem(key: 'show', label: '显示主窗口'),
          MenuItem(key: 'ball', label: inBall ? '退出悬浮球' : '悬浮球模式'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出程序'),
        ]),
      );
    } catch (e) {
      debugPrint('更新托盘菜单失败：$e');
      appendErrorLog('desktop_service', e, StackTrace.current,
          context: '更新托盘菜单');
    }
  }
}
