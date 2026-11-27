"""Draws Revenge's logo for its CurseForge listing into docs/curseforge/logo.png.

The skull is the same shape as the addon's own (tools/make_skull.py, from the accepted
mock-up), coral (#ff8c6e, the colour for your own deaths) with dark eyes, on a dark square.
400x400 PNG, the size CurseForge's moderation policy asks for, written with the standard
library only. The output is deterministic.

Usage: python -I tools/make_logo.py
"""

from __future__ import annotations

import bisect
import importlib.util
import math
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "docs" / "curseforge" / "logo.png"
SIZE = 400                        # CurseForge: "All avatars need to be 400x400 pixels"
SAMPLES = 3                       # supersampling per axis
SKULL_HEIGHT = 0.70               # of the image
CORAL = (255, 140, 110)
EYE = (22, 18, 17)
BG_CENTRE = (46, 38, 36)
BG_EDGE = (17, 14, 13)


def _skull_module():
    spec = importlib.util.spec_from_file_location("make_skull", HERE / "make_skull.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render() -> list[bytes]:
    skull = _skull_module()
    poly = skull.skull_outline()
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    scale = SIZE * SKULL_HEIGHT / (max(ys) - min(ys))
    # Centre the skull's bounding box in the image.
    off_x = SIZE / 2 - (min(xs) + max(xs)) / 2 * scale
    off_y = SIZE / 2 - (min(ys) + max(ys)) / 2 * scale
    edges = [(poly[i - 1], poly[i]) for i in range(len(poly))]
    eyes = [(ex * scale + off_x, ey * scale + off_y, r * scale) for ex, ey, r in skull.EYES]
    rows = []
    for row in range(SIZE):
        # Where each sample row crosses the outline (even-odd), in image pixels.
        crossings = []
        for s in range(SAMPLES):
            y = row + (s + 0.5) / SAMPLES
            vy = (y - off_y) / scale
            xs_row = []
            for (ax, ay), (bx, by) in edges:
                if (ay > vy) != (by > vy):
                    xs_row.append(((bx - ax) * (vy - ay) / (by - ay) + ax) * scale + off_x)
            crossings.append((y, sorted(xs_row)))
        line = bytearray([0])     # PNG filter: none
        for col in range(SIZE):
            cx, cy = col + 0.5 - SIZE / 2, row + 0.5 - SIZE / 2
            background = _mix(BG_CENTRE, BG_EDGE, min(1.0, math.hypot(cx, cy) / (SIZE * 0.72)))
            total = [0, 0, 0]
            for y, xs_row in crossings:
                for s in range(SAMPLES):
                    x = col + (s + 0.5) / SAMPLES
                    if bisect.bisect_right(xs_row, x) % 2:
                        eye = any(math.hypot(x - ex, y - ey) <= r for ex, ey, r in eyes)
                        colour = EYE if eye else CORAL
                    else:
                        colour = background
                    for i in range(3):
                        total[i] += colour[i]
            n = SAMPLES * SAMPLES
            line += bytes((round(total[0] / n), round(total[1] / n), round(total[2] / n), 255))
        rows.append(bytes(line))
    return rows


def png(rows: list[bytes]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)   # 8-bit RGBA
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png(render()))
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
