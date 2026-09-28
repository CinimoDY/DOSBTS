"""
Render the DOSBTS app icon — an amber Libre-style CGM sensor on CGA black.

The eiDotter yolk disc restated as a sensor: a round body, a recessed oval
cutout in the upper half and the small filament hole at the disc centre.
Sized to ~59% of the frame so it sits inside Apple's icon grid.

Uses Pillow primitives only (no libcairo / numpy). Everything is drawn at
SUPERSAMPLE x resolution and downscaled, which anti-aliases the ellipses.
scripts/app-icon.svg mirrors the `any` variant; keep the two in sync.

Variants (iOS 18+ single-size app icon appearances):
  any     full colour on the black CGA background
  dark    same art on a transparent background (iOS supplies the backdrop)
  tinted  grayscale luminance on transparent — iOS applies the tint colour

Palette hexes match eiDotter brand tokens from
  src/components/Brand/components/Logo.tsx:
    amber base    #FFB000
    dome          #FFD97A
    specular      #FFE8A8

Usage: python3 scripts/render-app-icon.py [--out DIR]
"""

import argparse
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SUPERSAMPLE = 2

# --- Palette (brand-locked to eiDotter) ---
BLACK = (0, 0, 0, 255)
AMBER = (255, 176, 0, 255)         # #FFB000
AMBER_DARK = (154, 87, 0, 255)     # #9A5700
AMBER_DEEP = (96, 52, 0, 255)      # recess shadow — darker than amberDark
DOME = (255, 217, 122, 255)        # #FFD97A
SPECULAR = (255, 232, 168, 255)    # #FFE8A8

# --- Geometry, all proportional to the body radius ---
BODY_RADIUS = 300                  # disc ≈ 59% of the 1024 frame
EDGE_WIDTH = 0.03                  # dark rim, × R
OVAL_HALF_W = 0.50                 # oval cutout, × R
OVAL_HALF_H = 0.21
OVAL_OFFSET_Y = -0.45              # oval centre above disc centre, × R
BEVEL = 0.045                      # shadow / highlight crescent depth, × R
HOLE_RADIUS = 0.11                 # filament hole, × R
HOLE_RING = 0.035                  # dark ring around the hole, × R


def _ellipse_box(cx, cy, rx, ry):
    return (cx - rx, cy - ry, cx + rx, cy + ry)


def _mask(size, box):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m


def _gradient_disc(size, cx, cy, r, stops, highlight):
    """Radially shaded disc; brightest point offset by `highlight` (× r)."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hx, hy = cx + highlight[0] * r, cy + highlight[1] * r
    inner, mid, outer = stops
    x0, y0 = int(cx - r), int(cy - r)
    w = h = int(2 * r) + 1
    data = []
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            t = min((((x - hx) ** 2 + (y - hy) ** 2) ** 0.5) / (r * 1.25), 1.0)
            if t < 0.5:
                k = t / 0.5
                c = tuple(int(inner[i] * (1 - k) + mid[i] * k) for i in range(4))
            else:
                k = (t - 0.5) / 0.5
                c = tuple(int(mid[i] * (1 - k) + outer[i] * k) for i in range(4))
            data.append(c)
    patch = Image.new("RGBA", (w, h))
    patch.putdata(data)
    canvas.paste(patch, (x0, y0))
    disc = _mask(size, _ellipse_box(cx, cy, r, r))
    canvas.putalpha(ImageChops.multiply(canvas.getchannel("A"), disc))
    return canvas


def _fill(size, mask, color):
    layer = Image.new("RGBA", (size, size), color)
    layer.putalpha(ImageChops.multiply(mask, Image.new("L", (size, size), color[3])))
    return layer


def render(mode: str = "any") -> Image.Image:
    s = SIZE * SUPERSAMPLE
    R = BODY_RADIUS * SUPERSAMPLE
    cx = cy = s // 2
    tinted = mode == "tinted"

    if tinted:
        # Luminance only — light disc, mid recess, black hole.
        body_stops = ((235, 235, 235, 255), (215, 215, 215, 255), (170, 170, 170, 255))
        edge, deep, recess, lift = (120,) * 3 + (255,), (70,) * 3 + (255,), (110,) * 3 + (255,), (255,) * 4
    else:
        body_stops = (DOME, AMBER, AMBER_DARK)
        edge, deep, recess, lift = AMBER_DARK, AMBER_DEEP, AMBER_DARK, SPECULAR

    bg = BLACK if mode == "any" else (0, 0, 0, 0)
    img = Image.new("RGBA", (s, s), bg)
    body_mask = _mask(s, _ellipse_box(cx, cy, R, R))

    # === Phosphor bloom behind the disc (colour variants only) ===
    if not tinted:
        bloom = _fill(s, body_mask, (AMBER[0], AMBER[1], AMBER[2], 110))
        img.alpha_composite(bloom.filter(ImageFilter.GaussianBlur(radius=0.08 * R)))

    # === Sensor body ===
    img.alpha_composite(_gradient_disc(s, cx, cy, R, body_stops, highlight=(-0.22, -0.28)))
    ring = ImageChops.subtract(body_mask, _mask(s, _ellipse_box(cx, cy, R * (1 - EDGE_WIDTH), R * (1 - EDGE_WIDTH))))
    img.alpha_composite(_fill(s, ring, edge))

    # === Oval cutout — recessed well with a bevel ===
    ox, oy = cx, cy + OVAL_OFFSET_Y * R
    orx, ory = OVAL_HALF_W * R, OVAL_HALF_H * R
    bevel = BEVEL * R
    well = _mask(s, _ellipse_box(ox, oy, orx, ory))
    well_shifted = _mask(s, _ellipse_box(ox, oy + bevel, orx, ory))
    # Lip highlight: the part of a lowered copy that pokes out below the well.
    img.alpha_composite(_fill(s, ImageChops.subtract(well_shifted, well), lift))
    # Well floor, then the shadowed top edge (well minus lowered copy).
    img.alpha_composite(_fill(s, well, recess))
    img.alpha_composite(_fill(s, ImageChops.subtract(well, well_shifted), deep))

    # === Filament hole at the disc centre ===
    hr = HOLE_RADIUS * R
    img.alpha_composite(_fill(s, _mask(s, _ellipse_box(cx, cy, hr + HOLE_RING * R, hr + HOLE_RING * R)), edge))
    img.alpha_composite(_fill(s, _mask(s, _ellipse_box(cx, cy, hr, hr)), BLACK))

    # === Scanline overlay, clipped to the disc (colour variants only) ===
    if not tinted:
        lines = Image.new("L", (s, s), 0)
        ld = ImageDraw.Draw(lines)
        step = 4 * SUPERSAMPLE
        for y in range(0, s, step):
            ld.rectangle([(0, y), (s, y + step // 2 - 1)], fill=20)
        img.alpha_composite(_fill(s, ImageChops.multiply(lines, body_mask), (0, 0, 0, 255)))

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return img.convert("RGB") if mode == "any" else img


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="scripts")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for mode, name in [("any", "AppIcon-1024.png"),
                       ("dark", "AppIcon-1024-dark.png"),
                       ("tinted", "AppIcon-1024-tinted.png")]:
        path = os.path.join(args.out, name)
        render(mode).save(path, "PNG", optimize=True)
        print(f"wrote {path}")
