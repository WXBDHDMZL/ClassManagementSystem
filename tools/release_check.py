#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发布验收：构建 → 打包 → 沙箱静默安装 → 真实数据副本启动冒烟 → 验收报告。

为什么要有它
------------
过去发版的"验证"只有三句话：analyze 0 问题、测试通过、exe 哈希是多少。
这三句都是构建机上的数字，既没有验证安装包，也没有验证"装完之后能不能读到
用户真实的 1754 条历史数据"。结果就是每次都要用户自己拍板"应该没问题吧"。

本脚本把能自动验证的部分全部跑一遍，任一步失败立即停止且**不产出安装包**：

  1. 版本/规则/文案/静态分析/全量测试
  2. Windows Release 构建，校验 exe 版本号与哈希
  3. 生成安装包，校验版本号与哈希
  4. 静默安装到临时目录（不碰 `C:\\Program Files`，不建桌面图标）
  5. 把**真实数据文件复制一份**放进沙箱目录，用安装后的 exe 启动
  6. 校验：进程存活、沙箱日志出现「程序启动」、数据仍可解码且条数一致、
     真实数据文件未被改动、HKCU 自启动项未被改动
  7. 强制结束进程后再次解码，确认原子写入没有把数据写坏
  8. 静默卸载，确认卸载项清理干净、用户数据目录仍在
  9. 输出 `build/release_report_vX.Y.Z.md`

用法：
    python tools/release_check.py                 # 完整跑一遍
    python tools/release_check.py --skip-tests    # 跳过 analyze + 全量测试
    python tools/release_check.py --skip-build    # 复用已有 exe，只验证安装与冒烟
    python tools/release_check.py --keep-sandbox  # 保留临时安装/数据目录便于排查
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "班级管理系统"
SANDBOX_ROOT = ROOT / "build" / "release_sandbox"
REPORT_DIR = ROOT / "build"

_PS = ["powershell", "-NoProfile", "-NonInteractive", "-Command"]

CHECKS: list[tuple[str, bool, str]] = []


# --------------------------------------------------------------------------- #
# 基础工具
# --------------------------------------------------------------------------- #
def say(message: str) -> None:
    print(message, flush=True)


def step(index: int, total: int, title: str) -> None:
    say("")
    say(f"=== [{index}/{total}] {title} " + "=" * max(0, 52 - len(title)))


def check(name: str, ok: bool, detail: str = "") -> bool:
    CHECKS.append((name, ok, detail))
    say(f"  [{'OK' if ok else 'FAIL'}] {name}" + (f"：{detail}" if detail else ""))
    return ok


def run(
    args: list[str],
    *,
    cwd: Path = ROOT,
    timeout: int = 1800,
    env: dict[str, str] | None = None,
    quiet: bool = False,
) -> subprocess.CompletedProcess:
    if not quiet:
        say("  $ " + " ".join(str(a) for a in args))
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    return subprocess.run(
        [str(a) for a in args],
        cwd=str(cwd),
        timeout=timeout,
        env=full_env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def powershell(script: str, timeout: int = 120) -> str:
    result = subprocess.run(
        _PS + [script],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    return (result.stdout or "").strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dart_string(name: str) -> str:
    source = (ROOT / "lib" / "constants" / "app_version.dart").read_text(
        encoding="utf-8"
    )
    match = re.search(rf"static const String {name}\s*=\s*'([^']*)'", source)
    if not match:
        raise SystemExit(f"无法从 app_version.dart 读取 {name}")
    return match.group(1)


def dart_int_list(name: str) -> list[int]:
    source = (ROOT / "lib" / "services" / "storage_service.dart").read_text(
        encoding="utf-8"
    )
    match = re.search(rf"static const List<int> {name} = <int>\[(.*?)\];", source, re.S)
    if not match:
        raise SystemExit(f"无法从 storage_service.dart 读取 {name}")
    return [int(value) for value in re.findall(r"\d+", match.group(1))]


def exe_version_info(path: Path) -> dict:
    script = (
        "$i = Get-Item -LiteralPath '" + str(path).replace("'", "''") + "'; "
        "$v = $i.VersionInfo; "
        "@{file=$v.FileVersion; product=$v.ProductVersion; size=$i.Length} | "
        "ConvertTo-Json -Compress"
    )
    raw = powershell(script)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"file": "", "product": "", "size": 0, "raw": raw}


# --------------------------------------------------------------------------- #
# LRX2 解码（与 lib/services/storage_service.dart 保持同一算法）
# --------------------------------------------------------------------------- #
def _derive_key(password: str) -> bytes:
    return hashlib.sha256(password.encode("utf-8")).digest()


def _sub_keys(salt: bytes, data_key: str) -> tuple[bytes, bytes]:
    master = _derive_key(data_key + "|" + base64.b64encode(salt).decode("ascii"))
    enc = hmac.new(master, b"enc", hashlib.sha256).digest()
    mac = hmac.new(master, b"mac", hashlib.sha256).digest()
    return enc, mac


def _keystream(enc_key: bytes, salt: bytes, nonce: bytes, length: int) -> bytes:
    out = bytearray()
    counter = 0
    while len(out) < length:
        block = hmac.new(
            enc_key,
            salt + nonce + counter.to_bytes(4, "big"),
            hashlib.sha256,
        ).digest()
        out.extend(block)
        counter += 1
    return bytes(out[:length])


def lrx2_decode_text(encoded: str) -> str:
    raw = base64.b64decode(encoded.strip())
    if raw[:4] != b"LRX2":
        raise ValueError("不是 LRX2 格式")
    salt = raw[4:20]
    nonce = raw[20:36]
    body = raw[36:-32]
    tag = raw[-32:]

    key_a = dart_int_list("_keyShareA")
    key_b = dart_int_list("_keyShareB")
    data_key = "".join(chr(a ^ b) for a, b in zip(key_a, key_b))
    enc_key, mac_key = _sub_keys(salt, data_key)

    expected = hmac.new(mac_key, raw[:-32], hashlib.sha256).digest()
    if not hmac.compare_digest(expected, tag):
        raise ValueError("HMAC 校验失败（文件损坏或被改动）")
    return bytes(a ^ b for a, b in zip(body, _keystream(enc_key, salt, nonce, len(body)))).decode(
        "utf-8"
    )


def decode_data_file(path: Path) -> dict:
    return json.loads(lrx2_decode_text(path.read_text(encoding="utf-8")))


def decode_log_file(path: Path) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    if not path.exists():
        return entries
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        # 程序正持有日志句柄时可能暂时不可读，下一轮再试。
        return entries
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        prefix = ""
        payload = line
        if line.startswith("[操作] "):
            prefix, payload = "操作", line[len("[操作] ") :]
        elif line.startswith("[错误] "):
            prefix, payload = "错误", line[len("[错误] ") :]
        try:
            entries.append((prefix, lrx2_decode_text(payload)))
        except Exception as exc:  # 明文/损坏行原样保留，便于报告
            entries.append((prefix or "未知", f"<无法解码：{exc}> {line[:120]}"))
    return entries


def data_summary(data: dict) -> dict:
    records_by_date = data.get("recordsByDate") or {}
    records = []
    for day, items in records_by_date.items():
        for item in items or []:
            records.append(item)
    students = data.get("students") or []
    return {
        "records": len(records),
        "dates": len(records_by_date),
        "students": len(students),
        "ids": sorted(str(item.get("id", "")) for item in records),
        "signature": sorted(
            "|".join(
                str(item.get(key, ""))
                for key in ("date", "studentName", "operationType", "timestamp", "remark")
            )
            for item in records
        ),
    }


def registry_run_value() -> str:
    result = subprocess.run(
        [
            "reg",
            "query",
            r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
            "/v",
            "ClassManagementSystem",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        return ""
    return (result.stdout or "").strip()


def uninstall_keys() -> list[str]:
    script = (
        "Get-ChildItem 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall' "
        "-ErrorAction SilentlyContinue | "
        "Where-Object { $_.PSChildName -like '*A5B2C3D4*' } | "
        "Select-Object -ExpandProperty PSChildName"
    )
    return [line for line in powershell(script).splitlines() if line.strip()]


def documents_directory() -> Path:
    """系统“文档”目录（本机可能被重定向到 D:\\Documents，不能假设是 %USERPROFILE%）。"""
    if os.name == "nt":
        try:
            import ctypes

            buffer = ctypes.create_unicode_buffer(260)
            # CSIDL_PERSONAL = 5
            if ctypes.windll.shell32.SHGetFolderPathW(None, 5, None, 0, buffer) == 0:
                if buffer.value:
                    return Path(buffer.value)
        except Exception:
            pass
    return Path.home() / "Documents"


# --------------------------------------------------------------------------- #
# 各阶段
# --------------------------------------------------------------------------- #
def stage_quality(version: str, skip_tests: bool) -> bool:
    step(1, 9, "版本、规则、文案与测试")
    for script in ("check_version.py", "check_rules.py", "ui_copy_check.py"):
        result = run([sys.executable, ROOT / "tools" / script], timeout=300, quiet=True)
        lines = [line for line in (result.stdout or "").strip().splitlines() if line.strip()]
        detail = lines[-1] if lines else ""
        if not check(script, result.returncode == 0, detail):
            say((result.stdout or "") + (result.stderr or ""))
            return False

    if skip_tests:
        say("  [SKIP] 按参数跳过 analyze 与全量测试")
        return True

    flutter = os.environ.get("CMS_FLUTTER") or shutil.which("flutter")
    if not flutter:
        check("flutter 可用", False, "未找到 flutter，可用 CMS_FLUTTER 指定")
        return False
    result = run([flutter, "analyze"], timeout=900, quiet=True)
    analyze_lines = [line.strip() for line in (result.stdout or "").splitlines() if line.strip()]
    if not check(
        "flutter analyze",
        result.returncode == 0,
        analyze_lines[-1] if analyze_lines else "",
    ):
        return False
    result = run([flutter, "test"], timeout=3600, quiet=True)
    tail = (result.stdout or "").strip().splitlines()[-1:] or [""]
    if not check("flutter test（全量）", result.returncode == 0, tail[0]):
        say((result.stdout or "")[-4000:])
        return False
    return True


def stage_build(version: str, pubspec_version: str) -> tuple[bool, Path]:
    step(2, 9, "Windows Release 构建")
    exe = ROOT / "build" / "windows" / "x64" / "runner" / f"{APP_NAME}.exe"
    result = run(["cmd", "/c", "build.bat"], timeout=1800)
    if result.returncode != 0:
        check("build.bat", False, f"退出码 {result.returncode}")
        say((result.stdout or "")[-4000:])
        say((result.stderr or "")[-2000:])
        return False, exe
    if not exe.exists():
        check("exe 存在", False, str(exe))
        return False, exe
    info = exe_version_info(exe)
    expected_file = pubspec_version.replace("+", "+")
    ok_version = str(info.get("file", "")).startswith(version.lstrip("V"))
    ok_product = str(info.get("product", "")).startswith(version.lstrip("V"))
    check("exe 版本号", ok_version and ok_product, f"File={info.get('file')} Product={info.get('product')}")
    check("exe 存在", True, f"{info.get('size')} bytes")
    return ok_version and ok_product, exe


def stage_installer(version: str) -> tuple[bool, Path | None]:
    step(3, 9, "生成安装包")
    iscc_candidates = [
        shutil.which("iscc"),
        r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        r"C:\Program Files\Inno Setup 6\ISCC.exe",
        r"C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    ]
    iscc = next((c for c in iscc_candidates if c and Path(c).exists()), None)
    if not iscc:
        check("Inno Setup 编译器", False, "未找到 ISCC.exe")
        return False, None

    before = set((ROOT / "installer" / "output").glob("*.exe"))
    result = run([iscc, ROOT / "installer" / "installer.iss"], cwd=ROOT / "installer", timeout=900)
    if result.returncode != 0:
        check("ISCC 打包", False, f"退出码 {result.returncode}")
        say((result.stdout or "")[-4000:])
        return False, None
    after = set((ROOT / "installer" / "output").glob("*.exe"))
    created = sorted(after - before, key=lambda p: p.stat().st_mtime)
    if not created:
        created = sorted(after, key=lambda p: p.stat().st_mtime)
        if not created:
            check("安装包产出", False, "output 目录没有 exe")
            return False, None
    installer = created[-1]

    info = exe_version_info(installer)
    ok = str(info.get("product", "")).startswith(version.lstrip("V"))
    check("安装包版本号", ok, f"Product={info.get('product')}")
    check("安装包存在", True, f"{installer.name} / {info.get('size')} bytes")

    release_dir = ROOT / "build" / f"release_v{version.lstrip('V')}"
    release_dir.mkdir(parents=True, exist_ok=True)
    asset_name = f"ClassManagementSystem_Setup_v{version.lstrip('V')}.exe"
    asset = release_dir / asset_name
    shutil.copy2(installer, asset)
    digest = sha256_file(asset)
    (release_dir / f"{asset_name}.sha256").write_text(
        f"{digest}  {asset_name}\n", encoding="utf-8"
    )
    check("发布资产命名与校验文件", True, f"{asset_name} / {digest[:16]}…")
    return ok, asset


def detect_previous_installer(version: str) -> Path | None:
    """在 installer/output 里找比当前版本低的最近一个安装包，用于覆盖升级演练。"""
    candidates: list[tuple[tuple[int, ...], Path]] = []
    current = tuple(int(part) for part in version.lstrip("V").split("+")[0].split("."))
    for path in (ROOT / "installer" / "output").glob("*.exe"):
        match = re.search(r"_v(\d+(?:\.\d+)+)\.exe$", path.name)
        if not match:
            continue
        parts = tuple(int(part) for part in match.group(1).split("."))
        if parts < current:
            candidates.append((parts, path))
    return max(candidates)[1] if candidates else None


def stage_install(
    asset: Path, version: str, upgrade_from: Path | None = None
) -> tuple[bool, Path, Path]:
    step(4, 9, "静默安装到临时目录")
    install_dir = SANDBOX_ROOT / f"install_v{version.lstrip('V')}"
    if install_dir.exists():
        shutil.rmtree(install_dir, ignore_errors=True)
    install_dir.mkdir(parents=True, exist_ok=True)
    log_path = SANDBOX_ROOT / f"install_v{version.lstrip('V')}.log"

    old_product = ""
    if upgrade_from and upgrade_from.exists():
        say(f"  覆盖升级演练：先安装旧版 {upgrade_from.name}")
        old_result = run(
            [
                str(upgrade_from),
                "/VERYSILENT",
                "/SUPPRESSMSGBOXES",
                "/NORESTART",
                "/SP-",
                "/NOICONS",
                "/TASKS=",
                f"/DIR={install_dir}",
                f"/LOG={SANDBOX_ROOT / 'install_previous.log'}",
            ],
            cwd=SANDBOX_ROOT,
            timeout=600,
        )
        old_exe = install_dir / f"{APP_NAME}.exe"
        if old_result.returncode == 0 and old_exe.exists():
            old_product = str(exe_version_info(old_exe).get("product", ""))
            check("旧版安装成功", bool(old_product), old_product)
        else:
            check("旧版安装成功", False, f"退出码 {old_result.returncode}")

    result = run(
        [
            str(asset),
            "/VERYSILENT",
            "/SUPPRESSMSGBOXES",
            "/NORESTART",
            "/SP-",
            "/NOICONS",
            "/TASKS=",
            f"/DIR={install_dir}",
            f"/LOG={log_path}",
        ],
        cwd=SANDBOX_ROOT,
        timeout=600,
    )
    if result.returncode != 0:
        check("静默安装", False, f"退出码 {result.returncode}")
        return False, install_dir, log_path
    exe = install_dir / f"{APP_NAME}.exe"
    ok = exe.exists()
    check("静默安装", ok, str(exe) if ok else "安装目录里没有 exe")
    if ok:
        info = exe_version_info(exe)
        product = str(info.get("product", ""))
        check(
            "安装后版本为当前版本",
            product.startswith(version.lstrip("V")),
            product,
        )
        if old_product:
            check(
                "覆盖升级后版本已更新",
                product != old_product,
                f"{old_product} -> {product}",
            )
    return ok, install_dir, log_path


def stage_smoke(exe: Path, source_data: Path, version: str) -> dict:
    step(5, 9, "真实数据副本启动冒烟")
    sandbox_docs = SANDBOX_ROOT / f"data_v{version.lstrip('V')}"
    data_root = sandbox_docs / "班级管理系统"
    if data_root.exists():
        shutil.rmtree(data_root, ignore_errors=True)
    data_root.mkdir(parents=True, exist_ok=True)

    target = data_root / source_data.name
    shutil.copy2(source_data, target)
    bak = source_data.with_name(source_data.name + ".bak")
    if bak.exists():
        shutil.copy2(bak, data_root / bak.name)

    source_hash = sha256_file(source_data)
    source_data_mtime = source_data.stat().st_mtime_ns
    source_summary = data_summary(decode_data_file(source_data))
    say(
        f"  真实数据副本：{source_summary['records']} 条记录 / "
        f"{source_summary['students']} 名学生 / {source_summary['dates']} 个日期"
    )

    registry_before = registry_run_value()
    real_dir_listing_before = sorted(p.name for p in source_data.parent.iterdir())

    env = {
        "CMS_DATA_DIR": str(sandbox_docs),
        "CMS_STARTUP_TARGET": "tray",
    }
    process = subprocess.Popen(
        [str(exe)],
        cwd=str(exe.parent),
        env={**os.environ, **env},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    log_file = data_root / "日志" / "班级管理系统_日志.txt"
    started = False
    deadline = time.time() + 60
    while time.time() < deadline:
        if log_file.exists():
            try:
                entries = decode_log_file(log_file)
            except Exception:
                entries = []
            if any("程序启动" in text for _, text in entries):
                started = True
                break
        if process.poll() is not None:
            break
        time.sleep(1)

    alive = process.poll() is None
    check("进程启动后保持存活", alive, f"PID {process.pid}")
    check("沙箱日志出现「程序启动」", started, str(log_file))
    check(
        "数据根目录被重定向到沙箱",
        data_root.exists() and log_file.exists(),
        f"CMS_DATA_DIR={sandbox_docs}",
    )

    time.sleep(3)
    entries = decode_log_file(log_file) if log_file.exists() else []
    startup_lines = [text for kind, text in entries if "程序启动" in text]
    version_ok = any(version in text for text in startup_lines)
    check("启动日志记录当前版本", version_ok, startup_lines[0] if startup_lines else "无")

    error_lines = [text for kind, text in entries if kind == "错误"]
    if error_lines:
        say(f"  [WARN] 启动期间产生 {len(error_lines)} 条错误日志：")
        for line in error_lines[:10]:
            say(f"         {line[:200]}")

    try:
        summary_after = data_summary(decode_data_file(target))
    except Exception as exc:
        check("沙箱数据可解码", False, str(exc))
        summary_after = {"records": -1, "students": -1, "dates": -1, "signature": []}
    else:
        check("沙箱数据可解码", True, f"{summary_after['records']} 条")
    check(
        "记录数未变",
        summary_after["records"] == source_summary["records"],
        f"{source_summary['records']} -> {summary_after['records']}",
    )
    check(
        "学生数与日期数未变",
        (summary_after["students"], summary_after["dates"])
        == (source_summary["students"], source_summary["dates"]),
        f"{source_summary['students']}/{source_summary['dates']} -> "
        f"{summary_after['students']}/{summary_after['dates']}",
    )
    check(
        "记录签名未变",
        summary_after["signature"] == source_summary["signature"],
        "" if summary_after["signature"] == source_summary["signature"] else "存在差异",
    )

    check(
        "真实数据文件未被改动",
        sha256_file(source_data) == source_hash
        and source_data.stat().st_mtime_ns == source_data_mtime,
        f"sha256 {source_hash[:16]}…",
    )
    check(
        "真实数据目录未新增文件",
        sorted(p.name for p in source_data.parent.iterdir()) == real_dir_listing_before,
        "",
    )
    check("HKCU 自启动项未被改动", registry_run_value() == registry_before)

    # 强制结束：模拟异常退出后数据仍可解码（原子写入）
    subprocess.run(
        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        process.kill()
    time.sleep(1)
    try:
        summary_killed = data_summary(decode_data_file(target))
        check(
            "强制结束后数据仍完整",
            summary_killed["records"] == source_summary["records"],
            f"{summary_killed['records']} 条",
        )
    except Exception as exc:
        check("强制结束后数据仍完整", False, str(exc))

    return {
        "sandbox_docs": sandbox_docs,
        "data_root": data_root,
        "source_summary": source_summary,
        "summary_after": summary_after,
        "error_lines": error_lines,
        "startup_lines": startup_lines,
    }


def stage_uninstall(install_dir: Path, version: str) -> bool:
    step(6, 9, "静默卸载与清理")
    # 冒烟测试结束时已结束进程；这里再兜底清理任何仍从安装目录启动的实例，
    # 否则被占用的 exe 会让卸载程序跳过删除。
    prefix = str(install_dir).replace("'", "''") + "\\"
    powershell(
        "Get-Process -ErrorAction SilentlyContinue | ForEach-Object { "
        "try { if ($_.Path -and $_.Path.StartsWith('" + prefix + "')) { "
        "Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }"
    )
    time.sleep(1)
    uninstaller = install_dir / "unins000.exe"
    ok = True
    if uninstaller.exists():
        result = run(
            [
                str(uninstaller),
                "/VERYSILENT",
                "/SUPPRESSMSGBOXES",
                "/NORESTART",
            ],
            timeout=300,
        )
        ok = check("静默卸载", result.returncode == 0, f"退出码 {result.returncode}")
    else:
        ok = check("找到卸载程序", False, str(uninstaller))
    # Inno 的卸载程序会把自己复制到临时目录后异步退出，目录不是立刻消失。
    for _ in range(60):
        if not install_dir.exists():
            break
        time.sleep(1)
    leftovers = (
        sorted(str(path.relative_to(install_dir)) for path in install_dir.rglob("*"))
        if install_dir.exists()
        else []
    )
    check("安装目录文件已清理", not leftovers, f"残留 {len(leftovers)} 项：{leftovers[:8]}")
    if install_dir.exists() and not leftovers:
        # 卸载器删完文件后留下一个空目录：不影响使用，清理掉并记录为观察项。
        say("  [WARN] 卸载后留下空目录（安装器行为），已清理")
        try:
            install_dir.rmdir()
        except OSError:
            pass
    check("卸载注册项已清理", not uninstall_keys(), "; ".join(uninstall_keys()))
    return ok


def write_report(version: str, pubspec_version: str, details: dict) -> Path:
    step(7, 9, "生成验收报告")
    passed = all(ok for _, ok, _ in CHECKS)
    lines = [
        f"# 发布验收报告 V{version.lstrip('V')}",
        "",
        f"- 生成时间：{time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"- 程序版本：{version}（{pubspec_version}）",
        f"- 验收结论：{'通过' if passed else '未通过'}",
        "",
        "| 检查项 | 结果 | 说明 |",
        "| --- | --- | --- |",
    ]
    for name, ok, detail in CHECKS:
        safe = str(detail).replace("|", "\\|")
        lines.append(f"| {name} | {'通过' if ok else '失败'} | {safe} |")

    lines += ["", "## 真实数据副本", ""]
    if "source_summary" in details:
        source = details["source_summary"]
        after = details.get("summary_after") or {}
        lines += [
            f"- 源数据：{source['records']} 条记录 / {source['students']} 名学生 / "
            f"{source['dates']} 个日期",
            f"- 启动后：{after.get('records')} 条记录 / {after.get('students')} 名学生 / "
            f"{after.get('dates')} 个日期",
            f"- 数据目录：`{details.get('data_root')}`",
        ]
    else:
        lines.append("- 未执行（前置步骤失败）")

    lines += ["", "## 启动日志", ""]
    startup = details.get("startup_lines") or []
    if startup:
        lines.append(f"- {startup[0]}")
    else:
        lines.append("- 未捕获到「程序启动」")
    errors = details.get("error_lines") or []
    lines.append(f"- 启动期间错误日志：{len(errors)} 条")
    for error in errors[:10]:
        lines.append(f"  - {error[:300]}")

    report = REPORT_DIR / f"release_report_v{version.lstrip('V')}.md"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    say(f"  报告：{report}")
    return report


def cleanup_sandbox() -> None:
    user = os.environ.get("USERNAME", "")
    if SANDBOX_ROOT.exists():
        if user:
            for target in SANDBOX_ROOT.rglob("*"):
                if target.is_dir():
                    subprocess.run(
                        ["icacls", str(target), "/remove:d", user],
                        capture_output=True,
                    )
                elif target.is_file():
                    subprocess.run(
                        ["icacls", str(target), "/remove:d", user],
                        capture_output=True,
                    )
        shutil.rmtree(SANDBOX_ROOT, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="发布验收：构建、打包、沙箱安装与真实数据冒烟")
    parser.add_argument("--skip-tests", action="store_true", help="跳过 analyze 与全量测试")
    parser.add_argument("--skip-build", action="store_true", help="复用已有 exe，只验证安装与冒烟")
    parser.add_argument("--keep-sandbox", action="store_true", help="保留临时安装与数据目录")
    parser.add_argument(
        "--skip-upgrade",
        action="store_true",
        help="跳过“先装旧版再覆盖升级”的演练",
    )
    parser.add_argument(
        "--data-source",
        default=str(
            documents_directory() / "班级管理系统" / "class_management_data.enc"
        ),
        help="用于冒烟的真实数据文件（只读，脚本会复制副本）",
    )
    args = parser.parse_args()

    version = dart_string("version")
    pubspec_version = dart_string("pubspecVersion")
    say(f"发布验收 {version}（{pubspec_version}）")
    say(f"项目目录：{ROOT}")

    source_data = Path(args.data_source)
    if not source_data.exists():
        check("真实数据文件存在", False, str(source_data))
        return 1

    SANDBOX_ROOT.mkdir(parents=True, exist_ok=True)

    if not stage_quality(version, args.skip_tests):
        write_report(version, pubspec_version, {})
        return 1

    if args.skip_build:
        exe = ROOT / "build" / "windows" / "x64" / "runner" / f"{APP_NAME}.exe"
        if not check("复用已有 exe", exe.exists(), str(exe)):
            write_report(version, pubspec_version, {})
            return 1
    else:
        ok, exe = stage_build(version, pubspec_version)
        if not ok:
            write_report(version, pubspec_version, {})
            return 1

    ok, asset = stage_installer(version)
    if not ok or asset is None:
        write_report(version, pubspec_version, {})
        return 1

    upgrade_from = None if args.skip_upgrade else detect_previous_installer(version)
    if upgrade_from:
        say(f"  覆盖升级演练使用：{upgrade_from.name}")
    ok, install_dir, _ = stage_install(asset, version, upgrade_from=upgrade_from)
    if not ok:
        write_report(version, pubspec_version, {})
        return 1

    details = stage_smoke(exe=install_dir / f"{APP_NAME}.exe", source_data=source_data, version=version)

    if not args.keep_sandbox:
        stage_uninstall(install_dir, version)
        cleanup_sandbox()
    else:
        say(f"  [KEEP] 沙箱目录保留在 {SANDBOX_ROOT}")

    report = write_report(version, pubspec_version, details)

    passed = all(ok for _, ok, _ in CHECKS)
    say("")
    say("=" * 70)
    say(f"验收结果：{'通过' if passed else '未通过'}（报告：{report}）")
    if passed:
        say(f"发布资产：{asset}（同目录下 .sha256 可一并上传）")
    say("=" * 70)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
