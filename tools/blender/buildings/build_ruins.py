"""Напівзруйновані будівлі: стоять майже всі стіни, один кут або секція обвалені, дах частково згорів, у стінах вибиті вікна,
діри від снарядів і немає дверей; завал лише там, де обвал. Контур — геометрія (діри, зламаний дах, обвал), деталь — запікання.
Камера гри бачить боки -Y і +X, тому руйнування скрізь на них. Запуск: build_ruins.py -- <out> [house1 house2 shed]"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, wall_run, burn_ring, opening, chip_slab, prism, bent_sheet, HeapSurface, heap_mound
from mathutils import Vector

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


def heaps(b, plan, seed, dens=7.0, mats=("rubble_hi",) * 5 + ("heap_grey",) * 2, base="heap_base"):
    """Купи: низький меш у b, високе скан-джерело повертається для запікання (темна основа, уламки 20-50 см зверху)."""
    bh = Builder()
    hr = random.Random(seed)
    for k, h in enumerate(plan):
        big = h.rx * h.ry > 8
        heap_mound(b, h, "heap", rings=7 if big else 3, segs=32 if big else 16)
        heap_mound(bh, h, base, rings=16 if big else 6, segs=96 if big else 40, jitter=0.04, seed=seed + k)
        for _ in range(int(math.pi * h.rx * h.ry * dens)):
            a = hr.uniform(0, 2 * math.pi)
            t = math.sqrt(hr.uniform(0, 1.0)) * 1.12
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py) if t < 1.0 else h.lip * max(0.0, 1.0 - (t - 1.0) / 0.12) * 0.8
            q = hr.random()
            size = hr.uniform(0.2, 0.42) if q < 0.7 else (hr.uniform(0.42, 0.6) if q < 0.95 else hr.uniform(0.6, 0.85))
            bh.rock(px, py, z + 0.04, size, hr.choice(mats), hr, buried=0.3)
    return bh


def soot_cut(b, P, cut, sgn, depth=0.5, nv=10):
    """Смуга кіптяви вздовж рваного краю даху: майже чорна біля краю, світлішає вглиб збереженої частини."""
    for i in range(nv):
        v0, v1 = i / nv, (i + 1) / nv
        pts = [P(cut(v0), v0), P(cut(v1), v1), P(cut(v1) + depth * sgn, v1), P(cut(v0) + depth * sgn, v0)]
        pts = [(x, y, z + 0.03) for (x, y, z) in pts]
        n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        tones = (0.02, 0.02, 0.2, 0.2)
        if n_.z < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)


def roof_part(b, P, x_end, cut, mat, nv=10):
    """Скат, що лишився між кінцем будинку x_end і рваним краєм cut(v) (v: 0 — карниз, 1 — коник)."""
    pts = [P(x_end, 0.0)] + [P(cut(i / nv), i / nv) for i in range(nv + 1)] + [P(x_end, 1.0)]
    b.poly_up(pts, mat)


def rafters(b, P, xs, rnd, v_lo, th=0.12, d=0.2, miss=0.2, mat="timber_dark", lo_z=None, sag=0.5):
    """Крокви над проваллом: частини немає, решта обламана на різній висоті й провисла."""
    for x in xs:
        if rnd.random() < miss:
            continue
        v1 = rnd.uniform(0.55, 1.0)
        a, c = Vector(P(x, v_lo)), Vector(P(x, v1))
        c.z -= rnd.uniform(0.3, 1.0) * sag * v1 * 2                        # провисла вниз до стіни
        if lo_z:                                                            # нижній кінець лежить на низькій обваленій стіні, а не висить над нею
            a.z = lo_z(x)
        b.beam(a, c, th, mat, d)


def house1():
    """Одноповерховий цегляний дім: східна половина даху ціла, західна провалилась, обвалена частина фронтальної й західної стін."""
    lib.reset()
    b = Builder()
    rnd = random.Random(14)
    E, R, ya, yb, ym, xb = 2.9, 5.6, -3.6, 3.6, 0.0, 5.4
    S, N = -3.2, 3.2
    # --- стіни: стоять майже на повну висоту, обвал — окремі куски з низьким рваним верхом
    wall_run(b, (-1.5, S), (5.0, S), 0.4, [2.9] * 8, "wall_ruin", "brick_ruin", 21, hcap=3.0, jag=0.12)
    wall_run(b, (-5.0, S), (-1.5, S), 0.4, [0.6, 1.4, 0.9, 2.0], "wall_ruin", "brick_ruin", 22, hcap=2.4)
    wall_run(b, (5.0, S), (5.0, N), 0.4, [2.9] * 8, "wall_ruin", "brick_ruin", 23, hcap=3.0, jag=0.12)
    wall_run(b, (5.0, N), (-2.0, N), 0.4, [2.9] * 8, "wall_ruin", "brick_ruin", 24, hcap=3.0, jag=0.12)
    wall_run(b, (-2.0, N), (-5.0, N), 0.4, [1.9, 1.2, 2.3, 0.8], "wall_ruin", "brick_ruin", 25, hcap=2.6)
    wall_run(b, (-5.0, N), (-5.0, S), 0.4, [2.5, 1.4, 0.7, 1.1, 0.5, 0.9, 0.6], "wall_ruin", "brick_ruin", 26, hcap=2.6)
    prism(b, [(-3.2, E), (3.2, E), (0.0, R)], 0.4, (5.0, 0.0, 0.0), math.pi / 2, 0.0, "brick_ruin", top_mat="brick_ruin")        # східний фронтон
    # --- вікна, двері, діри (на сторонах, що бачить камера, і ззаду)
    for x in (2.9, 4.3):
        burn_ring(b, "y", S - 0.2, x, 1.0, 1.2, 1.3, -1, g_side=0.45, g_bot=0.15, g_top=1.3)
        opening(b, "y", S - 0.2, x, 1.0, 1.2, 1.3, -1, k=4.5)
    opening(b, "y", S - 0.2, 0.2, 0.05, 1.1, 2.1, -1, k=4.5)                                   # двері вибито
    burn_ring(b, "y", S - 0.2, 0.2, 0.05, 1.1, 2.1, -1, g_side=0.5, g_bot=0.0, g_top=1.2)
    for y, w, h, z in ((-1.7, 1.2, 1.3, 1.0), (1.2, 1.7, 1.5, 0.8)):                         # східна стіна: вікно й діра від снаряда
        burn_ring(b, "x", 5.2, y, z, w, h, 1, g_side=0.5, g_bot=0.2, g_top=1.4)
        opening(b, "x", 5.2, y, z, w, h, 1, k=6.0)
    for x in (1.5, 3.6):
        burn_ring(b, "y", N + 0.2, x, 1.0, 1.2, 1.3, 1, g_side=0.45, g_bot=0.15, g_top=1.3)
        opening(b, "y", N + 0.2, x, 1.0, 1.2, 1.3, 1, k=4.5)
    # --- дах: схід цілий, захід упав; рваний край із кіптявою, крокви, провислі листи
    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    phs = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return 0.1 + 0.9 * math.sin(3.1 * v + phs[0]) + 0.3 * math.sin(9 * v + phs[1])

    def cutB(v):
        return -0.6 + 0.8 * math.sin(2.7 * v + phs[2]) + 0.3 * math.sin(8 * v + phs[0])
    roof_part(b, PF, xb, cutF, "fc_roof_xh")
    roof_part(b, PB, xb, cutB, "fc_roof_xh")
    soot_cut(b, PF, cutF, 1)
    soot_cut(b, PB, cutB, 1)
    xs = [-5.2 + 0.9 * i for i in range(7)]
    rafters(b, PF, xs, rnd, 0.0, lo_z=lambda x: 2.9 if x > -1.6 else 1.0 + 0.3 * (x + 5.2), sag=1.0)
    rafters(b, PB, xs, rnd, 0.0, lo_z=lambda x: 2.9 if x > -2.0 else 1.2, sag=1.0)
    b.beam((-5.0, ym, R - 0.1), (-1.0, ym, R - 0.55), 0.16, "timber_dark", 0.22)              # коник провис
    bent_sheet(b, (-1.6, -0.4, R - 0.5), (-2.0, -2.8, E + 0.1), 1.4, "fc_roof_burnt", 0.3)
    bent_sheet(b, (-3.2, 0.6, R - 0.9), (-3.0, 2.6, E + 0.0), 1.2, "fc_roof_burnt", 0.25)
    b.box(2.2, -0.2, 4.0, 0.75, 0.75, 3.3, "brick_ruin", top="brick_ruin")
    # --- завал: усередині під зниклим дахом і зсув назовні під обваленою стіною
    plan = [HeapSurface(-2.6, 0.2, 2.3, 2.5, 1.0, 71, bumps=6, lip=0.3, wob=0.2, lump=0.1, hummocks=3, hum_amp=0.35),
            HeapSurface(-3.3, -4.4, 2.5, 1.5, 1.0, 72, bumps=5, lip=0.28, wob=0.15, lump=0.08, hummocks=2, hum_amp=0.3),
            HeapSurface(-6.2, 0.4, 1.4, 2.6, 0.9, 73, bumps=6, lip=0.26, wob=0.15, lump=0.08, hummocks=2, hum_amp=0.3)]
    bh = heaps(b, plan, 7)
    lib.finish(b, "ruin_half_house1", out, tri_limit=4600, footprint=(2, 2), anchor=(0, 0), hi=bh, ground_clip=True)


def house2():
    """Двоповерховий дім: західна половина даху ціла, обвалений східний фронтон, перекриття висить із зрізу, завал назовні."""
    lib.reset()
    b = Builder()
    rnd = random.Random(33)
    E, R, ya, yb, ym = 6.0, 8.6, -5.4, 5.4, 0.0
    S, N = -5.0, 5.0
    FL = 3.1
    wall_run(b, (-5.0, S), (5.0, S), 0.4, [6.0] * 11, "wall_ruin", "brick_ruin", 31, hcap=6.2, jag=0.1)
    wall_run(b, (5.0, N), (-5.0, N), 0.4, [6.0] * 11, "wall_ruin", "brick_ruin", 32, hcap=6.2, jag=0.1)
    wall_run(b, (-5.0, N), (-5.0, S), 0.4, [6.0] * 11, "wall_ruin", "brick_ruin", 33, hcap=6.2, jag=0.1)
    prism(b, [(-5.0, E), (5.0, E), (0.0, R)], 0.4, (-5.0, 0.0, 0.0), math.pi / 2, 0.0, "brick_ruin", top_mat="brick_ruin")          # західний фронтон ціла
    # східний фронтон обвалений: низькі рвані секції з одним високим клином
    wall_run(b, (5.0, S), (5.0, N), 0.4, [1.3, 2.4, 4.6, 5.6, 4.0, 2.0, 1.2, 0.9, 1.7, 2.8, 1.4], "wall_ruin", "brick_ruin", 34, hcap=5.8, jag=0.7)
    # вікна двох поверхів; частина вибита з кіптявою, частина ще з рамами
    for fl, z in ((0, 1.0), (1, 4.0)):
        for x in (-3.4, -0.4, 2.6):
            blown = (fl == 1 and x != -0.4) or (fl == 0 and x == 2.6)
            if blown:
                burn_ring(b, "y", S - 0.2, x, z, 1.3, 1.5, -1, g_side=0.5, g_bot=0.2, g_top=1.5)
                opening(b, "y", S - 0.2, x, z, 1.3, 1.5, -1, k=4.5)
            else:
                b.window(("y", S - 0.2, -1), x, z, 1.3, 1.5)
        for x in (-2.0, 1.5):
            b.window(("y", N + 0.2, 1), x, z, 1.3, 1.5)
    opening(b, "y", S - 0.2, 4.0, 0.05, 1.1, 2.1, -1, k=4.5)                                 # двері вибито
    burn_ring(b, "y", S - 0.2, 4.0, 0.05, 1.1, 2.1, -1, g_side=0.5, g_bot=0.0, g_top=1.4)
    for y, z, w, h in ((-3.3, 1.0, 1.3, 1.5), (3.2, 4.0, 1.3, 1.5)):                          # східна стіна: де ще є, там вікна
        pass
    # дах: лише західна частина, рваний край; крокви далі
    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return 1.2 + 0.9 * math.sin(3 * v + ph[0]) + 0.35 * math.sin(9 * v + ph[1])

    def cutB(v):
        return 2.2 + 0.9 * math.sin(2.6 * v + ph[2]) + 0.35 * math.sin(8 * v + ph[0])
    roof_part(b, PF, -5.5, cutF, "tile_graphite")
    roof_part(b, PB, -5.5, cutB, "tile_graphite")
    soot_cut(b, PF, cutF, -1)
    soot_cut(b, PB, cutB, -1)
    xs = [1.0 + 0.9 * i for i in range(6)]
    rafters(b, PF, xs, rnd, 0.0, th=0.14, d=0.24)
    rafters(b, PB, xs, rnd, 0.0, th=0.14, d=0.24)
    b.beam((1.0, ym, R - 0.1), (5.0, ym, R - 0.9), 0.18, "timber_dark", 0.24)
    bent_sheet(b, (3.0, -1.0, R - 0.8), (3.4, -4.6, E + 0.1), 1.6, "fc_roof_burnt", 0.35)
    # перекриття між поверхами: висить із зрізу, нахилене до купи
    chip_slab(b, 2.6, 0.0, FL - 0.1, 5.6, 9.2, 0.28, (0.0, 0.17, 0.02), "slab_dark", "slab_dark", 41, rebar=4)
    b.box(-2.5, 0.0, 6.0, 0.9, 0.9, 2.2, "brick_ruin", top="brick_ruin")
    plan = [HeapSurface(5.4, 0.0, 2.5, 4.4, 1.7, 81, bumps=6, lip=0.3, wob=0.25, lump=0.12, hummocks=4, hum_amp=0.45, pw=1.5),
            HeapSurface(2.0, 0.5, 2.8, 3.2, 1.0, 82, bumps=5, lip=0.28, wob=0.15, lump=0.08, hummocks=2, hum_amp=0.3)]
    plan[0].fit_peak(1.9)
    bh = heaps(b, plan, 9, mats=("rubble_hi",) * 4 + ("heap_grey",) * 3)
    lib.finish(b, "ruin_half_house2", out, tri_limit=4800, footprint=(2, 2), anchor=(0, 0), hi=bh, ground_clip=True)


def shed():
    """Господарський сарай: задня й торцеві стіни стоять, фронтальна (на камеру) впала, дах з цього боку провис і провалився."""
    lib.reset()
    b = Builder()
    rnd = random.Random(57)
    E, R, ya, yb, ym = 3.4, 4.7, -3.4, 3.4, 0.0
    S, N, XW, XE = -3.0, 3.0, -6.0, 6.0
    wall_run(b, (XE, N), (XW, N), 0.14, [3.4] * 13, "clad_vc", "clad_wall", 51, hcap=3.5, jag=0.1, soot_h=1.2, brick_mat="clad_wall")
    wall_run(b, (XW, N), (XW, S), 0.14, [3.4, 3.4, 3.2, 2.2, 0.8, 0.6, 0.5], "clad_vc", "clad_wall", 52, hcap=3.5, jag=0.5, soot_h=1.2, brick_mat="clad_wall")
    wall_run(b, (XE, S), (XE, N), 0.14, [3.4] * 7, "clad_vc", "clad_wall", 53, hcap=3.5, jag=0.1, soot_h=1.2, brick_mat="clad_wall")
    prism(b, [(-3.0, E), (3.0, E), (0.0, R)], 0.14, (XE, 0.0, 0.0), math.pi / 2, 0.0, "clad_wall", top_mat="clad_wall")
    # фронтальна стіна: стійки частково стоять, полотнища лежать назовні
    for i, x in enumerate((-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0)):
        h = (3.4, 2.1, 0.9, 1.4, 2.8, 3.4, 3.4)[i]
        b.box(x, S, 0.0, 0.2, 0.2, h, "timber_dark")
    for (x, y, rot, ln, z, ang) in ((-3.0, -4.7, 0.1, 3.8, 0.25, 0.22), (0.5, -4.4, -0.15, 3.4, 0.5, 0.35), (-0.5, -5.9, 0.4, 2.6, 0.12, 0.1)):
        b.box_e(x, y, z + 0.2, ln, 2.4, 0.08, "clad_vc", euler=(ang, 0.0, rot), top="clad_vc")
    # прорізи: двері вибито на торці, діра від снаряда й вікно в тильній стіні
    opening(b, "x", XE + 0.1, -0.5, 0.05, 1.5, 2.4, 1, k=6.0)
    burn_ring(b, "x", XE + 0.1, -0.5, 0.05, 1.5, 2.4, 1, g_side=0.5, g_bot=0.0, g_top=1.0)
    opening(b, "y", N + 0.1, 2.0, 0.9, 1.6, 1.5, 1, k=4.5)
    burn_ring(b, "y", N + 0.1, 2.0, 0.9, 1.6, 1.5, 1, g_side=0.5, g_bot=0.2, g_top=1.2)
    opening(b, "y", N + 0.1, -3.5, 1.2, 1.0, 1.0, 1, k=4.5)

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]
    roof_part(b, PB, XE + 0.3, lambda v: -5.8 + 0.5 * math.sin(4 * v + ph[0]), "tin_red")          # задній скат майже цілий
    # передній скат: східний шматок і західний, посередині провал
    def cutE(v):
        return 0.5 + 1.0 * math.sin(3 * v + ph[1]) + 0.3 * math.sin(9 * v + ph[2])
    roof_part(b, PF, XE + 0.3, cutE, "tin_red")
    soot_cut(b, PF, cutE, 1, depth=0.6)

    def cutW(v):
        return -2.5 + 0.9 * math.sin(3.4 * v + ph[2]) + 0.3 * math.sin(8 * v + ph[0])
    roof_part(b, PF, XW - 0.3, cutW, "tin_red")
    soot_cut(b, PF, cutW, -1, depth=0.6)
    rafters(b, PF, [-2.2 + 0.8 * i for i in range(6)], rnd, 0.0, th=0.1, d=0.16, miss=0.15)
    b.beam((-6.0, ym, R - 0.1), (-2.0, ym, R - 0.7), 0.14, "timber_dark", 0.2)
    bent_sheet(b, (-0.6, -0.5, R - 0.7), (-1.0, -3.2, 1.0), 1.5, "clad_burnt", 0.3)
    plan = [HeapSurface(-1.5, -4.6, 3.4, 1.7, 0.9, 91, bumps=6, lip=0.26, wob=0.15, lump=0.08, hummocks=2, hum_amp=0.25),
            HeapSurface(-0.5, 0.2, 3.0, 2.0, 0.7, 92, bumps=5, lip=0.24, wob=0.1, lump=0.06, hummocks=2, hum_amp=0.2)]
    bh = heaps(b, plan, 11, dens=6.0, mats=("rubble_steel", "heap_grey", "rubble_hi", "heap_grey"))
    lib.finish(b, "ruin_half_shed", out, tri_limit=4600, footprint=(2, 2), anchor=(0, 0), hi=bh, ground_clip=True)


if want("house1"):
    house1()
if want("house2"):
    house2()
if want("shed"):
    shed()
