#ifndef RUNNER_BALL_WINDOW_H_
#define RUNNER_BALL_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

#include <gdiplus.h>

// 桌面悬浮球：独立的原生分层窗口（WS_EX_LAYERED，每像素 Alpha 的圆形图标）。
// 普通半透明外观：主题色半透明圆底 + 图标，桌面内容由系统合成器实时透出。
// 球始终置顶、不进入任务栏、不抢焦点；逻辑尺寸 56×56，按所在显示器 DPI 缩放。
// 单击（按下后未拖动即松开）触发 on_click；拖动结束触发 on_moved。
class BallWindow {
 public:
  // 悬浮球右键菜单命令（原生菜单 → Flutter 侧）。
  enum class BallMenuCommand {
    kOpen = 1,
    kQuickPraise,
    kQuickCriticize,
    kTodayRecords,
    kHistory,
    kStatistics,
    kSettings,
    kOpacityBase,
    kOpacityLast = kOpacityBase + 13,
    kHideToTray,
    kExit,
    kTogglePositionLock,
  };

  // 打开菜单前由 Dart 侧同步的轻量状态。
  struct BallMenuState {
    double opacity = 0.88;
    bool tray_ready = true;
    int today_praise = 0;
    int today_criticize = 0;
    bool position_locked = false;
    bool praise_enabled = true;
    bool criticize_enabled = true;
  };

  BallWindow();
  ~BallWindow();

  // 创建隐藏的球窗口：image_path 为球图标 PNG 的完整路径。
  bool Create(const std::wstring& image_path);

  // 显示球：x/y 为屏幕物理像素坐标；传负数表示使用默认位置
  // （主显示器工作区右下角）。
  bool Show(int physical_x, int physical_y);

  // 隐藏球（保留窗口，可再次显示）。
  void Hide();

  // 跟随应用主题：深色模式用深色半透明底，浅色模式用近白半透明底。
  void SetDarkMode(bool is_dark);

  // 外观设置：opacity 为整球不透明度（0.35–1.0）。
  void SetOpacity(double opacity);

  // 右键菜单状态：不透明度勾选项与托盘是否可用。
  void SetMenuState(const BallMenuState& state);

  bool IsVisible() const;

  // 拖动结束后回调（屏幕物理像素坐标），用于持久化位置。
  std::function<void(int physical_x, int physical_y)> on_moved;

  // 单击（按下后未拖动）回调，用于恢复主窗口。
  std::function<void()> on_click;

  // 右键菜单命令回调。
  std::function<void(BallMenuCommand command)> on_menu_command;

 private:
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam);

  // 在鼠标位置弹出右键菜单，并把选择结果转成 on_menu_command。
  void ShowContextMenu(HWND window);

  // 按目标位置所在显示器的 DPI 生成圆形位图并呈现到指定物理坐标。
  void RenderAt(int physical_x, int physical_y);

  // 拖动结束：夹回工作区并回调最终位置。
  void FinishDrag();

  // 把球夹回当前所在显示器的工作区并按新位置重绘（审计 A-14）。
  // 拖动结束、分辨率/DPI 变化、显示器拔插后都要走一次。
  void ClampToVisibleArea();

  // 计算"默认位置"（主显示器工作区右下角，物理像素）。
  void ResolveDefaultPosition(int* physical_x, int* physical_y) const;

  // 位置是否落在某个显示器的工作区内（允许少量越界，避免球被藏到屏幕外）。
  static bool IsPositionVisible(int physical_x, int physical_y);

  HWND window_handle_ = nullptr;
  std::wstring image_path_;
  int window_x_ = 0;
  int window_y_ = 0;
  int window_size_ = 0;
  bool is_visible_ = false;

  // 是否深色模式（跟随应用主题）。
  bool is_dark_ = false;

  // 外观：整球不透明度。
  double opacity_ = 0.88;

  // 右键菜单状态（不透明度勾选项、托盘是否可用）。
  BallMenuState menu_state_;

  // 球图标（只解码一次并缓存）。
  std::unique_ptr<Gdiplus::Image> icon_image_;

  // 拖动状态：用于区分"单击恢复"与"按住拖动"。
  bool is_pressing_ = false;
  bool is_dragging_ = false;
  POINT press_cursor_ = {0, 0};
  int press_anchor_x_ = 0;
  int press_anchor_y_ = 0;

  // 右键按下状态：用于区分"右键单击弹菜单"与"右键拖动不弹菜单"。
  bool is_right_pressing_ = false;
  POINT right_press_cursor_ = {0, 0};

  // 锁定位置时用户尝试拖动：用于避免松手被误判成单击。
  bool locked_drag_attempt_ = false;
};

#endif  // RUNNER_BALL_WINDOW_H_
