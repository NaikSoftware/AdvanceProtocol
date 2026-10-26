"""H5: панельна триповерхівка 30 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from mathutils import Vector, Matrix
import bmesh
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


def body(b, xa, xb, nf, front, back, roof, core_end=None, ends=None):
    """Секція будинку: серцевина, фасадні шари з прорізами-лоджіями, вікна на сітці."""
    top_z = nf * FLOOR
    ends = ends or (xb,) * nf                      # де обривається фасадний шар на кожному поверсі
    ce = xb if core_end is None else core_end      # де обривається серцевина (далі — порожнина кімнат)
    b.box((xa + ce) / 2, 0, 0, ce - xa, DEP - 2 * LOG, top_z, "panel", top="bitumen" if roof else "panel_scorched")
    for (ya, yb, cols, side) in ((Y1 - LOG, Y1, front, 1), (Y0, Y0 + LOG, back, -1)):
        yc = (ya + yb) / 2
        for f in range(nf):
            z0 = f * FLOOR
            use = cols if f >= 1 else ()
            for (a, c) in intervals(xa, ends[f], [i for i in use if xa <= bay_x(i) <= ends[f]]):
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
                    b.box(x + sx * (LW - 0.03), (ya + yb) / 2, z, 0.06, LOG, FLOOR - 0.15, "panel_light")   # впритул до шару фасаду: щілина 5 мм давала чорні крапки по краю лоджії
                if (i * 7 + f * 3 + (1 if side > 0 else 0)) % 2 == 0:                       # засклена лоджія: рама над парапетом
                    b.window(("y", ye - 0.08 * side, side), x, z + 1.15, 2 * LW - 0.06, FLOOR - 1.4)
            if nf > 2:
                b.box(x, (ya + yb) / 2, 2 * FLOOR - 0.15, 2 * LW, LOG, 0.15, "panel", top="panel")  # плита між лоджіями
                b.box(x, (ya + yb) / 2, top_z - 0.2, 2 * LW, LOG, 0.2, "panel", top="bitumen" if roof else "panel")


def windows(b, xa, xb, nf, front, back, blown=(), ends=None):
    """Сувора сітка: одне вікно на панель, однакового розміру; лоджійні вікна в глибині ніші."""
    for side, (y, sgn, cols) in (("front", (Y1, 1, front)), ("back", (Y0, -1, back))):
        for i in range(10):
            x = bay_x(i)
            if not (xa <= x <= xb):
                continue
            for f in range(nf):
                if i in STAIRS and f == 0 and side == "front":
                    continue
                if ends and x + 0.85 > ends[f]:
                    continue                                                      # фасад на цьому поверсі вже обвалився
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




# --------------------------------------------------------------------------- пошкоджений варіант

XC = 6.0                              # лінія обвалу східного торця
CORE_END = 0.0                        # серцевина закінчується тут; далі до XC — відкриті кімнати
YI = DEP / 2 - LOG                    # внутрішня півширина кімнат (між фасадними шарами)
ENDS = (6.0, 5.4, 3.3)                # де обривається фасадний шар на 1-му, 2-му, 3-му поверсі
SLAB_END = {1: XC + 0.4, 2: XC - 0.2, 3: 2.3}   # де обриваються перекриття (3 — плита даху, зрізана на 1-1.4 м назад від фасаду)
SLAB_TH = 0.22
PARTS = ((1.4, 3.6), (1.4, 3.2, 4.9), (1.4, 2.8))   # перегородки по кімнатах знизу вгору
MOUND = dict(hx=XC + 3.2, hy=-0.3, rx=5.8, ry=5.0, hmax=2.4)
CAV_LIN = 0.13                        # середнє альбедо стін кімнат (лінійне): під небом Річки дає на екрані sRGB ~70 (було 32), не чорне

CHECKS = {"sags": [], "protr": [], "slab_max": {}, "bundles": [], "lean": [], "slabs": [], "boulders": [], "rods": [], "heap_verts": [], "stubs": [], "partitions": {}, "ceilings": 0, "furniture": 0}


def _v3(*a):
    return Vector(a)


def rod(b, pts, r=0.01):
    """Прут арматури: тригранна призма вздовж ламаної, із торцями (замкнена, щоб нормалі йшли назовні). r — радіус описаного кола."""
    rings = []
    for i, p in enumerate(pts):
        d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(a).normalized()
        v = d.cross(u).normalized()
        rings.append([b.bm.verts.new(Vector(p) + (u * math.cos(t) + v * math.sin(t)) * r) for t in (0.0, 2.0944, 4.1888)])
    fs = [b.bm.faces.new((rings[i][k], rings[i][(k + 1) % 3], rings[i + 1][(k + 1) % 3], rings[i + 1][k])) for i in range(len(rings) - 1) for k in range(3)]
    fs += [b.bm.faces.new(rings[0][::-1]), b.bm.faces.new(rings[-1])]
    b._finish(fs, "rebar")
    for i in range(len(pts) - 1):
        CHECKS["rods"].append((2 * r, Vector(pts[i + 1]) - Vector(pts[i])))


def bundle(b, e, o, rnd, tang, n=3):
    """Пучок із n прутів 1-2 см із зламу: виходить уздовж o і загинається донизу під власною вагою."""
    o = Vector(o).normalized()
    for k in range(n):
        p0 = Vector(e) + Vector(tang) * (k - (n - 1) / 2) * 0.025 - o * 0.06
        l1, l2 = rnd.uniform(0.45, 0.8), rnd.uniform(0.3, 0.5)
        p1 = p0 + o * l1
        p2 = p1 + (o * 0.8 + Vector((0, 0, -0.6))).normalized() * l2
        rod(b, [p0, p1, p2], r=rnd.uniform(0.0055, 0.0095))
    CHECKS["bundles"].append((n - 1) * 0.025 + 2 * 0.0095)           # ширина пучка: 3 прути впритул, 5-8 см


def _wob(x, y, ph):
    """Шум без радіальної симетрії: три плоскі хвилі під різними кутами."""
    return (math.sin(0.9 * x + 1.3 * y + ph[0]) + 0.6 * math.sin(1.7 * x - 0.8 * y + ph[1]) + 0.5 * math.sin(0.5 * x + 2.1 * y + ph[2])) / 2.1


class Mound:
    """Низька основа з дрібної фракції: нерівномірна сітка з шумом, а не радіальні промені."""
    def __init__(self, hx, hy, rx, ry, hmax, rnd):
        self.hx, self.hy, self.rx, self.ry, self.hmax = hx, hy, rx, ry, hmax
        self.ph = [rnd.uniform(0, 6.28) for _ in range(3)]
        self.hum = [(hx + rnd.uniform(-0.6, 0.6) * rx, hy + rnd.uniform(-0.6, 0.6) * ry, rnd.uniform(0.3, 0.7)) for _ in range(4)]   # горби: купа не гладкий пагорб

    def h(self, x, y):
        e = math.hypot((x - self.hx) / self.rx, (y - self.hy) / self.ry)
        if e >= 1.0:
            return 0.0
        hum = sum(a * math.exp(-((x - px) ** 2 + (y - py) ** 2) / (2 * 1.3 ** 2)) for px, py, a in self.hum)
        return max(0.0, (self.hmax * (1 - e) ** 0.8 * (1 + 0.3 * _wob(x, y, self.ph)) + hum * (1 - e)))

    def build(self, b, rnd, nx=10, ny=9, mat="heap_grey"):
        xs = [self.hx - self.rx + 2 * self.rx * i / (nx - 1) for i in range(nx)]
        ys = [self.hy - self.ry + 2 * self.ry * j / (ny - 1) for j in range(ny)]
        vs = {}
        for i in range(nx):
            for j in range(ny):
                x = xs[i] + (rnd.uniform(-0.3, 0.3) * 2 * self.rx / (nx - 1) if 0 < i < nx - 1 else 0.0)
                y = ys[j] + (rnd.uniform(-0.3, 0.3) * 2 * self.ry / (ny - 1) if 0 < j < ny - 1 else 0.0)
                vs[i, j] = b.bm.verts.new((x, y, self.h(x, y)))
        fs = []
        for i in range(nx - 1):
            for j in range(ny - 1):
                q = [vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]]
                if all(v.co.z < 0.01 for v in q):
                    continue
                if rnd.random() < 0.5:
                    q = q[1:] + q[:1]
                fs += [b.bm.faces.new((q[0], q[1], q[2])), b.bm.faces.new((q[0], q[2], q[3]))]
        for f in fs:
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
        b._finish(fs, mat)


def piece(rnd, L, W):
    """Контур уламка плити в площині (s, t): прямокутник L x W із підсунутими кутами й 1-2 зрізаними кутами; без тонких голок."""
    c = [(-L / 2, -W / 2), (L / 2, -W / 2), (L / 2, W / 2), (-L / 2, W / 2)]
    c = [(x * rnd.uniform(0.9, 1.0), y * rnd.uniform(0.9, 1.0)) for x, y in c]
    cut = rnd.sample(range(4), rnd.choice((1, 2)))
    pts = []
    for i, p in enumerate(c):
        if i in cut:
            a, d = c[i - 1], c[(i + 1) % 4]
            for q, k in ((a, rnd.uniform(0.2, 0.34)), (d, rnd.uniform(0.2, 0.34))):
                pts.append((p[0] + (q[0] - p[0]) * k, p[1] + (q[1] - p[1]) * k))
        else:
            pts.append(p)
    # порядок: для зрізаного кута точки йдуть від попередньої сусідки до наступної
    return pts


def place_slab(b, pts, th, C, s, t, n, mat="slab_dark_dm", top="slab_dark_dm", heap=True, kind="slab"):
    """Плита-уламок: контур pts у площині (s, t), низ у точці C, нормаль n. Повертає верхню грань і вершини для вимірів."""
    rot = Matrix((s, t, n)).transposed()
    P = Vector(C)
    top_v = [b.bm.verts.new(rot @ Vector((x, y, th)) + P) for (x, y) in pts]
    bot_v = [b.bm.verts.new(rot @ Vector((x, y, 0.0)) + P) for (x, y) in pts]
    k = len(pts)
    if lib._signed(pts) < 0:
        top_v, bot_v = top_v[::-1], bot_v[::-1]
    ft = b.bm.faces.new(top_v)
    sides = [b.bm.faces.new((top_v[(i + 1) % k], top_v[i], bot_v[i], bot_v[(i + 1) % k])) for i in range(k)]
    b._finish([ft], top)
    b._finish(sides, mat)
    tn = b.rnd.uniform(0.85, 1.15)                                   # тон кожної плити свій: ±15 %
    for f in [ft] + sides:
        for lp in f.loops:
            lp[b.wtone] = (tn, tn, tn, 1.0)
    rec = dict(ft=ft, top=top_v, bot=bot_v, pts=pts, heap=heap)
    CHECKS["sags" if kind == "sag" else "slabs"].append(rec)
    return ft, rot


def slab_frame(yaw, theta):
    """Базис плити, що спускається в напрямку yaw з нахилом theta: s — вниз по схилу, t — вздовж горизонтального ребра, n — вгору."""
    d = _v3(math.cos(yaw), math.sin(yaw), 0)
    th = math.radians(theta)
    s = _v3(d.x * math.cos(th), d.y * math.cos(th), -math.sin(th))
    t = _v3(-d.y, d.x, 0)
    n = _v3(d.x * math.sin(th), d.y * math.sin(th), math.cos(th))
    return d, s, t, n


def edge_bundle(b, rnd, pts, th, C, rot, k=None):
    """Арматура з рваного краю плити: ребро обираємо те, що не дивиться стрімко вгору."""
    cand = []
    m = len(pts)
    for i in range(m):
        p, q = pts[i], pts[(i + 1) % m]
        if math.hypot(q[0] - p[0], q[1] - p[1]) < 0.6:
            continue
        mid = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
        ex, ey = q[0] - p[0], q[1] - p[1]
        ln = math.hypot(ex, ey)
        o2 = (ey / ln, -ex / ln)                                   # зовнішня нормаль ребра (контур проти годинникової)
        if lib._signed(pts) < 0:
            o2 = (-o2[0], -o2[1])
        o = rot @ Vector((o2[0], o2[1], 0))
        if abs(o.z) <= 0.45:
            cand.append((mid, o, rot @ Vector((ex / ln, ey / ln, 0))))
    if not cand:
        return
    mid, o, tg = rnd.choice(cand)
    e = rot @ Vector((mid[0], mid[1], th / 2)) + Vector(C)
    bundle(b, e, o, rnd, tg)


def boulder(b, rnd, c, dims, mat, yaw, spacer=False):
    """Брила бетону: перекошений паралелепіпед із власними розмірами (всі виміри 0.3-1 м), без голок."""
    from mathutils import Euler
    r = bmesh.ops.create_cube(b.bm, size=1.0)
    verts = r["verts"]
    rot = Euler((rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), yaw)).to_matrix()
    for v in verts:
        p = Vector((v.co.x * dims[0] * (1 + rnd.uniform(-0.1, 0.1)), v.co.y * dims[1] * (1 + rnd.uniform(-0.1, 0.1)), v.co.z * dims[2] * (1 + rnd.uniform(-0.1, 0.1))))
        v.co = rot @ p + Vector(c)
    faces = list({f for v in verts for f in v.link_faces})
    b._finish(faces, mat)
    tn = rnd.uniform(0.7, 1.1)
    for f in faces:
        for lp in f.loops:
            lp[b.wtone] = (tn, tn, tn, 1.0)
    CHECKS["boulders"].append((verts, rot, dims))


def stack_build(b, rnd, mound, U, yaw, theta, L, W, n_sl, mat="slab_dark_dm", rebar=1, tag=None):
    """Стос із n_sl паралельних плит «бутербродом»: між ними щілини 0.28-0.4 м із бриллю-розпоркою. U — центр верхнього ребра
    нижньої плити, плити спускаються від U за напрямком yaw. Повертає нижню точку ребра."""
    d, s, t, n = slab_frame(yaw, theta)
    off = 0.0
    for i in range(n_sl):
        th = rnd.uniform(0.15, 0.2)
        pts = piece(rnd, L * rnd.uniform(0.85, 1.0), W * rnd.uniform(0.85, 1.0))
        shift = s * rnd.uniform(-0.3, 0.3) + t * rnd.uniform(-0.3, 0.3)
        C = Vector(U) + s * (L / 2) + n * off + shift
        ft, rot = place_slab(b, pts, th, C, s, t, n, mat, mat)
        if tag is not None:
            CHECKS[tag].append(CHECKS["slabs"][-1])
        if i < n_sl - 1:                                           # дрібна фракція в щілині: розсип на верхній плиті
            q = [C + n * (th + 0.03) + s * (a_ * L * 0.3) + t * (c_ * W * 0.3) for a_, c_ in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            lib._quad(b, [tuple(v) for v in q], "heap_grey", tuple(n))
        if rnd.random() < 0.2 and rebar:
            edge_bundle(b, rnd, pts, th, C, rot)
        gap = rnd.uniform(0.45, 0.75)
        if i < n_sl - 1:                                           # розпірка між плитами тримає порожнину
            sp = C + s * rnd.uniform(-0.4, 0.4) + t * rnd.uniform(-0.5, 0.5) + n * (th + gap / 2)
            boulder(b, rnd, sp, (gap + 0.04, rnd.uniform(0.36, 0.5), rnd.uniform(0.36, 0.45)), "chunk_concrete", rnd.uniform(0, 6.28))
        off += th + gap
    return Vector(U) + s * L


def tent(b, rnd, mound, R, yaw, L, thA, nsl):
    """Дві плити-стоси сходяться верхніми ребрами: «намет» над порожниною. Нахил другого боку підбирається так, щоб обидва нижні краї
    сідали в основу купи на одній висоті гребеня."""
    d = _v3(math.cos(yaw), math.sin(yaw), 0)
    a = math.radians(thA)
    cap = 3.85 - 0.6 * (nsl - 1)                                   # гребінь не вище за межу купи з урахуванням верхніх плит стосу
    while True:
        zr = mound.h(R[0] + d.x * L * math.cos(a), R[1] + d.y * L * math.cos(a)) - 0.2 + L * math.sin(a)
        if zr <= cap or L < 1.6:
            break
        L *= 0.94
    best = None
    for deg in range(32, 67):
        r_ = math.radians(deg)
        err = abs(mound.h(R[0] - d.x * L * math.cos(r_), R[1] - d.y * L * math.cos(r_)) - 0.2 + L * math.sin(r_) - zr)
        if best is None or err < best[0]:
            best = (err, deg)
    U = _v3(R[0], R[1], zr)
    stack_build(b, rnd, mound, U, yaw, thA, L, 2.3, nsl)
    stack_build(b, rnd, mound, U, yaw + math.pi, best[1], L, 2.3, nsl)
    return zr


def wall_bands(b, a, c, z0, z1, nrm, mat="interior_wall_dm"):
    """Стіна кімнати трьома смугами з тоном у вершинах: низ темніший, середина світла, верхня третина закопчена."""
    rows = [(z0, 0.55), (z0 + (z1 - z0) * 0.33, 1.0), (z0 + (z1 - z0) * 0.67, 0.85), (z1, 0.3)]
    for (za, ta), (zb, tb) in zip(rows, rows[1:]):
        b.decal([(a[0], a[1], za), (c[0], c[1], za), (c[0], c[1], zb), (a[0], a[1], zb)], [ta, ta, tb, tb], mat, nrm)


def breach(b, rnd):
    """Відкриті кімнати на зламі: три поверхи, у кожному 2-3 перегородки, перекриття завтовшки не менше 0.2 м із рваним торцем
    (верхнє провисає), плита даху зрізана назад, штукатурка зі стійками й затіканнями, закопчена верхня третина стін."""
    ysag0, wsag = -YI + 0.35, 3.6
    for k in (1, 2, 3):                                            # перекриття k: низ на k*FLOOR - товщина
        xe = SLAB_END[k]
        z_top = k * FLOOR
        before_k = set(b.bm.verts)
        top = "bitumen" if k == 3 else "interior_floor"
        b.box((CORE_END + xe - 0.7) / 2, 0, z_top - SLAB_TH, xe - 0.7 - CORE_END, 2 * YI, SLAB_TH, "broken_end", top=top)
        y_from = ysag0 + wsag + 0.1 if k == 2 else -YI                # під провислим шматком торця немає
        cuts = sorted(rnd.uniform(0.15, 0.85) for _ in range(2 if k == 2 else 4))
        ys = [y_from] + [y_from + (YI - y_from) * c_ for c_ in cuts] + [YI]
        mx = 0.0
        for i in range(len(ys) - 1):                               # рваний торець: зубці різної довжини, кожен ≥ 0.2 м завтовшки
            ov = rnd.uniform(0.3, 0.7 if k == 3 else 1.0)
            th = rnd.uniform(SLAB_TH, 0.27)
            b.box(xe - 0.7 + ov / 2, (ys[i] + ys[i + 1]) / 2, z_top - th, ov, ys[i + 1] - ys[i] + 0.02, th, "broken_end", top=top)
            CHECKS["stubs"].append(th)
            mx = max(mx, xe - 0.7 + ov)
            if rnd.random() < 0.4:
                bundle(b, _v3(xe - 0.7 + ov, (ys[i] + ys[i + 1]) / 2, z_top - th / 2), (1, 0, 0), rnd, (0, 1, 0))
        CHECKS["slab_max"][k] = mx
        if k == 2:                                                 # верхнє перекриття кімнат провисло: шматок звисає з краю на 1-2 м
            d, s_, t_, n_ = slab_frame(0.0, 18.0)
            Ls, th = 1.95, 0.22
            pts = piece(rnd, Ls, wsag)
            hinge = _v3(xe - 0.7 - 0.15, ysag0 + wsag / 2, z_top)
            C = hinge - n_ * th + s_ * (Ls / 2)
            ft, rot = place_slab(b, pts, th, C, s_, t_, n_, "broken_end", "interior_floor", heap=False, kind="sag")
            edge_bundle(b, rnd, pts, th, C, rot)
            CHECKS["sags"][-1]["hinge_x"] = xe - 0.7
        # стеля: темна, але камера її майже не бачить; основна кіптява — на верхній третині стін
        zc = z_top - SLAB_TH
        f = lib._quad(b, [(CORE_END, -YI, zc - 0.03), (xe - 0.7, -YI, zc - 0.03), (xe - 0.7, YI, zc - 0.03), (CORE_END, YI, zc - 0.03)], "soot_v", (0, 0, -1))
        for lp in f.loops:
            lp[b.wtone] = (0.02, 0.02, 0.02, 1.0)
        CHECKS["ceilings"] += 1
        if k == 3:
            rs_ = b._slot("rebar")
            CHECKS["roof_verts"] = [v for v in b.bm.verts if v not in before_k and any(f.material_index != rs_ for f in v.link_faces)]   # без прутів арматури
        if k < 3:                                                  # кіптява на підлозі біля зламу: темнішає до краю
            xa_ = xe - 3.2
            b.decal([(xa_, -YI + 0.05, z_top + 0.03), (xe - 0.7, -YI + 0.05, z_top + 0.03), (xe - 0.7, YI - 0.05, z_top + 0.03), (xa_, YI - 0.05, z_top + 0.03)], [1.0, 0.6, 0.6, 1.0], "interior_floor_dm", (0, 0, 1))
            CHECKS["floor_soot"] = CHECKS.get("floor_soot", 0) + 1
    OFF = 0.05                                                     # внутрішні стіни зсунуті від граней фасадних шарів, щоб не було z-fighting
    for f in range(NF):                                            # кімнати
        zf, zc = (f * FLOOR + 0.03 if f else 0.03), (f + 1) * FLOOR - SLAB_TH - 0.03
        for sgn in (-1, 1):
            wall_bands(b, (CORE_END + OFF, sgn * (YI - OFF)), (ENDS[f] - 0.02, sgn * (YI - OFF)), zf, zc, (0, -sgn, 0))
        wall_bands(b, (CORE_END + OFF, -YI + OFF), (CORE_END + OFF, YI - OFF), zf, zc, (1, 0, 0))
        zp0 = zf - 0.03
        CHECKS["partitions"][f] = len(PARTS[f])
        for k, px in enumerate(PARTS[f]):
            h = (zc + 0.03) - zp0 - (0.0 if k == 0 else rnd.uniform(0.0, 1.1) if px > 3.0 else 0.0)   # дальні від залу обламані нижче
            dc = rnd.uniform(-2.5, 2.5)                                                              # проріз дверей 0.9 м
            for (ya, yb) in ((-YI + 0.02, dc - 0.45), (dc + 0.45, YI - 0.02)):
                b.box(px, (ya + yb) / 2, zp0, 0.14, yb - ya, h, "interior_wall", top="interior_wall")
    # меблі й уламки в кімнатах 2-го й 3-го поверхів
    b.box_e(2.1, -3.5, FLOOR + 0.45, 1.8, 0.55, 0.5, "timber_dark", euler=(0.0, 0.0, 0.25), top="timber_dark")
    b.box(3.9, 2.8, FLOOR, 1.9, 0.9, 0.35, "timber_dark", rot=0.4)
    b.box_e(2.0, 2.2, 2 * FLOOR + 0.35, 1.1, 0.7, 0.08, "timber_dark", euler=(0.12, 0.0, 0.3))
    b.box(2.0, 2.2, 2 * FLOOR, 0.06, 0.06, 0.34, "timber_dark")
    d, s, t, n = slab_frame(0.0, 42.0)                              # плита, що впала на перегородку в кімнаті 2-го поверху
    ft, rot = place_slab(b, piece(rnd, 1.7, 1.3), 0.17, _v3(4.0, -1.0, FLOOR + 0.1), s, t, n, "slab_dark_dm", "slab_dark_dm", heap=False)
    CHECKS["furniture"] = 4


def facade_breaks(b, rnd):
    """Зламаний зріз фасадних панелей: на кожному зрізі 3-5 виступів 0.3-0.8 м різної висоти, а сам торець зі рваним бетоном."""
    for f in range(NF):
        for sgn in (-1, 1):
            y0, y1 = sorted((sgn * YI, sgn * (YI + LOG)))
            lib._quad(b, [(ENDS[f] + 0.004, y0, f * FLOOR), (ENDS[f] + 0.004, y1, f * FLOOR), (ENDS[f] + 0.004, y1, (f + 1) * FLOOR), (ENDS[f] + 0.004, y0, (f + 1) * FLOOR)], "broken_end", (1, 0, 0))
            cnt = rnd.randint(3, 5)
            zs = sorted(rnd.uniform(0.0, FLOOR - 0.6) for _ in range(cnt))
            got = []
            for z0 in zs:
                before = set(b.bm.verts)
                ln, hh, yw = rnd.uniform(0.38, 0.7), rnd.uniform(0.45, 1.1), rnd.uniform(0.45, 0.8)
                yc = rnd.uniform(y0 + yw / 2, y1 - yw / 2)
                b.box(ENDS[f] + ln / 2 - 0.02, yc, f * FLOOR + z0, ln, yw, hh, "broken_end", top="broken_end", rot=rnd.uniform(-0.1, 0.1))
                got.append(max(v.co.x for v in b.bm.verts if v not in before) - ENDS[f])
            CHECKS["protr"].append(got)


def dust_ring(b, mound, rnd, n=30, width=0.9):
    """Смуга дрібняку 0.9 м навколо насипу з хвилястим зовнішнім краєм: купа не обривається по лінії, а розтікається по ґрунту."""
    ring = []
    for i in range(n + 1):
        a = 2 * math.pi * (i % n) / n
        ca, sa = math.cos(a), math.sin(a)
        wob = 1 + 0.06 * _wob(ca * 3, sa * 3, mound.ph)
        pin = (mound.hx + mound.rx * 0.97 * wob * ca, mound.hy + mound.ry * 0.97 * wob * sa)
        pout = (mound.hx + (mound.rx * wob + width) * ca, mound.hy + (mound.ry * wob + width) * sa)
        ring.append((pin, pout))
    for (a_in, a_out), (b_in, b_out) in zip(ring, ring[1:]):
        lib._quad(b, [(a_in[0], a_in[1], 0.07), (a_out[0], a_out[1], 0.04), (b_out[0], b_out[1], 0.04), (b_in[0], b_in[1], 0.07)], "heap_grey", (0, 0, 1))   # той самий дрібняк, що й на насипі
    CHECKS["ring"] = width


def damaged():
    """Обвал східного торця: стіни різані східцями на три поверхи, всередині відкриті кімнати, а завал лежить на землі купою
    плит під нахилом 30-70°, що спираються одна на одну з порожнинами між ними."""
    lib.reset()
    lib.palette(glass="dark", trim=0.95)
    M = lib.mats()
    wall = tuple(c * CAV_LIN / 0.13 * 0.17 / 0.66 for c in (1.06, 0.99, 0.86))       # Plaster001 у сірому дає ~0.66; тони смуг (середнє ~0.75) опускають до CAV_LIN
    M["interior_wall"] = lib.make_material("interior_wall", "Plaster001", 1.0, recolor=wall, streak=0.9, streak_xy=2.0, bump=0.006, rough=0.9, rvar=0.25, contrast=3.0,
                                           patch=[((0.05, 0.045, 0.04), 0.3), ((0.2, 0.17, 0.12), 0.2)], patch_scale=0.3)
    M["interior_floor"] = lib.make_material("interior_floor", "Concrete034", 1.5, (0.2, 0.19, 0.175), patch=((0.03, 0.03, 0.03), 0.3), streak=0.3)
    M["broken_end"] = lib.make_material("broken_end", "Concrete034", 1.2, (0.30, 0.285, 0.265), streak=0.5, base_dirt=0.5, bump=0.05, patch=((0.36, 0.15, 0.06), 0.3), patch_scale=0.22)   # рваний бетон з іржею
    lib.FLAT.add("rebar")                                                                   # прути: плоский зразок без AO, інакше тонкі призми запікаються чорними
    M["rebar"] = lib.make_material("rebar", flat=(0.13, 0.075, 0.05))                  # іржава арматура: світліша за чорне, інакше на екрані 0-15
    for nm in ("interior_wall", "interior_floor", "slab_dark"):
        lib._dm(nm)
    b = Builder()
    rnd = random.Random(21)
    F, B = (2, 4), (0, 3)
    body(b, X0, XC, NF, F, B, True, core_end=CORE_END, ends=ENDS)
    windows(b, X0, XC, NF, F, B, blown={("back", 6, 0), ("back", 4, 0), ("back", 5, 1), ("front", 6, 0), ("front", 5, 1)}, ends=ENDS)
    breach(b, rnd)
    facade_breaks(b, rnd)
    entrances(b, XC)
    roof_details(b, 1.4)                                           # димарі й сходова шахта на уламаному даху не лишаються
    # завал
    before = set(b.bm.verts)
    hrnd = random.Random(7)
    mound = Mound(rnd=hrnd, **MOUND)
    mound.build(b, hrnd, nx=16, ny=14)
    dust_ring(b, mound, hrnd)
    zrs = []
    for (R, yaw, L, th_a, nsl) in (((XC + 2.0, -2.4), 1.2, 2.9, 33, 2), ((XC + 3.9, 1.6), -0.35, 3.1, 48, 3), ((XC + 5.6, -1.2), 2.4, 2.7, 34, 2), ((XC + 1.8, 3.0), 0.5, 2.3, 44, 2), ((XC + 4.6, -3.4), 1.9, 2.6, 32, 2), ((XC + 7.0, 1.0), 0.9, 2.5, 45, 2), ((XC + 3.4, -0.6), 2.9, 2.8, 50, 2)):
        zrs.append(tent(b, hrnd, mound, R, yaw, L, th_a, nsl))
    for k in range(11):                                             # поодинокі плити, що притулилися до купи
        x, y = hrnd.uniform(XC + 0.5, XC + 8.0), hrnd.uniform(-4.2, 4.2)
        if mound.h(x, y) < 0.3:
            continue
        yaw, theta, L = hrnd.uniform(0, 6.28), (hrnd.uniform(31, 36) if k % 3 else hrnd.uniform(40, 58)), hrnd.uniform(1.4, 1.9)
        d, s, t, n = slab_frame(yaw, theta)
        lo = _v3(x, y, 0) + d * L * math.cos(math.radians(theta))
        U = _v3(x, y, mound.h(lo.x, lo.y) - 0.2 + L * math.sin(math.radians(theta)))
        stack_build(b, hrnd, mound, U, yaw, theta, L, 1.4, 1)
    # плита спирається на зріз фасадного шару першого поверху: верх на торці, низ на землі
    for ysg in (-1, 1):
        th_f = 55.0
        d_, s_, t_, n_ = slab_frame(0.0, th_f)
        Lf = 2.4
        stack_build(b, hrnd, mound, _v3(ENDS[0] + 0.1, ysg * (YI + LOG / 2 + 0.1), -0.15 + Lf * math.sin(math.radians(th_f))), 0.0, th_f, Lf, 1.5, 1, tag="lean")
    # плита зі зламу другого перекриття сповзла на купу: верх спирається на торець, низ у купі
    for (yy, k) in ((2.4, 1),):
        zt = k * FLOOR
        th_ = 0.2
        yaw, theta = 0.1, 35.0
        d, s, t, n = slab_frame(yaw, theta)
        Ll = 3.4
        pts = [(-Ll / 2, -1.0), (Ll / 2, -1.1), (Ll / 2 - 0.4, 1.0), (-Ll / 2 + 0.2, 1.1)]
        C = _v3(SLAB_END[k] + 0.2, yy, zt - th_ * 0.5) + s * (Ll / 2)
        ft, rot = place_slab(b, pts, th_, C, s, t, n)
        edge_bundle(b, hrnd, pts, th_, C, rot)
    # брили бетону 0.3-1 м на поверхні купи
    for i in range(46):
        for _try in range(20):
            x, y = hrnd.uniform(XC - 0.5, XC + 9.0), hrnd.uniform(-5.0, 5.0)
            if mound.h(x, y) > 0.15 or math.hypot((x - MOUND["hx"]) / MOUND["rx"], (y - MOUND["hy"]) / MOUND["ry"]) < 1.0:
                break
        dims = (hrnd.uniform(0.5, 0.9), hrnd.uniform(0.4, 0.8), hrnd.uniform(0.36, 0.6))
        boulder(b, hrnd, (x, y, mound.h(x, y) + dims[2] * 0.2), dims, hrnd.choice(("chunk_concrete", "chunk_concrete", "panel_frag")), hrnd.uniform(0, 6.28))
    CHECKS["heap_verts"] = [v for v in b.bm.verts if v not in before]
    validate()
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4600, footprint=(5, 2), anchor=(0, 0), ground_clip=True, ao=0.45)


def validate():
    """Кожна вимога до завалу й пролому — перевірка на побудованій геометрії; порушення валить збирання."""
    top = max(v.co.z for v in CHECKS["heap_verts"] if v.is_valid)
    assert 3.0 <= top <= 4.5, f"висота купи {top:.2f} м поза 3-4.5"
    hs = [c for c in CHECKS["slabs"] if c["heap"]]
    for c in CHECKS["slabs"]:
        c["ft"].normal_update()
        ang = math.degrees(math.acos(min(1.0, abs(c["ft"].normal.z))))
        assert 30.0 <= ang <= 70.0, f"нахил плити {ang:.1f}° поза 30-70°"
        c["ang"] = ang
        th = abs((c["top"][0].co - c["bot"][0].co).dot(c["ft"].normal))
        assert 0.14 - 1e-3 <= th <= 0.2 + 1e-3, f"товщина уламка {th:.3f}"
        xs = [(v.co.x, v.co.y, v.co.z) for v in c["top"]]
        # мінімальна ширина в площині: найменша з двох головних осей
        import numpy as np
        a = np.array(xs)
        a = a - a.mean(axis=0)
        ev = np.sqrt(np.maximum(np.linalg.eigvalsh(a.T @ a / len(a)), 0))
        lo, hi_ = ev[1] * 3.46, ev[2] * 3.46                        # ≈ розміри рівномірного прямокутника
        assert lo >= 0.8 and hi_ / lo <= 2.2, f"плита-скалка {lo:.2f} x {hi_:.2f}"
        c["size"] = (lo, hi_)
    exts = []
    for verts, rot, dims in CHECKS["boulders"]:
        loc = [rot.transposed() @ Vector(v.co) for v in verts]
        ext = sorted(max(p[i] for p in loc) - min(p[i] for p in loc) for i in range(3))
        assert 0.3 <= ext[0] and ext[2] <= 1.0, f"брила {ext}"
        assert ext[2] / ext[0] <= 3.4, "брила-голка"
        exts.append(ext)
    for dia, v in CHECKS["rods"]:
        assert 0.01 <= dia <= 0.02, f"діаметр прута {dia}"
        el = math.degrees(math.asin(abs(v.normalized().z)))
        assert el <= 60.0, f"прут стирчить сторч: {el:.0f}°"
    assert min(CHECKS["stubs"]) >= 0.2 and SLAB_TH >= 0.2, "торець перекриття тонший за 0.2 м"
    assert all(2 <= n <= 3 for n in CHECKS["partitions"].values()) and len(CHECKS["partitions"]) == NF, "перегородок має бути 2-3 на кімнату"
    assert CHECKS["ceilings"] == NF and CHECKS["furniture"] >= 3
    est = 255 * (1.055 * (CAV_LIN * 0.47) ** (1 / 2.4) - 0.055)      # 0.47 — зміряно під світлом Річки: альбедо 0.03 дало sRGB 32
    assert 60 <= est <= 80, f"нутро кімнат на екрані під Річкою ~{est:.0f}: ціль 60-80 (було 32)"
    # пролом: провис, зрізи, дах, арматура
    assert len(CHECKS["sags"]) == 1
    sg = CHECKS["sags"][0]
    sg["ft"].normal_update()
    sag_ang = math.degrees(math.acos(abs(sg["ft"].normal.z)))
    sag_over = max(v.co.x for v in sg["top"]) - sg["hinge_x"]
    assert 10.0 <= sag_ang <= 25.0, f"провис {sag_ang:.1f}° поза 10-25°"
    assert 1.0 <= sag_over <= 2.0, f"звис {sag_over:.2f} м поза 1-2 м"
    cut = ENDS[2] - max(v.co.x for v in CHECKS["roof_verts"])
    assert 1.0 <= cut <= 1.5, f"плита даху зрізана на {cut:.2f} м, треба 1-1.5"
    assert len(CHECKS["protr"]) == 2 * NF and all(3 <= len(g) <= 5 and all(0.3 <= x <= 0.8 for x in g) for g in CHECKS["protr"]), f"виступи зрізу фасаду {CHECKS['protr']}"
    assert all(0.05 <= w <= 0.08 for w in CHECKS["bundles"]) and CHECKS["bundles"], "пучок арматури 5-8 см"
    assert len(CHECKS["lean"]) == 2 and all(min(v.co.x for v in c["top"]) <= ENDS[0] + 0.45 for c in CHECKS["lean"]), "плита має спиратися на фасад"
    shallow = sum(1 for c in hs if c["ang"] <= 36.0)
    assert shallow >= 0.25 * len(hs), f"пологих плит {shallow} з {len(hs)}"
    assert CHECKS.get("floor_soot") == 2 and CHECKS["ring"] >= 0.5
    ang = [c["ang"] for c in hs]
    print("MEAS heap_top_m=%.2f slabs=%d tilt_deg=%.1f..%.1f boulders=%d rods=%d stub_th_min=%.3f" % (top, len(CHECKS["slabs"]), min(ang), max(ang), len(CHECKS["boulders"]), len(CHECKS["rods"]), min(CHECKS["stubs"])))
    print("MEAS slab_min_width=%.2f slab_max_len=%.2f boulder_dims_m=%.2f..%.2f" % (min(c["size"][0] for c in CHECKS["slabs"]), max(c["size"][1] for c in CHECKS["slabs"]), min(e[0] for e in exts), max(e[2] for e in exts)))


if os.environ.get("BLOCK_ONLY") != "damaged":
    intact()
damaged()
