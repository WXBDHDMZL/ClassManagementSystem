#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""最小规则门禁（B-16）：只拦“不能变多”的存量债务。

用法：
    python tools/check_rules.py                  # 检查，超基线退出 1
    python tools/check_rules.py --update-baseline # 把当前值写成新基线

基线在 tools/rule_baseline.json。规则：
  1. 裸 catch（无 `on` 分支）数量不得高于基线（目标逐步降到 ≤8，见 B-13）；
  2. lib/ 文件头版本必须与 app_version.dart 一致（B-14 的"禁止新增"兜底）。
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINE = ROOT / "tools/rule_baseline.json"
APP_VERSION_FILE = ROOT / "lib/constants/app_version.dart"


def _force_utf8_stdout():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


_force_utf8_stdout()


def count_bare_catches():
    count = 0
    for f in (ROOT / "lib").rglob("*.dart"):
        lines = f.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if "catch (" not in line:
                continue
            ctx = " ".join(lines[max(0, i - 2) : i + 1])
            if " on " in ctx:
                continue
            count += 1
    return count


def count_stale_headers():
    text = APP_VERSION_FILE.read_text(encoding="utf-8")
    m = re.search(r"static const String version = '(V[\d.]+)'", text)
    want = m.group(1) if m else ""
    stale = []
    for f in (ROOT / "lib").rglob("*.dart"):
        t = f.read_text(encoding="utf-8")
        mm = re.search(r"^ \* 版本 \(Version\): (V[\d.]+)\s*$", t, re.M)
        rel = str(f.relative_to(ROOT))
        if mm is None:
            stale.append(f"{rel}（缺文件头）")
        elif want and mm.group(1) != want:
            stale.append(rel)
    return stale


def ui_copy_violations():
    """UI-01：功能界面文案不得出现更新说明/旧版对比。"""
    sys.path.insert(0, str(ROOT / "tools"))
    import ui_copy_check

    return ui_copy_check.scan()


def main():
    update = "--update-baseline" in sys.argv
    current = {
        "bareCatch": count_bare_catches(),
        "note": "裸 catch 只降不升（目标 ≤8，见 BACKLOG B-13）",
    }
    baseline = {}
    if BASELINE.exists():
        try:
            baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
        except Exception:
            baseline = {}

    if update:
        old_catch = baseline.get("bareCatch")
        if isinstance(old_catch, int) and current["bareCatch"] > old_catch:
            print(
                f"[FAIL] 裸 catch 不得上调：当前 {current['bareCatch']} > 基线 {old_catch}",
                file=sys.stderr,
            )
            return 1
        merged = dict(baseline)
        merged.update(current)
        BASELINE.write_text(
            json.dumps(merged, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"[OK] 基线已更新：bareCatch={current['bareCatch']}")
        return 0

    problems = []
    base_catch = baseline.get("bareCatch")
    if base_catch is None:
        problems.append("  基线缺少 bareCatch；先运行 --update-baseline")
    elif current["bareCatch"] > base_catch:
        problems.append(
            f"  裸 catch 增加：当前 {current['bareCatch']} > 基线 {base_catch}（B-13 只降不升）"
        )
    else:
        print(
            f"[OK] 裸 catch：{current['bareCatch']} / 基线 {base_catch}"
            + ("（可下调基线）" if current["bareCatch"] < base_catch else "")
        )

    stale = count_stale_headers()
    if stale:
        problems.append(
            "  lib 文件头版本未同步：" + "、".join(stale[:10])
            + ("…" if len(stale) > 10 else "")
        )
    else:
        print("[OK] lib 文件头版本一致")

    copy_hits = ui_copy_violations()
    if copy_hits:
        problems.append(
            "  UI-01 界面文案出现更新说明/旧版表述：\n"
            + "\n".join("    " + item for item in copy_hits[:20])
            + ("\n    …" if len(copy_hits) > 20 else "")
        )
    else:
        print("[OK] UI-01 界面文案无更新说明/旧版表述")

    if problems:
        print("\n规则门禁未通过：")
        print("\n".join(problems))
        return 1
    print("\n[OK] 规则门禁通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
