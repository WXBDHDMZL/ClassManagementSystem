#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发版版本号一致性自查（V2.27.4 新增）。

用途：改完版本号后跑一遍，确认**所有该同步的位置都同步了**，
而不是靠人肉记忆"有哪些文件要改"——V2.27.3 就是漏了 9 处
（安装包名/属性停在旧版），用户可见。

用法：
    python tools/check_version.py            # 读 lib/constants/app_version.dart 作为基准
    python tools/check_version.py V2.27.5    # 或显式指定期望版本
退出码 0 = 全部一致；1 = 有文件与基准不一致（列出具体位置）。
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_VERSION_FILE = ROOT / "lib/constants/app_version.dart"


def _force_utf8_stdout():
    """把标准输出切到 UTF-8，避免默认中文 Windows 控制台（GBK）编码崩溃。

    背景（V2.27.7 修）：Python 在中文 Windows 上 stdout 默认用 GBK，
    打印 ✓/✗ 会抛 UnicodeEncodeError —— 正常情况下会变成"退出码 1 的假失败"，
    不一致时更会把逐条 `文件:行` 清单打断，正好毁掉本工具的意义。
    `reconfigure` 是 Python 3.7+ 才有的，旧版本用不了就退回安全模式。
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass


_force_utf8_stdout()


def read_expected():
    if len(sys.argv) > 1:
        want = sys.argv[1].strip()
        if not want.startswith("V"):
            want = "V" + want
        return want
    text = APP_VERSION_FILE.read_text(encoding="utf-8")
    m = re.search(r"static const String version = '(V[\d.]+)'", text)
    if not m:
        print("无法从 app_version.dart 解析出基准版本号")
        sys.exit(1)
    return m.group(1)


def main():
    ver = read_expected()                 # 形如 V2.27.4
    num = ver[1:]                         # 2.27.4
    full = None                           # 形如 2.27.4+57（从 pubspecVersion 取）
    t = APP_VERSION_FILE.read_text(encoding="utf-8")
    m = re.search(r"static const String pubspecVersion = '([\d.]+)\+(\d+)'", t)
    full = f"{m.group(1)}+{m.group(2)}" if m else None
    print(f"基准版本：{ver}  (pubspecVersion: {full})")

    problems = []

    def check(cond, where, got, want):
        if not cond:
            problems.append(f"  [X] {where}\n      实际: {got}\n      期望: {want}")

    # 1. app_version.dart 常量
    check(f"static const String version = '{ver}'" in t, "lib/constants/app_version.dart: version 常量", "不一致", ver)
    check(full and f"static const String pubspecVersion = '{full}'" in t, "lib/constants/app_version.dart: pubspecVersion", "不一致", str(full))

    # 2. pubspec.yaml
    ps = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    check(re.search(rf"^version: {re.escape(full)}\s*$", ps, re.M) is not None, "pubspec.yaml: version", "不一致", full)

    # 3. installer.iss 5 行
    iss = (ROOT / "installer/installer.iss").read_text(encoding="utf-8")
    for pat, label, want in [
        (rf"^AppVersion={re.escape(num)}\s*$", "installer.iss:4 AppVersion", num),
        (rf"^AppVerName=班级管理系统 {re.escape(ver)}\s*$", "installer.iss:5 AppVerName", ver),
        (rf"^VersionInfoVersion={re.escape(num)}\.0\s*$", "installer.iss:8 VersionInfoVersion", num + ".0"),
        (rf"^VersionInfoProductVersion={re.escape(num)}\s*$", "installer.iss:9 VersionInfoProductVersion", num),
        (rf"^OutputBaseFilename=班级管理系统_安装包_v{re.escape(num)}\s*$", "installer.iss:16 OutputBaseFilename", "v" + num),
    ]:
        check(re.search(pat, iss, re.M) is not None, label, "不一致", want)

    # 4. 两份 LICENSE.txt
    for lf in ["LICENSE.txt", "installer/LICENSE.txt"]:
        txt = (ROOT / lf).read_text(encoding="utf-8")
        check(f"对应程序版本：{ver}" in txt, f"{lf}: 对应程序版本", "不一致", ver)

    # 5. README.md
    rm = (ROOT / "README.md").read_text(encoding="utf-8")
    check(f"**{ver}**" in rm, "README.md: 顶部当前版本", "不一致", ver)
    # 安装包按需生成：README 可写当前版本文件名，也可写 v<版本> 占位说明。
    installer_name = f"班级管理系统_安装包_v{num}.exe" in rm
    installer_placeholder = "班级管理系统_安装包_v<版本>.exe" in rm
    check(
        installer_name or installer_placeholder,
        "README.md: 安装包名",
        "不一致",
        f"v{num}.exe 或 v<版本>.exe",
    )

    # 说明（2026-10-03）：开发交接说明.md 已由作者删除，不再纳入版本自查。
    # 若将来重新引入该类文档，请在此处恢复"逐处独立断言"的检查。

    # 说明（2026-10-05）：原根目录《更新内容.md》已按作者要求拆分——
    # 各版本内容逐版移入 更新/ 目录（更新内容_VX.md），根文件删除，
    # 因此不再有"第 3 行当前版本"这一处可查。

    # 8. dart 文件头（允许滞后，但报告数量提醒）
    stale = []
    for f in list((ROOT / "lib").rglob("*.dart")) + list((ROOT / "test").rglob("*.dart")):
        mm = re.search(r"^ \* 版本 \(Version\): (V[\d.]+)\s*$", f.read_text(encoding="utf-8"), re.M)
        if mm and mm.group(1) != ver:
            stale.append(f"{f.relative_to(ROOT)} ({mm.group(1)})")
    # 只有 lib 下的文件头要求同步（test 允许滞后），但仍报告 lib 的
    lib_stale = [s for s in stale if s.startswith("lib")]
    if lib_stale:
        problems.append("  [X] lib/ 下有文件头版本号未同步：\n      " + "\n      ".join(lib_stale))

    if problems:
        print("\n发现不一致：")
        print("\n".join(problems))
        print(f"\n共 {len(problems)} 处问题。")
        sys.exit(1)
    print("\n[OK] 全部一致（安装包属性/文件名、README、LICENSE、pubspec、dart 头）")


if __name__ == "__main__":
    main()
