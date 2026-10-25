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
from lib import Builder, chunks, mound, wall_run, bent_sheet, burn_ring
from mathutils import Vector

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
    """Вибите вікно: чорний проріз розміру цілого вікна і кіптява навколо нього (нижче карниза)."""
    e = 0.03 * sgn
    if axis == "y":
        quad = [(x - w / 2, y + e, z), (x + w / 2, y + e, z), (x + w / 2, y + e, z + h), (x - w / 2, y + e, z + h)]
    else:
        quad = [(x + e, y - w / 2, z), (x + e, y + w / 2, z), (x + e, y + w / 2, z + h), (x + e, y - w / 2, z + h)]
    b.poly(quad[::-1] if sgn < 0 else quad, "dark")
    burn_ring(b, axis, y if axis == "y" else x, x if axis == "y" else y, z, w, h, sgn, g_side=0.2, g_bot=0.1, g_top=0.45)


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
        rr = random.Random(77)

        def P(u, v):                                   # похилий скат -Y, що його бачить камера
            e = (xa + (xb - xa) * u, ya, EAVE)
            r = (xr0 + (xr1 - xr0) * u, ym, RIDGE)
            return tuple(e[i] * (1 - v) + r[i] * v for i in range(3))
        vs = [i / 12 for i in range(13)]
        uL = [0.30 + 0.05 * math.sin(v * 7) + rr.uniform(-0.04, 0.04) for v in vs]
        uR = [0.70 + 0.05 * math.sin(v * 9) + rr.uniform(-0.04, 0.04) for v in vs]
        # дві частини ската: розрив іде від коника крізь край карниза, тож контур даху ламається
        left = [(0, 0)] + [(uL[i], vs[i]) for i in range(13)] + [(0, 1)]
        right = [(uR[i], vs[i]) for i in range(13)] + [(1, 1), (1, 0)]
        b.poly_up([P(u, v) for (u, v) in left], "fc_roof_burnt")
        b.poly_up([P(u, v) for (u, v) in right], "fc_roof_burnt")
        # смуга кіптяви ~1.5 м навколо розриву: від майже чорного біля краю до тла даху
        for edge, sgn_ in ((uL, -1), (uR, 1)):
            for i in range(12):
                u0, u1 = edge[i], edge[i + 1]
                v0, v1 = vs[i], vs[i + 1]
                du = 0.17 * sgn_
                pts = [P(u0, v0), P(u1, v1), P(u1 + du, v1), P(u0 + du, v0)]
                pts = [(x, y - 0.025, z + 0.03) for (x, y, z) in pts]
                n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
                tones = (0.02, 0.02, 0.2, 0.2)
                if n_.z < 0:
                    pts, tones = pts[::-1], tones[::-1]
                b.soot(pts, tones, 1)
        # +Y скат з надірваним гребенем
        b.poly_up([(xb, yb, EAVE), (xa, yb, EAVE), (xr0, ym, RIDGE), (-1.2, ym + 0.2, RIDGE - 0.4), (0.0, ym + 0.8, RIDGE - 1.2), (1.4, ym + 0.3, RIDGE - 0.6), (xr1, ym, RIDGE)], "fc_roof_x")
        for k in range(7):                              # мокрі темні крокви, що лишились, з обламаними кінцями
            u = 0.34 + 0.05 * k
            if u > 0.69:
                break
            b.beam(P(u, 0.06 + 0.1 * rr.random()), P(u + 0.01, 0.9 - 0.25 * rr.random()), 0.14, "timber_dark", 0.2)
        b.beam(P(0.32, 0.55), P(0.68, 0.6), 0.14, "timber_dark", 0.2)
        # порожнина: один неосвітлений майже чорний чотирикутник над верхами стін (ними плашка штукатурки світилась)
        b.poly([(-4.7, y0 + 0.1, EAVE + 0.12), (4.7, y0 + 0.1, EAVE + 0.12), (4.7, y1 - 0.1, EAVE + 0.12), (-4.7, y1 - 0.1, EAVE + 0.12)][::-1], "cavity")
        for k in range(9):                                                        # балки перекриття горища: тьмяно видно крізь розрив
            b.box(-4.0 + 1.0 * k, (y0 + y1) / 2, EAVE + 0.12, 0.14, y1 - y0 - 0.4, 0.16, "timber_dark")
        for (sx_, sw_, sh_) in ((-1.4, 0.9, 0.35), (-0.3, 0.7, 0.6), (0.8, 1.0, 0.25)):    # східчастий зламаний верх стіни
            b.box(xa + (xb - xa) * 0.51 + sx_, y0 + 0.2, EAVE, sw_, 0.4, sh_, "wall_plaster", top="brick_face")
        # стіна під розривом карниза: темна зверху, світлішає донизу (кіптява над місцем виходу диму)
        xl, xr = xa + (xb - xa) * 0.30, xa + (xb - xa) * 0.72
        b.soot([(xl + 0.6, y0 - 0.03, EAVE - 1.5), (xr - 0.6, y0 - 0.03, EAVE - 1.5), (xr, y0 - 0.03, EAVE), (xl, y0 - 0.03, EAVE)][::-1], (0.30, 0.30, 0.10, 0.10), 1)
    if not hit:
        b.box(0, ym, RIDGE, xr1 - xr0 + 0.6, 0.3, 0.16, "gutter")
    else:
        b.box(-3.2 + 0.2, ym, RIDGE, 1.6, 0.3, 0.16, "gutter")
        b.box(3.2 - 0.2, ym, RIDGE, 1.6, 0.3, 0.16, "gutter")
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
    if hit:
        gutter(b, xa + (xb - xa) * 0.72, L / 2 + OV, y0 - OV, EAVE - 0.3)
    else:
        gutter(b, -L / 2 - OV, L / 2 + OV, y0 - OV, EAVE - 0.3)
    if hit:
        rr = random.Random(54)
        mound(b, 0.0, -4.05, 2.8, 0.28, 1.0, 51, rings=4, segs=16, tongues=0)
        for k in range(5):                                       # скановані уламки 0.3-0.6 м під стіною -Y
            b.rock(rr.uniform(-3.0, 3.0), -4.0 + rr.uniform(-0.15, 0.1), 0.25, rr.uniform(0.35, 0.6), rr.choice(("rubble", "heap")), rr)
        mound(b, 6.0, -0.4, 1.5, 2.0, 0.55, 52, rings=5, segs=18, tongues=1)  # розбитий завал на торці +X, не вище 0.6 м
        for k in range(5):
            b.rock(6.2 + rr.uniform(-1.6, 1.6), -0.4 + rr.uniform(-2.2, 2.2), 0.25 + rr.uniform(0, 0.3), rr.uniform(0.3, 0.6), "rubble", rr)
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
    b.box(0, 0, RIDGE, L + 0.8, 0.3, 0.18, "gutter")
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
    b.box(0, 0, RIDGE, L + 1.0, 0.3, 0.18, "gutter")
    # фотоелектрична батарея 5 x 3.4 м на скаті, який бачить камера (-Y)
    run = -(y0 - OV)
    sl = math.hypot(run, RIDGE - EAVE)
    ny, nz = (RIDGE - EAVE) / sl, run / sl

    def pv(x, s):
        return (x, -(run - s * run / sl + 0.05 * ny), EAVE + s * (RIDGE - EAVE) / sl + 0.05 * nz)
    b.poly_up([pv(-2.5, 1.2), pv(2.5, 1.2), pv(2.5, 4.6), pv(-2.5, 4.6)], "pv")
    for (xa_, sa, xb_, sb) in ((-2.6, 1.15, 2.6, 1.25), (-2.6, 4.55, 2.6, 4.65), (-2.6, 1.15, -2.5, 4.65), (2.5, 1.15, 2.6, 4.65)):
        q0, q1 = pv(xa_, sa), pv(xb_, sb)
        b.beam((q0[0], q0[1], q0[2] + 0.03), (q1[0], q1[1], q1[2] + 0.03), 0.09, "pv_frame", 0.09)
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
    b.box(0, 0, RIDGE, L + 0.8, 0.28, 0.16, "gutter")
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
def ruin(name, L, D, keep, seed, footprint, chimney=None, tile="tile_graphite", corner=False, cap=1.5):
    """Руїна: низька грудкувата купа зі сканованих уламків (Poly Haven, CC0), уламки стін 2-3 шматки на бік із проломами
    ≥1.2 м, висоти 0.3-cap м (один кут до поверху за потреби), нахилені крокви, листи покрівлі на купі."""
    lib.reset()
    b = Builder()
    rnd = random.Random(seed)
    x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
    sides = (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0)))
    for si, (p0, p1) in enumerate(sides):
        ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        n = int(ln)
        hs = [rnd.uniform(0.4, cap)]
        for i in range(n):
            hs.append(min(cap, max(0.3, hs[-1] + rnd.uniform(-0.7, 0.7))))
        # 2-3 шматки: два проломи довжиною не менше 2 відрізків (≥1.2 м після масштабування)
        pieces = rnd.choice((2, 3))
        cutpts = sorted(rnd.sample(range(2, n - 1), pieces - 1)) if n > 5 else [n // 2]
        for cp in cutpts:
            for j in range(cp, min(n + 1, cp + 2)):
                hs[j] = 0.0
        if rnd.random() > keep:                                     # іноді з боку лишається лише уламок
            for j in range(0, n + 1):
                if rnd.random() < 0.6:
                    hs[j] = 0.0
        if corner and si in (1, 2):                                  # один кут на поверх висоти: видно колишній дім здалеку
            if si == 1:
                hs[-3:] = [2.8, 3.1, 3.2]
            else:
                hs[:3] = [3.2, 3.0, 2.6]
        wall_run(b, p0, p1, 0.4, hs, "wall_ruin", "brick_face", seed * 3 + si)
    mound(b, 0.0, 0.0, L / 2 + 0.2, D / 2 + 0.2, 2.6, seed + 1, mat="heap", rings=9, segs=36, tongues=3)
    mound(b, rnd.uniform(-1.5, 1.5), rnd.uniform(-1.2, 1.2), L / 3, D / 3, 1.8, seed + 2, rings=5, segs=18, tongues=2)
    for k in range(4):                                                            # лопаті довкола основної купи
        ang = rnd.uniform(0, 2 * math.pi)
        rr_ = rnd.uniform(2.0, 3.4)
        mound(b, rr_ * math.cos(ang) * 1.15, rr_ * math.sin(ang) * 0.95, rnd.uniform(1.6, 2.4), rnd.uniform(1.4, 2.2), rnd.uniform(0.7, 1.3), seed + 10 + k, rings=4, segs=14, tongues=1)

    def heap_h(x, y):
        r = math.hypot(x / (L / 2 + 0.2), y / (D / 2 + 0.2))
        return 2.6 * max(0.0, 1 - r ** 1.7) * 0.75

    # скановані уламки 0.3-1 м, наполовину вкопані, по гребенях і краях
    for k in range(11):
        a = rnd.uniform(0, 2 * math.pi)
        t = rnd.choice((0.2, 0.35, 0.5, 0.65, 0.8, 0.95))
        px, py = (L / 2) * t * math.cos(a), (D / 2) * t * math.sin(a)
        b.rock(px, py, heap_h(px, py) + 0.2, rnd.uniform(0.4, 1.0), rnd.choice(("rubble", "heap", "rubble_steel")), rnd)
    for k in range(8):                                                            # відсип тоншає до країв
        a = rnd.uniform(0, 2 * math.pi)
        t = rnd.uniform(0.95, 1.2)
        b.rock((L / 2 + 1.5) * t * math.cos(a), (D / 2 + 1.5) * t * math.sin(a), 0.1, rnd.uniform(0.28, 0.5), rnd.choice(("rubble", "heap")), rnd)
    for k in range(4):                                                            # відколи цегли біля кінців уламків стін
        a = rnd.uniform(0, 2 * math.pi)
        b.rock((L / 2 - 0.2) * math.cos(a), (D / 2 - 0.2) * math.sin(a), 0.2, rnd.uniform(0.25, 0.45), "brick_face", rnd)
    if chimney:                                                                   # димар: цегла, зламаний верх
        cx, cy = chimney
        zh = heap_h(cx, cy)
        b.box_e(cx, cy, zh + 1.1, 0.8, 0.8, 2.2, "brick_face", euler=(0.05, -0.04, 0.2), top="brick_face")
        b.box_e(cx + 0.05, cy, zh + 2.3, 0.8, 0.8, 0.45, "brick_face", euler=(0.25, -0.2, 0.5), top="char")
    # 3-4 крокви ≤35°, ≥0.2 м завтовшки, обидва кінці вгризаються в купу
    for k in range(4):
        a = rnd.uniform(0, 2 * math.pi)
        r0 = rnd.uniform(0.5, 1.4)
        x0_, y0_ = r0 * math.cos(a) * 1.3, r0 * math.sin(a) * 1.0
        a2 = a + rnd.uniform(-0.5, 0.5)
        r1 = r0 + rnd.uniform(2.6, 3.4)
        x1_, y1_ = r1 * math.cos(a2) * 1.3, r1 * math.sin(a2) * 1.0
        sep = math.hypot(x1_ - x0_, y1_ - y0_)
        z1_ = max(0.2, heap_h(x1_, y1_) + 0.05)
        z0_ = heap_h(x0_, y0_) + 0.05
        z0_ = min(z0_, z1_ + sep * 0.55)                             # ≤ ~29° від горизонталі
        th = rnd.uniform(0.2, 0.32)
        b.beam((x0_, y0_, z0_), (x1_, y1_, z1_), th, rnd.choice(("timber_dark", "timber_dark", "char")), th * 1.2)
        b.box_e(x1_, y1_, z1_ + 0.05, 0.34, 0.34, 0.3, "char", euler=(rnd.uniform(0, 1), rnd.uniform(0, 1), 0))
    for k in range(7):                                                            # листи покрівлі лежать на купі, плоскі й зігнуті
        a = rnd.uniform(0, 2 * math.pi)
        t = rnd.uniform(0.3, 0.8)
        px, py = (L / 2) * t * math.cos(a), (D / 2) * t * math.sin(a)
        zz = heap_h(px, py) + 0.2
        ln = rnd.uniform(1.4, 2.0)
        bent_sheet(b, (px, py, zz), (px + ln * math.cos(a + 1), py + ln * math.sin(a + 1), max(0.3, zz - rnd.uniform(0.0, 0.3))), 1.1, rnd.choice((tile, "fc_roof_x", "tin_red", "tin_red")), 0.1,
                   axis="y" if abs(math.cos(a + 1)) > 0.5 else "x")
    lib.finish(b, name, out, tri_limit=5000, footprint=footprint, anchor=(0, 0))


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
    ruin("ruin_h1", 10.0, 8.0, 0.8, 11, (2, 2), chimney=(2.2, -0.2), tile="fc_roof_x", cap=1.5)
    ruin("ruin_h3", 10.0, 10.0, 0.6, 29, (2, 2), tile="tile_graphite", corner=True, cap=1.6)
