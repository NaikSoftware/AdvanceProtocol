"""H5: панельна п'ятиповерхівка 33 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант (обвалилась середня секція)."""
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
LEN, DEP, FLOOR, NF = 33.0, 12.0, 3.1, 5
NB = int(LEN / 3.0)      # 11 секцій по 3 м
H = FLOOR * NF           # 15.5 м до плити даху
X0, X1, Y0, Y1 = -LEN / 2, LEN / 2, -DEP / 2, DEP / 2
STAIRS = (1, 5, 9)       # осі сходових кліток (кроки по 3 м)
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


def body(b, xa, xb, nf, front, back, roof, core_end=None, ends=None, core_start=None, starts=None):
    """Секція будинку: серцевина, фасадні шари з прорізами-лоджіями, вікна на сітці."""
    top_z = nf * FLOOR
    ends = ends or (xb,) * nf                      # де обривається фасадний шар на кожному поверсі
    ce = xb if core_end is None else core_end      # де обривається серцевина (далі — порожнина кімнат)
    cs = xa if core_start is None else core_start  # де починається серцевина (праве крило)
    starts = starts or (xa,) * nf
    b.box((cs + ce) / 2, 0, 0, ce - cs, DEP - 2 * LOG, top_z, "panel", top="bitumen" if roof else "panel_scorched")
    for (ya, yb, cols, side) in ((Y1 - LOG, Y1, front, 1), (Y0, Y0 + LOG, back, -1)):
        yc = (ya + yb) / 2
        for f in range(nf):
            z0 = f * FLOOR
            use = cols if f >= 1 else ()
            for (a, c) in intervals(starts[f], ends[f], [i for i in use if starts[f] <= bay_x(i) <= ends[f]]):
                b.box((a + c) / 2, yc, z0, c - a, LOG, FLOOR, "panel", top="panel" if f < nf - 1 or not roof else "bitumen")
        for i in cols:
            x = bay_x(i)
            if not (xa <= x <= xb):
                continue
            ye = Y1 if side > 0 else Y0
            yp = ye - 0.06 * side
            for f in range(1, nf):
                z = f * FLOOR
                b.box(x, yp, z, 2 * LW, 0.12, 1.1, "panel")                       # парапет лоджії 1.1 м
                b.box(x, yp, z + 1.1, 2 * LW + 0.1, 0.07, 0.07, "metal_dark")    # поручень
                yb = ye - LOG * side + 0.01 * side
                b.poly([(x - LW, yb, z), (x + LW, yb, z), (x + LW, yb, z + FLOOR), (x - LW, yb, z + FLOOR)][::-side], "panel_light")
                for sx in (-1, 1):
                    b.box(x + sx * (LW - 0.03), (ya + yb) / 2, z, 0.06, LOG, FLOOR - 0.15, "panel_light")   # впритул до шару фасаду: щілина 5 мм давала чорні крапки по краю лоджії
                if (i * 7 + f * 3 + (1 if side > 0 else 0)) % 2 == 0:                       # засклена лоджія: рама над парапетом
                    b.window(("y", ye - 0.08 * side, side), x, z + 1.15, 2 * LW - 0.06, FLOOR - 1.4)
            for f in range(2, nf):
                b.box(x, (ya + yb) / 2, f * FLOOR - 0.15, 2 * LW, LOG, 0.15, "panel", top="panel")  # плита між лоджіями
            if nf > 2:
                b.box(x, (ya + yb) / 2, top_z - 0.2, 2 * LW, LOG, 0.2, "panel", top="bitumen" if roof else "panel")


def windows(b, xa, xb, nf, front, back, blown=(), ends=None, starts=None):
    """Сувора сітка: одне вікно на панель, однакового розміру; лоджійні вікна в глибині ніші."""
    for side, (y, sgn, cols) in (("front", (Y1, 1, front)), ("back", (Y0, -1, back))):
        for i in range(NB):
            x = bay_x(i)
            if not (xa <= x <= xb):
                continue
            for f in range(nf):
                if i in STAIRS and f == 0 and side == "front":
                    continue
                if (ends and x + 0.85 > ends[f]) or (starts and x - 0.85 < starts[f]):
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
                    y1_ = yy + 0.13 * sgn                                              # підвіконня: лише видимі грані (верх і фасад), 4 трикутники
                    lib._quad(b, [(x - 0.85, yy, z), (x + 0.85, yy, z), (x + 0.85, y1_, z), (x - 0.85, y1_, z)], "panel", (0, 0, 1))
                    lib._quad(b, [(x - 0.85, y1_, z - 0.1), (x + 0.85, y1_, z - 0.1), (x + 0.85, y1_, z), (x - 0.85, y1_, z)], "panel", (0, sgn, 0))


def roof_details(b, xmax, xmin=None):
    """Шахти сходів, димарі й парапет на даху; xmin/xmax — межі крила (повний будинок — без xmin)."""
    lo = X0 if xmin is None else xmin
    for i in STAIRS:
        if bay_x(i) > xmax or bay_x(i) - 1.3 < lo:
            continue
        b.box(bay_x(i), Y0 + 2.6, H, 2.6, 2.6, 2.4, "panel", top="bitumen")
    for k, x in enumerate((-13, -8, -3, 3, 8, 13)):
        if x > xmax or x < lo or (xmax < X1 and xmin is None and x > -4):
            continue
        b.cyl(x, 1.2 * (-1) ** k, H, 0.22, 1.6, 8, "metal_dark")
    # парапет по периметру даху
    xe = min(X1, xmax)
    b.box((lo + xe) / 2, Y1 - 0.1, H, xe - lo, 0.2, 0.5, "panel")
    b.box((lo + xe) / 2, Y0 + 0.1, H, xe - lo, 0.2, 0.5, "panel")
    if lo <= X0:
        b.box(X0 + 0.1, 0, H, 0.2, DEP - 0.4, 0.5, "panel")
    if xe >= X1:
        b.box(X1 - 0.1, 0, H, 0.2, DEP - 0.4, 0.5, "panel")


def entrances(b, xmax, xmin=-99.0):
    for i in STAIRS:
        if bay_x(i) > xmax or bay_x(i) < xmin:
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
    lib.finish(b, "h5_panel_block", out, tri_limit=4000, footprint=(4, 2), anchor=(0, 0))




# --------------------------------------------------------------------------- пошкоджений варіант

# --------------------------------------------------------------------------- пошкоджений варіант

XA, XB = -6.5, 6.5                    # пролом: одна середня секція 13 м, на всю висоту; з обох боків лишаються крила
XCEN = (XA + XB) / 2                  # вісь язика завалу
YF = Y1                               # площина фасаду, на який лежить завал (+Y моделі = −Z у Godot, «фасад»)
YI = DEP / 2 - LOG                    # внутрішня півширина кімнат (між фасадними шарами)
CL, CR = -11.5, 11.0                   # де кінчається серцевина лівого крила й починається серцевина правого; далі — відкриті кімнати
REL_L = (5.0, 4.1, 3.4, 4.4, 3.2)     # на скільки метрів від серцевини тримається фасадний шар на 1-5 поверсі (уступами)
REL_R = (4.5, 3.7, 3.0, 4.0, 3.2)
SLAB_REL = {1: 1.6, 2: 1.2, 3: 1.5, 4: 1.2, 5: 1.9}   # пласка частина перекриття від стіни: обламана за 1-2 м; 5 — плита даху
RAMPS = {1: (2, 4), -1: (3,)}         # поверхи, де перекриття звисає рампою (1 — ліве крило, -1 — праве)
SLAB_TH = 0.22
PASTEL = ((150, 190, 160), (215, 172, 142), (150, 172, 205), (216, 206, 172))   # пастельні стіни кімнат: м'ята, персик, блакить, крем
HEAP_TOP = 4.3                        # найвища точка плит, м
TONGUE_HW = 3.6                       # висота купи біля стіни, м
TONGUE_LEN = 7.6                      # щільна частина виходить від фасаду на ~7 м
XL = 6.0                              # площина фасаду в локальній системі язика (спуск уздовж +x), потім повертається на +Y моделі
CAV_LIN = 0.13                        # середнє альбедо стін кімнат (лінійне): під небом Річки дає на екрані sRGB ~70

CHECKS = {"ramps": [], "droops": [], "flats": [], "panels": [], "scatter": [], "apron": [], "protr": [], "slab_max": {}, "bundles": [], "slabs": [], "boulders": [], "rods": [],
          "heap_verts": [], "stubs": [], "partitions": {}, "ceilings": 0, "roof_verts": {}, "floor_rubble": 0, "cells": 0}


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


def place_slab(b, pts, th, C, s, t, n, mat="slab_light_dm", top="slab_light_dm", heap=True, kind="slab"):
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
    rows = [(z0, 0.55), (z0 + (z1 - z0) * 0.55, 1.0), (z1, 0.3)]
    for (za, ta), (zb, tb) in zip(rows, rows[1:]):
        b.decal([(a[0], a[1], za), (c[0], c[1], za), (c[0], c[1], zb), (a[0], a[1], zb)], [ta, ta, tb, tb], mat, nrm)



def rubble(b, rnd, c, size, mat, tone=(0.75, 1.2), flat=0.55):
    """Шматок завалу: перекошений восьмигранник (8 трикутників) з довшою віссю size, власного тону; чотири його осі різної довжини."""
    from mathutils import Euler
    a = size
    dims = (a, a * rnd.uniform(max(flat, 0.55), 1.0), a * rnd.uniform(flat, 0.8))
    rot = Euler((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(0, 6.28))).to_matrix()
    axes = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]
    vs = {}
    for i, ax in enumerate(axes):
        for sg in (-1, 1):
            p = Vector(ax) * sg * dims[i] / 2 * rnd.uniform(0.8, 1.0)
            p += Vector((rnd.uniform(-0.12, 0.12) * dims[0], rnd.uniform(-0.12, 0.12) * dims[1], rnd.uniform(-0.12, 0.12) * dims[2]))
            vs[i, sg] = b.bm.verts.new(rot @ p + Vector(c))
    faces = [b.bm.faces.new((vs[0, sx], vs[1, sy], vs[2, sz])) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    b._finish(faces, mat)
    tn = rnd.uniform(*tone)
    for f in faces:
        for lp in f.loops:
            lp[b.wtone] = (tn, tn, tn, 1.0)
    CHECKS["boulders"].append((list(vs.values()), rot, dims))


def wing(b, rnd, sgn, tgw):
    """Крило з відкритими кімнатами на зламі: sgn=+1 — ліве (відкрите до +x), -1 — праве. Кожен поверх — клітинки з поперечною й повздовжньою
    стінками, пастельні стіни, обламане перекриття (пласка частина 1-2 м від стіни, далі рампа чи звис), посипана підлога."""
    core = CL if sgn > 0 else CR
    rel = REL_L if sgn > 0 else REL_R
    X = lambda d: core + sgn * d
    rs_ = b._slot("rebar")
    for k in range(1, NF + 1):                                     # перекриття k: низ на k*FLOOR - товщина
        xe = SLAB_REL[k]
        z_top = k * FLOOR
        before_k = set(b.bm.verts)
        top = "bitumen" if k == NF else "interior_floor"
        b.box((X(0) + X(xe - 0.7)) / 2, 0, z_top - SLAB_TH, xe - 0.7, 2 * YI, SLAB_TH, "broken_end", top=top)
        cuts = [rnd.uniform(0.35, 0.65)]
        ys = [-YI] + [-YI + 2 * YI * c_ for c_ in cuts] + [YI]
        mx = 0.0
        for i in range(len(ys) - 1):                               # рваний торець: зубці різної довжини, кожен ≥ 0.2 м завтовшки
            ov = rnd.uniform(0.55, 0.7) if k == NF else rnd.uniform(0.3, 1.0)
            th = rnd.uniform(SLAB_TH, 0.27)
            b.box(X(xe - 0.7 + ov / 2), (ys[i] + ys[i + 1]) / 2, z_top - th, ov, ys[i + 1] - ys[i] + 0.02, th, "broken_end", top=top)
            CHECKS["stubs"].append(th)
            mx = max(mx, xe - 0.7 + ov)
            if rnd.random() < 0.04:
                bundle(b, _v3(X(xe - 0.7 + ov), (ys[i] + ys[i + 1]) / 2, z_top - th / 2), (sgn, 0, 0), rnd, (0, 1, 0))
        CHECKS["slab_max"][(sgn, k)] = mx
        CHECKS["flats"].append(mx)                                 # скільки пласкої плити лишилось від стіни
        zc = z_top - SLAB_TH
        f = lib._quad(b, [(X(0), -YI, zc - 0.03), (X(xe - 0.7), -YI, zc - 0.03), (X(xe - 0.7), YI, zc - 0.03), (X(0), YI, zc - 0.03)], "soot_v", (0, 0, -1))
        for lp in f.loops:
            lp[b.wtone] = (0.02, 0.02, 0.02, 1.0)
        CHECKS["ceilings"] += 1
        if k < NF:                                                 # кіптява на лишку підлоги й шматки, що на ній лежать
            b.decal([(X(0), -YI + 0.05, z_top + 0.03), (X(xe - 0.7), -YI + 0.05, z_top + 0.03), (X(xe - 0.7), YI - 0.05, z_top + 0.03), (X(0), YI - 0.05, z_top + 0.03)], [1.0, 0.6, 0.6, 1.0], "interior_floor_dm", (0, 0, 1))
            for _ in range(2):
                sz = rnd.uniform(0.44, 0.7)
                rubble(b, rnd, (X(rnd.uniform(0.4, xe - 0.8)), rnd.uniform(-3.8, 3.8), z_top + sz * 0.25), sz, "heap_light_dm", flat=0.5)
                CHECKS["floor_rubble"] += 1
        if k == NF:
            CHECKS["roof_verts"][sgn] = [v for v in b.bm.verts if v not in before_k and any(f.material_index != rs_ for f in v.link_faces)]   # без прутів арматури
    # перекриття, що звисають рампою: два шматки панелей по ~3 м, посередині панелі немає
    for k in RAMPS[sgn]:
        for (yc, wd, ang) in ((-3.0, 3.1, 31.0), (2.9, 3.3, 36.0)):
            d_, s_, t_, n_ = slab_frame(0.0 if sgn > 0 else math.pi, ang)
            hinge = _v3(X(SLAB_REL[k] - 0.1), yc, k * FLOOR)
            Lr = 6.0
            for Lq in [3.0 + 0.1 * q for q in range(0, 31)]:       # довжина до купи, а коли до неї не дістає — до 6 м, і шматок висить на арматурі
                e = hinge + s_ * Lq
                if e.z <= tgw(e.x, yc) + 0.1:
                    Lr = Lq
                    break
            th = 0.22
            pts = [(-Lr / 2, -wd / 2), (Lr / 2 - rnd.uniform(0.2, 0.6), -wd / 2), (Lr / 2, -wd / 2 + rnd.uniform(0.5, 1.2)), (Lr / 2 - rnd.uniform(0.1, 0.5), wd / 2), (-Lr / 2, wd / 2)]
            C = hinge - n_ * th + s_ * (Lr / 2)
            ft, rot = place_slab(b, pts, th, C, s_, t_, n_, "broken_end", "interior_floor", heap=False, kind="ramp")
            CHECKS["ramps"][-1]["len"] = Lr
            if k == RAMPS[sgn][0] and yc < 0:
                edge_bundle(b, rnd, pts, th, C, rot)
    # покрівля звисає з краю даху
    d_, s_, t_, n_ = slab_frame(0.0 if sgn > 0 else math.pi, 22.0)
    Ld = 1.9
    hinge = _v3(X(SLAB_REL[NF] - 0.1), 1.6, H)
    pts = [(-Ld / 2, -1.8), (Ld / 2, -1.8 + rnd.uniform(0.2, 0.6)), (Ld / 2 - rnd.uniform(0.2, 0.5), 1.8), (-Ld / 2, 1.8)]
    C = hinge - n_ * 0.25 + s_ * (Ld / 2)
    ft, rot = place_slab(b, pts, 0.25, C, s_, t_, n_, "broken_end", "bitumen", heap=False, kind="droop")
    CHECKS["droops"][-1].update(hinge_x=X(SLAB_REL[NF] - 0.1), sgn=sgn)
    if sgn > 0:
        edge_bundle(b, rnd, pts, 0.25, C, rot)
    # кімнати
    OFF = 0.05                                                     # внутрішні стіни зсунуті від граней фасадних шарів, щоб не було z-fighting
    for f in range(NF):
        zf, zc = f * FLOOR + 0.03, (f + 1) * FLOOR - SLAB_TH - 0.03
        re = rel[f]
        pm = (f + (0 if sgn > 0 else 2)) % 4                       # кожна клітинка свого пастельного кольору
        CHECKS["cells"] += 2
        for sy in (-1, 1):
            wall_bands(b, (X(0.05), sy * (YI - OFF)), (X(re - 0.02), sy * (YI - OFF)), zf, zc, (0, -sy, 0), "wp%d_dm" % pm)
        wall_bands(b, (X(0.05), -YI + OFF), (X(0.05), YI - OFF), zf, zc, (sgn, 0, 0), "wp%d_dm" % pm)
        zp0 = zf - 0.03
        nparts = 0
        if re > 2.6:                                               # поперечна стіна з дверима
            dc = rnd.uniform(-2.5, 2.5)
            for (ya, yb) in ((-YI + 0.02, dc - 0.45), (dc + 0.45, YI - 0.02)):
                b.box(X(1.8), (ya + yb) / 2, zp0, 0.14 * 1.0, yb - ya, (zc + 0.03) - zp0 - (rnd.uniform(0.0, 1.2) if re > 3.8 else 0.0), "wp%d" % ((pm + 1) % 4), top="wp%d" % pm)
            nparts += 1
        ln = min(re - 0.3, 3.4)                                    # повздовжня стіна ділить поверх на дві клітинки
        dg = rnd.uniform(0.8, ln - 1.0)
        for (da, db) in ((0.05, dg), (dg + 0.9, ln)):
            if db - da > 0.2:
                b.box((X(da) + X(db)) / 2, 0, zp0, db - da, 0.12, (zc + 0.03) - zp0 - (0.6 if db > 3.0 else 0.0), "wp%d" % ((pm + 2) % 4), top="wp%d" % pm)
        nparts += 1
        CHECKS["partitions"][(sgn, f)] = nparts + 1                # + задня стіна клітинки
    # меблі в кімнатах 3-го й 4-го поверхів
    if sgn > 0:
        b.box_e(X(1.2), -3.5, 2 * FLOOR + 0.45, 1.8, 0.55, 0.5, "timber_dark", euler=(0.0, 0.0, 0.25), top="timber_dark")
        b.box(X(2.0), 2.8, 3 * FLOOR, 1.9, 0.9, 0.35, "timber_dark", rot=0.4)
        CHECKS["furniture"] = CHECKS.get("furniture", 0) + 2


def facade_breaks(b, rnd, sgn):
    """Зламаний зріз фасадних панелей: на кожному зрізі 3-5 виступів 0.3-0.8 м різної висоти, а сам торець зі рваним бетоном."""
    core = CL if sgn > 0 else CR
    rel = REL_L if sgn > 0 else REL_R
    for f in range(NF):
        xe = core + sgn * rel[f]
        for sy in (-1, 1):
            y0, y1 = sorted((sy * YI, sy * (YI + LOG)))
            lib._quad(b, [(xe + sgn * 0.004, y0, f * FLOOR), (xe + sgn * 0.004, y1, f * FLOOR), (xe + sgn * 0.004, y1, (f + 1) * FLOOR), (xe + sgn * 0.004, y0, (f + 1) * FLOOR)], "broken_end", (sgn, 0, 0))
            cnt = 3
            zs = sorted(rnd.uniform(0.0, FLOOR - 0.6) for _ in range(cnt))
            got = []
            for z0 in zs:
                ln, hh, yw = rnd.uniform(0.38, 0.7), rnd.uniform(0.45, 1.1), rnd.uniform(0.45, 0.8)
                yc = rnd.uniform(y0 + yw / 2, y1 - yw / 2)
                za = f * FLOOR + z0
                px = xe + sgn * ln
                tri = [(xe - sgn * 0.02, yc - yw / 2), (xe - sgn * 0.02, yc + yw / 2), (px, yc + rnd.uniform(-0.2, 0.2))]    # зуб у плані — трикутник: 7 трикутників замість 10
                lib.shard(b, tri, hh, Matrix.Identity(3), (0, 0, za), "broken_end", "broken_end")
                got.append(max((x_ - xe) * sgn for x_, y_ in tri))
            CHECKS["protr"].append(got)


def _smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


class Tongue:
    """Язик завалу в локальній системі (спуск уздовж +x від площини XL): біля стіни заввишки TONGUE_HW зі схилом ~31°, від 13 м завширшки біля
    стіни розширюється до ~17 м; шум без радіальної симетрії. Після побудови весь завал повертається так, що +x стає +Y моделі."""
    def __init__(self, rnd):
        self.ph = [rnd.uniform(0, 6.28) for _ in range(3)]
        self.hum = [(XL + rnd.uniform(0.0, 5.0), rnd.uniform(-5.0, 5.0), rnd.uniform(0.25, 0.55)) for _ in range(6)]

    def half(self, d):
        return 5.2 + 1.3 * _smooth((d + 3.8) / 3.8) + 0.29 * max(0.0, d)

    def base(self, d):
        if d < -5.0:
            return 0.0
        if d < -3.8:
            return 2.0 * _smooth((d + 5.0) / 1.2)
        if d < 0.0:
            return 2.0 + (TONGUE_HW - 2.0) * (d + 3.8) / 3.8
        return TONGUE_HW * max(0.0, 1 - d / TONGUE_LEN) ** 1.15

    def h(self, x, y):
        d = x - XL
        w = self.half(d)
        lat = _smooth((w - abs(y)) / 2.2)
        hum = sum(a * math.exp(-((x - px) ** 2 + (y - py) ** 2) / (2 * 1.2 ** 2)) for px, py, a in self.hum)
        return max(0.0, (self.base(d) * (1 + 0.16 * _wob(x, y, self.ph)) + hum * min(1.0, max(0.0, 1 - d / TONGUE_LEN))) * lat)

    def build(self, b, rnd, mat="heap_light"):
        """Оболонка під уламками: нерівна сітка, нижча за верх плит і шматків."""
        xs = [XL - 5.0 + 1.55 * i for i in range(10)]
        ys = [-10.5 + 1.5 * j for j in range(15)]
        vs, fs = {}, []
        for i, x0 in enumerate(xs):
            for j, y0 in enumerate(ys):
                x = x0 + (rnd.uniform(-0.3, 0.3) if 0 < i < len(xs) - 1 else 0.0)
                y = y0 + (rnd.uniform(-0.3, 0.3) if 0 < j < len(ys) - 1 else 0.0)
                vs[i, j] = b.bm.verts.new((x, y, 0.85 * self.h(x, y)))
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
    """Карта висот завалу (0.25 м): оболонка, шматки й верхи вже покладених плит; плита лягає на найвищу опору, тож під нею лишаються порожнини."""
    G = 0.25
    X0, Y0, NX, NY = XL - 6.0, -12.0, 96, 96

    def __init__(self, tg):
        import numpy as np
        self.a = np.zeros((self.NX, self.NY))
        for i in range(self.NX):
            for j in range(self.NY):
                self.a[i, j] = 0.85 * tg.h(self.X0 + i * self.G, self.Y0 + j * self.G)

    def at(self, x, y):
        i = min(max(int(round((x - self.X0) / self.G)), 0), self.NX - 1)
        j = min(max(int(round((y - self.Y0) / self.G)), 0), self.NY - 1)
        return self.a[i, j]

    def raise_disc(self, x, y, r, z):
        for i in range(max(0, int((x - r - self.X0) / self.G)), min(self.NX, int((x + r - self.X0) / self.G) + 2)):
            for j in range(max(0, int((y - r - self.Y0) / self.G)), min(self.NY, int((y + r - self.Y0) / self.G) + 2)):
                if math.hypot(self.X0 + i * self.G - x, self.Y0 + j * self.G - y) <= r:
                    self.a[i, j] = max(self.a[i, j], z)


def _inside(poly, x, y):
    c = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i - 1], poly[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def drop(b, rnd, hf, x, y, yaw, theta, L, W, th, mat, kind, sink=0.3, rebar=0.1):
    """Плита L x W завтовшки th, нахил theta, спускається за напрямком yaw; лягає на найвищу опору (ніс вгрузає на sink), решта висить над
    порожниною. Верх записується в карту, тож наступні плити спираються на неї."""
    pts = piece(rnd, L, W)
    x0_, y0_, yaw0 = x, y, yaw
    for attempt in range(14):                                      # якщо плита лягла б вище за межу купи, зсуваємо її
        d, s, t, n = slab_frame(yaw, theta)
        smp = list(pts) + [(u, v) for u in (-L * 0.3, 0.0, L * 0.3) for v in (-W * 0.3, 0.0, W * 0.3)]
        C = _v3(x, y, 0.0)
        clr = min((C + s * u + t * v).z - hf.at(x + (s * u + t * v).x, y + (s * u + t * v).y) for u, v in smp)
        C.z = -clr - sink
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
    Mi = np.linalg.inv(np.array([[s.x, t.x], [s.y, t.y]]))
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


def apron(b, tg, width=1.3, n=44):
    """Пиловий фартух навколо язика: смуга між контуром завалу й обрисом на 1.3 м далі, з хвилястим зовнішнім краєм (без клітинок-прямокутників)."""
    cx, cy = XL + 2.5, 0.0
    ring = []
    for i in range(n + 1):
        a = -math.pi * 0.5 + math.pi * (i / n) * 1.0 * 2.0          # вся навколо центру; частину, що за стіною, відкидаємо нижче
        ca, sa = math.cos(a), math.sin(a)
        r = 0.0
        while r < 20.0 and tg.h(cx + ca * r, cy + sa * r) > 0.05:
            r += 0.1
        out = r + width * (1.0 + 0.3 * _wob(ca * 3, sa * 3, tg.ph))
        ring.append((cx + ca * (r - 0.3), cy + sa * (r - 0.3), cx + ca * out, cy + sa * out))
    cnt = 0
    for (x0, y0, x1, y1), (x2, y2, x3, y3) in zip(ring, ring[1:]):
        if min(x0, x1, x2, x3) < XL - 0.2:
            continue
        lib._quad(b, [(x0, y0, 0.06), (x1, y1, 0.035), (x3, y3, 0.035), (x2, y2, 0.06)], "heap_light", (0, 0, 1))
        cnt += 1
    CHECKS["apron"] = cnt


def damaged():
    """Обвал середньої секції: два уцілілі крила з відкритими кімнатами, між ними пролом на всю висоту; на фасад (+Y) лежить язик завалу
    (дрібняк і шматки 0.3-1.5 м як тіло, 6-8 плит стирчать під різними кутами), з інших боків уламків немає."""
    lib.reset()
    lib.palette(glass="dark", trim=0.95)
    M = lib.mats()
    for i, col in enumerate(PASTEL):                                # пастельні штукатурки кімнат, середнє альбедо ~CAV_LIN з урахуванням тонів смуг
        lin = lib.srgb_lin(tuple(c / 255.0 for c in col))
        k = CAV_LIN / 0.13 * 0.17 / (sum(lin) / 3) / 0.66
        M["wp%d" % i] = lib.make_material("wp%d" % i, "Plaster001", 1.0, recolor=tuple(c * k for c in lin), streak=0.9, streak_xy=2.0, bump=0.006, rough=0.9, rvar=0.25, contrast=3.0,
                                          patch=[((0.05, 0.045, 0.04), 0.3), ((0.2, 0.17, 0.12), 0.2)], patch_scale=0.3)
        lib._dm("wp%d" % i)
    M["interior_floor"] = lib.make_material("interior_floor", "Concrete034", 1.5, (0.2, 0.19, 0.175), patch=((0.03, 0.03, 0.03), 0.3), streak=0.3)
    M["broken_end"] = lib.make_material("broken_end", "Concrete034", 1.2, (0.30, 0.285, 0.265), streak=0.5, base_dirt=0.5, bump=0.05, patch=((0.36, 0.15, 0.06), 0.3), patch_scale=0.22)   # рваний бетон з іржею
    M["heap_light"] = lib.make_material("heap_light", "Concrete034", 2.0, (0.40, 0.39, 0.375), streak=0.3, base_dirt=0.4, bump=0.05)           # світло-сірий дрібняк завалу
    M["slab_light"] = lib.make_material("slab_light", "Concrete034", 1.2, (0.52, 0.505, 0.485), streak=0.4, base_dirt=0.4, bump=0.03)
    M["frag_light"] = lib.make_material("frag_light", "Concrete034", 1.2, (0.52, 0.505, 0.48), streak=0.8, base_dirt=0.5, bump=0.03)
    lib.FLAT.add("rebar")                                                                   # прути: плоский зразок без AO, інакше тонкі призми запікаються чорними
    M["rebar"] = lib.make_material("rebar", flat=(0.13, 0.075, 0.05))
    for nm in ("interior_floor", "heap_light", "slab_light", "frag_light"):
        lib._dm(nm)
    b = Builder()
    rnd = random.Random(21)
    hrnd = random.Random(7)
    tg = Tongue(hrnd)
    tgw = lambda x, y: 0.85 * tg.h(XL + (y - YF), XCEN - x)        # поверхня язика в координатах моделі
    ends_l = tuple(CL + r for r in REL_L)
    starts_r = tuple(CR - r for r in REL_R)
    # крила: серцевина + фасадні шари, що обриваються уступами по поверхах
    F, B = (0,), (10,)
    blown = {("back", 1, 1), ("front", 2, 0), ("front", 8, 1), ("back", 9, 2)}
    body(b, X0, max(ends_l), NF, F, B, True, core_end=CL, ends=ends_l)
    windows(b, X0, max(ends_l), NF, F, B, blown=blown, ends=ends_l)
    body(b, min(starts_r), X1, NF, F, B, True, core_start=CR, starts=starts_r)
    windows(b, min(starts_r), X1, NF, F, B, blown=blown, starts=starts_r)
    wing(b, rnd, 1, tgw)
    wing(b, rnd, -1, tgw)
    facade_breaks(b, rnd, 1)
    facade_breaks(b, rnd, -1)
    entrances(b, CL - 0.5)
    entrances(b, X1, CR - 1.0)
    roof_details(b, CL - 0.5)
    roof_details(b, X1, CR - 1.0)
    CHECKS["furniture"] = CHECKS.get("furniture", 0) + 2
    # завал (у локальній системі язика)
    before = set(b.bm.verts)
    tg.build(b, hrnd)
    hf = Heights(tg)
    n0 = len(CHECKS["slabs"])
    # тіло купи: дрібняк і шматки 0.3-1.5 м, світло-сірі, густо по всьому язику
    placed = 0
    for _ in range(900):
        if placed >= 95:
            break
        x, y = hrnd.uniform(XL - 4.0, XL + 8.5), hrnd.uniform(-9.5, 9.5)
        h0 = 0.85 * tg.h(x, y)
        if abs(y) > tg.half(x - XL) + (0.5 if x >= XL else -0.5) or (h0 < 0.25 and hrnd.random() < 0.8):
            continue
        sz = 0.5 + (hrnd.random() ** 1.9) * 0.9
        c = (x, y, h0 + sz * 0.12)
        rubble(b, hrnd, c, sz, "heap_light_dm", tone=(0.55, 1.3))
        hf.raise_disc(x, y, sz * 0.45, c[2] + sz * 0.3)
        placed += 1
    big = ((2.4, -4.6, 0.3, 34, 5.2, 2.8), (3.0, 0.2, -0.5, 46, 5.0, 2.6), (2.2, 4.4, 0.9, 28, 4.8, 2.6), (4.6, -1.8, 1.1, 42, 4.0, 2.4),
           (4.8, 2.6, -1.0, 38, 3.8, 2.2), (6.2, -4.4, 0.2, 30, 3.6, 2.2), (6.4, 4.8, -0.4, 26, 3.6, 2.2))
    for (dx, y, yaw, th_, L, W) in big:
        drop(b, hrnd, hf, XL + dx, y, yaw, th_, L, W, hrnd.uniform(0.15, 0.2), "slab_light_dm", "slab", sink=0.35, rebar=0.15)
    for (dx, y, yaw, th_) in ((5.4, -6.0, 0.5, 34), (5.6, 1.2, -0.7, 27), (3.6, -6.4, 0.2, 40), (4.4, 6.2, -0.6, 30), (6.8, -0.8, 1.2, 36)):
        drop(b, hrnd, hf, XL + dx, y, yaw, th_, 3.0, 2.8, hrnd.uniform(0.16, 0.2), "frag_light_dm", "panel", sink=0.3, rebar=0.3)
    for rec in CHECKS["slabs"][n0:]:
        rec["heap"] = True
    for i in range(10):                                             # дрібний розсип далі від язика
        x = hrnd.uniform(XL + 7.5, XL + 11.0)
        y = hrnd.uniform(-1.0, 1.0) * (tg.half(x - XL) - 0.8)
        sz = hrnd.uniform(0.44, 0.8)
        rubble(b, hrnd, (x, y, sz * 0.12), sz, "heap_light_dm", tone=(0.8, 1.25))
        CHECKS["scatter"].append(x - XL)
    apron(b, tg)
    CHECKS["heap_verts"] = [v for v in b.bm.verts if v not in before]
    validate(tg)
    for v in CHECKS["heap_verts"]:                                  # поворот язика на 90°: спуск +x -> +Y моделі, поперечна вісь -> X через XCEN
        xl, yl = v.co.x, v.co.y
        v.co.x, v.co.y = XCEN - yl, YF + (xl - XL)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=4600, footprint=(4, 3), anchor=(0, 6.0), ground_clip=True, ao=0.45)


def validate(tg):
    """Кожна вимога до завалу й пролому — перевірка на побудованій геометрії; порушення валить збирання."""
    import numpy as np
    hv = [v for v in CHECKS["heap_verts"] if v.is_valid]
    top = max(v.co.z for v in hv)
    assert 3.0 <= top <= 4.6, f"висота купи {top:.2f} м поза 3-4.6"
    wall_h = max(v.co.z for v in hv if abs(v.co.x - XL) <= 1.0)
    assert wall_h >= 2.5, f"біля стіни купа лише {wall_h:.2f} м"
    reach = max(v.co.x for v in hv) - XL
    assert 8.0 <= reach <= 12.0, f"виліт купи {reach:.1f} м поза 8-12"
    assert min(v.co.x for v in hv) >= XL - 5.1, "завал виходить углиб будинку за межу кімнат"
    side = [round(v.co.y, 1) for v in hv if v.co.z > 0.1 and v.co.x < XL and abs(v.co.y) > 7.0]        # всередині пролому (13 м) уламки лише між крилами
    assert not side, f"уламки з боків будинку далі ніж на 1 м від стіни {side[:5]}"
    dense = max(d for d in [i * 0.05 for i in range(0, 400)] if tg.base(d) > 0.3)       # де оболонка ще вища за 0.3 м
    assert 6.0 <= dense <= 8.0, f"щільна частина {dense:.1f} м, треба ~7"
    hs = [c for c in CHECKS["slabs"] if c["heap"]]
    big = panels = 0
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
            big += 1 if (c["kind"] == "slab" and c["L"] >= 3.0 and c["W"] >= 1.2) else 0
            panels += 1 if c["kind"] == "panel" else 0
    assert 6 <= big <= 8, f"великих плит {big}: треба 6-8"
    assert panels >= 4, f"шматків панелей {panels}"
    vis = sum(1 for c in hs if c["kind"] == "slab" and c["L"] > 3.0 and c["ft"].normal.x > 0.05)
    assert vis + len(CHECKS["ramps"]) >= 6, f"з камери видно лише {vis} довгих плит"
    assert sum(1 for c in hs if c["ang"] <= 36.0) >= 0.25 * len(hs)
    exts = []
    for verts, rot, dims in CHECKS["boulders"]:
        loc = [rot.transposed() @ Vector(v.co) for v in verts]
        ext = sorted(max(p[i] for p in loc) - min(p[i] for p in loc) for i in range(3))
        assert 0.3 <= ext[2] <= 1.5, f"шматок {ext}"
        assert ext[2] / max(ext[0], 0.05) <= 3.6, "шматок-голка"
        exts.append(ext)
    for dia, v in CHECKS["rods"]:
        assert 0.01 <= dia <= 0.02, f"діаметр прута {dia}"
        assert math.degrees(math.asin(abs(v.normalized().z))) <= 60.0, "прут стирчить сторч"
    assert min(CHECKS["stubs"]) >= 0.2 and SLAB_TH >= 0.2, "торець перекриття тонший за 0.2 м"
    assert len(CHECKS["partitions"]) == 2 * NF and all(2 <= n <= 3 for n in CHECKS["partitions"].values()), "стін у клітинках 2-3"
    assert CHECKS["ceilings"] == 2 * NF and CHECKS["furniture"] >= 3 and CHECKS["cells"] == 4 * NF
    est = 255 * (1.055 * (CAV_LIN * 0.47) ** (1 / 2.4) - 0.055)      # 0.47 — зміряно під світлом Річки: альбедо 0.03 дало sRGB 32
    assert 60 <= est <= 80, f"нутро кімнат на екрані під Річкою ~{est:.0f}: ціль 60-80"
    # пролом: жодного плаского перекриття далі 2 м від стіни, рампи 25-40, звис даху, зріз даху, зріз фасаду
    assert all(1.0 <= f <= 2.0 for f in CHECKS["flats"]) and len(CHECKS["flats"]) == 2 * NF, f"пласка частина перекриття від стіни {CHECKS['flats']}: має бути 1-2 м"
    assert len(CHECKS["ramps"]) == 2 * 3
    for r in CHECKS["ramps"]:
        r["ft"].normal_update()
        ang = math.degrees(math.acos(abs(r["ft"].normal.z)))
        assert 25.0 <= ang <= 40.0, f"рампа {ang:.1f}° поза 25-40"
        r["ang"] = ang
    assert len(CHECKS["droops"]) == 2
    for dr in CHECKS["droops"]:
        dr["ft"].normal_update()
        dang = math.degrees(math.acos(abs(dr["ft"].normal.z)))
        dover = max((v.co.x - dr["hinge_x"]) * dr["sgn"] for v in dr["top"])
        assert 15.0 <= dang <= 30.0 and 1.0 <= dover <= 2.0, f"звис даху {dang:.1f}° {dover:.2f} м"
    for sgn, vs in CHECKS["roof_verts"].items():
        edge = max((v.co.x - (CL if sgn > 0 else CR)) * sgn for v in vs)
        top_end = (REL_L if sgn > 0 else REL_R)[NF - 1]
        assert 1.0 <= top_end - edge <= 1.5, f"плита даху крила {sgn} зрізана на {top_end - edge:.2f} м, треба 1-1.5"
    assert len(CHECKS["protr"]) == 4 * NF and all(3 <= len(g) <= 5 and all(0.3 <= x <= 0.8 for x in g) for g in CHECKS["protr"]), f"виступи зрізу фасаду {CHECKS['protr']}"
    assert CHECKS["bundles"] and all(0.05 <= w <= 0.08 for w in CHECKS["bundles"]), "пучок арматури 5-8 см"
    assert CHECKS["apron"] > 20 and CHECKS["floor_rubble"] >= 2 * (NF - 1)
    print("MEAS heap_top_m=%.2f at_wall=%.2f reach=%.1f dense=%.1f slabs=%d (big=%d panels=%d) tilt=%.0f..%.0f ramps=%s" % (
        top, wall_h, reach, dense, len(hs), big, panels, min(c["ang"] for c in hs), max(c["ang"] for c in hs), [round(r["ang"]) for r in CHECKS["ramps"]]))
    print("MEAS flats_m=%s chunks=%d dims=%.2f..%.2f rods=%d apron_cells=%d" % ([round(f, 2) for f in CHECKS["flats"]], len(exts), min(e[2] for e in exts), max(e[2] for e in exts), len(CHECKS["rods"]), CHECKS["apron"]))


if os.environ.get("BLOCK_ONLY") != "damaged":
    intact()
damaged()
