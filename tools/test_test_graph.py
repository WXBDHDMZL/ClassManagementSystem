#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/test_graph.py 的单元测试。"""
from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from test_graph import DartGraph, resolve_import  # noqa: E402


class ResolveImportTest(unittest.TestCase):
    def test_package_import_from_lib(self) -> None:
        got = resolve_import(
            ROOT / "lib/services/storage_service.dart",
            "package:class_management_system/services/storage_crypto.dart",
        )
        self.assertEqual(got, (ROOT / "lib/services/storage_crypto.dart").resolve())

    def test_package_import_from_test(self) -> None:
        got = resolve_import(
            ROOT / "test/daily_export_test.dart",
            "package:class_management_system/widgets/record_list.dart",
        )
        self.assertEqual(got, (ROOT / "lib/widgets/record_list.dart").resolve())

    def test_relative_import(self) -> None:
        got = resolve_import(
            ROOT / "lib/services/storage_service.dart",
            "../models/app_data.dart",
        )
        self.assertEqual(got, (ROOT / "lib/models/app_data.dart").resolve())

    def test_external_package_ignored(self) -> None:
        self.assertIsNone(
            resolve_import(
                ROOT / "lib/services/storage_service.dart",
                "package:crypto/crypto.dart",
            )
        )
        self.assertIsNone(
            resolve_import(ROOT / "lib/services/storage_service.dart", "dart:async")
        )


class DartGraphTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.graph = DartGraph(root=ROOT).build()

    def test_graph_has_files_and_edges(self) -> None:
        self.assertGreater(len(self.graph.files), 100)
        self.assertGreater(len(self.graph.tests), 50)
        self.assertGreater(sum(len(v) for v in self.graph.edges.values()), 100)

    def test_package_edge_is_present(self) -> None:
        service = (ROOT / "lib/services/storage_service.dart").resolve()
        crypto = (ROOT / "lib/services/storage_crypto.dart").resolve()
        self.assertIn(crypto, self.graph.edges[service])

    def test_widget_change_selects_tests(self) -> None:
        tests = self.graph.affected(["lib/widgets/history_dialog.dart"])
        self.assertIsNotNone(tests)
        assert tests is not None
        self.assertIn("test/daily_export_test.dart", tests)
        self.assertGreater(len(tests), 5)

    def test_direct_tests_are_direct_importers(self) -> None:
        direct = self.graph.direct_tests(["lib/widgets/history_dialog.dart"])
        self.assertIn("test/daily_export_test.dart", direct)
        self.assertLess(len(direct), 10)

    def test_core_change_requires_all(self) -> None:
        tests, all_needed = self.graph.selected_or_all(
            ["lib/services/storage_service.dart"]
        )
        self.assertTrue(all_needed)
        self.assertEqual(tests, [])

    def test_non_dart_or_missing_requires_all(self) -> None:
        self.assertIsNone(self.graph.affected(["README.md"]))
        self.assertIsNone(self.graph.affected(["lib/services/not_exists.dart"]))
        _, all_needed = self.graph.selected_or_all(["README.md"])
        self.assertTrue(all_needed)


if __name__ == "__main__":
    unittest.main()
