#!/usr/bin/env python3
"""Draws the placeholder app icon (a gold crown on a blue tile with a hint of
territory pixels). Writes assets/icon/: icon_512.png (store / main),
icon_192.png (legacy launcher), and the Android adaptive icon layers
icon_foreground_432.png + icon_background_432.png. Replace these PNGs with
real art any time (same names and sizes)."""
from PIL import Image, ImageDraw
import os, random

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
GOLD = (250, 214, 64, 255)
EDGE = (60, 38, 6, 255)
BG_TOP = (36, 64, 120)
BG_BOTTOM = (20, 34, 70)


def background(size):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3)) + (255,)
        d.line([(0, y), (size, y)], fill=c)
    # A few territory "pixels" in player colours along the bottom.
    rnd = random.Random(7)
    cell = size // 16
    cols = [(64, 140, 255), (240, 80, 80), (90, 200, 110), (250, 200, 50)]
    for gy in range(11, 16):
        for gx in range(16):
            if rnd.random() < 0.55:
                c = cols[(gx // 4 + gy) % 4]
                d.rectangle([gx * cell, gy * cell, gx * cell + cell - 1, gy * cell + cell - 1], fill=c + (110,))
    return img


def crown(size, scale):
    """Crown polygon centred in a size×size transparent layer."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    s = size * scale
    pts = [(-1.0, 0.65), (-1.0, -0.35), (-0.5, 0.1), (0.0, -0.75), (0.5, 0.1), (1.0, -0.35), (1.0, 0.65)]
    poly = [(c + x * s, c + y * s) for x, y in pts]
    d.polygon(poly, fill=GOLD)
    d.line(poly + [poly[0]], fill=EDGE, width=max(2, int(s * 0.09)), joint="curve")
    for x in (-1.0, 0.0, 1.0):
        y = -0.75 if x == 0.0 else -0.35
        r = s * 0.11
        d.ellipse([c + x * s - r, c + y * s - r, c + x * s + r, c + y * s + r], fill=GOLD, outline=EDGE, width=max(1, int(s * 0.05)))
    for x, col in ((-0.5, (220, 40, 60)), (0.0, (60, 120, 255)), (0.5, (40, 190, 90))):
        r = s * 0.1
        d.ellipse([c + x * s - r, c + 0.38 * s - r, c + x * s + r, c + 0.38 * s + r], fill=col + (255,))
    return img


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


os.makedirs(OUT, exist_ok=True)
full = background(512)
full.alpha_composite(crown(512, 0.34))
rounded(full, 96).save(os.path.join(OUT, "icon_512.png"))
rounded(full, 96).resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "icon_192.png"))
# Adaptive icon: the launcher masks it to a circle/squircle, and only the
# middle ~66% is always visible, so the crown stays small and centred.
background(432).save(os.path.join(OUT, "icon_background_432.png"))
crown(432, 0.22).save(os.path.join(OUT, "icon_foreground_432.png"))
print("icons written to", os.path.abspath(OUT))
