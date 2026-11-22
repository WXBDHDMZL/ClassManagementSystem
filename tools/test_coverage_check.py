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

from coverage_check import parse_lcov, percent  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
