#include "dark_mode.h"

#include <dwmapi.h>
#include <uxtheme.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

namespace {

// SetPreferredAppMode 的取值。
constexpr int kPreferredAppModeForceDark = 2;
constexpr int kPreferredAppModeForceLight = 3;

// uxtheme!#133：允许某个窗口使用深色模式。
using AllowDarkModeForWindowFn = BOOL(WINAPI*)(HWND, BOOL);
// uxtheme!#135：设置进程偏好的应用模式。
using SetPreferredAppModeFn = int(WINAPI*)(int);
// uxtheme!#136：刷新已缓存的菜单主题（不调用则切换不会立刻生效）。
using FlushMenuThemesFn = void(WINAPI*)();

/// uxtheme 模块句柄：进程内只加载一次（审计 P2-54：此前函数模板按每个实例
/// 各加载一次、且从不释放）。
HMODULE UxthemeModule() {
  static HMODULE module = ::LoadLibraryExW(L"uxtheme.dll", nullptr,
                                           LOAD_LIBRARY_SEARCH_SYSTEM32);
  return module;
}

/// 按导出序号取 uxtheme 里的未公开函数；取不到时返回 nullptr。
template <typename T>
T UxthemeProc(int ordinal) {
  HMODULE module = UxthemeModule();
  if (module == nullptr) {
    return nullptr;
  }
  return reinterpret_cast<T>(
      ::GetProcAddress(module, MAKEINTRESOURCEA(ordinal)));
}

}  // namespace

void dark_mode::ApplyPreferredAppMode(bool is_dark) {
  static auto set_preferred_app_mode =
      UxthemeProc<SetPreferredAppModeFn>(135);
  if (set_preferred_app_mode == nullptr) {
    return;
  }
  set_preferred_app_mode(is_dark ? kPreferredAppModeForceDark
                                 : kPreferredAppModeForceLight);
  // 让已经缓存的菜单主题立即失效，菜单下一次弹出即为新主题。
  static auto flush_menu_themes = UxthemeProc<FlushMenuThemesFn>(136);
  if (flush_menu_themes != nullptr) {
    flush_menu_themes();
  }
}

void dark_mode::ApplyToWindow(HWND window, bool is_dark) {
  if (window == nullptr) {
    return;
  }
  const BOOL dark = is_dark ? TRUE : FALSE;
  static auto allow_dark_mode_for_window =
      UxthemeProc<AllowDarkModeForWindowFn>(133);
  if (allow_dark_mode_for_window != nullptr) {
    allow_dark_mode_for_window(window, dark);
  }
  // 弹出菜单跟随宿主窗口的主题：DarkMode_Explorer 是系统内置的深色主题名。
  ::SetWindowTheme(window, is_dark ? L"DarkMode_Explorer" : L"Explorer",
                   nullptr);
  ::DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                          sizeof(dark));
}

bool dark_mode::SystemPrefersDark() {
  DWORD value = 1;  // 读不到时按浅色处理
  DWORD size = sizeof(value);
  const LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &size);
  if (status != ERROR_SUCCESS) {
    return false;
  }
  return value == 0;
}
