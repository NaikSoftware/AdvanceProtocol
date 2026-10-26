#!/usr/bin/env python3
"""Виміри світла з кадрів tools/light_measure.gd: python3 -I tools/light_measure.py <каталог кадрів> <мітки.png>.

Ділянки стін і дахів — точки на кадрі crossroads_13_10_z8 (камера й геометрія не залежать від світла,
тож ті самі пікселі до й після). Земля — усі пікселі трави, що в кадрі без справжньої тіні світліші
за кадр з нею: відношення L* там, де є тінь.
"""
import colorsys
import sys

import numpy as np
from PIL import Image, ImageDraw

VIEW = "crossroads_13_10_z8"
HALF = 2
# хата: (затінена стіна, освітлена стіна, дах, чи дах у тіні) — пікселі кадру 1600x900
HOUSES = {
    "H1": ((780, 203), (828, 183), (780, 170), True),
    "H2": ((912, 406), (946, 462), (956, 400), False),
    "H3": ((1235, 444), (1346, 438), (1280, 400), True),
    "H4": ((445, 622), (583, 603), (507, 595), False),
}


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), float) / 255


def lab(rgb):
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    x = (0.4124564 * lin[..., 0] + 0.3575761 * lin[..., 1] + 0.1804375 * lin[..., 2]) / 0.95047
    y = 0.2126729 * lin[..., 0] + 0.7151522 * lin[..., 1] + 0.072175 * lin[..., 2]
    z = (0.0193339 * lin[..., 0] + 0.119192 * lin[..., 1] + 0.9503041 * lin[..., 2]) / 1.08883
    f = lambda t: np.where(t > 0.008856, np.cbrt(t), 7.787 * t + 16 / 116)
    return np.stack([116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))], -1)


def patch(img, p):
    x, y = p
    block = img[y - HALF:y + HALF + 1, x - HALF:x + HALF + 1].reshape(-1, 3)
    return np.median(block, axis=0)


def main():
    folder, marks_out = sys.argv[1], sys.argv[2]
    img = load(f"{folder}/{VIEW}.png")
    marks = Image.fromarray((img * 255).astype(np.uint8))
    draw = ImageDraw.Draw(marks)
    print("house  wall_shade(L,a,b)  wall_lit(L,a,b)  db*(shade-lit)  roof(L,hue deg,shaded)")
    for name, (shade, lit, roof, roof_shaded) in HOUSES.items():
        s, l, r = (patch(img, p) for p in (shade, lit, roof))
        ls, ll = lab(s), lab(l)
        hue = colorsys.rgb_to_hsv(*r)[0] * 360
        print(f"{name}  L{ls[0]:.1f} a{ls[1]:.1f} b{ls[2]:.1f}  L{ll[0]:.1f} a{ll[1]:.1f} b{ll[2]:.1f}  {ls[2] - ll[2]:+.1f}  "
              f"L{lab(r)[0]:.1f} {hue:.0f} {'shaded' if roof_shaded else 'lit'}")
        for p, c in ((shade, "cyan"), (lit, "yellow"), (roof, "magenta")):
            draw.rectangle([p[0] - HALF - 1, p[1] - HALF - 1, p[0] + HALF + 1, p[1] + HALF + 1], outline=c)
    marks.save(marks_out)
    for view in ("crossroads_13_10_z8", "crossroads_11_8_z8", "crossroads_15_9_z8", "crossroads_13_10_z20"):
        on, off = load(f"{folder}/{view}.png"), load(f"{folder}/{view}_off.png")
        lon, loff = lab(on)[..., 0], lab(off)[..., 0]
        sub = off[::2, ::2]
        hsv = np.array([colorsys.rgb_to_hsv(*px) for px in sub.reshape(-1, 3)]).reshape(sub.shape)
        grass = (hsv[..., 0] > 0.11) & (hsv[..., 0] < 0.32) & (hsv[..., 1] > 0.15)
        d = (loff - lon)[::2, ::2]
        sel = grass & (d > 0.5)
        if view.endswith("z20"):
            # на дальньому зумі краї кадру — хмарні тіні, що рухаються між двома кадрами; міряємо село
            sel[:125, :] = sel[375:, :] = False
            sel[:, :250] = sel[:, 525:] = False
        ratio = (lon[::2, ::2] / loff[::2, ::2])[sel]
        print(f"{view} ground: {sel.sum()} px, L* on/off median {np.median(ratio):.3f} p25 {np.percentile(ratio, 25):.3f} min {ratio.min():.3f}")
        lb = lab(off)[::2, ::2][grass]
        if view.endswith("z8"):
            a, b = np.median(lb[:, 1]), np.median(lb[:, 2])
            print(f"{view} grass (без тіні): L {np.median(lb[:, 0]):.1f} a {a:.1f} b {b:.1f} C* {np.hypot(a, b):.1f} h {np.degrees(np.arctan2(b, a)):.1f}")
        print(f"{view} frame L* mean {lon.mean():.2f}")


main()
