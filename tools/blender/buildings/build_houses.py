"""Сільські будинки H1-H4, пошкоджений H1 і руїни H1, H3 — у тому самому конвеєрі й тими самими
матеріалами, що решта будівель. Розміри з брифу, слід — ціле число тайлів (меш усередині,
виступ не більше 0.1 тайла). Фронт — +Y, коник уздовж X. Камера гри бачить боки -Y і +X, тому
пошкодження скрізь на цих боках."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, chunks, mound, wall_run, bent_sheet

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


def sills(b, x, y, sgn, w, z, axis):
    if axis == "y":
        b.box(x, y + 0.07 * sgn, z - 0.1, w + 0.3, 0.14, 0.1, "step")
    else:
        b.box(x + 0.07 * sgn, y, z - 0.1, 0.14, w + 0.3, 0.1, "step")


def blown(b, x, y, sgn, z, w, h, axis="y"):
    """Вибите вікно: чорний проріз і довгі кіптявні язики над ним."""
    e = 0.03 * sgn
    if axis == "y":
        quad = [(x - w / 2, y + e, z), (x + w / 2, y + e, z), (x + w / 2, y + e, z + h), (x - w / 2, y + e, z + h)]
        tongues = [[(x - w / 2 + 0.1, y + e, z + h), (x - w / 2 + 0.5, y + e, z + h), (x - w / 2 + 0.3, y + e, z + h + 1.3)],
                   [(x + 0.05, y + e, z + h), (x + 0.55, y + e, z + h), (x + 0.25, y + e, z + h + 1.9)],
                   [(x + w / 2 - 0.5, y + e, z + h), (x + w / 2 - 0.1, y + e, z + h), (x + w / 2 - 0.3, y + e, z + h + 1.0)]]
    else:
        quad = [(x + e, y - w / 2, z), (x + e, y + w / 2, z), (x + e, y + w / 2, z + h), (x + e, y - w / 2, z + h)]
        tongues = [[(x + e, y - w / 2 + 0.1, z + h), (x + e, y - w / 2 + 0.5, z + h), (x + e, y - w / 2 + 0.3, z + h + 1.3)],
                   [(x + e, y + 0.05, z + h), (x + e, y + 0.55, z + h), (x + e, y + 0.25, z + h + 1.8)]]
    flip = (sgn < 0) if axis == "y" else (sgn < 0)
    b.poly(quad[::-1] if flip else quad, "dark")
    for t in tongues:
        b.poly(t[::-1] if flip else t, "soot")


def win_front(b, y, sgn, xs, z, w=1.2, h=1.4, bl=()):
    for x in xs:
        if x in bl:
            blown(b, x, y, sgn, z, w, h)
        else:
            b.window(("y", y, sgn), x, z, w, h)
        sills(b, x, y, sgn, w, z, "y")


def win_side(b, x, sgn, ys, z, w=1.2, h=1.4, bl=()):
    for y in ys:
        if y in bl:
            blown(b, x, y, sgn, z, w, h, "x")
        else:
            b.window(("x", x, sgn), y, z, w, h)
        sills(b, x, y, sgn, w, z, "x")


def gutter(b, x0, x1, y, z):
    b.box((x0 + x1) / 2, y, z, x1 - x0, 0.14, 0.14, "gutter")


def post(b, x, y, z0, h):
    b.box(x, y, z0, 0.18, 0.18, h, "pvc")


# ----------------------------------------------------------------------- H1
def house1(hit=False):
    lib.reset()
    b = Builder()
    L, Db, EAVE, RIDGE = 10.0, 6.4, 3.0, 5.8      # корпус 10 x 6.4, веранда ще 1.6 м (разом 8 м)
    y0, y1 = -4.0, 2.4
    b.box(0, (y0 + y1) / 2, 0, L, Db, 0.5, "brick_grey")
    b.box(0, (y0 + y1) / 2, 0.5, L - 0.02, Db - 0.02, EAVE - 0.5, "wall_plaster")
    ym = (y0 + y1) / 2
    d = Db / 2
    OV = 0.5
    xa, xb, ya, yb = -L / 2 - OV, L / 2 + OV, y0 - OV, y1 + OV
    xr0, xr1 = -L / 2 + d, L / 2 - d
    b.poly([(xa, yb, EAVE), (xa, ya, EAVE), (xr0, ym, RIDGE)], "fc_roof")
    b.poly([(xb, ya, EAVE), (xb, yb, EAVE), (xr1, ym, RIDGE)], "fc_roof")
    if not hit:
        b.poly([(xa, ya, EAVE), (xb, ya, EAVE), (xr1, ym, RIDGE), (xr0, ym, RIDGE)], "fc_roof_x")
        b.poly([(xb, yb, EAVE), (xa, yb, EAVE), (xr0, ym, RIDGE), (xr1, ym, RIDGE)], "fc_roof_x")
    else:
        def P(u, v):                                   # похилий скат -Y, що його бачить камера
            e = (xa + (xb - xa) * u, ya, EAVE)
            r = (xr0 + (xr1 - xr0) * u, ym, RIDGE)
            return tuple(e[i] * (1 - v) + r[i] * v for i in range(3))
        # пролом розривається через коник: з лівого боку зубцями, з правого — косим розривом
        b.poly_up([P(0, 0), P(0.2, 0), P(0.24, 0.35), P(0.14, 0.55), P(0.2, 0.8), P(0.1, 1.0), P(0, 1.0)], "fc_roof_x")
        b.poly_up([P(0.78, 0), P(1, 0), P(1, 1.0), P(0.88, 1.0), P(0.82, 0.7), P(0.9, 0.5), P(0.8, 0.28)], "fc_roof_x")
        b.poly_up([P(0.2, 0), P(0.78, 0), P(0.74, 0.1), P(0.66, 0.2), P(0.56, 0.08), P(0.46, 0.2), P(0.36, 0.1), P(0.28, 0.2)], "fc_roof_x")
        # +Y скат з надірваним гребенем
        b.poly_up([(xb, yb, EAVE), (xa, yb, EAVE), (xr0, ym, RIDGE), (-1.2, ym + 0.2, RIDGE - 0.4), (0.0, ym + 0.8, RIDGE - 1.2), (1.4, ym + 0.3, RIDGE - 0.6), (xr1, ym, RIDGE)], "fc_roof_x")
        for k in range(8):                              # оголені обвуглені крокви в проломі
            u = 0.22 + 0.07 * k
            b.beam(P(u, 0.04), P(u + 0.01, 0.97), 0.14, "boards", 0.2)
        b.beam(P(0.2, 0.55), P(0.78, 0.6), 0.14, "char", 0.2)
        b.poly([(-4.6, y0 + 0.2, EAVE - 0.1), (4.6, y0 + 0.2, EAVE - 0.1), (4.6, y1 - 0.2, EAVE - 0.1), (-4.6, y1 - 0.2, EAVE - 0.1)][::-1], "floor_dark")
        bent_sheet(b, P(0.22, 0.45), (xa + 2.2, y0 + 0.9, 2.5), 1.0, "fc_roof_x", 0.2)
    if not hit:
        b.box(0, ym, RIDGE, xr1 - xr0 + 0.6, 0.3, 0.16, "metal_dark")
    else:
        b.box(-3.2 + 0.2, ym, RIDGE, 1.6, 0.3, 0.16, "metal_dark")
        b.box(3.2 - 0.2, ym, RIDGE, 1.6, 0.3, 0.16, "metal_dark")
    b.box(2.2, -0.2, 4.0, 0.75, 0.75, 3.3, "brick_face", top="brick_grey")        # цегляний димар
    bl = (-3.2, 0.0) if hit else ()
    win_front(b, y0, -1, (-3.2, 0.0, 3.2), 1.0, bl=bl)
    win_front(b, y1, 1, (-4.0, 4.0), 1.0)
    win_side(b, -L / 2, -1, (-1.0,), 1.0)
    win_side(b, L / 2, 1, (-1.0, 1.0), 1.0, bl=((-1.0,) if hit else ()))
    b.box(-3.9, y1 + 0.03, 0.5, 1.0, 0.06, 2.0, "pvc")
    b.box(0, 3.2, 0, 6.0, 1.6, 0.35, "step", top="step")                         # засклена веранда
    for px in (-3.0, -1.0, 1.0, 3.0):
        post(b, px, 3.9, 0.35, 2.2)
    for px in (-2.0, 0.0, 2.0):
        b.window(("y", 3.92, 1), px, 0.6, 1.8, 1.55)
    b.poly_up([(-3.4, 2.4, 2.75), (3.4, 2.4, 2.75), (3.4, 4.3, 2.35), (-3.4, 4.3, 2.35)], "fc_roof_x")
    b.box(0, 4.15, 0.0, 1.2, 0.5, 0.25, "step")
    gutter(b, -L / 2 - OV, L / 2 + OV, y0 - OV, EAVE - 0.3)
    if hit:
        # обгорілі смуги по стіні й купи завалу з видимих боків (-Y вузька смуга, +X широкий язик)
        b.box_e(5.1, 0.0, 0.5, 1.0, 3.0, 1.0, "char")
        mound(b, 0.0, -4.2, 3.0, 0.36, 0.8, 51, rings=4, segs=16)
        mound(b, 6.4, -0.4, 1.7, 2.3, 1.5, 52)
        chunks(b, 6.4, -0.4, 1.3, 1.2, 12, ("brick_face", "wall_plaster"), 53, smin=0.4, smax=0.9)
        rr = random.Random(54)
        for k in range(10):
            b.box_e(rr.uniform(-3.2, 3.2), -4.15 + rr.uniform(-0.2, 0.15), 0.2, rr.uniform(0.35, 0.6), rr.uniform(0.3, 0.45), rr.uniform(0.2, 0.4), rr.choice(("brick_face", "rubble")),
                    euler=(rr.uniform(-0.4, 0.4), rr.uniform(-0.4, 0.4), rr.uniform(0, 3.1)))
    lib.finish(b, "house_h1_hit" if hit else "house_h1", out, tri_limit=2600, footprint=(2, 1), anchor=(0, 0))


# ----------------------------------------------------------------------- H2
def house2():
    lib.reset()
    b = Builder()
    L, D, EAVE, RIDGE = 11.0, 9.0, 3.2, 7.0
    y0, y1 = -D / 2, D / 2
    b.box(0, 0, 0, L, D, 0.5, "brick_grey")
    b.box(0, 0, 0.5, L - 0.02, D - 0.02, EAVE - 0.5, "brick_face")
    b.gable(-L / 2, L / 2, y0, y1, EAVE, RIDGE, "tile_brown", "brick_face", ridge_axis="x", overhang=0.4)
    b.box(0, 0, RIDGE, L + 0.8, 0.3, 0.18, "metal_dark")
    b.box(-2.5, 0.4, 4.4, 0.6, 0.6, 3.4, "brick_face", top="brick_grey")
    win_front(b, y1, 1, (-4.0, 4.0), 1.1)
    win_front(b, y0, -1, (-3.5, 0.0, 3.5), 1.1)
    win_side(b, -L / 2, -1, (-1.5, 1.5), 1.1)
    win_side(b, L / 2, 1, (-1.5, 1.5), 1.1)
    b.box(0, y1 + 1.0, 0, 3.2, 2.0, 2.7, "brick_face", top="tile_brown")
    b.box(0, y1 + 2.02, 0, 1.2, 0.04, 2.1, "dark")
    b.box(0, y1 + 2.0, 0, 1.8, 0.9, 0.2, "step")
    b.window(("x", 1.6, 1), y1 + 1.0, 1.0, 0.9, 1.0)
    b.window(("x", -1.6, -1), y1 + 1.0, 1.0, 0.9, 1.0)
    b.box(L / 2 + 0.3, 0.0, 5.0, 0.15, 0.7, 0.7, "pvc")
    gutter(b, -L / 2 - 0.4, L / 2 + 0.4, y1 + 0.4, EAVE - 0.3)
    gutter(b, -L / 2 - 0.4, L / 2 + 0.4, y0 - 0.4, EAVE - 0.3)
    lib.finish(b, "house_h2", out, tri_limit=2200, footprint=(2, 2))


# ----------------------------------------------------------------------- H3
def house3():
    lib.reset()
    b = Builder()
    L, D, EAVE, RIDGE = 10.0, 10.0, 6.0, 9.5
    y0, y1 = -D / 2, D / 2
    OV = 0.5
    b.box(0, 0, 0, L, D, 1.0, "brick_grey")
    b.box(0, 0, 1.0, L - 0.02, D - 0.02, EAVE - 1.0, "wall_plaster")
    b.gable(-L / 2, L / 2, y0, y1, EAVE, RIDGE, "tile_graphite", "wall_plaster", ridge_axis="x", overhang=OV)
    b.box(0, 0, RIDGE, L + 1.0, 0.3, 0.18, "metal_dark")
    # фотоелектрична батарея 5 x 3.4 м на скаті, який бачить камера (-Y)
    run = -(y0 - OV)
    sl = math.hypot(run, RIDGE - EAVE)
    ny, nz = (RIDGE - EAVE) / sl, run / sl

    def pv(x, s):
        return (x, -(run - s * run / sl + 0.05 * ny), EAVE + s * (RIDGE - EAVE) / sl + 0.05 * nz)
    b.poly_up([pv(-2.5, 1.2), pv(2.5, 1.2), pv(2.5, 4.6), pv(-2.5, 4.6)], "pv")
    for fl, z in ((0, 1.5), (1, 4.2)):
        win_front(b, y1, 1, (-3.5, 0.0, 3.5) if fl else (-3.5, 3.5), z, 1.3, 1.5)
        win_front(b, y0, -1, (-3.5, 0.0, 3.5), z, 1.3, 1.5)
        win_side(b, -L / 2, -1, (-2.0, 2.0), z, 1.3, 1.5)
        win_side(b, L / 2, 1, (-2.0, 2.0), z, 1.3, 1.5)
    b.box(0, y1 + 0.03, 1.0, 1.2, 0.06, 2.2, "dark")
    for px in (-1.4, 1.4):
        post(b, px, y1 + 1.5, 1.0, 2.4)
    b.poly_up([(-1.8, y1, 3.5), (1.8, y1, 3.5), (1.8, y1 + 1.7, 3.1), (-1.8, y1 + 1.7, 3.1)], "tile_graphite")
    b.box(0, y1 + 1.4, 0.0, 3.2, 1.6, 1.0, "step", top="step")
    gutter(b, -L / 2 - OV, L / 2 + OV, y1 + OV, EAVE - 0.3)
    gutter(b, -L / 2 - OV, L / 2 + OV, y0 - OV, EAVE - 0.3)
    lib.finish(b, "house_h3", out, tri_limit=2400, footprint=(2, 2))


# ----------------------------------------------------------------------- H4
def house4():
    lib.reset()
    b = Builder()
    L, D, EAVE, RIDGE = 9.0, 6.0, 2.8, 5.5
    y0, y1 = -D / 2, D / 2
    b.box(0, 0, 0, L, D, 0.4, "brick_grey")
    b.box(0, 0, 0.4, L - 0.02, D - 0.02, EAVE - 0.4, "boards")
    b.gable(-L / 2, L / 2, y0, y1, EAVE, RIDGE, "tin_green", "boards", ridge_axis="x", overhang=0.4)
    b.box(0, 0, RIDGE, L + 0.8, 0.28, 0.16, "metal_dark")
    win_front(b, y1, 1, (-3.0, 3.0), 0.9, 1.0, 1.2)
    win_front(b, y0, -1, (-2.5, 2.5), 0.9, 1.0, 1.2)
    win_side(b, -L / 2, -1, (0.0,), 0.9, 1.0, 1.2)
    win_side(b, L / 2, 1, (0.0,), 0.9, 1.0, 1.2)
    b.box(0, y1 + 0.03, 0.4, 1.0, 0.06, 2.0, "dark")
    for px in (-1.1, 1.1):
        post(b, px, y1 + 1.4, 0.4, 2.2)
    b.poly_up([(-1.5, y1, 2.7), (1.5, y1, 2.7), (1.5, y1 + 1.6, 2.3), (-1.5, y1 + 1.6, 2.3)], "tin_green")
    b.box(0, y1 + 1.0, 0, 3.0, 1.4, 0.4, "step", top="step")
    b.box(2.8, -0.8, 4.2, 0.7, 0.7, 2.2, "brick_face", top="brick_grey")           # цегляний димар
    lib.finish(b, "house_h4", out, tri_limit=1800, footprint=(2, 1))


# ----------------------------------------------------------------------- руїни
def ruin(name, L, D, keep, seed, footprint, chimney=None, tile="tile_graphite"):
    """Руїна: суцільна купа з текстурою на 1.5-2.5 м, уламки стін від 0.5 м до поверху з косими
    верхами, відкриті крокви й листи, відсип 1-2 м за стінами."""
    lib.reset()
    b = Builder()
    rnd = random.Random(seed)
    x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
    sides = (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0)))
    for si, (p0, p1) in enumerate(sides):
        ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        n = int(ln)
        hs = [rnd.uniform(0.6, 2.8)]
        for i in range(n):
            hs.append(min(3.0, max(0.5, hs[-1] + rnd.uniform(-1.2, 1.2))))
        gone = 0
        for i in range(n + 1):
            if gone > 0:
                hs[i] = 0.0
                gone -= 1
            elif rnd.random() > keep:
                hs[i] = 0.0
                gone = rnd.choice((1, 2, 3))
        wall_run(b, (p0[0], p0[1]), (p1[0], p1[1]), 0.4, hs, "wall_plaster", "brick_face", seed * 3 + si)
    if chimney:
        cx, cy = chimney
        b.box(cx, cy, 0, 0.8, 0.8, 3.2, "brick_face")
        b.box_e(cx + 0.05, cy, 4.0, 0.8, 0.8, 1.5, "brick_face", euler=(0.12, -0.14, 0.3), top="char")
    # одна суцільна купа: 1.5-2.5 м у центрі, виходить за стіни на 1-2 м
    mound(b, 0.0, 0.0, L / 2 + 1.7, D / 2 + 1.7, 2.4, seed + 1, rings=7, segs=24)
    mound(b, rnd.uniform(-2, 2), rnd.uniform(-1.5, 1.5), L / 3, D / 3, 1.2, seed + 2, z0=1.2, rings=4, segs=14)
    chunks(b, 0.0, 0.0, min(L, D) / 2 - 0.6, 1.4, 34, ("brick_face", "wall_plaster", "rubble", "brick_grey"), seed + 3, z0=1.0, smin=0.5, smax=1.4)
    for k in range(26):                                                           # дрібніший відсип навколо
        a = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(1.0, 1.8)
        b.box_e((L / 2 + rr) * math.cos(a) * 0.98, (D / 2 + rr) * math.sin(a) * 0.98, 0.18, rnd.uniform(0.4, 0.9), rnd.uniform(0.4, 0.8), rnd.uniform(0.25, 0.5),
                rnd.choice(("brick_face", "rubble", "wall_plaster")), euler=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(0, 3.1)))
    for k in range(12):                                                           # відкриті крокви
        cx, cy = rnd.uniform(x0 + 1.5, x1 - 1.5), rnd.uniform(y0 + 1.5, y1 - 1.5)
        a = rnd.uniform(0, 3.1)
        ln = rnd.uniform(2.5, 4.0)
        b.beam((cx, cy, rnd.uniform(0.9, 1.6)), (cx + ln * math.cos(a) * 0.6, cy + ln * math.sin(a) * 0.6, rnd.uniform(2.0, 3.4)), 0.16, rnd.choice(("boards", "char")), 0.22)
    for k in range(9):                                                            # зігнуті листи на купі
        cx, cy = rnd.uniform(x0 + 1, x1 - 1), rnd.uniform(y0 + 1, y1 - 1)
        a = rnd.uniform(0, 3.1)
        ln = rnd.uniform(1.8, 2.8)
        bent_sheet(b, (cx, cy, rnd.uniform(1.4, 2.2)), (cx + ln * math.cos(a), cy + ln * math.sin(a), rnd.uniform(0.6, 1.3)), 1.1, rnd.choice((tile, "fc_roof_x", "clad_burnt")), 0.3,
                   axis="y" if abs(math.cos(a)) > 0.5 else "x")
    lib.finish(b, name, out, tri_limit=4500, footprint=footprint, anchor=(0, 0))


if want("h1"):
    house1(False)
if want("h1hit"):
    house1(True)
if want("h2"):
    house2()
if want("h3"):
    house3()
if want("h4"):
    house4()
if want("ruins"):
    ruin("ruin_h1", 10.0, 8.0, 0.8, 11, (2, 2), chimney=(2.2, -0.2), tile="fc_roof_x")
    ruin("ruin_h3", 10.0, 10.0, 0.4, 13, (2, 2), tile="tile_graphite")
