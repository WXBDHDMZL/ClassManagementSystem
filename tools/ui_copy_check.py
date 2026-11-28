#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""UI-01 文案门禁：功能界面不得出现更新日志 / 旧版对比 / 迁移说明。

用法：
    python tools/ui_copy_check.py          # 检查，命中退出 1
    python tools/ui_copy_check.py --list   # 只列出命中，不改变退出码

规则来自 tools/ui_copy_rules.json（与 test/ui_copy_policy_test.dart 共用）。
扫描 lib/ 下全部 Dart 文件；注释（// 与 /* */）不参与检查；
三引号长文案（''' / \"\"\"）同样会被检查。
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
RULES = ROOT / "tools" / "ui_copy_rules.json"


def _force_utf8_stdout():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


def load_rules():
    data = json.loads(RULES.read_text(encoding="utf-8"))
    return (
        list(data.get("forbidden", [])),
        list(data.get("allowed", [])),
        list(data.get("gated_features", [])),
        set(data.get("exempt_files", [])),
    )


def _skip_interpolation(source, start):
    """start 指向 '$'，返回匹配 '}' 之后的位置；跳过内部嵌套字符串。"""
    n = len(source)
    depth = 0
    i = start + 1
    while i < n:
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        elif c in ("'", '"'):
            q = c
            if source.startswith(q * 3, i):
                end = source.find(q * 3, i + 3)
                i = n if end == -1 else end + 3
                continue
            i += 1
            while i < n:
                if source[i] == "\\":
                    i += 2
                    continue
                if source[i] == q:
                    i += 1
                    break
                if source[i] == "\n":
                    break
                i += 1
            continue
        i += 1
    return n


def extract_literals(source):
    """返回 [(起始行号, 字面量内容)]，跳过注释。"""
    out = []
    i = 0
    n = len(source)
    line = 1

    def advance(count):
        nonlocal i, line
        end = min(i + count, n)
        while i < end:
            if source[i] == "\n":
                line += 1
            i += 1

    while i < n:
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            advance((n if end == -1 else end + 2) - i)
            continue
        if source.startswith("'''", i) or source.startswith('"""', i):
            quote = source[i : i + 3]
            start_line = line
            j = i + 3
            while j < n:
                if source[j] == "\\":
                    j += 2
                    continue
                if source.startswith("${", j):
                    j = _skip_interpolation(source, j)
                    continue
                if source.startswith(quote, j):
                    break
                j += 1
            stop = min(j, n)
            out.append((start_line, source[i + 3 : stop]))
            advance((n if j >= n else j + 3) - i)
            continue
        ch = source[i]
        if ch in ("'", '"'):
            start_line = line
            j = i + 1
            closed = False
            while j < n:
                c = source[j]
                if c == "$" and j + 1 < n and source[j + 1] == "{":
                    j = _skip_interpolation(source, j)
                    continue
                if c == "\\":
                    j += 2
                    continue
                if c == ch:
                    closed = True
                    break
                if c == "\n":
                    break
                j += 1
            out.append((start_line, source[i + 1 : min(j, n)]))
            # 引号本身要吃掉，否则下一个循环会把它当成新的字符串开头。
            advance(min(j, n) - i + (1 if closed else 0))
            continue
        advance(1)
    return out


def scan():
    forbidden, allowed, gated, exempt_files = load_rules()
    violations = []
    for path in sorted(LIB.rglob("*.dart")):
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel in exempt_files:
            continue
        literals = extract_literals(source)
        for start_line, value in literals:
            if any(token in value for token in allowed):
                continue
            hits = [token for token in forbidden if token in value]
            if not hits:
                continue
            flat = " ".join(value.split())
            violations.append(
                (
                    f"{path.relative_to(ROOT)}:{start_line}: {flat[:120]}"
                    f"（命中 {'、'.join(hits)}）"
                )
            )
        violations.extend(_gated_violations(rel, source, literals, gated))
    return violations


def _line_of(source, offset):
    return source.count("\n", 0, offset) + 1


def _gated_violations(rel, source, literals, gated):
    """功能未开放时仍被界面提到的文案。

    结构上已整体隐藏的入口（exempt_files）不参与检查；其余命中要么落在
    guard 表达式附近（同一行或向上 window 行内），要么在字面量所在行带
    marker 注释，否则视为遗漏门控。
    """
    out = []
    lines = source.splitlines()
    for rule in gated:
        word = rule.get("word", "")
        if not word:
            continue
        guard = rule.get("guard", "")
        marker = rule.get("marker", "")
        window = int(rule.get("window", 20))
        scope = rule.get("scope") or []
        exempt = set(rule.get("exempt_files") or [])
        if scope and not any(rel.startswith(prefix) for prefix in scope):
            continue
        if rel in exempt:
            continue
        for start_line, value in literals:
            if word not in value:
                continue
            idx = start_line - 1
            lo = max(0, idx - window)
            nearby = "\n".join(lines[lo : idx + 1])
            if guard and guard in nearby:
                continue
            if marker and marker in nearby:
                continue
            flat = " ".join(value.split())
            out.append(
                f"{rel}:{start_line}: {flat[:120]}"
                f"（功能未开放仍提到「{word}」，缺少 {guard} 判断）"
            )
    return out


def main():
    violations = scan()
    if not violations:
        print("[OK] 界面文案门禁通过（无更新说明/旧版表述）")
        return 0
    print("界面文案门禁未通过：")
    for item in violations:
        print("  " + item)
    return 0 if "--list" in sys.argv else 1


if __name__ == "__main__":
    _force_utf8_stdout()
    raise SystemExit(main())
