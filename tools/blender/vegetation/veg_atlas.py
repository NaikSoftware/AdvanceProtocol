"""Атлас групи рослинності на сезон: спрайти пучків і снопів та смуги кори.

Запуск (звичайний python): python3 -I veg_atlas.py <тека_спрайтів> <група> <сезон> <вихід>
група: bank | yard | meadow. Пише <вихід>/<група>_veg_<сезон>.png і .json (прямокутники в UV).
Клітинка 128 px: пучок ~2 м — 1,6 см на тексель, на найближчому зумі гри (7 см/px) це mip 2;
сніп очерету — 128×256 на ~2,5 м заввишки.
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

SRC, GROUP, SEASON, OUT = sys.argv[1:5]
SIZE, CELL, STRIP_W = 1024, 128, 32
GROUPS = {
    "bank": ["reed", "cattail", "willow", "alder"],
    "yard": ["apple", "cherry", "walnut", "lilac", "elder", "berry", "thuja"],
    "meadow": ["hawthorn", "dogrose", "pear", "oak", "wwillow"],
}
SHEAF = ("reed", "cattail")
# Кора (sRGB): середній тон і розкид світлих смуг. Темніша за листя, як у лісі.
BARK = {"willow": (0.40, 0.36, 0.26), "alder": (0.26, 0.24, 0.22), "apple": (0.33, 0.29, 0.25),
        "cherry": (0.32, 0.22, 0.19), "walnut": (0.45, 0.43, 0.40), "lilac": (0.36, 0.34, 0.31),
        "elder": (0.42, 0.39, 0.33), "berry": (0.38, 0.28, 0.21), "thuja": (0.36, 0.26, 0.20),
        "hawthorn": (0.32, 0.29, 0.26), "dogrose": (0.34, 0.25, 0.18), "pear": (0.24, 0.22, 0.20),
        "oak": (0.30, 0.28, 0.25), "wwillow": (0.36, 0.33, 0.27),
        # Свіжий злам: світла деревина уламків у купі поваленого дерева.
        "wood": (0.52, 0.44, 0.32)}


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0


def resize(img, w, h):
    im = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS)
    return np.asarray(im).astype(np.float64) / 255.0


def soft_edge(img, seed):
    """Рваний круглий край пучка замість прямих меж кадру (як у лісі)."""
    rng = np.random.default_rng(seed)
    n = img.shape[0]
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n * 2 - 1
    ang = np.arctan2(yy, xx)
    wob = sum(rng.uniform(0.03, 0.08) * np.sin(k * ang + rng.uniform(0, 6.3)) for k in (3, 5, 9))
    out = img.copy()
    out[..., 3] *= np.clip((0.98 + wob - np.hypot(xx, yy)) / 0.25, 0, 1)
    return out


def side_edge(img):
    """Сніп: бічні краї гаснуть, щоб стебла не обривались прямою лінією кадру; низ лишається."""
    w = img.shape[1]
    x = (np.arange(w) + 0.5) / w * 2 - 1
    out = img.copy()
    out[..., 3] *= np.clip((1.0 - np.abs(x)) / 0.15, 0, 1)[None, :]
    return out


def premul_dilate(img, steps=6):
    """Колір розтікається в прозорі тексели, щоб mip не тягли чорне тло в край пучка."""
    rgb, a = img[..., :3].copy(), img[..., 3]
    m = a > 0.05
    solid = m.copy()
    for _ in range(steps):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(m.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(np.roll(rgb * m[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(m, dy, 0), dx, 1)
        new = (~m) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        m = m | new
    if solid.any():
        rgb[~m] = rgb[solid].mean(axis=0)
    out = img.copy()
    out[..., :3] = rgb
    return out


def bark_strip(rgb, seed):
    """Смуга кори 32×256: поздовжні тріщини й плями ~5–20 см (на стовбурі 0,2–0,6 м завширшки)."""
    rng = np.random.default_rng(seed)
    h, w = 256, STRIP_W
    col = rng.normal(0, 1, (1, w))
    col = np.convolve(np.pad(col[0], 2, mode="wrap"), np.ones(3) / 3, "valid")[1:-1][None, :]
    rows = np.cumsum(rng.normal(0, 0.15, (h, 1)), 0)
    n = 0.10 * col + 0.04 * np.sin(rows) + rng.normal(0, 0.03, (h, w))
    out = np.ones((h, w, 4))
    out[..., :3] = np.clip(np.array(rgb)[None, None, :] * (1 + n[..., None]), 0, 1)
    return out


def litter_sprite(seed):
    """Пляма підстилки й тіні під кущем: темна бура, рваний край (alpha-cut, без напівпрозорості)."""
    rng = np.random.default_rng(seed)
    n = CELL
    img = np.zeros((n, n, 4))
    noise = rng.normal(0, 1, (n // 8, n // 8))
    noise = np.asarray(Image.fromarray(((noise - noise.min()) / np.ptp(noise) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
    img[..., :3] = np.array([0.24, 0.21, 0.18])[None, None, :] * (0.8 + 0.4 * noise[..., None])
    img[..., 3] = 1.0
    img = soft_edge(img, seed)
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n * 2 - 1
    # Край рідшає плямами: у середині суцільно, до краю — клапті.
    img[..., 3] = (img[..., 3] * (1.15 - np.hypot(xx, yy) * 0.75) > 0.3 + 0.55 * noise).astype(float)
    return img


def main():
    n = SIZE // CELL
    atlas = np.zeros((SIZE, SIZE, 4))
    free = np.ones((n, n), bool)
    rects = {"sprites": {}, "bark": {}}

    def take(w, h):
        for r in range(n - h + 1):
            for c in range(n - w + 1):
                if free[r:r + h, c:c + w].all():
                    free[r:r + h, c:c + w] = False
                    return r * CELL, c * CELL
        raise SystemExit("атлас переповнений")

    def uv(x, y, w, h):
        return [x / SIZE, y / SIZE, w / SIZE, h / SIZE]

    seed = 0
    for kind in GROUPS[GROUP]:
        files = sorted(glob.glob(os.path.join(SRC, "%s_%s" % (kind, SEASON), "sprite_*.png")))
        if not files:
            raise SystemExit("нема спрайтів %s_%s" % (kind, SEASON))
        rects["sprites"][kind] = []
        for f in files:
            img = load(f)
            seed += 1
            if kind in SHEAF:
                img = side_edge(resize(img, CELL, 2 * CELL))
                y, x = take(1, 2)
                h = 2 * CELL
            else:
                img = soft_edge(resize(img, CELL, CELL), seed)
                y, x = take(1, 1)
                h = CELL
            atlas[y:y + h, x:x + CELL] = premul_dilate(img)
            rects["sprites"][kind].append(uv(x, y, CELL, h))
    y, x = take(1, 1)
    atlas[y:y + CELL, x:x + CELL] = premul_dilate(litter_sprite(99))
    rects["sprites"]["litter"] = [uv(x, y, CELL, CELL)]
    woody = [k for k in GROUPS[GROUP] if k not in SHEAF] + ["wood"]
    for i, kind in enumerate(woody):
        if i % (CELL // STRIP_W) == 0:
            block = take(1, 2)
        y, x = block[0], block[1] + (i % (CELL // STRIP_W)) * STRIP_W
        atlas[y:y + 256, x:x + STRIP_W] = bark_strip(BARK[kind], i)
        rects["bark"][kind] = uv(x, y, STRIP_W, 256)
    os.makedirs(OUT, exist_ok=True)
    name = "%s_veg_%s" % (GROUP, SEASON)
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    json.dump(rects, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    print("atlas", name, "cells used", int((~free).sum()), "of", n * n)


main()
