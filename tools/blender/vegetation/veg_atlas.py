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
# Дерева, чия гола крона пізньої пори — ще й картки дрібного гілля (<вид>_bare). Джерело — ті самі
# спрайти голого гілля, що й у пізнього лісу (forest/src_leaf_sprites.py, кадр 2,4 м), з тим самим
# тоном (forest/specs/broadleaf_late.json): сіро-буре гілля однакове в лісі й на луці. Спрайти лісу
# лежать поза репозиторієм; тека — $FOREST_SPRITES (типово ~/.cache/ap-scratch/forest/crowns).
BARE = {"apple": "broad_late", "cherry": "broad_late", "walnut": "broad_late", "pear": "broad_late",
        "oak": "oak_late", "wwillow": "broad_late"}
FOREST_SPRITES = os.environ.get("FOREST_SPRITES", os.path.expanduser("~/.cache/ap-scratch/forest/crowns"))
BARE_GRADE = {"L": 26, "C": 3, "h": 55, "contrast_l": 0.6}
BARE_N = 4
# Вільха в спрайтах темніша за верболіз і ґрунт поруч (медіана кадру 52–80 проти 97 у верби): підсилення
# тону листя й гілок за порою, щоб крона сиділа в одному ряду з іншими видами.
GAIN = {"alder": {"summer": 1.8, "early": 1.65, "late": 1.3}}
# Кора (sRGB): середній тон і розкид світлих смуг. Темніша за листя, як у лісі.
# Не темніша за ~0,33: з тоном кори в кадрі стовбур і гілки виходили майже чорними.
# dead — сіро-бура деревина зім'ятих кущів і хмизу повалених дерев, однакова для всіх видів.
BARK = {"willow": (0.32, 0.28, 0.20), "alder": (0.34, 0.31, 0.27), "apple": (0.33, 0.29, 0.25),
        "cherry": (0.36, 0.29, 0.24), "walnut": (0.27, 0.22, 0.17), "lilac": (0.36, 0.34, 0.31),
        "elder": (0.31, 0.27, 0.21), "berry": (0.38, 0.28, 0.21), "thuja": (0.36, 0.26, 0.20),
        "hawthorn": (0.36, 0.32, 0.27), "dogrose": (0.36, 0.28, 0.21), "pear": (0.35, 0.29, 0.23),
        "oak": (0.36, 0.30, 0.23), "wwillow": (0.31, 0.27, 0.21), "dead": (0.36, 0.31, 0.25)}


def srgb_to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def lab_grade(img, g):
    """Середні L*, C* і тон h непрозорого — до цілі, розкид L* × contrast_l (як forest/make_atlas.py)."""
    m = img[..., 3] > 0.5
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    wp = np.array([0.95047, 1.0, 1.08883])
    xyz = srgb_to_lin(img[..., :3]) @ M.T / wp
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    L, a, b = 116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])
    L = g["L"] + (L - L[m].mean()) * g["contrast_l"]
    C, h = np.hypot(a, b), np.arctan2(b, a)
    h = h + (np.radians(g["h"]) - np.arctan2(b[m].mean(), a[m].mean()))
    C = C * (g["C"] / max(float(C[m].mean()), 1e-3))
    a, b = C * np.cos(h), C * np.sin(h)
    fy = (L + 16) / 116
    f = np.stack([fy + a / 500, fy, fy - b / 200], -1)
    xyz = np.where(f > 0.2069, f ** 3, (f - 16 / 116) / 7.787) * wp
    Mi = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    out = img.copy()
    out[..., :3] = lin_to_srgb(xyz @ Mi.T)
    return out


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
    """Маска плями затінення під кущем чи купою: м'який край, неправильна форма, усередині
    плямиста. Колір не потрібен — veg_shade.gdshader бере лише альфу й множить на неї ґрунт."""
    rng = np.random.default_rng(seed)
    n = CELL
    yy, xx = (np.mgrid[0:n, 0:n] + 0.5) / n * 2 - 1
    ang = np.arctan2(yy, xx)
    wob = sum(rng.uniform(0.05, 0.12) * np.sin(k * ang + rng.uniform(0, 6.3)) for k in (2, 3, 5))
    r = np.hypot(xx, yy) / (0.8 + wob)
    noise = rng.normal(0, 1, (n // 16, n // 16))
    noise = np.asarray(Image.fromarray(((noise - noise.min()) / np.ptp(noise) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
    img = np.zeros((n, n, 4))
    img[..., :3] = 0.5
    img[..., 3] = np.clip(1.0 - r, 0, 1) ** 1.5 * (0.7 + 0.3 * noise)
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

    # Смуги кори — першими: їм потрібні дві клітинки одна над одною, а після спрайтів вільні
    # клітинки вже розкидані поодинці.
    woody = [k for k in GROUPS[GROUP] if k not in SHEAF] + ["dead"]
    for i, kind in enumerate(woody):
        if i % (CELL // STRIP_W) == 0:
            block = take(1, 2)
        y, x = block[0], block[1] + (i % (CELL // STRIP_W)) * STRIP_W
        atlas[y:y + 256, x:x + STRIP_W] = bark_strip(BARK[kind], i)
        rects["bark"][kind] = uv(x, y, STRIP_W, 256)
    seed = 0
    sets = [(k, k, SEASON) for k in GROUPS[GROUP]]
    if SEASON == "late":
        sets += [(k + "_bare", k, "bare") for k in GROUPS[GROUP] if k in BARE]
    for key, kind, season in sets:
        if season == "bare":
            files = sorted(glob.glob(os.path.join(FOREST_SPRITES, BARE[kind], "sprite_*.png")))[:BARE_N]
        else:
            files = sorted(glob.glob(os.path.join(SRC, "%s_%s" % (kind, season), "sprite_*.png")))
        if not files:
            raise SystemExit("нема спрайтів для %s (%s)" % (key, season))
        rects["sprites"][key] = []
        for f in files:
            img = load(f)
            g = GAIN.get(kind, {}).get(season)
            if g:
                # Підсилення тону з розтягом контрасту навколо нового середнього: просте множення
                # пригнічувало різницю між листям і темним гіллям усередині куща.
                mk = img[..., 3] > 0.5
                new = img[..., :3] * g
                mu = new[mk].mean()
                img[..., :3] = np.clip(mu + (new - mu) * 2.8, 0, 1)
            seed += 1
            if kind in SHEAF:
                img = side_edge(resize(img, CELL, 2 * CELL))
                y, x = take(1, 2)
                h = 2 * CELL
            else:
                img = soft_edge(resize(img, CELL, CELL), seed)
                if season == "bare":
                    img = lab_grade(img, BARE_GRADE)
                y, x = take(1, 1)
                h = CELL
            atlas[y:y + h, x:x + CELL] = premul_dilate(img)
            rects["sprites"][key].append(uv(x, y, CELL, h))
    y, x = take(1, 1)
    atlas[y:y + CELL, x:x + CELL] = premul_dilate(litter_sprite(99))
    rects["sprites"]["litter"] = [uv(x, y, CELL, CELL)]
    os.makedirs(OUT, exist_ok=True)
    name = "%s_veg_%s" % (GROUP, SEASON)
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    json.dump(rects, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    print("atlas", name, "cells used", int((~free).sum()), "of", n * n)


main()
