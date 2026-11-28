#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""读取 coverage/lcov.info，报告行覆盖率并可选执行阈值。

用法：
    python tools/coverage_check.py
    python tools/coverage_check.py --enforce
    python tools/coverage_check.py --min-overall 80 --min-core 85
    python tools/coverage_check.py --update-baseline

棘轮（审计 A-27）：阈值只能升不能降。每次达标后可用 `--update-baseline` 把实测值
写进 tools/coverage_baseline.json（保留一位小数、向下取整）；之后任何时候覆盖率
比基线低超过 0.3 个百分点即失败。下调基线必须显式 `--allow-lower --reason <原因>`。
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LCOV = ROOT / "coverage" / "lcov.info"
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass
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


def _rel_lib(raw: str) -> str | None:
    text = raw.replace("\\", "/")
    marker = "/lib/"
    index = text.rfind(marker)
    if index < 0:
        if text.startswith("lib/"):
            return text
        return None
    return "lib/" + text[index + len(marker) :]


def parse_lcov(path: pathlib.Path) -> dict[str, tuple[int, int]]:
    """返回 {相对 lib 路径: (命中行数, 可执行行数)}。"""
    result: dict[str, list[int]] = {}
    current: str | None = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("SF:"):
            current = _rel_lib(line[3:].strip())
            if current:
                result.setdefault(current, [0, 0])
        elif line.startswith("DA:") and current:
            parts = line[3:].split(",")
            if len(parts) >= 2:
                try:
                    count = int(parts[1])
                except ValueError:
                    continue
                result[current][1] += 1
                if count > 0:
                    result[current][0] += 1
    return {name: (hit, total) for name, (hit, total) in result.items() if total > 0}


def percent(hit: int, total: int) -> float:
    return 100.0 * hit / total if total else 0.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lcov", default=str(LCOV))
    # 过渡门槛（审计 A-27）：当前实测 75.5% / 86.2%，先按 75.0% / 85.7% 兜底，
    # 目标是把两边都补到 80% / 85% 后改成 80.0 / 85.0（见 BACKLOG 覆盖率路线图）。
    parser.add_argument("--min-overall", type=float, default=75.0)
    parser.add_argument("--min-core", type=float, default=85.7)
    parser.add_argument("--enforce", action="store_true")
    parser.add_argument("--baseline", default=str(ROOT / "tools" / "coverage_baseline.json"))
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--allow-lower", action="store_true")
    parser.add_argument("--reason", default="")
    parser.add_argument("--ratchet-tolerance", type=float, default=0.3)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    path = pathlib.Path(args.lcov)
    if not path.exists():
        print(f"[ERROR] 找不到覆盖率文件：{path}")
        print("先运行：flutter test --coverage（或 python tools/check.py --lane full --coverage）")
        return 2
    data = parse_lcov(path)
    if not data:
        print(f"[ERROR] {path} 中没有可用的 lib/ 行覆盖记录")
        return 2

    total_hit = sum(hit for hit, _ in data.values())
    total_line = sum(total for _, total in data.values())
    overall = percent(total_hit, total_line)
    core = {name: data.get(name) for name in sorted(CORE_FILES)}
    core_hit = sum(hit for hit, _ in core.values() if hit is not None)
    core_line = sum(total for _, total in core.values() if total is not None)
    core_pct = percent(core_hit, core_line)

    if args.json:
        print(
            json.dumps(
                {
                    "overall": {"hit": total_hit, "total": total_line, "percent": round(overall, 2)},
                    "core": {
                        "hit": core_hit,
                        "total": core_line,
                        "percent": round(core_pct, 2),
                        "files": {
                            name: {"hit": v[0], "total": v[1], "percent": round(percent(*v), 2)}
                            for name, v in core.items()
                            if v
                        },
                    },
                },
                ensure_ascii=False,
                indent=2,
            )
        )
    else:
        print(f"总行覆盖率：{overall:.2f}% ({total_hit}/{total_line})")
        print(f"核心模块：{core_pct:.2f}% ({core_hit}/{core_line})")
        print("\n核心文件：")
        for name, value in core.items():
            if value is None:
                print(f"  {name:55s} 未出现在 lcov（0 覆盖）")
                continue
            print(f"  {name:55s} {percent(*value):6.2f}%  ({value[0]}/{value[1]})")

    baseline_path = pathlib.Path(args.baseline)
    baseline = _read_baseline(baseline_path)
    overall_floor = _floor1(overall)
    core_floor = _floor1(core_pct)

    if args.update_baseline:
        return _update_baseline(
            baseline_path,
            baseline,
            overall_floor,
            core_floor,
            allow_lower=args.allow_lower,
            reason=args.reason,
        )

    if args.enforce:
        failures = []
        if overall < args.min_overall:
            failures.append(f"总覆盖率 {overall:.2f}% < {args.min_overall:.2f}%")
        if core_pct < args.min_core:
            failures.append(f"核心覆盖率 {core_pct:.2f}% < {args.min_core:.2f}%")
        if baseline:
            base_overall = float(baseline.get("overall", 0.0))
            base_core = float(baseline.get("core", 0.0))
            tolerance = args.ratchet_tolerance
            if base_overall and overall_floor < base_overall - tolerance:
                failures.append(
                    f"总覆盖率 {overall_floor:.1f}% 比基线 {base_overall:.1f}% 退步超过 {tolerance} 个百分点"
                )
            if base_core and core_floor < base_core - tolerance:
                failures.append(
                    f"核心覆盖率 {core_floor:.1f}% 比基线 {base_core:.1f}% 退步超过 {tolerance} 个百分点"
                )
        if failures:
            print("\n[FAIL] " + "；".join(failures))
            return 1
        basis = f"基线上限 {baseline.get('overall')}/{baseline.get('core')}" if baseline else "无基线"
        print(
            f"\n[OK] 覆盖率达标（总 ≥{args.min_overall:.2f}%，核心 ≥{args.min_core:.2f}%；{basis}）"
        )
    return 0


def _floor1(value: float) -> float:
    """保留一位小数并向下取整（避免 75.59 被写成 75.6 造成假达标）。"""
    return int(value * 10) / 10.0


def _read_baseline(path: pathlib.Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _update_baseline(
    path: pathlib.Path,
    baseline: dict | None,
    overall: float,
    core: float,
    *,
    allow_lower: bool,
    reason: str,
) -> int:
    """写入/上调基线；下调必须有 --allow-lower 与 --reason。"""
    current = baseline or {}
    old_overall = float(current.get("overall", 0.0))
    old_core = float(current.get("core", 0.0))
    lower = overall < old_overall or core < old_core
    if lower and not allow_lower:
        print(
            f"[FAIL] 新值 {overall}/{core} 低于基线 {old_overall}/{old_core}；"
            "棘轮只允许上调。确需下调请加 --allow-lower --reason <原因>"
        )
        return 1
    if lower and not reason.strip():
        print("[FAIL] 下调基线必须用 --reason 说明原因")
        return 1
    payload = {
        "overall": overall,
        "core": core,
        "note": "覆盖率棘轮基线（一位小数、向下取整）；只升不降，下调需 --allow-lower --reason",
    }
    if lower:
        payload["lower_reason"] = reason.strip()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    action = "下调" if lower else "写入"
    print(f"[OK] 基线已{action}：总 {overall}% / 核心 {core}% → {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
