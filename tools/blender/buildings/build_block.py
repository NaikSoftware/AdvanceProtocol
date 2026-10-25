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
                    sp = [(x - 0.85, yy + e * 0.6, z + 1.35), (x + 0.85, yy + e * 0.6, z + 1.35), (x + 0.45, yy + e * 0.6, z + 4.0), (x - 0.45, yy + e * 0.6, z + 4.0)]
                    b.soot(sp, (0.02, 0.02, 0.38, 0.38), -sgn)
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
    """Обвал східного торця: стіни розрізані східцями на 1-3 поверхи, даху над провалом немає, плити й купа
    лежать у прольоті та перед ним (вид з боку камери: фасад -Y і торець +X)."""
    lib.reset()
    b = Builder()
    rnd = random.Random(21)
    xc = 6.0
    F, B = (2, 4), (0, 3)
    body(b, X0, xc, NF, F, B, True)
    windows(b, X0, xc, NF, F, B, blown={(sd, 6, f) for sd in ('front', 'back') for f in range(3)} | {(sd, 5, f) for sd in ('back',) for f in range(1, 3)})
    entrances(b, xc)
    roof_details(b, xc)
    # східці: висота кратна поверху (3.1 м), верх косий і зубчастий
    def steps(n, cap=NF):
        out_, h = [], rnd.randint(1, cap)
        for _ in range(n + 1):
            if rnd.random() < 0.45:
                h = max(1, min(cap, h + rnd.choice((-2, -1, 1, 1, 2))))
            out_.append(h * FLOOR + rnd.uniform(-0.25, 0.25))
        return out_
    back = steps(9, 1)                               # стіна біля проламу не вища за поверх
    east = steps(12)
    front = steps(4, 2)
    wall_run(b, (xc, Y0 + 0.2), (X1, Y0 + 0.2), 0.4, back, "panel_vc", "panel_vc", 5, pitch=0.7)
    wall_run(b, (X1 - 0.2, Y0), (X1 - 0.2, Y1), 0.4, east, "panel_vc", "panel_vc", 6, pitch=0.7)
    wall_run(b, (xc, Y1 - 0.2), (xc + 5.0, Y1 - 0.2), 0.4, front, "panel_vc", "panel_vc", 7, pitch=0.7)
    # вікна лишаються там, де стіна їх досягає; вибиті — з м'якою кіптявою
    def wall_h(vals, t):
        i = min(len(vals) - 2, max(0, int(t * (len(vals) - 1))))
        return vals[i]
    for i in (7, 8, 9):
        x = bay_x(i)
        t = (x - xc) / (X1 - xc)
        hb = wall_h(back, t)
        for f in range(3):
            z = f * FLOOR + 0.95
            if hb < z + 1.5:
                continue
            blow = rnd.random() < 0.85
            if blow:
                q = [(x - 0.7, Y0 - 0.03, z), (x + 0.7, Y0 - 0.03, z), (x + 0.7, Y0 - 0.03, z + 1.4), (x - 0.7, Y0 - 0.03, z + 1.4)]
                b.poly(q, "dark")
                b.soot([(x - 0.85, Y0 - 0.02, z + 1.35), (x + 0.85, Y0 - 0.02, z + 1.35), (x + 0.45, Y0 - 0.02, z + 4.0), (x - 0.45, Y0 - 0.02, z + 4.0)], (0.02, 0.02, 0.38, 0.38), 1)
            else:
                b.window(("y", Y0, -1), x, z, 1.4, 1.4)
    for k in range(6):
        yy = -4.2 + 1.6 * k
        t = (yy - Y0) / DEP
        he = wall_h(east, t)
        for f in range(3):
            z = f * FLOOR + 0.95
            if he < z + 1.5 or rnd.random() < 0.4:
                continue
            b.poly([(X1 + 0.03, yy - 0.7, z), (X1 + 0.03, yy + 0.7, z), (X1 + 0.03, yy + 0.7, z + 1.4), (X1 + 0.03, yy - 0.7, z + 1.4)], "dark")
            b.soot([(X1 + 0.02, yy - 0.85, z + 1.35), (X1 + 0.02, yy + 0.85, z + 1.35), (X1 + 0.02, yy + 0.45, z + 3.4), (X1 + 0.02, yy - 0.45, z + 3.4)], (0.02, 0.02, 0.38, 0.38), 1)
    # плити перекриттів, що лишились кронштейнами від стін, і розколота плита даху
    for (x, y, z, sx, sy, ax, ay, az) in ((9.0, -4.0, 3.0, 3.6, 1.8, 0.0, 0.0, 0.0), (13.5, -3.6, 6.1, 2.6, 2.0, 0.12, 0.0, 0.1), (8.0, 4.0, 3.0, 2.4, 1.6, -0.1, 0.0, 0.0)):
        b.box_e(x, y, z, sx, sy, 0.22, "panel", euler=(ax, ay, az), top="panel")
    # розколота плита даху лежить у прольоті під кутами 20-50° на купі
    for (x, y, z, sx, sy, ax, ay, az) in ((9.2, -0.5, 3.4, 3.2, 2.8, 0.7, 0.1, 0.2), (12.4, 1.6, 4.4, 3.4, 2.4, -0.8, 0.2, -0.4), (10.6, 2.8, 2.8, 2.8, 2.2, 0.5, -0.6, 0.6), (13.8, -1.8, 3.8, 2.6, 2.4, -0.6, -0.3, 1.1)):
        b.box_e(x, y, z, sx, sy, 0.22, "bitumen", euler=(ax, ay, az), top="bitumen")
    # арматура темна, іржава
    for k in range(18):
        x = rnd.uniform(6.5, 15.0)
        p0 = (x, Y0 + 0.2, rnd.uniform(3.0, 6.0)) if rnd.random() < 0.5 else (X1 - 0.2, rnd.uniform(-5, 5), rnd.uniform(3.0, 6.0))
        b.beam(p0, (p0[0] + rnd.uniform(-0.9, 0.9), p0[1] + rnd.uniform(-0.8, 0.8), p0[2] + rnd.uniform(0.5, 1.4)), 0.09, "rebar")
    # одна безперервна купа: заповнює проліт, виливається через низьку задню стіну на відсип і далі на торець
    mound(b, 11.0, 0.5, 4.8, 4.6, 5.0, 61, mat="heap_grey", rings=6, segs=22, tongues=2)
    mound(b, 12.8, -5.2, 4.8, 2.1, 3.4, 62, mat="heap_grey", rings=5, segs=18, tongues=4)
    mound(b, 16.4, -1.5, 2.6, 5.0, 2.6, 63, mat="heap_grey", rings=5, segs=16, tongues=3)
    chunks(b, 11.0, 0.0, 4.2, 4.0, 9, ("heap_grey", "rubble"), 2, z0=0.4, smin=0.5, smax=1.1)
    for k in range(10):                                                          # розсип тоншає без жорсткого краю
        a = rnd.uniform(0, 2 * math.pi)
        t = rnd.uniform(0.75, 1.15)
        px, py = 14.0 + 5.8 * t * math.cos(a), -2.5 + 6.2 * t * math.sin(a)
        if px < 15.0 or abs(py) > 8.4 or px > 20.2:
            continue
        b.rock(px, py, 0.12, rnd.uniform(0.28, 0.5), rnd.choice(("heap_grey", "rubble")), rnd)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4000, footprint=(5, 2), anchor=(0, 0))


intact()
damaged()
