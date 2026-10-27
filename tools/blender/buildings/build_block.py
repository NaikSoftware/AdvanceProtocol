"""H5: панельна п'ятиповерхівка 33 x 12 м із лоджіями, що врізані в фасад, і її пошкоджений варіант (обвалилась середня секція)."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
import heap_sim
from mathutils import Vector, Matrix
import bmesh
import bpy
from lib import Builder, chunks, mound, wall_run, burn_ring, panel_wall, opening2, chip_slab, HeapSurface, heap_mound

out = lib.out_dir()
LEN, DEP, FLOOR, NF = 57.0, 12.0, 3.1, 5
NB = int(LEN / 3.0)      # 19 секцій по 3 м
H = FLOOR * NF           # 15.5 м до плити даху
X0, X1, Y0, Y1 = -LEN / 2, LEN / 2, -DEP / 2, DEP / 2
STAIRS = (1, 5, 9, 13, 17)       # осі сходових кліток (кроки по 3 м)
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


def body(b, xa, xb, nf, front, back, roof, core_end=None, ends=None, core_start=None, starts=None, broken=()):
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
                if i in broken and f >= 3:                                         # біля пролому верхні лоджії зруйновані: лишається лише ніша
                    continue
                b.box(x, yp, z, 2 * LW, 0.12, 1.1, "panel")                       # парапет лоджії 1.1 м
                yb = ye - LOG * side + 0.01 * side
                b.poly([(x - LW, yb, z), (x + LW, yb, z), (x + LW, yb, z + FLOOR), (x - LW, yb, z + FLOOR)][::-side], "panel_light")
                for sx in (-1, 1):
                    b.box(x + sx * (LW - 0.03), (ya + yb) / 2, z, 0.06, LOG, FLOOR - 0.15, "panel_light")   # впритул до шару фасаду: щілина 5 мм давала чорні крапки по краю лоджії
                if (i * 7 + f * 3 + (1 if side > 0 else 0)) % 2 == 0:                       # засклена лоджія: рама над парапетом
                    b.window(("y", ye - 0.08 * side, side), x, z + 1.15, 2 * LW - 0.06, FLOOR - 1.4)
            for f in range(2, nf):
                if i in broken and f >= 3:
                    continue
                b.box(x, (ya + yb) / 2, f * FLOOR - 0.15, 2 * LW, LOG, 0.15, "panel", top="panel")  # плита між лоджіями
            if nf > 2 and i not in broken:
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
    for k, x in enumerate((-25, -20, -15, -9, 9, 15, 20, 25)):
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
    F, B = (2, 8, 14), (5, 11, 17)
    body(b, X0, X1, NF, F, B, True)
    windows(b, X0, X1, NF, F, B)
    entrances(b, X1)
    roof_details(b, X1)
    # бризки біля цоколя, патьоки під кожним підвіконням і від парапету даху; над відкритими лоджіями стіни немає
    sk = lambda cols: [(bay_x(i) - LW, bay_x(i) + LW) for i in cols]
    lib.weather(b, "panel", [("y", Y1, 1, X0, X1, 0.0, H)], seed=21, patches=False, skip_u=sk(F), seg=1.5, band=0.75, kband=(0.66, 0.72), ksill=(0.55, 0.65), lsill=(1.0, 1.5), eave_streaks=False)
    lib.weather(b, "panel", [("y", Y0, -1, X0, X1, 0.0, H)], seed=22, patches=False, skip_u=sk(B), seg=1.5, band=0.75, kband=(0.66, 0.72), ksill=(0.55, 0.65), lsill=(1.0, 1.5), eave_streaks=False)
    lib.weather(b, "panel", [("x", X1, 1, Y0, Y1, 0.0, H), ("x", X0, -1, Y0, Y1, 0.0, H)], seed=23, patches=False, seg=1.5, band=0.75, kband=(0.66, 0.72), eave_streaks=False)
    lib.finish(b, "h5_panel_block", out, tri_limit=6000, max_px=2048, footprint=(7, 2), anchor=(0, 0))




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
PASTEL = ((192, 186, 172), (186, 184, 176), (178, 182, 180), (196, 186, 170))   # запилені сіро-бежеві стіни кімнат з ледь помітними відтінками
HEAP_TOP = 4.8                        # найвища точка плит, м
TONGUE_HW = 3.6                       # висота купи біля стіни, м
TONGUE_LEN = 7.6                      # щільна частина виходить від фасаду на ~7 м
XL = 6.0                              # площина фасаду в локальній системі язика (спуск уздовж +x), потім повертається на +Y моделі
CAV_LIN = 0.22                        # середнє альбедо стін кімнат (лінійне): під небом Річки дає на екрані sRGB ~90 (L* 55-65)

CHECKS = {"ramps": [], "droops": [], "flats": [], "panels": [], "scatter": [], "apron": 0, "protr": [], "slab_max": {}, "bundles": [], "slabs": [], "boulders": [], "rods": [],
          "heap_verts": [], "stubs": [], "remnants": None, "partitions": {}, "ceilings": 0, "roof_verts": {}, "floor_rubble": 0, "cells": 0}


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


def stripes(b, a, c, z0, z1, nrm, mat, fr=(0.2, 0.5, 0.8)):
    """Шпалери: 2-3 вертикальні смуги темнішого тону на стіні (зсунуті в кімнату на 1 см, щоб не було z-fighting)."""
    ln = math.hypot(c[0] - a[0], c[1] - a[1])
    ux, uy = (c[0] - a[0]) / ln, (c[1] - a[1]) / ln
    o = 0.012
    for f in fr:
        p0, p1 = ln * f - 0.14, ln * f + 0.14
        pts = [(a[0] + ux * p0 + nrm[0] * o, a[1] + uy * p0 + nrm[1] * o, z0), (a[0] + ux * p1 + nrm[0] * o, a[1] + uy * p1 + nrm[1] * o, z0),
               (a[0] + ux * p1 + nrm[0] * o, a[1] + uy * p1 + nrm[1] * o, z1), (a[0] + ux * p0 + nrm[0] * o, a[1] + uy * p0 + nrm[1] * o, z1)]
        b.decal(pts, [0.62, 0.62, 0.5, 0.5], mat, nrm)
    CHECKS["stripes"] = CHECKS.get("stripes", 0) + len(fr)


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
                rubble(b, rnd, (X(rnd.uniform(0.4, xe - 0.8)), rnd.uniform(-3.8, 3.8), z_top + sz * 0.25), sz, "heap_rubble_dm", flat=0.5)
                CHECKS["floor_rubble"] += 1
        if k == NF:
            CHECKS["roof_verts"][sgn] = [v for v in b.bm.verts if v not in before_k and any(f.material_index != rs_ for f in v.link_faces)]   # без прутів арматури
    # перекриття, що звисають рампою зі зламом посередині: перший відрізок 26-28°, далі крутіше 37-38°, край рваний
    for k in RAMPS[sgn]:
        for (yc, wd, a1, a2) in ((-3.0, 3.1, 26.0, 37.0), (2.9, 3.3, 28.0, 38.0)):
            d1, s1, t1, n1 = slab_frame(0.0 if sgn > 0 else math.pi, a1)
            d2, s2, t2, n2 = slab_frame(0.0 if sgn > 0 else math.pi, a2)
            hinge = _v3(X(SLAB_REL[k] - 0.1), yc, k * FLOOR)
            L1 = 2.3
            Lr = 6.0
            for Lq in [L1 + 0.7 + 0.1 * q for q in range(0, 35)]:     # довжина до купи; не дістає — до ~6 м, і шматок висить на арматурі
                e = hinge + s1 * L1 + s2 * (Lq - L1)
                if e.z <= tgw(e.x, yc) + 0.1:
                    Lr = Lq
                    break
            th = 0.22
            L2 = Lr - L1
            pts1 = [(-L1 / 2, -wd / 2), (L1 / 2, -wd / 2 + rnd.uniform(0.0, 0.25)), (L1 / 2 - rnd.uniform(0.1, 0.3), wd / 2), (-L1 / 2, wd / 2)]
            C1 = hinge - n1 * th + s1 * (L1 / 2)
            place_slab(b, pts1, th, C1, s1, t1, n1, "broken_end", "interior_floor", heap=False, kind="ramp")
            hinge2 = hinge + s1 * L1 - n1 * 0.06                      # злам: другий відрізок трохи нижче й крутіше
            pts2 = [(-L2 / 2, -wd / 2), (L2 / 2 - rnd.uniform(0.2, 0.6), -wd / 2), (L2 / 2, -wd / 2 + rnd.uniform(0.5, 1.2)), (L2 / 2 - rnd.uniform(0.1, 0.5), wd / 2), (-L2 / 2, wd / 2)]
            C2 = hinge2 - n2 * th + s2 * (L2 / 2)
            ft, rot = place_slab(b, pts2, th, C2, s2, t2, n2, "broken_end", "interior_floor", heap=False, kind="ramp")
            CHECKS["ramps"][-1]["len"] = Lr
            if k == RAMPS[sgn][0] and yc < 0:
                edge_bundle(b, rnd, pts2, th, C2, rot)
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
        stripes(b, (X(0.05), -YI + OFF), (X(0.05), YI - OFF), zf + 0.4, zc - 0.5, (sgn, 0, 0), "wp%d_dm" % pm, (0.2, 0.5, 0.8))
        for sy in (-1, 1):
            stripes(b, (X(0.05), sy * (YI - OFF)), (X(re - 0.02), sy * (YI - OFF)), zf + 0.4, zc - 0.5, (0, -sy, 0), "wp%d_dm" % pm, (0.3, 0.7) if re > 2.5 else (0.5,))
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


def remnants(b, rnd):
    """Рештки задньої стіни й сходової клітки в проломі заввишки 1-3 поверхи, рваним верхом: крила лишаються одним корпусом."""
    rnd = random.Random(77)                                          # власний потік: симуляція (art-refs/heap_sim) залежить від цих коробок
    x = XA
    hs = []
    boxes = []                                                       # коробки для симуляції: уламки падають на ці рештки й упираються в них
    pat = [2, 1, 3, 1, 2, 3, 1]
    for k in range(40):
        if x >= XB - 0.3:
            break
        w = min(rnd.uniform(1.6, 3.0), XB - x)
        for (xa, wd) in ((x, w * 0.55), (x + w * 0.55, w * 0.45)):          # кожна ділянка — дві частини різної висоти: рваний верх
            fl = pat[k % len(pat)]
            h = fl * FLOOR - rnd.uniform(0.0, 1.2)
            b.box(xa + wd / 2, Y0 + LOG / 2, 0.0, wd + 0.02, LOG, h, "panel", top="broken_end")
            boxes.append((xa, xa + wd, Y0, Y0 + LOG, 0.0, h))
            hs.append(h)
            pat = pat[1:] + pat[:1] if rnd.random() < 0.5 else pat
        x += w
    # сходова клітка: бетонна коробка 3 x 3.2 м, одна половина вища
    sx = -1.5
    h1, h2 = 2 * FLOOR - 0.4, 3 * FLOOR - 0.7
    b.box(sx + 0.75, Y0 + LOG + 1.6, 0.0, 1.5, 3.2, h1, "panel", top="broken_end")
    b.box(sx + 2.25, Y0 + LOG + 1.6, 0.0, 1.5, 3.2, h2, "panel", top="broken_end")
    boxes += [(sx, sx + 1.5, Y0 + LOG, Y0 + LOG + 3.2, 0.0, h1), (sx + 1.5, sx + 3.0, Y0 + LOG, Y0 + LOG + 3.2, 0.0, h2)]
    CHECKS["remnants"] = (hs, h1, h2)
    return boxes


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
        self.hum = [(XL + rnd.uniform(-7.0, 5.0), rnd.uniform(-5.0, 5.0), rnd.uniform(0.3, 0.7)) for _ in range(10)]

    def half(self, d):
        return 6.9 if d < 0 else 6.9 + 0.26 * d           # усередині пролому — на всю його ширину (13 м), назовні розширюється до ~17 м

    def base(self, d):
        if d < -10.8:
            return 0.0                                      # далі — решта задньої стіни
        if d < -4.0:
            return 3.0 + 1.2 * _smooth((d + 10.8) / 6.8)
        if d < 0.0:
            return 4.2 - (4.2 - TONGUE_HW) * _smooth((d + 4.0) / 4.0)
        return TONGUE_HW * max(0.0, 1 - d / TONGUE_LEN) ** 1.15

    def h(self, x, y):
        d = x - XL
        w = self.half(d)
        lat = _smooth((w - abs(y)) / (0.8 + 1.4 * _smooth(d / 2.0)))
        hum = sum(a * math.exp(-((x - px) ** 2 + (y - py) ** 2) / (2 * 1.2 ** 2)) for px, py, a in self.hum)
        return max(0.0, (self.base(d) * (1 + 0.16 * _wob(x, y, self.ph)) + hum * min(1.0, max(0.0, 1 - d / TONGUE_LEN))) * lat)

    def build(self, b, rnd, mat="heap_rubble"):
        """Оболонка під уламками: нерівна сітка, нижча за верх плит і шматків."""
        xs = [XL - 11.2 + 1.6 * i for i in range(13)]
        ys = [-9.8 + 1.4 * j for j in range(15)]
        vs, fs, cnt = {}, [], {}
        for i, x0 in enumerate(xs):
            for j, y0 in enumerate(ys):
                x = x0 + (rnd.uniform(-0.3, 0.3) if 0 < i < len(xs) - 1 else 0.0)
                y = y0 + (rnd.uniform(-0.3, 0.3) if 0 < j < len(ys) - 1 else 0.0)
                hz = 0.8 * self.h(x, y)
                vs[i, j] = b.bm.verts.new((x, y, max(0.0, hz + rnd.uniform(-0.3, 0.3) * min(1.0, hz))))      # граняста, а не гладка оболонка
        for i in range(len(xs) - 1):
            for j in range(len(ys) - 1):
                q = [vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]]
                if all(v.co.z < 0.02 for v in q):
                    continue
                for v in q:
                    cnt[v] = cnt.get(v, 0) + 1                      # скільки клітинок оболонки спільні вершині
                if rnd.random() < 0.5:
                    q = q[1:] + q[:1]
                fs += [b.bm.faces.new((q[0], q[1], q[2])), b.bm.faces.new((q[0], q[2], q[3]))]
        for v, c in cnt.items():                                    # край оболонки лягає на землю: без вертикального борту
            if c < 4 and v.co.z > 0.0 and v.co.x > XL - 0.5 and abs(v.co.y) > 0.0:
                v.co.z = 0.0
        for f in fs:
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
        b._finish(fs, mat)


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
        lib._quad(b, [(x0, y0, 0.06), (x1, y1, 0.035), (x3, y3, 0.035), (x2, y2, 0.06)], "debris_apron", (0, 0, 1))
        cnt += 1
    CHECKS["apron_ring"] = cnt


SIM_SEED = 11
MOUND_K = 0.28                         # пагорб дрібної фракції під уламками — частка від повної висоти язика; решту набирають уламки


def sim_boxes(rem):
    """Нерухомі коробки симуляції: цілі крила (стіни пролому) й рештки задньої стіни із сходовою кліткою."""
    return [(-40.0, XA, Y0, Y1, 0.0, H), (XB, 40.0, Y0, Y1, 0.0, H)] + list(rem)


def _hash_pick(i, j):
    return ((i * 73856093) ^ (j * 19349663)) & 1


def load_sim(boxes, mh):
    """Результат хвиль симуляції (heap_sim.py, кожна хвиля окремим запуском Blender) із art-refs/heap_sim; світ задає world.json.
    Немає результату чи світ змінився — світ записується заново, а хвилі треба прогнати (`HEAP_WORLD_ONLY=1`, далі heap_sim.sh)."""
    import json
    import pickle
    import subprocess
    d = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "art-refs", "heap_sim"))
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, ".gdignore"), "a").close()                     # .blend між хвилями не має потрапити в імпорт Godot (він падає без шляху до Blender)
    gx0, gx1, gy0, gy1, st = -9.0, 9.0, -6.0, 20.0, 0.5
    nx, ny = int(round((gx1 - gx0) / st)) + 1, int(round((gy1 - gy0) / st)) + 1
    world = dict(seed=SIM_SEED, boxes=[list(bx) for bx in boxes], grid=[gx0, gx1, gy0, gy1, st], regions={"1": [-4.6, 4.6, 0.6, 4.6, 6.4, 8.0, 0.2], "2": [-4.8, 4.8, -1.0, 5.0, 6.4, 8.6, 0.25], "3": [-4.2, 4.2, -0.5, 4.8, 6.4, 8.6, 0.25],
                 "4": [-5.4, 5.4, -3.0, 5.0, 6.4, 9.5, 0.3], "5": [-5.4, 5.4, -3.0, 5.0, 6.4, 9.5, 0.3], "6": [-5.4, 5.4, -3.0, 5.0, 6.4, 9.5, 0.3]},
                 heights=[round(mh(gx0 + i * st, gy0 + j * st), 3) for j in range(ny) for i in range(nx)], version=4)
    wp = os.path.join(d, "world.json")
    same = os.path.exists(wp) and json.load(open(wp)) == json.loads(json.dumps(world))
    done = all(os.path.exists(os.path.join(d, "pieces_%d.pkl" % k)) for k in (1, 2, 3, 4, 5, 6))
    if not (same and done):
        for f in os.listdir(d):
            if f != ".gdignore":
                os.remove(os.path.join(d, f))
        json.dump(world, open(wp, "w"))
        if os.environ.get("HEAP_WORLD_ONLY"):
            print("WORLD", wp)
            raise SystemExit(0)
        for k in range(0, 7):                                        # кожна хвиля — окремий запуск Blender
            subprocess.run([bpy.app.binary_path, "-b", "--factory-startup", "--python", heap_sim.__file__, "--", str(k), d], check=True, timeout=175)
    pcs = []
    for k in (1, 2, 3, 4, 5, 6):
        pcs += pickle.load(open(os.path.join(d, "pieces_%d.pkl" % k), "rb"))
    return {"pieces": pcs}


def heap_from_sim(b, tg, tgw, boxes, rnd):
    """Завал із симуляції. 300-600 тіл падають із висоти пролому на пагорб: частина лягає всередині контуру секції, частина виштовхнута назовні
    з боку фасаду. Що лягло — стає високополігональною купою hi (для запікання нормалі, AO й кольору); у модель іде низькополігональна оболонка
    (висотна сітка ~1500-2000 трикутників), 4-6 найбільших плит окремою геометрією (втоплені в масу на 30-60 % під кутом 15-45°) і дрібний розсип."""
    import heap_sim
    from mathutils.bvhtree import BVHTree
    mh = lambda x, y: MOUND_K * tgw(x, y)
    res = load_sim(boxes, mh)
    pcs = res["pieces"]
    vol = 0.0
    for d in pcs:
        M = Matrix(d["matrix"])
        d["matrix"] = M
        bmv = bmesh.new()
        vv = [bmv.verts.new(v) for v in d["verts"]]
        for f in d["faces"]:
            try:
                bmv.faces.new([vv[i] for i in f])
            except ValueError:
                pass
        d["vol"] = abs(bmv.calc_volume())
        bmv.free()
        vol += d["vol"]
        d["wv"] = [M @ Vector(v) for v in d["verts"]]
        d["c"] = M.translation.copy()
        d["tilt"] = math.degrees(math.acos(min(1.0, abs(M.col[2].z))))
    # відсів: тіла, що провалились чи відлетіли, плити сторч і все далі ~1.5 м від щільної купи (на краю лишається рідкий розсип)
    n_all = len(pcs)
    for d in pcs:
        d["top"] = max(v.z for v in d["wv"])
    pcs[:] = [d for d in pcs if d["c"].z > -0.3 and abs(d["c"].x) < 8.8 and -5.0 < d["c"].y < 19.0 and d["top"] < (5.2 if d["kind"] == "slab" else 5.4)
              and not (d["kind"] == "slab" and d["tilt"] > 55.0)]
    cellz = {}
    for d in pcs:
        k_ = (int(math.floor(d["c"].x)), int(math.floor(d["c"].y)))
        cellz.setdefault(k_, []).append(d["top"])
    dense = [k_ for k_, v in cellz.items() if len(v) >= 6 and max(v) > 1.0]
    pcs[:] = [d for d in pcs if any(math.hypot(d["c"].x - (kx + 0.5), d["c"].y - (ky + 0.5)) <= 2.0 for kx, ky in dense)]
    vol = sum(d["vol"] for d in pcs)
    CHECKS["culled"] = n_all - len(pcs)
    rk = [max(d["size"]) for d in pcs if d["kind"] == "rock"]
    CHECKS["sim"] = dict(slabs=sum(1 for d in pcs if d["kind"] == "slab"), panels=sum(1 for d in pcs if d["kind"] == "panel"), total=len(pcs),
                         holes=sum(1 for d in pcs if d.get("hole")), boulders=sum(1 for r in rk if r >= 0.8), chunks=sum(1 for r in rk if 0.3 <= r < 0.8),
                         fines=sum(1 for r in rk if r < 0.3), volume=round(vol, 1))
    # який шматок плит лишається окремою геометрією: найбільші, що лягли під 15-45°, горизонт найвище
    cand = sorted((d for d in pcs if d["kind"] == "slab" and 15.0 <= d["tilt"] <= 45.0 and d["c"].y > -4.5 and d["c"].z > 0.5), key=lambda d: -d["size"][0] * d["size"][1])
    kept = cand[:6]
    if len(kept) < 4:
        kept = sorted((d for d in pcs if d["kind"] == "slab" and 10.0 <= d["tilt"] <= 50.0), key=lambda d: -d["size"][0] * d["size"][1])[:4]
    for d in kept:
        d["kept"] = True
    # висотна карта купи без плит, що лишаються окремо
    nx, ny = int((9.0 - -9.0) / 0.4) + 1, int((20.0 - -6.0) / 0.4) + 1
    mv, mf = [], []
    for j in range(ny):
        for i in range(nx):
            x, y = -9.0 + i * 0.4, -6.0 + j * 0.4
            mv.append(Vector((x, y, mh(x, y))))
    for j in range(ny - 1):
        for i in range(nx - 1):
            a = j * nx + i
            if max(mv[a].z, mv[a + 1].z, mv[a + nx].z, mv[a + nx + 1].z) < 0.01:
                continue
            mf.append((a, a + 1, a + nx + 1, a + nx))
    poly_v, poly_f = [], []                                          # пагорб-носій в оболонку не йде: лише тіла, що лягли; пагорб потрібен тільки як основа для запікання
    for d in pcs:
        if d.get("kept"):
            continue
        base = len(poly_v)
        poly_v.extend(d["wv"])
        poly_f.extend([tuple(base + i for i in f) for f in d["faces"]])
    bvh = BVHTree.FromPolygons([tuple(v) for v in poly_v], [tuple(f) for f in poly_f])

    def top_z(x, y):
        h = bvh.ray_cast(Vector((x, y, 40.0)), Vector((0, 0, -1)))
        return h[0].z if h[0] is not None else 0.0

    # втоплення окремих плит: опускаємо, поки 30-60 % їхньої площі не ховається під купою
    import numpy as np
    for d in kept:
        pts = d["outline"]
        M = d["matrix"]
        smp = [M @ Vector((u, v, d["th"] / 2)) for u in np.linspace(-d["size"][0] / 2, d["size"][0] / 2, 9) for v in np.linspace(-d["size"][1] / 2, d["size"][1] / 2, 7)
               if _in_poly(pts, u, v)]
        zs = [top_z(p.x, p.y) for p in smp]
        lo, hi_ = 0.0, 2.0
        for _ in range(14):
            mid = (lo + hi_) / 2
            frac = sum(1 for p, z in zip(smp, zs) if p.z - mid < z - 0.02) / len(smp)
            lo, hi_ = (mid, hi_) if frac < 0.38 else (lo, mid)
        d["dz"] = (lo + hi_) / 2
        d["buried"] = sum(1 for p, z in zip(smp, zs) if p.z - d["dz"] < z - 0.02) / len(smp)
        d["wv"] = [v - Vector((0, 0, d["dz"])) for v in d["wv"]]
        d["c"] = d["c"] - Vector((0, 0, d["dz"]))
    CHECKS["kept"] = kept
    # низькополігональна оболонка: висотна сітка променями зверху
    step = 0.5
    gx0, gx1, gy0, gy1 = -7.6, 7.6, -5.2, 18.6
    nx, ny = int((gx1 - gx0) / step) + 1, int((gy1 - gy0) / step) + 1
    z = [[0.0] * ny for _ in range(nx)]
    for i in range(nx):
        for j in range(ny):
            x, y = gx0 + i * step, gy0 + j * step
            z[i][j] = max(top_z(x + dx, y + dy) for dx, dy in ((0, 0), (0.28, 0.28), (-0.28, 0.28), (0.28, -0.28), (-0.28, -0.28)))   # огинаюча: порожнини між тілами не продавлюють оболонку
    zz = [[z[i][j] if 0 < i < nx - 1 and 0 < j < ny - 1 else z[i][j] for j in range(ny)] for i in range(nx)]
    for i in range(1, nx - 1):                                        # одне згладжування: промені не мають ловити кожен окремий шип
        for j in range(1, ny - 1):
            zz[i][j] = 0.7 * z[i][j] + 0.3 * (z[i - 1][j] + z[i + 1][j] + z[i][j - 1] + z[i][j + 1]) / 4.0
    vs, cnt, fs = {}, {}, []
    for i in range(nx):
        for j in range(ny):
            vs[i, j] = b.bm.verts.new((gx0 + i * step, gy0 + j * step, zz[i][j]))
    for i in range(nx - 1):
        for j in range(ny - 1):
            q = [vs[i, j], vs[i + 1, j], vs[i + 1, j + 1], vs[i, j + 1]]
            if max(v.co.z for v in q) < 0.12:
                continue
            for v in q:
                cnt[v] = cnt.get(v, 0) + 1
            if _hash_pick(i, j):
                q = q[1:] + q[:1]
            fs += [b.bm.faces.new((q[0], q[1], q[2])), b.bm.faces.new((q[0], q[2], q[3]))]
    for v, c in cnt.items():                                          # край оболонки лягає на землю, крім місць, де купа впирається у стіни будівлі
        near_wall = (abs(v.co.x) > 6.0 and v.co.y < 6.6) or v.co.y < -4.4
        if c < 4 and not near_wall:
            v.co.z = 0.0
    for f in fs:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    b._finish(fs, "heap_grey")
    CHECKS["shell_tris"] = len(fs)
    # плити, що лишились окремо
    for d in kept:
        M = d["matrix"]
        s_, t_, n_ = M.col[0].xyz.copy(), M.col[1].xyz.copy(), M.col[2].xyz.copy()
        pts = list(d["outline"])
        th = d["th"]
        P = d["c"].copy()
        if n_.z < 0:                                                  # плита лягла догори дном: верх — інший бік тієї ж призми
            s_, n_ = -s_, -n_
            pts = [(-x, y) for x, y in pts]
            P = P + (M.col[2].xyz) * (th / 2)
        else:
            P = P - n_ * (th / 2)
        rot = Matrix((s_, t_, n_)).transposed()
        ft, rot2 = place_slab(b, pts, th, P, s_, t_, n_, "slab_light_dm", "slab_light_dm", kind="slab")
        rec = CHECKS["slabs"][-1]
        rec["L"], rec["W"], rec["heap"] = d["size"][0], d["size"][1], True
        d["rec"] = rec
        edge_bundle(b, rnd, pts, th, P, rot2)
    # дрібний розсип: тіла, що відлетіли за межі оболонки, лишаються окремими шматками
    far = [d for d in pcs if d["kind"] != "slab" and not d.get("kept") and top_z(d["c"].x, d["c"].y) < d["c"].z - 0.35 and d["c"].z > 0.12][:40]
    for d in far:
        sz = max(d["size"])
        if 0.3 <= sz <= 1.5:
            rubble(b, rnd, (d["c"].x, d["c"].y, d["c"].z), sz, "heap_rubble_dm", tone=(0.8, 1.2))
            CHECKS["scatter"].append(d["c"].y - YF)
    # найбільші брили лишаються окремою низькополігональною геометрією над оболонкою: середня фракція читається в силуеті
    bigs = sorted((d for d in pcs if d["kind"] == "rock" and not d.get("kept") and max(d["size"]) >= 0.8 and d["c"].z > 0.5), key=lambda d: -d["top"])[:45]
    for d in bigs:
        rubble(b, rnd, (d["c"].x, d["c"].y, d["c"].z), max(d["size"]) * 0.95, "heap_rubble_dm", tone=(0.85, 1.3), flat=0.7)
    CHECKS["bigs"] = len(bigs)
    # фартух concrete_debris навколо контуру оболонки: смуга від краю купи на ~1.5 м, зовнішній край хвилястий
    def shell_h(x, y):
        i, j = int(round((x - gx0) / step)), int(round((y - gy0) / step))
        return zz[i][j] if 0 <= i < nx and 0 <= j < ny else 0.0
    cells_ = [(gx0 + i * step, gy0 + j * step) for i in range(nx) for j in range(ny) if zz[i][j] > 0.5 and gy0 + j * step > 4.0]
    ccx = sum(c[0] for c in cells_) / len(cells_)
    ccy = sum(c[1] for c in cells_) / len(cells_)
    ring, n_ap = [], 44
    for i in range(n_ap + 1):
        a_ = 2 * math.pi * (i % n_ap) / n_ap
        ca, sa = math.cos(a_), math.sin(a_)
        r_ = 0.0
        while r_ < 16.0 and shell_h(ccx + ca * r_, ccy + sa * r_) > 0.1:
            r_ += 0.1
        out_ = r_ + 1.5 * (1.0 + 0.3 * _wob(ca * 3, sa * 3, tg.ph))
        ring.append(((ccx + ca * (r_ - 0.3), ccy + sa * (r_ - 0.3)), (ccx + ca * out_, ccy + sa * out_)))
    na = 0
    for (p0, q0), (p1, q1) in zip(ring, ring[1:]):
        pts4 = [p0, q0, q1, p1]
        if any(y_ < Y1 + 0.3 for _, y_ in pts4):                      # всередині контуру будинку фартуха немає
            continue
        lib._quad(b, [(p0[0], p0[1], 0.06), (q0[0], q0[1], 0.035), (q1[0], q1[1], 0.035), (p1[0], p1[1], 0.06)], "debris_apron", (0, 0, 1))
        na += 1
    CHECKS["apron_ring"] = na
    # купки уламків на перекриттях 2-4 поверху з окремої симуляції
    fv0 = set(b.bm.verts)
    stubs, boxes2 = [], []
    for sgn in (1, -1):
        core = CL if sgn > 0 else CR
        boxes2.append((core - 40.0 if sgn > 0 else core, core if sgn > 0 else core + 40.0, Y0, Y1, 0.0, H))
        for k in (1, 2, 3):
            x0_, x1_ = sorted((core + sgn * 0.1, core + sgn * (SLAB_REL[k] - 0.3)))
            stubs.append((x0_, x1_, -YI, YI, k * FLOOR, 3))
    fres = heap_sim.simulate(SIM_SEED + 1, lambda x, y: 0.0, boxes2, (0, 1, 0, 1, 20, 21, 20.0, 0.0), (0, 0, 0), frames=70, floor_stubs=stubs)
    nfl = 0
    for d in fres["floor"]:
        c = d["matrix"].translation
        st = stubs[d["stub"]]
        if st[0] - 0.1 <= c.x <= st[1] + 0.1 and st[4] - 0.05 <= c.z <= st[4] + 0.9:
            rubble(b, rnd, (c.x, c.y, c.z), max(0.3, d["size"][0]), "heap_rubble_dm", tone=(0.8, 1.2))
            nfl += 1
    CHECKS["floor_rubble"] = nfl
    CHECKS["floor_verts"] = set(v for v in b.bm.verts if v not in fv0)
    # висока поліґональна купа для запікання
    hi = Builder()
    mfaces = []
    mvs = [hi.bm.verts.new(v) for v in mv]
    for f in mf:
        mfaces.append(hi.bm.faces.new([mvs[i] for i in f]))
    hi._finish(mfaces, "heap_base_rubble")
    for d in pcs:
        slot = {"slab": "slab_light_dm", "panel": "frag_light_dm", "rock": "heap_rubble_dm"}[d["kind"]]
        vs_ = [hi.bm.verts.new(v) for v in d["wv"]]
        tn = rnd.uniform(0.8, 1.25)
        fl = []
        for f in d["faces"]:
            try:
                fl.append(hi.bm.faces.new([vs_[i] for i in f]))
            except ValueError:
                pass
        hi._finish(fl, slot)
        for f in fl:
            for lp in f.loops:
                lp[hi.wtone] = (tn, tn, tn, 1.0)
    return hi


def _in_poly(pts, x, y):
    c = False
    for i in range(len(pts)):
        (x1, y1), (x2, y2) = pts[i - 1], pts[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def preview_hi(hi, path):
    """Знімає високополігональну купу з камери, схожої на ігрову (ортографічно, 45° по азимуту, нахил ~50°)."""
    import bpy
    me = bpy.data.meshes.new("hi_prev")
    hi.bm.to_mesh(me)
    ob = bpy.data.objects.new("hi_prev", me)
    bpy.context.scene.collection.objects.link(ob)
    cols = {"slab_light_dm": (0.7, 0.7, 0.7, 1), "frag_light_dm": (0.55, 0.55, 0.5, 1), "heap_rubble_dm": (0.4, 0.38, 0.36, 1), "heap_base_rubble": (0.3, 0.29, 0.28, 1)}
    for sl in hi.slots:
        m = bpy.data.materials.new(sl)
        m.diffuse_color = cols.get(sl, (0.5, 0.5, 0.5, 1))
        me.materials.append(m)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.render.resolution_x, sc.render.resolution_y = 1400, 900
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 26
    sc.collection.objects.link(cam)
    cam.location = (0.0 + 40 * math.sin(math.radians(45)) * math.cos(math.radians(50)) * -1, 6.0 + 40 * math.cos(math.radians(45)) * math.cos(math.radians(50)) * 1, 40 * math.sin(math.radians(50)))
    d = Vector((0.0, 6.0, 1.5)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", path)


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
    M["heap_light"] = lib.make_material("heap_light", "Concrete034", 2.0, (0.60, 0.59, 0.57), streak=0.3, base_dirt=0.4, bump=0.05)           # світло-сірий дрібняк завалу
    M["slab_light"] = lib.make_material("slab_light", "Concrete034", 1.2, (0.78, 0.76, 0.73), streak=0.9, streak_xy=1.6, base_dirt=0.5, bump=0.03, patch=((0.12, 0.11, 0.10), 0.25))
    M["frag_light"] = lib.make_material("frag_light", "Concrete034", 1.2, (0.70, 0.68, 0.65), streak=1.0, streak_xy=1.6, base_dirt=0.6, bump=0.03, patch=((0.10, 0.09, 0.08), 0.25))
    M["heap_rubble"] = lib.make_material("heap_rubble", "rubble", 2.0, (1.12, 1.02, 0.90), bump=0.07, rough=0.95, streak=0.2)
    M["heap_base_rubble"] = lib.make_material("heap_base_rubble", "rubble", 2.0, (1.12, 1.02, 0.90), bump=0.07, rough=0.95, streak=0.2)    # Poly Haven rubble, повтор 2 м, тон майже нейтральний
    M["debris_apron"] = lib.make_material("debris_apron", "concrete_debris", 2.0, (0.92, 0.84, 0.74), bump=0.05, rough=0.95)    # Poly Haven concrete_debris навколо язика
    M["panel_warm"] = lib.make_material("panel_warm", "Concrete034", 1.2, (0.98, 0.78, 0.54), seams=[("h", 3.0, 0.04, 0.55), ("z", 3.1, 0.05, 0.5)], streak=0.5, base_dirt=0.6, cells=("x", 3.0, "z", 3.1, 0.19), rough=0.9)   # торець: тепліший бетон, щоб небо не робило його синім
    lib.FLAT.add("rebar")                                                                   # прути: плоский зразок без AO, інакше тонкі призми запікаються чорними
    M["rebar"] = lib.make_material("rebar", flat=(0.13, 0.075, 0.05))
    for nm in ("interior_floor", "heap_light", "slab_light", "frag_light", "heap_rubble"):
        lib._dm(nm)
    b = Builder()
    rnd = random.Random(21)
    hrnd = random.Random(7)
    tg = Tongue(hrnd)
    tgw = lambda x, y: 0.8 * tg.h(XL + (y - YF), XCEN - x)        # поверхня язика в координатах моделі
    ends_l = tuple(CL + r for r in REL_L)
    starts_r = tuple(CR - r for r in REL_R)
    # крила: серцевина + фасадні шари, що обриваються уступами по поверхах
    F, B = (1, 3, 5, 14, 16), ()                                     # п'ять лоджій на одному фасаді; 5-та й 14-та, найближчі до пролому, частково зруйновані
    blown = {("back", 2, 1), ("front", 4, 0), ("front", 14, 1), ("back", 15, 2), ("front", 6, 3)}
    body(b, X0, max(ends_l), NF, F, B, True, core_end=CL, ends=ends_l, broken=(5, 14))
    windows(b, X0, max(ends_l), NF, F, B, blown=blown, ends=ends_l)
    body(b, min(starts_r), X1, NF, F, B, True, core_start=CR, starts=starts_r, broken=(5, 14))
    windows(b, min(starts_r), X1, NF, F, B, blown=blown, starts=starts_r)
    for xe, sg in ((X1, 1), (X0, -1)):                              # обидва торці: тепліший бетон і патьоки (з камери видно той, що стоїть до неї після повороту)
        lib._quad(b, [(xe + 0.006 * sg, Y0, 0.0), (xe + 0.006 * sg, Y1, 0.0), (xe + 0.006 * sg, Y1, H), (xe + 0.006 * sg, Y0, H)], "panel_warm", (sg, 0, 0))
        lib.weather(b, "panel", [("x", xe, sg, Y0, Y1, 0.0, H)], seed=23, patches=False, seg=1.5, band=0.75, kband=(0.66, 0.72), eave_streaks=False)
    wing(b, rnd, 1, tgw)
    wing(b, rnd, -1, tgw)
    facade_breaks(b, rnd, 1)
    facade_breaks(b, rnd, -1)
    rem_boxes = remnants(b, rnd)
    entrances(b, CL - 0.5)
    entrances(b, X1, CR - 1.0)
    roof_details(b, CL - 0.5)
    roof_details(b, X1, CR - 1.0)
    CHECKS["furniture"] = CHECKS.get("furniture", 0) + 2
    # завал: симуляція твердих тіл, потім низькополігональна оболонка й кілька плит окремою геометрією
    before = set(b.bm.verts)
    hi = heap_from_sim(b, tg, tgw, sim_boxes(rem_boxes), hrnd)
    if os.environ.get("HEAP_PREVIEW"):                               # кроп купи після симуляції, до запікання
        preview_hi(hi, os.environ["HEAP_PREVIEW"])
        return
    CHECKS["heap_verts"] = [v for v in b.bm.verts if v not in before]
    validate(tg)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=7500, max_px=2048, footprint=(7, 3), anchor=(0, 6.0), ground_clip=True, hi=hi, ao=0.25)


def validate(tg):
    """Кожна вимога до завалу й пролому — перевірка на побудованій геометрії; порушення валить збирання."""
    sim = CHECKS["sim"]
    assert 150 <= sim["boulders"] <= 200 and 500 <= sim["chunks"] <= 800 and 1000 <= sim["fines"] <= 1500, f"склад симуляції {sim}"
    assert 8 <= sim["slabs"] <= 12 and 30 <= sim["panels"] <= 60 and sim["holes"] >= 5, f"склад симуляції {sim}"
    assert sim["volume"] >= 100.0, f"об'єм уламків {sim['volume']} м³ < 100"
    kept = CHECKS["kept"]
    assert 4 <= len(kept) <= 6, f"окремих плит {len(kept)}"
    for d in kept:
        assert 10.0 <= d["tilt"] <= 50.0, f"нахил плити {d['tilt']:.0f}°"
        assert 0.25 <= d["buried"] <= 0.65, f"втоплена плита {d['buried']:.2f}"
        assert 3.0 <= d["size"][0] <= 6.0 and 1.2 <= d["size"][1] <= 3.0 and 0.16 <= d["th"] <= 0.22, f"плита {d['size']} {d['th']}"
    assert 1400 <= CHECKS["shell_tris"] <= 2300, f"трикутників оболонки {CHECKS['shell_tris']}"
    hv = [v for v in CHECKS["heap_verts"] if v.is_valid and v.co.z > 0.1 and v not in CHECKS["floor_verts"]]
    top = max(v.co.z for v in hv)
    assert 3.0 <= top <= 5.2, f"висота купи {top:.2f} м"
    inside = [v.co.z for v in hv if abs(v.co.x) < 5.0 and -3.0 < v.co.y < 5.0]
    assert inside and max(inside) >= 2.5, "пролом не засипано"
    reach = max(v.co.y for v in hv) - Y1
    assert 6.0 <= reach <= 12.5, f"виліт купи {reach:.1f} м"
    side = [(round(v.co.x, 1), round(v.co.y, 1)) for v in hv if (v.co.y < Y1 + 0.5 and abs(v.co.x) > 7.6) or abs(v.co.x) > 10.0]
    assert not side, f"уламки з боків будинку {side[:5]}"
    for dia, v in CHECKS["rods"]:
        assert 0.01 <= dia <= 0.02, f"діаметр прута {dia}"
        assert math.degrees(math.asin(abs(v.normalized().z))) <= 60.0, "прут стирчить сторч"
    assert min(CHECKS["stubs"]) >= 0.2 and SLAB_TH >= 0.2, "торець перекриття тонший за 0.2 м"
    assert len(CHECKS["partitions"]) == 2 * NF and all(2 <= n <= 3 for n in CHECKS["partitions"].values()), "стін у клітинках 2-3"
    assert CHECKS["ceilings"] == 2 * NF and CHECKS["furniture"] >= 3 and CHECKS["cells"] == 4 * NF
    est = 255 * (1.055 * (CAV_LIN * 0.47) ** (1 / 2.4) - 0.055)      # 0.47 — зміряно під світлом Річки: альбедо 0.03 дало sRGB 32
    assert 80 <= est <= 100, f"нутро кімнат на екрані під Річкою ~{est:.0f}: ціль L* 55-65 (sRGB 80-100)"
    assert all(1.0 <= f <= 2.0 for f in CHECKS["flats"]) and len(CHECKS["flats"]) == 2 * NF, f"пласка частина перекриття від стіни {CHECKS['flats']}"
    assert len(CHECKS["ramps"]) == 2 * 3 * 2 and CHECKS["stripes"] >= 2 * NF * 4, "рампи з переломом, смуги шпалер"
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
        assert 1.0 <= top_end - edge <= 1.5, f"плита даху крила {sgn} зрізана на {top_end - edge:.2f} м"
    assert len(CHECKS["protr"]) == 4 * NF and all(3 <= len(g) <= 5 and all(0.3 <= x <= 0.8 for x in g) for g in CHECKS["protr"]), "виступи зрізу фасаду"
    assert CHECKS["bundles"] and all(0.05 <= w <= 0.08 for w in CHECKS["bundles"]), "пучок арматури 5-8 см"
    hs_, h1_, h2_ = CHECKS["remnants"]
    assert hs_ and all(FLOOR - 1.3 <= h_ <= 3 * FLOOR for h_ in hs_) and max(hs_) >= 2 * FLOOR and h2_ >= 2 * FLOOR, f"рештки задньої стіни {hs_}"
    assert CHECKS["apron_ring"] >= 12 and CHECKS["floor_rubble"] >= 6, f"купки на перекриттях {CHECKS['floor_rubble']}"
    print("MEAS culled=%d" % CHECKS["culled"])
    print("MEAS sim=%s kept=%d tilt=%s buried=%s shell_tris=%d top=%.2f reach=%.1f floor_piles=%d scatter=%d" % (
        sim, len(kept), [round(d["tilt"]) for d in kept], [round(d["buried"], 2) for d in kept], CHECKS["shell_tris"], top, reach, CHECKS["floor_rubble"], len(CHECKS["scatter"])))


if os.environ.get("BLOCK_ONLY") != "damaged":
    intact()
damaged()
