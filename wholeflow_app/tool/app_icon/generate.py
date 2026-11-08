#!/usr/bin/env python3
"""Generates the WholeFlow app icons: Owner (teal) and Staff (amber, with a map pin).

Mark: a bold "W" drawn as one continuous stroke whose last leg rises into an
arrow (money flowing in). Owner: white on a teal gradient, arrowhead in amber.
Staff: teal on an amber gradient, arrowhead white, plus a map-pin badge so the
two apps differ in shape too (Android 13+ themed icons drop the colours).

Owner outputs (assets/icon/), turned into android/app/src/main/res and the iOS
icons by flutter_launcher_icons (config in pubspec.yaml):
  icon.svg         source artwork (full-bleed square)
  icon.png         1024 px, full-bleed: iOS and the legacy Android icon
  background.png   1024 px teal gradient: adaptive-icon background layer
  foreground.png   1024 px transparent: adaptive-icon foreground, inside the safe zone
  monochrome.png   1024 px white-on-transparent: Android 13+ themed icon

Staff outputs: the same five files in assets/icon/staff/, plus the launcher
PNGs in android/app/src/staff/res/ (written here directly: flutter_launcher_icons
can't do one flavor without taking over the others) and store/staff/icon-512.png.
The staff flavor reuses mipmap-anydpi-v26/ic_launcher.xml from src/main.

Run from wholeflow_app/ (needs cairosvg and Pillow):
  python3 tool/app_icon/generate.py && dart run flutter_launcher_icons
"""

import math
import pathlib

import cairosvg
from PIL import Image

APP = pathlib.Path(__file__).resolve().parents[2]
OUT = APP / "assets" / "icon"
STAFF_OUT = OUT / "staff"
STAFF_RES = APP / "android" / "app" / "src" / "staff" / "res"
SIZE = 1024

TEAL_LIGHT = "#009688"
TEAL_DARK = "#00574B"
WHITE = "#FFFFFF"
AMBER = "#FFC107"
AMBER_LIGHT = "#FFD54F"
AMBER_DARK = "#FFA000"

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


def gradient(light: str, dark: str) -> str:
    return (
        '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{light}"/><stop offset="1" stop-color="{dark}"/>'
        "</linearGradient></defs>"
    )


GRADIENT = gradient(TEAL_LIGHT, TEAL_DARK)
STAFF_GRADIENT = gradient(AMBER_LIGHT, AMBER_DARK)


def svg(body: str, background: bool, grad: str = GRADIENT) -> str:
    bg = f'{grad}<rect width="{SIZE}" height="{SIZE}" fill="url(#bg)"/>' if background else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">{bg}{body}</svg>'


# Staff: the W moves up-left and a map-pin badge sits bottom-right. Offsets are
# from the centre at full size; `k` shrinks the whole group about the centre
# (0.8 keeps the badge inside the adaptive-icon safe circle).
STAFF_MARK_SCALE = 0.84
STAFF_MARK_SHIFT = -48
BADGE_OFFSET = 190
BADGE_R = 112


def pin_badge(k: float, color: str) -> str:
    """A disc with a map pin cut out of it (and the pin's dot filled back in),
    as one even-odd path, so the pin shows whatever is behind the badge."""
    cx = cy = SIZE / 2 + BADGE_OFFSET * k
    r = BADGE_R * k
    s = r / 112  # pin artwork is drawn for a 112 px disc
    disc = f"M {cx - r:.1f} {cy:.1f} a {r:.1f} {r:.1f} 0 1 0 {2 * r:.1f} 0 a {r:.1f} {r:.1f} 0 1 0 {-2 * r:.1f} 0 Z"
    px, py = cx, cy - 12 * s           # centre of the pin's round head
    hr, tip = 44 * s, cy + 66 * s      # head radius, point of the pin
    pin = (
        f"M {px:.1f} {tip:.1f} C {px - 22 * s:.1f} {py + 40 * s:.1f} {px - hr:.1f} {py + 22 * s:.1f} {px - hr:.1f} {py:.1f} "
        f"A {hr:.1f} {hr:.1f} 0 1 1 {px + hr:.1f} {py:.1f} "
        f"C {px + hr:.1f} {py + 22 * s:.1f} {px + 22 * s:.1f} {py + 40 * s:.1f} {px:.1f} {tip:.1f} Z"
    )
    dr = 17 * s
    dot = f"M {px - dr:.1f} {py:.1f} a {dr:.1f} {dr:.1f} 0 1 0 {2 * dr:.1f} 0 a {dr:.1f} {dr:.1f} 0 1 0 {-2 * dr:.1f} 0 Z"
    return f'<path d="{disc} {pin} {dot}" fill="{color}" fill-rule="evenodd"/>'


def staff_mark(k: float, stroke_color: str, head_color: str, badge_color: str) -> str:
    shift = STAFF_MARK_SHIFT * k
    return (
        f'<g transform="translate({shift:.1f},{shift:.1f})">{mark(STAFF_MARK_SCALE * k, stroke_color, head_color)}</g>'
        + pin_badge(k, badge_color)
    )


def render(name: str, content: str, out: pathlib.Path = OUT) -> None:
    cairosvg.svg2png(bytestring=content.encode(), write_to=str(out / name), output_width=SIZE, output_height=SIZE)


# Android launcher sizes, as flutter_launcher_icons writes them for src/main.
LEGACY_PX = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_PX = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def resized(src: pathlib.Path, px: int, dest: pathlib.Path, mode: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    Image.open(src).convert(mode).resize((px, px), Image.LANCZOS).save(dest, optimize=True)


def staff() -> None:
    STAFF_OUT.mkdir(parents=True, exist_ok=True)
    full = svg(staff_mark(1.0, TEAL_DARK, WHITE, TEAL_DARK), background=True, grad=STAFF_GRADIENT)
    (STAFF_OUT / "icon.svg").write_text(full)
    render("icon.png", full, STAFF_OUT)
    render("background.png", svg("", background=True, grad=STAFF_GRADIENT), STAFF_OUT)
    render("foreground.png", svg(staff_mark(0.8, TEAL_DARK, WHITE, TEAL_DARK), background=False), STAFF_OUT)
    render("monochrome.png", svg(staff_mark(0.8, WHITE, WHITE, WHITE), background=False), STAFF_OUT)
    for dpi, px in LEGACY_PX.items():
        resized(STAFF_OUT / "icon.png", px, STAFF_RES / f"mipmap-{dpi}" / "ic_launcher.png", "RGB")
    for dpi, px in ADAPTIVE_PX.items():
        resized(STAFF_OUT / "background.png", px, STAFF_RES / f"drawable-{dpi}" / "ic_launcher_background.png", "RGB")
        for layer in ("foreground", "monochrome"):
            resized(STAFF_OUT / f"{layer}.png", px, STAFF_RES / f"drawable-{dpi}" / f"ic_launcher_{layer}.png", "RGBA")
    resized(STAFF_OUT / "icon.png", 512, APP / "store" / "staff" / "icon-512.png", "RGB")
    print(f"wrote the Staff icon to {STAFF_OUT}, {STAFF_RES} and store/staff/icon-512.png")


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
    staff()


if __name__ == "__main__":
    main()
