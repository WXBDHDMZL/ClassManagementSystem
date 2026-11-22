#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""版本号单一来源：以 pubspec.yaml 为基准，生成/校验所有版本落点（B-14）。

用法：
    python tools/stamp_version.py --check   # 只检查，不一致退出 1
    python tools/stamp_version.py --fix     # 自动写入所有落点

覆盖：
  - pubspec.yaml 的 version（唯一来源，本脚本只读）
  - lib/constants/app_version.dart 的 version / pubspecVersion
  - lib/**/*.dart 文件头「版本 (Version): VX.Y.Z」
  - installer/installer.iss 的 5 个版本字段
  - LICENSE.txt / installer/LICENSE.txt 的「对应程序版本」
  - README.md 顶部版本与安装包文件名
  - 真机验证清单.md 的适用版本/章节标题

注意：test/ 下文件头允许滞后，不在本脚本范围内。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_VERSION_FILE = ROOT / "lib/constants/app_version.dart"
PUBSPEC = ROOT / "pubspec.yaml"


def _force_utf8_stdout():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


_force_utf8_stdout()


def read_source_version():
    text = PUBSPEC.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", text, re.M)
    if not m:
        print("[ERROR] pubspec.yaml 里找不到 version: X.Y.Z+BUILD")
        sys.exit(1)
    num = m.group(1)
    build = m.group(2)
    return "V" + num, num, f"{num}+{build}"


def apply_pattern(text, pattern, replacement, flags=0):
    return re.sub(pattern, replacement, text, flags=flags)


def write_preserving_newline(path, text):
    """按文件原有的换行风格写回，避免版本同步把整仓库改成 CRLF。

    Path.write_text 在 Windows 上会把换行符统一翻译成 CRLF，以前每次发版
    都会制造上百个纯行尾变更，还得手工逐个还原。这里先读原文件判断是
    LF 还是 CRLF，再按同样风格写回，并保留 BOM。
    """
    raw = path.read_bytes()
    crlf = chr(13) + chr(10)
    lf = chr(10)
    normalized = text.replace(crlf, lf).replace(chr(13), lf)
    newline = crlf if crlf.encode("utf-8") in raw else lf
    data = normalized.replace(lf, newline).encode("utf-8")
    bom = bytes([0xEF, 0xBB, 0xBF])
    if raw.startswith(bom):
        data = bom + data
    path.write_bytes(data)


def plan_changes(ver, num, full):
    """返回 [(path, new_text, old_fragment_desc)]，不写盘。"""
    changes = []

    def load(path):
        p = ROOT / path
        if not p.exists():
            return None, None
        return p, p.read_text(encoding="utf-8")

    # 1) app_version.dart
    p, t = load("lib/constants/app_version.dart")
    if t is not None:
        new = re.sub(
            r"static const String version = 'V[\d.]+';",
            f"static const String version = '{ver}';",
            t,
        )
        new = re.sub(
            r"static const String pubspecVersion = '[\d.]+\+\d+';",
            f"static const String pubspecVersion = '{full}';",
            new,
        )
        new = re.sub(
            r"^ \* 版本 \(Version\): V[\d.]+\s*$",
            f" * 版本 (Version): {ver}",
            new,
            flags=re.M,
        )
        if new != t:
            changes.append((p, new, "app_version.dart 常量"))

    # 2) installer.iss 五个字段
    p, t = load("installer/installer.iss")
    if t is not None:
        new = apply_pattern(t, r"^AppVersion=.*$", f"AppVersion={num}", re.M)
        new = apply_pattern(
            new, r"^AppVerName=.*$", f"AppVerName=班级管理系统 {ver}", re.M
        )
        new = apply_pattern(
            new, r"^VersionInfoVersion=.*$", f"VersionInfoVersion={num}.0", re.M
        )
        new = apply_pattern(
            new,
            r"^VersionInfoProductVersion=.*$",
            f"VersionInfoProductVersion={num}",
            re.M,
        )
        new = apply_pattern(
            new,
            r"^OutputBaseFilename=.*$",
            f"OutputBaseFilename=班级管理系统_安装包_v{num}",
            re.M,
        )
        if new != t:
            changes.append((p, new, "installer.iss 版本字段"))

    # 3) 两份 LICENSE
    for rel in ("LICENSE.txt", "installer/LICENSE.txt"):
        p, t = load(rel)
        if t is not None:
            new = re.sub(r"对应程序版本：V[\d.]+", f"对应程序版本：{ver}", t)
            if new != t:
                changes.append((p, new, f"{rel} 对应程序版本"))

    # 4) README
    p, t = load("README.md")
    if t is not None:
        new = re.sub(r"\*\*V[\d.]+\*\*", f"**{ver}**", t, count=1)
        # 安装包按需生成：README 使用 v<版本> 占位时保持通用写法，不绑定具体版本。
        if "班级管理系统_安装包_v<版本>.exe" not in new:
            new = re.sub(
                r"班级管理系统_安装包_v[\d.]+\.exe",
                f"班级管理系统_安装包_v{num}.exe",
                new,
            )
        if new != t:
            changes.append((p, new, "README 版本/安装包名"))

    # 5) 真机验证清单
    p, t = load("真机验证清单.md")
    if t is not None:
        new = re.sub(r"\| 适用版本 \| V[\d.]+ 起 \|", f"| 适用版本 | {ver} 起 |", t)
        new = re.sub(
            r"(## 七、当前功能抽查（)V[\d.]+(，)",
            rf"\g<1>{ver}\g<2>",
            new,
        )
        if new != t:
            changes.append((p, new, "真机验证清单适用版本"))

    # 6) lib 文件头（app_version.dart 已在上方连同常量一起写，避免同路径二次写入覆盖常量）
    for f in (ROOT / "lib").rglob("*.dart"):
        if f == APP_VERSION_FILE:
            continue
        t = f.read_text(encoding="utf-8")
        new = re.sub(
            r"^ \* 版本 \(Version\): V[\d.]+\s*$",
            f" * 版本 (Version): {ver}",
            t,
            flags=re.M,
        )
        if new != t:
            changes.append((f, new, "文件头版本"))
    return changes


def main():
    mode = "--fix"
    if "--check" in sys.argv:
        mode = "--check"
    elif "--fix" in sys.argv:
        mode = "--fix"
    else:
        print(__doc__)
        print("请指定 --check 或 --fix")
        return 2

    ver, num, full = read_source_version()
    changes = plan_changes(ver, num, full)
    if not changes:
        print(f"[OK] 所有版本落点与 pubspec 一致：{ver} ({full})")
        return 0

    if mode == "--check":
        print(f"[X] 有 {len(changes)} 处版本落点与 pubspec 不一致：")
        for path, _, desc in changes[:40]:
            print(f"  - {path.relative_to(ROOT)}（{desc}）")
        print("运行 python tools/stamp_version.py --fix 自动同步。")
        return 1

    for path, new_text, desc in changes:
        write_preserving_newline(path, new_text)
    print(f"[OK] 已从 pubspec 同步 {len(changes)} 处到 {ver} ({full})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
