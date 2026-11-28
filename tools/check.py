#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统一测试入口：fast / commit / full / release 四条车道。

用法：
    python tools/check.py --lane fast
    python tools/check.py --lane commit
    python tools/check.py --lane full --coverage
    python tools/check.py --lane release --data-source <合成数据副本> --signing-key <key>

设计：
  fast     静态门禁 + 改动影响分析选中的测试（<60s 目标）
  commit   静态门禁 + 全部测试，排除少量耗时/IO 型 suite（<2.5min 目标）
  full     静态门禁 + 全量测试（可选覆盖率）
  release  full + release_check.py 的真实安装/升级/更新验收

所有车道都会先跑 check_rules / ui_copy / check_version / stamp_version /
git diff --check；不再存在“只跑 flutter test 就算全量”的入口。
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
LANES = TOOLS / "test_lanes.json"
TEST_DIR = ROOT / "test"
GATE_SCRIPTS = [
    ("check_rules", [TOOLS / "check_rules.py"]),
    ("ui_copy", [TOOLS / "ui_copy_check.py"]),
    ("check_version", [TOOLS / "check_version.py"]),
    ("stamp_version", [TOOLS / "stamp_version.py", "--check"]),
]


def _force_utf8_stdout() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


_force_utf8_stdout()


def _flutter(args: list[str]) -> list[str]:
    exe = os.environ.get("CMS_FLUTTER") or shutil.which("flutter")
    if not exe:
        raise SystemExit("[ERROR] 找不到 flutter；请设置 CMS_FLUTTER 或把 flutter 放进 PATH")
    if os.name == "nt" and exe.lower().endswith((".bat", ".cmd")):
        return ["cmd", "/c", exe] + args
    return [exe] + args


def _run(cmd: list[str], *, cwd: pathlib.Path = ROOT, capture: bool = False) -> int:
    print("\n$ " + " ".join(str(x) for x in cmd), flush=True)
    proc = subprocess.run(
        [str(x) for x in cmd],
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=capture,
    )
    if capture and proc.stdout:
        print(proc.stdout, end="")
    if capture and proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    return proc.returncode


def _git(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-c", "core.quotepath=false"] + args,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def changed_files(base: str | None) -> list[str]:
    names: set[str] = set()
    if base:
        diff = _git(["diff", "--name-only", base])
        if diff.returncode == 0:
            names.update(x.strip() for x in diff.stdout.splitlines() if x.strip())
    diff = _git(["diff", "HEAD", "--name-only"])
    if diff.returncode == 0:
        names.update(x.strip() for x in diff.stdout.splitlines() if x.strip())
    untracked = _git(["ls-files", "--others", "--exclude-standard"])
    if untracked.returncode == 0:
        names.update(x.strip() for x in untracked.stdout.splitlines() if x.strip())
    return sorted(names)


def all_tests() -> list[str]:
    return sorted(p.relative_to(ROOT).as_posix() for p in TEST_DIR.rglob("*_test.dart"))


def load_lanes() -> dict:
    return json.loads(LANES.read_text(encoding="utf-8"))


def is_docs_only(changed: list[str]) -> bool:
    return bool(changed) and all(
        p.endswith((".md", ".txt", ".png", ".jpg", ".jpeg"))
        or p.startswith(("docs/", "更新/", ".github/"))
        for p in changed
    )


def is_tools_only(changed: list[str]) -> bool:
    """tools/ 下的 Python/JSON 改动不触发 117 个 Dart suite。"""
    return bool(changed) and all(
        p.startswith("tools/") and p.endswith((".py", ".json")) for p in changed
    )


def run_tool_tests() -> int:
    print("\n== tools 自测 ==")
    return _run(
        [
            sys.executable,
            "-m",
            "unittest",
            "discover",
            "-s",
            "tools",
            "-p",
            "test_*.py",
            "-v",
        ]
    )


def select_affected(
    changed: list[str], lanes: dict, *, direct: bool = False
) -> tuple[list[str], bool]:
    # 工具/文档/CI 改动不影响 Dart 图；只有 Dart 源码与测试参与影响分析。
    dart_changed = [
        p
        for p in changed
        if p.endswith(".dart") and (p.startswith("lib/") or p.startswith("test/"))
    ]
    dependency_changed = any(
        p in {"pubspec.yaml", "pubspec.lock"}
        or p.startswith(("windows/", "installer/"))
        for p in changed
    )
    if dependency_changed:
        return all_tests(), True
    if not dart_changed:
        return [p for p in lanes.get("fast_fallback", []) if (ROOT / p).exists()], False

    sys.path.insert(0, str(TOOLS))
    from test_graph import DartGraph  # local tool, no package install

    graph = DartGraph(root=ROOT).build()
    if direct:
        selected = graph.direct_tests(dart_changed)
        if not selected:
            return [p for p in lanes.get("fast_fallback", []) if (ROOT / p).exists()], False
        return selected, False

    selected, all_tests_needed = graph.selected_or_all(dart_changed)
    if all_tests_needed:
        return all_tests(), True
    if not selected:
        return [p for p in lanes.get("fast_fallback", []) if (ROOT / p).exists()], False
    return selected, False


def run_gates() -> int:
    print("\n== 静态门禁 ==")
    for name, script in GATE_SCRIPTS:
        code = _run([sys.executable, *script])
        if code != 0:
            print(f"[FAIL] {name} 未通过")
            return code
    diff_check = _git(["diff", "--check"])
    if diff_check.returncode != 0:
        print("[FAIL] git diff --check 未通过")
        print(diff_check.stdout)
        print(diff_check.stderr)
        return diff_check.returncode
    print("[OK] 静态门禁通过")
    return 0


def run_analyze() -> int:
    print("\n== flutter analyze ==")
    return _run(_flutter(["analyze"]))


def run_flutter_tests(tests: list[str] | None, *, jobs: int | None, coverage: bool) -> int:
    args = ["test"]
    if coverage:
        args.append("--coverage")
    if jobs and jobs > 0:
        args.extend(["-j", str(jobs)])
    if tests is not None:
        args.extend(tests)
    print("\n== flutter test ==")
    return _run(_flutter(args))


def run_coverage_report(enforce: bool) -> int:
    print("\n== 覆盖率报告 ==")
    args = [sys.executable, TOOLS / "coverage_check.py"]
    if enforce:
        args.append("--enforce")
    return _run(args)


def is_widget_test(path: str) -> bool:
    try:
        text = (ROOT / path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return "testWidgets(" in text


def lane_fast(args: argparse.Namespace, lanes: dict) -> int:
    changed = changed_files(args.base)
    if not changed:
        print("[fast] 没有检测到改动，使用快速 fallback suite。")
        tests = [p for p in lanes.get("fast_fallback", []) if (ROOT / p).exists()]
        all_selected = False
    elif is_docs_only(changed):
        print("[fast] 仅文档/图片改动，跳过测试。")
        return 0
    elif is_tools_only(changed):
        print("[fast] 仅 tools/ 改动，运行工具自测。")
        if args.list:
            return 0
        code = run_gates()
        if code != 0:
            return code
        return run_tool_tests()
    else:
        print(f"[fast] 改动 {len(changed)} 个文件：")
        for item in changed[:20]:
            print(f"  - {item}")
        if len(changed) > 20:
            print(f"  ... 其余 {len(changed) - 20} 个")
        selected, all_selected = select_affected(changed, lanes, direct=True)
        # fast 只跑直接影响的纯单元测试；Widget/流程测试交给 commit/full。
        tests = [p for p in selected if not is_widget_test(p)]
        if any(p.startswith("lib/widgets/") for p in changed) and (
            ROOT / "test/widget_test.dart"
        ).exists():
            if "test/widget_test.dart" not in tests:
                tests.append("test/widget_test.dart")
        if not tests:
            tests = [p for p in lanes.get("fast_fallback", []) if (ROOT / p).exists()]
        print(
            f"[fast] 选中 {len(tests)} 个单元/烟测文件"
            + ("（依赖或影响面过大，已收敛）" if all_selected else "（仅直接依赖）")
        )
    if args.list:
        for item in tests:
            print(item)
        return 0
    code = run_gates()
    if code != 0:
        return code
    code = run_analyze()
    if code != 0:
        return code
    return run_flutter_tests(tests or None, jobs=args.jobs, coverage=False)


def lane_commit(args: argparse.Namespace, lanes: dict) -> int:
    core = [p for p in lanes.get("commit_core", []) if (ROOT / p).exists()]
    tests = set(core)
    changed = changed_files(args.base)
    if changed:
        selected, all_needed = select_affected(changed, lanes)
        # 审计 A-27：此前"受影响文件超过 10 个"会整体丢弃受影响测试、只留核心冒烟，
        # 于是改动面越大覆盖越少。现在无论如何都跑受影响测试，只用提示说明影响面。
        if all_needed:
            print("[commit] 影响面较大（依赖扩散），仍运行全部受影响测试。")
        tests.update(selected)
    ordered = sorted(tests)
    print(f"[commit] 运行 {len(ordered)} 个测试文件（核心 {len(core)} + 受影响）。")
    if args.list:
        for item in ordered:
            print(item)
        return 0
    code = run_gates()
    if code != 0:
        return code
    code = run_analyze()
    if code != 0:
        return code
    return run_flutter_tests(ordered, jobs=args.jobs, coverage=False)


def lane_full(args: argparse.Namespace, lanes: dict) -> int:
    if args.list:
        for item in all_tests():
            print(item)
        return 0
    code = run_gates()
    if code != 0:
        return code
    code = run_analyze()
    if code != 0:
        return code
    code = run_flutter_tests(None, jobs=args.jobs, coverage=args.coverage)
    if code != 0:
        return code
    if args.coverage:
        # 审计 A-27：此前 --enforce-coverage 默认关闭，"只出报告不判失败"等于没有门禁。
        # 现在默认强制；确需只看数字时用 --no-enforce-coverage。
        return run_coverage_report(not args.no_enforce_coverage)
    return 0


def lane_release(args: argparse.Namespace, lanes: dict) -> int:
    if not args.data_source:
        print("[ERROR] release 车道必须提供 --data-source（合成/脱敏数据副本，不能指向真实数据）")
        return 2
    code = lane_full(args, lanes)
    if code != 0:
        return code
    cmd = [
        sys.executable,
        TOOLS / "release_check.py",
        "--skip-tests",
        "--data-source",
        args.data_source,
    ]
    if args.signing_key:
        cmd.extend(["--signing-key", args.signing_key])
    if args.skip_build:
        cmd.append("--skip-build")
    if args.skip_upgrade:
        cmd.append("--skip-upgrade")
    if args.keep_sandbox:
        cmd.append("--keep-sandbox")
    return _run(cmd)


def main() -> int:
    parser = argparse.ArgumentParser(description="分层测试入口")
    parser.add_argument("--lane", choices=["fast", "commit", "full", "release"], default="fast")
    parser.add_argument("--base", default=None, help="fast 车道的 git 对比基准")
    parser.add_argument("--list", action="store_true", help="只列出将运行的测试文件")
    parser.add_argument("--jobs", type=int, default=0, help="传给 flutter test -j")
    parser.add_argument("--coverage", action="store_true", help="full/release 收集覆盖率")
    parser.add_argument(
        "--enforce-coverage",
        action="store_true",
        help="（已默认开启）覆盖率不达标时失败；保留该参数以兼容旧命令行",
    )
    parser.add_argument(
        "--no-enforce-coverage",
        action="store_true",
        help="只生成覆盖率报告，不做阈值判定（应急排查用）",
    )
    parser.add_argument("--data-source", default=None, help="release_check 的数据副本")
    parser.add_argument("--signing-key", default=None, help="release_check 的 Ed25519 私钥")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-upgrade", action="store_true")
    parser.add_argument("--keep-sandbox", action="store_true")
    args = parser.parse_args()

    lanes = load_lanes()
    started = time.monotonic()
    if args.lane == "fast":
        code = lane_fast(args, lanes)
    elif args.lane == "commit":
        code = lane_commit(args, lanes)
    elif args.lane == "full":
        code = lane_full(args, lanes)
    else:
        code = lane_release(args, lanes)
    print(f"\n[{args.lane}] 耗时 {time.monotonic() - started:.1f}s，退出码 {code}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
