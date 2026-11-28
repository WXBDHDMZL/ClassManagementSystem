#include "ball_window.h"

#include <flutter_windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <cmath>

#include "dark_mode.h"

namespace {

constexpr const wchar_t kBallWindowClassName[] =
    L"ClassManagementSystemBall";
// 窗口标题仅用于调试识别（球是 WS_POPUP，不显示标题）：悬浮球
constexpr const wchar_t kBallWindowTitle[] = L"\x60AC\x6D6E\x7403";
constexpr int kLogicalSize = 56;     // 逻辑直径（像素）
constexpr int kDragThreshold = 4;    // 逻辑像素：超过即视为拖动（比较前按 DPI 换算）
constexpr int kDefaultMargin = 24;   // 默认位置距工作区右下角的间距
constexpr int kVisibleSlack = 8;     // 允许越出工作区的容差（避免球被藏到屏幕外）

// 右键菜单命令 ID（仅本窗口使用，使用 40001 起避免与系统命令冲突）。
constexpr UINT kMenuOpen = 40001;
constexpr UINT kMenuQuickPraise = 40002;
constexpr UINT kMenuQuickCriticize = 40003;
// 40004 曾用于“追加记录”，已取消；保留空号避免影响其他菜单命令 ID。
constexpr UINT kMenuTodayRecords = 40005;
constexpr UINT kMenuHistory = 40006;
constexpr UINT kMenuStatistics = 40007;
constexpr UINT kMenuSettings = 40008;
constexpr UINT kMenuOpacityBase = 40009;
constexpr int kMenuOpacityCount = 14;
constexpr UINT kMenuHideToTray = 40023;
constexpr UINT kMenuExit = 40024;
constexpr UINT kMenuTogglePositionLock = 40025;

}  // namespace

BallWindow::BallWindow() = default;

BallWindow::~BallWindow() {
  if (window_handle_ != nullptr) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

bool BallWindow::Create(const std::wstring& image_path) {
  image_path_ = image_path;
  HINSTANCE instance = GetModuleHandle(nullptr);

  // 注册窗口类（进程内只注册一次）。
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASS window_class = {};
    window_class.hCursor = LoadCursor(nullptr, IDC_HAND);
    window_class.hInstance = instance;
    window_class.lpfnWndProc = BallWindow::WndProc;
    window_class.lpszClassName = kBallWindowClassName;
    if (RegisterClass(&window_class) == 0) {
      return false;
    }
    class_registered = true;
  }

  int x = 0;
  int y = 0;
  ResolveDefaultPosition(&x, &y);

  // 初始尺寸按主显示器 DPI 换算（Show 时会按实际位置所在显示器重算）。
  const UINT primary_dpi = FlutterDesktopGetDpiForMonitor(
      MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY));
  const int initial_size =
      static_cast<int>(std::lround(kLogicalSize * primary_dpi / 96.0));
  window_handle_ = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kBallWindowClassName, kBallWindowTitle, WS_POPUP, x, y, initial_size,
      initial_size, nullptr, nullptr, instance, this);
  return window_handle_ != nullptr;
}

bool BallWindow::Show(int physical_x, int physical_y) {
  if (window_handle_ == nullptr) {
    return false;
  }
  // 多显示器时副屏可能位于主屏左侧/上方，坐标合法为负数；
  // 只用可见性判断，不能把负坐标当成无效位置。
  // 审计 P2-47：(-1,-1) 是 Dart 侧的"未记录位置"哨兵 —— 它可能恰好落在
  // 主屏工作区左上角附近被判为"可见"，导致球停在哨兵位置而不是默认位置。
  if (physical_x == -1 && physical_y == -1) {
    ResolveDefaultPosition(&physical_x, &physical_y);
  } else if (!IsPositionVisible(physical_x, physical_y)) {
    // 未记录位置或位置已越界（换屏/改分辨率）：回到默认位置。
    ResolveDefaultPosition(&physical_x, &physical_y);
  }
  is_pressing_ = false;
  is_dragging_ = false;
  locked_drag_attempt_ = false;
  RenderAt(physical_x, physical_y);
  ShowWindow(window_handle_, SW_SHOWNOACTIVATE);
  SetWindowPos(window_handle_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  is_visible_ = true;
  return true;
}

void BallWindow::Hide() {
  if (window_handle_ == nullptr) {
    return;
  }
  is_pressing_ = false;
  is_dragging_ = false;
  locked_drag_attempt_ = false;
  ShowWindow(window_handle_, SW_HIDE);
  is_visible_ = false;
}

void BallWindow::SetDarkMode(bool is_dark) {
  if (is_dark_ == is_dark) {
    return;
  }
  is_dark_ = is_dark;
  // 球正在显示时立即重绘，切换主题即时生效。
  if (is_visible_ && window_handle_ != nullptr) {
    RenderAt(window_x_, window_y_);
  }
}

void BallWindow::SetOpacity(double opacity) {
  const double clamped = opacity < 0.35 ? 0.35 : (opacity > 1.0 ? 1.0 : opacity);
  if (std::abs(clamped - opacity_) < 0.001) {
    return;
  }
  opacity_ = clamped;
  if (is_visible_ && window_handle_ != nullptr) {
    RenderAt(window_x_, window_y_);
  }
}

void BallWindow::SetMenuState(const BallMenuState& state) {
  menu_state_ = state;
}

bool BallWindow::IsVisible() const {
  return is_visible_;
}

void BallWindow::ShowContextMenu(HWND window) {
  if (!is_visible_ || window == nullptr) {
    return;
  }

  // 原生弹出菜单跟随应用深浅色；这里必须在下发菜单前刷新一次，
  // 否则同一个进程内切换主题后菜单仍沿用系统默认颜色。
  dark_mode::ApplyPreferredAppMode(is_dark_);

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  HMENU quick_menu = CreatePopupMenu();
  HMENU today_menu = CreatePopupMenu();
  HMENU ball_menu = CreatePopupMenu();
  HMENU opacity_menu = CreatePopupMenu();
  if (quick_menu == nullptr || today_menu == nullptr || ball_menu == nullptr ||
      opacity_menu == nullptr) {
    if (quick_menu != nullptr) DestroyMenu(quick_menu);
    if (today_menu != nullptr) DestroyMenu(today_menu);
    if (ball_menu != nullptr) DestroyMenu(ball_menu);
    if (opacity_menu != nullptr) DestroyMenu(opacity_menu);
    DestroyMenu(menu);
    return;
  }

  // 设置中停用的记录类型必须灰化：否则用户点了“表扬”，对话框会
  // 静默回退到“批评”，最终可能把表扬记成批评。
  AppendMenuW(quick_menu,
              MF_STRING | (menu_state_.praise_enabled ? 0 : MF_GRAYED),
              kMenuQuickPraise, L"表扬…");
  AppendMenuW(quick_menu,
              MF_STRING | (menu_state_.criticize_enabled ? 0 : MF_GRAYED),
              kMenuQuickCriticize, L"批评…");

  AppendMenuW(today_menu, MF_STRING | MF_GRAYED, 0,
              (L"今日：表扬 " + std::to_wstring(menu_state_.today_praise) +
               L" · 批评 " + std::to_wstring(menu_state_.today_criticize))
                  .c_str());
  AppendMenuW(today_menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(today_menu, MF_STRING, kMenuTodayRecords, L"查看今日记录");
  AppendMenuW(today_menu, MF_STRING, kMenuHistory, L"历史记录…");
  AppendMenuW(today_menu, MF_STRING, kMenuStatistics, L"数据统计…");

  for (int index = 0; index < kMenuOpacityCount; ++index) {
    const int percent = 35 + index * 5;
    AppendMenuW(opacity_menu, MF_STRING, kMenuOpacityBase + index,
                (std::to_wstring(percent) + L"%").c_str());
  }
  int checked_index = static_cast<int>(
      std::lround((menu_state_.opacity * 100.0 - 35.0) / 5.0));
  if (checked_index < 0) checked_index = 0;
  if (checked_index >= kMenuOpacityCount) {
    checked_index = kMenuOpacityCount - 1;
  }
  const UINT checked_opacity = kMenuOpacityBase + checked_index;
  CheckMenuRadioItem(opacity_menu, kMenuOpacityBase,
                     kMenuOpacityBase + kMenuOpacityCount - 1, checked_opacity,
                     MF_BYCOMMAND);

  AppendMenuW(ball_menu, MF_POPUP,
              reinterpret_cast<UINT_PTR>(opacity_menu), L"不透明度");
  AppendMenuW(ball_menu,
              MF_STRING | (menu_state_.position_locked ? MF_CHECKED : MF_UNCHECKED),
              kMenuTogglePositionLock, L"锁定位置");
  AppendMenuW(ball_menu, MF_STRING | (menu_state_.tray_ready ? 0 : MF_GRAYED),
              kMenuHideToTray, L"收起到托盘");

  AppendMenuW(menu, MF_STRING, kMenuOpen, L"打开班级管理系统");
  SetMenuDefaultItem(menu, kMenuOpen, FALSE);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(quick_menu),
              L"快速记录");
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(today_menu),
              L"今日概览");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(ball_menu),
              L"悬浮球");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuSettings, L"设置…");
  AppendMenuW(menu, MF_STRING, kMenuExit, L"退出程序");

  POINT cursor;
  GetCursorPos(&cursor);
  // 先设置前台窗口再弹菜单，保证点击菜单外或按 Esc 时菜单能正常关闭。
  SetForegroundWindow(window);
  const UINT command = TrackPopupMenuEx(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY | TPM_WORKAREA,
      cursor.x, cursor.y, window, nullptr);
  PostMessageW(window, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (command == 0) {
    return;
  }

  BallMenuCommand menu_command;
  switch (command) {
    case kMenuOpen:
      menu_command = BallMenuCommand::kOpen;
      break;
    case kMenuQuickPraise:
      menu_command = BallMenuCommand::kQuickPraise;
      break;
    case kMenuQuickCriticize:
      menu_command = BallMenuCommand::kQuickCriticize;
      break;
    case kMenuTodayRecords:
      menu_command = BallMenuCommand::kTodayRecords;
      break;
    case kMenuHistory:
      menu_command = BallMenuCommand::kHistory;
      break;
    case kMenuStatistics:
      menu_command = BallMenuCommand::kStatistics;
      break;
    case kMenuSettings:
      menu_command = BallMenuCommand::kSettings;
      break;
    case kMenuHideToTray:
      menu_command = BallMenuCommand::kHideToTray;
      break;
    case kMenuExit:
      menu_command = BallMenuCommand::kExit;
      break;
    case kMenuTogglePositionLock:
      menu_command = BallMenuCommand::kTogglePositionLock;
      break;
    default:
      if (command >= kMenuOpacityBase &&
          command < kMenuOpacityBase + kMenuOpacityCount) {
        menu_command = static_cast<BallMenuCommand>(
            static_cast<int>(BallMenuCommand::kOpacityBase) +
            static_cast<int>(command - kMenuOpacityBase));
        break;
      }
      return;
  }
  if (on_menu_command) {
    on_menu_command(menu_command);
  }
}

void BallWindow::FinishDrag() {
  if (window_handle_ == nullptr || window_size_ <= 0) {
    return;
  }

  // 把球完整夹回当前显示器工作区，避免拖到一半时有一部分留在屏外。
  POINT point = {window_x_, window_y_};
  HMONITOR monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfo(monitor, &info)) {
    const int max_x = static_cast<int>(info.rcWork.right) - window_size_;
    const int max_y = static_cast<int>(info.rcWork.bottom) - window_size_;
    const int min_x = static_cast<int>(info.rcWork.left);
    const int min_y = static_cast<int>(info.rcWork.top);
    const int clamped_x = std::clamp(window_x_, min_x, max_x);
    const int clamped_y = std::clamp(window_y_, min_y, max_y);
    if (clamped_x != window_x_ || clamped_y != window_y_) {
      RenderAt(clamped_x, clamped_y);
    }
  }

  if (on_moved) {
    on_moved(window_x_, window_y_);
  }
}

void BallWindow::RenderAt(int physical_x, int physical_y) {
  if (window_handle_ == nullptr) {
    return;
  }

  // 球跨屏拖动时按目标位置所在显示器重新取 DPI，保证大小与清晰度。
  POINT target = {physical_x, physical_y};
  HMONITOR monitor = MonitorFromPoint(target, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = dpi / 96.0;
  const int size = static_cast<int>(std::lround(kLogicalSize * scale));
  if (size <= 0) {
    return;
  }

  HDC screen_dc = GetDC(nullptr);
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  BITMAPINFO bitmap_info = {};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = size;
  bitmap_info.bmiHeader.biHeight = -size;  // 负数：自上而下的位图
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS,
                                    &bits, nullptr, 0);
  if (bitmap == nullptr || bits == nullptr) {
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return;
  }
  HGDIOBJ previous = SelectObject(memory_dc, bitmap);

  {
    Gdiplus::Bitmap canvas(size, size, size * 4, PixelFormat32bppPARGB,
                           static_cast<BYTE*>(bits));
    Gdiplus::Graphics graphics(&canvas);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);

    const Gdiplus::REAL diameter = static_cast<Gdiplus::REAL>(size);
    const Gdiplus::REAL radius = diameter / 2.0f;
    // 普通半透明底：真正的透明混合由系统合成器实时完成，窗口不采集桌面像素。
    // 浅色主题用带一点蓝调的浅灰，避免在白色桌面上"白成一片"。
    constexpr BYTE kBaseAlpha = 228;
    const Gdiplus::Color fill =
        is_dark_ ? Gdiplus::Color(kBaseAlpha, 36, 38, 44)
                 : Gdiplus::Color(kBaseAlpha, 148, 168, 192);
    Gdiplus::SolidBrush fill_brush(fill);
    graphics.FillEllipse(&fill_brush, 0.0f, 0.0f, diameter, diameter);

    // 图标：只解码一次并缓存。
    if (icon_image_ == nullptr) {
      auto loaded = std::make_unique<Gdiplus::Image>(image_path_.c_str());
      if (loaded->GetLastStatus() == Gdiplus::Ok) {
        icon_image_ = std::move(loaded);
      }
    }
    if (icon_image_ != nullptr) {
      const Gdiplus::REAL inset = diameter * 0.16f;
      const Gdiplus::REAL icon_size = diameter - inset * 2.0f;
      graphics.DrawImage(icon_image_.get(), inset, inset, icon_size, icon_size);
    } else {
      // 图标缺失时在圆底上写一个"班"字，保证球仍然可用（正常不会发生）。
      OutputDebugStringW(L"[BallWindow] 球图标加载失败，改用文字标识\n");
      Gdiplus::Font font(L"Microsoft YaHei", diameter * 0.5f,
                         Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
      Gdiplus::SolidBrush text_brush(Gdiplus::Color(255, 59, 130, 246));
      Gdiplus::StringFormat text_format;
      text_format.SetAlignment(Gdiplus::StringAlignmentCenter);
      text_format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
      graphics.DrawString(L"\x73ED", -1, &font,
                          Gdiplus::RectF(0, 0, diameter, diameter),
                          &text_format, &text_brush);
    }

    // 圆外清零 + 整球透明度（PARGB 需连同颜色一起缩放）。
    BYTE* pixels = static_cast<BYTE*>(bits);
    const float center = (diameter - 1.0f) / 2.0f;
    for (int row = 0; row < size; ++row) {
      for (int col = 0; col < size; ++col) {
        BYTE* pixel = pixels + (static_cast<size_t>(row) * size + col) * 4;
        const float dx = col - center;
        const float dy = row - center;
        const float distance = std::sqrt(dx * dx + dy * dy);
        if (distance >= radius + 0.5f) {
          pixel[0] = 0;
          pixel[1] = 0;
          pixel[2] = 0;
          pixel[3] = 0;
          continue;
        }
        // 边缘 1px 内按距离渐变，保住抗锯齿的柔和边。
        const double edge =
            distance <= radius - 0.5f ? 1.0 : (radius + 0.5f - distance);
        const double factor = opacity_ * (edge > 1.0 ? 1.0 : edge);
        for (int channel = 0; channel < 4; ++channel) {
          pixel[channel] =
              static_cast<BYTE>(std::lround(pixel[channel] * factor));
        }
      }
    }
  }

  POINT destination = {physical_x, physical_y};
  SIZE window_size = {size, size};
  POINT source = {0, 0};
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  UpdateLayeredWindow(window_handle_, screen_dc, &destination, &window_size,
                      memory_dc, &source, 0, &blend, ULW_ALPHA);

  SelectObject(memory_dc, previous);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  window_x_ = physical_x;
  window_y_ = physical_y;
  window_size_ = size;
}

void BallWindow::ResolveDefaultPosition(int* physical_x,
                                        int* physical_y) const {
  POINT origin = {0, 0};
  HMONITOR monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &info);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = dpi / 96.0;
  const int margin = static_cast<int>(std::lround(kDefaultMargin * scale));
  const int size = static_cast<int>(std::lround(kLogicalSize * scale));
  *physical_x = info.rcWork.right - size - margin;
  *physical_y = info.rcWork.bottom - size - margin;
}

bool BallWindow::IsPositionVisible(int physical_x, int physical_y) {
  // 审计 P2-46：原实现只看左上角单点，球宽 56 只露 9px 也判"可见"。
  // 改为取 DPI 换算后的整球矩形，用球心是否落在任一屏幕工作区内判定，
  // 保证球至少半颗在可操作区域内（负坐标副屏天然支持）。
  POINT origin = {physical_x, physical_y};
  HMONITOR monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) {
    return false;
  }
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const int size = static_cast<int>(std::lround(kLogicalSize * dpi / 96.0));
  const int center_x = physical_x + size / 2;
  const int center_y = physical_y + size / 2;
  POINT center = {center_x, center_y};
  monitor = MonitorFromPoint(center, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) {
    return false;
  }
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &info)) {
    return false;
  }
  return center_x >= info.rcWork.left - kVisibleSlack &&
         center_y >= info.rcWork.top - kVisibleSlack &&
         center_x < info.rcWork.right + kVisibleSlack &&
         center_y < info.rcWork.bottom + kVisibleSlack;
}

LRESULT CALLBACK BallWindow::WndProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
  } else {
    auto* that = reinterpret_cast<BallWindow*>(
        GetWindowLongPtr(window, GWLP_USERDATA));
    if (that != nullptr) {
      return that->HandleMessage(window, message, wparam, lparam);
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT BallWindow::HandleMessage(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST: {
      // 只有圆内响应鼠标；方形窗口的透明边角直接穿透到下面的窗口。
      POINT screen = {static_cast<short>(LOWORD(lparam)),
                      static_cast<short>(HIWORD(lparam))};
      RECT rect;
      GetWindowRect(window, &rect);
      const double cx = (rect.left + rect.right) / 2.0;
      const double cy = (rect.top + rect.bottom) / 2.0;
      const double radius = (rect.right - rect.left) / 2.0;
      const double dx = screen.x - cx;
      const double dy = screen.y - cy;
      if (dx * dx + dy * dy <= (radius + 1.0) * (radius + 1.0)) {
        return HTCLIENT;
      }
      return HTTRANSPARENT;
    }
    case WM_LBUTTONDOWN: {
      // 记录按下位置，用于区分"单击恢复"与"按住拖动"。
      is_pressing_ = true;
      is_dragging_ = false;
      locked_drag_attempt_ = false;
      GetCursorPos(&press_cursor_);
      press_anchor_x_ = window_x_;
      press_anchor_y_ = window_y_;
      SetCapture(window);
      return 0;
    }
    case WM_MOUSEMOVE: {
      if (!is_pressing_) {
        break;
      }
      POINT cursor;
      GetCursorPos(&cursor);
      // 阈值按窗口所在显示器 DPI 换算（逻辑像素）。
      const int drag_threshold =
          kDragThreshold * static_cast<int>(::GetDpiForWindow(window)) / 96;
      if (!is_dragging_ &&
          (std::abs(cursor.x - press_cursor_.x) > drag_threshold ||
           std::abs(cursor.y - press_cursor_.y) > drag_threshold)) {
        if (menu_state_.position_locked) {
          // 锁定位置：拖动尝试不移动球，但松手时不要误触发单击恢复。
          locked_drag_attempt_ = true;
        } else {
          is_dragging_ = true;
        }
      }
      if (is_dragging_) {
        const int target_x =
            press_anchor_x_ + (cursor.x - press_cursor_.x);
        const int target_y =
            press_anchor_y_ + (cursor.y - press_cursor_.y);
        RenderAt(target_x, target_y);
      }
      return 0;
    }
    case WM_LBUTTONUP: {
      if (!is_pressing_) {
        break;
      }
      // 先快照再释放捕获：ReleaseCapture 会同步触发 WM_CAPTURECHANGED，
      // 该消息会把拖动状态复位，晚读就拿不到"这次是不是拖动"了。
      const bool was_dragging = is_dragging_;
      const bool was_locked_attempt = locked_drag_attempt_;
      is_pressing_ = false;
      is_dragging_ = false;
      locked_drag_attempt_ = false;
      ReleaseCapture();
      if (was_dragging) {
        FinishDrag();
      } else if (!was_locked_attempt && on_click) {
        on_click();
      }
      return 0;
    }
    case WM_RBUTTONDOWN:
      // 记录右键按下位置；右键拖动同样不移动球，只是不弹菜单。
      if (!is_pressing_ && !is_right_pressing_) {
        is_right_pressing_ = true;
        GetCursorPos(&right_press_cursor_);
        SetCapture(window);
      }
      return 0;
    case WM_RBUTTONUP: {
      if (!is_right_pressing_) {
        break;
      }
      POINT cursor;
      GetCursorPos(&cursor);
      const int drag_threshold =
          kDragThreshold * static_cast<int>(::GetDpiForWindow(window)) / 96;
      const bool was_dragging =
          std::abs(cursor.x - right_press_cursor_.x) > drag_threshold ||
          std::abs(cursor.y - right_press_cursor_.y) > drag_threshold;
      is_right_pressing_ = false;
      ReleaseCapture();
      if (!was_dragging) {
        ShowContextMenu(window);
      }
      return 0;
    }
    case WM_CONTEXTMENU:
      // 自定义菜单已经由 WM_RBUTTONUP 弹出，阻止系统再弹一次默认菜单。
      return 0;
    case WM_CAPTURECHANGED:
      // 捕获被系统或其他窗口抢走（如弹出 UAC、切换应用）时复位，
      // 否则会停在"按下中"状态，之后鼠标划过球就会意外拖动。
      is_pressing_ = false;
      is_dragging_ = false;
      is_right_pressing_ = false;
      locked_drag_attempt_ = false;
      return 0;
    case WM_DESTROY:
      window_handle_ = nullptr;
      is_visible_ = false;
      return 0;
    default:
      break;
  }
  return DefWindowProc(window, message, wparam, lparam);
}
