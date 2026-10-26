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
ENDS = (6.0, 5.4, 3.2)                # де обривається фасадний шар на 1-му, 2-му, 3-му поверсі
SLAB_END = {1: 1.5, 2: 1.0, 3: 1.9}   # де обриваються пласкі перекриття від стіни, що лишилась: обламані за 1-2 м; далі — рампа чи звис
SLAB_TH = 0.22
PARTS = ((1.5, 3.0), (1.5, 3.0, 4.5), (1.5, 3.0))   # перегородки по кімнатах знизу вгору
TONGUE_HW = 3.6                       # висота купи біля стіни, м
HEAP_TOP = 4.3                       # найвища точка плит, м
TONGUE_LEN = 7.6                      # щільна частина виходить від торця на ~7 м
SHELL_PHASE = 4                       # зерно фаз шуму оболонки
CAV_LIN = 0.13                        # середнє альбедо стін кімнат (лінійне): під небом Річки дає на екрані sRGB ~70 (було 32), не чорне

CHECKS = {"ramps": [], "droops": [], "flats": [], "panels": [], "scatter": [], "apron": [], "protr": [], "slab_max": {}, "bundles": [], "lean": [], "slabs": [], "boulders": [], "rods": [], "heap_verts": [], "stubs": [], "partitions": {}, "ceilings": 0, "furniture": 0}


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
    rec["kind"] = kind
    CHECKS[{"ramp": "ramps", "droop": "droops"}.get(kind, "slabs")].append(rec)
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


def wall_bands(b, a, c, z0, z1, nrm, mat="interior_wall_dm"):
    """Стіна кімнати трьома смугами з тоном у вершинах: низ темніший, середина світла, верхня третина закопчена."""
    rows = [(z0, 0.55), (z0 + (z1 - z0) * 0.33, 1.0), (z0 + (z1 - z0) * 0.67, 0.85), (z1, 0.3)]
    for (za, ta), (zb, tb) in zip(rows, rows[1:]):
        b.decal([(a[0], a[1], za), (c[0], c[1], za), (c[0], c[1], zb), (a[0], a[1], zb)], [ta, ta, tb, tb], mat, nrm)


def breach(b, rnd, tg):
    """Відкриті кімнати на зламі: три поверхи, у кожному 2-3 перегородки, перекриття завтовшки не менше 0.2 м із рваним торцем
    (верхнє провисає), плита даху зрізана назад, штукатурка зі стійками й затіканнями, закопчена верхня третина стін."""
    for k in (1, 2, 3):                                            # перекриття k: пласка частина лишається лише біля стіни
        xe = SLAB_END[k]
        z_top = k * FLOOR
        before_k = set(b.bm.verts)
        top = "bitumen" if k == 3 else "interior_floor"
        b.box((CORE_END + xe - 0.7) / 2, 0, z_top - SLAB_TH, xe - 0.7 - CORE_END, 2 * YI, SLAB_TH, "broken_end", top=top)
        cuts = sorted(rnd.uniform(0.15, 0.85) for _ in range(4))
        ys = [-YI] + [-YI + 2 * YI * c_ for c_ in cuts] + [YI]
        mx = 0.0
        for i in range(len(ys) - 1):                               # рваний торець: зубці різної довжини, кожен ≥ 0.2 м завтовшки
            ov = rnd.uniform(0.3, 0.7 if k == 3 else 1.0)
            if k == 3:
                ov = rnd.uniform(0.55, 0.7)
            th = rnd.uniform(SLAB_TH, 0.27)
            b.box(xe - 0.7 + ov / 2, (ys[i] + ys[i + 1]) / 2, z_top - th, ov, ys[i + 1] - ys[i] + 0.02, th, "broken_end", top=top)
            CHECKS["stubs"].append(th)
            mx = max(mx, xe - 0.7 + ov)
            if rnd.random() < 0.4:
                bundle(b, _v3(xe - 0.7 + ov, (ys[i] + ys[i + 1]) / 2, z_top - th / 2), (1, 0, 0), rnd, (0, 1, 0))
        CHECKS["slab_max"][k] = mx
        CHECKS["flats"].append(mx - CORE_END)                      # скільки пласкої плити лишилось від стіни
        zc = z_top - SLAB_TH
        f = lib._quad(b, [(CORE_END, -YI, zc - 0.03), (xe - 0.7, -YI, zc - 0.03), (xe - 0.7, YI, zc - 0.03), (CORE_END, YI, zc - 0.03)], "soot_v", (0, 0, -1))
        for lp in f.loops:
            lp[b.wtone] = (0.02, 0.02, 0.02, 1.0)
        CHECKS["ceilings"] += 1
        if k == 3:
            rs_ = b._slot("rebar")
            CHECKS["roof_verts"] = [v for v in b.bm.verts if v not in before_k and any(f.material_index != rs_ for f in v.link_faces)]   # без прутів арматури
        if k < 3:                                                  # кіптява на лишку підлоги біля зламу
            b.decal([(CORE_END, -YI + 0.05, z_top + 0.03), (xe - 0.7, -YI + 0.05, z_top + 0.03), (xe - 0.7, YI - 0.05, z_top + 0.03), (CORE_END, YI - 0.05, z_top + 0.03)], [1.0, 0.6, 0.6, 1.0], "interior_floor_dm", (0, 0, 1))
            CHECKS["floor_soot"] = CHECKS.get("floor_soot", 0) + 1
    # перекриття 2-го поверху звисає рампою до купи: два шматки панелей по ~3 м, посередині панелі немає
    for (yc, wd, ang) in ((-3.0, 3.1, 31.0), (2.9, 3.3, 36.0)):
        d_, s_, t_, n_ = slab_frame(0.0, ang)
        hinge = _v3(SLAB_END[2] - 0.1, yc, 2 * FLOOR)
        for Lr in [3.0 + 0.1 * q for q in range(0, 60)]:           # довжина, за якої нижній край лягає на купу
            e = hinge + s_ * Lr
            if e.z <= tg.h(e.x, yc) + 0.1:
                break
        th = 0.22
        pts = [(-Lr / 2, -wd / 2), (Lr / 2 - rnd.uniform(0.2, 0.6), -wd / 2), (Lr / 2, -wd / 2 + rnd.uniform(0.5, 1.2)), (Lr / 2 - rnd.uniform(0.1, 0.5), wd / 2), (-Lr / 2, wd / 2)]
        C = hinge - n_ * th + s_ * (Lr / 2)
        ft, rot = place_slab(b, pts, th, C, s_, t_, n_, "broken_end", "interior_floor", heap=False, kind="ramp")
        CHECKS["ramps"][-1]["len"] = Lr
        edge_bundle(b, rnd, pts, th, C, rot)
    # покрівля звисає з краю даху
    d_, s_, t_, n_ = slab_frame(0.0, 22.0)
    Ld = 1.9
    hinge = _v3(SLAB_END[3] - 0.1, 1.6, H)
    pts = [(-Ld / 2, -1.8), (Ld / 2, -1.8 + rnd.uniform(0.2, 0.6)), (Ld / 2 - rnd.uniform(0.2, 0.5), 1.8), (-Ld / 2, 1.8)]
    C = hinge - n_ * 0.25 + s_ * (Ld / 2)
    ft, rot = place_slab(b, pts, 0.25, C, s_, t_, n_, "broken_end", "bitumen", heap=False, kind="droop")
    CHECKS["droops"][-1]["hinge_x"] = SLAB_END[3] - 0.1
    edge_bundle(b, rnd, pts, 0.25, C, rot)
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


def _smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


class Tongue:
    """Язик завалу: лежить лише з боку пролому (від торця XC до +X), біля стіни заввишки TONGUE_HW зі схилом ~31°,
    від 13 м завширшки біля стіни розширюється; шум без радіальної симетрії."""
    def __init__(self, rnd):
        self.ph = [rnd.uniform(0, 6.28) for _ in range(3)]
        self.hum = [(XC + rnd.uniform(0.0, 5.0), rnd.uniform(-5.0, 5.0), rnd.uniform(0.25, 0.55)) for _ in range(6)]

    def half(self, d):
        return 4.8 + 1.5 * _smooth((d + 3.8) / 3.8) + 0.18 * max(0.0, d)

    def base(self, d):
        if d < -5.0:
            return 0.0
        if d < -3.8:
            return 2.0 * _smooth((d + 5.0) / 1.2)
        if d < 0.0:
            return 2.0 + (TONGUE_HW - 2.0) * (d + 3.8) / 3.8
        return TONGUE_HW * max(0.0, 1 - d / TONGUE_LEN) ** 1.15

    def h(self, x, y):
        d = x - XC
        w = self.half(d)
        lat = _smooth((w - abs(y)) / 2.2)
        hum = sum(a * math.exp(-((x - px) ** 2 + (y - py) ** 2) / (2 * 1.2 ** 2)) for px, py, a in self.hum)
        return max(0.0, (self.base(d) * (1 + 0.16 * _wob(x, y, self.ph)) + hum * min(1.0, max(0.0, 1 - d / TONGUE_LEN))) * lat)

    def build(self, b, rnd, mat="heap_grey"):
        """Оболонка під плитами: нерівна сітка, вершини зсунуті; вона нижча за верх плит."""
        xs = [XC - 5.0 + 1.15 * i for i in range(12)]
        ys = [-8.4 + 1.2 * j for j in range(15)]
        vs, fs = {}, []
        for i, x0 in enumerate(xs):
            for j, y0 in enumerate(ys):
                x = x0 + (rnd.uniform(-0.3, 0.3) if 0 < i < len(xs) - 1 else 0.0)
                y = y0 + (rnd.uniform(-0.3, 0.3) if 0 < j < len(ys) - 1 else 0.0)
                vs[i, j] = b.bm.verts.new((x, y, 0.88 * self.h(x, y)))
        for i in range(len(xs) - 1):
            for j in range(len(ys) - 1):
                q = [vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]]
                if all(v.co.z < 0.02 for v in q):
                    continue
                if rnd.random() < 0.5:
                    q = q[1:] + q[:1]
                fs += [b.bm.faces.new((q[0], q[1], q[2])), b.bm.faces.new((q[0], q[2], q[3]))]
        for f in fs:
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
        b._finish(fs, mat)


class Heights:
    """Карта висот поверхні завалу (0.25 м): оболонка й верхи вже покладених плит; плита лягає на найвищу опору, а під нею лишаються порожнини."""
    G = 0.25
    X0, Y0, NX, NY = XC - 6.0, -9.5, 90, 76

    def __init__(self, tg):
        import numpy as np
        self.a = np.zeros((self.NX, self.NY))
        for i in range(self.NX):
            for j in range(self.NY):
                self.a[i, j] = 0.88 * tg.h(self.X0 + i * self.G, self.Y0 + j * self.G)

    def at(self, x, y):
        i = min(max(int(round((x - self.X0) / self.G)), 0), self.NX - 1)
        j = min(max(int(round((y - self.Y0) / self.G)), 0), self.NY - 1)
        return self.a[i, j]


def _inside(poly, x, y):
    c = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i - 1], poly[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def drop(b, rnd, hf, x, y, yaw, theta, L, W, th, mat, kind, rebar=0.3):
    """Плита L x W завтовшки th, нахил theta, спускається за напрямком yaw; центр над (x, y); лягає на найвищу опору в карті висот
    (ніс вгрузає на 6 см), решта висить над порожниною. Верх записується в карту, тож наступні плити спираються на неї."""
    pts = piece(rnd, L, W)
    x0_, y0_, yaw0 = x, y, yaw
    for attempt in range(14):                                      # якщо плита лягла б вище за межу купи, зсуваємо її
        d, s, t, n = slab_frame(yaw, theta)
        smp = list(pts) + [(u, v) for u in (-L * 0.3, 0.0, L * 0.3) for v in (-W * 0.3, 0.0, W * 0.3)]
        C = _v3(x, y, 0.0)
        clr = min((C + s * u + t * v).z - hf.at(x + (s * u + t * v).x, y + (s * u + t * v).y) for u, v in smp)
        C.z = -clr - 0.06
        ztop = C.z + th * n.z + max((s * u + t * v).z for u, v in pts)
        if ztop <= HEAP_TOP:
            break
        x, y, yaw = x0_ + rnd.uniform(-1.2, 1.2) * (attempt + 1) / 4, y0_ + rnd.uniform(-1.8, 1.8) * (attempt + 1) / 4, yaw0 + rnd.uniform(-0.3, 0.3)
    else:
        return None
    ft, rot = place_slab(b, pts, th, C, s, t, n, mat, mat, kind=kind)
    rec = CHECKS["slabs"][-1]
    rec["L"], rec["W"], rec["yaw"] = L, W, yaw
    import numpy as np
    top = C + n * th
    rad = max(math.hypot(u, v) for u, v in pts) + 0.3
    M2 = np.array([[s.x, t.x], [s.y, t.y]])
    Mi = np.linalg.inv(M2)
    for i in range(hf.NX):
        px = hf.X0 + i * hf.G
        if abs(px - x) > rad:
            continue
        for j in range(hf.NY):
            py = hf.Y0 + j * hf.G
            if abs(py - y) > rad:
                continue
            u, v = Mi @ np.array([px - top.x, py - top.y])
            if _inside(pts, u, v):
                hf.a[i, j] = max(hf.a[i, j], top.z + s.z * u + t.z * v)
    if rnd.random() < rebar:
        edge_bundle(b, rnd, pts, th, C, rot)
    return C, s, d


def damaged():
    """Обвал східного торця: стіни різані східцями, з боку пролому лежить язик завалу (оболонка, великі плити під 20-50° з порожнинами,
    шматки стінових панелей), перекриття звисають рампою або обламані за 1-2 м від стіни; з інших боків уламків немає."""
    lib.reset()
    lib.palette(glass="dark", trim=0.95)
    M = lib.mats()
    wall = tuple(c * CAV_LIN / 0.13 * 0.17 / 0.66 for c in (1.06, 0.99, 0.86))       # Plaster001 у сірому дає ~0.66; тони смуг (середнє ~0.75) опускають до CAV_LIN
    M["interior_wall"] = lib.make_material("interior_wall", "Plaster001", 1.0, recolor=wall, streak=0.9, streak_xy=2.0, bump=0.006, rough=0.9, rvar=0.25, contrast=3.0,
                                           patch=[((0.05, 0.045, 0.04), 0.3), ((0.2, 0.17, 0.12), 0.2)], patch_scale=0.3)
    M["interior_floor"] = lib.make_material("interior_floor", "Concrete034", 1.5, (0.2, 0.19, 0.175), patch=((0.03, 0.03, 0.03), 0.3), streak=0.3)
    M["broken_end"] = lib.make_material("broken_end", "Concrete034", 1.2, (0.30, 0.285, 0.265), streak=0.5, base_dirt=0.5, bump=0.05, patch=((0.36, 0.15, 0.06), 0.3), patch_scale=0.22)   # рваний бетон з іржею
    lib.FLAT.add("rebar")                                                                   # прути: плоский зразок без AO, інакше тонкі призми запікаються чорними
    M["rebar"] = lib.make_material("rebar", flat=(0.13, 0.075, 0.05))                       # іржава арматура: світліша за чорне, інакше на екрані 0-15
    for nm in ("interior_wall", "interior_floor", "slab_dark"):
        lib._dm(nm)
    b = Builder()
    rnd = random.Random(21)
    hrnd = random.Random(7)
    tg = Tongue(hrnd)
    F, B = (2, 4), (0, 3)
    body(b, X0, XC, NF, F, B, True, core_end=CORE_END, ends=ENDS)
    windows(b, X0, XC, NF, F, B, blown={("back", 6, 0), ("back", 4, 0), ("back", 5, 1), ("front", 6, 0), ("front", 5, 1)}, ends=ENDS)
    breach(b, rnd, tg)
    facade_breaks(b, rnd)
    entrances(b, XC)
    roof_details(b, 1.4)                                           # димарі й сходова шахта на уламаному даху не лишаються
    # завал
    before = set(b.bm.verts)
    tg.build(b, hrnd)
    hf = Heights(tg)
    n0 = len(CHECKS["slabs"])
    # лежачі великі плити вздовж схилу (нахил майже по схилу), потім плити, що сперті на них під круткішим кутом, потім шматки стінових панелей
    big = ((2.6, -4.2, 0.15, 29, 5.4, 2.8), (3.2, 0.4, -0.10, 31, 5.8, 3.0), (2.4, 4.3, -0.25, 28, 5.0, 2.6),
           (5.0, -1.9, 0.85, 42, 4.4, 2.4), (4.8, 2.4, -0.80, 38, 4.0, 2.6), (6.8, -1.2, 0.30, 36, 3.4, 2.2), (6.2, 4.8, -0.30, 33, 4.2, 2.2))
    for (dx, y, yaw, th_, L, W) in big:
        drop(b, hrnd, hf, XC + dx, y, yaw, th_, L, W, hrnd.uniform(0.15, 0.2), "slab_dark_dm", "slab", rebar=0.3)
    for (dx, y, yaw, th_) in ((5.8, -4.6, 0.5, 34), (6.0, 1.0, -0.4, 27), (3.8, -6.0, 0.2, 45), (5.2, 6.0, -0.6, 26), (6.6, 3.4, 1.0, 30)):
        drop(b, hrnd, hf, XC + dx, y, yaw, th_, 3.0, 2.8, hrnd.uniform(0.16, 0.2), "panel_frag", "panel", rebar=0.2)
    for k in range(7):                                              # дрібніші плити нижче по схилу
        dx, y = hrnd.uniform(6.2, 7.6), hrnd.uniform(-6.0, 6.0)
        drop(b, hrnd, hf, XC + dx, y, hrnd.uniform(-1.0, 1.0), hrnd.uniform(22, 40), hrnd.uniform(2.2, 2.9), hrnd.uniform(1.3, 1.8), hrnd.uniform(0.15, 0.2), "slab_dark_dm", "slab", rebar=0.1)
    for rec in CHECKS["slabs"][n0:]:
        rec["heap"] = True
    # брили 0.3-1 м лише в проміжках: під носом кожної плити та дрібний розсип далі
    for rec in [r for r in CHECKS["slabs"][n0:] if r["kind"] == "slab"][:10]:
        lo = max(rec["bot"], key=lambda v: (v.co.x - XC) + 0.0)
        dims = (hrnd.uniform(0.5, 0.9), hrnd.uniform(0.4, 0.8), hrnd.uniform(0.36, 0.6))
        boulder(b, hrnd, (lo.co.x + 0.2, lo.co.y, max(0.0, hf.at(lo.co.x + 0.2, lo.co.y)) + dims[2] * 0.2), dims, hrnd.choice(("chunk_concrete", "chunk_concrete", "panel_frag")), hrnd.uniform(0, 6.28))
    for i in range(12):
        x = hrnd.uniform(XC + 7.0, XC + 11.5)
        y = hrnd.uniform(-1.0, 1.0) * (6.3 + 0.18 * (x - XC) - 0.8)
        dims = (hrnd.uniform(0.4, 0.7), hrnd.uniform(0.35, 0.6), hrnd.uniform(0.32, 0.45))
        boulder(b, hrnd, (x, y, dims[2] * 0.25), dims, hrnd.choice(("chunk_concrete", "panel_frag")), hrnd.uniform(0, 6.28))
        CHECKS["scatter"].append(x - XC)
    apron(b, tg)
    CHECKS["heap_verts"] = [v for v in b.bm.verts if v not in before]
    validate(tg)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4600, footprint=(5, 2), anchor=(0, 0), ground_clip=True, ao=0.45)


def apron(b, tg, step=0.9, width=1.3):
    """Пиловий фартух навколо язика: плоскі клітинки поруч із завалом (у межах сліду 5x2 тайли він вужчий за 2-3 м)."""
    cells = set()
    xs = [XC - 4.0 + step * i for i in range(int(18.0 / step))]
    ys = [-9.0 + step * j for j in range(int(18.0 / step) + 1)]
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            if tg.h(x + step / 2, y + step / 2) > 0.05 or x + step / 2 < XC - 0.5:
                continue
            near = min(math.hypot(x + step / 2 - px, y + step / 2 - py) for px in (x - width, x + step / 2, x + step + width) for py in (y - width, y + step / 2, y + step + width) if tg.h(px, py) > 0.2) if any(tg.h(px, py) > 0.2 for px in (x - width, x + step / 2, x + step + width) for py in (y - width, y + step / 2, y + step + width)) else None
            if near is not None and abs(y + step / 2) < 8.5:
                cells.add((i, j))
    for (i, j) in cells:
        x, y = xs[i], ys[j]
        lib._quad(b, [(x, y, 0.03), (x + step, y, 0.03), (x + step, y + step, 0.03), (x, y + step, 0.03)], "heap_grey", (0, 0, 1))
    CHECKS["apron"] = len(cells)


def validate(tg):
    """Кожна вимога до завалу й пролому — перевірка на побудованій геометрії; порушення валить збирання."""
    import numpy as np
    hv = [v for v in CHECKS["heap_verts"] if v.is_valid]
    top = max(v.co.z for v in hv)
    assert 3.0 <= top <= 4.6, f"висота купи {top:.2f} м поза 3-4.6: " + str([(c["kind"], round(c["L"], 1), round(max(v.co.z for v in c["top"]), 2)) for c in CHECKS["slabs"] if "L" in c])
    wall_h = max(v.co.z for v in hv if abs(v.co.x - XC) <= 1.0)
    assert wall_h >= 2.5, f"біля стіни купа лише {wall_h:.2f} м"
    reach = max(v.co.x for v in hv) - XC
    assert 8.0 <= reach <= 12.0, f"виліт купи {reach:.1f} м поза 8-12"
    assert min(v.co.x for v in hv) >= XC - 5.1, "завал виходить углиб будинку за межу кімнат"
    bad = [(round(v.co.x, 1), round(v.co.y, 1), round(v.co.z, 1)) for v in hv if v.co.x < XC and abs(v.co.y) > 7.0 and v.co.z > 0.1]
    assert not bad, f"уламки з боків будинку далі ніж на 1 м від стіни {bad[:5]}"
    dense = max(d for d in [i * 0.05 for i in range(0, 400)] if tg.base(d) > 0.3)       # де оболонка ще вища за 0.3 м
    assert 6.0 <= dense <= 8.0, f"щільна частина {dense:.1f} м, треба ~7"
    hs = [c for c in CHECKS["slabs"] if c["heap"]]
    big, panels = 0, 0
    for c in CHECKS["slabs"]:
        c["ft"].normal_update()
        ang = math.degrees(math.acos(min(1.0, abs(c["ft"].normal.z))))
        c["ang"] = ang
        th = abs((c["top"][0].co - c["bot"][0].co).dot(c["ft"].normal))
        a = np.array([(v.co.x, v.co.y, v.co.z) for v in c["top"]])
        a = a - a.mean(axis=0)
        ev = np.sqrt(np.maximum(np.linalg.eigvalsh(a.T @ a / len(a)), 0))
        c["size"] = (ev[1] * 3.46, ev[2] * 3.46)
        if c["heap"]:
            assert 20.0 <= ang <= 50.0, f"нахил плити {ang:.1f}° поза 20-50°"
            assert 0.14 - 1e-3 <= th <= 0.2 + 1e-3, f"товщина уламка {th:.3f}"
            assert c["size"][0] >= 1.2 and c["size"][1] / c["size"][0] <= 3.2, f"плита-скалка {c['size']}"
            if c["kind"] == "slab" and c["L"] >= 3.0 and c["W"] >= 1.2:
                big += 1
            if c["kind"] == "panel":
                panels += 1
        else:
            assert 30.0 <= ang <= 70.0 and 0.14 <= th <= 0.2, "плита в кімнаті"
    assert big >= 6, f"великих плит {big}"
    assert panels >= 4, f"шматків панелей {panels}"
    vis = sum(1 for c in hs if c["kind"] == "slab" and c["L"] > 3.0 and c["ft"].normal.dot(_v3(0.55, -0.55, 0.62)) > 0.3)
    assert vis + len([r for r in CHECKS["ramps"]]) >= 6, f"з камери видно лише {vis} довгих плит"
    shallow = sum(1 for c in hs if c["ang"] <= 36.0)
    assert shallow >= 0.25 * len(hs)
    exts = []
    for verts, rot, dims in CHECKS["boulders"]:
        loc = [rot.transposed() @ Vector(v.co) for v in verts]
        ext = sorted(max(p[i] for p in loc) - min(p[i] for p in loc) for i in range(3))
        assert 0.3 <= ext[0] and ext[2] <= 1.0, f"брила {ext}"
        assert ext[2] / ext[0] <= 3.4, "брила-голка"
        exts.append(ext)
    for dia, v in CHECKS["rods"]:
        assert 0.01 <= dia <= 0.02, f"діаметр прута {dia}"
        assert math.degrees(math.asin(abs(v.normalized().z))) <= 60.0, "прут стирчить сторч"
    assert min(CHECKS["stubs"]) >= 0.2 and SLAB_TH >= 0.2, "торець перекриття тонший за 0.2 м"
    assert all(2 <= n <= 3 for n in CHECKS["partitions"].values()) and len(CHECKS["partitions"]) == NF
    assert CHECKS["ceilings"] == NF and CHECKS["furniture"] >= 3
    est = 255 * (1.055 * (CAV_LIN * 0.47) ** (1 / 2.4) - 0.055)      # 0.47 — зміряно під світлом Річки: альбедо 0.03 дало sRGB 32
    assert 60 <= est <= 80, f"нутро кімнат на екрані під Річкою ~{est:.0f}: ціль 60-80 (було 32)"
    # пролом: жодного плаского перекриття, рампа, звис, зріз даху, зріз фасаду
    assert all(1.0 <= f <= 2.0 for f in CHECKS["flats"]), f"пласка частина перекриття від стіни {CHECKS['flats']}: має бути 1-2 м"
    assert len(CHECKS["ramps"]) == 2
    for r in CHECKS["ramps"]:
        r["ft"].normal_update()
        ang = math.degrees(math.acos(abs(r["ft"].normal.z)))
        assert 25.0 <= ang <= 40.0, f"рампа {ang:.1f}° поза 25-40"
        r["ang"] = ang
    assert len(CHECKS["droops"]) == 1
    dr = CHECKS["droops"][0]
    dr["ft"].normal_update()
    dang = math.degrees(math.acos(abs(dr["ft"].normal.z)))
    dover = max(v.co.x for v in dr["top"]) - dr["hinge_x"]
    assert 15.0 <= dang <= 30.0 and 1.0 <= dover <= 2.0, f"звис даху {dang:.1f}° {dover:.2f} м"
    cut = ENDS[2] - max(v.co.x for v in CHECKS["roof_verts"])
    assert 1.0 <= cut <= 1.5, f"плита даху зрізана на {cut:.2f} м, треба 1-1.5"
    assert len(CHECKS["protr"]) == 2 * NF and all(3 <= len(g) <= 5 and all(0.3 <= x <= 0.8 for x in g) for g in CHECKS["protr"]), f"виступи зрізу фасаду {CHECKS['protr']}"
    assert CHECKS["bundles"] and all(0.05 <= w <= 0.08 for w in CHECKS["bundles"]), "пучок арматури 5-8 см"
    assert CHECKS.get("floor_soot") == 2 and CHECKS["apron"] > 20
    print("MEAS heap_top_m=%.2f at_wall=%.2f reach=%.1f dense=%.1f slabs=%d (big=%d panels=%d) tilt=%.0f..%.0f ramps=%s droop=%.0f/%.2fm" % (
        top, wall_h, reach, dense, len(hs), big, panels, min(c["ang"] for c in hs), max(c["ang"] for c in hs), [round(r["ang"]) for r in CHECKS["ramps"]], dang, dover))
    print("MEAS flats_m=%s boulders=%d dims=%.2f..%.2f rods=%d apron_cells=%d" % ([round(f, 2) for f in CHECKS["flats"]], len(exts), min(e[0] for e in exts), max(e[2] for e in exts), len(CHECKS["rods"]), CHECKS["apron"]))


if os.environ.get("BLOCK_ONLY") != "damaged":
    intact()
damaged()
