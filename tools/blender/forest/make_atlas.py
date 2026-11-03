"""Збирає атлас групи: спрайти пучків за наборами видів і смуги стовбурів, із тонуванням.

Запуск (звичайний python): python3 -I make_atlas.py <spec.json> <тека_джерел> <вихід>
Пише <вихід>/<atlas>.png і <вихід>/<atlas>.json (прямокутники в UV для build_library.py).
Розкладка — сітка клітинок 128 px: спрайт пучка ~2,4 м займає клітинку (1,9 см на тексель),
блок 128×256 тримає чотири смуги кори по 32×256.
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

SPEC, SRC, OUT = sys.argv[1:4]
CELL = 128
STRIP_W, STRIP_H = 32, 256


def srgb_to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


LUM = np.array([0.2126, 0.7152, 0.0722])


def srgb_to_lab(rgb):
    lin = srgb_to_lin(rgb)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = lin @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def lab_to_srgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx, fz = fy + lab[..., 1] / 500, fy - lab[..., 2] / 200
    f = np.stack([fx, fy, fz], -1)
    xyz = np.where(f > 0.2069, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    Mi = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    return lin_to_srgb(xyz @ Mi.T)


def lab_grade(img, g):
    """Середні L*, C* і тон h непрозорого — до цілі; розкид навколо середнього лишається
    (L* множиться на contrast_l). Так задаються числа з брифу, а не «на око»."""
    m = img[..., 3] > 0.5
    lab = srgb_to_lab(img[..., :3])
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    if "L" in g:
        mu = L[m].mean()
        L = g["L"] + (L - mu) * g.get("contrast_l", 1.0)
    if "C" in g or "h" in g:
        am, bm = a[m].mean(), b[m].mean()
        C = np.hypot(a, b)
        h = np.arctan2(b, a)
        hm = np.arctan2(bm, am)
        if "h" in g:
            h = h + (np.radians(g["h"]) - hm)
        if "C" in g:
            C = C * (g["C"] / max(float(C[m].mean()), 1e-3))
        a, b = C * np.cos(h), C * np.sin(h)
    out = img.copy()
    out[..., :3] = lab_to_srgb(np.stack([L, a, b], -1))
    return out


def grade(img, g):
    """Тон під настрій сцени: тонування, стискання контрасту яскравості, насиченість і
    середня лінійна яскравість непрозорого."""
    a = img[..., 3]
    lin = srgb_to_lin(img[..., :3])
    m = a > 0.5
    if not m.any() or not g:
        return img
    if "lab" in g:
        return lab_grade(img, g["lab"])
    if "tint" in g:
        lin = lin * np.array(g["tint"])
    y = lin @ LUM
    if "contrast" in g:
        # Контраст у логарифмі яскравості: множник 0,6 дає на 40 % менші перепади.
        ly = np.log(np.maximum(y, 1e-5))
        mu = ly[m].mean()
        ny = np.exp(mu + (ly - mu) * g["contrast"])
        lin = lin * (ny / np.maximum(y, 1e-5))[..., None]
        y = ny
    if "sat" in g:
        lin = y[..., None] + (lin - y[..., None]) * g["sat"]
    if "target_y" in g:
        lin = lin * (g["target_y"] / max(float((lin @ LUM)[m].mean()), 1e-5))
    out = img.copy()
    out[..., :3] = lin_to_srgb(lin)
    return out


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0


def resize(img, w, h):
    im = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS)
    return np.asarray(im).astype(np.float64) / 255.0


def soft_edge(img, seed):
    """Рваний круглий край замість прямих меж кадру: інакше картка видає себе квадратом."""
    rng = np.random.default_rng(seed)
    n = img.shape[0]
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n * 2 - 1
    r = np.hypot(xx, yy)
    ang = np.arctan2(yy, xx)
    wob = sum(rng.uniform(0.03, 0.08) * np.sin(k * ang + rng.uniform(0, 6.3)) for k in (3, 5, 9))
    mask = np.clip((0.98 + wob - r) / 0.25, 0, 1)
    out = img.copy()
    out[..., 3] *= mask
    return out


def premul_dilate(img, steps=6):
    """Колір розтікається в прозорі тексели, щоб mip-рівні не тягли чорне в край пучка."""
    rgb, a = img[..., :3].copy(), img[..., 3]
    m = a > 0.05
    for _ in range(steps):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(m.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(np.roll(rgb * m[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(m, dy, 0), dx, 1)
        new = (~m) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        m = m | new
    # Решта прозорих текселів — середній колір пучка: далекі mip усереднюють блоки по
    # 16×16 і інакше тягнуть чорне тло в край крони — чорне конфеті здаля.
    solid = a > 0.05
    if solid.any():
        rgb[~m] = rgb[solid].mean(axis=0)
    out = img.copy()
    out[..., :3] = rgb
    return out


def trunk_strip(path):
    """Смуга кори: у кожному рядку — середні дві третини стовбура, де б він не стояв у кадрі
    (стовбур вигнутий і тоншає догори), розтягнуті на 32 px."""
    t = load(path)
    H, W = t.shape[:2]
    xs = np.arange(W)
    rows = np.zeros((H, STRIP_W, 4))
    ok = np.zeros(H, bool)
    for y in range(H):
        cols = xs[t[y, :, 3] > 0.5]
        if len(cols) < 2:
            continue
        c0, c1 = cols.min(), cols.max()
        a, b = c0 + (c1 - c0) / 6, c1 - (c1 - c0) / 6
        u = np.linspace(a, b, STRIP_W)
        i0 = np.clip(np.floor(u).astype(int), 0, W - 2)
        f = (u - i0)[:, None]
        rows[y] = t[y, i0] * (1 - f) + t[y, i0 + 1] * f
        ok[y] = True
    idx = np.where(ok)[0]
    near = idx[np.clip(np.searchsorted(idx, np.arange(H)), 0, len(idx) - 1)]
    rows = rows[near]
    s = resize(rows, STRIP_W, STRIP_H)
    s[..., 3] = 1.0
    return s


def main():
    global CELL
    spec = json.load(open(SPEC))
    CELL = spec.get("cell", CELL)
    size = spec.get("size", 1024)
    n = size // CELL
    atlas = np.zeros((size, size, 4))
    free = np.ones((n, n), bool)
    rects = {"sprites": {}, "trunks": {}, "extra": {}}

    def take(w, h):
        for r in range(n - h + 1):
            for c in range(n - w + 1):
                if free[r:r + h, c:c + w].all():
                    free[r:r + h, c:c + w] = False
                    return r * CELL, c * CELL
        raise SystemExit("атлас переповнений")

    def uv(x, y, w, h):
        return [x / size, y / size, w / size, h / size]

    seed = 0
    for name, sources in spec["sprite_sets"].items():
        rects["sprites"][name] = []
        for srcd in sources:
            files = sorted(glob.glob(os.path.join(SRC, srcd["src"], srcd.get("glob", "sprite_*.png"))))
            for f in files[:srcd.get("max", 99)]:
                img = load(f)
                img = resize(img, CELL, CELL)
                img = soft_edge(img, seed)
                seed += 1
                img = grade(img, srcd.get("grade", {}))
                if "alpha_gain" in srcd:
                    img[..., 3] = np.clip(img[..., 3] * srcd["alpha_gain"], 0, 1)
                y, x = take(1, 1)
                atlas[y:y + CELL, x:x + CELL] = premul_dilate(img)
                rects["sprites"][name].append(uv(x, y, CELL, CELL))

    block = None
    k = 0
    for it in spec["items"]:
        if not (it.get("trunk", True) or it.get("strip")):
            continue
        if k % (CELL // STRIP_W) == 0:
            block = take(1, STRIP_H // CELL)
        y, x = block[0], block[1] + (k % (CELL // STRIP_W)) * STRIP_W
        k += 1
        s = grade(trunk_strip(os.path.join(SRC, it.get("trunk_src", it["src"]), "trunk.png")), it.get("trunk_grade", {}))
        atlas[y:y + STRIP_H, x:x + STRIP_W] = s
        rects["trunks"][it["node"]] = uv(x, y, STRIP_W, STRIP_H)

    os.makedirs(OUT, exist_ok=True)
    name = spec["atlas"]
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    json.dump(rects, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    used = int((~free).sum())
    print("atlas", name, size, "cells used", used, "of", n * n)


main()
