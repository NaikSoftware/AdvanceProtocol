"""Бетонний блок (джерсі), придорожня водопропускна труба, фермерський причіп.

Причіп: перед (дишло) уздовж +Y Blender = −Z Godot. Труба: вісь уздовж Y, два оголовки.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


def concrete(name="road_concrete", seed=61, top_z=0.8):
    return concrete_mat(name, tile=1.5, seed=seed, top_z=top_z, seams=True, k=7.0)


def jersey():
    mat = concrete()
    b = B(); bm = b.bm
    # профіль «нью-джерсі» зі сколотими скосами й фасками: вертикальний низ, скіс, крутіший верх
    prof = [(-.30, 0), (.30, 0), (.30, .17), (.20, .50), (.12, .74), (.07, .80),
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
    finish(b, "infra_jersey_block")


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
    """Висота насипу вздовж Y: полотно (2,6 м у плані) на 1,0 м, схили до канав, тераса 0,5 м, схил до землі.
    Канави несиметричні: північна глибша й ширша."""
    if y >= 0:
        xs, hs = [0, .5, .9, 1.3, 2.6, 4.5, 5.2, 5.7, 6.5, 7.2, 8.6], [1, 1, .965, 1, 1, .5, 0, 0, .5, .5, 0]
    else:
        xs, hs = [0, .5, .9, 1.3, 2.6, 4.4, 5.0, 5.4, 6.0, 7.0, 8.4], [1, 1, .965, 1, 1, .55, .05, .05, .42, .42, 0]
    return float(np.interp(abs(y), xs, hs))


def terrain_vc(h, y):
    """Колір вершини (sRGB): мокрий мул на дні, мох і брудна смуга на урізі, суха глина схилу, трава тераси, колія."""
    a = abs(y)
    track, wet, moss, dirt, grass = (.34, .30, .24), (.17, .14, .11), (.22, .28, .13), (.36, .31, .22), (.30, .32, .25)
    if a <= 2.7 and h > .9:
        return track
    if 4.3 < a < 6.8 and h < .5:
        if h < .08: return wet
        if h < .3: return moss
        return dirt
    if h > .45 and a > 2.7:
        return grass
    return dirt


def terrain(b, mat, water):
    xs = [-4, -3.2, -2.4, -1.6, -0.8, 0, 0.8, 1.6, 2.4, 3.2, 4]
    ys = sorted({-8.4, -7.0, -6.0, -5.4, -5.0, -4.4, -2.6, -1.3, -.9, -.5, 0, .5, .9, 1.3, 2.6, 4.5, 5.2, 5.7, 6.5, 7.2, 8.6})
    rng = np.random.default_rng(5)
    bm = b.bm
    tex_mean = 0.57                                       # середня лінійна яскравість текстури шуму
    V = {}
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            f = min(1.0, max(0.0, (4.0 - abs(x)) / 1.6))
            h = prof_h(y) * f
            if 0 < i < len(xs) - 1 and 0 < j < len(ys) - 1 and h > 0.1:
                h += rng.uniform(-0.02, 0.02)
            v = bm.verts.new((x, y, h))
            V[(i, j)] = (v, terrain_vc(h, y))
    ii = b.mi(mat)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            q = [V[(i, j)], V[(i + 1, j)], V[(i + 1, j + 1)], V[(i, j + 1)]]
            f = bm.faces.new([p[0] for p in q])
            f.material_index = ii
            b.keep.add(f)
            for l, p in zip(f.loops, q):
                lin = srgb_to_lin(np.array(p[1])) / tex_mean
                l[b.col] = (*np.clip(lin, 0, 1), 1.0)
    # вода: вужча смуга на дні кожної канави
    wi = b.mi(water)
    for y0, y1, lv in ((5.13, 5.78, .07), (-5.55, -4.85, .1)):
        vs = [bm.verts.new((x, y, lv)) for x, y in ((-3.4, y0), (3.4, y0), (3.4, y1), (-3.4, y1))]
        f = bm.faces.new(vs); f.material_index = wi; b.keep.add(f)
        for l in f.loops: l[b.col] = (1, 1, 1, 1)


def terrain_mat():
    n = 128
    a = 0.78 * (0.85 + 0.3 * fbm(n, 77, 4))
    a = np.repeat(a[..., None], 3, -1) * np.array([1.0, 1.0, 0.97])
    h = fbm(n, 78, 6)
    return pbr("culvert_ground", albedo=a, normal=np.concatenate([normal_from_height(h, 2.0), np.ones((n, n, 1))], -1),
               tile=2.5, rough=0.95)


def culvert():
    mat = concrete("culvert_concrete", 63, 1.9)
    dark = pbr("culvert_water", color=(0.03, 0.035, 0.03), rough=0.12)
    b = B()
    b.mi(dark)                                                  # перший матеріал меша не отримує вершинних кольорів
    terrain(b, terrain_mat(), dark)
    z0 = 0.42                                                  # підошва оголовка заглиблена в насип
    zc = z0 + 0.62
    for s in (-1, 1):
        b.tone = 1 + 0.15 * s
        yh = s * 4.3
        b.box(mat, (0, yh, z0 + 0.75), (3.0, 0.4, 1.5))                        # оголовок
        b.box(mat, (0, yh + s * 0.1, z0 + 1.52), (3.1, 0.5, 0.1))              # верхня кромка
        tube(b, mat, (0, s * 4.7, zc), 0.62, 0.5, 0.4, inner=dark)             # виступ труби над укосом
        b.cyl(dark, (0, s * 4.52, zc), 0.5, 0.04, 20, axis="Y")                # темний зів
        for sx in (-1, 1):                                                     # відхилені крила
            b.box(mat, (sx * 1.7, s * 4.3, z0 + 0.45), (0.3, 1.0, 0.9), Matrix.Rotation(sx * s * 0.45, 3, "Z"))
    finish(b, "infra_culvert")


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


def trailer(name, paint, seed):
    body = sheet_mat(f"trailer_body_{seed}", paint, seed, tile_v=1.2)
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
        b.box(frame, (s * 1.22, ym, fl + 1.06), (0.14, y1 - y0 + 0.05, 0.1))         # верхня обв'язка
        b.box(frame, (s * 1.0, ym, 0.84), (0.16, y1 - y0 - 0.2, 0.22))               # лонжерон під кузовом
        for k in range(4):                                                           # ребра борту, 12 см
            b.box(frame, (s * 1.245, y0 + 0.5 + k * 1.65, fl + 0.55), (0.07, 0.12, 1.0))
        for yy in (y0 + 1.3, y0 + 4.2):                                              # петлі відкидного борту
            b.box(frame, (s * 1.26, yy, fl + 0.12), (0.1, 0.16, 0.14))
        for yy in (y0 + 0.3, y0 + 2.2, y0 + 3.4, y0 + 5.7):                          # гнізда стійок
            b.box(frame, (s * 1.27, yy, fl - 0.04), (0.12, 0.14, 0.14))
    b.box(body, (0, y0, fl + 0.55), (2.4, 0.05, 1.0))                               # задній борт
    b.box(frame, (0, y0 - 0.04, fl + 1.06), (2.5, 0.1, 0.1))
    b.box(body, (0, y1, fl + 0.65), (2.4, 0.07, 1.3))                               # щит (до 2.3 м)
    b.box(frame, (0, y1, fl + 1.32), (2.46, 0.12, 0.1))
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


reset()
if want("infra_jersey_block"): jersey()
if want("infra_culvert"): culvert()
if want("infra_trailer_green"): trailer("infra_trailer_green", (0.30, 0.34, 0.24), 71)
if want("infra_trailer_rust"): trailer("infra_trailer_rust", (0.50, 0.38, 0.33), 73)
