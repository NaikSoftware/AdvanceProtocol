"""Малі будинки на одну клітинку (8 x 8 м) і їхні напівзруйновані двійники: одна функція будує обидва, прапорець ruined лишає
те саме габаритне тіло. Напівзруйновані: стоять майже всі стіни, один кут або секція обвалені, дах частково згорів, у стінах
вибиті вікна й діри від снарядів, дверей немає; завал лише біля обвалу й не виходить за клітинку. Матеріали ті самі, що в цілих
будинків (світла штукатурка, червона цегла в димарі й на зламах, сірі дахи), кіптява й руйнування зверху.
Камера гри бачить боки -Y і +X, тому руйнування скрізь на них. Запуск: build_ruins.py -- <out> [house1 house2 shed]"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, wall_run, burn_ring, opening2, chip_slab, prism, bent_sheet, HeapSurface, heap_mound
from mathutils import Vector

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


def heaps(b, plan, seed, dens=7.0):
    """Купи: низький меш у b, високе скан-джерело для запікання (темна основа, уламки цегли й штукатурки 20-50 см зверху)."""
    bh = Builder()
    hr = random.Random(seed)
    for k, h in enumerate(plan):
        big = h.rx * h.ry > 8
        heap_mound(b, h, "heap_buff", rings=7 if big else 3, segs=32 if big else 16, skirt=0.5)
        heap_mound(bh, h, "heap_base_buff", rings=16 if big else 6, segs=96 if big else 40, jitter=0.04, seed=seed + k, skirt=0.5)
        for _ in range(int(math.pi * h.rx * h.ry * dens)):
            a = hr.uniform(0, 2 * math.pi)
            t = math.sqrt(hr.uniform(0, 1.0)) * 1.12
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py) if t < 1.0 else h.lip * max(0.0, 1.0 - (t - 1.0) / 0.12) * 0.8
            q = hr.random()
            size = hr.uniform(0.2, 0.42) if q < 0.7 else (hr.uniform(0.42, 0.6) if q < 0.95 else hr.uniform(0.6, 0.85))
            bh.rock(px, py, z + 0.04, size, "rubble_buff", hr, buried=0.3)
    return bh


def surface(plan):
    return lambda x, y: max(h.z(x, y) for h in plan)


def lumps(b, plan, rnd, n_each=8):
    """Край купи розбитий на грудки цегли й штукатурки 0.3-0.5 м: низькі грані, що стирчать зі схилу й кидають тінь."""
    for h in plan:
        for _ in range(n_each):
            a = rnd.uniform(0, 2 * math.pi)
            t = rnd.uniform(0.55, 1.0)
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py)
            sz = rnd.uniform(0.3, 0.5)
            b.box_e(px, py, z + sz * 0.22, sz * rnd.uniform(0.8, 1.4), sz * rnd.uniform(0.6, 1.0), sz * rnd.uniform(0.4, 0.7),
                    rnd.choice(("brick_face", "wall_plaster", "brick_face", "brick_dark")),
                    euler=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(0, 3.14)))


def soot_cut(b, P, cut, sgn, depth=0.25, nv=10):
    """Вузька смуга кіптяви вздовж рваного краю даху: темна біля краю, швидко згасає."""
    for i in range(nv):
        v0, v1 = i / nv, (i + 1) / nv
        pts = [P(cut(v0), v0), P(cut(v1), v1), P(cut(v1) + depth * sgn, v1), P(cut(v0) + depth * sgn, v0)]
        pts = [(x, y, z + 0.03) for (x, y, z) in pts]
        n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        tones = (0.10, 0.10, 0.5, 0.5)
        if n_.z < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)


def roof_part(b, P, x_end, cut, mat, nv=12):
    """Скат, що лишився між кінцем будинку x_end і рваним краєм cut(v) (v: 0 — карниз, 1 — коник)."""
    pts = [P(x_end, 0.0)] + [P(cut(i / nv), i / nv) for i in range(nv + 1)] + [P(x_end, 1.0)]
    b.poly_up(pts, mat)


def gable_roof(b, pf, pb, xw, xb, mat):
    b.poly_up([pf(xw, 0.0), pf(xb, 0.0), pf(xb, 1.0), pf(xw, 1.0)], mat)
    b.poly_up([pb(xw, 0.0), pb(xb, 0.0), pb(xb, 1.0), pb(xw, 1.0)], mat)


def house1(ruined):
    """Одноповерховий дім 6.6 x 4.8 м. Напівзруйнований: східна половина даху ціла, західна провалилась, обвалена частина
    фронтальної й західної стін, завал усередині й невеликий зсув перед обваленою стіною."""
    lib.reset()
    b = Builder()
    rnd = random.Random(14)
    hx, hy, OV = 3.3, 2.4, 0.35
    E, R = 2.5, 4.2
    ya, yb, ym, xb, xw = -(hy + OV), hy + OV, 0.0, hx + OV, -(hx + OV)
    S, N = -hy, hy

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.4, 2 * hy + 0.4, 0.5, "brick_grey")
        b.box(0, 0, 0.5, 2 * hx + 0.38, 2 * hy + 0.38, E - 0.5, "wall_plaster")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (sx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="brick_face")
        gable_roof(b, PF, PB, xw, xb, "fc_roof_xh")
        for x in (-2.3, -0.8, 1.5, 2.65):
            b.window(("y", S - 0.2, -1), x, 0.9, 1.0, 1.2)
        b.box(0.1, S - 0.2 + 0.03, 0.0, 1.0, 0.06, 2.0, "dark")
        b.box(0.1, S - 0.5, 0.0, 1.8, 0.7, 0.2, "step")
        for y in (-1.0, 1.0):
            b.window(("x", hx + 0.2, 1), y, 0.9, 1.1, 1.2)
            b.window(("x", -hx - 0.2, -1), y, 0.9, 1.1, 1.2)
        for x in (-2.3, -0.6, 1.2, 2.6):
            b.window(("y", N + 0.2, 1), x, 0.9, 1.0, 1.2)
        b.box(1.6, -0.2, 3.5, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
        lib.finish(b, "house_h5", out, tri_limit=1200, footprint=(1, 1))
        return
    kw = dict(top_tone=0.82, brick_mat="brick_face")
    wall_run(b, (-0.9, S), (hx, S), 0.4, [E] * 6, "wall_half", "brick_face", 21, hcap=2.6, jag=0.12, cap=0.06, **kw)
    wall_run(b, (-hx, S), (-0.9, S), 0.4, [0.6, 1.3, 0.9, 1.8], "wall_half", "brick_face", 22, hcap=2.2, **kw)
    wall_run(b, (hx, S), (hx, N), 0.4, [E] * 6, "wall_half", "brick_face", 23, hcap=2.6, jag=0.12, cap=0.06, **kw)
    wall_run(b, (hx, N), (-1.6, N), 0.4, [E] * 6, "wall_half", "brick_face", 24, hcap=2.6, jag=0.12, cap=0.06, **kw)
    wall_run(b, (-1.6, N), (-hx, N), 0.4, [1.7, 1.1, 2.0, 0.8], "wall_half", "brick_face", 25, hcap=2.2, **kw)
    wall_run(b, (-hx, N), (-hx, S), 0.4, [2.2, 1.3, 0.7, 1.0, 0.6], "wall_half", "brick_face", 26, hcap=2.2, **kw)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (hx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="brick_face")
    for x in (1.5, 2.65):
        burn_ring(b, "y", S - 0.2, x, 0.9, 1.0, 1.2, -1, g_side=0.35, g_bot=0.1, g_top=0.8, t_in=0.22, t_out=0.62)
        opening2(b, "y", S - 0.2, x, 0.9, 1.0, 1.2, -1)
    burn_ring(b, "y", S - 0.2, 0.1, 0.05, 1.0, 2.0, -1, g_side=0.35, g_bot=0.0, g_top=0.8, t_in=0.22, t_out=0.62)
    opening2(b, "y", S - 0.2, 0.1, 0.05, 1.0, 2.0, -1)
    for y, w, h, z in ((-1.0, 1.1, 1.2, 0.9), (1.0, 1.4, 1.3, 0.8)):
        burn_ring(b, "x", hx + 0.2, y, z, w, h, 1, g_side=0.35, g_bot=0.15, g_top=0.9, t_in=0.22, t_out=0.62)
        opening2(b, "x", hx + 0.2, y, z, w, h, 1)
    for x in (0.6, 2.0):
        burn_ring(b, "y", N + 0.2, x, 0.9, 1.0, 1.2, 1, g_side=0.35, g_bot=0.1, g_top=0.8, t_in=0.22, t_out=0.62)
        opening2(b, "y", N + 0.2, x, 0.9, 1.0, 1.2, 1)
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return -0.1 + 0.7 * math.sin(3.1 * v + ph[0]) + 0.25 * math.sin(9 * v + ph[1])

    def cutB(v):
        return -0.7 + 0.6 * math.sin(2.7 * v + ph[2]) + 0.25 * math.sin(8 * v + ph[0])
    roof_part(b, PF, xb, cutF, "fc_roof_xh")
    roof_part(b, PB, xb, cutB, "fc_roof_xh")
    soot_cut(b, PF, cutF, 1)
    soot_cut(b, PB, cutB, 1)
    plan = [HeapSurface(-1.9, 0.1, 1.25, 1.4, 0.85, 71, bumps=6, lip=0.28, wob=0.15, lump=0.07, hummocks=3, hum_amp=0.25),
            HeapSurface(-2.1, -2.95, 1.2, 0.5, 0.7, 72, bumps=5, lip=0.25, wob=0.1, lump=0.05, hummocks=1, hum_amp=0.2)]
    sf = surface(plan)
    # крокви лежать на верху стіни (консоль) або на завалі; тих, що висіли б у повітрі, немає
    for x in (-0.8, -0.2):
        for sgn, plate, P, cut in ((1, S + 0.05, PF, cutF), (-1, N - 0.05, PB, cutB)):
            v1 = rnd.uniform(0.3, 0.6)
            if x > min(cut(i / 8 * v1) for i in range(9)) - 0.1 or (sgn == 1 and x < -0.9) or (sgn == -1 and x < -1.6):
                continue
            c = P(x, v1)
            b.beam((x, plate, E + 0.05), (c[0], c[1], c[2] - 0.1), 0.12, "timber_dark", 0.18)
    for x in (-2.9, -2.2, -1.5):
        for y0, y1 in ((S + 0.5, S + 1.7), (N - 0.5, N - 1.7)):
            b.beam((x, y0, sf(x, y0) + 0.1), (x, y1, sf(x, y1) + 0.3), 0.12, "timber_dark", 0.18)
    b.beam((-3.0, 0.1, sf(-3.0, 0.1) + 0.12), (-1.0, 0.0, sf(-1.0, 0.0) + 0.3), 0.16, "timber_dark", 0.22)
    bent_sheet(b, (-2.7, -0.9, sf(-2.7, -0.9) + 0.2), (-2.3, 0.8, sf(-2.3, 0.8) + 0.2), 0.9, "sheet_char", 0.18, axis="x")
    bent_sheet(b, (-1.6, -1.2, sf(-1.6, -1.2) + 0.2), (-1.4, 0.5, sf(-1.4, 0.5) + 0.2), 0.9, "sheet_char", 0.18, axis="x")
    bent_sheet(b, (-1.5, -3.0, sf(-1.5, -3.0) + 0.1), (-2.9, -2.9, sf(-2.9, -2.9) + 0.1), 0.9, "sheet_char", 0.12, axis="y")
    b.box(1.6, -0.2, 3.5, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
    lumps(b, plan, rnd, 6)
    bh = heaps(b, plan, 7)
    lib.finish(b, "ruin_half_house1", out, tri_limit=4600, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def house2(ruined):
    """Двоповерховий дім 6 x 5.6 м. Напівзруйнований: західна половина даху ціла, східний фронтон обвалений, перекриття нахилене в завал."""
    lib.reset()
    b = Builder()
    rnd = random.Random(33)
    hx, hy, OV = 3.0, 2.8, 0.3
    E, R, FL = 5.4, 7.3, 2.7
    ya, yb, ym, xb, xw = -(hy + OV), hy + OV, 0.0, hx + OV, -(hx + OV)
    S, N = -hy, hy

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.4, 2 * hy + 0.4, 0.6, "brick_grey")
        b.box(0, 0, 0.6, 2 * hx + 0.38, 2 * hy + 0.38, E - 0.6, "wall_plaster")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (sx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="brick_face")
        gable_roof(b, PF, PB, xw, xb, "tile_graphite")
        for z in (0.9, 3.6):
            for x in (-1.8, 0.0, 1.8):
                b.window(("y", S - 0.2, -1), x, z, 1.2, 1.4)
            for x in (-1.2, 1.2):
                b.window(("y", N + 0.2, 1), x, z, 1.2, 1.4)
            for y in (-1.0, 1.0):
                b.window(("x", hx + 0.2, 1), y, z, 1.1, 1.4)
        b.box(2.2, S - 0.2 + 0.03, 0.0, 1.0, 0.06, 2.0, "dark")
        b.box(2.2, S - 0.5, 0.0, 1.8, 0.7, 0.2, "step")
        b.box(-1.8, 0.0, 6.2, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
        lib.finish(b, "house_h6", out, tri_limit=1600, footprint=(1, 1))
        return
    kw = dict(top_tone=0.82, brick_mat="brick_face")
    for p0, p1, seed in (((-hx, S), (hx, S), 31), ((hx, N), (-hx, N), 32), ((-hx, N), (-hx, S), 33)):
        wall_run(b, p0, p1, 0.4, [E] * 8, "wall_half", "brick_face", seed, hcap=5.6, jag=0.1, cap=0.06, **kw)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (-hx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="brick_face")
    wall_run(b, (hx, S), (hx, N), 0.4, [1.2, 2.2, 4.2, 5.0, 3.6, 1.8, 1.1, 0.9, 1.5, 2.5, 1.3], "wall_half", "brick_face", 34, hcap=5.2, jag=0.7, **kw)
    for fl, z in ((0, 0.9), (1, 3.6)):
        for x in (-1.8, 0.0, 1.8):
            blown = (fl == 1 and x != 0.0) or (fl == 0 and x == 1.8)
            if blown:
                burn_ring(b, "y", S - 0.2, x, z, 1.2, 1.4, -1, g_side=0.35, g_bot=0.15, g_top=1.0, t_in=0.22, t_out=0.62)
                opening2(b, "y", S - 0.2, x, z, 1.2, 1.4, -1)
            else:
                b.window(("y", S - 0.2, -1), x, z, 1.2, 1.4)
        for x in (-1.2, 1.2):
            b.window(("y", N + 0.2, 1), x, z, 1.2, 1.4)
    burn_ring(b, "y", S - 0.2, 2.2, 0.05, 1.0, 2.0, -1, g_side=0.35, g_bot=0.0, g_top=1.0, t_in=0.22, t_out=0.62)
    opening2(b, "y", S - 0.2, 2.2, 0.05, 1.0, 2.0, -1)
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return 0.4 + 0.6 * math.sin(3 * v + ph[0]) + 0.25 * math.sin(9 * v + ph[1])

    def cutB(v):
        return 1.0 + 0.6 * math.sin(2.6 * v + ph[2]) + 0.25 * math.sin(8 * v + ph[0])
    roof_part(b, PF, xw, cutF, "tile_graphite")
    roof_part(b, PB, xw, cutB, "tile_graphite")
    soot_cut(b, PF, cutF, -1)
    soot_cut(b, PB, cutB, -1)
    for x in (1.3, 2.0, 2.7):
        for plate, P in ((S + 0.05, PF), (N - 0.05, PB)):
            if rnd.random() < 0.2:
                continue
            v1 = rnd.uniform(0.25, 0.6)
            c = P(x, v1)
            b.beam((x, plate, E + 0.05), (c[0], c[1], c[2] - 0.12), 0.14, "timber_dark", 0.22)
    plan = [HeapSurface(3.4, 0.0, 0.85, 2.1, 1.3, 81, bumps=6, lip=0.28, wob=0.15, lump=0.08, hummocks=3, hum_amp=0.3, pw=1.5),
            HeapSurface(1.5, 0.3, 1.3, 1.9, 0.8, 82, bumps=5, lip=0.26, wob=0.1, lump=0.05, hummocks=2, hum_amp=0.2)]
    plan[0].fit_peak(1.45)
    sf = surface(plan)
    chip_slab(b, 1.7, 0.0, FL - 0.1, 3.4, 5.2, 0.24, (0.0, 0.42, 0.02), "floor_char", "floor_char", 41, rebar=3)
    bent_sheet(b, (1.6, -2.7, 5.4), (1.8, -1.2, FL + 0.3), 0.9, "sheet_char", 0.2, axis="x")
    bent_sheet(b, (3.2, 1.6, sf(3.2, 1.6) + 0.2), (3.9, 2.4, sf(3.9, 2.4) + 0.12), 0.9, "sheet_char", 0.12, axis="y")
    b.box(-1.8, 0.0, 6.2, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
    lumps(b, plan, rnd, 6)
    bh = heaps(b, plan, 9)
    lib.finish(b, "ruin_half_house2", out, tri_limit=4800, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def shed(ruined):
    """Господарський сарай 6.8 x 4.2 м. Напівзруйнований: фронтальна (на камеру) стіна впала, дах з цього боку провис уздовж того самого коника."""
    lib.reset()
    b = Builder()
    rnd = random.Random(57)
    hx, hy, OV = 3.4, 2.1, 0.3
    E, R = 2.8, 3.8
    ya, yb, ym = -(hy + OV), hy + OV, 0.0
    S, N, XW, XE = -hy, hy, -hx, hx
    xs = [XW - 0.3 + 0.5 * i for i in range(15)]
    for i in range(len(xs) - 1):
        b.poly_up([(xs[i], yb, E), (xs[i + 1], yb, E), (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_x")
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.3, 2 * hy + 0.3, 0.5, "brick_grey")
        b.box(0, 0, 0.5, 2 * hx + 0.28, 2 * hy + 0.28, E - 0.5, "boards")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.3, (sx, 0.0, 0.0), math.pi / 2, 0.0, "boards", top_mat="boards")
        for i in range(len(xs) - 1):
            b.poly_up([(xs[i], ya, E), (xs[i + 1], ya, E), (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_x")
        b.box(hx + 0.15, 0.0, 0.0, 0.06, 2.4, 2.4, "door_steel")
        b.window(("y", N + 0.15, 1), 1.8, 1.2, 0.8, 0.6)
        b.window(("y", N + 0.15, 1), -2.0, 1.2, 0.8, 0.6)
        lib.finish(b, "f8_shed", out, tri_limit=1000, footprint=(1, 1))
        return
    kw = dict(brick_mat="boards", soot_h=1.0, top_tone=0.82)
    wall_run(b, (XE, N), (XW, N), 0.14, [E] * 8, "boards_vc", "boards", 51, hcap=3.0, jag=0.1, cap=0.06, **kw)
    wall_run(b, (XW, N), (XW, S), 0.14, [E, E, 2.6, 1.8, 0.7, 0.5], "boards_vc", "boards", 52, hcap=3.0, jag=0.5, **kw)
    wall_run(b, (XE, S), (XE, N), 0.14, [E] * 6, "boards_vc", "boards", 53, hcap=3.0, jag=0.1, cap=0.06, **kw)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.14, (XE, 0.0, 0.0), math.pi / 2, 0.0, "boards", top_mat="boards")
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.14, (XW, 0.0, 0.0), math.pi / 2, 0.0, "boards", top_mat="boards")
    post_x = (-3.4, -2.27, -1.13, 0.0, 1.13, 2.27, 3.4)
    post_h = (E, 1.8, 0.8, 1.2, 2.3, E, E)
    for x, h in zip(post_x, post_h):
        b.box(x, S, 0.0, 0.18, 0.18, h, "timber_dark")
    for (x, y, rot, ln, z, ang) in ((-1.9, -3.1, 0.1, 2.8, 0.2, 0.22), (0.4, -2.9, -0.15, 2.4, 0.3, 0.3), (-0.5, -3.7, 0.4, 1.8, 0.1, 0.1)):
        b.box_e(x, y, z + 0.2, ln, 1.9, 0.08, "boards", euler=(ang, 0.0, rot), top="boards")
    opening2(b, "x", XE + 0.1, -0.3, 0.05, 1.3, 2.2, 1)
    burn_ring(b, "x", XE + 0.1, -0.3, 0.05, 1.3, 2.2, 1, g_side=0.35, g_bot=0.0, g_top=0.7, t_in=0.22, t_out=0.62)
    opening2(b, "y", N + 0.1, 1.8, 0.9, 1.4, 1.3, 1)
    burn_ring(b, "y", N + 0.1, 1.8, 0.9, 1.4, 1.3, 1, g_side=0.35, g_bot=0.15, g_top=0.8, t_in=0.22, t_out=0.62)
    opening2(b, "y", N + 0.1, -2.0, 1.1, 0.8, 0.9, 1)

    def hpost(x):
        for i in range(len(post_x) - 1):
            if post_x[i] <= x <= post_x[i + 1]:
                f = (x - post_x[i]) / (post_x[i + 1] - post_x[i])
                return post_h[i] * (1 - f) + post_h[i + 1] * f
        return E
    pts = []
    for x in xs:
        ez = max(0.8, hpost(max(XW, min(XE, x))) + 0.06) + (rnd.uniform(-0.06, 0.06) if x < 1.5 else 0.0)
        pts.append((x, ya + (E - ez) * 0.3, ez))
    hole = {i for i, x in enumerate(xs[:-1]) if -2.0 < x < -1.0}
    for i in range(len(xs) - 1):
        if i not in hole:
            b.poly_up([pts[i], pts[i + 1], (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_x")
    for x in (-1.8, -1.5, -1.2):
        j = min(range(len(xs)), key=lambda k: abs(xs[k] - x))
        b.beam(pts[j], (xs[j], ym, R - 0.05), 0.1, "timber_dark", 0.16)
    plan = [HeapSurface(-1.2, -3.0, 1.7, 0.65, 0.65, 91, bumps=6, lip=0.24, wob=0.1, lump=0.05, hummocks=1, hum_amp=0.15),
            HeapSurface(-0.8, 0.1, 1.3, 0.9, 0.5, 92, bumps=5, lip=0.22, wob=0.08, lump=0.04, hummocks=1, hum_amp=0.12)]
    lumps(b, plan, rnd, 5)
    bh = heaps(b, plan, 11, dens=6.0)
    lib.finish(b, "ruin_half_shed", out, tri_limit=4600, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


for fn, nm in ((house1, "house1"), (house2, "house2"), (shed, "shed")):
    if want(nm):
        fn(False)
        fn(True)
