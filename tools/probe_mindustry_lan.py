"""Probe Mindustry LAN discovery the same way Astral udp_probe does."""
from __future__ import annotations

import socket
import struct
import subprocess
import time

PROBE = bytes([0xFE, 0x01])  # DiscoverHost [-2, 1]


def try_parse(data: bytes) -> dict:
    """Parse NetworkIO.writeServerData()."""
    o = 0

    def rb() -> int:
        nonlocal o
        if o >= len(data):
            raise EOFError("eof")
        b = data[o]
        o += 1
        return b

    def rs(maxlen: int = 32) -> str:
        nonlocal o
        n = rb()
        if n > maxlen or o + n > len(data):
            raise ValueError(f"bad str len={n}")
        s = data[o : o + n].decode("utf-8", "replace")
        o += n
        return s

    def ri32() -> int:
        nonlocal o
        v = struct.unpack_from(">i", data, o)[0]
        o += 4
        return v

    def ri16() -> int:
        nonlocal o
        v = struct.unpack_from(">h", data, o)[0]
        o += 2
        return v

    try:
        name = rs(100)
        mapa = rs(64)
        players = ri32()
        wave = ri32()
        build = ri32()
        vertype = rs()
        mode = rb()
        limit = ri32()
        desc = rs(100)
        mode_name = rs(50)
        port = ri16()
        if port == 0:
            port = 6567
        return {
            "ok": True,
            "name": name,
            "map": mapa,
            "players": players,
            "wave": wave,
            "build": build,
            "vertype": vertype,
            "mode": mode,
            "limit": limit,
            "desc": desc,
            "modeName": mode_name,
            "port": port,
            "consumed": o,
            "total": len(data),
        }
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
            "hex": data[:80].hex(),
            "len": len(data),
        }


def probe(addr: str, port: int, timeout: float = 1.2) -> list:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.25)
    sock.bind(("0.0.0.0", 0))
    local = sock.getsockname()
    hits = []
    try:
        sock.sendto(PROBE, (addr, port))
        print(f">> sent fe01 to {addr}:{port} from {local}")
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                data, src = sock.recvfrom(2048)
            except socket.timeout:
                continue
            parsed = try_parse(data)
            hits.append((src, data, parsed))
            print(f"<< from {src[0]}:{src[1]} bytes={len(data)}")
            print("   ", parsed)
        if not hits:
            print(f"!! no reply from {addr}:{port}")
    finally:
        sock.close()
    return hits


def main() -> None:
    print("=== netstat :6567 / :20151 ===")
    r = subprocess.run(
        ["netstat", "-ano"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    found = False
    for line in r.stdout.splitlines():
        if ":6567" in line or ":20151" in line:
            print(line)
            found = True
    if not found:
        print("(no listeners matched)")

    print("\n=== loopback 127.0.0.1:6567 ===")
    h1 = probe("127.0.0.1", 6567)
    print("\n=== broadcast 255.255.255.255:6567 ===")
    h2 = probe("255.255.255.255", 6567)
    print("\n=== multicast 227.2.7.7:20151 ===")
    h3 = probe("227.2.7.7", 20151, timeout=1.5)

    ok = any(
        p.get("ok") for _, _, p in (h1 + h2 + h3)
    )
    print("\n=== summary ===")
    print("DISCOVERY_OK" if ok else "DISCOVERY_FAIL")


if __name__ == "__main__":
    main()
