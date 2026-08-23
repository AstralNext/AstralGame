"""Regenerate anti-aliased logo.png and multi-size Windows ICO via SDF.

Windows Explorer often shows the 48–256 frames; AA width is expressed in
**screen pixels** (then converted to canvas units) so edges stay soft at every
size. Rounded-corner alpha matches the general Astral Windows ICO (~23/256).
"""

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
# Match general Astral windows/runner/resources/app_icon.ico (~23px @ 256).
CORNER_RADIUS_FRAC = 23.0 / 256.0
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


def sdf_rounded_rect(
    x: np.ndarray, y: np.ndarray, size: float, radius: float
) -> np.ndarray:
    """SDF of axis-aligned rounded square covering [0, size)²."""
    half = size * 0.5
    r = min(radius, half - 1e-3)
    qx = np.abs(x - half) - (half - r)
    qy = np.abs(y - half) - (half - r)
    outside = np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0))
    inside = np.minimum(np.maximum(qx, qy), 0.0)
    return outside + inside - r


def mark_sdf(xx: np.ndarray, yy: np.ndarray) -> np.ndarray:
    sdf = np.full(xx.shape, 1e6, dtype=np.float32)
    for cx, cy, r in CIRCLES:
        sdf = np.minimum(sdf, sdf_circle(xx, yy, cx, cy, r))
    for i, j, br in BARS:
        ax, ay, _ = CIRCLES[i]
        bx, by, _ = CIRCLES[j]
        sdf = np.minimum(sdf, sdf_capsule(xx, yy, ax, ay, bx, by, br))
    return sdf


def coverage_from_sdf(sdf: np.ndarray, aa_canvas: float) -> np.ndarray:
    return np.clip(0.5 - sdf / aa_canvas, 0.0, 1.0)


def aa_canvas_for(size: int) -> float:
    """AA soft-edge width in canvas units ≈ target screen pixels."""
    # Black-on-white marks need a slightly wider ramp than light-on-color icons
    # or Explorer shows staircase edges, especially at 48–128.
    if size <= 16:
        px = 2.1
    elif size <= 24:
        px = 1.9
    elif size <= 48:
        px = 1.7
    elif size <= 128:
        px = 1.55
    else:
        px = 1.4
    return px * (CANVAS / size)


def supersample_factor(size: int) -> int:
    if size <= 32:
        return 8
    if size <= 64:
        return 4
    if size <= 128:
        return 2
    return 1


def render_mark_cover(size: int) -> np.ndarray:
    """Coverage of the white mark in [0, 1], supersampled then box-downsampled."""
    factor = supersample_factor(size)
    hi = size * factor
    scale = hi / CANVAS
    yy, xx = np.mgrid[0:hi, 0:hi].astype(np.float32)
    xx = (xx + 0.5) / scale
    yy = (yy + 0.5) / scale
    # AA width is in canvas units for the *final* size. Rendering at `hi` uses the
    # same canvas space, so do NOT divide by factor — box-downsampling then yields
    # ≈ aa_canvas_for(size) screen pixels of soft edge.
    cover = coverage_from_sdf(mark_sdf(xx, yy), aa_canvas_for(size))
    if factor == 1:
        return cover.astype(np.float32)
    reshaped = cover.reshape(size, factor, size, factor)
    return reshaped.mean(axis=(1, 3)).astype(np.float32)


def render_corner_alpha(size: int) -> np.ndarray:
    """Soft alpha mask for rounded square (1 = opaque interior)."""
    radius = CORNER_RADIUS_FRAC * size
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    xx = xx + 0.5
    yy = yy + 0.5
    sdf = sdf_rounded_rect(xx, yy, float(size), radius)
    # ~1 px AA on the corner silhouette.
    return coverage_from_sdf(sdf, 1.15).astype(np.float32)


def render(size: int, *, rounded: bool) -> Image.Image:
    cover = render_mark_cover(size)
    # White mark on black: gray = coverage. Soft edge = intermediate gray.
    gray = np.clip(cover * 255.0 + 0.5, 0, 255).astype(np.uint8)
    if rounded:
        alpha = np.clip(render_corner_alpha(size) * 255.0 + 0.5, 0, 255).astype(
            np.uint8
        )
        # Outside the rounded rect keep RGB black so premultiplied-ish scaling
        # in Explorer does not fringe white into transparent corners.
        mask = alpha.astype(np.float32) / 255.0
        gray = np.clip(gray.astype(np.float32) * mask + 0.5, 0, 255).astype(np.uint8)
    else:
        alpha = np.full((size, size), 255, dtype=np.uint8)
    return Image.fromarray(np.stack([gray, gray, gray, alpha], axis=-1))


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
        frame = render(size, rounded=True)
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
    # Square logo asset (launcher / in-app); ICO gets rounded corners for desktop.
    logo = render(512, rounded=False)
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
