"""Draws the 1024x1024 app icon: a white ship over two waves on harbor teal (#0B6E8A).

Drawn at 4x and scaled down for smooth edges. App Store icons must have no transparency, so the result is RGB.

Usage: python3 ci/make_icon.py App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw

SIZE = 1024
SCALE = 4
TEAL_TOP = (16, 124, 154)
TEAL_BOTTOM = (8, 92, 116)
WHITE = (255, 255, 255)
ON, OFF = 255, 0
LIFT = 40  # the drawing below is centred 40 px low; lift it to the middle


def s(v: float) -> int:
    return int(round(v * SCALE))


def gradient(size: int) -> Image.Image:
    column = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        column.putpixel((0, y), tuple(int(TEAL_TOP[i] + (TEAL_BOTTOM[i] - TEAL_TOP[i]) * t) for i in range(3)))
    return column.resize((size, size), Image.BILINEAR)


def wave(draw: ImageDraw.ImageDraw, y: float, amplitude: float, width: float, x0: float, x1: float) -> None:
    points = []
    steps = 160
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        points.append((s(x), s(y + amplitude * math.sin((x - x0) / (x1 - x0) * 3 * math.pi))))
    draw.line(points, fill=ON, width=s(width), joint="curve")
    r = s(width) / 2
    for px, py in (points[0], points[-1]):
        draw.ellipse((px - r, py - r, px + r, py + r), fill=ON)


def main(dst: str) -> None:
    big = SIZE * SCALE
    img = gradient(big)
    mask = Image.new("L", (big, big), OFF)  # white where the mark is; windows are cut out of it
    d = ImageDraw.Draw(mask)

    # Hull: flat deck, pointed bow on the right, rounded stern on the left.
    d.polygon([(s(196), s(548)), (s(842), s(548)), (s(752), s(662)), (s(262), s(662))], fill=ON)

    # Decks, stepping back toward the stern.
    d.rounded_rectangle((s(300), s(456), s(724), s(548) + s(4)), radius=s(22), fill=ON)
    d.rounded_rectangle((s(350), s(374), s(640), s(460)), radius=s(20), fill=ON)

    # Funnel, leaning back.
    d.polygon([(s(410), s(374)), (s(472), s(374)), (s(462), s(286)), (s(408), s(286))], fill=ON)

    # Windows and the hull stripe: cut out, so the sea colour shows through.
    for row_y, x_from, x_to, gap in ((502, 340, 690, 50), (417, 390, 610, 50)):
        x = x_from
        while x <= x_to:
            d.ellipse((s(x - 12), s(row_y - 12), s(x + 12), s(row_y + 12)), fill=OFF)
            x += gap
    d.rounded_rectangle((s(300), s(588), s(700), s(606)), radius=s(9), fill=OFF)

    # Two waves under the hull.
    wave(d, 732, 16, 30, 176, 848)
    wave(d, 806, 14, 26, 236, 788)

    mask = ImageChops.offset(mask, 0, -s(LIFT))
    img.paste(WHITE, (0, 0, big, big), mask)
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(dst, "PNG")
    print(f"Icon written: {dst} ({out.size[0]}x{out.size[1]}, no alpha)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
