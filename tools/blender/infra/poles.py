"""Опори ліній: бетонна 10 кВ, бетонна 0,4 кВ, дерев'яна, сталева решітчаста.

Дроти не геометрія: у GLB лежать порожні вузли wire_N — точки кріплення в локальних координатах,
дроти малює дошка екранними лініями. Траверса йде вздовж X, лінія — вздовж Y (Godot Z).
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


def mats():
    concrete = pbr("pole_concrete", "Concrete034", tile=1.5, tint=(0.85, 0.85, 0.82), sat=0.7, grime=0.0,
                   rough=0.9, seed=3)
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
    b = B(); H = 7.5
    b.frustum(concrete, 0.26, 0.17, H)
    zc = 6.9
    b.box(steel, (0, 0, zc), (1.9, 0.07, 0.09))            # траверса
    b.box(steel, (0, 0.0, zc - 0.05), (0.24, 0.22, 0.05))   # хомут
    w = [insulator(b, glass, steel, -0.85, 0, zc + 0.045), insulator(b, glass, steel, 0.85, 0, zc + 0.045),
         insulator(b, glass, steel, 0, 0, H, pin=0.3)]
    w = [w[0], w[2], w[1]]
    finish(b, "infra_pole_concrete_10kv", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def pole04():
    concrete, steel, glass = mats()
    b = B(); H = 7.0
    b.frustum(concrete, 0.26, 0.17, H)
    w = []
    for i, (z, s) in enumerate(((6.6, -1), (6.6, 1), (6.2, -1), (6.2, 1))):
        b.box(steel, (s * 0.2, 0, z), (0.4, 0.05, 0.05))
        b.cyl(glass, (s * 0.38, 0, z + 0.1), 0.06, 0.16, 4)   # котушковий ізолятор
        w.append((s * 0.38, 0, z + 0.2))
    finish(b, "infra_pole_concrete_04kv", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def pole_wood():
    concrete, steel, glass = mats()
    bark = pbr("pole_wood", "Bark012", tile=1.2, tint=(0.72, 0.66, 0.58), sat=0.4, grime=0.0, rough=0.95, seed=9)
    steel = bark
    b = B(); H = 8.0
    b.cyl(bark, (0, 0, H / 2), 0.125, H, 10)
    b.box(concrete, (0, -0.235, 0.8), (0.2, 0.2, 1.6))                 # бетонна приставка, ~3 м під землею
    for z in (0.5, 1.2):
        b.box(steel, (0, -0.11, z), (0.3, 0.45, 0.025))                # бандажі
    zc = 7.35
    b.box(bark, (0, 0, zc), (1.8, 0.1, 0.12))
    w = [insulator(b, glass, steel, -0.8, 0, zc + 0.06), insulator(b, glass, steel, 0, 0, H, pin=0.28),
         insulator(b, glass, steel, 0.8, 0, zc + 0.06)]
    finish(b, "infra_pole_wood", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


def tower():
    steel = pbr("tower_steel", color=(0.40, 0.42, 0.41), rough=0.6)   # рівна оцинковка
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


def tower_lod():
    """Спрощений далекий LOD: чотири товсті ноги, кілька поясів і траверси — без діагоналей, що мерехтять."""
    steel = pbr("tower_steel", color=(0.40, 0.42, 0.41), rough=0.6)
    b = B()
    hw = lambda z: 2.6 + (1.0 - 2.6) * z / 20 if z <= 20 else 1.0 + (0.45 - 1.0) * (z - 20) / 12
    cs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for c in cs:
        for z0, z1 in ((0, 20), (20, 32)):
            b.beam(steel, (c[0] * hw(z0), c[1] * hw(z0), z0), (c[0] * hw(z1), c[1] * hw(z1), z1), 0.45, 4)
    for z in (0.3, 10, 20):
        for k in range(4):
            c0, c1 = cs[k], cs[(k + 1) % 4]
            b.beam(steel, (c0[0] * hw(z), c0[1] * hw(z), z), (c1[0] * hw(z), c1[1] * hw(z), z), 0.3, 4)
    w = []
    for z, L in ((22.5, 3.8), (26, 4.6), (29.5, 3.8)):
        b.beam(steel, (-L, 0, z), (L, 0, z), 0.3, 4)
        for s in (-1, 1):
            w.append((s * L, 0, z - 2.6))
    b.beam(steel, (0, 0, 32), (0, 0, 33.5), 0.25, 4)
    w.append((0, 0, 33.5))
    finish(b, "infra_tower_lattice_lod", [(f"wire_{i}", p) for i, p in enumerate(w)], center=True)


reset()
for n, f in (("pole10", pole10), ("pole04", pole04), ("wood", pole_wood), ("tower", tower), ("tower_lod", tower_lod)):
    if want(n):
        f()
