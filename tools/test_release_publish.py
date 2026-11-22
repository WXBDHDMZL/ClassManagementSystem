#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""release_publish.py 的纯函数回归测试（不访问网络、不读写真实数据）。"""
from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

import release_publish as rp


class ChecksumTests(unittest.TestCase):
    def test_accepts_hash_and_filename(self) -> None:
        digest = "a" * 64
        self.assertEqual(
            rp.parse_checksum(f"{digest}  ClassManagementSystem_Setup_v4.13.0.exe", "ClassManagementSystem_Setup_v4.13.0.exe"),
            digest,
        )

    def test_accepts_binary_marker(self) -> None:
        digest = "b" * 64
        self.assertEqual(rp.parse_checksum(f"{digest} *setup.exe", "setup.exe"), digest)

    def test_accepts_hash_only(self) -> None:
        digest = "c" * 64
        self.assertEqual(rp.parse_checksum(digest, "setup.exe"), digest)

    def test_rejects_wrong_filename(self) -> None:
        digest = "d" * 64
        self.assertIsNone(rp.parse_checksum(f"{digest}  other.exe", "setup.exe"))

    def test_rejects_bad_hash(self) -> None:
        self.assertIsNone(rp.parse_checksum("not-a-hash  setup.exe", "setup.exe"))
        self.assertIsNone(rp.parse_checksum("abc  setup.exe", "setup.exe"))


class ProductVersionTests(unittest.TestCase):
    def test_exact_and_build(self) -> None:
        self.assertTrue(rp.product_version_matches("4.13.7", "4.13.7"))
        self.assertTrue(rp.product_version_matches("4.13.7+182", "4.13.7"))
        self.assertTrue(rp.product_version_matches(" 4.13.7 ", "4.13.7"))

    def test_rejects_superstring(self) -> None:
        self.assertFalse(rp.product_version_matches("4.13.70", "4.13.7"))
        self.assertFalse(rp.product_version_matches("4.13.7.1", "4.13.7"))
        self.assertFalse(rp.product_version_matches("V4.13.7", "4.13.7"))
        self.assertFalse(rp.product_version_matches("", "4.13.7"))


class Sha256Tests(unittest.TestCase):
    def test_file_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "asset.bin"
            path.write_bytes(b"ClassManagementSystem")
            self.assertEqual(
                rp.sha256_file(path),
                hashlib.sha256(b"ClassManagementSystem").hexdigest(),
            )


class ReleaseReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self._old_root = rp.ROOT
        self._tmp = tempfile.TemporaryDirectory()
        rp.ROOT = Path(self._tmp.name)
        (rp.ROOT / "build").mkdir()

    def tearDown(self) -> None:
        rp.ROOT = self._old_root
        self._tmp.cleanup()

    def _write(self, text: str) -> None:
        (rp.ROOT / "build" / "release_report_v4.13.7.md").write_text(
            text, encoding="utf-8"
        )

    def test_missing_report(self) -> None:
        self.assertIsNotNone(rp.release_report_problem("4.13.7"))

    def test_pass_report(self) -> None:
        self._write("# 发布验收报告 V4.13.7\n\n- 验收结论：通过\n")
        self.assertIsNone(rp.release_report_problem("4.13.7"))

    def test_failed_report(self) -> None:
        self._write("# 发布验收报告 V4.13.7\n\n- 验收结论：通过\n| 安装包 | 失败 | x |\n")
        self.assertIsNotNone(rp.release_report_problem("4.13.7"))

    def test_wrong_version(self) -> None:
        self._write("# 发布验收报告 V4.13.6\n\n- 验收结论：通过\n")
        self.assertIsNotNone(rp.release_report_problem("4.13.7"))


if __name__ == "__main__":
    unittest.main()
