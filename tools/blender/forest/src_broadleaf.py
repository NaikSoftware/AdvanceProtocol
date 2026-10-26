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
    "hero_oak": dict(low_limbs=3, sec=2, ter=1, lobes=9, lobe_r=2.9, h=19.0, cb=8.9, w=15.0, limbs=7, rise=62, leader=0.3, cards=820, r=0.45, shape="dome", bark="oak", seed=31),
    "hero_lime": dict(low_limbs=3, sec=2, ter=1, lobes=9, lobe_r=2.6, h=20.0, cb=11.4, w=12.0, limbs=7, rise=42, leader=0.6, cards=780, r=0.38, shape="egg", bark="lime", seed=32),
    "hero_birch": dict(low_limbs=3, sec=2, ter=1, lobes=8, lobe_r=1.6, spacing=0.8, h=17.0, cb=10.2, w=6.0, limbs=6, rise=30, leader=0.88, cards=230, r=0.2, shape="egg", bark="birch", seed=33),
    "hero_poplar": dict(low_limbs=3, sec=1, ter=1, lobes=9, lobe_r=1.5, spacing=0.45, h=25.0, cb=13.0, w=4.5, limbs=8, rise=14, leader=0.92, cards=660, r=0.32, shape="column", bark="lime", seed=34),
    # Пізня осінь: та сама будова, але з другорядними й третинними гілками — голу крону
    # тримає гілля, а не пучки (тих лишається третина).
    "birch_a_bare": dict(sec=1, ter=1, h=18.0, cb=7.5, w=5.0, limbs=5, rise=32, leader=0.85, cards=34, r=0.16, shape="egg", bark="birch", seed=11),
    "birch_b_bare": dict(sec=1, ter=1, h=16.0, cb=6.0, w=5.5, limbs=5, rise=36, leader=0.8, cards=32, r=0.15, shape="egg", bark="birch", seed=12),
    "oak_a_bare": dict(sec=1, ter=1, h=20.0, cb=6.5, w=9.5, limbs=5, rise=58, leader=0.3, cards=40, r=0.30, shape="dome", bark="oak", seed=21),
    "oak_b_bare": dict(sec=1, ter=1, h=19.0, cb=5.5, w=8.5, limbs=5, rise=50, leader=0.45, cards=38, r=0.27, shape="dome", bark="oak", seed=22),
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
        radii[-1] = min(radii[-1], 0.04)
        limbs.append({"pts": [p.round(3).tolist() for p in pts], "r": [round(r, 3) for r in radii], "sides": 3})
        tips.append(pts[-1])
    # Другорядні й третинні гілки: на голому дереві саме вони роблять крону деревом, а не
    # віником із кількох палиць.
    secondary = branch_out(limbs[:v["limbs"]], v.get("sec", 0), rng, 0.35, 0.5)
    limbs += secondary + branch_out(secondary, v.get("ter", 0), rng, 0.45, 0.6)
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
    if v.get("lobes"):
        cards = lobe_cards(v, limbs, rng)
        # Пучок на кінці кожної гілки: гілка, що виходить за лопать, інакше стирчить із
        # крони голим сірим сучком.
        for lm in limbs[v["limbs"]:]:
            e = np.array(lm["pts"][-1])
            cards.append({"c": e.round(3).tolist(), "n": [0, 0, 1], "roll": float(rng.uniform(0, 6.283)),
                          "size": round(float(rng.uniform(1.4, 1.8)), 3), "shade": 0.8})
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
    # Видимі гілки під кроною поодинокого дерева: від стовбура нижче крони навскіс угору до її
    # низу — інакше крона на голому стовбурі читається грибом на паличці. Окреме зерно: пучки
    # і решта дерев не змінюються.
    lr = np.random.default_rng(v["seed"] + 1000)
    for j in range(v.get("low_limbs", 0)):
        az = 2 * math.pi * j / v["low_limbs"] + lr.uniform(-0.5, 0.5)
        h0 = cb * lr.uniform(0.6, 0.8)
        reach = v["w"] * lr.uniform(0.22, 0.3)
        d = np.array([math.cos(az), math.sin(az), 0.0])
        pts = [np.array([0.0, 0.0, h0]), d * reach * 0.5 + np.array([0, 0, h0 + (cb - h0) * 0.7]),
               d * reach + np.array([0, 0, cb + 0.8])]
        r0 = v["r"] * 0.5
        limbs.append({"pts": [p.round(3).tolist() for p in pts], "r": [round(r0, 3), round(r0 * 0.6, 3), 0.04], "sides": 4})
    th = max(cb + v["leader"] * (top - cb), 1.0)
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    trunk_png(os.path.join(d, "trunk.png"), v["bark"], th, rng)
    meta = {"tag": tag, "source": "procedural", "cards": cards, "limbs": limbs, "crown_base": cb, "top": top,
            "trunk_width": v["r"] * 2 / 0.6, "trunk_render_height": th, "leader_top": th}
    json.dump(meta, open(os.path.join(d, "cards.json"), "w"), indent=1)
    print("TREE", tag, "cards", len(cards), "limbs", len(limbs))


def branch_out(parents, count, rng, len_lo, len_hi):
    """По count дочірніх гілок на кожну з parents: від середини батьківської, убік і вгору,
    два відрізки, кінець тоншає до 2 см — товстий обрубаний кінець стирчав би з крони сучком."""
    out = []
    for lm in parents:
        pts = [np.array(p) for p in lm["pts"]]
        if len(pts) < 2:
            continue
        for _ in range(count):
            t = rng.uniform(0.45, 0.85)
            k = min(int(t * (len(pts) - 1)), len(pts) - 2)
            b = pts[k] + (pts[k + 1] - pts[k]) * (t * (len(pts) - 1) - k)
            ld = (pts[-1] - pts[0]) / max(np.linalg.norm(pts[-1] - pts[0]), 1e-3)
            side = np.cross(ld, [0, 0, 1])
            side /= max(np.linalg.norm(side), 1e-3)
            d = ld + side * rng.choice([-1, 1]) * rng.uniform(0.5, 0.9) + np.array([0, 0, 0.25])
            d /= np.linalg.norm(d)
            ln = np.linalg.norm(pts[-1] - pts[0]) * rng.uniform(len_lo, len_hi)
            m = b + d * ln * 0.55
            e = m + (d + rng.normal(0, 0.2, 3) + np.array([0, 0, 0.15])) / 1.2 * ln * 0.45
            r0 = max(lm["r"][k] * 0.55, 0.03)
            out.append({"pts": [b.round(3).tolist(), m.round(3).tolist(), e.round(3).tolist()],
                        "r": [round(r0, 3), round(r0 * 0.6, 3), 0.02], "sides": 3})
    return out


def lobe_cards(v, limbs, rng):
    """Крона поодинокого дерева — 4–7 купол-лопатей на кінцях скелетних гілок, що
    перекриваються: обрис горбкуватий, як у справжнього дуба чи липи, а не рівна куля."""
    tips = np.array([lm["pts"][-1] for lm in limbs])
    order = np.argsort(-(np.hypot(tips[:, 0], tips[:, 1]) + tips[:, 2] * 0.3))
    # Лопаті різного розміру з розкидом центрів: однакові кулі на палиці читались би
    # штучно, як зліплені сніжки.
    centres = [tips[i] + rng.normal(0, 0.4, 3) + np.array([0, 0, v["lobe_r"] * 0.3]) for i in order[:v["lobes"]]]
    centres.append(np.array([0.0, 0.0, v["h"] - v["lobe_r"] * 0.9]))  # верхівка над стовбуром
    radii = [v["lobe_r"] * rng.uniform(0.7, 1.3) for _ in centres]
    top, cb = v["h"], v["cb"]
    zc = (cb + top) / 2
    cards = []
    placed = []
    tries = 0
    while len(cards) < v["cards"] and tries < v["cards"] * 60:
        tries += 1
        i = rng.integers(len(centres))
        c = centres[i]
        r = radii[i] * rng.uniform(0.9, 1.1)
        d = rng.normal(0, 1, 3)
        d[2] = abs(d[2]) * 0.8 + 0.1  # низ лопаті камера не бачить
        d /= np.linalg.norm(d)
        p = c + d * r * rng.uniform(0.55, 1.0)
        if p[2] > top or p[2] < cb + 0.5:
            continue
        if placed and np.min(np.linalg.norm(np.array(placed) - p, axis=1)) < v.get("spacing", 0.6):
            continue
        placed.append(p)
        hfrac = float(np.clip((p[2] - cb) / (top - cb), 0, 1))
        out = np.array([p[0], p[1], (p[2] - zc) * 0.6])
        out /= max(np.linalg.norm(out), 1e-3)
        cards.append({"c": p.round(3).tolist(), "n": out.round(3).tolist(), "roll": float(rng.uniform(0, 6.283)),
                      "size": round(float(rng.uniform(1.8, 2.4)), 3),
                      "shade": round(min(0.55 + 0.25 * float(np.linalg.norm(p - c) / r) + 0.2 * hfrac, 1.0), 3)})
    return cards


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
        for _ in range(int(360 * height / 15)):
            yy, xx = rng.integers(0, H), rng.integers(0, W)
            ln, th = rng.integers(8, 40), rng.integers(1, 4)
            img[yy:yy + th, max(xx - ln // 2, 0):xx + ln // 2] *= 0.2
        # Чорні латки під гілками й поперечні смуги — з них березу видно з 45°, а не лише
        # білу паличку.
        for _ in range(int(60 * height / 15)):
            yy, xx = rng.integers(0, H), rng.integers(0, W)
            r = rng.integers(6, 20)
            img[max(yy - r // 2, 0):yy + r // 2, max(xx - r, 0):xx + r] *= 0.15
        low = (1 - y) < (3.0 / height) * (0.8 + 0.4 * noise)  # нижні метри — темна тріщинувата кора
        img[low] = img[low] * 0.25
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
        # Сучки — убік і лише трохи вгору: стовбур на проламаній клітинці лежить під
        # корпусом, і сучок угору простромив би його.
        d = np.array([rng.uniform(-0.3, 0.3), rng.choice([-1, 1]) * 0.95, 0.25])
        limbs.append({"pts": [b.tolist(), (b + d * rng.uniform(0.8, 1.4)).tolist()], "r": [r * 0.35, r * 0.2], "sides": 3})
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    trunk_png(os.path.join(d, "trunk.png"), "oak", length, rng)
    meta = {"tag": tag, "source": "procedural", "cards": [], "limbs": limbs, "crown_base": 0.0, "top": 2 * r,
            "trunk_width": 2 * r, "trunk_render_height": length}
    json.dump(meta, open(os.path.join(d, "cards.json"), "w"), indent=1)
    print("LOG", tag)


def hedge(tag, evergreen, seed):
    """Смуга узлісся на одну сторону клітинки: 8 м уздовж x, 2,8 м углиб, 2–4 м заввишки.

    Три ряди карток уступами, щільно, без просвітів між кущами: дошка ставить такий шматок
    на кожну сторону крайової клітинки, що дивиться в поле, і край стоїть стіною, а смуга
    дерев в одну клітинку стає живоплотом. Окремі кущі на узліссі читались би горошинами
    з травою між ними. Ялинник (evergreen) звужується догори, як молоді ялини.
    """
    rng = np.random.default_rng(seed)
    cards = []
    layers = [(0.75, 1.0), (1.6, 0.85), (2.5, 0.6)] if evergreen else [(0.7, 1.0), (1.5, 0.9), (2.3, 0.55)]
    for z, keep in layers:
        for row, y in enumerate((-1.0, 0.0, 1.0)):
            x = -4.0 + (0.45 if row % 2 else 0.0)
            while x < 4.0:
                if rng.random() < keep:
                    c = [x + rng.normal(0, 0.15), y + rng.normal(0, 0.2), z + rng.normal(0, 0.15)]
                    cards.append({"c": [round(q, 3) for q in c], "n": [0, 0, 1], "roll": float(rng.uniform(0, 6.283)),
                                  "size": round(float(rng.uniform(1.2, 1.6)), 3),
                                  "shade": round(0.7 + 0.1 * z / 2.5 + 0.1 * (y > 0), 3)})
                x += 0.9
    limbs = []
    if not evergreen:
        for _ in range(6):  # кілька стебел, видимих крізь голий кущ
            b = np.array([rng.uniform(-3.5, 3.5), rng.uniform(-0.8, 0.8), 0.0])
            e = b + np.array([rng.normal(0, 0.4), rng.normal(0, 0.3), rng.uniform(2.0, 3.0)])
            limbs.append({"pts": [b.round(3).tolist(), e.round(3).tolist()], "r": [0.04, 0.015], "sides": 3})
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    trunk_png(os.path.join(d, "trunk.png"), "lime", 3.0, rng)
    meta = {"tag": tag, "source": "procedural", "cards": cards, "limbs": limbs, "crown_base": 0.0, "top": 3.2,
            "trunk_width": 0.1, "trunk_render_height": 3.0, "centre": [0, 0, 1.4], "radii": [4.5, 1.6, 1.8]}
    json.dump(meta, open(os.path.join(d, "cards.json"), "w"), indent=1)
    print("HEDGE", tag, "cards", len(cards))


def litter(tag, seed):
    """Повалений ліс на клітинці, яку проломив танк: плоскі картки гілля на землі, без
    стоячих крон. Стовбури кладе дошка окремо (Log_*)."""
    rng = np.random.default_rng(seed)
    flats = []
    for _ in range(14):
        c = [rng.uniform(-3.4, 3.4), rng.uniform(-3.4, 3.4), round(float(rng.uniform(0.03, 0.12)), 3)]
        flats.append({"c": [round(q, 3) for q in c], "roll": float(rng.uniform(0, 6.283)),
                      "size": round(float(rng.uniform(1.6, 2.6)), 3), "shade": round(float(rng.uniform(0.7, 0.9)), 3)})
    d = os.path.join(OUT, tag)
    os.makedirs(d, exist_ok=True)
    trunk_png(os.path.join(d, "trunk.png"), "oak", 3.0, rng)
    meta = {"tag": tag, "source": "procedural", "cards": [], "flats": flats, "limbs": [], "crown_base": 0.0,
            "top": 0.2, "trunk_width": 0.1, "trunk_render_height": 3.0}
    json.dump(meta, open(os.path.join(d, "cards.json"), "w"), indent=1)
    print("LITTER", tag, "flats", len(flats))


for tag, v in VARIANTS.items():
    build(tag, v)
hedge("hedge_spruce", True, 61)
hedge("hedge_shrub", False, 62)
litter("litter_a", 71)
log("log_a", 6.5, 0.22, 51)
log("log_b", 4.5, 0.17, 52)
