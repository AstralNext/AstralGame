#!/usr/bin/env python3
"""Quark Drive Open API client for Astral Game releases.

Talks to https://open-api-drive.quark.cn directly (no CLI / agent runtime).
Auth comes from GitHub Secrets: QUARK_DRIVE_CONFIG_JSON or token fields.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import mimetypes
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

API = "https://open-api-drive.quark.cn"
CLIENT_ID = os.environ.get("QUARK_CLIENT_ID", "third_party_agent")
SIGN_KEY = os.environ.get("QUARK_SIGN_KEY", "cf134812e2de4032bd1cb7c3727e84b3")


class Sha1:
    """Incremental SHA1 with exportable intermediate state (matches Quark hash-worker)."""

    def __init__(self) -> None:
        self.h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        self._buf = bytearray()
        self._n = 0

    def update(self, data: bytes) -> None:
        self._n += len(data)
        buf = self._buf + data
        off = 0
        while off + 64 <= len(buf):
            self._block(buf[off : off + 64])
            off += 64
        self._buf = bytearray(buf[off:])

    def _block(self, chunk: bytes) -> None:
        w = [0] * 80
        for i in range(16):
            w[i] = int.from_bytes(chunk[i * 4 : i * 4 + 4], "big")
        for i in range(16, 80):
            v = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
            w[i] = ((v << 1) | (v >> 31)) & 0xFFFFFFFF
        a, b, c, d, e = self.h
        for i in range(80):
            if i < 20:
                f = (b & c) | ((~b) & d)
                k = 0x5A827999
            elif i < 40:
                f = b ^ c ^ d
                k = 0x6ED9EBA1
            elif i < 60:
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            else:
                f = b ^ c ^ d
                k = 0xCA62C1D6
            temp = (((a << 5) | (a >> 27)) + f + e + k + w[i]) & 0xFFFFFFFF
            e, d, c, b, a = d, c, ((b << 30) | (b >> 2)) & 0xFFFFFFFF, a, temp
        self.h = [
            (self.h[0] + a) & 0xFFFFFFFF,
            (self.h[1] + b) & 0xFFFFFFFF,
            (self.h[2] + c) & 0xFFFFFFFF,
            (self.h[3] + d) & 0xFFFFFFFF,
            (self.h[4] + e) & 0xFFFFFFFF,
        ]

    def state(self) -> list[int]:
        return list(self.h)

    def hexdigest(self) -> str:
        n = self._n * 8
        buf = bytearray(self._buf)
        buf.append(0x80)
        if len(buf) > 56:
            buf.extend(b"\x00" * (64 - len(buf)))
            self._block(bytes(buf))
            buf = bytearray()
        buf.extend(b"\x00" * (56 - len(buf)))
        buf.extend((n >> 32).to_bytes(4, "big"))
        buf.extend((n & 0xFFFFFFFF).to_bytes(4, "big"))
        clone = Sha1()
        clone.h = list(self.h)
        clone._block(bytes(buf))
        return "".join(f"{x:08x}" for x in clone.h)


def _md5_hex(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def _sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


_CONFIG_PATH = Path(
    os.environ.get(
        "QUARK_CONFIG_PATH",
        str(Path.home() / ".cursor" / "skills" / "quarkclouddrive" / "openclaw" / "config.json"),
    )
)
_RAW_CONFIG: dict[str, Any] | None = None


def _load_config() -> dict[str, Any]:
    global _RAW_CONFIG
    agent_code = os.environ.get("QUARK_AGENT_AUTH_CODE", "").strip()
    raw = os.environ.get("QUARK_DRIVE_CONFIG_JSON", "").strip()
    cfg: dict[str, Any] | None = None
    if raw:
        try:
            cfg = json.loads(raw)
        except json.JSONDecodeError as exc:
            if not agent_code:
                raise SystemExit(f"QUARK_DRIVE_CONFIG_JSON invalid JSON: {exc}") from exc
            cfg = None
    if cfg is None and _CONFIG_PATH.is_file() and not os.environ.get("QUARK_ACCESS_TOKEN"):
        try:
            cfg = json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            cfg = None
    if cfg is None and os.environ.get("QUARK_ACCESS_TOKEN") and os.environ.get("QUARK_USER_ID"):
        uid = os.environ["QUARK_USER_ID"]
        cfg = {
            "deviceId": os.environ.get("QUARK_DEVICE_ID") or "github-actions-astral-game",
            "platform": os.environ.get("QUARK_PLATFORM") or "Linux",
            "currentUserId": uid,
            uid: {
                "accessToken": os.environ["QUARK_ACCESS_TOKEN"],
                "refreshToken": os.environ.get("QUARK_REFRESH_TOKEN", ""),
                "userId": uid,
            },
        }
    if cfg is None:
        # Bootstrap minimal config purely from QUARK_AGENT_AUTH_CODE.
        # Access token / user id are dummies and will be replaced after code exchange.
        if not agent_code:
            raise SystemExit(
                "missing Quark auth: set QUARK_DRIVE_CONFIG_JSON, or QUARK_ACCESS_TOKEN+QUARK_USER_ID, "
                "or QUARK_AGENT_AUTH_CODE"
            )
        cfg = {
            "deviceId": os.environ.get("QUARK_DEVICE_ID") or "github-actions-astral-game",
            "platform": os.environ.get("QUARK_PLATFORM") or "Linux",
            "currentUserId": "",
        }

    uid = str(cfg.get("currentUserId") or "")
    account = cfg.get(uid) if uid else None
    if not isinstance(account, dict):
        for key, val in cfg.items():
            if isinstance(val, dict) and val.get("accessToken"):
                uid = str(val.get("userId") or key)
                account = val
                break
    has_token = isinstance(account, dict) and bool(account.get("accessToken"))
    if not has_token and not agent_code:
        raise SystemExit("quark config has no accessToken and QUARK_AGENT_AUTH_CODE not set")
    _RAW_CONFIG = cfg
    return {
        "user_id": str(account.get("userId") or uid) if account else uid,
        "device_id": str(cfg.get("deviceId") or "github-actions-astral-game"),
        "platform": str(cfg.get("platform") or "Linux"),
        "access_token": str(account["accessToken"]) if has_token else "",
        "refresh_token": str(account.get("refreshToken") or "") if account else "",
    }


def _persist_tokens(user_id: str, access: str, refresh: str) -> None:
    cfg = _RAW_CONFIG
    if not isinstance(cfg, dict):
        return
    account = cfg.get(user_id)
    if not isinstance(account, dict):
        account = {}
        cfg[user_id] = account
    account["accessToken"] = access
    if refresh:
        account["refreshToken"] = refresh
    account["userId"] = user_id
    account["update_time"] = int(time.time() * 1000)
    cfg["currentUserId"] = user_id
    if _CONFIG_PATH.parent.is_dir():
        _CONFIG_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"token saved to {_CONFIG_PATH}", flush=True)


class QuarkDrive:
    def __init__(self, cfg: dict[str, str]) -> None:
        self.cfg = cfg
        self.access_token = cfg["access_token"]

    def _headers(self, method: str, path: str) -> dict[str, str]:
        ts = str(int(time.time() * 1000))
        token = _sha256_hex(f"{method.upper()}&{path}&{ts}&{SIGN_KEY}")
        return {
            "x-pan-client-id": CLIENT_ID,
            "x-pan-tm": ts,
            "x-pan-token": token,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "astral-game-quark-release/1.0",
        }

    def _url(self, path: str, extra: dict[str, str] | None = None) -> str:
        params = {
            "req_id": str(uuid.uuid4()),
            "access_token": self.access_token,
            "device_id": self.cfg["device_id"],
            "platform": self.cfg["platform"],
        }
        if extra:
            params.update(extra)
        q = "&".join(f"{k}={_quote(v)}" for k, v in params.items() if v != "")
        return f"{API}{path}?{q}"

    def _request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        extra_query: dict[str, str] | None = None,
        timeout: int = 120,
    ) -> dict[str, Any]:
        headers = self._headers(method, path)
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        req = Request(self._url(path, extra_query), data=data, method=method, headers=headers)
        try:
            with urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8")
        except HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            raise SystemExit(f"HTTP {exc.code} {path}: {raw[:500]}") from exc
        except URLError as exc:
            raise SystemExit(f"network error {path}: {exc}") from exc
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid json from {path}: {raw[:300]}") from exc
        return payload

    def _ok(self, payload: dict[str, Any], what: str) -> dict[str, Any]:
        if int(payload.get("status", -1)) != 0 or payload.get("data") is None:
            raise SystemExit(
                f"{what} failed: errno={payload.get('errno')} "
                f"{payload.get('agent_msg') or payload.get('error_info') or payload}"
            )
        return payload["data"]

    def rotate(self) -> bool:
        """Try to refresh access_token via refresh_token. Returns True on success."""
        refresh = self.cfg.get("refresh_token") or ""
        if not refresh:
            print("token rotate skipped: no refresh_token", flush=True)
            return False
        path = "/agent/v1/oauth/access_token/rotate"
        try:
            payload = self._request(
                "POST",
                path,
                {"refresh_token": refresh, "device_id": self.cfg["device_id"]},
            )
        except SystemExit as exc:
            print(f"token rotate request failed: {exc}", flush=True)
            return False
        data = payload.get("data") or {}
        access = data.get("access_token") or data.get("accessToken")
        if payload.get("status") == 0 and access:
            self.access_token = str(access)
            new_refresh = data.get("refresh_token") or data.get("refreshToken")
            if new_refresh:
                self.cfg["refresh_token"] = str(new_refresh)
            new_uid = str(data.get("user_id") or data.get("userId") or self.cfg.get("user_id") or "")
            if new_uid:
                self.cfg["user_id"] = new_uid
            _persist_tokens(self.cfg["user_id"], self.access_token, self.cfg.get("refresh_token") or "")
            print("token rotated", flush=True)
            return True
        print(
            f"token rotate failed: status={payload.get('status')} errno={payload.get('errno')} "
            f"{payload.get('agent_msg') or payload.get('error_info') or ''}",
            flush=True,
        )
        return False

    def login_by_agent_auth_code(self, code: str) -> bool:
        """Exchange a CAC-style agent auth code for HTTP Open API access+refresh tokens."""
        if not code:
            return False
        code = code.strip()
        print(f"==> exchanging QUARK_AGENT_AUTH_CODE ({len(code)} chars) for HTTP token", flush=True)
        path = "/agent/v1/oauth/access_token"
        body: dict[str, Any] = {
            "client_id": CLIENT_ID,
            "grant_type": "authorization_code",
            "code": code,
            "device_id": self.cfg["device_id"],
            "platform": self.cfg["platform"],
        }
        try:
            payload = self._request("POST", path, body)
        except SystemExit as exc:
            print(f"CAC code exchange failed: {exc}", flush=True)
            return False
        status = payload.get("status")
        if status is None:
            # Some OAuth implementations return tokens directly without a status envelope.
            status = 0 if (payload.get("access_token") or payload.get("accessToken")) else payload.get("code", -1)
        data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
        access = data.get("access_token") or data.get("accessToken") or payload.get("access_token") or payload.get("accessToken")
        refresh = data.get("refresh_token") or data.get("refreshToken") or payload.get("refresh_token") or payload.get("refreshToken")
        uid = (
            data.get("user_id")
            or data.get("userId")
            or data.get("uid")
            or payload.get("user_id")
            or payload.get("userId")
            or payload.get("uid")
            or self.cfg.get("user_id")
            or ""
        )
        if int(status or -1) != 0 or not access:
            print(
                f"CAC code exchange rejected: status={status} errno={payload.get('errno')} "
                f"{payload.get('agent_msg') or payload.get('error_info') or payload.get('msg') or payload}",
                flush=True,
            )
            return False
        self.access_token = str(access)
        self.cfg["access_token"] = self.access_token
        if refresh:
            self.cfg["refresh_token"] = str(refresh)
        if uid:
            self.cfg["user_id"] = str(uid)
        _persist_tokens(self.cfg["user_id"] or "", self.access_token, self.cfg.get("refresh_token") or "")
        print(
            f"CAC login ok user_id={self.cfg.get('user_id') or uid or '?'} access_len={len(self.access_token)}",
            flush=True,
        )
        return True

    def user_info(self) -> dict[str, Any]:
        payload = self._request(
            "GET",
            "/open/v1/user/info",
            extra_query={"access_token": self.access_token},
        )
        return self._ok(payload, "user info")

    def _looks_like_auth_error(self, exc: SystemExit) -> bool:
        msg = str(exc).lower()
        return (
            "未授权" in msg
            or "token" in msg
            or "auth" in msg
            or "11001" in msg
            or "1408" in msg
            or "未登录" in msg
        )

    def ensure_auth(self) -> None:
        # 1) Fast path: existing token still works.
        fast_err: SystemExit | None = None
        if self.access_token:
            try:
                self.user_info()
                return
            except SystemExit as exc:
                if not self._looks_like_auth_error(exc):
                    raise
                fast_err = exc
                print(f"access token stale/invalid: {exc}", flush=True)

        # 2) Try refresh_token rotate.
        if self.rotate():
            try:
                self.user_info()
                return
            except SystemExit as exc:
                if not self._looks_like_auth_error(exc):
                    raise
                print(f"rotated token still invalid: {exc}", flush=True)

        # 3) Try CAC agent auth code exchange (new bootstrap path).
        agent_code = os.environ.get("QUARK_AGENT_AUTH_CODE", "").strip()
        if agent_code and self.login_by_agent_auth_code(agent_code):
            try:
                self.user_info()
                return
            except SystemExit as exc:
                if not self._looks_like_auth_error(exc):
                    raise
                print(f"token from CAC code still invalid: {exc}", flush=True)

        # All paths exhausted.
        hint = ""
        if not agent_code:
            hint = " (set QUARK_AGENT_AUTH_CODE with a fresh CAC code to bootstrap)"
        msg = f"quark authentication failed, all strategies exhausted{hint}"
        if fast_err is not None:
            msg += f"; first error: {fast_err}"
        raise SystemExit(msg)

    def create_dir(self, name: str, parent_fid: str = "0") -> str:
        payload = self._request(
            "POST",
            "/open/v1/dir",
            {"dir_path": name, "pdir_fid": parent_fid},
        )
        data = self._ok(payload, f"create dir {name}")
        fid = str(data.get("fid") or "")
        if not fid:
            raise SystemExit(f"create dir {name}: empty fid")
        return fid

    def _proof(self, path: Path, size: int, x_pan_token: str) -> dict[str, str]:
        seed1 = _md5_hex(_md5_hex(f"{self.cfg['user_id']}{x_pan_token}".encode()).encode())
        seed2 = _md5_hex(_md5_hex(str(size).encode()).encode())

        def code_of(seed: str) -> str:
            if size <= 0:
                return ""
            start = int(seed[:16], 16) % size
            end = min(start + 8, size)
            if start == end:
                return ""
            with path.open("rb") as f:
                f.seek(start)
                chunk = f.read(end - start)
            import base64

            return base64.b64encode(chunk).decode("ascii")

        return {
            "proof_version": "v1",
            "proof_seed1": seed1,
            "proof_seed2": seed2,
            "proof_code1": code_of(seed1),
            "proof_code2": code_of(seed2),
        }

    def upload_file(self, path: Path, parent_fid: str) -> str:
        size = path.stat().st_size
        sha1 = Sha1()
        md5 = hashlib.md5()
        with path.open("rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    break
                sha1.update(chunk)
                md5.update(chunk)
        sha1_hex = sha1.hexdigest()
        md5_hex = md5.hexdigest()
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        pre_headers = self._headers("POST", "/open/v1/file/upload_pre")
        body: dict[str, Any] = {
            "file_name": path.name,
            "size": size,
            "sha1": sha1_hex,
            "md5": md5_hex,
            "pdir_fid": parent_fid,
            "format_type": mime,
            "parallel_upload": True,
            "hash_update": False,
            "same_path_file_reuse": True,
            "device_id": self.cfg["device_id"],
            "device_name": "Astral Game CI",
        }
        if self.cfg.get("user_id"):
            body.update(self._proof(path, size, pre_headers["x-pan-token"]))
        req = Request(
            self._url("/open/v1/file/upload_pre"),
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers=pre_headers,
        )
        try:
            with urlopen(req, timeout=120) as resp:
                pre = json.loads(resp.read().decode("utf-8"))
        except HTTPError as exc:
            raise SystemExit(
                f"upload_pre {path.name}: HTTP {exc.code} {exc.read().decode('utf-8', errors='replace')[:400]}"
            ) from exc
        data = self._ok(pre, f"upload_pre {path.name}")
        if data.get("finish") and data.get("fid"):
            print(f"  instant {path.name} fid={data['fid']}", flush=True)
            return str(data["fid"])

        task_id = str(data["task_id"])
        part_size = int(data.get("part_size") or size)
        common = dict(data.get("common_headers") or {})
        parts = _parts(size, part_size)
        uploaded: list[dict[str, Any]] = []
        urls = list(data.get("upload_urls") or [])
        if not urls:
            urls = self._get_upload_urls(task_id, parts, sha1_states_for(path, parts))
            common = dict((self._last_url_common or common))
        url_by_no = {int(u.get("part_number") or i + 1): u for i, u in enumerate(urls)}
        missing = [p for p in parts if p["no"] not in url_by_no]
        if missing:
            extra = self._get_upload_urls(task_id, missing, sha1_states_for(path, parts))
            for item in extra:
                url_by_no[int(item["part_number"])] = item
            if self._last_url_common:
                common = dict(self._last_url_common)

        with path.open("rb") as f:
            for part in parts:
                info = url_by_no.get(part["no"])
                if not info:
                    raise SystemExit(f"no upload url for part {part['no']}")
                f.seek(part["start"])
                chunk = f.read(part["end"] - part["start"])
                auth = (
                    (info.get("signature_info") or {}).get("signature")
                    or info.get("authorization")
                    or ""
                )
                etag = _put_oss_chunk(str(info["upload_url"]), chunk, common, str(auth))
                uploaded.append({"part_number": part["no"], "etag": etag})
                print(
                    f"  part {part['no']}/{len(parts)} {path.name} {part['end'] - part['start']}B",
                    flush=True,
                )

        finish = self._request(
            "POST",
            "/open/v1/file/upload_finish",
            {"task_id": task_id, "part_info_list": uploaded},
        )
        data = self._ok(finish, f"upload_finish {path.name}")
        fid = str(data.get("fid") or "")
        if not fid:
            raise SystemExit(f"upload_finish {path.name}: empty fid")
        print(f"  uploaded {path.name} fid={fid}", flush=True)
        return fid

    _last_url_common: dict[str, Any] | None = None

    def _get_upload_urls(
        self,
        task_id: str,
        parts: list[dict[str, int]],
        states: dict[int, dict[str, Any]],
    ) -> list[dict[str, Any]]:
        body_parts: list[dict[str, Any]] = []
        for part in parts:
            item: dict[str, Any] = {
                "part_number": part["no"],
                "part_size": part["end"] - part["start"],
            }
            prev = states.get(part["no"] - 1)
            if prev:
                item["parallel_sha1_ctx"] = {
                    "part_offset": prev["offset"],
                    "h": prev["h"],
                }
            body_parts.append(item)
        payload = self._request(
            "POST",
            "/open/v1/file/get_upload_urls",
            {"task_id": task_id, "part_info_list": body_parts},
        )
        data = self._ok(payload, "get_upload_urls")
        self._last_url_common = dict(data.get("common_headers") or {})
        return list(data.get("upload_urls") or [])

    def share(self, fids: list[str], title: str) -> str:
        payload = self._request(
            "POST",
            "/agent/v1/share/create",
            {
                "fid_list": fids,
                "title": title,
                "url_type": 1,
                "expired_type": 1,
            },
        )
        data = self._ok(payload, "share")
        url = str(data.get("share_url") or "")
        if not url:
            raise SystemExit("share: empty url")
        return url


def _put_oss_chunk(url: str, chunk: bytes, common: dict[str, Any], authorization: str) -> str:
    """PUT one part to OSS. Do not invent Content-Type; signed headers must match exactly."""
    parsed = urlparse(url)
    headers = {str(k): str(v) for k, v in common.items() if v not in (None, "")}
    if authorization:
        headers["Authorization"] = authorization
    headers["Content-Length"] = str(len(chunk))
    conn_cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    host = parsed.hostname or ""
    port = parsed.port
    path = parsed.path + (f"?{parsed.query}" if parsed.query else "")
    conn = conn_cls(host, port, timeout=600)
    try:
        conn.request("PUT", path, body=chunk, headers=headers)
        resp = conn.getresponse()
        body = resp.read()
        if resp.status < 200 or resp.status >= 300:
            raise SystemExit(
                f"PUT chunk HTTP {resp.status}: {body[:400]!r}"
            )
        etag = (resp.getheader("ETag") or resp.getheader("etag") or "").strip().strip('"')
        if not etag:
            raise SystemExit("PUT chunk missing etag")
        return etag
    finally:
        conn.close()


def _quote(value: str) -> str:
    from urllib.parse import quote

    return quote(str(value), safe="")


def _parts(size: int, part_size: int) -> list[dict[str, int]]:
    if part_size <= 0:
        part_size = size or 1
    out: list[dict[str, int]] = []
    start = 0
    no = 1
    while start < size:
        end = min(start + part_size, size)
        out.append({"no": no, "start": start, "end": end})
        start = end
        no += 1
    return out or [{"no": 1, "start": 0, "end": 0}]


def sha1_states_for(path: Path, parts: list[dict[str, int]]) -> dict[int, dict[str, Any]]:
    sha1 = Sha1()
    states: dict[int, dict[str, Any]] = {}
    with path.open("rb") as f:
        for part in parts:
            f.seek(part["start"])
            sha1.update(f.read(part["end"] - part["start"]))
            states[part["no"]] = {"offset": part["end"], "h": sha1.state()}
    return states


def _write_github_output(share_url: str) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if not out or not share_url:
        return
    with open(out, "a", encoding="utf-8") as f:
        f.write(f"share_url={share_url}\n")


def cmd_whoami(_args: argparse.Namespace) -> int:
    client = QuarkDrive(_load_config())
    client.ensure_auth()
    info = client.user_info()
    nickname = info.get("nickname") or info.get("user_name") or info.get("username") or ""
    print(f"ok user_id={client.cfg['user_id']} nickname={nickname}")
    return 0


def cmd_upload(args: argparse.Namespace) -> int:
    version = str(args.version).lstrip("v")
    tag = f"v{version}"
    release_dir = Path(args.dir)
    files = sorted(p for p in release_dir.iterdir() if p.is_file())
    if not files:
        raise SystemExit(f"no files in {release_dir}")

    client = QuarkDrive(_load_config())
    client.ensure_auth()
    parent = (os.environ.get("QUARK_PARENT_FID") or "").strip()
    if not parent:
        parent = client.create_dir("AstralGame", "0")
        print(f"AstralGame fid={parent}", flush=True)
    ver_fid = client.create_dir(tag, parent)
    print(f"{tag} fid={ver_fid}", flush=True)

    fids = [client.upload_file(path, ver_fid) for path in files]
    share_url = ""
    if os.environ.get("QUARK_SHARE", "1") != "0":
        share_url = client.share([ver_fid], f"Astral Game {tag}")
        print(f"QUARK_SHARE_URL={share_url}", flush=True)
        _write_github_output(share_url)

    site_token = os.environ.get("ASTRAL_SITE_TOKEN", "").strip()
    if share_url and site_token:
        root = Path(__file__).resolve().parents[2]
        updater = root / "tools" / "quark_release" / "update_downloads_json.py"
        import subprocess

        subprocess.check_call(
            [
                sys.executable,
                str(updater),
                "--token",
                site_token,
                "--repo",
                os.environ.get("SITE_REPO", "AstralNext/next.astral.github.io"),
                "--path",
                os.environ.get("SITE_DOWNLOADS_PATH", "public/downloads.json"),
                "--version",
                tag,
                "--url",
                share_url,
            ]
        )
    elif share_url:
        print("ASTRAL_SITE_TOKEN not set; skip website downloads.json", flush=True)
    print(f"uploaded {len(fids)} files", flush=True)
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("whoami")
    up = sub.add_parser("upload")
    up.add_argument("version")
    up.add_argument("dir", nargs="?", default="release")
    args = p.parse_args()
    if args.cmd == "whoami":
        return cmd_whoami(args)
    if args.cmd == "upload":
        return cmd_upload(args)
    raise SystemExit(2)


if __name__ == "__main__":
    raise SystemExit(main())
