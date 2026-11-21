#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `release_check.py` 产出的安装包上传到 GitHub Release。

为什么要有它
------------
程序的自动更新只认两样东西：
  1. Release 资产里名字含 `Setup` 的可执行文件；
  2. 与它同名的 `.sha256` 文件（内容为 64 位十六进制哈希，可带文件名）。

手工上传很容易在这两点上出错：传了中文文件名的安装包、忘了传 `.sha256`、
或者哈希内容和文件名对不上，客户端就会更新失败或拒绝更新。

本脚本只做一件事：把已经通过验收的资产按上面的规则上传。它不会构建、不会
打包、不会覆盖已有资产；同名资产已存在时直接报错退出。

用法：
    set GITHUB_TOKEN=...
    python tools/release_publish.py            # 上传当前版本
    python tools/release_publish.py --dry-run  # 只检查资产与远端状态
"""
from __future__ import annotations

import argparse
import json
import os
import re
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


def main() -> int:
    parser = argparse.ArgumentParser(description="上传安装包与校验文件到 GitHub Release")
    parser.add_argument("--dry-run", action="store_true", help="只检查，不实际创建/上传")
    parser.add_argument("--notes", default="", help="Release 说明（默认使用 更新/更新内容_VX.Y.Z.md）")
    args = parser.parse_args()

    version = dart_string("version").lstrip("V")
    tag = f"v{version}"
    release_dir = ROOT / "build" / f"release_v{version}"
    asset_name = f"ClassManagementSystem_Setup_v{version}.exe"
    asset = release_dir / asset_name
    checksum = release_dir / f"{asset_name}.sha256"

    if not asset.exists() or not checksum.exists():
        say(f"[FAIL] 缺少发布资产，请先运行 tools/release_check.py：{release_dir}")
        return 1

    expected = checksum.read_text(encoding="utf-8").strip().split()[0].lower()
    import hashlib

    actual = hashlib.sha256(asset.read_bytes()).hexdigest()
    if expected != actual:
        say(f"[FAIL] .sha256 与实际文件不一致：{expected} != {actual}")
        return 1
    say(f"[OK] 资产校验通过：{asset_name}（{asset.stat().st_size} bytes，sha256 {actual[:16]}…）")

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    if not token:
        if args.dry_run:
            say("[DRY] 未设置 GITHUB_TOKEN；仅做本地资产校验，不访问远端")
            say(f"[DRY] 将创建/更新 Release {tag} 并上传 {asset_name} + .sha256")
            return 0
        say("[FAIL] 未设置 GITHUB_TOKEN（需要该仓库的 Contents: Read and write 权限）")
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
            say(f"[DRY] 将创建 Release {tag} 并上传 {asset_name} + .sha256")
            return 0
        status, body = request(
            "POST",
            f"{API}/repos/{OWNER}/{REPO}/releases",
            token,
            {
                "tag_name": tag,
                "name": f"V{version}",
                "body": notes,
                "draft": False,
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

    existing = {item.get("name") for item in release.get("assets", []) or []}
    upload_url = str(release.get("upload_url", "")).split("{", 1)[0]
    for path in (asset, checksum):
        if path.name in existing:
            say(f"[FAIL] 资产已存在，不做覆盖：{path.name}")
            return 1
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

    say(f"[DONE] https://github.com/{OWNER}/{REPO}/releases/tag/{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
