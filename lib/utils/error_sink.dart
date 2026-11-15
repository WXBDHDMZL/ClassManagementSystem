/* 
 * 班级管理系统 - Class Management System 
 * 作者 (Author): WXBDHDMZL
 * 版权 (Copyright): © 2026 WXBDHDMZL
 * 许可证 (License): AGPL-3.0-only
 * 版本 (Version): V4.9.8
 * 创建日期 (Created): 2026-10-02 
 * 
 * 本软件以 GNU Affero General Public License v3.0 only（AGPL-3.0-only）发布。
 * 你可以依据该许可证使用、修改和再分发本软件；完整条款见根目录 LICENSE.txt。
 */

/// 错误落盘通道（**零 Flutter 依赖**，可被 models 层安全使用）。
/// 位置（代码审查报告 H7）：放在 `utils/` 而非 `services/` —— 它只是
/// typedef + 注入点，与"业务服务"语义无关；移动后 `models → services`
/// 的反向依赖在分层图上不再成立。
///
/// 背景（N-5）：`models/app_data.dart` 与 `app_settings.dart` 此前直接 import
/// `services/error_log_service.dart`——后者依赖 `package:flutter/material.dart`
/// 与 `dart:ui`，于是**纯数据层反向依赖了 UI 层**：在纯 Dart 环境下（无 Flutter
/// 绑定）这些模型连"加载时丢了几条数据"的日志都写不出来。
///
/// 这里把"写日志"抽象成一个可注入的回调：模型层只依赖本文件，
/// 真正的实现（写文件 + 串行队列）由 `error_log_service.dart` 在启动时注入。
library;

/// 错误接收器签名：tag / 错误内容 / 调用栈（栈可为空）/ 场景说明（可为空）。
typedef ErrorSink = void Function(
  String tag,
  Object error,
  StackTrace? stack, {
  String? context,
});

ErrorSink? _sink;

/// 注入实现（由 `error_log_service.dart` 在 `installErrorLog()` 时调用）。
void setErrorSink(ErrorSink sink) => _sink = sink;

/// 上报一条错误。
///
/// [context] 描述"当时在做什么"（如"保存数据：自动备份"），便于排查定位。
///
/// **绝不抛异常**：没有注入实现（如纯 Dart 单测）时静默丢弃，只当没有日志通道。
/// 调用方不需要 try/catch。
void reportError(String tag, Object error, [StackTrace? stack, String? context]) {
  final sink = _sink;
  if (sink == null) return;
  try {
    sink(tag, error, stack, context: context);
  } catch (_) {
    // 日志通道自身出错绝不影响主流程。
  }
}
