"""H5: панельна триповерхівка 30 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from mathutils import Vector
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
                    lib.burn_ring(b, "y", yy, x, z + 0.15, 1.1, 1.1, sgn, g_side=0.35, g_bot=0.1, g_top=0.35, ztop=H - 0.05, mat="panel_dm", strong=True)
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
    lib.palette(glass="dark", trim=0.95)                                         # обрамлення в тон панелі
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
    for (y, sgn) in ((Y1 - 0.2, 1), (Y0 + 0.2, -1)):                              # огризки фасадного шару: зубці 0.4-1.2 м різної висоти
        for f in range(NF):
            if rnd.random() < 0.35:
                continue
            ln = rnd.uniform(0.4, 1.2)
            hh = rnd.uniform(1.2, FLOOR - 0.2)
            b.box(xc + ln / 2, y, f * FLOOR, ln, 0.4, hh, "panel_frag", top="panel_frag")


def pile_drop(b, plan, xc, rnd):
    """Звал уламків: плити перекриттів, даху й фасаду розколоті на 6-15 шматків завтовшки 0.14-0.2 м.
    Шматки падають по одному на карту висот (купа + вже покладені): площину опори підганяють під точки контуру,
    нахил обмежують 30°, а шматок піднімають, доки він не спирається на найвищу точку. Сліди уламку пишуться в карту."""
    import numpy as np
    from mathutils import Matrix
    G, gx0, gy0, nx_, ny_ = 0.2, xc, -10.0, 90, 100
    hf = np.zeros((nx_, ny_))
    for i in range(nx_):
        for j in range(ny_):
            x, y = gx0 + i * G, gy0 + j * G
            hf[i, j] = max(max(h_.z(x, y) for h_ in plan), 0.0)
    def H_(x, y):
        i, j = int(round((x - gx0) / G)), int(round((y - gy0) / G))
        return hf[min(max(i, 0), nx_ - 1), min(max(j, 0), ny_ - 1)]
    slabs = [(6.0, 3.0, 0.2, "slab_dark", "slab_dark", 12), (6.0, 3.0, 0.2, "slab_dark", "slab_dark", 11), (6.0, 3.0, 0.2, "slab_dark", "slab_dark", 13),
             (5.0, 3.0, 0.18, "slab_dark", "bitumen", 10), (5.0, 3.0, 0.18, "slab_dark", "bitumen", 9),
             (3.0, 3.1, 0.16, "slab_dark", "panel_frag", 7), (3.0, 3.1, 0.16, "slab_dark", "panel_frag", 6), (3.0, 3.1, 0.16, "slab_dark", "panel_frag", 8),
             (4.0, 2.4, 0.14, "slab_dark", "slab_dark", 8)]
    pieces = []
    for (sx, sy, th, mat, top, k) in slabs:
        for pts, _ in lib.fracture(sx, sy, k, rnd, step=0.8):
            xs_, ys_ = [p[0] for p in pts], [p[1] for p in pts]
            if lib._area(pts) < 0.25 or min(max(xs_) - min(xs_), max(ys_) - min(ys_)) < 0.35:
                continue                                                         # тріски-голки читаються як сміття, а не бетон
            pieces.append((pts, th, mat, top))
    rnd.shuffle(pieces)
    pieces.sort(key=lambda p: -lib._area(p[0]) * rnd.uniform(0.6, 1.4))           # здебільшого великі спершу, дрібні зверху
    tmax = math.tan(math.radians(30))
    for (pts, th, mat, top) in pieces:
        rad = max(math.hypot(x, y) for x, y in pts)
        cx = min(max(xc + 0.6 + rad, rnd.gauss(11.5, 2.0)), 17.5)
        cy = min(max(rnd.gauss(-0.5, 2.3), Y0 - 2.0), Y1 + 1.0)
        yaw = Matrix.Rotation(rnd.uniform(0, 2 * math.pi), 3, "Z")
        loc = [yaw @ Vector((x, y, 0)) for x, y in pts] + [Vector((0, 0, 0))]
        hs = [H_(cx + v.x, cy + v.y) for v in loc]
        # площина z = a + gx*dx + gy*dy найменшими квадратами
        A = np.array([[1.0, v.x, v.y] for v in loc])
        a, gx, gy = np.linalg.lstsq(A, np.array(hs), rcond=None)[0]
        g = math.hypot(gx, gy)
        if g > tmax:
            gx, gy = gx * tmax / g, gy * tmax / g
        a = max(h - gx * v.x - gy * v.y for h, v in zip(hs, loc)) - rnd.uniform(0.0, 0.05)   # спирається на найвищу опору, трохи вгрузає
        nrm = Vector((-gx, -gy, 1.0)).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(nrm).to_matrix() @ yaw
        lib.shard(b, pts, th, rot, (cx, cy, a), mat, top)
        if rnd.random() < 0.45:                                                  # арматура з рваного краю
            x, y = rnd.choice(pts)
            r = math.hypot(x, y) or 1.0
            p0 = rot @ Vector((x, y, th / 2)) + Vector((cx, cy, a))
            p1 = rot @ Vector((x + x / r * rnd.uniform(0.3, 0.8), y + y / r * rnd.uniform(0.3, 0.8), th / 2 + rnd.uniform(0.0, 0.25))) + Vector((cx, cy, a))
            b.beam(p0, p1, 0.04, "rebar")
        for i in range(nx_):                                                     # карта висот: верх шматка там, де він лежить
            x = gx0 + i * G - cx
            if abs(x) > rad:
                continue
            for j in range(ny_):
                y = gy0 + j * G - cy
                if abs(y) > rad:
                    continue
                q = yaw.transposed() @ Vector((x, y, 0))
                if _inside(pts, q.x, q.y):
                    hf[i, j] = max(hf[i, j], a + gx * x + gy * y + th)


def _inside(poly, x, y):
    c = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i - 1], poly[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def damaged():
    """Обвал східного торця: стіни розрізані східцями на 1-3 поверхи, даху над провалом немає, плити й купа
    лежать у прольоті та перед ним (вид з боку камери: фасад -Y і торець +X)."""
    lib.reset()
    lib.palette(glass="dark", trim=0.95)
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
    # плити перекриттів 2-го й 3-го поверхів висять із зрізу стіни, провиснувши до купи
    chip_slab(b, xc + 2.0, 0.3, FLOOR - 0.15, 4.0, 6.6, 0.25, (0.0, 0.16, 0.0), "slab_dark", "slab_dark", 301)
    chip_slab(b, xc + 1.4, -0.4, 2 * FLOOR - 0.15, 2.8, 6.0, 0.25, (0.0, 0.24, 0.05), "slab_dark", "slab_dark", 302)
    # низька основа з дрібної фракції (щебінь лише в запіканні): не конус, а розсип до 1 м
    bh = Builder()
    plan = [HeapSurface(11.5, 0.0, 5.2, 5.0, 1.0, 61, bumps=6, lip=0.0, wob=0.45, lump=0.25, hummocks=6, hum_amp=0.35, pw=1.6, noise=1.0, feather=1.5),
            HeapSurface(15.5, -3.5, 3.4, 3.0, 0.6, 63, bumps=7, lip=0.0, wob=0.35, lump=0.3, hummocks=4, hum_amp=0.25, pw=1.6, noise=1.5, feather=1.2)]
    for k, hsf in enumerate(plan):
        heap_mound(b, hsf, "heap_grey", rings=4, segs=20, skirt=0.05)
        heap_mound(bh, hsf, "heap_base_grey", rings=14, segs=80, jitter=0.03, seed=61 + k)
    hrnd = random.Random(99)
    for hsf in plan:
        for _ in range(int(math.pi * hsf.rx * hsf.ry * 22.0)):
            a_ = hrnd.uniform(0, 2 * math.pi)
            r = math.sqrt(hrnd.uniform(0, 1.0)) * hsf.radius(a_)
            px, py = hsf.cx + hsf.rx * r * math.cos(a_), hsf.cy + hsf.ry * r * math.sin(a_)
            bh.rock(px, py, hsf.z(px, py) + 0.02, hrnd.uniform(0.06, 0.22), "heap_grey", hrnd, buried=0.3)
    # уламки плит, скинуті на купу по черзі: кожен лягає на те, що вже лежить, нахил не більше 30°
    pile_drop(b, plan, xc, random.Random(7))
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4600, footprint=(5, 2), anchor=(0, 0), hi=bh, ground_clip=True, ao=0.45)


intact()
damaged()
