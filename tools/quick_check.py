#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快速检查：flutter analyze + 只跑本次改动相关的测试。

用法：
    python tools/quick_check.py                 # 按工作区改动自动挑选测试
    python tools/quick_check.py --base HEAD~1   # 按某个提交之后的改动挑选
    python tools/quick_check.py --full          # analyze + 全量测试（发版前用）

设计目的：全量测试约 3 分钟，改一小批代码就全跑一遍会拖慢迭代。日常开发用
本脚本，只跑 import 到被改文件、或文本里出现被改文件名的测试；发版前再跑
--full 与三套门禁（check_rules.py / ui_copy_check.py / check_version.py）。
"""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEST_DIR = ROOT / "test"
FALLBACK_TESTS = [
    "test/app_data_provider_test.dart",
    "test/daily_flow_test.dart",
    "test/comprehensive_fixes_test.dart",
]


def _force_utf8_stdout():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


_force_utf8_stdout()


def _flutter(args):
    exe = os.environ.get("CMS_FLUTTER") or shutil.which("flutter")
    if not exe:
        print("[ERROR] 找不到 flutter，可设置环境变量 CMS_FLUTTER 指向 flutter.bat")
        sys.exit(2)
    if os.name == "nt" and exe.lower().endswith((".bat", ".cmd")):
        return ["cmd", "/c", exe] + args
    return [exe] + args


def _git(args):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false"] + args,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def changed_files(base):
    """返回相对仓库根的文件列表（含未跟踪文件）。"""
    names = set()
    if base:
        diff = _git(["diff", "--name-only", base])
        if diff.returncode == 0:
            names.update(line.strip() for line in diff.stdout.splitlines() if line.strip())
    status = _git(["status", "--porcelain"])
    if status.returncode == 0:
        for line in status.stdout.splitlines():
            if len(line) < 4:
                continue
            path = line[3:].strip()
            if " -> " in path:
                path = path.split(" -> ", 1)[1]
            if path:
                names.add(path)
    return sorted(names)


def _read(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def tests_for(changed):
    """把改动文件映射到测试文件。"""
    selected = set()
    test_files = sorted(TEST_DIR.glob("*_test.dart"))
    for rel in changed:
        p = rel.replace("\\", "/")
        if p.startswith("test/") and p.endswith("_test.dart"):
            selected.add(p)
            continue
        if not p.startswith("lib/") or not p.endswith(".dart"):
            continue
        lib_rel = p[len("lib/"):]
        import_needle = f"package:class_management_system/{lib_rel}"
        stem = pathlib.Path(lib_rel).stem
        for test_file in test_files:
            text = _read(test_file)
            if import_needle in text or stem in text:
                selected.add("test/" + test_file.name)
        # 设置页大量使用 part，单独按目录兜底。
        if lib_rel.startswith("widgets/settings/"):
            for test_file in test_files:
                if "settings" in test_file.name:
                    selected.add("test/" + test_file.name)
    if not selected:
        for rel in FALLBACK_TESTS:
            if (ROOT / rel).exists():
                selected.add(rel)
    return sorted(selected)


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--full", action="store_true", help="运行全量测试")
    parser.add_argument("--base", default=None, help="对比的 git 基准（默认看工作区状态）")
    args = parser.parse_args()

    print("[1/2] flutter analyze")
    result = subprocess.run(_flutter(["analyze"]), cwd=ROOT)
    if result.returncode != 0:
        print("[X] analyze 未通过，先修问题再继续。")
        return 1

    if args.full:
        print("[2/2] flutter test（全量）")
        return subprocess.run(_flutter(["test"]), cwd=ROOT).returncode

    changed = changed_files(args.base)
    selected = tests_for(changed)
    print(f"[2/2] 改动 {len(changed)} 个文件，选中 {len(selected)} 个测试文件：")
    for rel in selected[:20]:
        print(f"  - {rel}")
    if len(selected) > 20:
        print(f"  ... 其余 {len(selected) - 20} 个")
    if not selected:
        print("[!] 没有匹配到测试文件，建议改用 --full。")
        return 0
    return subprocess.run(_flutter(["test"] + selected), cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
