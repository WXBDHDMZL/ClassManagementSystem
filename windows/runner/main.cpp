#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <gdiplus.h>
#include <windows.h>

#include <algorithm>

#include "dark_mode.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 初始化 COM，供库与插件使用。
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 先按系统偏好初始化应用模式（深色菜单需要在窗口创建前先声明），
  // 应用自己的主题确定后会由 Dart 侧通过通道再次校正。
  dark_mode::ApplyPreferredAppMode(dark_mode::SystemPrefersDark());

  // 单实例保护：程序支持最小化到托盘后继续在后台运行，
  // 重复启动会产生两个进程并发写同一份数据文件，因此
  // 第二次启动只唤起已有实例的主窗口，然后本进程直接退出。
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"ClassManagementSystem.Local.SingleInstance");
  if (instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // 按窗口类名 + 标题定位本程序主窗口（可能正处于最小化或隐藏到托盘状态）。
    // 审计 P2-51：第一实例可能"已持有互斥体、窗口尚未创建"——重试等待窗口
    // 出现（最多约 2 秒）；此前不等待直接退出，用户观感是"双击没反应"。
    HWND existing_window = nullptr;
    for (int attempt = 0; attempt < 40 && existing_window == nullptr;
         ++attempt) {
      existing_window = ::FindWindowW(
          L"FLUTTER_RUNNER_WIN32_WINDOW",
          L"\x73ED\x7EA7\x7BA1\x7406\x7CFB\x7EDF");
      if (existing_window == nullptr) {
        ::Sleep(50);
      }
    }
    if (existing_window != nullptr) {
      // 闪烁修复：此时若正处于悬浮球模式，直接 ShowWindow 会让主页面先闪现
      // （球还没收起）。改为投递唤醒消息，由 Flutter 侧先收球、再显示主窗口。
      ::PostMessageW(existing_window, kAppWakeMessage, 0, 0);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  // GDI+：悬浮球图标需要按 Alpha 通道合成为圆形位图。
  Gdiplus::GdiplusStartupInput gdiplus_input;
  ULONG_PTR gdiplus_token = 0;
  if (Gdiplus::GdiplusStartup(&gdiplus_token, &gdiplus_input, nullptr) !=
      Gdiplus::Ok) {
    return EXIT_FAILURE;
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // 审计 P1-26：开机自启动时不显示主窗口 —— 托盘模式带 --tray，
  // 悬浮球模式带 --ball。此前原生首帧无条件 Show()，与 Dart 侧的隐藏
  // 存在时序竞态（窗口一闪）。
  const bool start_to_tray =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tray") != command_line_arguments.end();
  const bool start_to_ball =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--ball") != command_line_arguments.end();
  const bool start_hidden = start_to_tray || start_to_ball;
  // 把启动目标通过进程环境交给 Dart：命令行参数在不同 Flutter 版本里
  // 不一定能从 Platform.executableArguments 读到，环境变量是稳定的。
  if (start_to_ball) {
    SetEnvironmentVariableW(L"CMS_STARTUP_TARGET", L"ball");
  } else if (start_to_tray) {
    SetEnvironmentVariableW(L"CMS_STARTUP_TARGET", L"tray");
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // 审计 P2-53：整段窗口生命周期放进内层作用域 —— **先析构窗口**（释放悬浮球
  // 缓存的 GDI+ 位图等资源），再做 GdiplusShutdown；此前 shutdown 早于析构，
  // 退出期在已关闭的 GDI+ 上调 GdipDisposeImage 属未定义行为。
  {
    FlutterWindow window(project, start_hidden);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    // 窗口标题：班级管理系统（使用 UTF-16 转义，避免源文件编码导致的乱码）
    if (!window.Create(L"\x73ED\x7EA7\x7BA1\x7406\x7CFB\x7EDF", origin, size)) {
      return EXIT_FAILURE;
    }
    // 最小窗口尺寸（逻辑像素，随屏幕缩放自动换算）。
    // 注意：window_manager 插件会截走 WM_GETMINMAXINFO 并自行 return 0，
    // 这里的设置实际不生效；真正生效的是 Dart 侧
    // DesktopService.minimumWindowSize（windowManager.setMinimumSize）。
    // 保留此处仅为不使用插件时的兜底。
    window.SetMinimumSize(Win32Window::Size(1080, 680));
    window.SetQuitOnClose(true);

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  }

  ::CloseHandle(instance_mutex);
  Gdiplus::GdiplusShutdown(gdiplus_token);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
