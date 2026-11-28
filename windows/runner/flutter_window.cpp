#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "dark_mode.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

/// 从 EncodableValue 读整数（Dart 端可能编码为 32 位或 64 位整数）。
int ToInt(const flutter::EncodableValue& value, int fallback) {
  if (const int32_t* int32_value = std::get_if<int32_t>(&value)) {
    return *int32_value;
  }
  if (const int64_t* int64_value = std::get_if<int64_t>(&value)) {
    return static_cast<int>(*int64_value);
  }
  return fallback;
}

/// 从 EncodableValue 读浮点数（Dart 端通常编码为 double）。
double ToDouble(const flutter::EncodableValue& value, double fallback) {
  if (const double* double_value = std::get_if<double>(&value)) {
    return *double_value;
  }
  if (const int32_t* int_value = std::get_if<int32_t>(&value)) {
    return static_cast<double>(*int_value);
  }
  if (const int64_t* int64_value = std::get_if<int64_t>(&value)) {
    return static_cast<double>(*int64_value);
  }
  return fallback;
}

// 取消 DWM 隐形的兜底定时器：即使下一帧回调因异常没有触发，
// 也不能让主窗口永久不可见。
constexpr UINT_PTR kUncloakTimerId = 0x51;

void SetWindowCloaked(HWND window, bool cloaked) {
  const BOOL value = cloaked ? TRUE : FALSE;
  ::DwmSetWindowAttribute(window, DWMWA_CLOAK, &value, sizeof(value));
}

void UncloakWindow(HWND window) {
  SetWindowCloaked(window, false);
  ::KillTimer(window, kUncloakTimerId);
}

/// 悬浮球图标路径：位于 Flutter 资源目录，随安装包一起分发。
std::wstring BallImagePath() {
  // 动态扩展缓冲区，避免安装路径超过 MAX_PATH 时路径被截断。
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = ::GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  while (length == path.size()) {
    path.resize(path.size() * 2);
    length = ::GetModuleFileNameW(
        nullptr, path.data(), static_cast<DWORD>(path.size()));
  }
  path.resize(length);
  const size_t slash = path.find_last_of(L"\\/");
  const std::wstring directory =
      slash == std::wstring::npos ? path : path.substr(0, slash);
  return directory + L"\\data\\flutter_assets\\assets\\icons\\ball.png";
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::ShowMainWindowWithoutFlash() {
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  const bool minimized = ::IsIconic(window) != FALSE;
  const bool hidden = ::IsWindowVisible(window) == FALSE;
  if (!minimized && !hidden) {
    ::SetForegroundWindow(window);
    return;
  }

  // 最小化/隐藏窗口的恢复会立刻露出一块尚未提交 Flutter 帧的客户区，
  // 在部分显卡/缩放下表现为闪一下白底。先用 DWM 把窗口整体隐形，
  // 恢复并强制调度下一帧，帧就绪后再取消隐形。
  SetWindowCloaked(window, true);
  if (minimized) {
    ::ShowWindow(window, SW_RESTORE);
  }
  ::ShowWindow(window, SW_SHOW);
  ::SetForegroundWindow(window);
  ::SetTimer(window, kUncloakTimerId, 400, nullptr);

  if (flutter_controller_ != nullptr && flutter_controller_->engine() != nullptr) {
    flutter_controller_->engine()->SetNextFrameCallback([window]() {
      UncloakWindow(window);
      ::SetForegroundWindow(window);
    });
    flutter_controller_->ForceRedraw();
  } else {
    UncloakWindow(window);
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 悬浮球控制通道：Dart 侧控制显隐，原生侧回传单击与拖动结束事件。
  ball_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "class_management_system/ball",
          &flutter::StandardMethodCodec::GetInstance());
  ball_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "showBall") {
          int x = -1;
          int y = -1;
          if (const auto* arguments =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto x_iterator =
                arguments->find(flutter::EncodableValue("x"));
            if (x_iterator != arguments->end()) {
              x = ToInt(x_iterator->second, -1);
            }
            const auto y_iterator =
                arguments->find(flutter::EncodableValue("y"));
            if (y_iterator != arguments->end()) {
              y = ToInt(y_iterator->second, -1);
            }
          }
          // 修复（审计 P2-52）：球窗口创建失败时返回错误 —— 让 Dart 侧走
          // "恢复主窗口"的回退，而不是静默成功（主窗被藏、球不存在）。
          if (!ball_window_.Show(x, y)) {
            result->Error("ball-unavailable", "悬浮球窗口创建失败");
            return;
          }
          result->Success();
          return;
        }
        if (call.method_name() == "showMainWindow") {
          ShowMainWindowWithoutFlash();
          result->Success();
          return;
        }
        if (call.method_name() == "hideBall") {
          ball_window_.Hide();
          result->Success();
          return;
        }
        if (call.method_name() == "setBallStyle") {
          // 悬浮球外观：opacity 为整球不透明度。
          double opacity = 0.88;
          if (const auto* arguments =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto opacity_iterator =
                arguments->find(flutter::EncodableValue("opacity"));
            if (opacity_iterator != arguments->end()) {
              if (const double* value =
                      std::get_if<double>(&opacity_iterator->second)) {
                opacity = *value;
              } else if (const int32_t* int_value =
                             std::get_if<int32_t>(&opacity_iterator->second)) {
                opacity = static_cast<double>(*int_value);
              }
            }
          }
          ball_window_.SetOpacity(opacity);
          result->Success();
          return;
        }
        if (call.method_name() == "setBallMenuState") {
          // 右键菜单的轻量状态：不透明度、托盘可用、今日摘要与悬浮球行为。
          BallWindow::BallMenuState state;
          if (const auto* arguments =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto opacity_iterator =
                arguments->find(flutter::EncodableValue("opacity"));
            if (opacity_iterator != arguments->end()) {
              state.opacity = ToDouble(opacity_iterator->second, 0.88);
            }
            const auto tray_iterator =
                arguments->find(flutter::EncodableValue("trayReady"));
            if (tray_iterator != arguments->end()) {
              if (const bool* tray_ready =
                      std::get_if<bool>(&tray_iterator->second)) {
                state.tray_ready = *tray_ready;
              }
            }
            const auto praise_iterator =
                arguments->find(flutter::EncodableValue("todayPraise"));
            if (praise_iterator != arguments->end()) {
              state.today_praise = ToInt(praise_iterator->second, 0);
            }
            const auto criticize_iterator =
                arguments->find(flutter::EncodableValue("todayCriticize"));
            if (criticize_iterator != arguments->end()) {
              state.today_criticize = ToInt(criticize_iterator->second, 0);
            }
            const auto lock_iterator =
                arguments->find(flutter::EncodableValue("positionLocked"));
            if (lock_iterator != arguments->end()) {
              if (const bool* locked =
                      std::get_if<bool>(&lock_iterator->second)) {
                state.position_locked = *locked;
              }
            }
            const auto praise_enabled_iterator =
                arguments->find(flutter::EncodableValue("praiseEnabled"));
            if (praise_enabled_iterator != arguments->end()) {
              if (const bool* enabled =
                      std::get_if<bool>(&praise_enabled_iterator->second)) {
                state.praise_enabled = *enabled;
              }
            }
            const auto criticize_enabled_iterator =
                arguments->find(flutter::EncodableValue("criticismEnabled"));
            if (criticize_enabled_iterator != arguments->end()) {
              if (const bool* enabled =
                      std::get_if<bool>(&criticize_enabled_iterator->second)) {
                state.criticize_enabled = *enabled;
              }
            }
          }
          ball_window_.SetMenuState(state);
          result->Success();
          return;
        }
        if (call.method_name() == "setDarkMode") {
          const bool* is_dark = std::get_if<bool>(call.arguments());
          if (is_dark == nullptr) {
            result->Error("invalid_argument", "需要一个布尔参数");
            return;
          }
          dark_mode::ApplyPreferredAppMode(*is_dark);
          dark_mode::ApplyToWindow(GetHandle(), *is_dark);
          // 修复（审计 P2-55）：记录应用主题 —— 系统强调色变化时标题栏
          // 跟随应用主题，而不是被注册表里的系统偏好覆盖。
          Win32Window::SetAppDarkModeOverride(*is_dark);
          ball_window_.SetDarkMode(*is_dark);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  // 创建悬浮球窗口（默认隐藏，等 Dart 侧通知再显示）。
  if (ball_window_.Create(BallImagePath())) {
    ball_window_.on_click = [this]() {
      if (ball_channel_) {
        ball_channel_->InvokeMethod(
            "onBallClicked", std::make_unique<flutter::EncodableValue>());
      }
    };
    ball_window_.on_moved = [this](int x, int y) {
      if (ball_channel_) {
        flutter::EncodableMap arguments = {
            {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
            {flutter::EncodableValue("y"), flutter::EncodableValue(y)}};
        ball_channel_->InvokeMethod(
            "onBallMoved",
            std::make_unique<flutter::EncodableValue>(arguments));
      }
    };
    ball_window_.on_menu_command = [this](BallWindow::BallMenuCommand command) {
      if (!ball_channel_) {
        return;
      }
      std::string action;
      double value = 0.0;
      bool has_value = false;
      switch (command) {
        case BallWindow::BallMenuCommand::kOpen:
          action = "open";
          break;
        case BallWindow::BallMenuCommand::kQuickPraise:
          action = "quickPraise";
          break;
        case BallWindow::BallMenuCommand::kQuickCriticize:
          action = "quickCriticize";
          break;
        case BallWindow::BallMenuCommand::kTodayRecords:
          action = "todayRecords";
          break;
        case BallWindow::BallMenuCommand::kHistory:
          action = "history";
          break;
        case BallWindow::BallMenuCommand::kStatistics:
          action = "statistics";
          break;
        case BallWindow::BallMenuCommand::kSettings:
          action = "settings";
          break;
        case BallWindow::BallMenuCommand::kHideToTray:
          action = "hideToTray";
          break;
        case BallWindow::BallMenuCommand::kExit:
          action = "exit";
          break;
        case BallWindow::BallMenuCommand::kTogglePositionLock:
          action = "togglePositionLock";
          break;
        default: {
          const int opacity_index =
              static_cast<int>(command) -
              static_cast<int>(BallWindow::BallMenuCommand::kOpacityBase);
          if (opacity_index < 0 || opacity_index > 13) {
            return;
          }
          action = "setOpacity";
          value = 0.35 + opacity_index * 0.05;
          has_value = true;
          break;
        }
      }
      flutter::EncodableMap arguments = {
          {flutter::EncodableValue("action"), flutter::EncodableValue(action)}};
      if (has_value) {
        arguments[flutter::EncodableValue("value")] =
            flutter::EncodableValue(value);
      }
      ball_channel_->InvokeMethod(
          "onBallMenuCommand",
          std::make_unique<flutter::EncodableValue>(arguments));
    };
  } else {
    OutputDebugStringW(L"[FlutterWindow] 悬浮球窗口创建失败\n");
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // 审计 P1-26：--tray / --ball 启动时不显示主窗口（开机自启进托盘或悬浮球）。
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 通道依赖引擎的消息器，先于控制器释放。
  ball_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 兜底取消 cloak 必须优先于 Flutter 的消息处理，避免定时器被消费后
  // 主窗口一直保持隐形。
  if (message == WM_TIMER && wparam == kUncloakTimerId) {
    UncloakWindow(hwnd);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // 修复（审计 P2-56）：广播消息可能先于控制器创建/后于销毁到达，补空值守卫。
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;

    case WM_QUERYENDSESSION:
      // 关机/注销：显式放行，绝不阻塞系统关机。
      // 已知取舍（审计 P2-xx）：C++ 无法等待 Dart 异步写盘链，本次会话
      // 尚未落盘的最近一次异步保存可能丢失；但保存走 AtomicFile 原子写，
      // 主数据文件绝不会出现半截/损坏，最坏情况仅损失最后一次未落盘的修改。
      // 数据文件在文档目录，关机不会触碰。
      return TRUE;

    case WM_ENDSESSION:
      // 会话即将结束，进程将被系统直接终止；无需额外收尾（见 WM_QUERYENDSESSION 注释）。
      return 0;
  }

  if (message == kAppWakeMessage && ball_channel_) {
    // 单实例二次启动的唤醒：交给 Dart 统一处理（收球 → 显示主窗口 → 前置焦点）。
    ball_channel_->InvokeMethod("wakeup",
                                std::make_unique<flutter::EncodableValue>());
    return 0;
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
