"""Збирає атласи лісу: з відрендерених крон хвої й атласів листяних крон (agy).

Запуск (звичайний python, не Blender):
  python3 -I make_textures.py <art-refs/forest> <вихід>
Читає у <art-refs/forest>: crowns/crown_*.png, sprites/*.png, broadleaf_{late,summer,early}.png
(сирий результат генератора), пише <вихід>/atlas_<тип>[_<сезон>].png 1280x1280 RGBA та
<вихід>/crowns.json. Розкладка атласу: три вікна кроною 10x10 м по 640 px (чверті 0, 1, 2),
четверта чверть — аркуш 640 px із клітинками по 320 px (кора, кора, береза, кущ).
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
CELL = 640
WIN_M = 10.0
PXM = CELL / WIN_M  # 64 px/м = 1,56 см/піксель
SRC_PXM = 128.0  # крони хвої й листяні атласи мають 128 px/м
THIS = os.path.dirname(os.path.abspath(__file__))

# Середня яскравість непрозорих пікселів (лінійна), під настрій: L* 24 — 40.
TARGET_Y = {"pine": 0.028, "late": 0.060, "summer": 0.070, "early": 0.12}


def srgb_to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def grade(im, target_y):
    """Масштабує лінійну яскравість так, щоб середнє по непрозорих пікселях дало target_y."""
    a = np.asarray(im).astype(np.float32) / 255.0
    lin = srgb_to_lin(a[..., :3])
    y = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    m = a[..., 3] > 0.5
    k = float(np.clip(target_y / max(y[m].mean(), 1e-4), 0.25, 3.0)) if m.any() else 1.0
    out = np.dstack([lin_to_srgb(lin * k), a[..., 3]])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def desaturate(im, k):
    """Рання осінь від генератора надто яскрава для похмурого настрою: k < 1 приглушує колір."""
    if k == 1.0:
        return im
    a = np.asarray(im).astype(np.float32)
    g = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    a[..., :3] = g[..., None] + (a[..., :3] - g[..., None]) * k
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def harden(im, lo=0.35, hi=0.65):
    a = np.asarray(im).astype(np.float32) / 255.0
    t = np.clip((a[..., 3] - lo) / (hi - lo), 0, 1)
    a[..., 3] = t * t * (3 - 2 * t)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")


def fill_under_alpha(im):
    """Колір прозорих пікселів = розмитий колір сусідів: мипи не дають ореолу."""
    a = np.asarray(im).astype(np.float32)
    al = a[..., 3:4] / 255.0
    pm = Image.fromarray((a[..., :3] * al).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(6))
    wm = Image.fromarray((al[..., 0] * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(6))
    pm = np.asarray(pm).astype(np.float32)
    wm = np.maximum(np.asarray(wm).astype(np.float32)[..., None] / 255.0, 1e-3)
    bg = np.clip(pm / wm, 0, 255)
    rgb = np.where(al > 0.5, a[..., :3], np.where(al > 0.02, a[..., :3], bg))
    return Image.fromarray(np.dstack([rgb, a[..., 3]]).astype(np.uint8), "RGBA")


def key_background(path, mode):
    """Сирий атлас із намальованою шахівницею замість alpha: ключ за яскравістю й насиченістю."""
    im = Image.open(path)
    if im.mode == "RGBA" and np.asarray(im)[..., 3].min() < 250:
        if mode == "late":
            a = np.asarray(im).astype(np.float32)
            a[..., :3] = np.minimum(a[..., :3], np.array([84.0, 76.0, 68.0]))  # світлі кінчики гілок
            im = Image.fromarray(a.astype(np.uint8), "RGBA")
        return im
    rgb = np.asarray(im.convert("RGB")).astype(np.float32)
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    lum = rgb.mean(axis=2)
    sat = (mx - mn) / np.maximum(mx, 1)
    if mode == "late":
        # Краї тонких гілок змішані зі світлою шахівницею: затемнення прибирає сіру крупу.
        rgb = np.minimum(rgb, np.array([84.0, 76.0, 68.0]))
    fg = np.maximum(np.clip((185 - lum) / 50, 0, 1), np.clip((sat - 0.10) / 0.12, 0, 1))
    return Image.fromarray(np.dstack([rgb, fg * 255]).astype(np.uint8), "RGBA")


def split_cells(im, season):
    """Чотири крони з атласу 2x2; для голих гілок товщає alpha — тонкі лінії не виживають у мипах."""
    w = im.width // 2
    out = []
    for k in range(4):
        c = im.crop(((k % 2) * w, (k // 2) * w, (k % 2 + 1) * w, (k // 2 + 1) * w))
        scale = 320 / w
        if scale != 1:
            c = c.resize((320, 320), Image.LANCZOS)
        al = c.getchannel("A").point(lambda v: 255 if v > 60 else 0)
        bb = al.getbbox()
        out.append(c.crop(bb))
    return out


def load_crowns():
    d = {}
    for n in ("pine_a", "pine_b", "spruce_a", "spruce_b"):
        im = Image.open(f"{SRC}/crowns/crown_{n}.png").convert("RGBA")
        bb = im.getchannel("A").point(lambda v: 255 if v > 60 else 0).getbbox()
        d[n] = im.crop(bb)
    return d


def place(canvas, crown, diameter_m, cx_m, cy_m, rng, bright):
    src_d = max(crown.size)
    s = diameter_m * PXM / src_d
    im = crown.rotate(rng.uniform(0, 360), expand=True, resample=Image.BICUBIC)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    arr[..., :3] = np.clip(arr[..., :3] * bright, 0, 255)
    im = Image.fromarray(arr.astype(np.uint8), "RGBA")
    x = int(cx_m * PXM - im.width / 2)
    y = int(cy_m * PXM - im.height / 2)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(im, (x, y))
    canvas.alpha_composite(layer)
    return {"cx": cx_m, "cy": cy_m, "r": diameter_m / 2}


def spread(rng, n, lo, hi, min_d):
    pts = []
    if n == 0:
        return pts
    for _ in range(400):
        p = (rng.uniform(lo, hi), rng.uniform(lo, hi))
        if all(math.dist(p, q) >= min_d for q in pts):
            pts.append(p)
        if len(pts) == n:
            break
    return pts


def compose(kind, season, conif, broad, rng):
    """kind: pine | mixed | deciduous. Повертає (RGBA 1024², список крон для країв)."""
    cv = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    crowns = []
    # Нижній шар: темніші крони під верхніми, щоб покриття сягало 80–90 %, а не лишалося ґратою.
    under = {"pine": (5, 0.55), "mixed": (4, 0.55), "deciduous": (0, 1.0)}[kind]
    if kind == "deciduous" and season != "late":
        under = (7, 0.6) if season == "summer" else (4, 0.6)
    pool = [conif[n] for n in ("pine_a", "pine_b")] if kind != "deciduous" else broad
    for (x, y) in spread(rng, under[0], 2.0, 8.0, 2.4):
        place(cv, rng.choice(pool), rng.uniform(5.5, 7.0), x, y, rng, under[1])
    if kind == "pine":
        for (x, y) in spread(rng, 3, 2.9, 7.1, 3.0):
            n = rng.choice(["pine_a", "pine_b"])
            c = place(cv, conif[n], rng.uniform(5.4, 6.6), x, y, rng, rng.uniform(0.9, 1.1))
            c["kind"] = "pine"
            crowns.append(c)
        for (x, y) in spread(rng, 1, 3.0, 7.0, 0):
            c = place(cv, conif[rng.choice(["spruce_a", "spruce_b"])], rng.uniform(3.6, 4.4), x, y, rng, 1.0)
            c["kind"] = "spruce"
            crowns.append(c)
    elif kind == "mixed":
        pts = spread(rng, 4, 3.0, 7.0, 3.0)
        for i, (x, y) in enumerate(pts):
            if i < 2:
                n = rng.choice(["pine_a", "pine_b"] if i == 0 else ["spruce_a", "spruce_b"])
                c = place(cv, conif[n], 5.8 if i == 0 else 4.0, x, y, rng, rng.uniform(0.9, 1.1))
                c["kind"] = "pine" if i == 0 else "spruce"
            else:
                c = place(cv, rng.choice(broad), rng.uniform(5.8, 7.2), x, y, rng, rng.uniform(0.9, 1.1))
                c["kind"] = "broad"
            crowns.append(c)
    else:
        n = 4 if season == "summer" else 3
        d = (6.4, 7.4) if season == "late" else ((7.2, 8.6) if season == "summer" else (6.2, 7.6))
        for (x, y) in spread(rng, n, 3.2, 6.8, 3.0):
            c = place(cv, rng.choice(broad), rng.uniform(*d), x, y, rng, rng.uniform(0.9, 1.1))
            c["kind"] = "broad"
            crowns.append(c)
    return cv, crowns


def scatter_patch(pieces, rng, size=320, cover=0.6):
    """Кущ: безліч шматків крон, повернутих навмання, з прозорим краєм."""
    cv = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for _ in range(80):
        p = rng.choice(pieces)
        s = rng.randint(80, 140)
        x0 = rng.randint(0, max(0, p.width - s))
        y0 = rng.randint(0, max(0, p.height - s))
        q = p.crop((x0, y0, x0 + s, y0 + s)).rotate(rng.uniform(0, 360), resample=Image.BICUBIC)
        px, py = rng.randint(20, size - s - 20), rng.randint(36, size - s - 12)
        layer = Image.new("RGBA", cv.size, (0, 0, 0, 0))
        layer.paste(q, (px, py))
        cv.alpha_composite(layer)
        if np.asarray(cv)[..., 3].mean() / 255 > cover:
            break
    # Край картки прозорий: інакше два перехресних квади дають видимий шов.
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse((10, 10, size - 10, size - 10), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(12))
    cv.putalpha(ImageChops.multiply(cv.getchannel("A"), m))
    return cv


def sprite_shrub(rng, size=320):
    cv = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    files = [f"{SRC}/sprites/fir_{i}.png" for i in range(4)]
    for _ in range(9):
        s = Image.open(rng.choice(files)).convert("RGBA")
        k = rng.uniform(120, 190) / s.height
        s = s.resize((int(s.width * k), int(s.height * k)), Image.LANCZOS)
        s = s.rotate(rng.uniform(-30, 30), expand=True, resample=Image.BICUBIC)
        layer = Image.new("RGBA", cv.size, (0, 0, 0, 0))
        layer.paste(s, (rng.randint(0, size - s.width), size - s.height - rng.randint(0, 70)))
        cv.alpha_composite(layer)
    return cv


def sheet(kind, season, pieces, bark_img, rng):
    sh = Image.new("RGBA", (640, 640), (0, 0, 0, 255))
    b = bark_img.resize((320, 320), Image.LANCZOS).convert("RGBA")
    a = np.asarray(b).astype(np.float32)
    ba = a.copy()
    ba[..., 0] *= 1.25
    ba[..., 1] *= 1.0
    ba[..., 2] *= 0.8  # Сосна: рудувато-коричнева кора
    bb = a.copy()
    bb[..., :3] = bb[..., :3].mean(axis=2, keepdims=True) * 0.85 + bb[..., :3] * 0.15  # дуб: сіра
    sh.paste(Image.fromarray(np.clip(ba, 0, 255).astype(np.uint8), "RGBA"), (0, 0))
    sh.paste(Image.fromarray(np.clip(bb, 0, 255).astype(np.uint8), "RGBA"), (320, 0))
    birch = Image.new("RGBA", (320, 320), (176, 172, 160, 255))
    d = ImageDraw.Draw(birch)
    for _ in range(120):
        x, y = rng.randint(0, 319), rng.randint(0, 319)
        w, h = rng.randint(9, 44), rng.randint(2, 6)
        d.ellipse((x, y, x + w, y + h), fill=(24, 22, 20, 255))
    sh.paste(birch, (0, 320))
    if kind == "pine":
        shrub = sprite_shrub(rng)
    else:
        shrub = scatter_patch(pieces, rng, cover=0.55)
    sh.paste(shrub, (320, 320))
    return sh


def main():
    bark_img = Image.open(f"{SRC}/bark.jpg").convert("RGB")
    conif = load_crowns()
    crowns_json = {}
    seasons = {}
    for s in ("late", "summer", "early"):
        p = f"{SRC}/broadleaf_{s}.png"
        if os.path.exists(p):
            seasons[s] = split_cells(key_background(p, s), s)
    jobs = [("pine", "pine", None)]
    for s in seasons:
        jobs += [("mixed", "mixed", s), ("deciduous", "deciduous", s)]
    for name, kind, season in jobs:
        rng = random.Random(len(name) * 131 + (ord(season[0]) if season else 7))
        broad = seasons.get(season, [])
        atlas = Image.new("RGBA", (1280, 1280), (0, 0, 0, 0))
        info = []
        for v in range(3):
            cv, cr = compose(kind, season, conif, broad, rng)
            cv = fill_under_alpha(harden(cv, 0.3, 0.65) if season == "late" else harden(cv))
            if kind == "pine":
                target = TARGET_Y["pine"]
            elif kind == "deciduous":
                target = TARGET_Y[season]
            else:
                target = (TARGET_Y["pine"] + TARGET_Y[season]) / 2
            cv = desaturate(grade(cv, target), 0.7 if season == "early" else 1.0)
            atlas.paste(cv, ((v % 2) * 640, (v // 2) * 640))
            info.append(cr)
            cov = np.asarray(cv)[..., 3].astype(np.float32).mean() / 255
            print(name, season, "cell", v, "alpha cover", round(cov, 3))
        pieces = list(conif.values()) if kind == "pine" else broad
        sh = sheet(kind, season, pieces, bark_img, rng)
        atlas.paste(sh, (640, 640))
        key = name + ("_" + season if season else "")
        atlas.save(f"{OUT}/atlas_{key}.png", optimize=True)
        crowns_json[key] = info
        if kind in ("pine", "deciduous"):  # малий файл кущів: GLB кущів не тягне весь атлас
            atlas.crop((960, 960, 1280, 1280)).save(f"{OUT}/shrub_{season or 'conifer'}.png", optimize=True)
    json.dump(crowns_json, open(f"{OUT}/crowns.json", "w"))


main()
