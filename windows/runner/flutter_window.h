#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "ball_window.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
// 单实例二次启动的唤醒消息：由第二个进程投递给已有主窗口，
// 主窗口收到后转交 Dart 侧处理（先收悬浮球、再显示主窗口），
// 避免原生直接 ShowWindow 造成主页面闪现。
constexpr UINT kAppWakeMessage = WM_APP + 0x4C4D;

class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // [start_hidden] 为 true 时（开机自启动 --tray / --ball）首帧不显示主窗口，
  // 由 Dart 侧按需显示（审计 P1-26）。
  FlutterWindow(const flutter::DartProject& project, bool start_hidden);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // 先恢复/显示窗口，等 Flutter 提交下一帧后再取消 DWM 隐形，
  // 避免最小化恢复时先露出空白白底。
  void ShowMainWindowWithoutFlash();

  // The project to run.
  flutter::DartProject project_;

  // 启动时是否隐藏主窗口（--tray / --ball 开机自启动）。
  bool start_hidden_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 悬浮球控制通道：Dart 控制显隐，原生回传单击/拖动事件。
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      ball_channel_;

  // 桌面悬浮球：独立的原生分层小窗口。
  BallWindow ball_window_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
