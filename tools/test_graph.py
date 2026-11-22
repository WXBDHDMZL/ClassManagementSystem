#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""测试影响分析：按 Dart import/export/part 关系找出受影响的测试。

用法：
    python tools/test_graph.py --changed lib/services/storage_service.dart
    python tools/test_graph.py --changed lib/foo.dart lib/bar.dart --json

退出码：
    0  正常（可能输出 ALL 或测试文件列表）
    1  参数/仓库错误
    2  改动包含无法分析的文件，调用方应回退到更宽的测试通道
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from collections import deque
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGE = "class_management_system"
TEST_SUFFIX = "_test.dart"
DIRECTIVE_RE = re.compile(
    r"""^\s*(import|export|part)\s+['"]([^'"]+)['"]""",
    re.MULTILINE,
)
CORE_FILES = {
    "lib/services/storage_service.dart",
    "lib/services/storage_crypto.dart",
    "lib/services/backup_crypto.dart",
    "lib/services/security_service.dart",
    "lib/services/auth_service.dart",
    "lib/providers/app_data_provider.dart",
    "lib/providers/app_data/import_restore.dart",
    "lib/services/transfer_service.dart",
    "lib/services/github_update_service.dart",
}


def _norm(path: pathlib.Path) -> pathlib.Path:
    return pathlib.Path(path).resolve()


def _rel(root: pathlib.Path, path: pathlib.Path) -> str:
    return _norm(path).relative_to(_norm(root)).as_posix()


def _repo_root_for(source: pathlib.Path) -> pathlib.Path:
    """从源文件向上找 pubspec.yaml；找不到时退回工具所在仓库。"""
    current = _norm(source).parent
    for parent in (current, *current.parents):
        if (parent / "pubspec.yaml").exists():
            return parent
    return ROOT


def resolve_import(source: pathlib.Path, target: str) -> pathlib.Path | None:
    """把 import/export/part 的字符串解析成本仓库 Dart 文件；外部包返回 None。"""
    raw = target.strip()
    if not raw or raw.startswith("dart:"):
        return None
    if raw.startswith("package:"):
        package, _, rest = raw[len("package:") :].partition("/")
        if package != PACKAGE or not rest:
            return None
        candidate = _repo_root_for(source) / "lib" / rest
    elif raw.startswith("."):
        candidate = source.parent / raw
    else:
        # 少数测试/工具使用仓库根相对路径；按源码目录优先，再按仓库根兜底。
        candidate = source.parent / raw
        if not candidate.exists():
            candidate = _repo_root_for(source) / raw
    candidate = _norm(candidate)
    if candidate.suffix != ".dart":
        candidate = candidate.with_suffix(".dart")
    return candidate


@dataclass
class DartGraph:
    root: pathlib.Path = ROOT
    edges: dict[pathlib.Path, set[pathlib.Path]] = field(default_factory=dict)
    reverse: dict[pathlib.Path, set[pathlib.Path]] = field(default_factory=dict)
    part_owner: dict[pathlib.Path, pathlib.Path] = field(default_factory=dict)
    owner_parts: dict[pathlib.Path, set[pathlib.Path]] = field(default_factory=dict)
    tests: set[pathlib.Path] = field(default_factory=set)
    files: set[pathlib.Path] = field(default_factory=set)

    def build(self) -> "DartGraph":
        self.files = {
            _norm(p)
            for base in (self.root / "lib", self.root / "test")
            if base.exists()
            for p in base.rglob("*.dart")
        }
        self.tests = {
            p
            for p in self.files
            if p.name.endswith(TEST_SUFFIX) and "test" in p.parts
        }
        self.edges = {p: set() for p in self.files}

        for path in sorted(self.files):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for kind, target in DIRECTIVE_RE.findall(text):
                resolved = resolve_import(path, target)
                if resolved is None:
                    continue
                # 构建/生成文件不进入图，避免把 build 探针当成源码。
                try:
                    resolved.relative_to(_norm(self.root))
                except ValueError:
                    continue
                if resolved not in self.files:
                    continue
                self.edges[path].add(resolved)
                if kind == "part":
                    self.part_owner[resolved] = path
                    self.owner_parts.setdefault(path, set()).add(resolved)

        # part 是 owner 的一部分；双向连边，改 part 等于改 owner。
        for part, owner in self.part_owner.items():
            self.edges.setdefault(part, set()).add(owner)
            self.edges.setdefault(owner, set()).add(part)

        self.reverse = {p: set() for p in self.edges}
        for source, targets in self.edges.items():
            for target in targets:
                self.reverse.setdefault(target, set()).add(source)
        return self

    def _canonical(self, path: pathlib.Path) -> pathlib.Path:
        return self.part_owner.get(path, path)

    def is_core(self, path: pathlib.Path) -> bool:
        canonical = self._canonical(path)
        try:
            rel = _rel(self.root, canonical)
        except ValueError:
            return False
        return rel in CORE_FILES

    def affected(self, changed: list[str]) -> list[str] | None:
        """返回受影响的测试文件；包含非 Dart/不存在文件时返回 None（调用方回退）。"""
        selected: set[pathlib.Path] = set()
        for raw in changed:
            path = pathlib.Path(raw)
            if not path.is_absolute():
                path = self.root / path
            path = _norm(path)
            if path.suffix != ".dart" or not path.exists():
                return None
            if path not in self.edges:
                # 新文件可能在 build 时尚未进图；保守回退。
                return None
            starts = {path, self._canonical(path)}
            starts.update(self.owner_parts.get(self._canonical(path), ()))
            seen = set(starts)
            queue = deque(starts)
            while queue:
                node = queue.popleft()
                if node in self.tests:
                    selected.add(node)
                for dependent in self.reverse.get(node, ()):
                    if dependent not in seen:
                        seen.add(dependent)
                        queue.append(dependent)
        return sorted(_rel(self.root, p) for p in selected)

    def direct_tests(self, changed: list[str]) -> list[str]:
        """只返回直接 import 改动文件的测试；用于 fast 车道的秒级反馈。"""
        selected: set[pathlib.Path] = set()
        for raw in changed:
            path = pathlib.Path(raw)
            if not path.is_absolute():
                path = self.root / path
            path = _norm(path)
            if path.suffix != ".dart" or not path.exists() or path not in self.edges:
                continue
            if path in self.tests:
                selected.add(path)
            canonical = self._canonical(path)
            for dependent in self.reverse.get(canonical, ()):
                if dependent in self.tests:
                    selected.add(dependent)
            for dependent in self.reverse.get(path, ()):
                if dependent in self.tests:
                    selected.add(dependent)
        return sorted(_rel(self.root, p) for p in selected)

    def selected_or_all(self, changed: list[str]) -> tuple[list[str], bool]:
        affected = self.affected(changed)
        if affected is None:
            return [], True
        if any(
            self.is_core(
                _norm((self.root / p)) if not pathlib.Path(p).is_absolute() else pathlib.Path(p)
            )
            for p in changed
        ):
            return [], True
        return affected, False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--changed", nargs="+", required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    graph = DartGraph().build()
    selected, all_tests = graph.selected_or_all(args.changed)
    if args.json:
        print(json.dumps({"all": all_tests, "tests": selected}, ensure_ascii=False))
    else:
        if all_tests:
            print("ALL")
        elif not selected:
            print("NONE")
        else:
            for item in selected:
                print(item)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
