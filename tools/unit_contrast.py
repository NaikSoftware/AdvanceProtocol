"""ΔE (CIELAB, CIE76) моделі проти ґрунту навколо за кадрами tools/unit_shot.gd (contrast=<набір>).

    python3 -I tools/unit_contrast.py <out_dir> <tag> [tag...]

Для кожного місця читає <tag>_<місце>_{A,B,C}.png: маска — пурпурові пікселі кадру C; колір моделі —
медіана маски в кадрі A і медіана найсвітлішої половини маски (верх, освітлений сонцем); ґрунт —
медіана кільця навколо маски в кадрі B (без моделі, без власної тіні). Друкує ΔE за обома.
"""
import sys, glob, os
import numpy as np
from PIL import Image


def lab(rgb):
    c = np.asarray(rgb, float) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    x, y, z = (c @ m.T / np.array([0.95047, 1.0, 1.08883])).T
    f = lambda t: np.where(t > 216 / 24389, np.cbrt(t), (24389 / 27 * t + 16) / 116)
    return np.array([116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))])


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


out_dir = sys.argv[1]
print(f"{'frame':28s} {'px':>6s} {'model L*':>8s} {'ground L*':>9s} {'dE median':>9s} {'dE top':>7s} {'top L a b':>20s}")
for tag in sys.argv[2:]:
    for fa in sorted(glob.glob(f"{out_dir}/{tag}_*_A.png")):
        base = fa[:-6]
        A = np.asarray(Image.open(fa).convert("RGB")).astype(int)
        B = np.asarray(Image.open(base + "_B.png").convert("RGB")).astype(int)
        C = np.asarray(Image.open(base + "_C.png").convert("RGB")).astype(int)
        mask = (C[..., 0] > 200) & (C[..., 1] < 60) & (C[..., 2] > 200)
        if mask.sum() < 50:
            print(f"{os.path.basename(base):28s} no mask")
            continue
        ring = dilate(mask, 12) & ~dilate(mask, 3)
        px = A[mask]
        luma = px @ np.array([0.2126, 0.7152, 0.0722])
        top = px[luma >= np.median(luma)]
        gnd = np.median(B[ring], 0)
        lg = lab(gnd)
        d_med = float(np.linalg.norm(lab(np.median(px, 0)) - lg))
        d_top = float(np.linalg.norm(lab(np.median(top, 0)) - lg))
        print(f"{os.path.basename(base):28s} {mask.sum():6d} {lab(np.median(px, 0))[0]:8.1f} {lg[0]:9.1f} {d_med:9.1f} {d_top:7.1f} {np.array2string(lab(np.median(top, 0)).round(1))}")
