#!/usr/bin/env python3
"""Generate dependency-free PNG app icons for the PWA.

Run from the web/ directory: python3 scripts/generate_icons.py
"""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "icons")


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def blend(dst, src, alpha):
    return tuple(int(round(dst[i] * (1 - alpha) + src[i] * alpha)) for i in range(3))


def segment_distance(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def draw(size, path):
    pixels = [[(0, 0, 0) for _ in range(size)] for _ in range(size)]
    s = size / 512.0

    for y in range(size):
        for x in range(size):
            # Diagonal navy gradient with a soft teal glow in the lower right.
            t = (x + y) / (2 * size)
            base = lerp((13, 23, 40), (6, 10, 18), t)
            glow = max(0.0, 1.0 - math.hypot(x - size * 0.78, y - size * 0.82) / (size * 0.75))
            base = blend(base, (14, 116, 144), 0.28 * glow)
            pixels[y][x] = base

    # Faint grid.
    grid = (26, 44, 68)
    for i in range(1, 8):
        pos = int(size * i / 8)
        for x in range(size):
            pixels[pos][x] = blend(pixels[pos][x], grid, 0.35)
        for y in range(size):
            pixels[y][pos] = blend(pixels[y][pos], grid, 0.35)

    # Upward sparkline.
    points = [(70, 360), (150, 300), (230, 318), (310, 214), (390, 236), (450, 132)]
    points = [(x * s, y * s) for x, y in points]
    teal = (45, 212, 191)
    cyan = (56, 189, 248)
    width = max(2.0, 14 * s)
    for i in range(len(points) - 1):
        x1, y1 = points[i]
        x2, y2 = points[i + 1]
        color = lerp(teal, cyan, i / max(1, len(points) - 2))
        minx, maxx = int(min(x1, x2) - width - 2), int(max(x1, x2) + width + 2)
        miny, maxy = int(min(y1, y2) - width - 2), int(max(y1, y2) + width + 2)
        for y in range(max(0, miny), min(size, maxy + 1)):
            for x in range(max(0, minx), min(size, maxx + 1)):
                d = segment_distance(x, y, x1, y1, x2, y2)
                if d <= width:
                    alpha = min(1.0, (width - d) / max(1.0, width * 0.45))
                    pixels[y][x] = blend(pixels[y][x], color, alpha)

    # Nodes at the turning points.
    for i, (x, y) in enumerate(points[1:-1], start=1):
        r = 13 * s
        color = (226, 250, 255)
        for py in range(max(0, int(y - r - 2)), min(size, int(y + r + 3))):
            for px in range(max(0, int(x - r - 2)), min(size, int(x + r + 3))):
                d = math.hypot(px - x, py - y)
                if d <= r:
                    alpha = min(1.0, (r - d) / max(1.0, r * 0.5))
                    pixels[py][px] = blend(pixels[py][px], color, alpha)

    # Arrow head at the end.
    tip = points[-1]
    for angle in (math.radians(150), math.radians(210)):
        length = 46 * s
        ex = tip[0] + length * math.cos(angle)
        ey = tip[1] + length * math.sin(angle)
        for y in range(max(0, int(min(tip[1], ey) - width - 2)), min(size, int(max(tip[1], ey) + width + 3))):
            for x in range(max(0, int(min(tip[0], ex) - width - 2)), min(size, int(max(tip[0], ex) + width + 3))):
                d = segment_distance(x, y, tip[0], tip[1], ex, ey)
                if d <= width:
                    alpha = min(1.0, (width - d) / max(1.0, width * 0.45))
                    pixels[y][x] = blend(pixels[y][x], cyan, alpha)

    # PNG encode.
    raw = b"".join(b"\x00" + bytes(channel for pixel in row for channel in pixel) for row in pixels)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for dimension in (192, 512):
        target = os.path.join(OUT, f"icon-{dimension}.png")
        draw(dimension, target)
        print(f"wrote {target}")
