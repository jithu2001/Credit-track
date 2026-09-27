#!/usr/bin/env python3
"""Generates the WholeFlow app icon PNGs used by flutter_launcher_icons.

Mark: a bold "W" drawn as one continuous stroke whose last leg rises into an
arrow (money flowing in), white on a teal gradient, arrowhead in amber.

Outputs (assets/icon/):
  icon.svg         source artwork (full-bleed square)
  icon.png         1024 px, full-bleed: iOS and the legacy Android icon
  background.png   1024 px teal gradient: adaptive-icon background layer
  foreground.png   1024 px transparent: adaptive-icon foreground, inside the safe zone
  monochrome.png   1024 px white-on-transparent: Android 13+ themed icon

Run from wholeflow_app/ (needs cairosvg):
  python3 tool/app_icon/generate.py && dart run flutter_launcher_icons
"""

import math
import pathlib

import cairosvg

OUT = pathlib.Path(__file__).resolve().parents[2] / "assets" / "icon"
SIZE = 1024

TEAL_LIGHT = "#009688"
TEAL_DARK = "#00574B"
WHITE = "#FFFFFF"
AMBER = "#FFC107"

# The "W" on a 1024 grid, centred. The last point is the arrow tip.
# Shifted down-left so the arrow's weight doesn't pull the mark off-centre.
W_POINTS = [(-245, -130), (-135, 190), (-15, -20), (105, 190), (235, -180)]
STROKE = 92
HEAD_LEN = 150   # arrowhead length along the stroke
HEAD_HALF = 105  # arrowhead half-width


def mark(scale: float, stroke_color: str, head_color: str) -> str:
    """The W + arrow as SVG elements, scaled about the centre."""
    cx = cy = SIZE / 2
    pts = [(cx + x * scale, cy + y * scale) for x, y in W_POINTS]
    (x1, y1), (x2, y2) = pts[-2], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length          # along the last leg
    px, py = -uy, ux                           # perpendicular
    head, half = HEAD_LEN * scale, HEAD_HALF * scale
    tip = (x2 + ux * head * 0.35, y2 + uy * head * 0.35)
    base = (tip[0] - ux * head, tip[1] - uy * head)
    left = (base[0] + px * half, base[1] + py * half)
    right = (base[0] - px * half, base[1] - py * half)
    # Stop the stroke inside the arrowhead so the round cap doesn't poke out.
    stem_end = (base[0] + ux * head * 0.25, base[1] + uy * head * 0.25)
    path = " ".join(
        [f"M {pts[0][0]:.1f} {pts[0][1]:.1f}"]
        + [f"L {x:.1f} {y:.1f}" for x, y in pts[1:-1]]
        + [f"L {stem_end[0]:.1f} {stem_end[1]:.1f}"]
    )
    tri = " ".join(f"{x:.1f},{y:.1f}" for x, y in (tip, left, right))
    return (
        f'<path d="{path}" fill="none" stroke="{stroke_color}" stroke-width="{STROKE * scale:.1f}" '
        f'stroke-linecap="round" stroke-linejoin="round"/>'
        f'<polygon points="{tri}" fill="{head_color}" stroke="{head_color}" '
        f'stroke-width="{STROKE * scale * 0.18:.1f}" stroke-linejoin="round"/>'
    )


GRADIENT = (
    '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
    f'<stop offset="0" stop-color="{TEAL_LIGHT}"/><stop offset="1" stop-color="{TEAL_DARK}"/>'
    "</linearGradient></defs>"
)


def svg(body: str, background: bool) -> str:
    bg = f'{GRADIENT}<rect width="{SIZE}" height="{SIZE}" fill="url(#bg)"/>' if background else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">{bg}{body}</svg>'


def render(name: str, content: str) -> None:
    cairosvg.svg2png(bytestring=content.encode(), write_to=str(OUT / name), output_width=SIZE, output_height=SIZE)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Full-bleed icon: the mark fills ~60% of the square.
    full = svg(mark(1.0, WHITE, AMBER), background=True)
    (OUT / "icon.svg").write_text(full)
    render("icon.png", full)
    render("background.png", svg("", background=True))
    # Adaptive foreground: launchers mask to a circle/squircle and may zoom, so
    # keep the mark within the central ~60% safe zone.
    render("foreground.png", svg(mark(0.8, WHITE, AMBER), background=False))
    render("monochrome.png", svg(mark(0.8, WHITE, WHITE), background=False))
    print(f"wrote icon.svg, icon.png, background.png, foreground.png, monochrome.png to {OUT}")


if __name__ == "__main__":
    main()
