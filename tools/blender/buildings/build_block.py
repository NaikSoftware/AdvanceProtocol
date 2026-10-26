"""H5: панельна триповерхівка 30 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, chunks, mound, wall_run, burn_ring, panel_wall, opening2, chip_slab, HeapSurface, heap_mound

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
                b.box(x, yp, z + 1.1, 2 * LW + 0.1, 0.07, 0.07, "metal_dark")    # поручень
                yb = ye - LOG * side + 0.01 * side
                b.poly([(x - LW, yb, z), (x + LW, yb, z), (x + LW, yb, z + FLOOR), (x - LW, yb, z + FLOOR)][::-side], "panel_light")
                for sx in (-1, 1):
                    b.box(x + sx * (LW - 0.02), (ya + yb) / 2, z, 0.03, LOG, FLOOR - 0.15, "panel_light")
                if (i * 7 + f * 3 + (1 if side > 0 else 0)) % 2 == 0:                       # засклена лоджія: рама над парапетом
                    b.window(("y", ye - 0.08 * side, side), x, z + 1.15, 2 * LW - 0.06, FLOOR - 1.4)
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
                    lib.burn_ring(b, "y", yy, x, z + 0.15, 1.1, 1.1, sgn, g_side=0.35, g_bot=0.1, g_top=5.0, ztop=H - 0.05, mat="panel_dm", strong=True)
                    lib.plume(b, "y", yy, sgn, x, z + 1.25, 1.1, H - 0.05, "panel_dm")          # шлейф над прорізом на чистій стіні
                    opening2(b, "y", yy, x, z + 0.15, 1.1, 1.1, sgn, streak=0.0, sooty=True)
                    lib.window_ring(b, "y", yy, sgn, x, z + 0.15, 1.1, 1.1, d=0.15, t=0.03, mat="panel")   # укіс: справжній отвір усередину
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
        if x > xmax or (xmax < X1 and x > -4):
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
    lib.palette(glass="dark")                                                    # темне скло з сірим небом: світлі штори в панельці читались папером
    b = Builder()
    F, B = (2, 4, 7), (0, 3, 6)
    body(b, X0, X1, NF, F, B, True)
    windows(b, X0, X1, NF, F, B)
    entrances(b, X1)
    roof_details(b, X1)
    # бризки біля цоколя, патьоки під кожним підвіконням і від парапету даху; над відкритими лоджіями стіни немає
    sk = lambda cols: [(bay_x(i) - LW, bay_x(i) + LW) for i in cols]
    lib.weather(b, "panel", [("y", Y1, 1, X0, X1, 0.0, H)], seed=21, patches=False, skip_u=sk(F), seg=1.5, band=0.75, kband=(0.66, 0.72), ksill=(0.55, 0.65), lsill=(1.0, 1.5), eave_streaks=False)
    lib.weather(b, "panel", [("y", Y0, -1, X0, X1, 0.0, H)], seed=22, patches=False, skip_u=sk(B), seg=1.5, band=0.75, kband=(0.66, 0.72), ksill=(0.55, 0.65), lsill=(1.0, 1.5), eave_streaks=False)
    lib.weather(b, "panel", [("x", X1, 1, Y0, Y1, 0.0, H), ("x", X0, -1, Y0, Y1, 0.0, H)], seed=23, patches=False, seg=1.5, band=0.75, kband=(0.66, 0.72), eave_streaks=False)
    lib.finish(b, "h5_panel_block", out, tri_limit=2500, footprint=(4, 2), anchor=(0, 0))


def broken_end(b, xc, rnd):
    """Зламаний торець уцілілого корпусу: темне нутро замість цілої стіни, плити перекриттів стирчать на 0.3-0.6 м
    східцями (три шматки по глибині різної довжини), огризки фасадних панелей біля краю."""
    yi0, yi1 = Y0 + 0.05, Y1 - 0.05
    lib._quad(b, [(xc + 0.01, yi0, 0.0), (xc + 0.01, yi1, 0.0), (xc + 0.01, yi1, H), (xc + 0.01, yi0, H)], "interior_burnt", (1.0, 0.0, 0.0))
    for f in range(1, NF + 1):                                                   # рваний край плит: 5 шматків різної довжини й товщини
        cuts = sorted(rnd.uniform(0.1, 0.9) for _ in range(4))
        ys = [yi0] + [yi0 + (yi1 - yi0) * c_ for c_ in cuts] + [yi1]
        for k in range(5):
            ov = rnd.uniform(0.15, 0.6)
            th = rnd.uniform(0.14, 0.22)
            b.box(xc + ov / 2, (ys[k] + ys[k + 1]) / 2, f * FLOOR - th, ov, ys[k + 1] - ys[k], th, "slab_dark", top="slab_dark", rot=rnd.uniform(-0.2, 0.2))
    for (x_, y_, h_) in ((xc + 1.6, -2.0, 3.6), (xc + 2.8, 1.8, 2.2), (xc + 1.2, 3.0, 1.4)):   # огризки колон і перегородок у порожнечі
        b.box(x_, y_, 0.0, 0.35, 0.35, h_, "panel_frag", top="panel_frag", rot=rnd.uniform(-0.3, 0.3))
    for (y, sgn) in ((Y1 - 0.2, 1), (Y0 + 0.2, -1)):                              # огризки фасадного шару: зубці 0.4-1.2 м різної висоти
        for f in range(NF):
            if rnd.random() < 0.35:
                continue
            ln = rnd.uniform(0.4, 1.2)
            hh = rnd.uniform(1.2, FLOOR - 0.2)
            b.box(xc + ln / 2, y, f * FLOOR, ln, 0.4, hh, "panel_frag", top="panel_frag")


def damaged():
    """Обвал східного торця: стіни розрізані східцями на 1-3 поверхи, даху над провалом немає, плити й купа
    лежать у прольоті та перед ним (вид з боку камери: фасад -Y і торець +X)."""
    lib.reset()
    lib.palette(glass="dark")
    b = Builder()
    rnd = random.Random(21)
    xc = 6.0
    F, B = (2, 4), (0, 3)
    body(b, X0, xc, NF, F, B, True)
    # вибиті розкидано, не цілим стовпчиком: над кожним лишається чиста стіна, на якій видно шлейф
    windows(b, X0, xc, NF, F, B, blown={("back", 6, 0), ("back", 4, 0), ("back", 5, 1), ("front", 6, 0), ("front", 5, 1)})
    broken_end(b, xc, rnd)
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
    # прямі збірні панелі по 3 м із двома рівнями зламаного верху і легким відхиленням від виска
    back = [FLOOR, 2 * FLOOR]                                                   # на третину менше стоячих панелей
    east = [2 * FLOOR, FLOOR, 2 * FLOOR]
    front = [FLOOR]
    roots = []
    roots += panel_wall(b, (xc, Y0 + 0.2), (X1, Y0 + 0.2), 0.4, back, "panel_frag", 5, piece=3.0, tilt=0.03, inner=(0.0, 1.0), lips=(FLOOR,), in_mat="panel_in")
    roots += panel_wall(b, (X1 - 0.2, Y0), (X1 - 0.2, Y1), 0.4, east, "panel_frag", 6, piece=3.0, tilt=0.04, inner=(-1.0, 0.0), lips=(FLOOR, 2 * FLOOR), in_mat="panel_in")
    roots += panel_wall(b, (xc, Y1 - 0.2), (xc + 6.0, Y1 - 0.2), 0.4, front, "panel_frag", 7, piece=3.0, tilt=0.03, inner=(0.0, -1.0), lips=(FLOOR,), in_mat="panel_in")
    def wall_h(vals, t):
        return vals[min(len(vals) - 1, max(0, int(t * len(vals))))]
    # вікна лишаються там, де стіна їх досягає; вибиті — з м'якою кіптявою
    for i in (7, 8):
        x = bay_x(i)
        t = (x - xc) / (X1 - xc)
        hb = wall_h(back, t)
        for f in range(3):
            z = f * FLOOR + 0.95
            if hb - 1.4 < z + 1.8:
                continue
            blow = True
            if blow:
                lib.burn_ring(b, "y", Y0, x, z + 0.15, 1.1, 1.1, -1, g_side=0.35, g_bot=0.1, g_top=5.0, ztop=H - 0.05, mat="panel_dm", strong=True)
                lib.plume(b, "y", Y0, -1, x, z + 1.25, 1.1, H - 0.05, "panel_dm")
                opening2(b, "y", Y0, x, z + 0.15, 1.1, 1.1, -1, streak=0.0, sooty=True)
            else:
                b.window(("y", Y0, -1), x, z, 1.4, 1.4)
    for k in range(6):
        yy = -4.2 + 1.6 * k
        t = (yy - Y0) / DEP
        he = wall_h(east, t)
        for f in range(3):
            z = f * FLOOR + 0.95
            if he - 1.4 < z + 1.8 or rnd.random() < 0.4 or (f == 0 and k % 2):          # у нижньому ряду не частіше кожного другого прорізу
                continue
            lib.burn_ring(b, "x", X1, yy, z + 0.15, 1.1, 1.1, 1, g_side=0.35, g_bot=0.1, g_top=5.0, ztop=H - 0.05, mat="panel_dm", strong=True)
            lib.plume(b, "x", X1, 1, yy, z + 1.25, 1.1, H - 0.05, "panel_dm")
            opening2(b, "x", X1, yy, z + 0.15, 1.1, 1.1, 1, streak=0.0, sooty=True)
    # плити перекриттів, що лишились кронштейнами від стін, і розколота плита даху
    for (x, y, z, sx, sy, ax, ay, az) in ((9.0, -4.0, 2.9, 3.6, 1.8, 0.35, 0.0, 0.0), (13.5, -3.6, 5.9, 2.6, 2.0, 0.38, 0.0, 0.1), (8.0, 4.0, 2.9, 2.4, 1.6, -0.3, 0.0, 0.0)):
        chip_slab(b, x, y, z, sx, sy, 0.22, (ax, ay, az), "slab_dark", "slab_dark", int(x * 10 + y))
    # плити перекриттів 2-го й 3-го поверхів висять із зрізу стіни, провиснувши до купи: видно підлогу, а не порожню коробку
    chip_slab(b, xc + 2.0, 0.3, FLOOR - 0.15, 4.0, 6.6, 0.25, (0.0, 0.16, 0.0), "slab_dark", "slab_dark", 301)
    chip_slab(b, xc + 1.4, -0.4, 2 * FLOOR - 0.15, 2.8, 6.0, 0.25, (0.0, 0.24, 0.05), "slab_dark", "slab_dark", 302)
    # розколота плита даху лежить у прольоті під кутами 20-50° на купі
    for (x, y, z, sx, sy, ax, ay, az) in ((9.2, -0.5, 3.4, 3.2, 2.8, 0.38, 0.1, 0.2), (12.4, 1.6, 4.4, 3.4, 2.4, -0.4, 0.2, -0.4), (10.6, 2.8, 2.8, 2.8, 2.2, 0.3, -0.3, 0.6), (13.8, -1.8, 3.8, 2.6, 2.4, -0.35, -0.25, 1.1)):
        chip_slab(b, x, y, z, sx, sy, 0.34, (ax, ay, az), "slab_dark", "bitumen", int(x * 10 + y) + 5, per_edge=2)
    # арматура темна, іржава: кожен стрижень виходить із верху панелі
    for k, (rx_, ry_, rz_) in enumerate(roots):
        if k % 2:
            continue
        b.beam((rx_, ry_, rz_ - 0.1), (rx_ + rnd.uniform(-0.5, 0.5), ry_ + rnd.uniform(-0.5, 0.5), rz_ + rnd.uniform(0.6, 1.2)), 0.09, "rebar")
    # одна безперервна купа: плавна поверхня без радіальних зломів (парабола, горби, западина), контур із 5-7 опуклостей і заокругленою
    # губою; деталь — бетонні уламки 0.3-0.9 м на темній основі — запікається зі скан-джерела разом з AO
    bh = Builder()
    # край купи сходить у землю (feather), без бортика; перехід у колір ґрунту — спідницею 1.5 м
    plan = [HeapSurface(11.0, 0.5, 4.8, 4.6, 4.3, 61, bumps=6, lip=0.0, wob=0.45, lump=0.25, hummocks=6, hum_amp=0.9, pw=1.35, noise=1.0, feather=1.5),
            HeapSurface(12.8, -5.0, 4.6, 2.2, 2.0, 62, bumps=5, lip=0.0, wob=0.2, lump=0.12, hummocks=3, hum_amp=0.4, pw=1.5, noise=1.0, feather=1.2),
            HeapSurface(16.2, -1.5, 2.6, 5.0, 1.7, 63, bumps=7, lip=0.0, wob=0.35, lump=0.3, hummocks=6, hum_amp=0.9, pw=1.5, noise=1.5, feather=1.2)]   # правий горб не гладкий купол
    plan[0].fit_peak(2.6)                                                       # нижча купа: на крутих боках проєкція зверху тягнулась смугами
    print("HEAPPEAK h5", [round(max(h_.z(h_.cx + h_.rx * u / 20.0, h_.cy + h_.ry * v / 20.0) for u in range(-20, 21) for v in range(-20, 21)), 2) for h_ in plan], "s", round(plan[0].s, 3))
    for k, hsf in enumerate(plan):
        big = k == 0
        heap_mound(b, hsf, "heap_grey", rings=5 if big else 3, segs=24 if big else 14, skirt=0.05)      # без спідниці: запечений колір ґрунту давав світле кільце; край сам сходить у землю
        heap_mound(bh, hsf, "heap_base_grey", rings=18 if big else 8, segs=110 if big else 56, jitter=0.1 * hsf.hmax / 4.0, seed=61 + k)
    hrnd = random.Random(99)
    for hsf in plan:
        n = int(math.pi * hsf.rx * hsf.ry * 22.0)                                    # дрібний щебінь 10-40 см (лише в запіканні)
        for _ in range(n):
            a_ = hrnd.uniform(0, 2 * math.pi)
            t = math.sqrt(hrnd.uniform(0, 1.0)) * 1.1
            r = t * hsf.radius(a_)
            px, py = hsf.cx + hsf.rx * r * math.cos(a_), hsf.cy + hsf.ry * r * math.sin(a_)
            z = hsf.z(px, py) if t < 1.0 else hsf.lip * max(0.0, 1.0 - (t - 1.0) / 0.12) * 0.8
            q = hrnd.random()
            size = hrnd.uniform(0.1, 0.25) if q < 0.7 else (hrnd.uniform(0.25, 0.4) if q < 0.97 else hrnd.uniform(0.4, 0.7))
            bh.rock(px, py, z + 0.02, size, "heap_grey", hrnd, buried=0.3)
    def surf(x, y):
        return max(h_.z(x, y) for h_ in plan)
    for k in range(5):                                                           # справжні шматки, що ламають силует
        px, py = rnd.uniform(14.5, 19.0), rnd.uniform(-7.5, 4.0)
        b.rock(px, py, 0.4, rnd.uniform(0.6, 1.1), "heap_grey", rnd, buried=0.45)
    for k in range(7):                                                           # арматура стирчить із купи пучками
        px, py = rnd.uniform(8.0, 15.0), rnd.uniform(-3.0, 4.0)
        z0_ = surf(px, py)
        b.beam((px, py, z0_ - 0.1), (px + rnd.uniform(-0.6, 0.6), py + rnd.uniform(-0.6, 0.6), z0_ + rnd.uniform(0.5, 1.1)), 0.06, "rebar")
    for k in range(4):                                                           # уламки панелей товщиною 0.3 м, наполовину в купі
        px, py = rnd.uniform(14.8, 18.5), rnd.uniform(-6.5, 3.0)
        chip_slab(b, px, py, max(0.45, surf(px, py) * 0.7), rnd.uniform(1.4, 2.0), rnd.uniform(1.0, 1.5), 0.3, (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0, 3.1)), "slab_dark", "slab_dark", 400 + k, rebar=1, per_edge=2)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4600, footprint=(5, 2), anchor=(0, 0), hi=bh, ground_clip=True, ao=0.45)


intact()
damaged()
