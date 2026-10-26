"""Малі будинки на одну клітинку (8 x 8 м) і їхні напівзруйновані двійники: одна функція будує обидва, прапорець ruined лишає
те саме габаритне тіло. Напівзруйновані: стоять майже всі стіни, один кут або секція обвалені, дах частково згорів, у стінах
вибиті вікна й діри від снарядів, дверей немає; завал лише біля обвалу й не виходить за клітинку. Матеріали ті самі, що в цілих
будинків (світла штукатурка, червона цегла в димарі й на зламах, сірі дахи), кіптява й руйнування зверху.
Камера гри бачить боки -Y і +X, тому руйнування скрізь на них. Запуск: build_ruins.py -- <out> [house1 house2 shed]"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, wall_run, burn_ring, opening2, chip_slab, prism, bent_sheet, HeapSurface, heap_mound
from mathutils import Vector

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


def heaps(b, plan, seed, dens=7.0):
    """Купи: низький меш у b, високе скан-джерело для запікання (темна основа, уламки цегли й штукатурки 20-50 см зверху)."""
    bh = Builder()
    hr = random.Random(seed)
    for k, h in enumerate(plan):
        big = h.rx * h.ry > 8
        heap_mound(b, h, "heap_buff", rings=7 if big else 3, segs=32 if big else 16, skirt=0.5, skirt_mat="rubble_buff")
        heap_mound(bh, h, "heap_base_buff", rings=16 if big else 6, segs=96 if big else 40, jitter=0.04, seed=seed + k, skirt=0.5)
        for _ in range(int(math.pi * h.rx * h.ry * dens)):
            a = hr.uniform(0, 2 * math.pi)
            t = math.sqrt(hr.uniform(0, 1.0)) * 1.12
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py) if t < 1.0 else h.lip * max(0.0, 1.0 - (t - 1.0) / 0.12) * 0.8
            q = hr.random()
            size = hr.uniform(0.2, 0.42) if q < 0.7 else (hr.uniform(0.42, 0.6) if q < 0.95 else hr.uniform(0.6, 0.85))
            bh.rock(px, py, z + 0.04, size, "rubble_buff", hr, buried=0.3)
    return bh


def surface(plan):
    return lambda x, y: max(h.z(x, y) for h in plan)


def lumps(b, plan, rnd, n_each=8):
    """Край купи розбитий на грудки цегли й штукатурки 0.3-0.5 м: низькі грані, що стирчать зі схилу й кидають тінь."""
    for h in plan:
        for _ in range(n_each):
            a = rnd.uniform(0, 2 * math.pi)
            t = rnd.uniform(0.55, 1.0)
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py)
            sz = rnd.uniform(0.3, 0.5)
            b.box_e(px, py, z + sz * 0.22, sz * rnd.uniform(0.8, 1.4), sz * rnd.uniform(0.6, 1.0), sz * rnd.uniform(0.4, 0.7),
                    rnd.choice(("brick_face", "wall_plaster", "brick_face", "brick_dark")),
                    euler=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(0, 3.14)))


def plane_soot(b, pts, tones, nrm):
    """Грань кіптяви в площині стіни, нормаллю до nrm; тон — вершинний колір (читається як sRGB)."""
    n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
    if n_.dot(Vector(nrm)) < 0:
        pts, tones = pts[::-1], tones[::-1]
    b.soot(pts, tones, 1)


def roof_break(b, P, cut, sgn, rnd, mat, nv=18, battens=True):
    """Рваний край даху: ступінчастий контур (кожен ряд листів чи черепиці обламаний на свою довжину), вузька кіптява вздовж краю
    й оголені рейки, що стирчать у провал. sgn — у який бік від краю лишився дах."""
    xs = [cut(i / nv) + rnd.uniform(-0.14, 0.14) for i in range(nv)]
    pts = [P(xs[0] + 0.0, 0.0)]
    for i in range(nv):
        pts.append(P(xs[i], i / nv))
        pts.append(P(xs[i], (i + 1) / nv))
    return pts, xs


def roof_part(b, P, x_end, cut, mat, rnd, nv=18, battens=True):
    pts, xs = roof_break(b, P, cut, 1, rnd, mat, nv)
    b.poly_up([P(x_end, 0.0)] + pts + [P(x_end, 1.0)], mat)
    return xs


def break_dress(b, P, xs, sgn, rnd, nv=18):
    """Кіптява вздовж краю (вузька) і рейки 5x4 см, що стирчать за край на 0.2-0.5 м."""
    for i in range(nv):
        v0, v1 = i / nv, (i + 1) / nv
        pts = [P(xs[i], v0), P(xs[i], v1), P(xs[i] + 0.2 * sgn, v1), P(xs[i] + 0.2 * sgn, v0)]
        pts = [(x, y, z + 0.03) for (x, y, z) in pts]
        n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        tones = (0.09, 0.09, 0.3, 0.3)
        if n_.z < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)
    for i in range(1, nv, 2):
        v = (i + 0.5) / nv
        a = P(xs[i] + 0.1 * sgn, v)
        c = P(xs[i] - sgn * rnd.uniform(0.2, 0.5), v)
        b.beam((a[0], a[1], a[2] - 0.05), (c[0], c[1], c[2] - 0.08), 0.05, "timber_dark", 0.04)


def trim(b, xa, xb, ya, yb, E, hx, S, N, front=True, back=True):
    """Ринви вздовж карнизів і одна водостічна труба на східному куті фронту; навіс і ринва дають силует вже зблизька."""
    if front:
        b.box((xa + xb) / 2, ya + 0.04, E - 0.14, xb - xa - 0.1, 0.13, 0.1, "gutter")
    if back:
        b.box((xa + xb) / 2, yb - 0.04, E - 0.14, xb - xa - 0.1, 0.13, 0.1, "gutter")
    b.box(hx + 0.12, S - 0.27, 0.12, 0.08, 0.08, E - 0.3, "gutter")
    b.box(hx + 0.12, ya + 0.04, E - 0.3, 0.08, 0.13, 0.12, "gutter")


def pane_dress(b, axis, c, sgn, u, z, w, h, rain=True):
    """Вікно, посаджене в рамку: підвіконня 11 см, лиштва 7 см навколо скла (її тінь читається як врізання) і потік від підвіконня."""
    if axis == "y":
        b.box(u, c + sgn * 0.055, z - 0.1, w + 0.28, 0.11, 0.1, "step")
        b.box(u, c + sgn * 0.035, z + h, w + 0.16, 0.07, 0.07, "step")
        for sx in (-1, 1):
            b.box(u + sx * (w / 2 + 0.04), c + sgn * 0.035, z, 0.08, 0.07, h, "step")
    else:
        b.box(c + sgn * 0.055, u, z - 0.1, 0.11, w + 0.28, 0.1, "step")
        b.box(c + sgn * 0.035, u, z + h, 0.07, w + 0.16, 0.07, "step")
        for sx in (-1, 1):
            b.box(c + sgn * 0.035, u + sx * (w / 2 + 0.04), z, 0.07, 0.08, h, "step")
    if rain and z - 0.3 > 0.55:
        z1 = max(0.6, z - 1.0)
        for sx in (-0.28, 0.28):
            uu = u + sx * w
            if axis == "y":
                pts = [(uu - 0.07, c + sgn * 0.012, z1), (uu + 0.07, c + sgn * 0.012, z1), (uu + 0.07, c + sgn * 0.012, z - 0.1), (uu - 0.07, c + sgn * 0.012, z - 0.1)]
                plane_soot(b, pts, (0.76, 0.76, 0.5, 0.5), (0, sgn, 0))
            else:
                pts = [(c + sgn * 0.012, uu - 0.07, z1), (c + sgn * 0.012, uu + 0.07, z1), (c + sgn * 0.012, uu + 0.07, z - 0.1), (c + sgn * 0.012, uu - 0.07, z - 0.1)]
                plane_soot(b, pts, (0.76, 0.76, 0.5, 0.5), (sgn, 0, 0))


def grime(b, axis, c, sgn, u0, u1, z0, h=0.55):
    """Смуга бруду біля цоколя: темніше внизу, поступово до тону стіни."""
    if axis == "y":
        pts = [(u0, c + sgn * 0.012, z0), (u1, c + sgn * 0.012, z0), (u1, c + sgn * 0.012, z0 + h), (u0, c + sgn * 0.012, z0 + h)]
        plane_soot(b, pts, (0.4, 0.4, 0.76, 0.76), (0, sgn, 0))
    else:
        pts = [(c + sgn * 0.012, u0, z0), (c + sgn * 0.012, u1, z0), (c + sgn * 0.012, u1, z0 + h), (c + sgn * 0.012, u0, z0 + h)]
        plane_soot(b, pts, (0.4, 0.4, 0.76, 0.76), (sgn, 0, 0))


def gable_roof(b, pf, pb, xw, xb, mat):
    b.poly_up([pf(xw, 0.0), pf(xb, 0.0), pf(xb, 1.0), pf(xw, 1.0)], mat)
    b.poly_up([pb(xw, 0.0), pb(xb, 0.0), pb(xb, 1.0), pb(xw, 1.0)], mat)


def tooth_ok(x, cut, v1, side):
    """Крокву можна класти, лише якщо вона не потрапляє під лишок даху (інакше пробиває скат)."""
    vs = [cut(i / 8 * v1) for i in range(9)]
    return x < min(vs) - 0.12 if side > 0 else x > max(vs) + 0.12


def house1(ruined):
    """Одноповерховий дім 6.6 x 4.8 м. Напівзруйнований: східна половина даху ціла, західна провалилась, обвалена частина
    фронтальної й західної стін, завал усередині й невеликий зсув перед обваленою стіною."""
    lib.reset()
    b = Builder()
    rnd = random.Random(14)
    hx, hy = 3.3, 2.4
    E, R = 2.5, 4.2
    ya, yb, ym, xb, xw = -(hy + 0.4), hy + 0.4, 0.0, hx + 0.45, -(hx + 0.45)
    S, N = -hy, hy

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.4, 2 * hy + 0.4, 0.5, "brick_grey")
        b.box(0, 0, 0.5, 2 * hx + 0.38, 2 * hy + 0.38, E - 0.5, "wall_plaster")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (sx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
        gable_roof(b, PF, PB, xw, xb, "fc_roof_xh")
        trim(b, xw, xb, ya, yb, E, hx, S, N)
        for x in (-2.3, -0.8, 1.5, 2.65):
            b.window(("y", S - 0.19, -1), x, 0.9, 1.0, 1.2)
            pane_dress(b, "y", S - 0.19, -1, x, 0.9, 1.0, 1.2)
        b.box(0.1, S - 0.19 + 0.03, 0.0, 1.0, 0.06, 2.0, "dark")
        b.box(0.1, S - 0.5, 0.0, 1.8, 0.7, 0.2, "step")
        for y in (-1.0, 1.0):
            for sx, sgn in ((hx + 0.19, 1), (-hx - 0.19, -1)):
                b.window(("x", sx, sgn), y, 0.9, 1.1, 1.2)
                pane_dress(b, "x", sx, sgn, y, 0.9, 1.1, 1.2)
        for x in (-2.3, -0.6, 1.2, 2.6):
            b.window(("y", N + 0.19, 1), x, 0.9, 1.0, 1.2)
            pane_dress(b, "y", N + 0.19, 1, x, 0.9, 1.0, 1.2)
        grime(b, "y", S - 0.19, -1, -hx, hx, 0.5)
        grime(b, "y", N + 0.19, 1, -hx, hx, 0.5)
        grime(b, "x", hx + 0.19, 1, S, N, 0.5)
        b.box(1.6, -0.2, 3.5, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
        lib.finish(b, "house_h5", out, tri_limit=2200, footprint=(1, 1))
        return
    kw = dict(top_tone=0.82)
    standing = dict(brick_mat="wall_plaster", cap=0.06, jag=0.12, **kw)
    broken = dict(brick_mat="brick_face", **kw)
    wall_run(b, (-0.9, S), (hx + 0.2, S), 0.4, [E] * 6, "wall_half", "wall_plaster", 21, hcap=2.6, **standing)
    wall_run(b, (-hx, S), (-0.9, S), 0.4, [0.6, 1.3, 0.9, 1.8], "wall_half", "brick_face", 22, hcap=2.2, **broken)
    wall_run(b, (hx, S), (hx, N), 0.4, [E] * 6, "wall_half", "wall_plaster", 23, hcap=2.6, **standing)
    wall_run(b, (hx + 0.2, N), (-1.6, N), 0.4, [E] * 6, "wall_half", "wall_plaster", 24, hcap=2.6, **standing)
    wall_run(b, (-1.6, N), (-hx, N), 0.4, [1.7, 1.1, 2.0, 0.8], "wall_half", "brick_face", 25, hcap=2.2, **broken)
    wall_run(b, (-hx, N), (-hx, S), 0.4, [2.2, 1.3, 0.7, 1.0, 0.6], "wall_half", "brick_face", 26, hcap=2.2, **broken)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (hx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
    zt = E - 0.03
    for x in (1.5, 2.65):
        burn_ring(b, "y", S - 0.2, x, 0.9, 1.0, 1.2, -1, g_side=0.3, g_bot=0.1, g_top=0.6, t_in=0.22, t_out=0.62, ztop=zt)
        opening2(b, "y", S - 0.2, x, 0.9, 1.0, 1.2, -1, ztop=zt)
    burn_ring(b, "y", S - 0.2, 0.1, 0.05, 1.0, 2.0, -1, g_side=0.3, g_bot=0.0, g_top=0.6, t_in=0.22, t_out=0.62, ztop=zt)
    opening2(b, "y", S - 0.2, 0.1, 0.05, 1.0, 2.0, -1, ztop=zt)
    for y, w, h, z in ((-1.0, 1.1, 1.2, 0.9), (1.0, 1.4, 1.3, 0.8)):
        burn_ring(b, "x", hx + 0.2, y, z, w, h, 1, g_side=0.3, g_bot=0.15, g_top=0.7, t_in=0.22, t_out=0.62, ztop=zt)
        opening2(b, "x", hx + 0.2, y, z, w, h, 1, ztop=zt)
    for x in (0.6, 2.0):
        burn_ring(b, "y", N + 0.2, x, 0.9, 1.0, 1.2, 1, g_side=0.3, g_bot=0.1, g_top=0.6, t_in=0.22, t_out=0.62, ztop=zt)
        opening2(b, "y", N + 0.2, x, 0.9, 1.0, 1.2, 1, ztop=zt)
    grime(b, "y", S - 0.2, -1, -0.9, hx, 0.0)
    grime(b, "x", hx + 0.2, 1, S, N, 0.0)
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return -0.1 + 0.7 * math.sin(3.1 * v + ph[0]) + 0.25 * math.sin(9 * v + ph[1])

    def cutB(v):
        return -0.7 + 0.6 * math.sin(2.7 * v + ph[2]) + 0.25 * math.sin(8 * v + ph[0])
    xsF = roof_part(b, PF, xb, cutF, "fc_roof_xh", rnd)
    xsB = roof_part(b, PB, xb, cutB, "fc_roof_xh", rnd)
    break_dress(b, PF, xsF, 1, rnd)
    break_dress(b, PB, xsB, 1, rnd)
    trim(b, -0.7, xb, ya, yb, E, hx, S, N)
    plan = [HeapSurface(-1.9, 0.1, 1.25, 1.4, 0.85, 71, bumps=6, lip=0.28, wob=0.15, lump=0.07, hummocks=3, hum_amp=0.25),
            HeapSurface(-2.1, -2.95, 1.2, 0.5, 0.7, 72, bumps=5, lip=0.25, wob=0.1, lump=0.05, hummocks=1, hum_amp=0.2)]
    sf = surface(plan)
    # крокви лежать на верху стіни (консоль) або на завалі; тих, що висіли б у повітрі чи пробивали скат, немає
    for x in (-0.8, -0.2):
        for plate, P, cut in ((S + 0.05, PF, cutF), (N - 0.05, PB, cutB)):
            v1 = rnd.uniform(0.3, 0.6)
            if not tooth_ok(x, cut, v1, 1) or (plate < 0 and x < -0.9) or (plate > 0 and x < -1.6):
                continue
            c = P(x, v1)
            b.beam((x, plate, E + 0.05), (c[0], c[1], c[2] - 0.1), 0.12, "timber_dark", 0.18)
    for x in (-2.9, -2.2, -1.5):
        for y0, y1 in ((S + 0.5, S + 1.7), (N - 0.5, N - 1.7)):
            b.beam((x, y0, sf(x, y0) + 0.1), (x, y1, sf(x, y1) + 0.3), 0.12, "timber_dark", 0.18)
    b.beam((-3.0, 0.1, sf(-3.0, 0.1) + 0.12), (-1.0, 0.0, sf(-1.0, 0.0) + 0.3), 0.16, "timber_dark", 0.22)
    bent_sheet(b, (-2.7, -0.9, sf(-2.7, -0.9) + 0.2), (-2.3, 0.8, sf(-2.3, 0.8) + 0.2), 0.9, "sheet_char", 0.18, axis="x")
    bent_sheet(b, (-1.6, -1.2, sf(-1.6, -1.2) + 0.2), (-1.4, 0.5, sf(-1.4, 0.5) + 0.2), 0.9, "sheet_char", 0.18, axis="x")
    bent_sheet(b, (-1.5, -3.0, sf(-1.5, -3.0) + 0.1), (-2.9, -2.9, sf(-2.9, -2.9) + 0.1), 0.9, "sheet_char", 0.12, axis="y")
    b.box(1.6, -0.2, 3.5, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
    lumps(b, plan, rnd, 6)
    bh = heaps(b, plan, 7)
    lib.finish(b, "ruin_half_house1", out, tri_limit=4600, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def house2(ruined):
    """Двоповерховий дім 6 x 5.6 м. Напівзруйнований: західна половина даху ціла, східний фронтон обвалений, перекриття нахилене в завал."""
    lib.reset()
    b = Builder()
    rnd = random.Random(33)
    hx, hy = 3.0, 2.8
    E, R, FL = 5.4, 7.3, 2.7
    ya, yb, ym, xb, xw = -(hy + 0.4), hy + 0.4, 0.0, hx + 0.45, -(hx + 0.45)
    S, N = -hy, hy

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.4, 2 * hy + 0.4, 0.6, "brick_grey")
        b.box(0, 0, 0.6, 2 * hx + 0.38, 2 * hy + 0.38, E - 0.6, "wall_plaster")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (sx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
        gable_roof(b, PF, PB, xw, xb, "tile_graphite")
        trim(b, xw, xb, ya, yb, E, hx, S, N)
        for z in (0.9, 3.6):
            for x in (-1.8, 0.0, 1.8):
                b.window(("y", S - 0.19, -1), x, z, 1.2, 1.4)
                pane_dress(b, "y", S - 0.19, -1, x, z, 1.2, 1.4)
            for x in (-1.2, 1.2):
                b.window(("y", N + 0.19, 1), x, z, 1.2, 1.4)
                pane_dress(b, "y", N + 0.19, 1, x, z, 1.2, 1.4)
            for y in (-1.0, 1.0):
                b.window(("x", hx + 0.19, 1), y, z, 1.1, 1.4)
                pane_dress(b, "x", hx + 0.19, 1, y, z, 1.1, 1.4)
        b.box(2.2, S - 0.19 + 0.03, 0.0, 1.0, 0.06, 2.0, "dark")
        b.box(2.2, S - 0.5, 0.0, 1.8, 0.7, 0.2, "step")
        grime(b, "y", S - 0.19, -1, -hx, hx, 0.6)
        grime(b, "x", hx + 0.19, 1, S, N, 0.6)
        b.box(-1.8, 0.0, 6.2, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
        lib.finish(b, "house_h6", out, tri_limit=2600, footprint=(1, 1))
        return
    kw = dict(top_tone=0.82)
    standing = dict(brick_mat="wall_plaster", cap=0.06, jag=0.1, **kw)
    wall_run(b, (-hx - 0.2, S), (hx + 0.2, S), 0.4, [E] * 8, "wall_half", "wall_plaster", 31, hcap=5.6, **standing)
    wall_run(b, (hx + 0.2, N), (-hx - 0.2, N), 0.4, [E] * 8, "wall_half", "wall_plaster", 32, hcap=5.6, **standing)
    wall_run(b, (-hx, N), (-hx, S), 0.4, [E] * 8, "wall_half", "wall_plaster", 33, hcap=5.6, **standing)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (-hx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
    wall_run(b, (hx, S), (hx, N), 0.4, [1.2, 2.2, 4.2, 5.0, 3.6, 1.8, 1.1, 0.9, 1.5, 2.5, 1.3], "wall_half", "brick_face", 34, hcap=5.2, jag=0.7, brick_mat="brick_face", **kw)
    zt = E - 0.03
    for fl, z in ((0, 0.9), (1, 3.6)):
        for x in (-1.8, 0.0, 1.8):
            blown = (fl == 1 and x != 0.0) or (fl == 0 and x == 1.8)
            if blown:
                burn_ring(b, "y", S - 0.2, x, z, 1.2, 1.4, -1, g_side=0.3, g_bot=0.15, g_top=0.7, t_in=0.22, t_out=0.62, ztop=zt)
                opening2(b, "y", S - 0.2, x, z, 1.2, 1.4, -1, ztop=zt)
            else:
                b.window(("y", S - 0.2, -1), x, z, 1.2, 1.4)
                pane_dress(b, "y", S - 0.2, -1, x, z, 1.2, 1.4)
        for x in (-1.2, 1.2):
            b.window(("y", N + 0.2, 1), x, z, 1.2, 1.4)
            pane_dress(b, "y", N + 0.2, 1, x, z, 1.2, 1.4)
    burn_ring(b, "y", S - 0.2, 2.2, 0.05, 1.0, 2.0, -1, g_side=0.3, g_bot=0.0, g_top=0.7, t_in=0.22, t_out=0.62, ztop=zt)
    opening2(b, "y", S - 0.2, 2.2, 0.05, 1.0, 2.0, -1, ztop=zt)
    grime(b, "y", S - 0.2, -1, -hx, hx, 0.0)
    # внутрішня грань західного фронтону не чиста штукатурка: кіптява згори, облуплені плями
    xi = -hx + 0.21
    plane_soot(b, [(xi, -2.5, 2.8), (xi, 2.5, 2.8), (xi, 2.0, 6.7), (xi, -2.0, 6.7)], (0.7, 0.7, 0.22, 0.22), (1, 0, 0))
    for (yy, zz, ww, hh) in ((-1.0, 4.4, 1.2, 0.9), (1.2, 3.6, 0.9, 1.2), (0.0, 5.6, 1.4, 0.7)):
        plane_soot(b, [(xi + 0.004, yy - ww / 2, zz), (xi + 0.004, yy + ww / 2, zz + 0.1), (xi + 0.004, yy + ww * 0.4, zz + hh), (xi + 0.004, yy - ww * 0.5, zz + hh * 0.8)], (0.34, 0.34, 0.18, 0.18), (1, 0, 0))
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return 0.4 + 0.6 * math.sin(3 * v + ph[0]) + 0.25 * math.sin(9 * v + ph[1])

    def cutB(v):
        return 1.0 + 0.6 * math.sin(2.6 * v + ph[2]) + 0.25 * math.sin(8 * v + ph[0])
    # дах: лишок ліворуч від краю; скат малюємо від західного кінця до рваного краю
    def roof_west(P, cut):
        nv = 18
        xs = [cut(i / nv) + rnd.uniform(-0.14, 0.14) for i in range(nv)]
        pts = [P(xw, 0.0)]
        for i in range(nv):
            pts.append(P(xs[i], i / nv))
            pts.append(P(xs[i], (i + 1) / nv))
        pts.append(P(xw, 1.0))
        b.poly_up(pts, "tile_graphite")
        return xs
    xsF = roof_west(PF, cutF)
    xsB = roof_west(PB, cutB)
    break_dress(b, PF, xsF, -1, rnd)
    break_dress(b, PB, xsB, -1, rnd)
    trim(b, xw, 1.0, ya, yb, E, hx, S, N)
    for x in (1.5, 2.2, 2.8):
        for plate, P, cut in ((S + 0.05, PF, cutF), (N - 0.05, PB, cutB)):
            v1 = rnd.uniform(0.25, 0.55)
            if rnd.random() < 0.2 or not tooth_ok(x, cut, v1, -1):
                continue
            c = P(x, v1)
            b.beam((x, plate, E + 0.05), (c[0], c[1], c[2] - 0.12), 0.14, "timber_dark", 0.22)
    plan = [HeapSurface(3.4, 0.0, 0.85, 2.1, 1.3, 81, bumps=6, lip=0.28, wob=0.15, lump=0.08, hummocks=3, hum_amp=0.3, pw=1.5),
            HeapSurface(1.5, 0.3, 1.3, 1.9, 0.8, 82, bumps=5, lip=0.26, wob=0.1, lump=0.05, hummocks=2, hum_amp=0.2)]
    plan[0].fit_peak(1.45)
    sf = surface(plan)
    chip_slab(b, 1.7, 0.0, FL - 0.1, 3.4, 5.2, 0.24, (0.0, 0.42, 0.02), "floor_char", "floor_char", 41, rebar=3)
    bent_sheet(b, (1.6, -2.7, 5.4), (1.8, -1.2, FL + 0.3), 0.9, "sheet_char", 0.2, axis="x")
    bent_sheet(b, (3.2, 1.6, sf(3.2, 1.6) + 0.2), (3.9, 2.4, sf(3.9, 2.4) + 0.12), 0.9, "sheet_char", 0.12, axis="y")
    b.box(-1.8, 0.0, 6.2, 0.6, 0.6, 1.9, "brick_face", top="brick_grey")
    lumps(b, plan, rnd, 6)
    bh = heaps(b, plan, 9)
    lib.finish(b, "ruin_half_house2", out, tri_limit=4800, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def shed(ruined):
    """Господарський сарай 6.8 x 4.2 м. Напівзруйнований: фронтальна (на камеру) стіна впала, дах з цього боку провис уздовж того самого коника."""
    lib.reset()
    b = Builder()
    rnd = random.Random(57)
    hx, hy = 3.4, 2.1
    E, R = 2.8, 3.8
    ya, yb, ym = -(hy + 0.4), hy + 0.4, 0.0
    S, N, XW, XE = -hy, hy, -hx, hx
    xs = [XW - 0.45 + 0.5 * i for i in range(16)]
    for i in range(len(xs) - 1):
        b.poly_up([(xs[i], yb, E), (xs[i + 1], yb, E), (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_x")
    b.box(0, yb - 0.04, E - 0.14, 2 * hx + 0.8, 0.13, 0.1, "gutter")
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.3, 2 * hy + 0.3, 0.5, "brick_grey")
        b.box(0, 0, 0.5, 2 * hx + 0.28, 2 * hy + 0.28, E - 0.5, "boards_soft")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.3, (sx, 0.0, 0.0), math.pi / 2, 0.0, "boards_soft", top_mat="boards_soft")
        for i in range(len(xs) - 1):
            b.poly_up([(xs[i], ya, E), (xs[i + 1], ya, E), (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_x")
        b.box(0, ya + 0.04, E - 0.14, 2 * hx + 0.8, 0.13, 0.1, "gutter")
        b.box(hx + 0.2, S - 0.18, 0.12, 0.08, 0.08, E - 0.3, "gutter")
        b.box(hx + 0.15, 0.0, 0.0, 0.06, 2.4, 2.4, "door_steel")
        b.window(("y", N + 0.15, 1), 1.8, 1.2, 0.8, 0.6)
        pane_dress(b, "y", N + 0.15, 1, 1.8, 1.2, 0.8, 0.6, rain=False)
        b.window(("y", N + 0.15, 1), -2.0, 1.2, 0.8, 0.6)
        pane_dress(b, "y", N + 0.15, 1, -2.0, 1.2, 0.8, 0.6, rain=False)
        grime(b, "y", S - 0.14, -1, -hx, hx, 0.5, 0.5)
        lib.finish(b, "f8_shed", out, tri_limit=1600, footprint=(1, 1))
        return
    kw = dict(brick_mat="boards_soft", soot_h=1.0, top_tone=0.82)
    wall_run(b, (XE, N), (XW, N), 0.14, [E] * 8, "boards_soft_vc", "boards_soft", 51, hcap=3.0, jag=0.1, cap=0.06, **kw)
    wall_run(b, (XW, N), (XW, S), 0.14, [E, E, 2.6, 1.8, 0.7, 0.5], "boards_soft_vc", "boards_soft", 52, hcap=3.0, jag=0.5, **kw)
    wall_run(b, (XE, S), (XE, N), 0.14, [E] * 6, "boards_soft_vc", "boards_soft", 53, hcap=3.0, jag=0.1, cap=0.06, **kw)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.14, (XE, 0.0, 0.0), math.pi / 2, 0.0, "boards_soft", top_mat="boards_soft")
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.14, (XW, 0.0, 0.0), math.pi / 2, 0.0, "boards_soft", top_mat="boards_soft")
    post_x = (-3.4, -2.27, -1.13, 0.0, 1.13, 2.27, 3.4)
    post_h = (E, 1.8, 0.8, 1.2, 2.3, E, E)
    for x, h in zip(post_x, post_h):
        b.box(x, S, 0.0, 0.18, 0.18, h, "timber_dark")
    for (x, y, rot, ln, z, ang) in ((-1.9, -3.1, 0.1, 2.8, 0.2, 0.22), (0.4, -2.9, -0.15, 2.4, 0.3, 0.3), (-0.5, -3.7, 0.4, 1.8, 0.1, 0.1)):
        b.box_e(x, y, z + 0.2, ln, 1.9, 0.08, "boards_soft", euler=(ang, 0.0, rot), top="boards_soft")
    zt = E - 0.03
    opening2(b, "x", XE + 0.1, -0.3, 0.05, 1.3, 2.2, 1, ztop=zt)
    burn_ring(b, "x", XE + 0.1, -0.3, 0.05, 1.3, 2.2, 1, g_side=0.3, g_bot=0.0, g_top=0.5, t_in=0.22, t_out=0.62, ztop=zt)
    opening2(b, "y", N + 0.1, 1.8, 0.9, 1.4, 1.3, 1, ztop=zt)
    burn_ring(b, "y", N + 0.1, 1.8, 0.9, 1.4, 1.3, 1, g_side=0.3, g_bot=0.15, g_top=0.6, t_in=0.22, t_out=0.62, ztop=zt)
    opening2(b, "y", N + 0.1, -2.0, 1.1, 0.8, 0.9, 1, ztop=zt)

    def hpost(x):
        for i in range(len(post_x) - 1):
            if post_x[i] <= x <= post_x[i + 1]:
                f = (x - post_x[i]) / (post_x[i + 1] - post_x[i])
                return post_h[i] * (1 - f) + post_h[i + 1] * f
        return E
    pts = []
    for x in xs:
        ez = max(0.8, hpost(max(XW, min(XE, x))) + 0.06) + (rnd.uniform(-0.06, 0.06) if x < 1.5 else 0.0)
        pts.append((x, ya + (E - ez) * 0.3, ez))
    hole = {i for i, x in enumerate(xs[:-1]) if -2.0 < x < -1.0}
    for i in range(len(xs) - 1):
        if i not in hole:
            b.poly_up([pts[i], pts[i + 1], (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_x")
    for x in (-1.8, -1.5, -1.2):
        j = min(range(len(xs)), key=lambda k: abs(xs[k] - x))
        b.beam(pts[j], (xs[j], ym, R - 0.05), 0.1, "timber_dark", 0.16)
    plan = [HeapSurface(-1.2, -3.0, 1.7, 0.65, 0.65, 91, bumps=6, lip=0.24, wob=0.1, lump=0.05, hummocks=1, hum_amp=0.15),
            HeapSurface(-0.8, 0.1, 1.3, 0.9, 0.5, 92, bumps=5, lip=0.22, wob=0.08, lump=0.04, hummocks=1, hum_amp=0.12)]
    lumps(b, plan, rnd, 5)
    bh = heaps(b, plan, 11, dens=6.0)
    lib.finish(b, "ruin_half_shed", out, tri_limit=4600, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


for fn, nm in ((house1, "house1"), (house2, "house2"), (shed, "shed")):
    if want(nm):
        fn(False)
        fn(True)
