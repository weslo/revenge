"""Draws Revenge's skull (the accepted mock-up's SVG) into RevengeTracker/Media/Skull.tga.

The skull is white with dark eyes and a thin dark outline, so the game can tint it with
SetVertexColor (coral for you, blue for friends, yellow for guildmates) and it stays
readable on nameplates and the map. 64x64, 32-bit TGA, which WoW loads from addon folders.

Usage: python -I tools/make_skull.py   (rewrites the file; the output is deterministic)
"""

from __future__ import annotations

import math
import struct
from pathlib import Path

SIZE = 64          # pixels
VIEW = 16.0        # the SVG's viewBox is 0 0 16 16
SAMPLES = 4        # supersampling per axis
OUTLINE = 0.45     # outline width, in viewBox units
EYES = [(5.8, 7.0, 1.3), (10.2, 7.0, 1.3)]
EYE_SHADE = 0.13   # eyes are near-black (#222a31 in the mock-up)
OUT = Path(__file__).resolve().parent.parent / "RevengeTracker" / "Media" / "Skull.tga"


def skull_outline() -> list[tuple[float, float]]:
    """The mock-up's path 'M8 1.5c-3.3 0-5.5 2.3-5.5 5.2 ... z' as a polygon."""
    points = [(8.0, 1.5)]

    def cubic(c1, c2, end, steps=24):
        x0, y0 = points[-1]
        p1 = (x0 + c1[0], y0 + c1[1])
        p2 = (x0 + c2[0], y0 + c2[1])
        p3 = (x0 + end[0], y0 + end[1])
        for i in range(1, steps + 1):
            t = i / steps
            u = 1 - t
            points.append((
                u**3 * x0 + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                u**3 * y0 + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
            ))

    def rel(dx, dy):
        x, y = points[-1]
        points.append((x + dx, y + dy))

    cubic((-3.3, 0), (-5.5, 2.3), (-5.5, 5.2))
    cubic((0, 1.8), (0.9, 3.1), (2, 3.9))
    for dx, dy in [(0, 2.4), (1.8, 0), (0, -1.5), (1.4, 0), (0, 1.5), (1.6, 0), (0, -1.5),
                   (1.4, 0), (0, 1.5), (1.8, 0), (0, -2.4)]:
        rel(dx, dy)
    cubic((1.1, -0.8), (2, -2.1), (2, -3.9))
    cubic((0, -2.9), (-2.2, -5.2), (-5.5, -5.2))
    return points


def inside(poly, x, y) -> bool:
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def edge_distance(poly, x, y) -> float:
    best = math.inf
    for i in range(len(poly)):
        ax, ay = poly[i - 1]
        bx, by = poly[i]
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        t = 0.0 if length == 0 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / length))
        best = min(best, math.hypot(x - (ax + t * dx), y - (ay + t * dy)))
    return best


def render() -> bytes:
    poly = skull_outline()
    pixels = bytearray()
    for row in range(SIZE):
        for col in range(SIZE):
            shade_sum = alpha_sum = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (col + (sx + 0.5) / SAMPLES) * VIEW / SIZE
                    y = (row + (sy + 0.5) / SAMPLES) * VIEW / SIZE
                    if inside(poly, x, y):
                        eye = any(math.hypot(x - ex, y - ey) <= r for ex, ey, r in EYES)
                        shade_sum += EYE_SHADE if eye else 1.0
                        alpha_sum += 1.0
                    elif edge_distance(poly, x, y) <= OUTLINE:
                        shade_sum += 0.0     # outline: black
                        alpha_sum += 0.85
            n = SAMPLES * SAMPLES
            alpha = alpha_sum / n
            shade = shade_sum / alpha_sum if alpha_sum else 0.0
            value = round(255 * shade)
            pixels += bytes((value, value, value, round(255 * alpha)))  # BGRA
    return bytes(pixels)


def main() -> None:
    # Uncompressed true-colour TGA, 32 bits, 8 alpha bits, origin top-left.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(header + render())
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
