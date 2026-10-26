"""Огорожі прямими секціями по 8 м (вздовж X) і кутовий елемент (два плеча по 4 м).

Типи: профнастил (два кольори — для різних половин мапи), декоративний бетонний «єврозабір»,
промислова панельна (ПО-2), дерев'яний штахет (картка з alpha, дошки <1 px на дальньому зумі).
Кут: стовп у куті, одне плече вздовж +X, друге вздовж +Y (Godot −Z); початок — центр габариту.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


WARM = (1.05, 1.0, 0.9)   # теплий сіро-бежевий бетон, а не нейтрально-сірий


def _stone(n):
    """Єврозабір «камінь»: нерівні опуклі камені рядами різної висоти, шви 2 см."""
    rng = np.random.default_rng(41)
    h = np.zeros((n, n)); v = 0.04
    while v < 0.96:
        rh = rng.uniform(0.1, 0.18); u = 0.04
        while u < 0.96:
            rw = rng.uniform(0.12, 0.26)
            h = np.maximum(h, box_mask(n, u, min(u + rw, 0.96), v, min(v + rh, 0.96), 0.02) * rng.uniform(0.7, 1.0))
            u += rw + 0.012
        v += rh + 0.012
    return 0.2 + 0.8 * h


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
CONCRETE = {
    "slab": dict(nom=2.0, ph=2.0, pw=0.2, seed=51, seams=True),
    "euro_stone": dict(nom=2.0, ph=1.8, pw=0.2, seed=52, relief=_stone, k=12.0),
    "euro_brick": dict(nom=2.0, ph=2.0, pw=0.2, seed=53, relief=_brick, k=10.0),
    "euro_wave": dict(nom=2.0, ph=2.2, pw=0.2, seed=54, relief=_wave, k=8.0),
    "brickpost": dict(nom=2.5, ph=1.9, pw=0.4, seed=55, brick_post=True),
    "painted_green": dict(nom=3.0, ph=2.2, pw=0.2, seed=56, relief=_ribs, paint=(0.42, 0.52, 0.40), peel=0.8, rust=3),
    "painted_beige": dict(nom=2.0, ph=1.8, pw=0.2, seed=57, paint=(0.74, 0.66, 0.52), peel=0.6),
}


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
    elif kind == "euro":
        def relief(n):   # три втоплені філенги один над одним у секції 2 × 2 м, зі скосом
            h = np.zeros((n, n))
            for v0, v1 in ((0.03, 0.31), (0.34, 0.62), (0.65, 0.93)):
                h = np.maximum(h, box_mask(n, 0.06, 0.94, v0, v1, 0.03))
            return 1 - 0.8 * h
        sheet = concrete_mat("euro_panel", tile=2.0, relief=relief, seed=25, top_z=1.9, shade=0.1, k=9.0, streak_k=0.9, streak_len=0.8, val=0.92, tint=WARM, moss=0.7, rust_runs=2, chips=True)
        post = concrete_mat("euro_post", tile=2.0, seed=26, top_z=1.95, streak_k=0.9, streak_len=0.8, val=0.92, tint=WARM, moss=0.6, chips=True)
        b.mi(post)              # перший матеріал меша Godot не фарбує вершинним кольором — тон дістається панелям
        nom, ph, pw = 2.0, 1.95, 0.2
    elif kind == "po2":
        def relief(n):   # три горизонтальні ребра й рамка по краю плити 4 × 2,5 м
            h = np.zeros((n, n))
            for z in (0.55, 1.2, 1.85):
                h = np.maximum(h, box_mask(n, 0.0, 1.0, z / 2.5 - 0.035, z / 2.5 + 0.035, 0.01))
            return 0.35 + 0.65 * h
        sheet = concrete_mat("po2_panel", tile=4.0, tile_v=2.5, relief=relief, seed=27, top_z=2.45, tint=WARM, moss=0.7, rust_runs=3, chips=True)
        post = concrete_mat("po2_post", tile=2.0, seed=28, top_z=2.45, tint=WARM, moss=0.6, chips=True)
        b.mi(post)
        nom, ph, pw = 4.0, 2.5, 0.2
    elif kind in CONCRETE:
        spec = CONCRETE[kind]
        nom, ph, pw = spec["nom"], spec["ph"], spec["pw"]
        sheet = concrete_mat(f"{kind}_panel", tile=nom, tile_v=ph, relief=spec.get("relief"), seed=spec["seed"], top_z=ph - 0.05, k=spec.get("k", 9.0),
                             streak_k=0.7, streak_len=0.9, tint=WARM, moss=0.7, rust_runs=spec.get("rust", 2), chips=True,
                             paint=spec.get("paint"), peel=spec.get("peel", 0.0), seams=spec.get("seams", False))
        if spec.get("brick_post"):
            post = pbr(f"{kind}_post", "Bricks105", tile=1.0, tint=(0.82, 0.50, 0.40), sat=0.6, grime=0.3, rough=0.9, seed=spec["seed"] + 1)
            cap = concrete_mat(f"{kind}_cap", tile=1.0, seed=spec["seed"] + 2, tint=WARM, moss=0.0)
        else:
            post = concrete_mat(f"{kind}_post", tile=2.0, seed=spec["seed"] + 1, top_z=ph, streak_k=0.7, streak_len=0.8, tint=WARM, moss=0.6, chips=True)
        b.mi(post)
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
                b.box(cap, at(s, ph + 0.04), (pw + 0.1, pw + 0.1, 0.08), yaw)          # бетонна шапка стовпа
        for i in range(n):
            c = (i + 0.5) * pitch; w = pitch - pw
            if kind.startswith("sheet"):
                t = 1 + rng.uniform(-0.25, 0.25); dh = rng.uniform(-0.07, 0.07)
                b.tone = (t * (1 + dh), t, t * (1 - dh))                                   # тон і відтінок листа
                b.box(sheet, at(c, 0.99, 0.045), (w, 0.035, 1.92), yaw)
                b.tone = 1.0
            elif kind == "euro":
                b.tone = 1 + rng.uniform(-0.12, 0.12)
                b.box(sheet, at(c, 0.9, 0), (w, 0.1, 1.8), yaw)
                b.tone = 1.0
            elif kind in CONCRETE:
                if damaged and i == 1:
                    continue                                                       # плити немає зовсім
                b.tone = 1 + rng.uniform(-0.12, 0.12)                              # кожна плита свого тону
                if damaged and i == n - 1:                                         # розбита плита: нижній уламок, нахилений
                    b.box(sheet, at(c, 0.4, 0.05), (w * 0.8, 0.09, 0.8), yaw @ Matrix.Rotation(0.25, 3, "X"))
                else:
                    b.box(sheet, at(c, ph / 2 - 0.02, 0), (w, 0.09, ph - 0.08), yaw)
                b.tone = 1.0
            elif kind == "po2":
                b.tone = 1 + rng.uniform(-0.12, 0.12)
                b.box(sheet, at(c, 1.25, 0), (w, 0.09, 2.3), yaw)
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
    finish(b, name, jpeg=(kind != "picket"))


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
for kind in ("sheet_green", "sheet_brown", "euro", "po2", "picket") + tuple(CONCRETE):
    for corner in (False, True):
        nm = f"infra_fence_{kind}" + ("_corner" if corner else "")
        if want(nm):
            fence(kind, corner, nm)
for kind in ("slab", "euro_stone"):                                           # пошкоджена секція: однієї плити нема, одна розбита
    nm = f"infra_fence_{kind}_damaged"
    if want(nm):
        fence(kind, False, nm, damaged=True)
