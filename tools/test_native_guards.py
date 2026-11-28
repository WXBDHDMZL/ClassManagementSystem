#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""原生层 DPI 处理与关机落盘预算的静态守卫。

真机上的系统缩放、系统关机时机无法在 CI 里复现（见 docs/TESTING.md 的真机
冒烟清单），但"代码里必须仍然处理这些消息""Dart 侧预算不得超过原生等待"
是可以自动检查的，避免以后被无声改回去。
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="replace")


class BallWindowDpiGuardTest(unittest.TestCase):
    def test_redraws_on_dpi_and_theme_changes(self) -> None:
        source = _read("windows/runner/ball_window.cpp")
        for message in ("WM_DPICHANGED", "WM_DISPLAYCHANGE", "WM_SETTINGCHANGE"):
            self.assertIn(
                message,
                source,
                msg=f"悬浮球必须响应 {message}，否则改缩放后贴图会模糊/错位",
            )


class ShutdownBudgetTest(unittest.TestCase):
    def test_dart_budgets_stay_below_native_wait(self) -> None:
        native = _read("windows/runner/flutter_window.cpp")
        match = re.search(r"GetTickCount\(\)\s*\+\s*(\d+)", native)
        self.assertIsNotNone(match, "未找到原生 WM_QUERYENDSESSION 的等待毫秒数")
        native_budget = int(match.group(1))

        dart = _read("lib/services/desktop_service.dart")
        budgets = [
            int(value)
            for value in re.findall(
                r"_shutdown(?:Save|Log)Budget\s*=\s*Duration\(milliseconds:\s*(\d+)\)",
                dart,
            )
        ]
        self.assertEqual(len(budgets), 2, "应能解析保存/日志两处关机预算")
        self.assertLess(
            sum(budgets),
            native_budget,
            msg="Dart 侧落盘预算必须小于原生等待，否则关机时必然丢最后一次保存",
        )


if __name__ == "__main__":
    unittest.main()