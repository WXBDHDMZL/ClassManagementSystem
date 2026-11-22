#ifndef RUNNER_DARK_MODE_H_
#define RUNNER_DARK_MODE_H_

#include <windows.h>

// 深浅色适配工具：让系统绘制的菜单（托盘右键菜单）与窗口标题栏跟随应用主题。
// 内部使用 uxtheme 的未公开导出（按序号取地址并做空值保护），
// 取不到时静默降级为系统默认外观，不影响功能。
namespace dark_mode {

// 设置进程偏好的应用模式，并刷新菜单主题缓存（切换后立即生效）。
void ApplyPreferredAppMode(bool is_dark);

// 让指定窗口（及其弹出的菜单）使用深浅色：窗口主题 + 标题栏。
void ApplyToWindow(HWND window, bool is_dark);

// 读取系统"应用模式"偏好（注册表 AppsUseLightTheme），供启动时初始化。
bool SystemPrefersDark();

}  // namespace dark_mode

#endif  // RUNNER_DARK_MODE_H_
