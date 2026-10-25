"""Огорожі прямими секціями по 8 м (вздовж X) і кутовий елемент (два плеча по 4 м).

Типи: профнастил (два кольори — для різних половин мапи), декоративний бетонний «єврозабір»,
промислова панельна (ПО-2), дерев'яний штахет (картка з alpha, дошки <1 px на дальньому зумі).
Кут: стовп у куті, одне плече вздовж +X, друге вздовж +Y (Godot −Z); початок — центр габариту.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


def runs(corner):
    return [((-4, 0), (1, 0), 8)] if not corner else [((0, 0), (1, 0), 4), ((0, 0), (0, 1), 4)]


def fence(kind, corner, name):
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
        sheet = concrete_mat("euro_panel", tile=2.0, relief=relief, seed=25, top_z=1.9, shade=0.1, k=9.0, streak_k=0.9, streak_len=0.8)
        post = concrete_mat("euro_post", tile=2.0, seed=26, top_z=1.95, streak_k=0.9, streak_len=0.8)
        b.mi(post)              # перший матеріал меша Godot не фарбує вершинним кольором — тон дістається панелям
        nom, ph, pw = 2.0, 1.95, 0.2
    elif kind == "po2":
        def relief(n):   # три горизонтальні ребра й рамка по краю плити 4 × 2,5 м
            h = np.zeros((n, n))
            for z in (0.55, 1.2, 1.85):
                h = np.maximum(h, box_mask(n, 0.0, 1.0, z / 2.5 - 0.035, z / 2.5 + 0.035, 0.01))
            return 0.35 + 0.65 * h
        sheet = concrete_mat("po2_panel", tile=4.0, tile_v=2.5, relief=relief, seed=27, top_z=2.45)
        post = concrete_mat("po2_post", tile=2.0, seed=28, top_z=2.45)
        b.mi(post)
        nom, ph, pw = 4.0, 2.5, 0.2
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
        for i in range(n):
            c = (i + 0.5) * pitch; w = pitch - pw
            if kind.startswith("sheet"):
                t = 1 + rng.uniform(-0.25, 0.25); dh = rng.uniform(-0.07, 0.07)
                b.tone = (t * (1 + dh), t, t * (1 - dh))                                   # тон і відтінок листа
                b.box(sheet, at(c, 0.99, 0.045), (w, 0.035, 1.92), yaw)
                b.tone = 1.0
            elif kind == "euro":
                b.tone = 1 + rng.uniform(-0.2, 0.2)
                b.box(sheet, at(c, 0.9, 0), (w, 0.1, 1.8), yaw)
                b.tone = 1.0
            elif kind == "po2":
                b.tone = 1 + rng.uniform(-0.2, 0.2)
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
for kind in ("sheet_green", "sheet_brown", "euro", "po2", "picket"):
    for corner in (False, True):
        nm = f"infra_fence_{kind}" + ("_corner" if corner else "")
        if want(nm):
            fence(kind, corner, nm)
