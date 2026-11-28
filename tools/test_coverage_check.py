#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/coverage_check.py 的单元测试。"""
from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from coverage_check import _floor1, _update_baseline, parse_lcov, percent  # noqa: E402


class CoverageParseTest(unittest.TestCase):
    def test_parse_absolute_and_relative_paths(self) -> None:
        text = "\n".join(
            [
                "SF:D:\\repo\\lib\\services\\storage_service.dart",
                "DA:1,3",
                "DA:2,0",
                "end_of_record",
                "SF:lib/services/auth_service.dart",
                "DA:10,1",
                "DA:11,2",
                "end_of_record",
            ]
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "lcov.info"
            path.write_text(text, encoding="utf-8")
            data = parse_lcov(path)
        self.assertEqual(data["lib/services/storage_service.dart"], (1, 2))
        self.assertEqual(data["lib/services/auth_service.dart"], (2, 2))

    def test_percent(self) -> None:
        self.assertEqual(percent(1, 2), 50.0)
        self.assertEqual(percent(0, 0), 0.0)


class CoverageRatchetTest(unittest.TestCase):
    """审计 A-27：覆盖率棘轮只升不降。"""

    def test_floor1_never_rounds_up(self) -> None:
        self.assertEqual(_floor1(76.39), 76.3)
        self.assertEqual(_floor1(87.0), 87.0)
        self.assertEqual(_floor1(0.0), 0.0)

    def test_update_baseline_writes_values(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "coverage_baseline.json"
            code = _update_baseline(path, None, 76.3, 87.0, allow_lower=False, reason="")
            self.assertEqual(code, 0)
            payload = path.read_text(encoding="utf-8")
            self.assertIn('"overall": 76.3', payload)
            self.assertIn('"core": 87.0', payload)

    def test_lower_without_flag_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "coverage_baseline.json"
            self.assertEqual(
                _update_baseline(path, None, 76.3, 87.0, allow_lower=False, reason=""),
                0,
            )
            before = path.read_text(encoding="utf-8")
            code = _update_baseline(
                path, {"overall": 76.3, "core": 87.0}, 75.0, 86.0,
                allow_lower=False, reason="",
            )
            self.assertEqual(code, 1)
            self.assertEqual(path.read_text(encoding="utf-8"), before)

    def test_lower_with_flag_requires_reason(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "coverage_baseline.json"
            code = _update_baseline(
                path, {"overall": 76.3, "core": 87.0}, 75.0, 86.0,
                allow_lower=True, reason="   ",
            )
            self.assertEqual(code, 1)

    def test_lower_with_flag_and_reason_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "coverage_baseline.json"
            code = _update_baseline(
                path, {"overall": 76.3, "core": 87.0}, 75.0, 86.0,
                allow_lower=True, reason="重构期间临时下调",
            )
            self.assertEqual(code, 0)
            payload = path.read_text(encoding="utf-8")
            self.assertIn("重构期间临时下调", payload)
            self.assertIn('"overall": 75.0', payload)

    def test_raise_is_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "coverage_baseline.json"
            code = _update_baseline(
                path, {"overall": 76.3, "core": 87.0}, 78.0, 88.0,
                allow_lower=False, reason="",
            )
            self.assertEqual(code, 0)
            self.assertIn('"overall": 78.0', path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
