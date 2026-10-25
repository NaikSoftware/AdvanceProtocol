"""Сільські будинки H1-H4, пошкоджений H1 і руїни H1, H3 — у тому самому конвеєрі й тими самими
матеріалами, що решта будівель. Розміри з брифу, слід — ціле число тайлів (меш усередині,
виступ не більше 0.1 тайла). Фронт — +Y, коник уздовж X."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, chunks

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


def win_front(b, y, sgn, xs, z, w=1.2, h=1.4):
    for x in xs:
        b.window(("y", y, sgn), x, z, w, h)
        b.box(x, y + 0.07 * sgn, z - 0.1, w + 0.3, 0.14, 0.1, "step")           # підвіконня


def win_side(b, x, sgn, ys, z, w=1.2, h=1.4):
    for y in ys:
        b.window(("x", x, sgn), y, z, w, h)
        b.box(x + 0.07 * sgn, y, z - 0.1, 0.14, w + 0.3, 0.1, "step")


def gutter(b, x0, x1, y, z):
    b.box((x0 + x1) / 2, y, z, x1 - x0, 0.14, 0.14, "pvc")                       # ринва


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
    b.poly([(xa, ya, EAVE), (xb, ya, EAVE), (xr1, ym, RIDGE), (xr0, ym, RIDGE)], "fc_roof_x")
    b.poly([(xa, yb, EAVE), (xa, ya, EAVE), (xr0, ym, RIDGE)], "fc_roof")
    b.poly([(xb, ya, EAVE), (xb, yb, EAVE), (xr1, ym, RIDGE)], "fc_roof")
    if not hit:
        b.poly([(xb, yb, EAVE), (xa, yb, EAVE), (xr0, ym, RIDGE), (xr1, ym, RIDGE)], "fc_roof_x")
    else:
        def P(u, v):
            e = (xb + (xa - xb) * u, yb, EAVE)
            r = (xr1 + (xr0 - xr1) * u, ym, RIDGE)
            return tuple(e[i] * (1 - v) + r[i] * v for i in range(3))
        b.poly_up([P(0, 0), P(0.28, 0), P(0.3, 0.45), P(0.2, 0.7), P(0.26, 1.0), P(0, 1.0)], "fc_roof_x")
        b.poly_up([P(0.74, 0), P(1, 0), P(1, 1.0), P(0.8, 1.0), P(0.72, 0.6), P(0.78, 0.3)], "fc_roof_x")
        b.poly_up([P(0.28, 0), P(0.74, 0), P(0.7, 0.12), P(0.62, 0.2), P(0.5, 0.1), P(0.4, 0.22), P(0.3, 0.15)], "fc_roof_x")
        b.poly_up([P(0.26, 1.0), P(0.8, 1.0), P(0.72, 0.85), P(0.6, 0.78), P(0.5, 0.88), P(0.4, 0.76), P(0.3, 0.84)], "fc_roof_x")
        for k in range(7):                                                       # оголені крокви в проломі
            u = 0.32 + 0.065 * k
            b.beam(P(u, 0.05), P(u + 0.01, 0.92), 0.12, "boards", 0.2)
        b.poly([(-4.6, y0 + 0.2, EAVE - 0.1), (4.6, y0 + 0.2, EAVE - 0.1), (4.6, y1 - 0.2, EAVE - 0.1), (-4.6, y1 - 0.2, EAVE - 0.1)][::-1], "floor_dark")
    b.box(0, ym, RIDGE, xr1 - xr0 + 0.6, 0.3, 0.16, "metal_dark")                # коник
    b.box(2.2, -0.2, 4.0, 0.75, 0.75, 3.3, "brick_face", top="brick_grey")        # цегляний димар
    # вікна: гладка сітка по фасадах, на торцях і ззаду
    win_front(b, y0, -1, (-3.2, 0.0, 3.2), 1.0)
    win_front(b, y1, 1, (-4.0, 4.0), 1.0)
    win_side(b, -L / 2, -1, (-1.0,), 1.0)
    win_side(b, L / 2, 1, (-1.0, 1.0), 1.0)
    b.box(-3.9, y1 + 0.03, 0.5, 1.0, 0.06, 2.0, "pvc")
    # засклена веранда по довгому боку: підлога, стійки, скління, односхилий дах
    b.box(0, 3.2, 0, 6.0, 1.6, 0.35, "step", top="step")
    for px in (-3.0, -1.0, 1.0, 3.0):
        post(b, px, 3.9, 0.35, 2.2)
    for px in (-2.0, 0.0, 2.0):
        b.window(("y", 3.92, 1), px, 0.6, 1.8, 1.55)
    b.box(0, 3.2, 0, 0.9, 0.6, 0.0001, "step")
    b.poly_up([(-3.4, 2.4, 2.75), (3.4, 2.4, 2.75), (3.4, 4.3, 2.35), (-3.4, 4.3, 2.35)], "fc_roof_x")
    b.box(0, 4.15, 0.0, 1.2, 0.5, 0.25, "step")                                  # сходи
    gutter(b, -L / 2 - OV, L / 2 + OV, y0 - OV, EAVE - 0.3)
    if hit:
        for (x, y, h) in ((1.0, 2.5, 0.8), (3.0, 2.5, 1.1)):
            b.box_e(x, y, h / 2, 1.0, 0.6, h, "char", euler=(0, 0, 0.2))
        chunks(b, 1.5, 3.0, 1.1, 0.8, 14, ("brick_face", "wall_plaster", "rubble"), 41, smin=0.4, smax=1.0)
    lib.finish(b, "house_h1_hit" if hit else "house_h1", out, tri_limit=2200, footprint=(2, 1), anchor=(0, -0.0))


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
    # закритий ґанок із плоским дахом
    b.box(0, y1 + 1.0, 0, 3.2, 2.0, 2.7, "brick_face", top="tile_brown")
    b.box(0, y1 + 2.02, 0, 1.2, 0.04, 2.1, "dark")
    b.box(0, y1 + 2.0, 0, 1.8, 0.9, 0.2, "step")
    b.window(("x", 1.6, 1), y1 + 1.0, 1.0, 0.9, 1.0)
    b.window(("x", -1.6, -1), y1 + 1.0, 1.0, 0.9, 1.0)
    b.box(L / 2 + 0.3, 0.0, 5.0, 0.15, 0.7, 0.7, "pvc")                         # супутникова тарілка
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
    # фотоелектрична батарея 5 x 3.4 м на фронтальному скаті
    run = y1 + OV
    sl = math.hypot(run, RIDGE - EAVE)
    ny, nz = (RIDGE - EAVE) / sl, run / sl
    def pv(x, s):
        return (x, run - s * run / sl + 0.04 * ny, EAVE + s * (RIDGE - EAVE) / sl + 0.04 * nz)
    b.poly_up([pv(-2.5, 1.4), pv(2.5, 1.4), pv(2.5, 4.8), pv(-2.5, 4.8)], "pv")
    for fl, z in ((0, 1.5), (1, 4.2)):
        win_front(b, y1, 1, (-3.5, 0.0, 3.5) if fl else (-3.5, 3.5), z, 1.3, 1.5)
        win_front(b, y0, -1, (-3.5, 0.0, 3.5), z, 1.3, 1.5)
        win_side(b, -L / 2, -1, (-2.0, 2.0), z, 1.3, 1.5)
        win_side(b, L / 2, 1, (-2.0, 2.0), z, 1.3, 1.5)
    b.box(0, y1 + 0.03, 1.0, 1.2, 0.06, 2.2, "dark")                              # двері
    for px in (-1.4, 1.4):
        post(b, px, y1 + 1.5, 1.0, 2.4)                                           # навіс із двома стійками
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
    b.cyl(2.8, -0.8, 4.0, 0.16, 2.2, 8, "metal_dark")                            # димар-труба
    lib.finish(b, "house_h4", out, tri_limit=1800, footprint=(2, 1))


# ----------------------------------------------------------------------- руїни
def ruin(name, L, D, keep, seed, footprint, chimney=None, tile="tile_graphite"):
    lib.reset()
    b = Builder()
    rnd = random.Random(seed)
    x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
    levels = (0.35, 0.9, 1.5, 2.2, 2.7)
    segs = []
    for sx in range(int(L)):
        x = x0 + 0.5 + sx
        segs.append((x, y0, 1.0, 0.4))
        segs.append((x, y1, 1.0, 0.4))
    for sy in range(int(D)):
        y = y0 + 0.5 + sy
        segs.append((x0, y, 0.4, 1.0))
        segs.append((x1, y, 0.4, 1.0))
    h_prev = 1.5
    for (x, y, sx, sy) in segs:
        if rnd.random() > keep:
            continue
        h = rnd.choice(levels)
        if rnd.random() < 0.6:
            h = (h + h_prev) / 2          # східчасті верхи: сусідні відрізки близькі за висотою
        h_prev = h
        b.box_e(x, y, h / 2, sx, sy, h, "wall_plaster", euler=(0, 0, 0), top="brick_face")
        b.box(x, y, 0, sx + 0.02, sy + 0.02, min(h, 0.5), "brick_grey")
    if chimney:
        cx, cy = chimney
        b.box(cx, cy, 0, 0.8, 0.8, 3.0, "brick_face")
        b.box_e(cx, cy, 3.3, 0.8, 0.8, 0.7, "brick_face", euler=(0.1, -0.12, 0.3), top="char")
        b.box_e(cx, cy, 4.0, 0.7, 0.7, 0.6, "brick_face", euler=(-0.2, 0.15, 0.1))
    # купи кутастого завалу всередині контуру (0.5-1.5 м), щільніші в центрі
    hw, hd = (L / 2 - 0.5), (D / 2 - 0.5)
    for k in range(3 if L * D > 90 else 2):
        px, py = rnd.uniform(-hw * 0.5, hw * 0.5), rnd.uniform(-hd * 0.4, hd * 0.4)
        chunks(b, px, py, min(hw, hd) * 0.6, 1.8, 26, ("brick_face", "wall_plaster", "rubble", "brick_grey"), seed * 7 + k, smin=0.5, smax=1.4)
    for k in range(14):                                                           # дрібніше сміття по контуру
        b.box_e(rnd.uniform(x0 - 0.3, x1 + 0.3), rnd.choice((y0 - 0.2, y1 + 0.2)) if rnd.random() < 0.5 else rnd.uniform(y0, y1), 0.2, rnd.uniform(0.4, 0.8), rnd.uniform(0.4, 0.8), rnd.uniform(0.3, 0.5),
                rnd.choice(("brick_face", "rubble")), euler=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(0, 3.1)))
    # зігнуті листи покрівлі на купах і обвуглені крокви
    for k in range(10):
        b.box_e(rnd.uniform(x0 + 1.5, x1 - 1.5), rnd.uniform(y0 + 1.8, y1 - 1.8), rnd.uniform(0.5, 1.6), 1.1, rnd.uniform(1.6, 2.4), 0.05,
                rnd.choice((tile, "fc_roof_x", "clad_burnt")), euler=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.5, 0.5), rnd.uniform(0, 3.1)))
    for k in range(9):
        cx, cy = rnd.uniform(x0 + 2, x1 - 2), rnd.uniform(y0 + 2.2, y1 - 2.2)
        a = rnd.uniform(0, 3.1)
        b.beam((cx, cy, rnd.uniform(0.4, 1.2)), (cx + 2.0 * math.cos(a), cy + 2.0 * math.sin(a), rnd.uniform(0.6, 1.8)), 0.14, "char", 0.2)
    lib.finish(b, name, out, tri_limit=3500, footprint=footprint)


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
    ruin("ruin_h1", 10.0, 8.0, 0.7, 11, (2, 1), chimney=(2.2, -0.2), tile="fc_roof_x")
    ruin("ruin_h3", 10.0, 10.0, 0.3, 13, (2, 2), tile="tile_graphite")
