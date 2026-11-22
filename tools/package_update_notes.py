#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `更新/` 下的历史更新说明打包成 Release 附件。

GitHub Release 删除旧版本后，历史更新说明仍随源码保留；本脚本额外生成
一个 zip，方便在最新 Release 中一次取回 V1.0.0 以来的全部更新记录。
"""
from __future__ import annotations

import argparse
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTES = ROOT / "更新"


def version_key(name: str) -> tuple[int, ...]:
    match = re.search(r"_V(\d+(?:\.\d+)*)\.md$", name)
    return tuple(int(part) for part in match.group(1).split(".")) if match else ()


def main() -> int:
    parser = argparse.ArgumentParser(description="打包历史更新说明")
    parser.add_argument("--out", required=True, help="输出 zip 路径")
    args = parser.parse_args()

    notes = sorted(NOTES.glob("更新内容_V*.md"), key=lambda path: version_key(path.name))
    if not notes:
        raise SystemExit("没有找到更新说明")
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    index = ["班级管理系统 历史更新记录", ""]
    index += [f"- {path.stem.replace('更新内容_', '')}" for path in notes]
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in notes:
            archive.write(path, f"更新/{path.name}")
        archive.writestr("更新/索引.txt", "\n".join(index) + "\n")
    print(f"[OK] {out} ({out.stat().st_size} bytes, {len(notes)} 个版本)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
