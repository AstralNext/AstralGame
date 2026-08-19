"""Regenerate anti-aliased logo.png and multi-size Windows ICO via SDF."""

from __future__ import annotations

import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO_OUT = ROOT / "assets" / "logo.png"
ICO_ASSETS = ROOT / "assets" / "icon.ico"
ICO_WIN = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

# Fitted to the Astral mark on a 512 canvas (pixel centers).
CIRCLES = (
    (245.0, 175.0, 96.0),
    (343.0, 327.0, 62.0),
    (163.0, 386.0, 42.5),
)
BARS = (
    (0, 1, 16.0),
    (1, 2, 13.5),
)
CANVAS = 512.0
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)


def sdf_circle(x: np.ndarray, y: np.ndarray, cx: float, cy: float, r: float) -> np.ndarray:
    return np.hypot(x - cx, y - cy) - r


def sdf_capsule(
    x: np.ndarray, y: np.ndarray, ax: float, ay: float, bx: float, by: float, r: float
) -> np.ndarray:
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = np.clip(((x - ax) * dx + (y - ay) * dy) / length2, 0.0, 1.0)
    return np.hypot(x - (ax + t * dx), y - (ay + t * dy)) - r


def coverage(size: int, aa: float) -> np.ndarray:
    scale = size / CANVAS
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    xx = (xx + 0.5) / scale
    yy = (yy + 0.5) / scale
    sdf = np.full((size, size), 1e6, dtype=np.float32)
    for cx, cy, r in CIRCLES:
        sdf = np.minimum(sdf, sdf_circle(xx, yy, cx, cy, r))
    for i, j, br in BARS:
        ax, ay, _ = CIRCLES[i]
        bx, by, _ = CIRCLES[j]
        sdf = np.minimum(sdf, sdf_capsule(xx, yy, ax, ay, bx, by, br))
    return np.clip(0.5 - sdf / aa, 0.0, 1.0)


def aa_for(size: int) -> float:
    # Wider coverage on large black/white icons; tighter on 16–24 so they stay crisp.
    if size <= 24:
        return 1.05
    if size <= 48:
        return 1.25
    if size <= 128:
        return 1.45
    return 1.65


def to_rgba(cover: np.ndarray) -> Image.Image:
    gray = np.clip(cover * 255.0 + 0.5, 0, 255).astype(np.uint8)
    alpha = np.full_like(gray, 255)
    return Image.fromarray(np.stack([gray, gray, gray, alpha], axis=-1))


def render(size: int) -> Image.Image:
    return to_rgba(coverage(size, aa_for(size)))


def _dib_bytes(im: Image.Image) -> bytes:
    """32-bit ICO DIB: BITMAPINFOHEADER + bottom-up BGRA + 1-bit AND mask."""
    rgba = np.array(im.convert("RGBA"))
    h, w = rgba.shape[:2]
    bgra = rgba[::-1, :, [2, 1, 0, 3]].tobytes()
    and_row = ((w + 31) // 32) * 4
    and_mask = bytes(and_row * h)
    header = struct.pack(
        "<IiiHHIIiiII",
        40,
        w,
        h * 2,
        1,
        32,
        0,
        len(bgra) + len(and_mask),
        0,
        0,
        0,
        0,
    )
    return header + bgra + and_mask


def save_ico(path: Path) -> None:
    # 32-bit BMP DIB for every size so Windows GDI/Explorer can pick 16–256 natively.
    encoded: list[tuple[int, bytes]] = []
    for size in ICO_SIZES:
        frame = render(size)
        blob = _dib_bytes(frame)
        encoded.append((size, blob))
    count = len(encoded)
    offset = 6 + 16 * count
    out = bytearray(struct.pack("<HHH", 0, 1, count))
    for size, blob in encoded:
        dim = 0 if size == 256 else size
        out += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    for _, blob in encoded:
        out += blob
    path.write_bytes(out)


def main() -> None:
    logo = render(512)
    LOGO_OUT.parent.mkdir(parents=True, exist_ok=True)
    logo.save(LOGO_OUT, format="PNG", optimize=True)
    save_ico(ICO_ASSETS)
    ICO_WIN.parent.mkdir(parents=True, exist_ok=True)
    save_ico(ICO_WIN)
    print(f"wrote {LOGO_OUT}")
    print(f"wrote {ICO_ASSETS}")
    print(f"wrote {ICO_WIN}")


if __name__ == "__main__":
    main()
