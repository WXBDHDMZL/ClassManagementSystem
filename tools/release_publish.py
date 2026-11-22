#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `release_check.py` 产出的安装包上传到 GitHub Release。

为什么要有它
------------
程序的自动更新只认两样东西：
  1. Release 资产里名字含 `Setup` 的可执行文件；
  2. 与它同名的 `.sha256` 文件（内容为 64 位十六进制哈希，可带文件名）；
  3. 与它同名的 `.sig` 文件（对 SHA-256 摘要的 Ed25519 签名）。

手工上传很容易在这三点上出错：传了中文文件名的安装包、忘了传 `.sha256`、
或者哈希/签名和文件名对不上，客户端就会更新失败或拒绝更新。

本脚本只做一件事：把已经通过验收的资产按上面的规则上传。它不会构建、不会
打包、不会覆盖已有资产；同名资产已存在时直接报错退出。

用法：
    python tools/release_publish.py            # 上传当前版本（优先读 GITHUB_TOKEN，其次读 Windows 凭据管理器）
    python tools/release_publish.py --dry-run  # 只检查资产与远端状态
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
OWNER = "WXBDHDMZL"
REPO = "ClassManagementSystem"
API = "https://api.github.com"


def say(message: str) -> None:
    print(message, flush=True)


def dart_string(name: str) -> str:
    source = (ROOT / "lib" / "constants" / "app_version.dart").read_text(encoding="utf-8")
    match = re.search(rf"static const String {name}\s*=\s*'([^']*)'", source)
    if not match:
        raise SystemExit(f"无法从 app_version.dart 读取 {name}")
    return match.group(1)


def run_git(*args: str) -> tuple[bool, str]:
    """返回 (成功, stdout 去空白)。失败时为 False，调用方必须把它当成异常。"""
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return False, ""
    return completed.returncode == 0, completed.stdout.strip()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_checksum(text: str, asset_name: str) -> str | None:
    """解析 `hash  filename`；格式、文件名或哈希不合法时返回 None。"""
    parts = text.strip().split()
    if len(parts) < 1 or re.fullmatch(r"[0-9a-fA-F]{64}", parts[0]) is None:
        return None
    if len(parts) >= 2 and parts[1].lstrip("*") != asset_name:
        return None
    return parts[0].lower()


def public_key_base64() -> str:
    source = (ROOT / "lib" / "constants" / "update_signing_key.dart").read_text(
        encoding="utf-8"
    )
    match = re.search(r"publicKeyBase64\s*=\s*'([^']+)'", source)
    if not match:
        raise SystemExit("无法从 update_signing_key.dart 读取公钥")
    return match.group(1)


def dart_executable() -> str:
    """定位 Dart CLI，优先 dart.exe，避免 Windows 下只找到无扩展名包装脚本。"""
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


def verify_signature(asset: Path, signature: Path) -> bool:
    """用 Dart 验签工具复核 .sig，避免把损坏签名上传。"""
    try:
        completed = subprocess.run(
            [
                dart_executable(),
                "run",
                "tools/sign_release.dart",
                "--verify",
                "--in",
                str(asset),
                "--sig",
                str(signature),
                "--pub",
                public_key_base64(),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def product_version_matches(product: str, version: str) -> bool:
    """只接受精确版本（可带 +build），避免 4.13.7 误匹配 4.13.70。"""
    return re.fullmatch(
        rf"{re.escape(version)}(?:\+[0-9A-Za-z.-]+)?", product.strip()
    ) is not None


def git_release_problem() -> str | None:
    """发布必须来自已推送的 main，且工作树干净。"""
    try:
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return "无法读取 git 状态"
    if status.returncode != 0:
        return "git status 执行失败"
    if status.stdout.strip():
        return "工作树不干净，请先提交或还原改动"
    ok, branch = run_git("rev-parse", "--abbrev-ref", "HEAD")
    if not ok:
        return "无法读取当前分支"
    if branch != "main":
        return f"当前分支为 {branch!r}，发布必须从 main 执行"
    ok, head = run_git("rev-parse", "HEAD")
    if not ok or not head:
        return "无法读取 HEAD"
    ok, remote = run_git("rev-parse", "origin/main")
    if not ok or not remote:
        return "缺少 origin/main，请先 fetch 并推送 main"
    if head != remote:
        return "HEAD 与 origin/main 不一致，请先推送 main"
    return None


def git_tag_problem(version: str) -> str | None:
    """发布 tag 必须已存在且指向当前 HEAD，避免源码归档与安装包不一致。"""
    tag = f"v{version}"
    ok, tag_commit = run_git("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
    if not ok or not tag_commit:
        return f"缺少标签 {tag}；请先在当前 HEAD 创建并推送标签"
    ok, head = run_git("rev-parse", "HEAD")
    if not ok or not head:
        return "无法读取 HEAD"
    if tag_commit != head:
        return (
            f"标签 {tag} 指向 {tag_commit[:12]}，当前 HEAD 为 {head[:12]}；"
            "请先把标签移到 HEAD 或从标签对应提交重新构建"
        )
    ok, remote = run_git("ls-remote", "--tags", "origin", f"refs/tags/{tag}")
    if not ok or not remote:
        return f"远端缺少标签 {tag}；请先推送标签"
    remote_shas = {
        line.split()[0]
        for line in remote.splitlines()
        if line.split() and line.split()[-1] in (f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    }
    if tag_commit not in remote_shas:
        return f"远端标签 {tag} 与本地不一致；请先推送标签"
    return None


def release_report_problem(version: str) -> str | None:
    """release_check 的报告必须存在且明确通过。"""
    report = ROOT / "build" / f"release_report_v{version}.md"
    if not report.exists():
        return f"缺少发布验收报告 {report}"
    text = report.read_text(encoding="utf-8", errors="replace")
    if f"# 发布验收报告 V{version}" not in text:
        return f"发布验收报告版本不是 V{version}"
    if "验收结论：通过" not in text:
        return "发布验收报告结论不是“通过”"
    for marker in ("| 失败 |", "| 未通过 |", "验收结论：失败"):
        if marker in text:
            return f"发布验收报告包含失败记录：{marker}"
    return None


def request(
    method: str,
    url: str,
    token: str,
    payload: dict | None = None,
    *,
    raw: bytes | None = None,
    content_type: str = "application/json",
) -> tuple[int, dict | str]:
    data = raw
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ClassManagementSystem-release-publish",
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    if data is not None:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            body = response.read().decode("utf-8", errors="replace")
            try:
                return response.status, json.loads(body)
            except json.JSONDecodeError:
                return response.status, body
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        try:
            return error.code, json.loads(body)
        except json.JSONDecodeError:
            return error.code, body


def system_credential() -> str:
    """从 Windows 凭据管理器读取 github.com 凭据（与 git push 使用同一来源）。"""
    try:
        completed = subprocess.run(
            ["git", "-c", "credential.helper=wincred", "credential", "fill"],
            input="protocol=https\nhost=github.com\n\n",
            capture_output=True,
            text=True,
            timeout=20,
        )
        for line in (completed.stdout or "").splitlines():
            if line.startswith("password="):
                return line.split("=", 1)[1].strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="上传安装包与校验文件到 GitHub Release")
    parser.add_argument("--dry-run", action="store_true", help="只检查，不实际创建/上传")
    parser.add_argument("--notes", default="", help="Release 说明（默认使用 更新/更新内容_VX.Y.Z.md）")
    parser.add_argument(
        "--extra-asset",
        action="append",
        default=[],
        help="额外上传的资产（可重复），例如历史更新记录 zip；不要求 .sha256/.sig",
    )
    args = parser.parse_args()

    version = dart_string("version").lstrip("V")
    tag = f"v{version}"
    try:
        target_commitish = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=ROOT,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        target_commitish = ""
    if not target_commitish:
        say("[FAIL] 无法读取 HEAD，拒绝发布")
        return 1
    release_dir = ROOT / "build" / f"release_v{version}"
    asset_name = f"ClassManagementSystem_Setup_v{version}.exe"
    asset = release_dir / asset_name
    checksum = release_dir / f"{asset_name}.sha256"
    signature = release_dir / f"{asset_name}.sig"

    if not asset.exists() or not checksum.exists() or not signature.exists():
        say(f"[FAIL] 缺少发布资产（需 exe/.sha256/.sig），请先运行 tools/release_check.py：{release_dir}")
        return 1

    # F1 发布链加固：验收报告、git 状态与远端 HEAD 必须一致，避免绕过
    # release_check.py 手工发布，或把未推送的构建挂到 Release 上。
    git_problem = git_release_problem()
    if git_problem:
        say(f"[FAIL] {git_problem}")
        return 1
    tag_problem = git_tag_problem(version)
    if tag_problem:
        say(f"[FAIL] {tag_problem}")
        return 1
    report_problem = release_report_problem(version)
    if report_problem:
        say(f"[FAIL] {report_problem}")
        return 1

    expected = parse_checksum(checksum.read_text(encoding="utf-8"), asset_name)
    if expected is None:
        say(f"[FAIL] .sha256 格式或文件名不合法：{checksum.name}")
        return 1

    # 审计 P1-10/P2-18：防止把旧安装包挂到新 tag 下；上传前核对 exe 内嵌
    # ProductVersion 与当前 app_version.dart 一致。
    try:
        product = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "$v=(Get-Item -LiteralPath $env:RELEASE_ASSET).VersionInfo.ProductVersion; Write-Output $v",
            ],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "RELEASE_ASSET": str(asset)},
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        product = ""
    if not product_version_matches(product, version):
        say(f"[FAIL] 安装包 ProductVersion（{product or '未知'}）与当前版本 V{version} 不一致，拒绝发布")
        return 1
    actual = sha256_file(asset)
    if expected != actual:
        say(f"[FAIL] .sha256 与实际文件不一致：{expected} != {actual}")
        return 1
    if not verify_signature(asset, signature):
        say(f"[FAIL] .sig 与安装包不匹配或签名无效：{signature.name}")
        return 1
    say(
        f"[OK] 资产校验通过：{asset_name}"
        f"（{asset.stat().st_size} bytes，sha256 {actual[:16]}…，签名有效）"
    )
    extras: list[Path] = []
    for raw_path in args.extra_asset:
        extra = Path(raw_path).resolve()
        if not extra.is_file():
            say(f"[FAIL] 额外资产不存在：{raw_path}")
            return 1
        if extra.name in {asset.name, checksum.name, signature.name}:
            say(f"[FAIL] 额外资产与安装包资产重名：{extra.name}")
            return 1
        if extra.name in {item.name for item in extras}:
            say(f"[FAIL] 额外资产重复：{extra.name}")
            return 1
        extras.append(extra)
        say(f"[OK] 额外资产：{extra.name}（{extra.stat().st_size} bytes）")

    token = (
        os.environ.get("GITHUB_TOKEN")
        or os.environ.get("GH_TOKEN")
        or system_credential()
    )
    if not token:
        if args.dry_run:
            say("[DRY] 未找到 GitHub 凭据；仅做本地资产校验，不访问远端")
            say(f"[DRY] 将创建/更新 Release {tag} 并上传 {asset_name} + .sha256 + .sig")
            return 0
        say("[FAIL] 未找到 GitHub 凭据（可设置 GITHUB_TOKEN，或先让 git 记住 github.com 凭据）")
        return 1

    status, body = request("GET", f"{API}/repos/{OWNER}/{REPO}/releases/tags/{tag}", token)
    release = body if isinstance(body, dict) else {}
    if status == 404:
        say(f"[..] 远端还没有 {tag}，准备创建")
        notes_path = ROOT / "更新" / f"更新内容_V{version}.md"
        notes = args.notes or (
            notes_path.read_text(encoding="utf-8") if notes_path.exists() else f"V{version}"
        )
        if args.dry_run:
            say(f"[DRY] 将创建 Release {tag} 并上传 {asset_name} + .sha256 + .sig")
            return 0
        status, body = request(
            "POST",
            f"{API}/repos/{OWNER}/{REPO}/releases",
            token,
            {
                "tag_name": tag,
                "name": f"V{version}",
                "body": notes,
                # 审计 P2-18：固定到本次提交，避免 Release 指向默认分支的
                # 非构建提交（AGPL 源码对应性）。
                **({"target_commitish": target_commitish} if target_commitish else {}),
                # P1-9：先建草稿，两个资产都上传成功后才发布。否则 .exe 上传
                # 成功、.sha256 失败会留下“已发布但客户端拒绝更新”的坏 Release。
                "draft": True,
                "prerelease": False,
            },
        )
        if status not in (200, 201) or not isinstance(body, dict):
            say(f"[FAIL] 创建 Release 失败：HTTP {status} {body}")
            return 1
        release = body
        say(f"[OK] 已创建 Release {tag}")
    elif status != 200 or not isinstance(body, dict):
        say(f"[FAIL] 查询 Release 失败：HTTP {status} {body}")
        return 1
    else:
        say(f"[OK] 远端已存在 Release {tag}")

    existing_assets = {
        str(item.get("name")): item
        for item in (release.get("assets", []) or [])
        if item.get("name")
    }
    release_is_draft = bool(release.get("draft"))
    release_target = str(release.get("target_commitish") or "")
    if release_target and target_commitish and release_target != target_commitish:
        say(
            f"[FAIL] 远端 Release 指向 {release_target[:12]}，当前 HEAD 为 "
            f"{target_commitish[:12]}；源码归档与安装包不一致，拒绝续传"
        )
        return 1
    upload_url = str(release.get("upload_url", "")).split("{", 1)[0]
    local_hashes = {
        asset.name: actual,
        checksum.name: sha256_file(checksum),
        signature.name: sha256_file(signature),
    }
    for extra in extras:
        local_hashes[extra.name] = sha256_file(extra)
    for path in (asset, checksum, signature, *extras):
        remote = existing_assets.get(path.name)
        if remote is not None:
            if not release_is_draft:
                say(f"[FAIL] 资产已存在，不做覆盖：{path.name}")
                return 1
            remote_size = remote.get("size")
            remote_digest = str(remote.get("digest") or "").lower()
            local_digest = f"sha256:{local_hashes[path.name]}"
            if remote_size != path.stat().st_size:
                say(
                    f"[FAIL] 草稿资产 {path.name} 大小与本次构建不一致"
                    f"（远端 {remote_size}，本地 {path.stat().st_size}），请删除后重传"
                )
                return 1
            if not remote_digest:
                say(
                    f"[FAIL] 草稿资产 {path.name} 没有远端摘要，无法确认是否同一文件；"
                    "请删除该草稿资产后重传"
                )
                return 1
            if remote_digest != local_digest:
                say(
                    f"[FAIL] 草稿资产 {path.name} 摘要与本次构建不一致；"
                    "重跑 release_check.py 会生成非确定性 exe，请删除草稿资产后重传"
                )
                return 1
            say(f"[OK] 草稿已含 {path.name}（摘要一致），跳过上传")
            continue
        if args.dry_run:
            say(f"[DRY] 将上传 {path.name}")
            continue
        query = urllib.parse.urlencode({"name": path.name})
        status, body = request(
            "POST",
            f"{upload_url}?{query}",
            token,
            raw=path.read_bytes(),
            content_type="application/octet-stream",
        )
        if status not in (200, 201):
            say(f"[FAIL] 上传 {path.name} 失败：HTTP {status} {body}")
            return 1
        say(f"[OK] 已上传 {path.name}")

    if release_is_draft and not args.dry_run:
        status, body = request(
            "PATCH",
            f"{API}/repos/{OWNER}/{REPO}/releases/{release.get('id')}",
            token,
            {"draft": False},
        )
        if status not in (200, 201):
            say(f"[FAIL] 发布 Release 失败（资产已上传，草稿保留）：HTTP {status} {body}")
            return 1
        say("[OK] 已发布 Release（草稿 → 正式）")

    say(f"[DONE] https://github.com/{OWNER}/{REPO}/releases/tag/{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
