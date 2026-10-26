"""Мости річкової карти: три різні силуети й зруйнований стан кожного.

Запуск: blender -b --factory-startup -P tools/blender/bridges/build_bridges.py -- <out_dir>

Один світ — одиниця = клітинка = 8 м. Вісь мосту — Y у Blender (у Godot це -Z), поперек — X,
вгору — Z. Нуль Z — найнижча точка моделі (низ опори чи понтона), а верх настилу лежить на
DECK_TOP над нею: сцена ставить модель на `deck_y(клітинка) - DECK_TOP`, тоді настил збігається
з дорогою на берегах, а підошва стоїть на дні русла.

Зруйнований стан не окремий малюнок: той самий збирач, що й цілий, віддає групи частин
(прольоти, секції, плити), а `broken` лише повертає й зсуває ці групи та додає уламки.
"""
import math
import json
import os
import struct
import sys

import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]
TEX_DIR = os.path.join(OUT, "bridge_tex")  # одна текстура на матеріал для всіх шести мостів
os.makedirs(TEX_DIR, exist_ok=True)

# Суха модель: мокрота — справа гри на карті, тож ніщо тут не блищить (шорсткість >= 0.75).
# --- матеріали: (колір sRGB, шорсткість, металічність). Колір береться з текстури 512 px, що лягає
# на клітинку (8 м), тобто ~1.6 см на піксель; тут лише середній тон для довідки.
MATS = {
    "concrete": ((0.50, 0.49, 0.47), 0.95, 0.0),
    "concrete_dust": ((0.68, 0.66, 0.62), 1.0, 0.0),
    "rubble": ((0.34, 0.33, 0.31), 1.0, 0.0),
    "asphalt1": ((0.16, 0.16, 0.165), 0.95, 0.0),
    "asphalt_wet": ((0.22, 0.22, 0.225), 0.9, 0.0),
    "asphalt": ((0.16, 0.16, 0.165), 0.95, 0.0),
    "steel_gal": ((0.50, 0.52, 0.52), 0.75, 0.1),
    "steel_dark": ((0.27, 0.28, 0.27), 0.75, 0.1),
    "wet": ((0.10, 0.11, 0.11), 0.9, 0.0),
    "rust": ((0.20, 0.09, 0.05), 0.9, 0.1),
    "steel_grey": ((0.38, 0.40, 0.39), 0.75, 0.1),
    "deckplate": ((0.27, 0.29, 0.25), 0.9, 0.1),
}
MAT_ORDER = list(MATS)

# Верх настилу над нулем Z (низом моделі). Бетон і панельний міст стоять на дні, понтон плаває:
# дно русла на 2.2-2.7 м під верхом берега, вода на 1.25 м.
DECK_TOP = {"centre": 0.30, "west": 0.30, "east": 0.21}


TILE_M = 1.0  # одна текстура = клітинка (одиниця світу)


class Box:
    """Паралелепіпед без днища: підвище не видно, а трикутників менше."""

    def __init__(self, mat, c, s, rot=None):
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        self.mat = mat
        self.role = None
        self.v = [Vector(p) for p in (
            (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
            (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz))]
        if rot is not None:
            self.v = [rot @ p for p in self.v]
        self.v = [p + Vector(c) for p in self.v]
        self.uv = self._uv(c, s)

    def _uv(self, c, s):
        """Розгортка в метрах світу (тайл = 8 м = одна текстура 512 px, ~1.6 см/піксель):
        шов не залежить від розміру коробки, а щойно коробку повернули чи зсунули, текстура
        їде з нею. Асфальт — виняток: його текстура лежить упоперек, з крайовими лініями."""
        out = []
        for f in FACES:
            q = [self.v[i] for i in f]
            n = (q[1] - q[0]).cross(q[3] - q[0])
            ax = max(range(3), key=lambda k: abs(n[k]))
            if f == FACES[4] and self.mat in ("asphalt", "asphalt1", "asphalt_wet"):
                out.append([((p.x - c[0]) / s[0] + 0.5, p.y / TILE_M) for p in q])
            elif ax == 2:
                out.append([(p.x / TILE_M, p.y / TILE_M) for p in q])
            elif ax == 1:
                out.append([(p.x / TILE_M, p.z / TILE_M) for p in q])
            else:
                out.append([(p.y / TILE_M, p.z / TILE_M) for p in q])
        return out


def xf(group, m):
    for b in group:
        b.v = [m @ p for p in b.v]


def about(pivot, rot):
    """Поворот навколо точки pivot (rot — Matrix 3x3)."""
    p = Vector(pivot)
    return Matrix.Translation(p) @ rot.to_4x4() @ Matrix.Translation(-p)


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def zmin(group):
    return min(p.z for b in group for p in b.v)


def ground(group):
    """Опускає групу так, щоб її найнижча точка торкалась дна."""
    xf(group, Matrix.Translation((0, 0, -zmin(group))))


import random


def jag(face_y, sign, w, z0, z1, mat="concrete", seed=1, n=9, x0=0.0):
    """Зуби відколу на торці: грубі уламки, що виступають за площину зламу, щоб торець не був гладкою плитою."""
    r = random.Random(seed)
    out = []
    for i in range(n):
        x = x0 - w / 2 + (i + 0.5) * w / n
        d = r.uniform(0.02, 0.07)
        hh = (z1 - z0) * r.uniform(0.35, 0.9)
        zc = r.uniform(z0 + hh / 2, z1 - hh / 2)
        out.append(Box(mat, (x + r.uniform(-0.01, 0.01), face_y + sign * d / 2, zc),
                       (w / n * r.uniform(0.7, 1.2), d, hh), rx(r.uniform(-10, 10)) @ rz(r.uniform(-12, 12))))
    return out


def rebar_stubs(face_y, sign, w, z_rows, seed=2, per_row=6):
    """Арматура з торця: прути 4-5 см завтовшки і ~0.7 м завдовжки у два ряди; усі загнуті вниз
    і вбік, жоден не лежить на настилі."""
    r = random.Random(seed)
    out = []
    for zc in z_rows:
        for i in range(per_row):
            x = -w / 2 + (i + 0.5) * w / per_row + r.uniform(-0.01, 0.01)
            a = r.uniform(8, 32)
            out.append(Box("rust", (x, face_y + sign * 0.045, zc + r.uniform(-0.008, 0.008)),
                           (0.006, 0.09, 0.006), rx(-sign * a) @ rz(r.uniform(-10, 10))))
    return out


def torn_plate(face_y, sign, w, z0, z1, seed=3, n=5):
    """Обшивка понтона, розірвана на торці: відігнуті вниз лапті листа замість арматури."""
    r = random.Random(seed)
    out = []
    for i in range(n):
        x = -w / 2 + (i + 0.5) * w / n
        out.append(Box("steel_grey", (x, face_y + sign * 0.04, r.uniform(z0, z1)),
                       (w / n * 0.8, 0.08, 0.008), rx(-sign * r.uniform(25, 55)) @ rz(r.uniform(-12, 12))))
    return out


def chord_stubs(face_y, sign, xt, tw, z_low, z_top):
    """Обірвані пояси ферми: короткі обрубки, зігнуті вниз, замість високих плит на торці."""
    out = []
    for sx in (-1, 1):
        out.append(Box("steel_gal", (sx * xt, face_y + sign * 0.04, z_low), (tw, 0.1, 0.03), rx(-sign * 30)))
    return out


def wet(c, s):
    """Темна смуга мокрої поверхні на ватерлінії: контакт предмета з водою."""
    return Box("wet", c, s)


# ---------------------------------------------------------------- центр: бетонна балка, 3 клітинки
def concrete(broken):
    L, W = 3.0, 0.88
    DT = DECK_TOP["centre"]
    th = 0.14  # плита 1.1 м
    bot = DT - th
    WL = DT - 0.01 - 0.156  # вода відносно дна

    def span(y0, y1, lo=False, hi=False, seed=0):
        """Проліт: плита, асфальт, парапети зі сталевою огорожею; lo/hi — оббитий торець."""
        n = y1 - y0
        yc = (y0 + y1) / 2
        g = [Box("concrete", (0, yc, bot + th / 2), (W, n, th)),
             Box("asphalt", (0, yc, DT + 0.004), (W - 0.2, n, 0.008))]
        for sx in (-1, 1):
            g.append(Box("concrete", (sx * (W / 2 - 0.03), yc, DT + 0.055), (0.06, n, 0.11)))
            g.append(Box("steel_grey", (sx * (W / 2 - 0.03), yc, DT + 0.15), (0.035, n, 0.035)))  # поручень
        for face, sign, on in ((y0, -1, lo), (y1, 1, hi)):
            if on:
                g += jag(face, sign, W, bot, DT + 0.11, seed=seed + sign + 3)
                g += rebar_stubs(face, sign, W - 0.1, (bot + th * 0.3, bot + th * 0.7), seed=seed + sign + 9)
        return g

    # Бетон: два прольоти по 12 м на стінчастій опорі в усю ширину настилу; береги тримають упори.
    py = -0.0625 if broken else 0.0  # у руїні опора закінчується там, де обламано проліт
    pier = [Box("concrete", (0, py, bot / 2), (W - 0.02, 0.125, bot)),
            Box("concrete", (0, py, bot - 0.015), (W + 0.02, 0.125 if broken else 0.16, 0.03)),
            wet((0, py, WL), (W - 0.016, 0.133, 0.06))]
    abut = [Box("concrete", (0, sy * (L / 2 - 0.09), bot / 2), (W + 0.02, 0.18, bot)) for sy in (-1, 1)]
    abut += [wet((0, sy * (L / 2 - 0.09), WL), (W + 0.028, 0.188, 0.06)) for sy in (-1, 1)]
    if not broken:
        return {"pier": pier, "abut": abut, "span1": span(-L / 2, 0), "span2": span(0, L / 2)}

    s1 = span(-L / 2, 0, hi=True, seed=1)
    # Другий проліт відламався від опори: край біля берега просів на 5°, середня плита впала
    # вільним кінцем у воду, торкається дна й лежить під 19°; між нею й опорою щілина понад 4 м.
    near = span(1.0, L / 2 - 0.1, lo=True, seed=2)
    xf(near, about((0, L / 2 - 0.1, DT - 0.02), rx(5)))
    drop = span(0.5, 0.99, lo=True, hi=True, seed=3)
    xf(drop, about((0, 0.99, bot), rx(19.5)))
    xf(drop, about((0, 0.75, 0.2), rz(6)))
    ground(drop)
    drop.append(wet((0, 0.56, 0.067), (W + 0.008, 0.14, 0.134)))
    r = random.Random(7)
    fall = []
    for k in range(5):
        a = r.uniform(0.1, 0.17)
        b = r.uniform(0.09, 0.15)
        hgt = r.uniform(0.12, 0.2)  # над водою лишається менше половини
        x, y, yaw = 0.2 + 0.16 * (k % 2) + r.uniform(0, 0.06), 0.04 + k * 0.07, r.uniform(0, 80)
        low = min(hgt, WL)
        fall.append(Box("wet", (x, y, low / 2), (a, b, low), rz(yaw) @ rx(r.uniform(-8, 8))))
        if hgt > WL:
            fall.append(Box("rubble", (x, y, WL + (hgt - WL) / 2), (a * 0.85, b * 0.85, hgt - WL),
                            rz(yaw) @ rx(r.uniform(-14, 14)) @ ry(r.uniform(-14, 14))))
    return {"pier": pier, "abut": abut, "span1": s1, "near": near, "drop": drop, "fall": fall}


# ---------------------------------------------------------------- захід: панельна ферма
def bailey(broken):
    L = 2.0
    DT = DECK_TOP["west"]
    PL, PH = 3.0 / 8, 2.7 / 8  # панель 3.0 × 2.7 м: висота справжньої двоярусної ферми
    N = 5
    y0 = -N * PL / 2
    rw = 3.7 / 8  # проїзна частина
    tw = 0.04  # стінка ферми (0.3 м)
    xt = rw / 2 + tw / 2
    WL = DT - 0.01 - 0.156

    def panel(i):
        ya, yb = y0 + i * PL, y0 + (i + 1) * PL
        yc = (ya + yb) / 2
        g = [Box("deckplate", (0, yc, DT - 0.02), (rw, PL, 0.04)),
             Box("asphalt1", (0, yc, DT + 0.004), (rw - 0.04, PL, 0.008)),
             Box("steel_gal", (0, yc, DT - 0.05), (rw + 2 * tw, 0.03, 0.025)),
             Box("steel_gal", (0, ya + 0.015, DT - 0.045), (rw + 2 * tw, 0.02, 0.03))]
        diag_len = math.hypot(PL, PH - 0.03)
        ang = math.degrees(math.atan2(PH - 0.03, PL))
        for sx in (-1, 1):
            g.append(Box("steel_gal", (sx * xt, yc, DT + 0.015), (tw, PL, 0.03)))  # нижній пояс
            g.append(Box("steel_gal", (sx * xt, yc, DT + PH - 0.015), (tw, PL, 0.03)))  # верхній
            g[-1].role = "top"
            g.append(Box("steel_gal", (sx * xt, ya + 0.01, DT + PH / 2), (tw, 0.02, PH)))  # стійка
            for sgn in (1, -1):  # хрест у кожній панелі
                g.append(Box("steel_gal", (sx * xt, yc, DT + PH / 2), (tw - 0.01, diag_len, 0.016), rx(sgn * ang)))
                g[-1].role = "diag"
        return g

    panels = [panel(i) for i in range(N)]
    end = [Box("steel_gal", (sx * xt, sy * (N * PL / 2), DT + PH / 2), (tw, 0.02, PH))
           for sx in (-1, 1) for sy in (-1, 1)]
    # Опори: бетонні лежні на кінцях переправи; їхня довжина не виходить за 2 клітинки.
    abut = [Box("concrete", (0, sy * (L / 2 - 0.08), (DT - 0.045) / 2), (0.7, 0.16, DT - 0.045))
            for sy in (-1, 1)]
    abut += [Box("concrete", (0, sy * (L / 2 - 0.08), DT - 0.045 + 0.0), (0.74, 0.16, 0.02)) for sy in (-1, 1)]
    abut += [wet((0, sy * (L / 2 - 0.08), WL), (0.708, 0.168, 0.05)) for sy in (-1, 1)]
    if not broken:
        return {"abut": abut, "end": end, **{f"p{i}": p for i, p in enumerate(panels)}}

    # Західна половина висить на своєму березі, а її східний кінець провалився у воду під 19° і
    # розвернувся; пояси вигнуті, діагоналі випнуті. Середню панель знесло: на її місці вода й уламки.
    west = panels[0] + panels[1] + [end[0], end[2]]
    for b in panels[1]:
        if b.role == "top":
            xf([b], about((b.v[0].x, y0 + PL, DT + PH - 0.015), rx(-30)))
    for b in panels[0]:
        if b.role == "top":
            xf([b], about((b.v[0].x, y0, DT + PH - 0.015), rx(-9)))
    diags = [b for b in panels[1] + panels[0] if b.role == "diag"]
    for k, b in enumerate(diags[:4]):
        c = sum((p for p in b.v), Vector()) / 8
        xf([b], Matrix.Translation((0.035 * (1 if k % 2 else -1), 0, 0)) @ about(c, rx(16)))
    west += chord_stubs(y0 + 2 * PL, 1, xt, tw, DT + 0.015, DT + PH - 0.015)
    xf(west, about((0, y0, DT - 0.05), rx(-19)))
    xf(west, about((0, y0, DT - 0.05), rz(-8)))
    east = panels[3] + panels[4] + [end[1], end[3]] + chord_stubs(y0 + 3 * PL, -1, xt, tw, DT + 0.015, DT + PH - 0.015)
    xf(east, about((0, L / 2 - 0.06, DT), rx(10)))
    # Уламки у воді, кожен від 0.3 тайла: настил, балка й дві діагоналі лежать у розриві.
    junk = [Box("asphalt_wet", (0.44, 0.1, 0.116), (0.3, 0.26, 0.04), rx(10) @ rz(40)),
            Box("steel_gal", (-0.4, 0.0, 0.13), (0.04, 0.5, 0.04), rz(25) @ rx(10)),
            Box("steel_gal", (0.5, -0.12, 0.122), (0.03, 0.4, 0.03), rz(-35) @ rx(-4)),
            Box("steel_gal", (-0.5, 0.15, 0.122), (0.03, 0.38, 0.03), rz(30) @ rx(4))]
    junk.append(wet((0.44, 0.1, 0.1), (0.31, 0.27, 0.06)))
    return {"abut": abut, "west": west, "east": east, "junk": junk}


# ---------------------------------------------------------------- схід: понтонний міст (сталь)
def pontoon(broken):
    hh = 0.17  # поплавок 1.4 м; решта до настилу — рама
    rwid = 0.70
    wl = DECK_TOP["east"] - 0.01 - 0.156  # ватерлінія над дном
    floats = (-0.33, 0.0, 0.33)  # три окремі поплавки, між ними ~1 м темної води

    def bay(y0, y1, ramp=False, bows=()):
        n = y1 - y0
        yc = (y0 + y1) / 2
        dz = -0.03 if ramp else 0.0  # аппарель сидить нижче й піднімається до берега
        g = [Box("deckplate", (0, yc, hh + 0.02 + dz), (rwid, n - 0.012, 0.04))]
        lo = y0 + (0.06 if any(sg < 0 for _, sg in bows) else 0.0)
        hi = y1 - (0.06 if any(sg > 0 for _, sg in bows) else 0.0)
        for fx in floats:
            g.append(Box("steel_grey", (fx, (lo + hi) / 2, hh / 2), (0.2, hi - lo - 0.012, hh)))
            g.append(wet((fx, (lo + hi) / 2, wl), (0.204, hi - lo - 0.008, 0.05)))
            for yb, sg in bows:  # скошений форштевень: плита від кіля на кінці до верху корпусу
                g.append(Box("steel_grey", (fx, yb - sg * 0.03, hh / 2), (0.2, 0.012, 0.18), rx(sg * 19)))
        for sx in (-1, 1):
            g.append(Box("steel_grey", (sx * 0.455, yc, hh * 0.55), (0.03, n - 0.012, 0.045)))  # стрейк
            g.append(Box("steel_grey", (sx * (rwid / 2 + 0.012), yc, hh + 0.052 + dz), (0.024, n - 0.012, 0.032)))
        for yb, sg in bows:  # похилий з'їзд ~0.3 тайла до берега
            g.append(Box("deckplate", (0, yb - sg * 0.15, hh + 0.04), (rwid, 0.3, 0.03), rx(sg * 6)))
        return g

    # 2 клітинки замало для відсіків по 6.7 м з аппарелями: чотири відсіки довжини 0.45-0.55.
    bays = {"r0": bay(-1.0, -0.55, True, ((-1.0, -1),)), "b1": bay(-0.55, 0.0), "b2": bay(0.0, 0.55),
            "r1": bay(0.55, 1.0, True, ((1.0, 1),))}
    plates = []
    if not broken:
        return {**bays, "plates": plates}

    # Відсік b1 висить на кінці r0 і схилений вільним кінцем униз на 11°, під воду, та розвернутий за
    # течією; середній відсік знесло, від нього лишився обрубок збоку, зануреного до ватерлінії й
    # нахиленого. У розриві по обидва боки чиста вода (>0.5 тайла).
    b1 = bays["b1"] + jag(0.0, 1, 0.8, 0.0, hh * 0.7, "steel_grey", 21, 8) + torn_plate(0.0, 1, 0.8, 0.05, hh, 4)
    xf(b1, about((0, -0.55, 0.03), rx(-9)))
    xf(b1, about((0, -0.55, 0), rz(-9)))
    r1 = bays["r1"] + jag(0.55, -1, 0.8, 0.0, hh * 0.7, "steel_grey", 23, 8) + torn_plate(0.55, -1, 0.8, 0.05, hh, 6)
    frag = [Box("steel_grey", (0.0, 0.0, hh / 2), (0.2, 0.3, hh)), wet((0, 0, wl), (0.204, 0.304, 0.05)),
            Box("deckplate", (-0.04, 0.0, hh + 0.02), (0.3, 0.3, 0.04))]
    frag += jag(0.15, 1, 0.26, 0.0, hh * 0.45, "steel_dark", 31, 5) + jag(-0.15, -1, 0.26, 0.0, hh * 0.45, "steel_dark", 32, 5)
    frag += torn_plate(0.15, 1, 0.3, 0.05, hh, 7, 4) + torn_plate(-0.15, -1, 0.3, 0.05, hh, 8, 4)
    xf(frag, about((0, 0, 0), rx(-30) @ rz(35)))
    xf(frag, Matrix.Translation((0.5, 0.1, 0)))
    xf(frag, Matrix.Translation((0, 0, -0.07 - zmin(frag))))  # сидить глибше за ватерлінію, дно ще вище
    return {"r0": bays["r0"], "b1": b1, "frag": frag, "r1": r1, "plates": plates}


MODELS = {
    "bridge_river_centre": (concrete, False),
    "bridge_river_centre_broken": (concrete, True),
    "bridge_river_west": (bailey, False),
    "bridge_river_west_broken": (bailey, True),
    "bridge_river_east": (pontoon, False),
    "bridge_river_east_broken": (pontoon, True),
}


TEX = 512


def _noise(rng, sigma_x, sigma_y=None, size=TEX):
    """Тайлова шумова картинка: білий шум, відфільтрований у частотній області."""
    import numpy as np
    sigma_y = sigma_x if sigma_y is None else sigma_y
    f = np.fft.fft2(rng.standard_normal((size, size)))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    f *= np.exp(-0.5 * ((fx * size * sigma_x * 0.04) ** 2 + (fy * size * sigma_y * 0.04) ** 2) * 6.0)
    n = np.real(np.fft.ifft2(f))
    return (n - n.mean()) / (n.std() + 1e-9)


def make_texture(name):
    """Колір (sRGB), висота в метрах і крок піксельної сітки в метрах (по u, по v).
    Висота пекається в метрах ДО масштабу 1/8 тайла, тож нахил нормалі справжній."""
    import numpy as np
    rng = np.random.default_rng(sum(map(ord, name)))
    base = np.array(MATS[name][0])
    yy, xx = np.mgrid[0:TEX, 0:TEX] / TEX  # yy — рядки (v), xx — стовпці (u)
    img = np.ones((TEX, TEX, 3)) * base
    lum = np.zeros((TEX, TEX))
    h = np.zeros((TEX, TEX))
    step = (8.0 / TEX, 8.0 / TEX)  # 1.56 см на піксель
    mod = lambda a, k: (a * k) % 1.0
    if name in ("concrete", "concrete_dust", "rubble"):
        lum = 0.012 * _noise(rng, 12) + 0.02 * _noise(rng, 2.0) + 0.02 * _noise(rng, 0.7)
        lum -= 0.05 * np.clip(_noise(rng, 0.8, 14) - 0.6, 0, None)  # патьоки від води
        pores = _noise(rng, 0.6) > 2.4
        lum -= 0.04 * pores
        board = mod(yy, 6) < 0.02  # шви опалубки щитами по 1,3 м
        h = 0.006 * _noise(rng, 2.0) + 0.003 * _noise(rng, 0.7) - 0.004 * pores - 0.008 * board
        lum -= 0.015 * board
        if name == "concrete":
            joint = mod(yy, 2) < 0.01  # шов плит кожні 4 м
            h -= 0.012 * joint
            lum -= 0.02 * joint
    elif name in ("asphalt", "asphalt1", "asphalt_wet"):
        lum = 0.008 * _noise(rng, 1.0) + 0.008 * _noise(rng, 0.5) + 0.004 * _noise(rng, 8)
        for cu in (0.28, 0.72):  # смуги, виїжджені колесами
            lum -= 0.012 * np.exp(-((xx - cu) / 0.07) ** 2)
        grain = _noise(rng, 0.45) > 2.2
        lum += 0.016 * grain
        h = 0.002 * _noise(rng, 0.5) + 0.002 * grain + 0.0008 * _noise(rng, 2.0)
        for cu in (0.045, 0.955):  # крайові лінії
            w = (np.abs(xx - cu) < 0.02) * (_noise(rng, 2.0) > -1.2)
            img = np.where(w[..., None], np.array([0.36, 0.36, 0.34]) * (1 + 0.1 * _noise(rng, 0.6))[..., None], img)
        dash = (np.abs(xx - 0.5) < 0.03) & ((yy % 0.5) < 0.25) & (_noise(rng, 2.0) > -1.2) & (name == "asphalt")
        img = np.where(dash[..., None], np.array([0.33, 0.33, 0.31]) * (1 + 0.1 * _noise(rng, 0.6))[..., None], img)
        step = (0.68 * 8.0 / TEX, 8.0 / TEX)  # u лягає впоперек настилу
    elif name == "steel_gal":
        lum = 0.03 * _noise(rng, 3) + 0.02 * _noise(rng, 0.6) + 0.02 * _noise(rng, 0.8, 10)
        # Світла оцинкована сталь з темними патьоками від води, без дрібних плям.
        streak = np.clip(_noise(rng, 0.8, 10) - 0.6, 0, None)
        lum -= 0.06 * streak
        h = 0.0008 * _noise(rng, 0.6) - 0.004 * (mod(yy, 4) < 0.008) - 0.001 * streak
    elif name == "wet":
        lum = 0.01 * _noise(rng, 4)
    elif name == "rust":
        lum = 0.04 * _noise(rng, 6) + 0.03 * _noise(rng, 0.6)
        h = 0.004 * _noise(rng, 0.8)
    elif name in ("steel_grey", "steel_dark"):
        lum = 0.04 * _noise(rng, 3) + 0.04 * _noise(rng, 0.8, 10) + 0.02 * _noise(rng, 0.5)
        seam = (mod(yy, 4) < 0.01) | (mod(xx, 4) < 0.01)  # стики листів 2 м
        rib = (mod(xx, 16) < 0.016) | (mod(yy, 16) < 0.016)  # ребра жорсткості через 0,5 м
        h = 0.0012 * _noise(rng, 0.6) - 0.005 * seam + 0.012 * rib
        lum += -0.06 * seam + 0.05 * rib
    elif name == "deckplate":
        lum = 0.008 * _noise(rng, 2.5) + 0.006 * _noise(rng, 0.5)
        seam = (mod(xx, 16) < 0.012) | (mod(yy, 16) < 0.012)  # стики листів 0,5 м
        pad = _noise(rng, 6) > 1.0
        lum += -0.0 * seam
        h = 0.0012 * _noise(rng, 0.7) - 0.002 * seam
    img = np.clip(img + lum[..., None], 0, 1)
    px = np.concatenate([img, np.ones((TEX, TEX, 1))], axis=2)
    return px.astype("float32"), h, step


def bake_normal(h, step):
    """Нормаль у дотичному просторі (OpenGL, +V вгору) з висоти в метрах; шви тайляться."""
    import numpy as np
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) / (2 * step[0])
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) / (2 * step[1])
    n = np.stack([-gx, -gy, np.ones_like(h)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return np.concatenate([n * 0.5 + 0.5, np.ones((TEX, TEX, 1))], axis=2).astype("float32")



FACES = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]


TEXCACHE = {}


def _save_image(name, px, space):
    img = bpy.data.images.new(f"bridge_{name}", TEX, TEX, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = f"{TEX_DIR}/{name}.png"
    img.file_format = "PNG"
    img.save()
    img.colorspace_settings.name = space
    return img


def build(name, fn, broken):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = fn(broken)
    mats = {}
    for k in MAT_ORDER:
        c, r, m = MATS[k]
        if k not in TEXCACHE:
            TEXCACHE[k] = make_texture(k)
        col, h, step = TEXCACHE[k]
        img = _save_image(f"{k}", col, "sRGB")
        nrm = _save_image(f"{k}_n", bake_normal(h, step), "Non-Color")
        mat = bpy.data.materials.new(f"bridge_{k}")
        mat.use_nodes = True
        b = mat.node_tree.nodes["Principled BSDF"]
        t = mat.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        mat.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
        tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tn.image = nrm
        nm = mat.node_tree.nodes.new("ShaderNodeNormalMap")
        mat.node_tree.links.new(tn.outputs["Color"], nm.inputs["Color"])
        mat.node_tree.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        b.inputs["Roughness"].default_value = r
        b.inputs["Metallic"].default_value = m
        mats[k] = mat
    verts, faces, midx, uvs = [], [], [], []
    for g in groups.values():
        for b in g:
            base = len(verts)
            verts += [tuple(p) for p in b.v]
            for f, uv in zip(FACES, b.uv):
                faces.append(tuple(base + i for i in f))
                midx.append(MAT_ORDER.index(b.mat))
                uvs += uv
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for k in MAT_ORDER:
        mesh.materials.append(mats[k])
    for p, mi in zip(mesh.polygons, midx):
        p.material_index = mi
    layer = mesh.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", [c for uv in uvs for c in uv])
    mesh.update()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Нормалі назовні: порядок обходу граней задано для додатного об'єму, перевіряємо явно.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    print(f"BRIDGE {name} x[{min(xs):.3f},{max(xs):.3f}] y[{min(ys):.3f},{max(ys):.3f}] "
          f"z[{min(zs):.3f},{max(zs):.3f}] tris={sum(len(p.vertices) - 2 for p in mesh.polygons)}")
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_keep_originals=True)
    strip_image_views(f"{OUT}/{name}.glb")


def strip_image_views(path):
    """Експортер лишає в зовнішньої картинки і uri, і bufferView — це недійсне glTF."""
    d = open(path, "rb").read()
    n, _ = struct.unpack_from("<II", d, 12)
    g = json.loads(d[20:20 + n])
    for im in g.get("images", []):
        im.pop("bufferView", None)
    j = json.dumps(g, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    rest = d[20 + n:]
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(j) + len(rest)) + struct.pack("<II", len(j), 0x4E4F534A) + j + rest
    open(path, "wb").write(out)


for n, (f, b) in MODELS.items():
    build(n, f, b)
