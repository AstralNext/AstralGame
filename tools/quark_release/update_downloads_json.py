#!/usr/bin/env python3
"""Prepend a Quark share entry to next.astral.github.io public/downloads.json."""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import urllib.error
import urllib.request


def github_api(token: str, method: str, url: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        url,
        data=None if body is None else json.dumps(body).encode("utf-8"),
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "astral-game-quark-release",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GitHub API {method} {url} failed: {exc.code} {detail}") from exc


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--token", required=True)
    p.add_argument("--repo", default="AstralNext/next.astral.github.io")
    p.add_argument("--path", default="public/downloads.json")
    p.add_argument("--version", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--branch", default="main")
    args = p.parse_args()

    version = args.version if args.version.startswith("v") else f"v{args.version}"
    d = dt.date.today()
    today = f"{d.year}年{d.month}月{d.day}日"
    api = f"https://api.github.com/repos/{args.repo}/contents/{args.path}?ref={args.branch}"
    current = github_api(args.token, "GET", api)
    sha = current.get("sha") or ""
    raw = base64.b64decode(current.get("content") or "").decode("utf-8")
    try:
        items = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"downloads.json is not valid JSON: {exc}") from exc
    if not isinstance(items, list):
        raise SystemExit("downloads.json root must be a list")

    entry = {"version": version, "date": today, "url": args.url.strip()}
    items = [x for x in items if not (isinstance(x, dict) and x.get("version") == version)]
    items.insert(0, entry)
    new_raw = json.dumps(items, ensure_ascii=False, indent=2) + "\n"
    if new_raw == raw:
        print("downloads.json unchanged")
        return 0

    put_url = f"https://api.github.com/repos/{args.repo}/contents/{args.path}"
    github_api(
        args.token,
        "PUT",
        put_url,
        {
            "message": f"Add Astral Game {version} Quark download.",
            "content": base64.b64encode(new_raw.encode("utf-8")).decode("ascii"),
            "sha": sha,
            "branch": args.branch,
        },
    )
    print(f"updated {args.repo}/{args.path} -> {version} {args.url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
