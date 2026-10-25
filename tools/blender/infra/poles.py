"""Опори ліній: бетонна 10 кВ, бетонна 0,4 кВ, дерев'яна, сталева решітчаста.

Дроти не геометрія: у GLB лежать порожні вузли wire_N — точки кріплення в локальних координатах,
дроти малює дошка екранними лініями. Траверса йде вздовж X, лінія — вздовж Y (Godot Z).
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


def mats():
    concrete = concrete_mat("pole_concrete", tile=2.0, seed=3, ground=False)
    steel = pbr("pole_steel", "MetalPlates013", tile=1.0, tint=(0.7, 0.72, 0.7), sat=0.5, rust=0.0,
                grime=0.0, rough=0.6, metal=0.1, seed=5)
    return concrete, steel, concrete          # ізолятор з бетонного матеріалу: світла крапка, менше викликів


def insulator(b, glass, steel, x, y, z0, pin=0.18):
    """Штирьовий ізолятор: сталевий штир і керамічний дзвін; повертає точку кріплення дроту."""
    # ізолятор — єдина дрібна геометрія: 4-гранна призма ~20 см, світла крапка на траверсі
    b.cyl(glass, (x, y, z0 + 0.1), 0.08, 0.2, 4, r2=0.05)
    return (x, y, z0 + 0.2)


def pole10():
    concrete, steel, glass = mats()
    b = B(); H = 10.5
    b.frustum(concrete, 0.30, 0.17, H)
    zc = H - 0.6
    b.box(steel, (0, 0, zc), (1.9, 0.07, 0.09))            # траверса
    b.box(steel, (0, 0.0, zc - 0.05), (0.24, 0.22, 0.05))   # хомут
    w = [insulator(b, glass, steel, -0.85, 0, zc + 0.045), insulator(b, glass, steel, 0.85, 0, zc + 0.045),
         insulator(b, glass, steel, 0, 0, H, pin=0.3)]
    w = [w[0], w[2], w[1]]
    finish(b, "infra_pole_concrete_10kv", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def pole04():
    concrete, steel, glass = mats()
    b = B(); H = 9.5
    b.frustum(concrete, 0.30, 0.17, H)
    w = []
    for i, (z, s) in enumerate(((H - 0.4, -1), (H - 0.4, 1), (H - 0.8, -1), (H - 0.8, 1))):
        b.box(steel, (s * 0.2, 0, z), (0.4, 0.05, 0.05))
        b.cyl(glass, (s * 0.38, 0, z + 0.1), 0.06, 0.16, 4)   # котушковий ізолятор
        w.append((s * 0.38, 0, z + 0.2))
    finish(b, "infra_pole_concrete_04kv", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def pole_wood():
    concrete, steel, glass = mats()
    bark = pbr("pole_wood", "Bark012", tile=1.2, tint=(0.72, 0.66, 0.58), sat=0.4, grime=0.0, rough=0.95, seed=9)
    steel = bark
    b = B(); H = 9.0
    b.cyl(bark, (0, 0, H / 2), 0.125, H, 10)
    b.box(concrete, (0, -0.235, 0.8), (0.2, 0.2, 1.6))                 # бетонна приставка, ~3 м під землею
    for z in (0.5, 1.2):
        b.box(steel, (0, -0.11, z), (0.3, 0.45, 0.025))                # бандажі
    zc = H - 0.65
    b.box(bark, (0, 0, zc), (1.8, 0.1, 0.12))
    w = [insulator(b, glass, steel, -0.8, 0, zc + 0.06), insulator(b, glass, steel, 0, 0, H, pin=0.28),
         insulator(b, glass, steel, 0.8, 0, zc + 0.06)]
    finish(b, "infra_pole_wood", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def galv():
    """Оцинковка: рівний сірий із ледь помітними розводами й дрібним зерном у нормалі (3 см/тексель)."""
    n = 64
    streak = tile_noise(6, 2, n, 91)
    a = np.array([0.45, 0.47, 0.46])[None, None, :] * (0.94 + 0.1 * streak[..., None])
    h = tile_noise(24, 24, n, 92)
    return pbr("tower_steel", albedo=a, normal=np.concatenate([normal_from_height(h, 1.5), np.ones((n, n, 1))], -1),
               tile=2.0, rough=0.6)


def tower():
    steel = galv()
    glass = steel
    b = B()
    levels = [0, 5, 10, 15, 20, 22.5, 26, 29.5, 32]
    def hw(z):
        return 2.6 + (1.0 - 2.6) * z / 20 if z <= 20 else 1.0 + (0.45 - 1.0) * (z - 20) / 12
    r_leg, r_m = 0.22, 0.12
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    P = lambda z, c: (c[0] * hw(z), c[1] * hw(z), z)
    for i in range(len(levels) - 1):
        z0, z1 = levels[i], levels[i + 1]
        for c in corners:
            b.beam(steel, P(z0, c), P(z1, c), r_leg, 3)
        for k in range(4):                                   # одна діагональ на грань, зигзагом
            c0, c1 = corners[k], corners[(k + 1) % 4]
            if (i + k) % 2 == 0:
                b.beam(steel, P(z0, c0), P(z1, c1), r_m, 3)
            else:
                b.beam(steel, P(z0, c1), P(z1, c0), r_m, 3)
    for z in levels[1:-1]:
        for k in range(4):
            b.beam(steel, P(z, corners[k]), P(z, corners[(k + 1) % 4]), r_m, 3)
    w = []
    for z, L in ((22.5, 3.8), (26, 4.6), (29.5, 3.8)):
        for s in (-1, 1):
            x0 = s * hw(z)
            b.beam(steel, (x0, 0, z), (s * L, 0, z), 0.14, 3)                       # нижній пояс
            b.beam(steel, (x0, 0, z + 1.4), (s * L, 0, z), 0.12, 3)                 # верхній розкіс
            b.beam(steel, (x0, 0, z + 1.4), (s * (hw(z) + (L - hw(z)) * 0.5), 0, z), 0.1, 3)
            b.cyl(glass, (s * L, 0, z - 1.3), 0.09, 2.6, 4)                         # підвісна гірлянда
            w.append((s * L, 0, z - 2.6))
    b.beam(steel, (0, 0, 32), (0, 0, 33.5), 0.12, 3)
    w.append((0, 0, 33.5))                                                          # грозотрос
    finish(b, "infra_tower_lattice", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def lattice_card_mat():
    """Решітка однієї грані (u 0..1 від ноги до ноги, v = висота/32 м): пояси й діагоналі панелей, alpha-маска."""
    W, H = 64, 256
    levels = [0, 5, 10, 15, 20, 22.5, 26, 29.5, 32]
    yy, xx = np.mgrid[0:H, 0:W]
    v = (yy + 0.5) / H * 32.0
    u = (xx + 0.5) / W
    alpha = np.zeros((H, W))
    def seg(p0, p1, wpx):
        # відстань у текселях до відрізка (u, v) -> піксельні координати
        x0, y0 = p0[0] * W, p0[1] / 32.0 * H
        x1, y1 = p1[0] * W, p1[1] / 32.0 * H
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((xx + 0.5 - x0) * dx + (yy + 0.5 - y0) * dy) / (dx * dx + dy * dy + 1e-9), 0, 1)
        d = np.hypot(xx + 0.5 - (x0 + t * dx), yy + 0.5 - (y0 + t * dy))
        return d < wpx
    for i in range(len(levels) - 1):
        z0, z1 = levels[i], levels[i + 1]
        alpha = np.maximum(alpha, seg((0, z0), (1, z0), 3.0))
        a, b2 = ((0, z0), (1, z1)) if i % 2 == 0 else ((1, z0), (0, z1))
        alpha = np.maximum(alpha, seg(a, b2, 2.6))
    alpha = np.maximum(alpha, seg((0, 0), (0, 32), 3.4))
    alpha = np.maximum(alpha, seg((1, 0), (1, 32), 3.4))
    col = np.ones((H, W, 3)) * np.array([0.45, 0.47, 0.46])
    a = np.concatenate([col, alpha[..., None]], -1)
    return pbr("tower_lattice_card", albedo=a, tile=2.0, rough=0.6, alpha=True, double_sided=True)


def tower_lod():
    """Далекий LOD: чотири грані з alpha-решіткою (той самий силует), траверси — тонкі балки, без діагоналей-геометрії."""
    steel = galv()
    card = lattice_card_mat()
    b = B()
    hw = lambda z: 2.6 + (1.0 - 2.6) * z / 20 if z <= 20 else 1.0 + (0.45 - 1.0) * (z - 20) / 12
    cs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    uv = b.bm.loops.layers.uv.verify()
    idx = b.mi(card)
    for k in range(4):
        c0, c1 = cs[k], cs[(k + 1) % 4]
        for z0, z1 in ((0, 20), (20, 32)):
            vs = [b.bm.verts.new((c[0] * hw(z), c[1] * hw(z), z)) for c, z in ((c0, z0), (c1, z0), (c1, z1), (c0, z1))]
            f = b.bm.faces.new(vs)
            f.material_index = idx
            b.skip_uv.add(f)
            for l, (u, vv) in zip(f.loops, ((0, z0), (1, z0), (1, z1), (0, z1))):
                l[uv].uv = (u, vv / 32.0)
    w = []
    for z, L in ((22.5, 3.8), (26, 4.6), (29.5, 3.8)):
        b.beam(steel, (-L, 0, z), (L, 0, z), 0.2, 3)
        for s in (-1, 1):
            w.append((s * L, 0, z - 2.6))
    b.beam(steel, (0, 0, 32), (0, 0, 33.5), 0.2, 3)
    w.append((0, 0, 33.5))
    finish(b, "infra_tower_lattice_lod", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True, jpeg=False)


reset()
for n, f in (("pole10", pole10), ("pole04", pole04), ("wood", pole_wood), ("tower", tower), ("tower_lod", tower_lod)):
    if want(n):
        f()
