/*
 * 班级管理系统 - Class Management System
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.12.0
 * 创建日期 (Created): 2026-10-24
 *
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// 通知类型。颜色只在 [AppNotificationHost] 内集中映射。
enum AppNoticeKind { info, success, warning, error }

/// 通知上的可选动作（如“撤销”）。动作只对当前这条通知有效。
class AppNoticeAction {
  const AppNoticeAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// 一条通知。
class AppNotice {
  AppNotice({
    required this.id,
    required this.message,
    required this.kind,
    required this.duration,
    required this.pinned,
    this.action,
  });

  final int id;
  final String message;
  final AppNoticeKind kind;
  final Duration duration;
  final bool pinned;
  final AppNoticeAction? action;
  AppNoticeHandle? handle;
}

/// 通知句柄：可主动关闭，也可在测试里检查是否已经结束。
class AppNoticeHandle {
  AppNoticeHandle._(this._dismiss);

  final FutureOr<void> Function()? _dismiss;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _done = false;

  bool get isDone => _done;

  /// 监听通知结束；通知结束后再监听会抛断言。
  void addListener(VoidCallback listener) {
    if (_done) {
      throw AssertionError('通知已经结束，不能再添加监听');
    }
    _listeners.add(listener);
  }

  /// 主动关闭。已经结束时重复调用无副作用。
  void dismiss() {
    if (_done) return;
    _dismiss?.call();
  }

  void _markDone() {
    if (_done) return;
    _done = true;
    _listeners.clear();
  }
}

/// 全局通知控制器：瞬时通知立即叠放（最多 [maxVisible] 条），常驻通知单独占一条。
///
/// 设计约束：
/// - 新通知立即出现在顶部，不再等上一条消失，保证提醒及时；
/// - 最多同时显示 3 条，超出时优先移除最早的普通提示；
/// - 如果当前全是错误/警告，则移除最早的一条，保证最新提醒可见；
/// - 相同文案+类型在显示中/常驻项里已存在时复用，不重复；
/// - 常驻通知（保存失败等）不自动消失，由状态显式清除；
/// - 控制器不直接碰 UI，便于单元测试与替换。
class AppNoticeController extends ChangeNotifier {
  AppNoticeController();

  /// 最多同时显示的瞬时通知数。
  static const int maxVisible = 3;

  final List<AppNotice> _active = <AppNotice>[];
  final Map<int, Timer> _timers = <int, Timer>{};
  AppNotice? _pinned;
  int _nextId = 1;
  bool _disposed = false;

  /// 兼容旧调用/测试：当前最早的一条瞬时通知。
  AppNotice? get current => _active.isEmpty ? null : _active.first;

  /// 当前全部瞬时通知，按加入顺序（最早在前）。UI 通常倒序展示。
  List<AppNotice> get active => List<AppNotice>.unmodifiable(_active);

  AppNotice? get pinned => _pinned;
  bool get hasNotice => _active.isNotEmpty || _pinned != null;

  /// 当前是否有带动作的通知。通知层据此决定是否接收鼠标事件。
  bool get hasAction => _active.any((notice) => notice.action != null);

  AppNoticeHandle show(
    String message, {
    AppNoticeKind kind = AppNoticeKind.info,
    Duration duration = const Duration(milliseconds: 2500),
    AppNoticeAction? action,
  }) {
    if (_disposed) return AppNoticeHandle._(null);
    // 带动作的通知不能被旧文案复用：否则新操作会拿到旧通知的按钮。
    final duplicate = action == null ? _findDuplicate(message, kind, pinned: false) : null;
    if (duplicate != null) return duplicate.handle!;
    if (action != null) _removeActionNotices();

    final notice = AppNotice(
      id: _nextId++,
      message: message,
      kind: kind,
      duration: duration,
      pinned: false,
      action: action,
    );
    final handle = AppNoticeHandle._(() => _dismiss(notice.id));
    notice.handle = handle;

    _active.add(notice);
    _startTimer(notice);
    while (_active.length > maxVisible) {
      _removeOverflowOldest(notice.id);
    }
    _notify();
    return handle;
  }

  AppNoticeHandle showPinned(
    String message, {
    AppNoticeKind kind = AppNoticeKind.error,
  }) {
    if (_disposed) return AppNoticeHandle._(null);
    if (_pinned != null &&
        _pinned!.message == message &&
        _pinned!.kind == kind) {
      return _pinned!.handle!;
    }
    _pinned?.handle?._markDone();
    final notice = AppNotice(
      id: _nextId++,
      message: message,
      kind: kind,
      duration: Duration.zero,
      pinned: true,
    );
    final handle = AppNoticeHandle._(() => clearPinned());
    notice.handle = handle;
    _pinned = notice;
    _notify();
    return handle;
  }

  void clearPinned() {
    if (_disposed) return;
    final notice = _pinned;
    if (notice == null) return;
    _pinned = null;
    notice.handle?._markDone();
    _notify();
  }

  void dismissAll() {
    if (_disposed) return;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final notice in _active) {
      notice.handle?._markDone();
    }
    _active.clear();
    _pinned?.handle?._markDone();
    _pinned = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final notice in _active) {
      notice.handle?._markDone();
    }
    _active.clear();
    _pinned?.handle?._markDone();
    _pinned = null;
    super.dispose();
  }

  void _dismiss(int id) {
    if (_disposed) return;
    if (_pinned?.id == id) {
      clearPinned();
      return;
    }
    final index = _active.indexWhere((notice) => notice.id == id);
    if (index < 0) return;
    final notice = _active.removeAt(index);
    _cancelTimer(notice);
    notice.handle?._markDone();
    _notify();
  }

  void _finish(int id) {
    if (_disposed) return;
    final index = _active.indexWhere((notice) => notice.id == id);
    if (index < 0) return;
    final notice = _active.removeAt(index);
    _cancelTimer(notice);
    notice.handle?._markDone();
    _notify();
  }

  void _startTimer(AppNotice notice) {
    final duration = notice.duration < const Duration(milliseconds: 50)
        ? const Duration(milliseconds: 50)
        : notice.duration;
    _timers[notice.id] = Timer(duration, () => _finish(notice.id));
  }

  void _cancelTimer(AppNotice notice) {
    _timers.remove(notice.id)?.cancel();
  }

  /// 超限时优先淘汰最早的普通提示；若全是错误/警告，则淘汰最早一条。
  /// 新加的那条不参与“普通提示”淘汰，避免它刚出现就被自己挤掉。
  void _removeOverflowOldest(int newestId) {
    var index = _active.indexWhere(
      (notice) =>
          notice.id != newestId &&
          notice.kind != AppNoticeKind.error &&
          notice.kind != AppNoticeKind.warning,
    );
    if (index < 0) index = 0;
    final removed = _active.removeAt(index);
    _cancelTimer(removed);
    removed.handle?._markDone();
  }

  /// 撤销只保留最近一次：新动作通知出现时，旧动作通知立即失效。
  void _removeActionNotices() {
    for (var i = _active.length - 1; i >= 0; i--) {
      final notice = _active[i];
      if (notice.action == null) continue;
      _active.removeAt(i);
      _cancelTimer(notice);
      notice.handle?._markDone();
    }
  }

  AppNotice? _findDuplicate(
    String message,
    AppNoticeKind kind, {
    required bool pinned,
  }) {
    if (pinned && _pinned != null) {
      if (_pinned!.message == message && _pinned!.kind == kind) {
        return _pinned;
      }
    }
    for (final notice in _active) {
      if (notice.message == message &&
          notice.kind == kind &&
          notice.pinned == pinned) {
        return notice;
      }
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// 把通知控制器挂到 MaterialApp.builder 里。
///
/// 注意：只提供控制器，不负责渲染，避免 InheritedWidget 每次通知都重建整棵
/// 应用树。真正监听的是 [AppNotificationHost]。
class AppNotificationScope extends InheritedWidget {
  const AppNotificationScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final AppNoticeController controller;

  static AppNoticeController? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppNotificationScope>();
    final scope = element?.widget;
    return scope is AppNotificationScope ? scope.controller : null;
  }

  @override
  bool updateShouldNotify(AppNotificationScope oldWidget) =>
      oldWidget.controller != controller;
}

/// 顶层通知宿主：放在 Navigator 外侧的 Stack 中，因此永远盖在所有路由、
/// 对话框和菜单之上。
class AppNotificationHost extends StatelessWidget {
  const AppNotificationHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = AppNotificationScope.maybeOf(context);
    if (controller == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 88,
          left: 16,
          right: 16,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _NotificationLayer(controller: controller),
          ),
        ),
      ],
    );
  }
}

class _NotificationLayer extends StatelessWidget {
  const _NotificationLayer({required this.controller});

  final AppNoticeController controller;

  @override
  Widget build(BuildContext context) {
    final pinned = controller.pinned;
    final active = controller.active;
    if (pinned == null && active.isEmpty) {
      return const SizedBox.shrink();
    }
    // 最新的瞬时通知排在最上面，保证第二/第三条立即出现在视野内。
    final visible = active.reversed.toList(growable: false);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pinned != null)
                  IgnorePointer(
                    // 常驻错误提示没有按钮，继续完全穿透。
                    child: _NoticeCapsule(notice: pinned),
                  ),
                if (pinned != null && visible.isNotEmpty)
                  const SizedBox(height: 8),
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  IgnorePointer(
                    // 只有带动作的胶囊接收点击；普通提示仍穿透到下方界面。
                    ignoring: visible[i].action == null,
                    child: _NoticeCapsule(notice: visible[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeCapsule extends StatelessWidget {
  const _NoticeCapsule({required this.notice});

  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    late final Color background;
    late final Color foreground;
    late final IconData icon;

    if (notice.pinned) {
      background = scheme.error;
      foreground = scheme.onError;
      icon = Icons.warning_amber_rounded;
    } else {
      switch (notice.kind) {
        case AppNoticeKind.error:
          background = scheme.errorContainer;
          foreground = scheme.onErrorContainer;
          icon = Icons.error_outline;
        case AppNoticeKind.warning:
          background = theme.semantic.warning;
          foreground = theme.semantic.onSemantic;
          icon = Icons.warning_amber_rounded;
        case AppNoticeKind.success:
          background = scheme.primaryContainer;
          foreground = scheme.onPrimaryContainer;
          icon = Icons.check_circle_outline;
        case AppNoticeKind.info:
          background = scheme.primaryContainer;
          foreground = scheme.onPrimaryContainer;
          icon = Icons.info_outline;
      }
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: background,
        elevation: 8,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notice.message,
                  maxLines: notice.pinned ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
              if (notice.action != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final action = notice.action;
                    if (action == null) return;
                    notice.handle?.dismiss();
                    action.onPressed();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    backgroundColor: foreground.withValues(alpha: 0.10),
                    minimumSize: const Size(52, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(notice.action!.label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部提示入口。
///
/// 在正式 App 里，[AppNotificationScope] 由 main.dart 挂在 Navigator 外层，
/// 因而提示永远在对话框/菜单之上。所有调用方（包括测试）都必须提供 Scope。
AppNoticeHandle showTopSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final controller = AppNotificationScope.maybeOf(context);
  if (controller == null) {
    throw FlutterError(
      'showTopSnackBar 需要 AppNotificationScope，请将它挂在 Navigator 外层。',
    );
  }
  return controller.show(
    message,
    kind: isError ? AppNoticeKind.error : AppNoticeKind.info,
    duration: const Duration(milliseconds: 2500),
  );
}

/// 带“撤销”按钮的成功提示。
///
/// [onUndo] 返回实际撤销的条数；0 表示已过期或目标已被修改。撤销按钮只保留
/// 最近一次操作，提示与普通提示一样在 2500 毫秒后自动消失。
AppNoticeHandle showUndoTopSnackBar(
  BuildContext context,
  String message, {
  required int Function() onUndo,
}) {
  final controller = AppNotificationScope.maybeOf(context);
  if (controller == null) {
    throw FlutterError(
      'showUndoTopSnackBar 需要 AppNotificationScope，请将它挂在 Navigator 外层。',
    );
  }
  return controller.show(
    message,
    kind: AppNoticeKind.success,
    duration: const Duration(milliseconds: 2500),
    action: AppNoticeAction(
      label: '撤销',
      onPressed: () {
        final removed = onUndo();
        controller.show(
          removed > 0 ? '已撤销本次记录' : '撤销失败：操作已过期或记录已被修改',
          kind: removed > 0 ? AppNoticeKind.success : AppNoticeKind.error,
          duration: const Duration(milliseconds: 2500),
        );
      },
    ),
  );
}
