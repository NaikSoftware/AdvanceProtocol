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
    if kind.startswith("sheet"):
        col = {"sheet_green": (0.36, 0.52, 0.42), "sheet_brown": (0.62, 0.36, 0.28)}[kind]
        sheet = pbr(f"{kind}_panel", "CorrugatedSteel005", tile=1.15, paint=col, contrast=0.6, rust=0.2, grime=0.15,
                    rough=0.65, metal=0.1, seed=21 if kind.endswith("green") else 22)
        post = sheet
        nom, ph, pw = 2.5, 2.0, 0.08
    elif kind == "euro":
        sheet = pbr("euro_panel", "Concrete034", tile=1.5, tint=(0.66, 0.65, 0.62), sat=0.6, contrast=0.25, grime=0.25, rough=0.9, seed=25)
        post = sheet
        nom, ph, pw = 2.0, 1.95, 0.15
    elif kind == "po2":
        sheet = pbr("po2_panel", "Concrete046", tile=2.0, tint=(0.6, 0.6, 0.58), sat=0.6, contrast=0.25, grime=0.3, rough=0.95, seed=27)
        post = sheet
        nom, ph, pw = 4.0, 2.5, 0.2
    elif kind == "picket":
        sheet = None
        post = pbr("picket_post", "Planks021", tile=1.0, tint=(0.62, 0.58, 0.52), sat=0.4, grime=0.6, rough=0.95, seed=29)
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
                b.box(sheet, at(c, 1.02, 0.045), (w, 0.035, 1.8), yaw)
            elif kind == "euro":
                b.box(sheet, at(c, 0.95, 0), (w, 0.07, 1.6), yaw)
            elif kind == "po2":
                b.box(sheet, at(c, 1.25, 0), (w, 0.09, 2.3), yaw)
            else:
                # картка: площина вздовж плеча
                v = [b.bm.verts.new(p) for p in (at(c - w / 2, 0.08), at(c + w / 2, 0.08),
                                                 at(c + w / 2, 1.3), at(c - w / 2, 1.3))]
                f = b.bm.faces.new(v)
                f.material_index = b.mi(card)
                b.skip_uv.add(f)
                uv = b.bm.loops.layers.uv.verify()
                for l, (u, vv) in zip(f.loops, ((0, 0), (w / 2, 0), (w / 2, 1), (0, 1))):
                    l[uv].uv = (u, vv)
    finish(b, name, jpeg=(kind != "picket"))


def picket_mat():
    """Штахет 2 м × 1,3 м: дошка 0,1 м з проміжком, шпичаки, дві планки; різна висота й тон дощок."""
    W, H = 128, 128
    rng = np.random.default_rng(31)
    x = (np.arange(W) + 0.5) / W * 2.0                         # метри по довжині
    y = (np.arange(H) + 0.5) / H * 1.3                         # метри по висоті
    idx = np.floor(x / 0.1).astype(int); fx = (x / 0.1) - idx
    top = 1.22 + rng.uniform(-0.08, 0.0, 20)[idx]              # неоднакова висота дощок
    tone = rng.uniform(0.7, 1.05, 20)[idx]
    X, Y = np.meshgrid(np.arange(W), np.arange(H))
    ydat = y[:, None]
    pointed = top[None, :] - 0.045 * (1 - np.abs(fx[None, :] - 0.5) * 2)
    board = (np.abs(fx[None, :] - 0.5) < 0.43) & (ydat < pointed + 0.045)
    rail = ((np.abs(ydat - 0.4) < 0.03) | (np.abs(ydat - 1.05) < 0.03))
    alpha = (board | (rail & (idx[None, :] >= 0))).astype(float)
    grain = fbm(W, 33, 8, 2)
    base = np.array([0.62, 0.56, 0.48])
    col = base * (tone[None, :, None] * (0.75 + 0.4 * grain[..., None]))
    col = np.where(rail[..., None] & ~board[..., None], col * 0.6, col)
    a = np.concatenate([col, alpha[..., None]], -1)[::-1]    # рядок 0 знизу, як у Blender
    nrm = normal_from_height(grain, 6.0)
    return pbr("picket_card", albedo=a, normal=np.concatenate([nrm, np.ones((H, W, 1))], -1), tile=2.0,
               rough=0.95, alpha=True, double_sided=True)


reset()
for kind in ("sheet_green", "sheet_brown", "euro", "po2", "picket"):
    for corner in (False, True):
        nm = f"infra_fence_{kind}" + ("_corner" if corner else "")
        if want(nm):
            fence(kind, corner, nm)
