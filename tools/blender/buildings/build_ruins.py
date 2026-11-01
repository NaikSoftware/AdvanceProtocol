"""Малі будинки на одну клітинку (8 x 8 м) і їхні напівзруйновані двійники: одна функція будує обидва, прапорець ruined лишає
те саме габаритне тіло. Напівзруйновані: стоять майже всі стіни, один кут або секція обвалені, дах частково згорів, у стінах
вибиті вікна й діри від снарядів, дверей немає; завал лише біля обвалу й не виходить за клітинку. Матеріали ті самі, що в цілих
будинків (світла штукатурка, червона цегла в димарі й на зламах, сірі дахи), кіптява й руйнування зверху.
Камера гри бачить боки -Y і +X, тому руйнування скрізь на них.
Ще два цілі сараї для дворів без зруйнованих двійників: f8_shed_brick (цегляний під чорно-коричневим руберойдом) і f8_shed_lean (дерев'яна
прибудова з односхилим дахом). Запуск: build_ruins.py -- <out> [house1 house2 shed shed_brick shed_lean]"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, wall_run, burn_ring, opening2, chip_slab, prism, bent_sheet, heap_mound
from lib import HeapSurface as _HS
from mathutils import Vector

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def HeapSurface(*a, **k):
    k.setdefault("noise", 1.0)
    k.setdefault("feather", 0.5)                                                  # нерівна поверхня й рваний контур для всіх відсипів
    return _HS(*a, **k)


def want(n):
    return not only or n in only


def heaps(b, plan, seed, dens=7.0):
    """Купи: низький меш, високе скан-джерело для запікання (фотоскан сміття + уламки 20-60 см різного матеріалу й тону)."""
    return lib.rubble_heaps(b, plan, seed, dens=dens, skirt=0.5)


def surface(plan):
    return lambda x, y: max(h.z(x, y) for h in plan)


def lumps(b, plan, rnd, n_each=8):
    lib.rubble_lumps(b, plan, rnd, n_each, tmin=0.1, tmax=1.0, size=(0.18, 0.45))


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
    # рваний край ламаною через середини рядів: сходинки по ряду давали на зумі 6 піксельні зубці
    pts = [P(xs[0], 0.0)] + [P(xs[i], (i + 0.5) / nv) for i in range(nv)] + [P(xs[-1], 1.0)]
    edge_thick(b, pts, sgn)
    return pts, xs


def edge_thick(b, pts, sgn, d=0.15):
    """Видима товщина зламу: смуга 15 см униз від краю (лист плюс лати), обернена до провалу (від боку sgn, де дах лишився)."""
    for p0, p1 in zip(pts[:-1], pts[1:]):
        q = [p0, p1, (p1[0], p1[1], p1[2] - d), (p0[0], p0[1], p0[2] - d)]
        lib._quad(b, q, "boards_ruin", (-sgn, 0.0, 0.0))


def roof_part(b, P, x_end, cut, mat, rnd, nv=18, battens=True):
    pts, xs = roof_break(b, P, cut, 1 if x_end > 0 else -1, rnd, mat, nv)
    b.poly_up([P(x_end, 0.0)] + pts + [P(x_end, 1.0)], mat)
    return xs


def break_dress(b, P, xs, sgn, rnd, nv=18, battens=True):
    """Кіптява вздовж краю (вузька) і рейки 5x4 см, що стирчать за край на 0.2-0.5 м."""
    for i in range(nv):                                                          # кіптява на самому даху: чорна біля краю, згасає за ~0.9 м
        v0, v1 = i / nv, (i + 1) / nv
        for (d0, d1, t0, t1) in ((0.0, 0.35, 0.4, 0.7), (0.35, 0.9, 0.7, 1.0)):      # чорна облямівка уздовж зламу читається як обведення
            pts = [P(xs[i] + d0 * sgn, v0), P(xs[i] + d0 * sgn, v1), P(xs[i] + d1 * sgn, v1), P(xs[i] + d1 * sgn, v0)]
            pts = [(x, y, z + 0.01) for (x, y, z) in pts]
            n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
            if n_.z < 0:
                n_ = -n_
            b.decal(pts, (t0, t0, t1, t1), "fc_roof_xh_dm", tuple(n_.normalized()))
    for i in range(1, nv, 2) if battens else ():
        v = (i + 0.5) / nv
        a = P(xs[i] + 0.1 * sgn, v)
        c = P(xs[i] - sgn * rnd.uniform(0.2, 0.5), v)
        b.beam((a[0], a[1], a[2] - 0.05), (c[0], c[1], c[2] - 0.08), 0.05, "timber_dark", 0.04)


def trim(b, xa, xb, ya, yb, E, hx, S, N, front=True, back=True):
    """Ринви вздовж карнизів і одна водостічна труба на східному куті фронту; навіс і ринва дають силует вже зблизька."""
    if front:
        b.box((xa + xb) / 2, ya + 0.04, E - 0.14, xb - xa - 0.1, 0.13, 0.1, "gutter_d")
    if back:
        b.box((xa + xb) / 2, yb - 0.04, E - 0.14, xb - xa - 0.1, 0.13, 0.1, "gutter_d")
    b.box(hx + 0.12, S - 0.27, 0.12, 0.08, 0.08, E - 0.3, "gutter_d")
    b.box(hx + 0.12, ya + 0.04, E - 0.3, 0.08, 0.13, 0.12, "gutter_d")


_RAIN = random.Random(7)
DM = ["wall_plaster_dm"]                 # матеріал декалей-множників поточної стіни: патьоки й бруд темнять саму стіну, а не фарбують сірим


def pane_dress(b, axis, c, sgn, u, z, w, h, rain=True):
    """Вікно, посаджене в рамку: підвіконня 11 см, лиштва 7 см навколо скла (її тінь читається як врізання) і потік від підвіконня."""
    if axis == "y":                                                               # відлив на 17 см, лиштва на 12: скло глибше на ~9 см
        b.box(u, c + sgn * 0.085, z - 0.08, w + 0.34, 0.17, 0.08, "step")
    else:
        b.box(c + sgn * 0.085, u, z - 0.08, 0.17, w + 0.34, 0.08, "step")
    lib.window_ring(b, axis, c, sgn, u, z, w, h)
    if rain and z - 0.3 > 0.55 and _RAIN.random() < 0.5:
        ln_ = _RAIN.uniform(0.4, 1.2)
        z1 = max(0.6, z - 0.1 - ln_)
        uu = u + _RAIN.uniform(-0.3, 0.3) * w
        hw = _RAIN.uniform(0.06, 0.11)
        if axis == "y":
            pts = [(uu - hw, c + sgn * 0.012, z1), (uu + hw, c + sgn * 0.012, z1), (uu + hw, c + sgn * 0.012, z - 0.1), (uu - hw, c + sgn * 0.012, z - 0.1)]
            b.decal(pts, (1.0, 1.0, 0.76, 0.76), DM[0], (0, sgn, 0))
        else:
            pts = [(c + sgn * 0.012, uu - hw, z1), (c + sgn * 0.012, uu + hw, z1), (c + sgn * 0.012, uu + hw, z - 0.1), (c + sgn * 0.012, uu - hw, z - 0.1)]
            b.decal(pts, (1.0, 1.0, 0.76, 0.76), DM[0], (sgn, 0, 0))


def grime(b, axis, c, sgn, u0, u1, z0, h=0.55):
    """Смуга бруду біля цоколя: темніше внизу, поступово до тону стіни."""
    if axis == "y":
        pts = [(u0, c + sgn * 0.012, z0), (u1, c + sgn * 0.012, z0), (u1, c + sgn * 0.012, z0 + h), (u0, c + sgn * 0.012, z0 + h)]
        b.decal(pts, (0.62, 0.62, 1.0, 1.0), DM[0], (0, sgn, 0))
    else:
        pts = [(c + sgn * 0.012, u0, z0), (c + sgn * 0.012, u1, z0), (c + sgn * 0.012, u1, z0 + h), (c + sgn * 0.012, u0, z0 + h)]
        b.decal(pts, (0.62, 0.62, 1.0, 1.0), DM[0], (sgn, 0, 0))


def gable_roof(b, pf, pb, xw, xb, mat):
    b.poly_up([pf(xw, 0.0), pf(xb, 0.0), pf(xb, 1.0), pf(xw, 1.0)], mat)
    b.poly_up([pb(xw, 0.0), pb(xb, 0.0), pb(xb, 1.0), pb(xw, 1.0)], mat)


def tooth_ok(x, cut, v1, side):
    """Крокву можна класти, лише якщо вона не потрапляє під лишок даху (інакше пробиває скат)."""
    vs = [cut(i / 8 * v1) for i in range(9)]
    return x < min(vs) - 0.12 if side > 0 else x > max(vs) + 0.12


def house1(ruined, variant=0):
    """Одноповерховий дім 6.6 x 4.8 м. Напівзруйнований: східна половина даху ціла, західна провалилась, обвалена частина
    фронтальної й західної стін, завал усередині й невеликий зсув перед обваленою стіною."""
    lib.reset()
    lib.ROOFS["cherry_ruin"] = ("tile", (0.24, 0.09, 0.09))                    # темна вишня, як дахи хат у грі: яскраво-червоний давав тоновий розрив зі стінами
    lib.palette(wall=(0.73, 0.64, 0.57), roof="cherry_ruin" if ruined else "cherry_dark", eave=3.0, chim="ch_orange", row=0.3, trim=0.95, frame=4)
    DM[0] = "wall_plaster_dm" if not ruined else "wall_half"
    b = Builder()
    b.win_kind = 3                                                               # вузькі вертикальні з фрамугою
    rnd = random.Random(14 + 101 * variant)                                    # variant: той самий корпус, інший виріз даху, крокви й завал
    hx, hy = 3.3, 2.4
    E, R = 3.0, 6.5
    ya, yb, ym, xb, xw = -(hy + 0.4), hy + 0.4, 0.0, hx + 0.45, -(hx + 0.45)
    S, N = -hy, hy

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.46, 2 * hy + 0.46, 0.5, "plinth_flat")       # цоколь на 4 см за стіною
        b.box(0, 0, 0.5, 2 * hx + 0.38, 2 * hy + 0.38, E - 0.5, "wall_plaster")
        c_ = 0.19
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (sx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
        gable_roof(b, PF, PB, xw, xb, "fc_roof_xh")
        trim(b, xw, xb, ya, yb, E, hx, S, N)
        for x in (-2.3, -0.8, 1.5, 2.65):
            b.window(("y", S - 0.19, -1), x, 1.0, 0.8, 1.5, kind=4 if x < 0 else None)   # вузькі; два з гратами
            pane_dress(b, "y", S - 0.19, -1, x, 1.0, 0.8, 1.5, rain=False)
        b.box(0.1, S - 0.21, 0.0, 1.0, 0.06, 2.0, "door_red")                   # на 4 см перед стіною: врівень зі стіною двері мерехтять і читаються як пролом
        b.box(0.1, S - 0.22, 2.0, 1.2, 0.07, 0.1, "trim")
        for sx in (-0.55, 0.55):
            b.box(0.1 + sx, S - 0.22, 0.0, 0.1, 0.07, 2.1, "trim")
        b.box(0.1, S - 0.5, 0.0, 1.8, 0.7, 0.2, "plinth_flat")
        for y in (-1.0, 1.0):
            for sx, sgn in ((hx + 0.19, 1), (-hx - 0.19, -1)):
                b.window(("x", sx, sgn), y, 1.0, 0.8, 1.5)
                pane_dress(b, "x", sx, sgn, y, 1.0, 0.8, 1.5, rain=False)
        for x in (-2.3, -0.6, 1.2, 2.6):
            b.window(("y", N + 0.19, 1), x, 1.0, 0.8, 1.5)
            pane_dress(b, "y", N + 0.19, 1, x, 1.0, 0.8, 1.5, rain=False)
        b.chimney2("wide", 1.6, -0.2, 4.6, 3.0)                     # тинькований широкий
        c_ = 0.19
        lib.weather(b, "wall_plaster", [("y", S - c_, -1, -hx - c_, hx + c_, 0.5, E), ("y", N + c_, 1, -hx - c_, hx + c_, 0.5, E), ("x", hx + c_, 1, S - c_, N + c_, 0.5, E), ("x", -hx - c_, -1, S - c_, N + c_, 0.5, E)], seed=11)
        lib.finish(b, "house_h5", out, tri_limit=2200, footprint=(1, 1))
        return
    kw = dict(top_tone=0.82, inner_tone=0.85, in_mat="plaster_burnt")             # внутрішні грані — обгоріла штукатурка
    standing = dict(brick_mat="brick_face", cap=0.06, jag=0.12, **kw)          # на зламі — цегла, а не фарба
    broken = dict(brick_mat="brick_face", step=0.35, diag_p=0.85, jit=0.5, **kw)
    wall_run(b, (-0.9, S), (hx + 0.2, S), 0.4, [E] * 6, "wall_half", "wall_plaster", 21, hcap=3.1, **standing)
    wall_run(b, (-hx, S), (-0.9, S), 0.4, [0.6, 1.3, 0.9, 1.8], "wall_half", "brick_face", 22, hcap=2.2, **broken)
    wall_run(b, (hx, S), (hx, N), 0.4, [E] * 6, "wall_half", "wall_plaster", 23, hcap=3.1, **standing)
    wall_run(b, (hx + 0.2, N), (-1.6, N), 0.4, [E] * 6, "wall_half", "wall_plaster", 24, hcap=3.1, **standing)
    wall_run(b, (-1.6, N), (-hx, N), 0.4, [1.7, 1.1, 2.0, 0.8], "wall_half", "brick_face", 25, hcap=2.2, **broken)
    wall_run(b, (-hx, N), (-hx, S), 0.4, [2.2, 1.3, 0.7, 1.0, 0.6], "wall_half", "brick_face", 26, hcap=2.2, **broken)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (hx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
    zt = E - 0.03
    for x in (1.5, 2.65):
        burn_ring(b, "y", S - 0.2, x, 0.9, 1.0, 1.2, -1, g_side=0.35, g_bot=0.1, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
        opening2(b, "y", S - 0.2, x, 1.0, 1.0, 1.4, -1, ztop=zt, streak=0.0, sooty=True)
        lib.window_ring(b, "y", S - 0.2, -1, x, 1.0, 1.0, 1.4)   # лиштва лишилась: проріз читається розміром вікна
    burn_ring(b, "y", S - 0.2, 0.1, 0.05, 1.0, 2.0, -1, g_side=0.35, g_bot=0.0, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
    opening2(b, "y", S - 0.2, 0.1, 0.05, 1.0, 2.0, -1, ztop=zt, streak=0.0, sooty=True)
    for y, w, h, z in ((-1.0, 1.1, 1.4, 1.0), (1.0, 1.1, 1.4, 1.0)):              # пропорції вікон цілої h5
        burn_ring(b, "x", hx + 0.2, y, z, w, h, 1, g_side=0.35, g_bot=0.15, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
        opening2(b, "x", hx + 0.2, y, z, w, h, 1, ztop=zt, streak=0.0, sooty=True)
        lib.window_ring(b, "x", hx + 0.2, 1, y, z, w, h)   # лиштва лишилась: проріз читається розміром вікна
    for x in (0.6, 2.0):
        burn_ring(b, "y", N + 0.2, x, 0.9, 1.0, 1.2, 1, g_side=0.35, g_bot=0.1, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
        opening2(b, "y", N + 0.2, x, 1.0, 1.0, 1.4, 1, ztop=zt, streak=0.0, sooty=True)
        lib.window_ring(b, "y", N + 0.2, 1, x, 1.0, 1.0, 1.4)   # лиштва лишилась: проріз читається розміром вікна
    lib.weather(b, "wall_half", [("y", S - 0.2, -1, -0.9, hx + 0.2, 0.0, E), ("x", hx + 0.2, 1, S - 0.2, N + 0.2, 0.0, E)], seed=17, patches=False)
    lib.pocks(b, "y", S - 0.2, -1, 1.2, 1.4, 2.0, 45, 41, zmin=0.2, zmax=2.9)
    lib.pocks(b, "x", hx + 0.2, 1, 0.0, 1.5, 1.8, 30, 42, zmin=0.2, zmax=2.9)
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
    plan = [HeapSurface(-1.9, 0.1, 1.5, 1.8, 1.0, 71 + 10 * variant, bumps=6, lip=0.28, wob=0.15, lump=0.07, hummocks=3, hum_amp=0.3),
            HeapSurface(-2.1, -2.95, 1.2, 0.5, 0.7, 72 + 10 * variant, bumps=5, lip=0.25, wob=0.1, lump=0.05, hummocks=1, hum_amp=0.2),
            HeapSurface(-3.42, -0.2, 0.5, 1.6, 0.7, 74 + 10 * variant, bumps=5, lip=0.2, wob=0.1, lump=0.05, hummocks=1, hum_amp=0.2)]
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
    b.chimney(1.6 + 1.0 * variant, -0.2, 4.6, 0.6, 3.1, "brick_face", cap="plinth_flat")                # variant: димар ближче до східного причілку
    lumps(b, plan, rnd, 14)
    # на купі — окремі шматки цегляної кладки 0.5-0.7 м і балки, що лежать зверху, а не тонуть у буро запеченій купі
    for (cx_, cy_, sz_) in ((-2.5, -0.7, 0.7), (-1.4, 1.0, 0.6), (-2.2, -2.7, 0.55), (-3.3, 0.6, 0.5)):
        b.chunk(cx_, cy_, sf(cx_, cy_) + sz_ * 0.45, sz_, "chunk_brick", rnd, tone=(1.0, 1.15))
    b.beam((-3.1, -1.5, sf(-3.1, -1.5) + 0.25), (-1.5, -0.3, sf(-1.5, -0.3) + 0.22), 0.2, "timber_dark", 0.22)
    b.beam((-2.7, 0.7, sf(-2.7, 0.7) + 0.2), (-1.1, 1.5, sf(-1.1, 1.5) + 0.25), 0.18, "timber_dark", 0.2)
    bh = heaps(b, plan, 7 + 5 * variant)
    lib.finish(b, "ruin_half_house1" + ("_b" if variant else ""), out, tri_limit=4600, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def house2(ruined, variant=0):
    """Двоповерховий дім 6 x 5.6 м. Напівзруйнований: західна половина даху ціла, східний фронтон обвалений, перекриття нахилене в завал."""
    lib.reset()
    lib.palette(wall=(0.76, 0.72, 0.60), roof="green_mid", eave=6.0, chim="ch_sand", frame=1, trim=0.92)
    if ruined:
        lib.ROOFS["green_ruin"] = ("corr", (0.12, 0.27, 0.16))                 # справжня темна зелень палітри хат
        lib.palette(wall=(0.76, 0.72, 0.60), roof="green_ruin", eave=6.0, chim="ch_sand", frame=1, trim=0.92)
    DM[0] = "wall_plaster_dm" if not ruined else "wall_half_w"
    b = Builder()
    b.win_kind = 0                                                               # старі дерев'яні на три стулки
    rnd = random.Random(33)
    hx, hy = 3.0, 2.8
    E, R, FL = 6.0, 9.5, 3.0
    ya, yb, ym, xb, xw = -(hy + 0.4), hy + 0.4, 0.0, hx + 0.45, -(hx + 0.45)
    S, N = -hy, hy

    def PF(x, v):
        return (x, ya + (ym - ya) * v, E + (R - E) * v)

    def PB(x, v):
        return (x, yb + (ym - yb) * v, E + (R - E) * v)
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.46, 2 * hy + 0.46, 0.6, "plinth_flat")
        b.box(0, 0, 0.6, 2 * hx + 0.38, 2 * hy + 0.38, E - 0.6, "wall_plaster")
        c_ = 0.19
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.4, (sx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster", top_mat="wall_plaster")
        gable_roof(b, PF, PB, xw, xb, "tile_small")
        trim(b, xw, xb, ya, yb, E, hx, S, N)
        for z in (0.9, 3.6):
            for x in (-1.8, 0.0, 1.8):
                b.window(("y", S - 0.19, -1), x, z, 1.2, 1.4)
                pane_dress(b, "y", S - 0.19, -1, x, z, 1.2, 1.4, rain=False)
            for x in (-1.2, 1.2):
                b.window(("y", N + 0.19, 1), x, z, 1.2, 1.4)
                pane_dress(b, "y", N + 0.19, 1, x, z, 1.2, 1.4, rain=False)
            for y in (-1.0, 1.0):
                b.window(("x", hx + 0.19, 1), y, z, 1.1, 1.4)
                pane_dress(b, "x", hx + 0.19, 1, y, z, 1.1, 1.4, rain=False)
        b.box(2.2, S - 0.19 + 0.03, 0.0, 1.0, 0.06, 2.0, "door_wood")
        b.box(2.2, S - 0.19 + 0.05, 2.0, 1.2, 0.07, 0.1, "trim")
        for sx in (-0.55, 0.55):
            b.box(2.2 + sx, S - 0.19 + 0.05, 0.0, 0.1, 0.07, 2.1, "trim")
        b.box(2.2, S - 0.5, 0.0, 1.8, 0.7, 0.2, "plinth_flat")
        b.window(("x", hx + 0.19, 1), 0.0, E + 1.0, 0.8, 0.9, kind=3)      # віконце горища у фронтоні
        lib.window_ring(b, "x", hx + 0.19, 1, 0.0, E + 1.0, 0.8, 0.9)
        b.chimney2("hood", -1.8, 0.0, 8.6, 1.6, "brick_face")       # цегляний із зонтом на гребені
        c_ = 0.19
        lib.weather(b, "wall_plaster", [("y", S - c_, -1, -hx - c_, hx + c_, 0.6, E), ("y", N + c_, 1, -hx - c_, hx + c_, 0.6, E), ("x", hx + c_, 1, S - c_, N + c_, 0.6, E), ("x", -hx - c_, -1, S - c_, N + c_, 0.6, E)], seed=13)
        lib.finish(b, "house_h6", out, tri_limit=2600, footprint=(1, 1))
        return
    kw = dict(top_tone=0.82, inner_tone=0.85, in_mat="plaster_burnt")
    standing = dict(brick_mat="brick_face", cap=0.06, jag=0.1, **kw)
    # біля обваленого кута фронтова стіна обламана сходинками цегли до 3 м, а не обрізана рівно
    wall_run(b, (-hx - 0.2, S), (hx + 0.2, S), 0.4, [E] * 7 + [3.0], "wall_half_w", "wall_plaster_w", 31, hcap=6.2, **standing)
    wall_run(b, (hx + 0.2, N), (-hx - 0.2, N), 0.4, [E] * 8, "wall_half_w", "wall_plaster_w", 32, hcap=6.2, **standing)   # задня стіна з фронтоном ціла
    wall_run(b, (-hx, N), (-hx, S), 0.4, [E] * 8, "wall_half_w", "wall_plaster_w", 33, hcap=6.2, **standing)
    prism(b, [(-hy, E), (hy, E), (hy, E + 0.5), (1.9, E + 0.5), (1.9, E + 1.1), (1.1, E + 1.1), (1.1, E + 1.7), (0.4, E + 1.7), (0.4, E + 1.2), (-0.5, E + 1.2), (-0.5, E + 0.7), (-1.4, E + 0.7), (-1.4, E + 0.2), (-hy, E + 0.2)], 0.4, (-hx, 0.0, 0.0), math.pi / 2, 0.0, "wall_plaster_w", top_mat="brick_dark")   # зламаний верх: п'ять уступів 0.4-0.6 м, на зламі темна цегла   # зламаний верх фронтону
    wall_run(b, (hx, S), (hx, N), 0.4, [1.2, 2.2, 4.2, 5.0, 3.6, 1.8, 1.1, 0.9, 1.5, 2.5, 1.3], "wall_half_w", "chunk_brick", 34, hcap=5.2, jag=0.8, brick_mat="chunk_brick", step=0.7, diag_p=0.6, jit=1.0, cap=0.3, tvar=0.3, **kw)
    zt = E - 0.03
    for fl, z in ((0, 0.9), (1, 3.6)):
        for x in (-1.8, 0.0, 1.8):
            blown = (fl == 1 and x != 0.0) or (fl == 0 and x == 1.8)
            if blown:
                burn_ring(b, "y", S - 0.2, x, z, 1.2, 1.4, -1, g_side=0.35, g_bot=0.15, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
                opening2(b, "y", S - 0.2, x, z, 1.2, 1.4, -1, ztop=zt, streak=0.0, sooty=True)
                lib.window_ring(b, "y", S - 0.2, -1, x, z, 1.2, 1.4)   # лиштва лишилась: проріз читається розміром вікна
            else:
                b.window(("y", S - 0.2, -1), x, z, 1.2, 1.4)
                pane_dress(b, "y", S - 0.2, -1, x, z, 1.2, 1.4)
        for x in (-1.2, 1.2):
            b.window(("y", N + 0.2, 1), x, z, 1.2, 1.4)
            pane_dress(b, "y", N + 0.2, 1, x, z, 1.2, 1.4)
    burn_ring(b, "y", S - 0.2, 2.2, 0.05, 1.0, 2.0, -1, g_side=0.35, g_bot=0.0, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
    opening2(b, "y", S - 0.2, 2.2, 0.05, 1.0, 2.0, -1, ztop=zt, streak=0.0, sooty=True)
    lib.weather(b, "wall_half_w", [("y", S - 0.2, -1, -hx - 0.2, hx + 0.2, 0.0, E)], seed=19, patches=False)
    lib.pocks(b, "y", S - 0.2, -1, 0.5, 3.0, 2.6, 60, 43, zmin=0.2, zmax=5.9)
    # внутрішня грань західного фронтону не чиста штукатурка: кіптява згори, облуплені плями
    xi = -hx + 0.21
    # внутрішня стіна вже з обгорілої штукатурки (in_mat); суцільні площини кіптяви робили її чорною порожнечею
    for (yy, zz, ww, hh_) in ((-1.2, 3.4, 1.1, 0.8), (0.9, 4.2, 0.9, 0.9), (1.7, 3.0, 0.7, 0.6)):      # плями втрати штукатурки: проступає цегла
        b.box(xi + 0.015, yy, zz, 0.03, ww, hh_, "brick_face")
    ph = [rnd.uniform(0, 6.3) for _ in range(3)]

    def cutF(v):
        return 0.4 + 0.6 * math.sin(3 * v + ph[0]) + 0.25 * math.sin(9 * v + ph[1])

    def cutB(v):
        return 1.0 + 0.6 * math.sin(2.6 * v + ph[2]) + 0.25 * math.sin(8 * v + ph[0])
    # дах: лишок ліворуч від краю; скат малюємо від західного кінця до рваного краю
    def roof_west(P, cut):
        nv = 18
        xs = [cut(i / nv) + rnd.uniform(-0.14, 0.14) for i in range(nv)]
        edge = [P(xs[0], 0.0)] + [P(xs[i], (i + 0.5) / nv) for i in range(nv)] + [P(xs[-1], 1.0)]
        b.poly_up([P(xw, 0.0)] + edge + [P(xw, 1.0)], "tile_small")
        edge_thick(b, edge, -1)
        return xs
    xsF = roof_west(PF, cutF)
    xsB = roof_west(PB, cutB)
    break_dress(b, PF, xsF, -1, rnd, battens=False)
    break_dress(b, PB, xsB, -1, rnd, battens=False)
    trim(b, xw, 1.0, ya, yb, E, hx, S, N)
    for x in (1.5, 2.2, 2.8):
        for plate, P, cut in ((S + 0.05, PF, cutF),):
            v1 = rnd.uniform(0.25, 0.55)
            if rnd.random() < 0.2 or not tooth_ok(x, cut, v1, -1):
                continue
            c = P(x, v1)
            b.beam((x, plate, E + 0.05), (c[0], c[1], c[2] - 0.12), 0.14, "timber_dark", 0.22)
    plan = [HeapSurface(3.4, 0.0, 0.85, 2.1, 1.3, 81, bumps=6, lip=0.28, wob=0.15, lump=0.08, hummocks=3, hum_amp=0.3, pw=1.5),
            HeapSurface(1.7, 0.2, 1.5, 2.0, 1.7, 82, bumps=5, lip=0.26, wob=0.15, lump=0.06, hummocks=3, hum_amp=0.5)]
    plan[0].fit_peak(1.0)
    sf = surface(plan)
    chip_slab(b, 1.4, -1.4, FL - 0.1, 2.8, 2.4, 0.22, (0.0, 0.35, 0.05), "slab_dark", "slab_dark", 41, rebar=3, per_edge=2)    # бетон перекриття в кіптяві
    chip_slab(b, 1.8, 1.4, FL - 0.25, 2.6, 2.2, 0.22, (0.0, 0.42, -0.06), "slab_dark", "slab_dark", 42, rebar=2, per_edge=2)
    for (cx_, cy_, cz_) in ((1.0, -1.8, FL + 0.05), (1.5, -1.0, FL + 0.12), (2.1, 1.0, FL - 0.02)):   # цеглини з обваленої стіни на плиті
        b.chunk(cx_, cy_, cz_, 0.28, "chunk_brick", rnd, tone=(0.85, 1.05))
    # дах упав трьома шматками з тієї самої черепиці, що стоїть: лежать на крокві й підлозі, провисли всередину
    chip_slab(b, 1.9, -1.7, 4.7, 2.0, 2.0, 0.12, (-0.5, 0.08, 0.0), "sheet_char", "sheet_char", 43, rebar=0, per_edge=2)
    chip_slab(b, 2.5, 0.1, 3.8, 2.1, 1.9, 0.12, (-0.35, 0.12, 0.1), "sheet_char", "sheet_char", 44, rebar=0, per_edge=2)
    chip_slab(b, 2.9, 1.7, 3.0, 1.9, 1.7, 0.12, (-0.25, 0.18, -0.2), "sheet_char", "sheet_char", 45, rebar=0, per_edge=2)
    bent_sheet(b, (3.2, 1.6, sf(3.2, 1.6) + 0.2), (3.9, 2.4, sf(3.9, 2.4) + 0.12), 0.9, "sheet_char", 0.12, axis="y")
    b.chimney(-1.8, 0.0, 8.0, 0.6, 2.4, "brick_face", cap="plinth_flat")
    lumps(b, plan, rnd, 14)
    bh = heaps(b, plan, 9)
    lib.finish(b, "ruin_half_house2", out, tri_limit=4800, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def shed(ruined, variant=0):
    """Господарський сарай 6.8 x 4.2 м. Напівзруйнований: фронтальна (на камеру) стіна впала, дах з цього боку провис уздовж того самого коника."""
    lib.reset()
    lib.ROOFS["slate_ruin"] = ("tile", (0.15, 0.155, 0.17))                     # темний дах: світлий шифер над бежевими дошками читався блідим деревом
    lib.palette(roof="slate_ruin" if ruined else "asb_old", eave=2.8)
    DM[0] = "boards_soft_vc"
    if ruined:
        # дошки темніші на чверть: бежеві читались блідим деревом, а дах мусить лишатись темнішим за стіну
        mt = lib.mats()
        mt["boards_soft"] = lib.make_material("boards_soft", flat=(0.27, 0.245, 0.21), seams=[("h", 0.18, 0.02, 0.4)], streak=0.5, base_dirt=0.4,
                                              seam_bump=0.8, undul=(1.2, 0.01), rough=0.9)
        mt["boards_soft_vc"] = lib.make_material("boards_soft_vc", flat=(0.27, 0.245, 0.21), seams=[("h", 0.18, 0.02, 0.4)], streak=0.5, base_dirt=0.4,
                                                 vmul=True, seam_bump=0.8, undul=(1.2, 0.01), rough=0.9)
        lib._dm("boards_soft")
    b = Builder()
    rnd = random.Random(57 + 19 * variant)
    hx, hy = 3.4, 2.1
    E, R = 2.8, 3.8
    ya, yb, ym = -(hy + 0.4), hy + 0.4, 0.0
    S, N, XW, XE = -hy, hy, -hx, hx
    xs = [XW - 0.45 + 0.5 * i for i in range(16)]
    for i in range(len(xs) - 1):
        b.poly_up([(xs[i], yb, E), (xs[i + 1], yb, E), (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_xh")
    b.box(0, yb - 0.04, E - 0.14, 2 * hx + 0.8, 0.13, 0.1, "gutter_d")
    if not ruined:
        b.box(0, 0, 0, 2 * hx + 0.3, 2 * hy + 0.3, 0.5, "plinth_dark")
        b.box(0, 0, 0.5, 2 * hx + 0.28, 2 * hy + 0.28, E - 0.5, "boards_soft")
        for sx in (hx, -hx):
            prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.3, (sx, 0.0, 0.0), math.pi / 2, 0.0, "boards_soft", top_mat="boards_soft")
        for i in range(len(xs) - 1):
            b.poly_up([(xs[i], ya, E), (xs[i + 1], ya, E), (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_xh")
        b.box(0, ya + 0.04, E - 0.14, 2 * hx + 0.8, 0.13, 0.1, "gutter_d")
        b.box(hx + 0.2, S - 0.18, 0.12, 0.08, 0.08, E - 0.3, "gutter_d")
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
    wall_run(b, (XW, N), (XW, S), 0.14, [E, E, 2.6, 1.8, 0.7, 0.5], "boards_soft_vc", "boards_soft", 52, hcap=3.0, jag=0.5, step=0.4, diag_p=0.8, jit=0.5, **kw)
    wall_run(b, (XE, S), (XE, N), 0.14, [E] * 6, "boards_soft_vc", "boards_soft", 53, hcap=3.0, jag=0.1, cap=0.06, **kw)
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.14, (XE, 0.0, 0.0), math.pi / 2, 0.0, "boards_soft", top_mat="boards_soft")
    prism(b, [(-hy, E), (hy, E), (0.0, R)], 0.14, (XW, 0.0, 0.0), math.pi / 2, 0.0, "boards_soft", top_mat="boards_soft")
    post_x = (-3.4, -2.27, -1.13, 0.0, 1.13, 2.27, 3.4)
    post_h = (E, 1.8, 0.8, 1.2, 2.3, E, E) if variant == 0 else (E, E, 2.3, 1.0, 0.7, 1.7, E)
    for x, h in zip(post_x, post_h):
        b.box(x, S, 0.0, 0.18, 0.18, h, "timber_dark")
    sheets = ((-1.9, -3.1, 0.1, 2.8, 0.2, 0.22), (0.4, -2.9, -0.15, 2.4, 0.3, 0.3), (-0.5, -3.7, 0.4, 1.8, 0.1, 0.1)) if variant == 0 else \
        ((0.9, -3.2, -0.25, 2.5, 0.2, 0.25), (-1.2, -3.0, 0.2, 2.2, 0.3, 0.28), (2.0, -3.7, 0.5, 1.7, 0.1, 0.1))
    for (x, y, rot, ln, z, ang) in sheets:
        for k in (-1, 0, 1):                                                  # лист ламаний на три смуги з різним нахилом: блиск не заливає весь лист
            b.box_e(x - math.sin(rot) * 0.64 * k, y + math.cos(rot) * 0.64 * k, z + 0.2 + 0.03 * k, ln, 0.62, 0.05, "roof_fallen", euler=(ang + 0.2 * k, 0.12 * k, rot), top="roof_fallen")   # лист зламаний на три смуги з помітним заломом
    b.cyl(-2.95 + 5.2 * variant, -2.35, 0.0, 0.3, 0.9, 12, "steel_paint")                       # бочка й ящик на землі біля впалої стіни
    b.box(-2.35 + 4.4 * variant, -2.5, 0.0, 0.7, 0.5, 0.5, "boards_soft", rot=0.3 + 0.9 * variant)
    zt = E - 0.03
    opening2(b, "x", XE + 0.1, -0.3, 0.05, 1.3, 2.2, 1, ztop=zt, streak=0.0, sooty=True)
    burn_ring(b, "x", XE + 0.1, -0.3, 0.05, 1.3, 2.2, 1, g_side=0.35, g_bot=0.0, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
    opening2(b, "y", N + 0.1, 1.8, 0.9, 1.4, 1.3, 1, ztop=zt, streak=0.0, sooty=True)
    lib.window_ring(b, "y", N + 0.1, 1, 1.8, 0.9, 1.4, 1.3)   # лиштва лишилась: проріз читається розміром вікна
    burn_ring(b, "y", N + 0.1, 1.8, 0.9, 1.4, 1.3, 1, g_side=0.35, g_bot=0.15, g_top=2.2, t_in=0.22, t_out=0.62, ztop=zt, mat=DM[0])
    opening2(b, "y", N + 0.1, -2.0, 1.1, 0.8, 0.9, 1, ztop=zt, streak=0.0, sooty=True)
    lib.window_ring(b, "y", N + 0.1, 1, -2.0, 1.1, 0.8, 0.9)   # лиштва лишилась: проріз читається розміром вікна

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
    hole = {i for i, x in enumerate(xs[:-1]) if (-2.0 < x < -1.0 if variant == 0 else 0.9 < x < 1.9)}
    for i in range(len(xs) - 1):
        if i not in hole:
            b.poly_up([pts[i], pts[i + 1], (xs[i + 1], ym, R), (xs[i], ym, R)], "fc_roof_xh")
    for x in (-1.8, -1.5, -1.2):
        j = min(range(len(xs)), key=lambda k: abs(xs[k] - x))
        b.beam(pts[j], (xs[j], ym, R - 0.05), 0.1, "timber_dark", 0.16)
    plan = [HeapSurface(-0.8 + 2.0 * variant, 0.1, 1.3, 0.9, 0.5, 92 + variant, bumps=5, lip=0.22, wob=0.08, lump=0.04, hummocks=1, hum_amp=0.12)]
    lumps(b, plan, rnd, 8)
    bh = heaps(b, plan, 11 + 3 * variant, dens=6.0)
    lib.finish(b, "ruin_half_shed" + ("_b" if variant else ""), out, tri_limit=4600, footprint=(1, 1), hi=bh, ground_clip=True, ao=0.35)


def shed_variant(name, kind):
    """Інші сараї для дворів: brick — цегляний 5 x 3.6 м під темно-коричневим двосхилим дахом із темними сталевими дверима;
    lean — дерев'яна прибудова з односхилим дахом із зеленого профлисту."""
    lib.reset()
    lib.ROOFS["felt_black"] = ("tile", (0.16, 0.125, 0.11))                # руберойд: майже чорно-коричневий, темніший за цеглу
    lib.palette(roof="felt_black" if kind == "brick" else "green_dark", eave=2.4)
    mt = lib.mats()
    if kind == "brick":
        # темна цегла під темно-коричневим руберойдом: на сонці світла цегла й зелений дах читалися живоплотом
        mt["brick_face"] = lib.make_material("brick_face", "Bricks105", 1.0, recolor=(0.40, 0.22, 0.17), streak=0.3, base_dirt=0.6, bump=0.02,
                                             patch=((0.09, 0.06, 0.04), 0.2), patch_scale=1.6)
        lib._dm("brick_face")
    else:
        # дошки прибудови сірі й темні, не бежеві: світле дерево лишалося плямою на траві
        mt["boards_soft"] = lib.make_material("boards_soft", flat=(0.165, 0.154, 0.139), seams=[("h", 0.18, 0.02, 0.4)], streak=0.5, base_dirt=0.4,
                                              seam_bump=0.8, undul=(1.2, 0.01), rough=0.9)
        lib._dm("boards_soft")
    b = Builder()
    hx, hy, E = (2.5, 1.8, 2.4) if kind == "brick" else (2.2, 1.6, 2.2)
    if kind == "brick":
        R_ = 3.4
        b.box(0, 0, 0, 2 * hx + 0.08, 2 * hy + 0.08, 0.3, "plinth_dark")
        b.box(0, 0, 0.3, 2 * hx, 2 * hy, E - 0.3, "brick_face")
        b.gable(-hx, hx, -hy, hy, E, R_, "fc_roof_xh", "brick_face", ridge_axis="x", overhang=0.3)
        b.box(0, -hy - 0.03, 0.3, 0.9, 0.06, 1.9, "door_steel")
        b.window(("x", hx, 1), 0.0, 1.2, 0.6, 0.5, kind=0)
        lib.window_ring(b, "x", hx, 1, 0.0, 1.2, 0.6, 0.5, t=0.06, mat="brick_face")
        lib.weather(b, "brick_face", [("y", -hy, -1, -hx, hx, 0.3, E), ("x", hx, 1, -hy, hy, 0.3, E)], seed=61, patches=False)
    else:
        Eb = E + 0.9                                                              # задня стіна вища: односхилий дах
        b.box(0, 0, 0, 2 * hx + 0.06, 2 * hy + 0.06, 0.25, "plinth_dark")
        b.box(0, 0, 0.25, 2 * hx, 2 * hy, E - 0.25, "boards_soft")
        lib._quad(b, [(-hx, hy, E), (hx, hy, E), (hx, hy, Eb), (-hx, hy, Eb)], "boards_soft", (0, 1, 0))
        for sx in (-1, 1):
            tri = [(sx * hx, -hy, E), (sx * hx, hy, E), (sx * hx, hy, Eb)]
            v = [Vector(q) for q in tri]
            n_ = (v[1] - v[0]).cross(v[2] - v[1])
            f = b.poly(tri if n_.x * sx > 0 else tri[::-1], "boards_soft")
            b.facing.append((f, Vector((sx, 0, 0))))
        b.poly_up([(-hx - 0.3, -hy - 0.4, E - 0.12), (hx + 0.3, -hy - 0.4, E - 0.12), (hx + 0.3, hy + 0.25, Eb + 0.06), (-hx - 0.3, hy + 0.25, Eb + 0.06)], "fc_roof_xh")
        b.box(-0.8, -hy - 0.03, 0.25, 1.0, 0.06, 1.8, "door_steel")
        lib.weather(b, "boards_soft", [("y", -hy, -1, -hx, hx, 0.25, E)], seed=63, patches=False)
    lib.finish(b, name, out, tri_limit=1200, footprint=(1, 1))


for fn, nm in ((house1, "house1"), (house2, "house2"), (shed, "shed")):
    if want(nm):
        fn(False)
        fn(True)
# Лише руїни: перебудова ruin_*, не чіпаючи цілих двійників; «b» — той самий слід, інший виріз даху, завал і розкидані листи.
for fn, nm, v in ((house1, "ruin_house1", 0), (house1, "ruin_house1b", 1), (house2, "ruin_house2", 0), (shed, "ruin_shed", 0), (shed, "ruin_shedb", 1)):
    if want(nm):
        fn(True, v)
if want("shed_brick"):
    shed_variant("f8_shed_brick", "brick")
if want("shed_lean"):
    shed_variant("f8_shed_lean", "lean")
