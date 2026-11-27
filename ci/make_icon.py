"""Draws the app icon and the launch-screen mark: a porthole looking out on a golden-hour sea, a small ship on the
horizon, on harbor teal. Original artwork, no text, no trademarks.

Drawn at 4x (4096 px) and scaled down for smooth edges. The App Store icon has no transparency and no rounded
corners (iOS rounds it), so it is saved as RGB. The launch mark is the porthole alone on a transparent background,
written next to the icon's asset catalog (LaunchMark.imageset), which Info.plist's UILaunchScreen shows.

Usage: python3 ci/make_icon.py App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4
N = SIZE * SCALE
LAUNCH_PX = 660  # 220 pt at @3x

BACKGROUND = [(0.0, "#1291B0"), (0.5, "#0B6E8A"), (1.0, "#06394B")]
METAL = [(0.0, "#FFFFFF"), (0.5, "#E6EDEF"), (1.0, "#A3B7BE")]
LIP = [(0.0, "#7F98A1"), (1.0, "#DCE5E8")]
SKY = [(0.0, "#1B3A6B"), (0.36, "#5E5894"), (0.66, "#E07F7C"), (0.88, "#F6B26E"), (1.0, "#FCD490")]
SEA = [(0.0, "#16849C"), (0.45, "#0B627B"), (1.0, "#05364A")]

CX, CY = 512, 512
R_OUT, R_LIP, R_IN = 404, 336, 318  # outer ring, inner lip, glass
HORIZON = 566
SUN_X, SUN_R = 458, 80


def s(v: float) -> int:
    return int(round(v * SCALE))


def rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def ramp(stops, steps):
    stops = [(t, rgb(c)) for t, c in stops]
    out = []
    for i in range(steps):
        t = i / (steps - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                u = 0.0 if t1 == t0 else max(0.0, min(1.0, (t - t0) / (t1 - t0)))
                out.append(tuple(int(round(c0[k] + (c1[k] - c0[k]) * u)) for k in range(3)))
                break
        else:
            out.append(stops[-1][1])
    return out


def vgrad(w: int, h: int, stops) -> Image.Image:
    column = Image.new("RGB", (1, 1024))
    column.putdata(ramp(stops, 1024))
    return column.resize((w, h), Image.BILINEAR)


def dgrad(stops, angle: float) -> Image.Image:
    """A full-canvas linear gradient tilted by `angle` degrees (negative: lit from the top left)."""
    big = int(N * 1.5)
    g = vgrad(big // 4, big // 4, stops).rotate(angle, resample=Image.BICUBIC).resize((big, big), Image.BILINEAR)
    o = (big - N) // 2
    return g.crop((o, o, o + N, o + N))


def blank() -> Image.Image:
    return Image.new("L", (N, N), 0)


def soft(mask: Image.Image, radius: float) -> Image.Image:
    small = mask.resize((N // 4, N // 4), Image.BILINEAR).filter(ImageFilter.GaussianBlur(radius / 4))
    return small.resize((N, N), Image.BILINEAR)


def fade(mask: Image.Image, k: float) -> Image.Image:
    return mask.point(lambda v: int(v * k))


def paint(img: Image.Image, color: str, mask: Image.Image) -> None:
    img.paste(rgb(color), (0, 0), mask)


def circle(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill: int = 255) -> None:
    d.ellipse((s(cx - r), s(cy - r), s(cx + r), s(cy + r)), fill=fill)


def poly(d: ImageDraw.ImageDraw, pts, fill: int = 255) -> None:
    d.polygon([(s(x), s(y)) for x, y in pts], fill=fill)


def ship(d: ImageDraw.ImageDraw, x: float, y: float, w: float) -> None:
    """A generic cruise ship in silhouette, bow to the right, waterline at y. Not any real ship."""
    poly(d, [(x, y - 0.115 * w), (x + 0.86 * w, y - 0.125 * w), (x + w, y - 0.15 * w), (x + 0.9 * w, y + 0.012 * w),
             (x + 0.05 * w, y + 0.012 * w)])
    d.rounded_rectangle((s(x + 0.10 * w), s(y - 0.205 * w), s(x + 0.80 * w), s(y - 0.10 * w)),
                        radius=s(0.035 * w), fill=255)
    d.rounded_rectangle((s(x + 0.20 * w), s(y - 0.285 * w), s(x + 0.68 * w), s(y - 0.19 * w)),
                        radius=s(0.035 * w), fill=255)
    poly(d, [(x + 0.30 * w, y - 0.27 * w), (x + 0.42 * w, y - 0.27 * w), (x + 0.395 * w, y - 0.385 * w),
             (x + 0.29 * w, y - 0.385 * w)])


def view() -> Image.Image:
    """What the porthole looks out on: dusk sky, setting sun, glitter on the water, a ship on the horizon."""
    top, bottom = CY - R_IN, CY + R_IN
    img = Image.new("RGB", (N, N))
    img.paste(vgrad(N, s(HORIZON - top) + 2, SKY), (0, s(top)))
    img.paste(vgrad(N, s(bottom - HORIZON) + 2, SEA), (0, s(HORIZON)))
    sky = blank()
    ImageDraw.Draw(sky).rectangle((0, 0, N, s(HORIZON)), fill=255)

    glow = blank()
    circle(ImageDraw.Draw(glow), SUN_X, HORIZON, SUN_R * 2.6)
    paint(img, "#FFD48A", ImageChops.multiply(fade(soft(glow, s(80)), 0.6), sky))
    sun = blank()
    circle(ImageDraw.Draw(sun), SUN_X, HORIZON, SUN_R)
    paint(img, "#FFF3D0", ImageChops.multiply(sun, sky))

    clouds = blank()
    cd = ImageDraw.Draw(clouds)
    for x0, x1, y, t in ((236, 420, 470, 9), (560, 770, 432, 7)):
        cd.rounded_rectangle((s(x0), s(y), s(x1), s(y + t)), radius=s(t / 2), fill=255)
    paint(img, "#F7A98A", fade(soft(clouds, s(2)), 0.55))

    # Glitter under the sun: dashes that thicken and spread toward the viewer.
    rnd = random.Random(7)
    glitter = blank()
    gd = ImageDraw.Draw(glitter)
    y = HORIZON + 7
    while y < bottom - 10:
        f = (y - HORIZON) / (bottom - HORIZON)
        thick = 4 + 9 * f
        spread = SUN_R * (0.5 + 1.1 * f)
        for _ in range(2 if f > 0.25 else 1):
            half = spread * rnd.uniform(0.25, 0.6)
            off = rnd.uniform(-spread + half, spread - half) * (0.8 if f > 0.25 else 0.3)
            gd.rounded_rectangle((s(SUN_X + off - half), s(y), s(SUN_X + off + half), s(y + thick)),
                                 radius=s(thick / 2), fill=int(255 * (1.0 - 0.4 * f)))
        y += thick + 8 + 16 * f
    paint(img, "#FFE3A6", glitter)

    swells = blank()
    wd = ImageDraw.Draw(swells)
    for y0, amp, phase, width in ((640, 5, 0.0, 4), (700, 7, 1.7, 5), (770, 9, 3.1, 6)):
        pts = [(150 + 740 * i / 160, y0 + amp * math.sin(i / 160 * 9 + phase)) for i in range(161)]
        wd.line([(s(px), s(py)) for px, py in pts], fill=255, width=s(width), joint="curve")
    paint(img, "#5FB6CB", fade(swells, 0.28))

    hull = blank()
    ship(ImageDraw.Draw(hull), SUN_X + SUN_R * 1.35, HORIZON + 3, 150)
    paint(img, "#14233A", hull)
    return img


def porthole(img: Image.Image) -> Image.Image:
    """Draws the ring, the bolts and the glass onto img; returns the mask of the whole porthole."""
    ring = blank()
    rd = ImageDraw.Draw(ring)
    circle(rd, CX, CY, R_OUT)
    circle(rd, CX, CY, R_LIP, fill=0)
    metal = dgrad(METAL, -35)
    img.paste(metal, (0, 0), ring)
    rim = blank()
    ImageDraw.Draw(rim).arc((s(CX - R_OUT + 3), s(CY - R_OUT + 3), s(CX + R_OUT - 3), s(CY + R_OUT - 3)),
                            start=160, end=290, fill=255, width=s(5))
    paint(img, "#FFFFFF", fade(soft(rim, s(3)), 0.9))
    lip = blank()
    ld = ImageDraw.Draw(lip)
    circle(ld, CX, CY, R_LIP)
    circle(ld, CX, CY, R_IN, fill=0)
    img.paste(dgrad(LIP, -35), (0, 0), lip)

    shadows, bolts = blank(), blank()
    sd, bd = ImageDraw.Draw(shadows), ImageDraw.Draw(bolts)
    for k in range(8):
        a = math.pi / 8 + k * math.pi / 4
        r = (R_OUT + R_LIP) / 2
        bx, by = CX + r * math.cos(a), CY + r * math.sin(a)
        circle(sd, bx + 1.5, by + 3, 14)
        circle(bd, bx, by, 12)
    paint(img, "#6F868E", soft(shadows, s(3)))
    img.paste(metal, (0, 0), bolts)

    glass = blank()
    circle(ImageDraw.Draw(glass), CX, CY, R_IN)
    img.paste(view(), (0, 0), glass)
    inner = blank()
    idr = ImageDraw.Draw(inner)
    circle(idr, CX, CY, R_IN)
    circle(idr, CX + 4, CY + 22, R_IN - 4, fill=0)
    paint(img, "#081826", ImageChops.multiply(fade(soft(inner, s(12)), 0.55), glass))
    glint = blank()
    box = (s(CX - R_IN + 42), s(CY - R_IN + 42), s(CX + R_IN - 42), s(CY + R_IN - 42))
    gl = ImageDraw.Draw(glint)
    gl.arc(box, start=198, end=246, fill=255, width=s(15))
    gl.arc(box, start=252, end=258, fill=255, width=s(15))
    paint(img, "#FFFFFF", ImageChops.multiply(fade(soft(glint, s(4)), 0.32), glass))

    whole = blank()
    circle(ImageDraw.Draw(whole), CX, CY, R_OUT)
    return whole


def main(dst: str) -> None:
    img = dgrad(BACKGROUND, -30)
    drop = blank()
    circle(ImageDraw.Draw(drop), CX, CY + 26, R_OUT + 2)
    paint(img, "#022330", fade(soft(drop, s(44)), 0.6))
    mask = porthole(img)

    icon = img.resize((SIZE, SIZE), Image.LANCZOS)
    icon.save(dst, "PNG")
    print(f"Icon written: {dst} ({icon.size[0]}x{icon.size[1]}, no alpha)")

    # Launch mark: the porthole alone, transparent around it.
    box = (s(CX - R_OUT - 4), s(CY - R_OUT - 4), s(CX + R_OUT + 4), s(CY + R_OUT + 4))
    mark = img.crop(box).convert("RGBA")
    mark.putalpha(mask.crop(box))
    mark = mark.resize((LAUNCH_PX, LAUNCH_PX), Image.LANCZOS)
    launch = Path(dst).resolve().parents[1] / "LaunchMark.imageset" / "LaunchMark.png"
    if launch.parent.is_dir():
        mark.save(launch, "PNG")
        print(f"Launch mark written: {launch} ({LAUNCH_PX}x{LAUNCH_PX})")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
