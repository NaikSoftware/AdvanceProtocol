"""H5: панельна триповерхівка 30 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, chunks, mound, wall_run

out = lib.out_dir()
LEN, DEP, FLOOR, NF = 30.0, 12.0, 3.1, 3
H = FLOOR * NF           # 9.3 м до плити даху
X0, X1, Y0, Y1 = -LEN / 2, LEN / 2, -DEP / 2, DEP / 2
STAIRS = (1, 5, 8)       # осі сходових кліток (кроки по 3 м)
LOG = 1.2                # глибина лоджії
LW = 1.3                 # піввисота лоджії по ширині (проріз 2.6 м)


def bay_x(i):
    return X0 + 1.5 + 3.0 * i


def intervals(xa, xb, cols):
    """Відрізки фасадного шару між лоджіями (проріз 2.6 м навколо осі панелі)."""
    cuts = sorted((bay_x(i) - LW, bay_x(i) + LW) for i in cols)
    res, cur = [], xa
    for a, b in cuts:
        if a > cur:
            res.append((cur, a))
        cur = b
    if cur < xb:
        res.append((cur, xb))
    return res


def body(b, xa, xb, nf, front, back, roof):
    """Секція будинку: серцевина, фасадні шари з прорізами-лоджіями, вікна на сітці."""
    top_z = nf * FLOOR
    b.box((xa + xb) / 2, 0, 0, xb - xa, DEP - 2 * LOG, top_z, "panel", top="bitumen" if roof else "panel_scorched")
    for (ya, yb, cols, side) in ((Y1 - LOG, Y1, front, 1), (Y0, Y0 + LOG, back, -1)):
        yc = (ya + yb) / 2
        for f in range(nf):
            z0 = f * FLOOR
            use = cols if f >= 1 else ()
            for (a, c) in intervals(xa, xb, [i for i in use if xa <= bay_x(i) <= xb]):
                b.box((a + c) / 2, yc, z0, c - a, LOG, FLOOR, "panel", top="panel" if f < nf - 1 or not roof else "bitumen")
        for i in cols:
            x = bay_x(i)
            if not (xa <= x <= xb):
                continue
            ye = Y1 if side > 0 else Y0
            yp = ye - 0.06 * side
            for f in (1, 2):
                if f >= nf:
                    continue
                z = f * FLOOR
                b.box(x, yp, z, 2 * LW, 0.12, 1.1, "panel")                       # парапет лоджії 1.1 м
                yb = ye - LOG * side + 0.01 * side
                b.poly([(x - LW, yb, z), (x + LW, yb, z), (x + LW, yb, z + FLOOR), (x - LW, yb, z + FLOOR)][::-side], "panel_light")
                for sx in (-1, 1):
                    b.box(x + sx * (LW - 0.02), (ya + yb) / 2, z, 0.03, LOG, FLOOR - 0.15, "panel_light")
            if nf > 2:
                b.box(x, (ya + yb) / 2, 2 * FLOOR - 0.15, 2 * LW, LOG, 0.15, "panel", top="panel")  # плита між лоджіями
                b.box(x, (ya + yb) / 2, top_z - 0.2, 2 * LW, LOG, 0.2, "panel", top="bitumen" if roof else "panel")


def windows(b, xa, xb, nf, front, back, blown=()):
    """Сувора сітка: одне вікно на панель, однакового розміру; лоджійні вікна в глибині ніші."""
    for side, (y, sgn, cols) in (("front", (Y1, 1, front)), ("back", (Y0, -1, back))):
        for i in range(10):
            x = bay_x(i)
            if not (xa <= x <= xb):
                continue
            for f in range(nf):
                if i in STAIRS and f == 0 and side == "front":
                    continue
                z = f * FLOOR + 0.95
                yy = y - (LOG * sgn if (i in cols and f >= 1) else 0.0)
                if (side, i, f) in blown:
                    e = 0.03 * sgn
                    q = [(x - 0.7, yy + e, z), (x + 0.7, yy + e, z), (x + 0.7, yy + e, z + 1.4), (x - 0.7, yy + e, z + 1.4)]
                    b.poly(q[::sgn], "dark")
                    for (dx0, dx1, hh) in ((-0.65, -0.2, 1.4), (-0.15, 0.3, 2.2), (0.35, 0.65, 1.1)):
                        t = [(x + dx0, yy + e, z + 1.4), (x + dx1, yy + e, z + 1.4), (x + (dx0 + dx1) / 2, yy + e, z + 1.4 + hh)]
                        b.poly(t[::sgn], "soot")
                    continue
                b.window(("y", yy, sgn), x, z, 1.4, 1.4)
                if not (i in cols and f >= 1):
                    b.box(x, yy + 0.06 * sgn, z - 0.1, 1.7, 0.14, 0.1, "panel")      # підвіконня


def roof_details(b, xmax):
    for i in STAIRS:
        if bay_x(i) > xmax:
            continue
        b.box(bay_x(i), Y0 + 2.6, H, 2.6, 2.6, 2.4, "panel", top="bitumen")
    for k, x in enumerate((-12, -7, -2, 3, 11.5, 13.5)):
        if x > xmax:
            continue
        b.cyl(x, 1.2 * (-1) ** k, H, 0.22, 1.6, 8, "metal_dark")
    # парапет по периметру даху
    xe = min(X1, xmax + 0.0)
    b.box((X0 + xe) / 2, Y1 - 0.1, H, xe - X0, 0.2, 0.5, "panel")
    b.box((X0 + xe) / 2, Y0 + 0.1, H, xe - X0, 0.2, 0.5, "panel")
    b.box(X0 + 0.1, 0, H, 0.2, DEP - 0.4, 0.5, "panel")
    if xe >= X1:
        b.box(X1 - 0.1, 0, H, 0.2, DEP - 0.4, 0.5, "panel")


def entrances(b, xmax):
    for i in STAIRS:
        if bay_x(i) > xmax:
            continue
        b.box(bay_x(i), Y1 + 0.02, 0, 1.3, 0.04, 2.1, "dark")
        b.box(bay_x(i), Y1 + 0.6, 2.4, 2.4, 1.2, 0.15, "bitumen", top="bitumen")


def intact():
    lib.reset()
    b = Builder()
    F, B = (2, 4, 7), (0, 3, 6)
    body(b, X0, X1, NF, F, B, True)
    windows(b, X0, X1, NF, F, B)
    entrances(b, X1)
    roof_details(b, X1)
    lib.finish(b, "h5_panel_block", out, tri_limit=2500, footprint=(4, 2), anchor=(0, 0))


def damaged():
    lib.reset()
    b = Builder()
    rnd = random.Random(21)
    xc = 6.0
    z2 = 2 * FLOOR
    F, B = (2, 4), (0, 3)
    body(b, X0, xc, NF, F, B, True)
    body(b, xc, X1, 2, (), (), False)
    blown = {("front", 7, 0), ("front", 7, 1), ("front", 8, 1), ("front", 9, 1), ("back", 7, 0), ("back", 7, 1), ("back", 8, 1), ("back", 9, 0), ("back", 9, 1)}
    windows(b, X0, xc, NF, F, B)
    windows(b, xc, X1, 2, (), (), blown=blown)
    entrances(b, xc)
    roof_details(b, xc)
    b.box((xc + X1) / 2, 0, z2 - 0.05, X1 - xc, DEP, 0.2, "panel_scorched", top="panel_scorched")
    # східчастий зубчастий профіль зламу: стіни третього поверху від 0.3 до 3.1 м з косими верхами
    def prof(n, lo=0.3, hi=3.1):
        h = [rnd.uniform(lo, hi)]
        for _ in range(n):
            h.append(min(hi, max(lo, h[-1] + rnd.uniform(-1.4, 1.4))))
        return h
    wall_run(b, (xc, Y0 + 0.2), (X1, Y0 + 0.2), 0.4, prof(9), "panel_scorched", "char", 5)
    wall_run(b, (X1 - 0.2, Y0), (X1 - 0.2, Y1), 0.4, [0.0, 0.0] + prof(8, 0.2, 2.6)[:-1], "panel_scorched", "char", 6)
    wall_run(b, (xc, Y1 - 0.2), (xc + 4.0, Y1 - 0.2), 0.4, prof(4, 0.3, 2.2), "panel_scorched", "char", 7)
    # плита даху розколота на 3-4 шматки, що спираються на купу під кутами 20-50°
    for (x, y, z, sx, sy, ax, ay, az) in ((8.6, -2.2, 1.3, 3.2, 2.8, 0.55, 0.1, 0.2), (12.0, 1.8, 2.0, 3.4, 2.6, -0.7, 0.2, -0.4), (10.2, 2.6, 1.0, 2.8, 2.2, 0.35, -0.5, 0.6), (13.6, -2.6, 1.7, 2.6, 2.4, -0.45, -0.3, 1.1)):
        b.box_e(x, y, z2 + z, sx, sy, 0.22, "bitumen", euler=(ax, ay, az), top="bitumen")
    # темна іржава арматура з обламаних країв
    for k in range(18):
        x = rnd.uniform(6.5, 15.0)
        edge = rnd.random()
        if edge < 0.35:
            p0 = (x, Y0 + 0.2, z2 + 0.3)
        elif edge < 0.6:
            p0 = (X1 - 0.2, rnd.uniform(-5, 5), z2 + 0.3)
        else:
            p0 = (x, rnd.uniform(-5, 5), z2 + 0.1)
        b.beam(p0, (p0[0] + rnd.uniform(-0.9, 0.9), p0[1] + rnd.uniform(-0.8, 0.8), p0[2] + rnd.uniform(0.5, 1.4)), 0.09, "rebar")
    # відсип 4-6 м завширшки й 1.5-2 м заввишки на вибитому розі (бік, що його бачить камера)
    mound(b, 17.0, -1.0, 3.6, 7.4, 2.0, 61, rings=7, segs=24)
    mound(b, 11.5, -6.5, 4.5, 1.9, 1.5, 62, rings=5, segs=18)
    mound(b, 10.5, 0.0, 4.2, 5.0, 1.3, 63, z0=z2, rings=5, segs=18)
    chunks(b, 16.8, -1.0, 2.6, 2.0, 22, ("rubble", "panel_scorched", "panel", "brick_grey"), 2, smin=0.5, smax=1.4)
    chunks(b, 10.2, -6.4, 1.3, 1.5, 10, ("rubble", "panel_scorched"), 3, smin=0.5, smax=1.0)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4200, footprint=(5, 2), anchor=(0, 0))


intact()
damaged()
