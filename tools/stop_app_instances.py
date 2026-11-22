#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建前收口：结束正在运行的「班级管理系统」实例。

为什么需要它
------------
Windows 上**正在运行的 exe 无法被覆盖**。本程序带系统托盘，关闭主窗口后常驻
后台；此时重新构建会占用 `build/windows/x64/runner/班级管理系统.exe`，链接器
直接报 `LNK1104: 无法打开文件 ...班级管理系统.exe`，表现为"构建莫名失败、
必须手动去任务栏/托盘关掉程序才行"。

本脚本在构建前自动把它结束掉：
  - 没有实例在跑 → 直接放行；
  - 有实例 → 结束并等待句柄释放；
  - 结束不掉（通常是以管理员身份启动、当前权限不足）→ **提前退出并给出明确
    提示**，而不是让链接器抛一句难懂的 LNK1104（也省掉一次 80 秒的无效构建）。

退出码：0 = 可以继续构建；2 = 仍有实例占用，需手动处理。
由 build.bat / installer/build_installer.bat 调用。
"""
import subprocess
import sys
import time

APP_NAME = "班级管理系统"
_PS = ["powershell", "-NoProfile", "-NonInteractive", "-Command"]


def _powershell(script: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        _PS + [script],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def _running_count() -> int:
    """当前正在运行的实例数（只解析数字，不依赖控制台中文编码）。"""
    expr = f"@(Get-Process -Name '{APP_NAME}' -ErrorAction SilentlyContinue).Count"
    result = _powershell(expr)
    try:
        return int((result.stdout or "").strip())
    except ValueError:
        return 0


def main() -> int:
    if _running_count() == 0:
        print("[OK] 没有正在运行的程序实例，直接开始构建")
        return 0

    print(f"[..] 检测到正在运行的「{APP_NAME}」，先结束它以免占用 exe")
    _powershell(
        f"Get-Process -Name '{APP_NAME}' -ErrorAction SilentlyContinue | "
        f"Stop-Process -Force -ErrorAction SilentlyContinue"
    )
    # 进程退出到文件句柄真正释放有一小段延迟，轮询等待。
    for _ in range(40):
        if _running_count() == 0:
            print("[OK] 已结束运行中的程序实例，继续构建")
            return 0
        time.sleep(0.25)

    print(f"[X] 「{APP_NAME}」仍在运行，且当前权限无法结束它")
    print("    常见原因：该程序是以管理员身份启动的。")
    print("    处理办法：手动关闭该程序后重试，或以管理员权限运行本构建脚本。")
    return 2


if __name__ == "__main__":
    sys.exit(main())
