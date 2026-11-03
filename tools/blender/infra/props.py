"""Бетонний блок (джерсі), придорожня водопропускна труба, фермерський причіп.

Причіп: перед (дишло) уздовж +Y Blender = −Z Godot. Труба: вісь уздовж Y, два оголовки.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


def concrete(name="road_concrete", seed=61, top_z=0.8, **kw):
    return concrete_mat(name, tile=1.5, seed=seed, top_z=top_z, k=7.0, **kw)


def jersey():
    def rel(n):   # нерегулярні виколупини замість рівних смуг; дорожній бруд знизу 20 см
        return 0.55 + 0.45 * fbm(n, 9, 5, 3)
    # Старий бетон, як устої мосту поруч: темніший, патьоки з-під верху, брудна смуга від дороги внизу,
    # мох і іржа від петель. Світлий рівний сірий читався пластиковою деталькою.
    mat = concrete(top_z=0.8, relief=rel, shade=0.12, val=0.66, ground=True, band=(0.0, 0.18, 0.7), streak_k=0.8,
                   streak_len=0.45, tint=(1.07, 1.0, 0.86), moss=0.7, rust_runs=3, chips=True, size=256)  # 256 px на 1.5 м: ~0.6 см на піксель, не розмите поруч із ґрунтом
    b = B(); bm = b.bm
    # профіль «нью-джерсі» зі сколотими скосами й фасками: вертикальний низ, скіс, крутіший верх
    # низ на 8 см у ґрунті (floor=0): блок осів, а не лежить зверху
    prof = [(-.30, -.08), (.30, -.08), (.30, .17), (.20, .50), (.12, .74), (.07, .80),
            (-.07, .80), (-.12, .74), (-.20, .50), (-.30, .17)]
    rng = np.random.default_rng(7)
    rings = []
    for x in (-1.0, 1.0):
        ring = []
        for (y, z) in prof:
            dy, dz = 0.0, 0.0
            if z > 0.7 or y in (-.30, .30) and z > 0:      # сколи: верх і нижні кути зсунуто на кілька см
                dz = -rng.random() * 0.05; dy = (rng.random() - 0.5) * 0.03
            ring.append(bm.verts.new((x + (rng.random() - 0.5) * 0.01 * (1 if abs(x) > 0 else 0), y + dy, z + dz)))
        rings.append(ring)
    n = len(prof)
    for k in range(n):
        bm.faces.new([rings[0][k], rings[0][(k + 1) % n], rings[1][(k + 1) % n], rings[1][k]])
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[1])
    for f in bm.faces:
        f.material_index = b.mi(mat)
    finish(b, "infra_jersey_block", floor=0.0)


def tube(b, mat, c, ro, ri, L, n=20, inner=None):
    bm = b.bm
    y0, y1 = c[1] - L / 2, c[1] + L / 2
    ang = [2 * math.pi * k / n for k in range(n)]
    V = {key: [bm.verts.new((c[0] + r * math.cos(a), y, c[2] + r * math.sin(a))) for a in ang]
         for key, (r, y) in {"o0": (ro, y0), "o1": (ro, y1), "i0": (ri, y0), "i1": (ri, y1)}.items()}
    i = b.mi(mat); j = b.mi(inner or mat)
    for k in range(n):
        k2 = (k + 1) % n
        for q, m in (([V["o0"][k], V["o1"][k], V["o1"][k2], V["o0"][k2]], i), ([V["i0"][k], V["i0"][k2], V["i1"][k2], V["i1"][k]], j),
                     ([V["o0"][k], V["o0"][k2], V["i0"][k2], V["i0"][k]], i), ([V["o1"][k], V["i1"][k], V["i1"][k2], V["o1"][k2]], i)):
            bm.faces.new(q).material_index = m


def prof_h(y):
    """Висота насипу вздовж Y: полотно на 1,0 м з двома коліями (по 0,4 м завширшки, 14 см глибиною),
    схили до тераси 0,5 м і далі до землі. Північ і південь трохи різні."""
    if y >= 0:
        xs, hs = [0, .6, .65, .72, 1.08, 1.15, 1.25, 2.6, 4.5, 7.2, 8.6], [1, 1, 1.03, .86, .86, 1.03, 1, 1, .5, .5, 0]
    else:
        xs, hs = [0, .6, .65, .72, 1.08, 1.15, 1.25, 2.6, 4.4, 7.0, 8.4], [1, 1, 1.03, .86, .86, 1.03, 1, 1, .55, .45, 0]
    return float(np.interp(abs(y), xs, hs))


def carve(x, y, h):
    """Канава від кожного оголовка вздовж осі труби: пласке дно ~1 м, схили по 0,5 м; дно сходить до землі."""
    a = abs(y)
    if a < 4.3:
        return h
    v = float(np.clip((1.5 - abs(x)) / 0.5, 0, 1))             # 1 на дні, 0 за бровкою
    return h * (1 - v) + 0.04 * v                              # дно трохи над землею дошки: без z-fighting


def terrain_vc(h, x, y, ruts=False):
    """Колір вершини (sRGB). Власного кольору лише в колії, канавах і на насипу; решта нейтральна й гаснe в альфі."""
    a = abs(y)
    track, slope = (.34, .30, .24), (.26, .235, .185)
    wet, moss, mud, grass = (.15, .125, .10), (.20, .25, .12), (.22, .18, .12), (.30, .31, .26)
    if ruts:
        return tuple(c * 0.65 for c in track)                 # дно колії: ґрунт ×0,65, не майже чорне
    if a > 4.3 and abs(x) < 2.2 and h < .5:
        if h < .1: return wet
        if h < .3: return moss if abs(x) < 1.7 else mud
        return mud
    if a <= 2.7 and h > .9:
        return track
    if h > .45 and a > 4.3:
        return grass
    return slope


def terrain(b, mat, water, wetmat):
    xs = [-4, -3, -2, -1.5, -1.25, -1.0, -0.5, 0, 0.5, 1.0, 1.25, 1.5, 2, 3, 4]
    ys = sorted({-8.4, -7.8, -7.0, -6.6, -6.0, -5.6, -5.2, -4.5, -4.4, 4.4, -2.6, -1.25, -1.15, -1.08, -.72, -.65, -.6, 0, .6, .65,
                 .72, 1.08, 1.15, 1.25, 2.6, 4.5, 5.2, 5.6, 6.0, 6.6, 7.2, 7.8, 8.6})
    rng = np.random.default_rng(5)
    bm = b.bm
    tex_mean = 0.57                                       # середня лінійна яскравість текстури
    V = {}
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            f = min(1.0, max(0.0, (4.0 - abs(x)) / 2.4))
            base = prof_h(y)
            h = carve(x, y, base * f) if abs(y) >= 4.3 else base * f
            xx = x
            if 0 < i < len(xs) - 1 and 0 < j < len(ys) - 1 and h > 0.1 and abs(y) > 1.3:
                h += rng.uniform(-0.02, 0.02)
            if abs(y) > 4.5 and 0.95 < abs(x) < 1.6 and 0 < j < len(ys) - 1:       # нерівний берег
                xx = x + rng.uniform(-0.12, 0.12)
                h = max(0.04, h + rng.uniform(-0.05, 0.05))
            rut = 0.7 < abs(y) < 1.1
            d = min(4.0 - abs(x), (8.4 if y < 0 else 8.6) - abs(y))
            alpha = float(np.clip(d / 1.8, 0, 1))          # край пагорба гасне в землю
            if abs(y) > 4.3 and abs(x) < 2.0:
                alpha = max(alpha, float(np.clip(d / 1.0, 0, 1)))
            col = terrain_vc(h, x, y, rut and base > .8)
            wc = float(np.clip(d / 1.8, 0, 1))                        # на краю колір зливається з нейтральним тоном землі
            neutral = (.28, .29, .24)
            col = tuple(n_ + (c_ - n_) * wc for n_, c_ in zip(neutral, col))
            v = bm.verts.new((xx, y, h))
            V[(i, j)] = (v, col, alpha)
    ii = b.mi(mat)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            q = [V[(i, j)], V[(i + 1, j)], V[(i + 1, j + 1)], V[(i, j + 1)]]
            f = bm.faces.new([p[0] for p in q])
            f.material_index = ii
            b.keep.add(f)
            for l, p in zip(f.loops, q):
                lin = srgb_to_lin(np.array(p[1])) / tex_mean
                l[b.col] = (*np.clip(lin, 0, 1), p[2])
    # вода: смуга 2,6 м у кожній канаві (берег різаний схилами), на кінцях гасне; плюс мокрі смуги в колії
    wi = b.mi(water)

    def strip(x0, x1, y0, y1, lv, nseg=6):
        ys_ = np.linspace(y0, y1, nseg + 1)
        rows = []
        for k, y in enumerate(ys_):
            a_ = 0.0 if k in (0, nseg) else 1.0
            rows.append((bm.verts.new((x0, y, lv)), bm.verts.new((x1, y, lv)), a_))
        for k in range(nseg):
            q = [rows[k][0], rows[k][1], rows[k + 1][1], rows[k + 1][0]]
            f = bm.faces.new(q); f.material_index = wi; b.keep.add(f)
            for l, vi in zip(f.loops, (k, k, k + 1, k + 1)):
                l[b.col] = (1, 1, 1, rows[vi][2])
    strip(-1.3, 1.3, 4.7, 7.4, 0.06)
    strip(-1.3, 1.3, -7.2, -4.7, 0.06)
    wet_i = b.mi(wetmat)
    for sy in (-0.9, 0.9):                                   # мокре дно колій
        strip_x = np.linspace(-3.2, 3.2, 7)
        for k in range(6):
            vs = [bm.verts.new((strip_x[k], sy - 0.1, .868)), bm.verts.new((strip_x[k + 1], sy - 0.1, .868)),
                  bm.verts.new((strip_x[k + 1], sy + 0.1, .868)), bm.verts.new((strip_x[k], sy + 0.1, .868))]
            f = bm.faces.new(vs); f.material_index = wet_i; b.keep.add(f)
            for l in f.loops: l[b.col] = (1, 1, 1, 1.0 if 0 < k < 5 else 0.0)


def terrain_mat():
    """Колія й земля: дрібний гравій (~3 см), без низькочастотних плям; край гасне альфа-змішуванням."""
    n = 128
    fine = tile_noise(48, 48, n, 76)
    a = 0.78 * (0.92 + 0.08 * fine)
    a = np.repeat(a[..., None], 3, -1)
    alpha = 0.8 + 0.2 * fbm(n, 79, 6, 3)
    return pbr("culvert_ground", albedo=np.concatenate([a, alpha[..., None]], -1),
               normal=np.concatenate([normal_from_height(fine, 1.5), np.ones((n, n, 1))], -1),
               tile=1.5, rough=0.95, alpha=True, blend=True)


def culvert():
    mat = concrete("culvert_concrete", 63, 1.9, val=0.8, band=(0.4, 0.8, 0.3), streak_k=0.5, ground=False)
    water = pbr("culvert_water", color=(0.16, 0.18, 0.175), rough=0.12, opacity=0.9)
    dark = pbr("culvert_dark", color=(0.02, 0.022, 0.02), rough=1.0)
    b = B()
    b.mi(dark)                                                  # перший матеріал меша не отримує вершинних кольорів
    wetmat = pbr("culvert_wet", color=(0.30, 0.27, 0.22), rough=0.15, opacity=0.35)
    terrain(b, terrain_mat(), water, wetmat)
    z0 = 0.0                                                   # підошва оголовка на дні канави, спинка підпирає насип
    zc = z0 + 0.62
    for s in (-1, 1):
        b.tone = 1 + 0.12 * s
        yh = s * 4.3
        b.box(mat, (0, yh, z0 + 0.75), (3.0, 0.4, 1.5))                        # оголовок
        tube(b, mat, (0, s * 4.7, zc), 0.62, 0.5, 0.4, inner=dark)             # виступ труби над укосом
        b.cyl(dark, (0, s * 4.52, zc), 0.5, 0.04, 20, axis="Y")                # темний зів
        for sx in (-1, 1):                                                     # відхилені крила
            b.box(mat, (sx * 1.7, s * 4.3, z0 + 0.45), (0.3, 1.0, 0.9), Matrix.Rotation(sx * s * 0.45, 3, "Z"))
    finish(b, "infra_culvert", jpeg=False)


def bed_mat():
    """Дно кузова: засохле багно з соломою, ~2 см на тексель (128 px на 2,56 м), без яскравих цяток."""
    n = 128
    rng = np.random.default_rng(97)
    mud = np.array([0.24, 0.19, 0.13])[None, None, :] * (0.75 + 0.5 * fbm(n, 98, 4)[..., None])
    straw = np.zeros((n, n))
    for _ in range(90):                                    # соломини: короткі світліші риски
        x, y = rng.integers(0, n), rng.integers(0, n)
        ln, ang = rng.integers(6, 18), rng.uniform(0, np.pi)
        for t in range(ln):
            xx, yy = int(x + t * np.cos(ang)) % n, int(y + t * np.sin(ang)) % n
            straw[yy, xx] = 1
    a = mud * (1 - 0.35 * straw[..., None]) + np.array([0.42, 0.34, 0.20])[None, None, :] * 0.35 * straw[..., None]
    h = fbm(n, 99, 8) * 0.7 + straw * 0.3
    return pbr("trailer_bed", albedo=a, normal=np.concatenate([normal_from_height(h, 2.5), np.ones((n, n, 1))], -1),
               tile=2.56, rough=0.95)


def trailer(name, paint, seed, kind="tipper"):
    """kind: tipper — самоскидний 2ПТС з високими бортами; flatbed — одновісна платформа з низькими бортами
    й дерев'яною підлогою; tank — бочка-водовоз на одновісному шасі."""
    if kind != "tipper":
        return trailer_small(name, paint, seed, kind)
    body = sheet_mat(f"trailer_body_{seed}", paint, seed, tile_v=2.1, band=(0.9, 1.5), patch=0.6)
    frame = pbr("trailer_frame", "MetalPlates013", tile=1.0, tint=(0.42, 0.41, 0.39), sat=0.3, rust=0.0, grime=0.0,
                rough=0.8, seed=seed + 1)
    bed = bed_mat()
    tyre = rim = frame        # шасі, шини й диски — один матеріал
    b = B()
    y0, y1, fl = -3.75, 2.25, 1.01
    ym = (y0 + y1) / 2
    b.box(frame, (0, ym, fl), (2.4, y1 - y0, 0.08))                                 # підлога
    b.box(bed, (0, ym, fl + 0.055), (2.3, y1 - y0 - 0.1, 0.03))                     # дно: багно й солома
    for s in (-1, 1):
        b.box(body, (s * 1.2, ym, fl + 0.55), (0.05, y1 - y0, 1.0))                  # борт
        yy0 = y0 - 0.025
        for k, (a_, b_, tn, th) in enumerate(((0.0, 2.1, 0.74, 0.1), (2.2, 4.0, 0.9, 0.11), (4.1, 6.05, 0.8, 0.095))):
            b.tone = tn                                                                # верхня обв'язка з розривами й різним тоном
            b.box(body, (s * 1.22, yy0 + (a_ + b_) / 2, fl + 1.06), (0.14, b_ - a_, th), None)
        b.tone = 0.72
        b.box(body, (s * 1.228, ym, fl + 0.14), (0.01, y1 - y0 - 0.1, 0.2))             # темна смуга вздовж нижнього краю
        for k in range(4):                                                              # патьоки під ребрами
            for off in (-0.13, 0.15):
                b.box(body, (s * 1.228, y0 + 0.5 + k * 1.65 + off, fl + 0.4), (0.01, 0.07, 0.7 - 0.2 * (off > 0)))
        b.tone = 1.0
        b.box(frame, (s * 1.0, ym, 0.84), (0.16, y1 - y0 - 0.2, 0.22))               # лонжерон під кузовом
        for k in range(4):                                                           # ребра борту, 12 см
            b.box(frame, (s * 1.245, y0 + 0.5 + k * 1.65, fl + 0.55), (0.07, 0.12, 1.0))
        for yy in (y0 + 1.3, y0 + 4.2):                                              # петлі відкидного борту
            b.box(frame, (s * 1.26, yy, fl + 0.12), (0.1, 0.16, 0.14))
        for yy in (y0 + 0.3, y0 + 2.2, y0 + 3.4, y0 + 5.7):                          # гнізда стійок
            b.box(frame, (s * 1.27, yy, fl - 0.04), (0.12, 0.14, 0.14))
    b.box(body, (0, y0, fl + 0.55), (2.4, 0.05, 1.0))                               # задній борт
    b.tone = 0.82
    b.box(body, (0, y0 - 0.04, fl + 1.06), (2.5, 0.1, 0.1))
    b.tone = 1.0
    b.box(body, (0, y1, fl + 0.65), (2.4, 0.07, 1.3))                               # щит (до 2.3 м)
    b.tone = 0.82
    b.box(body, (0, y1, fl + 1.32), (2.46, 0.12, 0.1))
    b.tone = 1.0
    for ay in (-2.4, -1.2):
        b.cyl(frame, (0, ay, 0.5), 0.07, 2.3, 8, axis="X")                          # осі
        for s in (-1, 1):
            b.cyl(tyre, (s * 1.05, ay, 0.5), 0.5, 0.4, 16, axis="X")
            b.cyl(rim, (s * 1.05 + s * 0.02, ay, 0.5), 0.28, 0.4, 10, axis="X")
    for s in (-1, 1):                                                               # дишло: А-подібна рама, світліша
        b.beam(body, (s * 0.65, y1, 0.85), (0, 3.7, 1.1), 0.17)
    b.box(body, (0, 3.62, 1.1), (0.45, 0.4, 0.22))
    b.box(body, (0, y1 + 0.55, 0.85), (1.3, 0.2, 0.2))
    b.beam(frame, (0, 2.55, 1.0), (0, 2.38, 2.0), 0.07, 8)                          # гідроциліндр
    finish(b, name)


def tank_mat(name, paint, seed, n=128):
    """Гладка фарбована бочка: іржа неправильними плямами двох масштабів і кілька патьоків, а не рівні кружки."""
    big, small = fbm(n, seed, 3, 4), fbm(n, seed + 5, 9, 3)
    rust = np.clip((0.6 * big + 0.4 * small - 0.58) * 6, 0, 1)
    u = (np.arange(n) + 0.5) / n
    rng = np.random.default_rng(seed)
    for _ in range(5):
        u0, ln = rng.uniform(0, 1), rng.uniform(0.2, 0.6)
        v = (np.arange(n) + 0.5) / n
        rust = np.maximum(rust, 0.7 * np.exp(-((u[None, :] - u0) / 0.01) ** 2) * np.clip(1 - np.abs(v[:, None] - 0.5) / ln, 0, 1))
    col = np.array(paint) * (0.85 + 0.25 * fbm(n, seed + 9, 4, 3))[..., None]
    a = col * (1 - rust[..., None]) + np.array([0.33, 0.17, 0.08]) * (0.7 + 0.5 * small[..., None]) * rust[..., None]
    nrm = normal_from_height(0.5 * small + 0.5 * rust, 1.5)
    return pbr(name, albedo=a, normal=np.concatenate([nrm, np.ones((n, n, 1))], -1), tile=2.0, rough=0.7, metal=0.1)


def trailer_small(name, paint, seed, kind):
    body = (sheet_mat(f"trailer_body_{seed}", paint, seed, tile_v=1.2, band=(0.4, 0.9), patch=0.7) if kind == "flatbed"
            else tank_mat(f"trailer_tank_{seed}", paint, seed))
    frame = pbr("trailer_frame", "MetalPlates013", tile=1.0, tint=(0.42, 0.41, 0.39), sat=0.3, rust=0.0, grime=0.0, rough=0.8, seed=seed + 1)
    b = B()
    y0, y1, fl = -2.4, 1.6, 0.75
    ym = (y0 + y1) / 2
    for s in (-1, 1):
        b.box(frame, (s * 0.8, ym, fl - 0.12), (0.12, y1 - y0, 0.16))                  # лонжерони
    if kind == "flatbed":
        deck = pbr("trailer_deck", "Planks021", tile=1.0, tint=(0.55, 0.48, 0.40), sat=0.5, grime=0.4, rough=0.9, seed=seed + 2)
        b.box(deck, (0, ym, fl), (2.0, y1 - y0, 0.06))                                   # дощата підлога
        for s in (-1, 1):
            b.box(body, (s * 1.0, ym, fl + 0.22), (0.04, y1 - y0, 0.4))                  # низькі борти 40 см
        b.box(body, (0, y0, fl + 0.22), (2.0, 0.04, 0.4))
        b.box(body, (0, y1, fl + 0.3), (2.0, 0.05, 0.55))
    else:
        b.cyl(body, (0, ym, fl + 0.75), 0.72, y1 - y0 - 0.3, 16, axis="Y")               # бочка 3,7 м
        b.cyl(frame, (0, ym, fl + 1.5), 0.22, 0.2, 10)                                   # горловина
        for yy in (y0 + 0.6, y1 - 0.6):
            b.box(frame, (0, yy, fl + 0.2), (1.5, 0.12, 0.3))                            # ложементи
    b.cyl(frame, (0, ym - 0.4, 0.42), 0.06, 2.0, 8, axis="X")                           # одна вісь
    for s in (-1, 1):
        b.cyl(frame, (s * 0.92, ym - 0.4, 0.42), 0.42, 0.3, 14, axis="X")
    b.beam(frame, (-0.6, y1, 0.65), (0, y1 + 1.6, 0.7), 0.12)                           # дишло
    b.beam(frame, (0.6, y1, 0.65), (0, y1 + 1.6, 0.7), 0.12)
    finish(b, name)


reset()
if want("infra_jersey_block"): jersey()
if want("infra_culvert"): culvert()
if want("infra_trailer_green"): trailer("infra_trailer_green", (0.30, 0.34, 0.24), 71)
if want("infra_trailer_rust"): trailer("infra_trailer_rust", (0.52, 0.34, 0.22), 73)
if want("infra_trailer_flatbed"): trailer("infra_trailer_flatbed", (0.30, 0.38, 0.46), 75, "flatbed")
if want("infra_trailer_tank"): trailer("infra_trailer_tank", (0.48, 0.52, 0.54), 77, "tank")
