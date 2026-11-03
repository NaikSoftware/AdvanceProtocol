"""Огорожі прямими секціями по 8 м (вздовж X) і кутовий елемент (два плеча по 4 м).

Типи: профнастил (два кольори — для різних половин мапи), декоративний бетонний «єврозабір»,
промислова панельна (ПО-2), дерев'яний штахет (картка з alpha, дошки <1 px на дальньому зумі).
Кут: стовп у куті, одне плече вздовж +X, друге вздовж +Y (Godot −Z); початок — центр габариту.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


WARM = (1.05, 1.0, 0.9)   # теплий сіро-бежевий бетон, а не нейтрально-сірий


def _stone(n, seed=41, count=46):
    """Єврозабір «камінь»: камені на випадковій сітці (клітинки Вороного), шви 2-3 см, кожен камінь опуклий і свого рівня."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, 1, (count, 2))
    lift = rng.uniform(0.6, 1.0, count)
    u = (np.arange(n) + 0.5) / n
    uu, vv = np.meshgrid(u, u)
    d = np.sqrt((uu[..., None] - pts[:, 0]) ** 2 + ((vv[..., None] - pts[:, 1]) * 0.9) ** 2)
    o = np.argsort(d, -1)
    f1 = np.take_along_axis(d, o[..., :1], -1)[..., 0]
    f2 = np.take_along_axis(d, o[..., 1:2], -1)[..., 0]
    edge = np.clip((f2 - f1) / 0.025, 0, 1)
    dome = np.clip(1 - f1 / 0.12, 0, 1) ** 0.5
    return 0.15 + 0.85 * edge * (0.6 + 0.4 * dome) * lift[o[..., 0]]


def _euro(n):
    """Класичний єврозабір: три втоплені філенги один над одним, зі скосом."""
    h = np.zeros((n, n))
    for v0, v1 in ((0.03, 0.31), (0.34, 0.62), (0.65, 0.93)):
        h = np.maximum(h, box_mask(n, 0.06, 0.94, v0, v1, 0.03))
    return 1 - 0.8 * h


def _po2(n):
    """ПО-2: три горизонтальні ребра."""
    h = np.zeros((n, n))
    for z in (0.55, 1.2, 1.85):
        h = np.maximum(h, box_mask(n, 0.0, 1.0, z / 2.5 - 0.035, z / 2.5 + 0.035, 0.01))
    return 0.35 + 0.65 * h


def _brick(n):
    """Єврозабір «цегла»: перев'язка 25 x 6,5 см рельєфом."""
    u = (np.arange(n) + 0.5) / n; z = (np.arange(n) + 0.5) / n
    row = np.floor(z * 2.0 / 0.075)
    uu = (u[None, :] * 2.0 / 0.25 + 0.5 * (row[:, None] % 2)) % 1.0
    vv = (z * 2.0 / 0.075) % 1.0
    return 0.3 + 0.7 * ((uu > 0.05) & (uu < 0.95) & (vv[:, None] > 0.12) & (vv[:, None] < 0.88))


def _wave(n):
    """Єврозабір «хвиля»: горизонтальні хвилі кроком 0,3 м."""
    u = (np.arange(n) + 0.5) / n; z = (np.arange(n) + 0.5) / n
    return 0.5 + 0.5 * np.sin(2 * np.pi * (z[:, None] * 2.2 / 0.3 + 0.35 * np.sin(2 * np.pi * u[None, :] * 2)))


def _ribs(n):
    z = (np.arange(n) + 0.5) / n
    h = np.zeros((n, n))
    for zz in (0.25, 0.5, 0.75):
        h = np.maximum(h, box_mask(n, 0.0, 1.0, zz - 0.03, zz + 0.03, 0.01))
    return 0.35 + 0.65 * h


# Типи бетонних парканів (усі — окремі моделі): висота 1,8-2,2 м, різні візерунки, частина фарбована
# Бетонні паркани: nom — крок секції, ph — висота стовпа, hh/z0 — висота й низ панелі, rows — плит у пазах,
# berm — валик біля основи (трава, бруд, гравій)
CONCRETE = {
    "euro": dict(nom=2.0, ph=1.95, pw=0.2, seed=25, relief=_euro, k=14.0, hh=1.8, z0=0.0, rows=4, berm="dirt"),
    "po2": dict(nom=4.0, ph=2.5, pw=0.2, seed=27, relief=_po2, k=12.0, hh=2.3, z0=0.1, rust=3, berm="gravel"),
    "slab": dict(nom=2.0, ph=2.0, pw=0.2, seed=51, seams=True, berm="grass"),
    "euro_stone": dict(nom=2.0, ph=1.8, pw=0.2, seed=52, relief=_stone, k=12.0, rows=4, berm="dirt"),
    "euro_brick": dict(nom=2.0, ph=2.0, pw=0.2, seed=53, relief=_brick, k=10.0, rows=4, berm="gravel"),
    "euro_wave": dict(nom=2.0, ph=2.2, pw=0.2, seed=54, relief=_wave, k=8.0, rows=4, berm="grass"),
    "brickpost": dict(nom=2.5, ph=1.9, pw=0.4, seed=55, brick_post=True, berm="gravel"),
    "painted_green": dict(nom=3.0, ph=2.2, pw=0.2, seed=56, relief=_ribs, paint=(0.42, 0.52, 0.40), peel=0.8, rust=3, berm="grass"),
    "painted_beige": dict(nom=2.0, ph=1.8, pw=0.2, seed=57, paint=(0.74, 0.66, 0.52), peel=0.6, berm="dirt"),
}


def _lum(a):
    return float((a[..., :3] * [0.2126, 0.7152, 0.0722]).sum(-1).mean())


def berm_cell(kind, n, seed, target):
    """Валик біля основи: трава, бруд або гравій, середня яскравість = target (на 20-30 % темніший за панель)."""
    g = acg_albedo("Ground111", (1, 1, 1), 0.6, 0, seed, 0.0, size=n)
    f = fbm(n, seed + 3, 5, 4)
    if kind == "grass":
        m = np.clip((f - 0.35) * 3, 0, 1)[..., None]
        a = g * (1 - m) + np.array([0.24, 0.30, 0.14]) * (0.7 + 0.6 * f[..., None]) * m
    elif kind == "gravel":
        a = acg_albedo("Asphalt031", (1, 1, 1), 0.3, 0, seed, 0.0, size=n) * (0.8 + 0.4 * tile_noise(24, 24, n, seed + 5))[..., None]
    else:
        a = g * np.array([1.0, 0.92, 0.8])
    a = a * (target / max(_lum(a), 1e-4))
    nrm = normal_from_height(0.6 * f + 0.4 * tile_noise(32, 32, n, seed + 7), 3.0)
    return a, nrm


def panel_atlas(kind, spec, n=128):
    """Один матеріал на панелі й валик: три варіанти плити (свої патьоки) і клітинка валика — 4 клітинки в ряд."""
    hh = spec.get("hh", spec["ph"] - 0.08)
    cells_a, cells_n = [], []
    for v in range(3):
        a, nrm = concrete_mat(f"{kind}_v{v}", tile=spec["nom"], tile_v=hh, relief=spec.get("relief"), seed=spec["seed"] + 17 * v,
                              top_z=hh - 0.05, k=spec.get("k", 9.0) * 1.6, shade=0.45 if spec.get("relief") else 0.18, streak_k=0.7,
                              streak_len=0.9, tint=WARM, moss=0.7, rust_runs=spec.get("rust", 2), chips=True, paint=spec.get("paint"),
                              peel=spec.get("peel", 0.0), seams=spec.get("seams", False), size=n, arrays=True)
        cells_a.append(a); cells_n.append(nrm)
    ba, bn = berm_cell(spec.get("berm", "dirt"), n, spec["seed"] + 5, 0.75 * _lum(cells_a[0]))
    cells_a.append(ba); cells_n.append(bn)
    A = np.concatenate(cells_a, 1); Nm = np.concatenate(cells_n, 1)
    return pbr(f"{kind}_atlas", albedo=A, normal=np.concatenate([Nm, np.ones(Nm.shape[:2] + (1,))], -1), tile=1.0, rough=0.92)


def berm(b, atlas, at, c, w, rng):
    """Валик ґрунту під панеллю з обох боків: клин від 8-14 см біля плити до нуля за 0.3 м, низ на землі."""
    uv = b.bm.loops.layers.uv.verify()
    p0 = Vector(at(c - w / 2, 0.0))
    d = (Vector(at(c + w / 2, 0.0)) - p0).normalized()
    for side in (-1, 1):
        hb = rng.uniform(0.08, 0.14)
        q = [at(c - w / 2, 0.0, side * 0.32), at(c + w / 2, 0.0, side * 0.32), at(c + w / 2, hb, side * 0.05), at(c - w / 2, hb, side * 0.05)]
        vs = [b.bm.verts.new(p) for p in q]
        f = b.bm.faces.new(vs)
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        b._tag(atlas, vs)
        for l in f.loops:
            u = (l.vert.co - p0).dot(d) / w
            l[uv].uv = ((3 + 0.01 + 0.98 * min(max(u, 0.0), 1.0)) / 4, l.vert.co.z / hb)
        b.skip_uv.add(f)
        b.keep.add(f)


def atlas_uv(b, verts, M, cell, v0=0.0, v1=1.0):
    """UV граней бокса в клітинку атласу: лице — уся клітинка (u вздовж, v вгору), торці й верх — вузькі смуги краю."""
    uv = b.bm.loops.layers.uv.verify()
    Mi = M.inverted()
    ins = 0.01
    for f in {f for v in verts for f in v.link_faces}:
        loc = [Mi @ l.vert.co for l in f.loops]
        c = sum(loc, Vector()) / len(loc)
        ax = max(range(3), key=lambda k: abs(c[k]))
        for l, p in zip(f.loops, loc):
            if ax == 1:
                u, v = p.x + 0.5, p.z + 0.5
            elif ax == 0:
                u, v = 0.02 * (p.y + 0.5), p.z + 0.5
            else:
                u, v = p.x + 0.5, 0.97 + 0.03 * (p.y + 0.5)
            l[uv].uv = ((cell + ins + (1 - 2 * ins) * u) / 4, v0 + (v1 - v0) * v)
        b.skip_uv.add(f)


def runs(corner):
    return [((-4, 0), (1, 0), 8)] if not corner else [((0, 0), (1, 0), 4), ((0, 0), (0, 1), 4)]


def fence(kind, corner, name, damaged=False):
    b = B()
    rng = np.random.default_rng(sum(map(ord, name)))
    if kind.startswith("sheet"):
        col = {"sheet_green": (0.33, 0.39, 0.31), "sheet_brown": (0.44, 0.35, 0.30)}[kind]
        sheet = sheet_mat(f"{kind}_panel", col, 21 if kind.endswith("green") else 22)
        post = sheet_mat(f"{kind}_post", col, 23)
        b.mi(post)              # перший матеріал меша Godot не фарбує вершинним кольором — тон дістається листам
        nom, ph, pw = 2.5, 2.0, 0.08
    elif kind in CONCRETE:
        spec = CONCRETE[kind]
        nom, ph, pw = spec["nom"], spec["ph"], spec["pw"]
        if kind == "euro":
            post = concrete_mat("euro_post", tile=2.0, seed=26, top_z=1.95, streak_k=0.9, streak_len=0.8, val=0.92, tint=WARM, moss=0.6, chips=True)
        elif kind == "po2":
            post = concrete_mat("po2_post", tile=2.0, seed=28, top_z=2.45, tint=WARM, moss=0.6, chips=True)
        elif spec.get("brick_post"):
            post = pbr(f"{kind}_post", "Bricks105", tile=1.0, tint=(0.82, 0.50, 0.40), sat=0.6, grime=0.3, rough=0.9, seed=spec["seed"] + 1)
        else:
            post = concrete_mat(f"{kind}_post", tile=2.0, seed=spec["seed"] + 1, top_z=ph, streak_k=0.7, streak_len=0.8, tint=WARM, moss=0.6, chips=True)
        b.mi(post)              # перший матеріал меша Godot не фарбує вершинним кольором — тон дістається панелям
        atlas = panel_atlas(kind, spec)                                    # панелі й валик — один матеріал: дві поверхні на модель
    elif kind == "picket":
        sheet = None
        post = pbr("picket_post", "Planks021", tile=1.0, tint=(0.42, 0.36, 0.29), sat=0.4, grime=0.0, rough=0.95, seed=29)
        nom, ph, pw = 2.0, 1.45, 0.1
        card = picket_mat()
    for (ox, oy), (dx, dy), L in runs(corner):
        n = max(1, round(L / nom)); pitch = L / n
        yaw = Matrix.Rotation(math.atan2(dy, dx), 3, "Z")
        at = lambda s, z, off=0.0: (ox + dx * s - dy * off, oy + dy * s + dx * off, z)
        for i in range(n + 1):
            s = i * pitch
            if corner and i == 0 and (dx, dy) != (1, 0):
                continue                                           # кутовий стовп один
            if not corner and i in (0, n):
                s += pw / 2 if i == 0 else -pw / 2
            b.box(post, at(s, ph / 2), (pw, pw, ph), yaw)
            if kind in CONCRETE and CONCRETE[kind].get("brick_post"):
                b.box(post, at(s, ph + 0.04), (pw + 0.1, pw + 0.1, 0.08), yaw)         # шапка стовпа тим самим матеріалом
        lean_i, sunk_i = (int(rng.integers(n)), int(rng.integers(n))) if n > 1 else (-1, -1)   # на кожному плечі одна нахилена й одна просіла
        for i in range(n):
            c = (i + 0.5) * pitch; w = pitch - pw
            if kind.startswith("sheet"):
                t = 1 + rng.uniform(-0.25, 0.25); dh = rng.uniform(-0.07, 0.07)
                b.tone = (t * (1 + dh), t, t * (1 - dh))                                   # тон і відтінок листа
                b.box(sheet, at(c, 0.99, 0.045), (w, 0.035, 1.92), yaw)
                b.tone = 1.0
            elif kind in CONCRETE:
                spec = CONCRETE[kind]
                hh, z0, rows = spec.get("hh", ph - 0.08), spec.get("z0", 0.02), spec.get("rows", 1)
                cell = int(rng.integers(3))                                        # своя маска патьоків на кожну панель
                b.tone = 1 + rng.uniform(-0.12, 0.12)
                berm(b, atlas, at, c, w, rng)
                if damaged and i == 1:                                             # злам: рваний профіль з 4 пеньків і уламки біля основи
                    xs = sorted(rng.uniform(-w / 2, w / 2, 3))
                    edges = [-w / 2] + list(xs) + [w / 2]
                    for k_ in range(4):
                        hz = rng.uniform(0.15, 0.9)
                        vs, M = b.box(atlas, at(c + (edges[k_] + edges[k_ + 1]) / 2, z0 + hz / 2, 0), (edges[k_ + 1] - edges[k_] - 0.01, 0.09, hz), yaw)
                        atlas_uv(b, vs, M, cell, 0.0, hz / hh)
                    for k_ in range(4):
                        sz = rng.uniform(0.2, 0.4)
                        rot = yaw @ Matrix.Rotation(rng.uniform(0, 3.1), 3, "Z") @ Matrix.Rotation(rng.uniform(-0.2, 0.2), 3, "X")
                        vs, M = b.box(atlas, at(c + rng.uniform(-w / 2, w / 2), 0.05, rng.choice((-1, 1)) * rng.uniform(0.12, 0.2)), (sz, sz * 0.5, 0.09), rot)   # у межах валика: габарит симетричний, лінія паркану по центру
                        atlas_uv(b, vs, M, cell, 0.3, 0.6)
                    b.tone = 1.0
                    continue
                if damaged and i == n - 1:                                         # розбита плита: нижній уламок, нахилений
                    vs, M = b.box(atlas, at(c, 0.4, 0.05), (w * 0.8, 0.09, 0.8), yaw @ Matrix.Rotation(0.25, 3, "X"))
                    atlas_uv(b, vs, M, cell, 0.0, 0.8 / hh)
                    b.tone = 1.0
                    continue
                # нахил 3.5-6° усієї панелі довкола нижнього краю; просіла чи бракована — нижчий верх
                a_ = rng.uniform(0.06, 0.1) * rng.choice((-1, 1)) if (i == lean_i or rng.random() < 0.15) else 0.0
                top = hh - (rng.uniform(0.1, 0.18) if (i == sunk_i and i != lean_i or rng.random() < 0.1) else 0.0)
                rh = top / rows
                for r_ in range(rows):
                    zr = rh * (r_ + 0.5)
                    vs, M = b.box(atlas, at(c, z0 + zr * math.cos(a_), -zr * math.sin(a_)), (w, 0.09, rh - (0.02 if rows > 1 else 0)), yaw @ Matrix.Rotation(a_, 3, "X"))
                    atlas_uv(b, vs, M, cell, r_ * rh / hh, (r_ + 1) * rh / hh)
                b.tone = 1.0
            else:
                # картка: площина вздовж плеча
                v = [b.bm.verts.new(p) for p in (at(c - w / 2, 0.08), at(c + w / 2, 0.08),
                                                 at(c + w / 2, 1.3), at(c - w / 2, 1.3))]
                f = b.bm.faces.new(v)
                f.material_index = b.mi(card)
                b.skip_uv.add(f)
                uv = b.bm.loops.layers.uv.verify()
                for l, (u, vv) in zip(f.loops, ((0, 0), (w / 0.9, 0), (w / 0.9, 1), (0, 1))):
                    l[uv].uv = (u, vv)
    finish(b, name, jpeg=(kind != "picket"), floor=0.0)                 # опора — стовпи на нулі, а не найнижча вершина


def picket_mat():
    """Штахет: 6 дощок по 0,15 м у тайлі 0,9 м (1,4 см/тексель); дошка 8 см, просвіт 7 см; планки позаду."""
    W, H = 64, 128
    rng = np.random.default_rng(31)
    x = (np.arange(W) + 0.5) / W * 0.9
    y = (np.arange(H) + 0.5) / H * 1.22 + 0.08
    idx = np.minimum((x / 0.15).astype(int), 5); fx = x / 0.15 - idx
    top = 1.26 + rng.uniform(-0.05, 0.0, 6)[idx]
    tone = rng.uniform(0.8, 1.05, 6)[idx]
    board = (np.abs(fx[None, :] - 0.5) < 0.267) & (y[:, None] < top[None, :])
    rail = (np.abs(y[:, None] - 0.4) < 0.035) | (np.abs(y[:, None] - 1.05) < 0.035)
    grain = np.tile(tile_noise(8, 3, W, 33), (2, 1))
    base = np.array([0.50, 0.41, 0.31])
    col = base * (tone[None, :, None] * (0.85 + 0.25 * grain[..., None]))
    col = np.where(board[..., None], col, col * 0.55)
    col = np.where((board & (np.abs(fx[None, :] - 0.5) > 0.19))[..., None], col * 0.55, col)   # темні краї дощок
    alpha = (board | rail).astype(float)
    a = np.concatenate([col, alpha[..., None]], -1)
    nrm = normal_from_height(grain, 2.0)
    return pbr("picket_card", albedo=a, normal=np.concatenate([nrm, np.ones((H, W, 1))], -1), tile=0.9,
               rough=0.95, alpha=True, double_sided=True)


reset()
for kind in ("sheet_green", "sheet_brown", "picket") + tuple(CONCRETE):
    for corner in (False, True):
        nm = f"infra_fence_{kind}" + ("_corner" if corner else "")
        if want(nm):
            fence(kind, corner, nm)
for kind in ("slab", "euro_stone"):                                           # пошкоджена секція: однієї плити нема, одна розбита
    nm = f"infra_fence_{kind}_damaged"
    if want(nm):
        fence(kind, False, nm, damaged=True)
