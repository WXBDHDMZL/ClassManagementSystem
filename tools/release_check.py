#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发布验收：构建 → 打包 → 沙箱静默安装 → 真实数据副本启动冒烟 → 验收报告。

为什么要有它
------------
过去发版的"验证"只有三句话：analyze 0 问题、测试通过、exe 哈希是多少。
这三句都是构建机上的数字，既没有验证安装包，也没有验证"装完之后能不能读到
用户真实的 真实记录（计数已脱敏）历史数据"。结果就是每次都要用户自己拍板"应该没问题吧"。

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

CHECKS: list[tuple[str, bool | None, str]] = []


# --------------------------------------------------------------------------- #
# 基础工具
# --------------------------------------------------------------------------- #
def say(message: str) -> None:
    print(message, flush=True)


def step(index: int, total: int, title: str) -> None:
    say("")
    say(f"=== [{index}/{total}] {title} " + "=" * max(0, 52 - len(title)))


def check(name: str, ok: bool | None, detail: str = "") -> bool | None:
    """True=通过，False=失败，None=按参数故意跳过（不等同于通过）。"""
    CHECKS.append((name, ok, detail))
    label = "OK" if ok is True else ("SKIP" if ok is None else "FAIL")
    say(f"  [{label}] {name}" + (f"：{detail}" if detail else ""))
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


def dart_executable() -> str:
    """定位 Dart AOT/CLI 可执行文件，避免 Windows 下只找到无扩展名的包装脚本。"""
    explicit = os.environ.get("CMS_DART")
    if explicit and Path(explicit).exists():
        return explicit
    found = shutil.which("dart.exe")
    if found:
        return found
    flutter = os.environ.get("CMS_FLUTTER") or shutil.which("flutter")
    if flutter:
        sibling = Path(flutter).parent / "cache" / "dart-sdk" / "bin" / "dart.exe"
        if sibling.exists():
            return str(sibling)
    return "dart"


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
# LRX3 解码（DPAPI 本机钥）
# --------------------------------------------------------------------------- #
import ctypes
from ctypes import wintypes


class _DataBlob(ctypes.Structure):
    _fields_ = [
        ("cbData", wintypes.DWORD),
        ("pbData", ctypes.POINTER(ctypes.c_ubyte)),
    ]


def _dpapi_unprotect(payload: bytes) -> bytes:
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    crypt32.CryptUnprotectData.argtypes = [
        ctypes.POINTER(_DataBlob),
        ctypes.POINTER(ctypes.c_wchar_p),
        ctypes.POINTER(_DataBlob),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(_DataBlob),
    ]
    crypt32.CryptUnprotectData.restype = wintypes.BOOL
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    kernel32.LocalFree.restype = ctypes.c_void_p

    buffer = ctypes.create_string_buffer(payload)
    blob_in = _DataBlob(
        len(payload), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte))
    )
    blob_out = _DataBlob()
    if not crypt32.CryptUnprotectData(
        ctypes.byref(blob_in),
        None,
        None,
        None,
        None,
        0x1,
        ctypes.byref(blob_out),
    ):
        raise OSError("DPAPI 解密失败")
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        kernel32.LocalFree(blob_out.pbData)


def _find_key_file(path: Path) -> Path:
    for parent in (path.parent, path.parent.parent, path.parent.parent.parent):
        candidate = parent / "class_management_data.enc.key"
        if candidate.exists():
            return candidate
    raise FileNotFoundError("找不到数据密钥文件 class_management_data.enc.key")


def _load_data_key(path: Path) -> bytes:
    key_file = _find_key_file(path)
    envelope = base64.b64decode(key_file.read_text(encoding="utf-8").strip())
    if envelope[:4] != b"LRK1":
        raise ValueError("密钥文件格式不是 LRK1")
    key = _dpapi_unprotect(envelope[4:])
    if len(key) != 32:
        raise ValueError(f"数据密钥长度异常：{len(key)}")
    return key


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


def lrx3_decode_text(encoded: str, data_key: bytes) -> str:
    raw = base64.b64decode(encoded.strip())
    if raw[:4] != b"LRX3":
        if raw[:4] == b"LRX2":
            raise ValueError("这是 V5.0.0 不支持的 LRX2 旧格式")
        raise ValueError("不是 LRX3 格式")
    salt = raw[4:20]
    nonce = raw[20:36]
    body = raw[36:-32]
    tag = raw[-32:]
    master = hmac.new(data_key, b"lrx3" + salt, hashlib.sha256).digest()
    enc_key = hmac.new(master, b"enc", hashlib.sha256).digest()
    mac_key = hmac.new(master, b"mac", hashlib.sha256).digest()
    expected = hmac.new(mac_key, raw[:-32], hashlib.sha256).digest()
    if not hmac.compare_digest(expected, tag):
        raise ValueError("HMAC 校验失败（文件损坏或被改动）")
    plain = bytes(
        a ^ b for a, b in zip(body, _keystream(enc_key, salt, nonce, len(body)))
    )
    return plain.decode("utf-8")


def decode_data_file(path: Path) -> dict:
    return json.loads(lrx3_decode_text(path.read_text(encoding="utf-8"), _load_data_key(path)))


def decode_log_file(path: Path) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    if not path.exists():
        return entries
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        data_key = _load_data_key(path)
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
            entries.append((prefix, lrx3_decode_text(payload, data_key)))
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
    for line in (result.stdout or "").splitlines():
        if not line.strip().startswith("ClassManagementSystem"):
            continue
        parts = line.split(None, 2)
        if len(parts) == 3:
            return parts[2].strip()
    return ""


def restore_registry_run(value: str) -> None:
    """恢复验收前用户已有的自启动值；空串表示原本不存在。"""
    key = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
    if value:
        subprocess.run(
            ["reg", "add", key, "/v", "ClassManagementSystem", "/t", "REG_SZ",
             "/d", value, "/f"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    else:
        subprocess.run(
            ["reg", "delete", key, "/v", "ClassManagementSystem", "/f"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )


def uninstall_keys() -> list[str]:
    # P1-3：Inno 以管理员安装时写 HKLM 的 Uninstall 项，旧实现只查 HKCU，
    # 结果恒为空、卸载检查永远“通过”。三处都查（含 32 位视图）。
    script = (
        "$paths = @("
        "'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall',"
        "'HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall',"
        "'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall'"
        "); foreach ($p in $paths) { "
        "Get-ChildItem $p -ErrorAction SilentlyContinue | "
        "Where-Object { $_.PSChildName -like '*A5B2C3D4*' } | "
        "Select-Object -ExpandProperty PSChildName }"
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
        # 审计 A-27：此前 --skip-tests 直接返回成功，等于发布验收可以完全不做质量检查。
        # 现在必须显式再加 --allow-skip-tests，并且结果里要留下醒目警告。
        say("  [FAIL] 发布验收不允许用 --skip-tests 跳过 analyze 与全量测试")
        say("         如确有原因（例如仅供内部冒烟），请加 --allow-skip-tests 并自行承担风险")
        return False

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


def stage_installer(version: str, signing_key: Path | None) -> tuple[bool, Path | None]:
    step(3, 9, "生成安装包")
    # P0-2：安装包必须带 VC++ x64 运行库，否则干净 Windows 上安装成功但程序
    # 起不来（缺少 MSVCP140.dll）。缺文件时直接失败，绝不产出“坏包”。
    redist = ROOT / "installer" / "VC_redist.x64.exe"
    redist_ok = redist.exists() and redist.stat().st_size >= 5_000_000
    check(
        "VC++ 运行库随包",
        redist_ok,
        f"{redist.name} / {redist.stat().st_size} bytes" if redist.exists() else "缺少 installer/VC_redist.x64.exe",
    )
    if not redist_ok:
        return False, None
    iscc_candidates = [
        shutil.which("iscc"),
        r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        r"C:\Program Files\Inno Setup 6\ISCC.exe",
        r"C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
        r"C:\Program Files\Inno Setup 7\ISCC.exe",
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

    signature = release_dir / f"{asset_name}.sig"
    if signing_key is None:
        check("安装包签名", False, "缺少 --signing-key，不能发布更新包")
        return False, None
    try:
        completed = subprocess.run(
            [
                dart_executable(),
                "run",
                "tools/sign_release.dart",
                "--in",
                str(asset),
                "--key",
                str(signing_key),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except (OSError, subprocess.SubprocessError) as error:
        check("安装包签名", False, f"签名工具执行失败：{error}")
        return False, None
    if completed.returncode != 0 or not signature.exists():
        check("安装包签名", False, (completed.stderr or completed.stdout or "")[-1000:])
        return False, None
    check("安装包签名", True, signature.name)
    return ok, asset


def detect_previous_installer(version: str) -> Path | None:
    """找比当前版本低的最近一个安装包，用于覆盖升级演练。

    优先 installer/output（正式安装包目录）；若已被清理，再回退到
    build/release_v*/ 历史发布目录，避免升级演练因本地资产清理而静默跳过。
    """
    candidates: list[tuple[tuple[int, ...], Path]] = []
    current = tuple(int(part) for part in version.lstrip("V").split("+")[0].split("."))
    roots = [ROOT / "installer" / "output"]
    roots.extend(sorted((ROOT / "build").glob("release_v*"), reverse=True))
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.glob("*.exe"):
            match = re.search(r"_v(\d+(?:\.\d+)+)\.exe$", path.name, re.IGNORECASE)
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

    # P1-4：验收安装包与正式版共用同一 AppId，Inno 在静默安装/卸载时会
    # 覆盖同一卸载注册项。若本机已装正式版，验收会把它从“应用和功能”里
    # 抹掉。这里先拦住，要求到干净测试环境或先卸载正式版。
    existing_keys = uninstall_keys()
    if existing_keys:
        check(
            "安装前无同名已安装程序",
            False,
            "检测到已安装的同一程序："
            + "、".join(existing_keys)
            + "。请先在测试环境卸载后再运行 release_check，避免覆盖正式安装。",
        )
        return False, install_dir, log_path

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
                "/CLOSEAPPLICATIONS",
                "/RESTARTAPPLICATIONS",
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
            "/CLOSEAPPLICATIONS",
            "/RESTARTAPPLICATIONS",
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
    step(5, 9, "数据副本启动冒烟")
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
    key_source = source_data.with_name(source_data.name + ".key")
    if key_source.exists():
        shutil.copy2(key_source, data_root / key_source.name)

    source_hash = sha256_file(source_data)
    source_data_mtime = source_data.stat().st_mtime_ns
    if target.read_bytes()[:4] == b"LRX2":
        check("数据格式", False, "V5.0.0 不再支持 LRX2 数据；请使用 V4.14.1 的 LRX3 数据验收")
        raise SystemExit("V5.0.0 不支持 LRX2 数据")
    source_summary = data_summary(decode_data_file(target))
    say(
        f"  数据副本：{source_summary['records']} 条记录 / "
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
    if registry_run_value() != registry_before:
        restore_registry_run(registry_before)
    check(
        "HKCU 自启动项未被改动",
        registry_run_value() == registry_before,
        "验收期间被程序改写，已恢复原值",
    )

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
    passed = all(ok is not False for _, ok, _ in CHECKS)
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
        status = "通过" if ok is True else ("跳过" if ok is None else "失败")
        lines.append(f"| {name} | {status} | {safe} |")

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
    parser.add_argument(
        "--skip-tests",
        action="store_true",
        help="跳过 analyze 与全量测试（必须同时给 --allow-skip-tests；结果不可用于发版结论）",
    )
    parser.add_argument(
        "--allow-skip-tests",
        action="store_true",
        help="确认已知晓风险并允许跳过测试",
    )
    parser.add_argument("--skip-build", action="store_true", help="复用已有 exe，只验证安装与冒烟")
    parser.add_argument("--keep-sandbox", action="store_true", help="保留临时安装与数据目录")
    parser.add_argument(
        "--skip-upgrade",
        action="store_true",
        help="跳过“先装旧版再覆盖升级”的演练",
    )
    parser.add_argument(
        "--data-source",
        default=None,
        help="用于冒烟的数据文件（必填，只读；请显式传脱敏副本，脚本会复制到沙箱）",
    )
    parser.add_argument(
        "--signing-key",
        default=None,
        help="离线 Ed25519 私钥文件（Base64，32 字节）；最终发布必填",
    )
    args = parser.parse_args()

    version = dart_string("version")
    pubspec_version = dart_string("pubspecVersion")
    say(f"发布验收 {version}（{pubspec_version}）")
    say(f"项目目录：{ROOT}")

    if not args.data_source:
        check(
            "冒烟数据源",
            False,
            "必须显式传 --data-source（脱敏数据副本）。禁止默认读取真实数据目录。",
        )
        return 1
    source_data = Path(args.data_source)
    if not source_data.exists():
        check("冒烟数据文件存在", False, str(source_data))
        return 1

    SANDBOX_ROOT.mkdir(parents=True, exist_ok=True)

    skip_tests = args.skip_tests and getattr(args, "allow_skip_tests", False)
    if skip_tests:
        say("  [WARN] 已按 --allow-skip-tests 跳过 analyze 与全量测试：本次结果不可用于发版结论")
    if not stage_quality(version, skip_tests):
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

    signing_key = Path(args.signing_key) if args.signing_key else None
    ok, asset = stage_installer(version, signing_key)
    if not ok or asset is None:
        write_report(version, pubspec_version, {})
        return 1

    upgrade_from = None if args.skip_upgrade else detect_previous_installer(version)
    if args.skip_upgrade:
        check("覆盖升级演练", None, "SKIP（--skip-upgrade）")
    elif upgrade_from is None:
        check("覆盖升级演练", None, "SKIP：未找到更旧版本安装包")
    else:
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
        check("静默卸载", None, "SKIP（--keep-sandbox）")
        check("清理沙箱", None, "SKIP（--keep-sandbox）")
        say(f"  [KEEP] 沙箱目录保留在 {SANDBOX_ROOT}")

    report = write_report(version, pubspec_version, details)

    passed = all(ok is not False for _, ok, _ in CHECKS)
    skipped = [name for name, ok, _ in CHECKS if ok is None]
    say("")
    say("=" * 70)
    skip_suffix = f"；跳过 {len(skipped)} 项：{'、'.join(skipped)}" if skipped else ""
    say(f"验收结果：{'通过' if passed else '未通过'}（报告：{report}{skip_suffix}）")
    if passed:
        say(f"发布资产：{asset}（同目录下 .sha256 / .sig 可一并上传）")
    say("=" * 70)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
