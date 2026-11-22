#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""重复跑全量测试并保留失败现场（B-22 偶发失败排查工具）。

用法：
    python tools/run_full_tests.py            # 默认跑 2 次
    python tools/run_full_tests.py --runs 5

每次运行输出保存到 build/test_runs/run_N.log；失败时额外把失败用例名
提取到 build/test_runs/run_N_failed.txt，便于事后定位偶发问题。
退出码：全部通过 0；任一失败 1。
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "test_runs"

# 与 build.bat 保持同一套 Flutter 路径约定；优先 CMS_FLUTTER，否则使用 PATH。
FLUTTER = os.environ.get("CMS_FLUTTER") or "flutter"


def _force_utf8_stdout():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


_force_utf8_stdout()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=2)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    failures = []
    for i in range(1, args.runs + 1):
        print(f"=== 第 {i}/{args.runs} 次全量测试 ===")
        proc = subprocess.run(
            f'"{FLUTTER}" test --reporter compact',
            cwd=ROOT,
            capture_output=True,
            shell=True,
        )
        text = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")
        (OUT / f"run_{i}.log").write_text(text, encoding="utf-8")
        if proc.returncode == 0:
            print(f"  [OK] 全绿（日志 build/test_runs/run_{i}.log）")
            continue
        failed = sorted(
            set(
                m.group(1).strip()
                for m in re.finditer(r"([^\r\n]+?) \[E\]", text)
            )
        )
        (OUT / f"run_{i}_failed.txt").write_text(
            "\n".join(failed) + "\n", encoding="utf-8"
        )
        print(f"  [FAIL] 失败 {len(failed)} 例（run_{i}_failed.txt）")
        failures.extend(failed)

    if failures:
        print("\n失败的用例：")
        for name in failures:
            print(f"  - {name}")
        return 1
    print(f"\n[OK] {args.runs} 次全量测试全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
