"""H5: панельна триповерхівка 30 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, chunks

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
                b.box(x, yp, z, 2 * LW, 0.12, 1.0, "panel")                       # парапет лоджії
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
                    b.poly([(x - 0.7, yy + 0.03 * sgn, z), (x + 0.7, yy + 0.03 * sgn, z), (x + 0.7, yy + 0.03 * sgn, z + 1.4), (x - 0.7, yy + 0.03 * sgn, z + 1.4)][::sgn], "dark")
                    b.poly([(x - 0.9, yy + 0.02 * sgn, z + 1.4), (x + 0.9, yy + 0.02 * sgn, z + 1.4), (x + 0.5, yy + 0.02 * sgn, z + 2.5), (x - 0.5, yy + 0.02 * sgn, z + 2.3)][::sgn], "panel_scorched")
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
    # плита перекриття 2-го поверху, частково зірвана; обрубки стін третього поверху — зубчасті
    b.box((xc + X1) / 2, 0, z2 - 0.05, X1 - xc, DEP, 0.2, "panel_scorched", top="panel_scorched")
    stubs = ((7.0, Y1 - 0.2, 1.4, 0.4, 2.6), (8.6, Y1 - 0.2, 0.7, 0.4, 0.8), (6.5, Y0 + 0.2, 1.0, 0.4, 2.9), (9.0, Y0 + 0.2, 3.0, 0.4, 1.1), (11.0, Y0 + 0.2, 1.2, 0.4, 2.5),
             (13.3, Y0 + 0.2, 2.2, 0.4, 3.0), (X1 - 0.2, -3.0, 0.4, 3.5, 1.3), (X1 - 0.2, 1.0, 0.4, 1.0, 2.9), (X1 - 0.2, 4.0, 0.4, 2.0, 1.0), (10.6, Y1 - 0.2, 1.6, 0.4, 0.6))
    for (x, y, sx, sy, h) in stubs:
        b.box_e(x, y, z2 + h / 2, sx, sy, h, "panel_scorched", euler=(0, 0, rnd.uniform(-0.05, 0.05)), top="char")
    # нерівна арматура, що стирчить з краю плити й обламків
    for k in range(16):
        x = rnd.uniform(6.5, 15.0)
        y = rnd.choice((Y1 - 0.2, Y0 + 0.2)) if rnd.random() < 0.6 else rnd.uniform(-5, 5)
        ex = X1 + 0.1 if y not in (Y1 - 0.2, Y0 + 0.2) else x
        b.beam((ex, y, z2 - 0.05), (ex + rnd.uniform(-0.8, 0.9), y + rnd.uniform(-0.7, 0.8), z2 + rnd.uniform(0.4, 1.4)), 0.09, "rust")
    # купи кутастого завалу: на плиті, перед фасадом, збоку й ззаду
    chunks(b, 10.8, 0.0, 4.6, 2.4, 55, ("rubble", "panel_scorched", "panel"), 1, z0=z2, smin=0.4, smax=1.4)
    chunks(b, 11.0, 5.9, 1.9, 3.4, 30, ("rubble", "panel_scorched", "brick_grey"), 2, smin=0.5, smax=1.5)
    chunks(b, 14.4, 0.5, 1.5, 2.0, 14, ("rubble", "panel"), 3, smin=0.5, smax=1.2)
    chunks(b, 10.5, -6.4, 1.6, 1.6, 12, ("rubble", "panel_scorched"), 4, smin=0.5, smax=1.2)
    # упала плита даху на купі
    b.box_e(9.8, 0.2, z2 + 1.9, 6.0, 5.0, 0.22, "bitumen", euler=(0.18, -0.12, 0.1), top="bitumen")
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=3200, footprint=(4, 2), anchor=(0, 0))


intact()
damaged()
