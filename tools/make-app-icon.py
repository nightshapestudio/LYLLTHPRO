#!/usr/bin/env python3
"""Builds LYLLTH's macOS app icon from the wordmark's own glyphs.

The mark is the "LL" at the centre of LYLLTH: the NIGHTSHAPE outline L and
the solid L exactly as the wordmark sets them, joined across the top by one
bar at the solid L's stroke weight, so the pair reads as two beamed eighth
notes. Nothing is redrawn by hand; the glyphs come from the bundled fonts.

Fill is the NIGHTSHAPE tie-dye at icon density (4 spots at radius 0.80, the
same density as DRUMKIT's icon; the wordmark's 5 at 0.60 breaks into blobs in
a small square). Teal is composited last or the purples wash over it.

Every size is a Lanczos downsample of the 1024 master, never re-rendered
small. Output: LYLLTH/Assets.xcassets/AppIcon.appiconset.

Usage: tools/make-app-icon.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "LYLLTH", "Resources", "Fonts")
OUT = os.path.join(ROOT, "LYLLTH", "Assets.xcassets", "AppIcon.appiconset")

UNITS = 1000                 # glyphs are laid out at 1000 units per em
TRACKING = 26                # the wordmark's 1.6 pt tracking at 62 pt, in units
ADVANCE = 570                # advance width of L in both cuts
STROKE = 80                  # solid L stem and foot weight, measured
# The beam is heavier than the stems, as engraved beams are. User asked for
# a thicker top line than the stroke weight and chose 150 on 2026-09-25.
BEAM = int(os.environ.get("LYLLTH_ICON_BEAM", "150"))

TEAL = (0x33, 0xCC, 0xCC)
INDIGO = (0x66, 0x66, 0xFF)
PURPLE = (0x99, 0x33, 0xFF)
# (x, y, colour) in the mark's box; teal last.
SPOTS = [
    (0.82, 0.88, PURPLE),
    (0.46, 0.08, INDIGO),
    (0.96, 0.30, PURPLE),
    (0.06, 0.40, TEAL),
]
SPOT_RADIUS = 0.80
BACKGROUND = (0, 0, 0)       # matches DRUMKIT's icon


def mark() -> Image.Image:
    outline = ImageFont.truetype(os.path.join(FONTS, "NIGHTSHAPE-Bold_Outline.ttf"), UNITS)
    solid = ImageFont.truetype(os.path.join(FONTS, "Nightshape-Bold.ttf"), UNITS)
    def layer(font, x):
        image = Image.new("L", (2400, 1400), 0)
        ImageDraw.Draw(image).text((x, 100), "L", font=font, fill=255)
        return image

    origin_x = 200
    left = layer(outline, origin_x)
    right = layer(solid, origin_x + ADVANCE + TRACKING)
    canvas = Image.fromarray(np.maximum(np.array(left), np.array(right)))
    draw = ImageDraw.Draw(canvas)

    # Each glyph measured on its own layer so neither is mistaken for the other.
    left_ink = np.array(left) > 127
    right_ink = np.array(right) > 127
    ys, _ = np.nonzero(left_ink)
    outline_top = ys.min()
    stem_right = np.nonzero(left_ink[outline_top + 200])[0].max() + 1
    solid_stem_right = np.nonzero(right_ink.any(axis=0))[0].min() + STROKE
    if not (0 < stem_right < solid_stem_right):
        sys.exit("glyph measurement failed; fonts changed?")
    draw.rectangle([stem_right, outline_top, solid_stem_right - 1, outline_top + BEAM - 1], fill=255)
    return canvas.crop(canvas.getbbox())


def tie_dye(size) -> Image.Image:
    w, h = size
    field = np.zeros((h, w, 3)) + np.array(INDIGO, float)
    radius = max(w, h) * SPOT_RADIUS
    yy, xx = np.mgrid[0:h, 0:w]
    for sx, sy, colour in SPOTS:
        alpha = np.clip(1 - np.sqrt((xx - sx * w) ** 2 + (yy - sy * h) ** 2) / radius, 0, 1)[..., None]
        field = field * (1 - alpha) + np.array(colour, float) * alpha
    return Image.fromarray(field.astype("uint8"))


def master() -> Image.Image:
    """Opaque, full-bleed true black, like DRUMKIT's icon. macOS 26 masks
    icons to its own shape; a transparent margin there gets a system backing
    that stops the ground reading as true black."""
    size = 1024
    icon = Image.new("RGB", (size, size), BACKGROUND)

    glyphs = mark()
    # Same proportion the mark had on Apple's 824-pt body: 560 / 824 of it.
    target = round(size * 560 / 824)
    scale = target / glyphs.width
    glyphs = glyphs.resize((round(glyphs.width * scale), round(glyphs.height * scale)), Image.LANCZOS)
    fill = tie_dye(glyphs.size)
    x, y = optical_origin(glyphs, size)
    icon.paste(fill, (x, y), glyphs)
    return icon


def optical_origin(glyphs: Image.Image, size: int):
    """Centres the mark by where its ink sits, not by its box.

    The outline L is hollow and light; the solid L and the beam carry the
    weight, so box-centring reads left and low. Horizontally the mark is
    placed halfway between box centre and ink centroid (a full centroid
    over-corrects). Vertically the same, then lifted 1.5% of the tile, since
    the optical middle of a square sits slightly above its measured middle.
    """
    ink = np.array(glyphs, float) / 255
    total = ink.sum()
    ys, xs = np.mgrid[0:ink.shape[0], 0:ink.shape[1]]
    cx = (ink * xs).sum() / total
    cy = (ink * ys).sum() / total
    box_cx, box_cy = glyphs.width / 2, glyphs.height / 2
    anchor_x = (box_cx + cx) / 2
    anchor_y = (box_cy + cy) / 2
    return round(size / 2 - anchor_x), round(size / 2 - anchor_y - size * 0.015)


def main():
    os.makedirs(OUT, exist_ok=True)
    art = master()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            art.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as handle:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, handle, indent=2)
    with open(os.path.join(os.path.dirname(OUT), "Contents.json"), "w") as handle:
        json.dump({"info": {"author": "xcode", "version": 1}}, handle, indent=2)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
