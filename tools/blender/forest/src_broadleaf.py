"""Джерело листяних дерев і кущів: процедурна будова (стовбур, скелетні гілки, картки пучків)
і смуга кори. Звичайний python, без Blender:
  python3 -I src_broadleaf.py <вихід>
Пише <вихід>/<тег>/cards.json і trunk.png для кожного виду з VARIANTS — у тому самому
форматі, що й src_conifer.py, тож build_library.py збирає їх однаково.

Скелетні гілки — геометрія, бо на голому дереві пізньої осені саме вони тримають обрис
крони, а берізку від інших відрізняє білий стовбур, видимий у будь-який сезон.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

OUT = sys.argv[1]

# h — висота, cb — низ крони, w — діаметр крони (м); limbs — кількість скелетних гілок,
# rise — кут гілки від вертикалі (°), leader — частка крони, куди доходить стовбур,
# cards — карток пучків, r — радіус стовбура біля землі, shape — форма крони:
# egg (яйце, береза), dome (купол, дуб), column (колона, тополя).
VARIANTS = {
    "birch_a": dict(h=18.0, cb=7.5, w=5.0, limbs=5, rise=32, leader=0.85, cards=34, r=0.16, shape="egg", bark="birch", seed=11),
    "birch_b": dict(h=16.0, cb=6.0, w=5.5, limbs=5, rise=36, leader=0.8, cards=32, r=0.15, shape="egg", bark="birch", seed=12),
    "oak_a": dict(h=20.0, cb=6.5, w=9.5, limbs=5, rise=58, leader=0.3, cards=40, r=0.30, shape="dome", bark="oak", seed=21),
    "oak_b": dict(h=19.0, cb=5.5, w=8.5, limbs=5, rise=50, leader=0.45, cards=38, r=0.27, shape="dome", bark="oak", seed=22),
    "hero_oak": dict(sec=1, h=19.0, cb=3.6, w=15.0, limbs=7, rise=62, leader=0.3, cards=85, r=0.45, shape="dome", bark="oak", seed=31),
    "hero_lime": dict(sec=1, h=20.0, cb=3.2, w=12.0, limbs=7, rise=42, leader=0.6, cards=85, r=0.38, shape="egg", bark="lime", seed=32),
    "hero_birch": dict(sec=2, h=17.0, cb=4.0, w=6.0, limbs=6, rise=30, leader=0.88, cards=60, r=0.2, shape="egg", bark="birch", seed=33),
    "hero_poplar": dict(sec=1, h=25.0, cb=2.5, w=4.5, limbs=8, rise=14, leader=0.92, cards=70, r=0.32, shape="column", bark="lime", seed=34),
    # Кущі: кілька стебел від землі, без стовбура.
    "shrub_hazel": dict(h=4.2, cb=0.6, w=4.0, limbs=5, rise=30, leader=0.0, cards=14, r=0.0, shape="egg", bark="lime", seed=41, stems=True),
    "shrub_thorn": dict(h=2.8, cb=0.3, w=3.2, limbs=4, rise=40, leader=0.0, cards=11, r=0.0, shape="dome", bark="oak", seed=42, stems=True),
}


def envelope(p, v):
    """Радіус крони на висоті z (від низу крони) для форми виду."""
    top = v["h"] - v["cb"]
    t = np.clip((p - v["cb"]) / top, 0, 1)
    R = v["w"] / 2
    if v["shape"] == "dome":
        return R * np.sqrt(np.clip(1 - ((t - 0.35) / 0.65) ** 2, 0, 1)) * (0.85 + 0.15 * (t < 0.35))
    if v["shape"] == "column":
        return R * np.clip(np.sin(np.pi * np.clip(t * 1.05, 0, 1)) ** 0.5, 0, 1)
    return R * np.sqrt(np.clip(np.sin(np.pi * t), 0, 1))


def build(tag, v):
    rng = np.random.default_rng(v["seed"])
    top = v["h"]
    cb = v["cb"]
    limbs = []
    tips = []
    for i in range(v["limbs"]):
        az = 2 * math.pi * i / v["limbs"] + rng.uniform(-0.4, 0.4)
        h0 = (rng.uniform(0.0, 0.25) if v.get("stems") else cb + rng.uniform(0.0, 0.35) * (top - cb))
        rise = math.radians(v["rise"] * rng.uniform(0.8, 1.2))
        # Довжина — до обрису крони: гілка закінчується там, де починаються пучки.
        pts = [np.array([0.0, 0.0, h0])]
        d = np.array([math.sin(rise) * math.cos(az), math.sin(rise) * math.sin(az), math.cos(rise)])
        for k in range(3):
            step = (v["w"] / 2) / math.sin(max(rise, 0.3)) * 0.36 if v["shape"] != "column" else (top - h0) / 3.4
            nxt = pts[-1] + d * step
            r_env = float(envelope(np.array(nxt[2]), v))
            if math.hypot(nxt[0], nxt[1]) > r_env * 0.85 and k:
                break
            pts.append(nxt)
            d = d + rng.normal(0, 0.15, 3) + np.array([0, 0, 0.12 if v["shape"] != "dome" else -0.02])
            d /= np.linalg.norm(d)
        base_r = max(v["r"] * 0.45, 0.05) if not v.get("stems") else 0.05
        radii = [base_r * (1 - 0.6 * j / max(len(pts) - 1, 1)) for j in range(len(pts))]
        limbs.append({"pts": [p.round(3).tolist() for p in pts], "r": [round(r, 3) for r in radii], "sides": 3})
        tips.append(pts[-1])
    # Другорядні гілки: на голому дереві саме вони роблять крону деревом, а не віником.
    for lm in list(limbs[:v["limbs"]]):
        pts = [np.array(p) for p in lm["pts"]]
        if len(pts) < 2:
            continue
        for j in range(v.get("sec", 0)):
            t = rng.uniform(0.45, 0.85)
            k = min(int(t * (len(pts) - 1)), len(pts) - 2)
            b = pts[k] + (pts[k + 1] - pts[k]) * (t * (len(pts) - 1) - k)
            ld = (pts[-1] - pts[0]) / max(np.linalg.norm(pts[-1] - pts[0]), 1e-3)
            side = np.cross(ld, [0, 0, 1])
            side /= max(np.linalg.norm(side), 1e-3)
            d = ld + side * rng.choice([-1, 1]) * rng.uniform(0.5, 0.9) + np.array([0, 0, 0.25])
            d /= np.linalg.norm(d)
            ln = np.linalg.norm(pts[-1] - pts[0]) * rng.uniform(0.35, 0.5)
            m = b + d * ln * 0.55
            e = m + (d + rng.normal(0, 0.2, 3) + np.array([0, 0, 0.15])) / 1.2 * ln * 0.45
            r0 = lm["r"][k] * 0.55
            limbs.append({"pts": [b.round(3).tolist(), m.round(3).tolist(), e.round(3).tolist()],
                          "r": [round(r0, 3), round(r0 * 0.7, 3), round(r0 * 0.4, 3)], "sides": 3})
    # Пучки сидять на зовнішній половині гілок: картка без гілки під нею висить у повітрі.
    anchors = []
    for lm in limbs:
        pts = [np.array(p) for p in lm["pts"]]
        for k in range(len(pts) - 1):
            for t in np.linspace(0, 1, 4, endpoint=False):
                anchors.append(pts[k] + (pts[k + 1] - pts[k]) * t)
        anchors.append(pts[-1])
    anchors = np.array(anchors)
    outer = np.hypot(anchors[:, 0], anchors[:, 1]) + np.maximum(anchors[:, 2] - cb, 0) * 0.3
    anchors = anchors[outer >= np.percentile(outer, 35)]
    cards = []
    n = v["cards"]
    zc = (cb + top) / 2
    tries = 0
    while len(cards) < n and tries < n * 300:
        tries += 1
        if len(cards) % 5 < 3:
            a = anchors[rng.integers(len(anchors))]
            p = a + rng.normal(0, 0.45, 3) + np.array([0, 0, 0.3])
        else:
            # Частина пучків — на поверхні обрису: інакше широка крона розпадається на
            # купки на кінцях гілок і читається парасолькою.
            z = rng.uniform(cb + 0.5, top - 0.3)
            R = float(envelope(np.array(z), v))
            az = rng.uniform(0, 2 * math.pi)
            rr = R * rng.uniform(0.6, 0.95)
            p = np.array([rr * math.cos(az), rr * math.sin(az), z])
        z = p[2]
        R = float(envelope(np.array(z), v))
        if math.hypot(p[0], p[1]) > R * 1.05 + 0.3 or z > top or z < 0.3:
            continue
        if any(np.linalg.norm(p - np.array(c["c"])) < 0.9 for c in cards):
            continue
        rr = math.hypot(p[0], p[1])
        out = np.array([p[0], p[1], (z - zc) * 0.6])
        out /= max(np.linalg.norm(out), 1e-3)
        hfrac = float(np.clip((z - cb) / (top - cb), 0, 1))
        d = out * 0.8 + np.array([0, 0, 0.3 + 0.25 * hfrac]) + rng.normal(0, 0.25, 3)
        d /= np.linalg.norm(d)
        shade = 0.55 + 0.25 * min(1.0, rr / max(R, 1e-3)) + 0.2 * hfrac
        cards.append({"c": p.round(3).tolist(), "n": d.round(3).tolist(), "roll": float(rng.uniform(0, 6.283)),
                      "size": round(float(rng.uniform(2.0, 2.7) * (0.75 if v.get("stems") else 1.0)), 3),
                      "shade": round(min(shade, 1.0), 3)})
    th = max(cb + v["leader"] * (top - cb), 1.0)
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    trunk_png(os.path.join(d, "trunk.png"), v["bark"], th, rng)
    meta = {"tag": tag, "source": "procedural", "cards": cards, "limbs": limbs, "crown_base": cb, "top": top,
            "trunk_width": v["r"] * 2 / 0.6, "trunk_render_height": th, "leader_top": th}
    json.dump(meta, open(os.path.join(d, "cards.json"), "w"), indent=1)
    print("TREE", tag, "cards", len(cards), "limbs", len(limbs))


def trunk_png(path, kind, height, rng):
    """Кора на висоту стовбура: 128×1024, низ кадру — земля."""
    H, W = 1024, 128
    y = np.linspace(1, 0, H)[:, None]  # 1 — верх
    noise = np.asarray(Image.fromarray((rng.random((H // 8, W // 4)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
    fine = rng.random((H, W))
    if kind == "birch":
        base = np.array([0.80, 0.79, 0.74])
        img = np.ones((H, W, 3)) * base * (0.9 + 0.1 * noise[..., None])
        # Горизонтальні чечевички й темні латки — ознака берези, видна з 45°.
        for _ in range(int(220 * height / 15)):
            yy, xx = rng.integers(0, H), rng.integers(0, W)
            ln, th = rng.integers(6, 30), rng.integers(1, 3)
            img[yy:yy + th, max(xx - ln // 2, 0):xx + ln // 2] *= 0.25
        for _ in range(int(25 * height / 15)):
            yy, xx = rng.integers(0, H), rng.integers(0, W)
            r = rng.integers(4, 12)
            img[max(yy - r, 0):yy + r, max(xx - r, 0):xx + r] *= 0.35
        low = (1 - y) < (2.2 / height) * (0.8 + 0.4 * noise)  # нижні метри — темна тріщинувата кора
        img[low] = img[low] * 0.3
    else:
        base = {"oak": np.array([0.33, 0.31, 0.28]), "lime": np.array([0.36, 0.34, 0.31])}[kind]
        furrow = np.asarray(Image.fromarray((rng.random((H // 64, W // 6)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
        img = base * (0.65 + 0.45 * furrow[..., None]) * (0.92 + 0.08 * fine[..., None])
    a = np.ones((H, W, 1))
    im = Image.fromarray((np.dstack([np.clip(img, 0, 1), a]) * 255).astype(np.uint8), "RGBA")
    im.filter(ImageFilter.SMOOTH).save(path)


def log(tag, length, r, seed):
    """Повалений стовбур: лежить уздовж x, трохи вигнутий, із двома обламаними сучками."""
    rng = np.random.default_rng(seed)
    pts = [[-length / 2 + length * k / 3, rng.normal(0, 0.12), r] for k in range(4)]
    limbs = [{"pts": pts, "r": [r * 1.1, r, r * 0.85, r * 0.7], "sides": 5}]
    for k in (1, 2):
        b = np.array(pts[k])
        d = np.array([rng.uniform(-0.3, 0.3), rng.choice([-1, 1]) * 0.7, 0.7])
        limbs.append({"pts": [b.tolist(), (b + d * rng.uniform(0.8, 1.4)).tolist()], "r": [r * 0.35, r * 0.2], "sides": 3})
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    trunk_png(os.path.join(d, "trunk.png"), "oak", length, rng)
    meta = {"tag": tag, "source": "procedural", "cards": [], "limbs": limbs, "crown_base": 0.0, "top": 2 * r,
            "trunk_width": 2 * r, "trunk_render_height": length}
    json.dump(meta, open(os.path.join(d, "cards.json"), "w"), indent=1)
    print("LOG", tag)


for tag, v in VARIANTS.items():
    build(tag, v)
log("log_a", 6.5, 0.22, 51)
log("log_b", 4.5, 0.17, 52)
