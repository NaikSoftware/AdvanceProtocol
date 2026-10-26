"""Сільські будинки H1-H4, пошкоджений H1 і руїни H1, H3 — у тому самому конвеєрі й тими самими
матеріалами, що решта будівель. Розміри з брифу, слід — ціле число тайлів (меш усередині,
виступ не більше 0.1 тайла). Фронт — +Y, коник уздовж X. Камера гри бачить боки -Y і +X, тому
пошкодження скрізь на цих боках."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import opening2, Builder, chunks, mound, mound_radius, wall_run, bent_sheet, burn_ring, HeapSurface, heap_mound
from mathutils import Vector

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


def sills(b, x, y, sgn, w, z, axis):
    """Відлив на 5 см далі за наличник (0.12 м), тож під ним лягає тінь."""
    if axis == "y":
        b.box(x, y + 0.085 * sgn, z - 0.08, w + 0.34, 0.17, 0.08, "step")
    else:
        b.box(x + 0.085 * sgn, y, z - 0.08, 0.17, w + 0.34, 0.08, "step")


def blown(b, x, y, sgn, z, w, h, axis="y"):
    """Вибите вікно: чорний проріз розміру цілого вікна і кіптява навколо нього (нижче карниза)."""
    e = 0.03 * sgn
    if axis == "y":
        quad = [(x - w / 2, y + e, z), (x + w / 2, y + e, z), (x + w / 2, y + e, z + h), (x - w / 2, y + e, z + h)]
    else:
        quad = [(x + e, y - w / 2, z), (x + e, y + w / 2, z), (x + e, y + w / 2, z + h), (x + e, y - w / 2, z + h)]
    if axis == "y":
        opening2(b, "y", y, x, z, w, h, sgn, streak=0.0, sooty=True)
    else:
        opening2(b, "x", x, y, z, w, h, sgn, streak=0.0, sooty=True)
    burn_ring(b, axis, y if axis == "y" else x, x if axis == "y" else y, z, w, h, sgn, g_side=0.3, g_bot=0.1, g_top=1.9, ztop=2.95, mat="wall_plaster_dm")
    lib.window_ring(b, axis, y if axis == "y" else x, sgn, x if axis == "y" else y, z, w, h)   # проріз у лиштві: читається втопленим отвором, а не плямою
    lib.pocks(b, axis, y if axis == "y" else x, sgn, x if axis == "y" else y, z + h / 2, 1.6, 10, int(abs(x * 7 + y * 13)) + 3, zmin=0.55, zmax=2.9)


RING = ["trim", 0.1, False]              # наличник поточного будинку: матеріал, ширина лиштви (мала — лише укіс), віконниці


def win_front(b, y, sgn, xs, z, w=1.2, h=1.4, bl=()):
    for x in xs:
        if x in bl:
            blown(b, x, y, sgn, z, w, h)
        else:
            b.window(("y", y, sgn), x, z, w, h)
            lib.window_ring(b, "y", y, sgn, x, z, w, h, t=RING[1], mat=RING[0])
            if RING[2]:
                shutters(b, "y", y, sgn, x, z, w, h)
        sills(b, x, y, sgn, w, z, "y")


def win_side(b, x, sgn, ys, z, w=1.2, h=1.4, bl=()):
    for y in ys:
        if y in bl:
            blown(b, x, y, sgn, z, w, h, "x")
        else:
            b.window(("x", x, sgn), y, z, w, h)
            lib.window_ring(b, "x", x, sgn, y, z, w, h, t=RING[1], mat=RING[0])
            if RING[2]:
                shutters(b, "x", x, sgn, y, z, w, h)
        sills(b, x, y, sgn, w, z, "x")


def shutters(b, axis, c, sgn, u, z, w, h):
    """Дерев'яні віконниці обабіч вікна, відчинені до стіни."""
    for sx in (-1, 1):
        uu = u + sx * (w / 2 + RING[1] + w / 4 + 0.02)
        if axis == "y":
            b.box(uu, c + 0.03 * sgn, z, w / 2, 0.04, h, "door_wood")
        else:
            b.box(c + 0.03 * sgn, uu, z, 0.04, w / 2, h, "door_wood")


def gutter(b, x0, x1, y, z):
    b.box((x0 + x1) / 2, y, z, x1 - x0, 0.14, 0.14, "gutter")


def pipe(b, x, y, sgn, ov, eave):
    """Водостічна труба на 8 см від стіни y і коліно до ринви, що висить на ov за стіною."""
    lib.downpipe(b, x, y + 0.08 * sgn, eave - 0.45)
    b.box(x, y + sgn * (0.08 + ov) / 2, eave - 0.45, 0.1, ov - 0.04, 0.1, "gutter")


def post(b, x, y, z0, h):
    b.box(x, y, z0, 0.18, 0.18, h, "pvc")


# ----------------------------------------------------------------------- H1
def house1(hit=False):
    lib.reset()
    lib.palette(wall=(0.70, 0.63, 0.53), roof="asb_dark", eave=3.0, chim="ch_grey", frame=3, trim=0.88)
    RING[:] = ["trim", 0.1, False]
    b = Builder()
    b.win_kind, b.win_mix = 0, (1, 0.4)                                     # старі дерев'яні на три стулки, частину замінено пластиковими
    L, Db, EAVE, RIDGE = 10.0, 6.4, 3.0, 6.5      # корпус 10 x 6.4, веранда ще 1.6 м (разом 8 м)
    y0, y1 = -4.0, 2.4
    b.box(0, (y0 + y1) / 2, 0, L + 0.08, Db + 0.08, 0.5, "brick_grey")          # цоколь на 4 см за стіною
    b.box(0, (y0 + y1) / 2, 0.5, L - 0.02, Db - 0.02, EAVE - 0.5, "wall_plaster")
    if not hit:                                                                  # у пошкодженої хати кути обсипались (і бюджет трикутників)
        lib.quoins(b, [(-L / 2, y0, 1, 1), (L / 2, y0, -1, 1), (L / 2, y1, -1, -1)], 0.5, EAVE - 0.05)
    ym = (y0 + y1) / 2
    d = Db / 2
    OV = 0.5
    xa, xb, ya, yb = -L / 2 - OV, L / 2 + OV, y0 - OV, y1 + OV
    xr0, xr1 = -L / 2 + d, L / 2 - d
    b.poly([(xa, yb, EAVE), (xa, ya, EAVE), (xr0, ym, RIDGE)], "fc_roof_h")
    b.poly([(xb, ya, EAVE), (xb, yb, EAVE), (xr1, ym, RIDGE)], "fc_roof_h")
    if not hit:
        b.poly([(xa, ya, EAVE), (xb, ya, EAVE), (xr1, ym, RIDGE), (xr0, ym, RIDGE)], "fc_roof_xh")
        b.poly([(xb, yb, EAVE), (xa, yb, EAVE), (xr0, ym, RIDGE), (xr1, ym, RIDGE)], "fc_roof_xh")
    else:
        rr = random.Random(77)

        def P(u, v):                                   # похилий скат -Y, що його бачить камера
            e = (xa + (xb - xa) * u, ya, EAVE)
            r = (xr0 + (xr1 - xr0) * u, ym, RIDGE)
            return tuple(e[i] * (1 - v) + r[i] * v for i in range(3))
        nh = 8
        vs = [i / nh for i in range(nh + 1)]
        ds = 0.5 / (xb - xa)                                                      # шви листів 0.5 м: край рветься по них, під прямими кутами
        spikes = set(rr.sample(range(1, nh), 3))
        uL, uR = [], []
        for i, v in enumerate(vs):
            cen = 0.5 + 0.04 * math.sin(v * 5.0 + 1.0)
            half = 0.16 + 0.12 * math.sin(math.pi * min(1.0, v * 0.85 + 0.1)) + rr.uniform(-0.03, 0.03)
            if i in spikes:
                half += rr.choice((-1, 1)) * rr.uniform(0.05, 0.09)
            uL.append(round((cen - half) / ds) * ds)
            uR.append(round((cen + half) / ds) * ds)
        left = [(0, 0)] + [(uL[i], vs[i]) for i in range(nh + 1)] + [(0, 1)]
        right = [(uR[i], vs[i]) for i in range(nh + 1)] + [(1, 1), (1, 0)]
        b.poly_up([P(u, v) for (u, v) in left], "fc_roof_xh")
        b.poly_up([P(u, v) for (u, v) in right], "fc_roof_xh")
        # карнизна плита під розривом: той самий лист із швами, а не гладка смуга
        b.poly_up([P(uL[0], 0.0), P(uR[0], 0.0), P(uR[0], 0.09), P(uL[0], 0.09)], "fc_roof_xh")
        # одна м'яка підпалина, віднесена вітром угору по скату: під розривом ~0.2 м, над ним до ~1.5 м; край рваний язиками
        for edge, sgn_ in ((uL, -1), (uR, 1)):
            prev = None
            for k in range(25):
                v = k / 24
                xx = v * nh
                ii = min(nh - 1, int(xx))
                fr_ = xx - ii
                u_in = edge[ii] * (1 - fr_) + edge[ii + 1] * fr_
                p_in = P(u_in, v)
                p_out = P(u_in + sgn_ * rr.uniform(0.045, 0.1), min(1.0, v + rr.uniform(0.0, 0.05)))
                cur = (p_in, p_out, rr.uniform(0.08, 0.14), 1.0)
                if prev is not None:
                    pts = [prev[0], cur[0], cur[1], prev[1]]
                    pts = [(x, y - 0.025, z + 0.03) for (x, y, z) in pts]
                    tn_ = [prev[2], cur[2], cur[3], prev[3]]
                    n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
                    if n_.z < 0:
                        n_ = -n_
                    b.decal(pts, tn_, "fc_roof_xh_dm", tuple(n_.normalized()))      # кіптява множником на шифері: згасає в колір даху
                prev = cur
        for k in range(16):                                                       # язики сажі вгору від верхніх країв розриву, різної довжини
            side_ = rr.choice((-1, 1))
            edge = uL if side_ < 0 else uR
            v0 = rr.uniform(0.35, 0.95)
            xx = v0 * nh
            ii = min(nh - 1, int(xx))
            u0_ = edge[ii] * (1 - (xx - ii)) + edge[ii + 1] * (xx - ii)
            ln_ = rr.uniform(0.06, 0.2)
            w_ = rr.uniform(0.01, 0.03)
            pts = [P(u0_ - w_, v0), P(u0_ + w_, v0), P(u0_ + w_ * 0.4 - side_ * 0.01, min(1.0, v0 + ln_)), P(u0_ - w_ * 0.4 - side_ * 0.01, min(1.0, v0 + ln_))]
            pts = [(x, y - 0.025, z + 0.03) for (x, y, z) in pts]
            tn_ = [rr.uniform(0.1, 0.16), rr.uniform(0.1, 0.16), 0.7, 0.7]
            n_ = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
            if n_.z < 0:
                n_ = -n_
            b.decal(pts, tn_, "fc_roof_xh_dm", tuple(n_.normalized()))
        for edge, sgn_ in ((uL, -1), (uR, 1)):                                    # переламані рейки стирчать у розрив
            for i in range(1, nh):
                if rr.random() < 0.45:
                    continue
                a_ = P(edge[i] + sgn_ * 0.02, vs[i])
                c_ = P(edge[i] - sgn_ * rr.uniform(0.03, 0.08), vs[i])
                b.beam((a_[0], a_[1], a_[2] - 0.05), (c_[0], c_[1], c_[2] - 0.1), 0.05, "timber_hit", 0.04)
        for v_ in (0.17, 0.33, 0.62, 0.8):                                        # 4 рейки впоперек скату з нерівними проміжками, одна обламана й звисає
            iL = min(range(nh + 1), key=lambda k: abs(vs[k] - v_))
            a_, c_ = P(uL[iL] - 0.02, v_), P(uR[iL] + 0.02, v_)
            if v_ == 0.62:
                c_ = (c_[0] - (c_[0] - a_[0]) * 0.45, c_[1], c_[2] - 0.55)
            b.beam((a_[0], a_[1], a_[2] - 0.06), (c_[0], c_[1], c_[2] - 0.06), 0.05, "timber_hit", 0.05)
        lib.bent_sheet(b, P(uL[3] + 0.01, vs[3]), (P(uL[3] + 0.06, vs[3])[0], P(uL[3], vs[3])[1] + 0.9, P(uL[3], vs[3])[2] - 0.9), 0.9, "sheet_char", 0.18, axis="x")
        lib.bent_sheet(b, P(uR[6] - 0.01, vs[6]), (P(uR[6] - 0.05, vs[6])[0], P(uR[6], vs[6])[1] + 0.8, P(uR[6], vs[6])[2] - 0.8), 0.9, "sheet_char", 0.15, axis="x")
        # +Y скат з надірваним гребенем
        b.poly_up([(xb, yb, EAVE), (xa, yb, EAVE), (xr0, ym, RIDGE), (-1.2, ym + 0.2, RIDGE - 0.4), (0.0, ym + 0.8, RIDGE - 1.2), (1.4, ym + 0.3, RIDGE - 0.6), (xr1, ym, RIDGE)], "fc_roof_xh")
        for k in range(7):                              # мокрі темні крокви, що лишились, з обламаними кінцями
            u = 0.34 + 0.05 * k
            if u > 0.69:
                break
            b.beam(P(u, 0.06 + 0.1 * rr.random()), P(u + 0.01, 0.9 - 0.25 * rr.random()), 0.14, "timber_hit", 0.2)
        b.beam(P(0.32, 0.55), P(0.68, 0.6), 0.14, "timber_hit", 0.2)
        for k in range(4):                                                        # уламки на скаті: шифер, цегла димаря, штукатурка — вибух розкидав їх навколо розриву
            side_ = rr.choice((-1, 1))
            v_ = rr.uniform(0.05, 0.8)
            ii = min(nh - 1, int(v_ * nh))
            u_ = (uL[ii] - rr.uniform(0.02, 0.12)) if side_ < 0 else (uR[ii] + rr.uniform(0.02, 0.12))
            q = P(u_, v_)
            sz = rr.uniform(0.15, 0.3)
            b.chunk(q[0], q[1] - 0.02, q[2] + sz * 0.25, sz, rr.choice(("chunk_brick", "chunk_plaster", "chunk_concrete")), rr, tone=(0.55, 0.9))
        # порожнина: один неосвітлений майже чорний чотирикутник над верхами стін (ними плашка штукатурки світилась)
        b.poly([(-4.7, y0 + 0.1, EAVE + 0.12), (4.7, y0 + 0.1, EAVE + 0.12), (4.7, y1 - 0.1, EAVE + 0.12), (-4.7, y1 - 0.1, EAVE + 0.12)][::-1], "cavity")
        for k in range(9):                                                        # балки перекриття горища: тьмяно видно крізь розрив
            b.box(-4.0 + 1.0 * k, (y0 + y1) / 2, EAVE + 0.12, 0.14, y1 - y0 - 0.4, 0.16, "timber_hit")
        for (sx_, sw_, sh_) in ((-1.4, 0.9, 0.35), (-0.3, 0.7, 0.6), (0.8, 1.0, 0.25)):    # східчастий зламаний верх стіни
            b.box(xa + (xb - xa) * 0.51 + sx_, y0 + 0.2, EAVE, sw_, 0.4, sh_, "plaster_char", top="brick_dark")
        # стіна під розривом карниза: темна зверху, світлішає донизу (кіптява над місцем виходу диму)
        xl, xr = xa + (xb - xa) * 0.30, xa + (xb - xa) * 0.72
        nst = 16
        w_ = (xr - xl) / nst
        for i in range(nst):                                                      # смужки однакової глибини: тон плавно переходить у тон стіни, без чорного краю
            dep = 1.25 + rr.uniform(-0.05, 0.05)
            x0_, x1_ = xl + i * w_, xl + (i + 1) * w_
            b.decal([(x0_, y0 - 0.03, EAVE - dep), (x1_, y0 - 0.03, EAVE - dep), (x1_, y0 - 0.03, EAVE), (x0_, y0 - 0.03, EAVE)], (1.0, 1.0, 0.12, 0.12), "wall_plaster_dm", (0, -1, 0))
    if not hit:
        b.box(0, ym, RIDGE, xr1 - xr0 + 0.6, 0.3, 0.16, "gutter")
    b.chimney2("brick" if hit else "hood", 2.2, -0.2, 5.4, 2.3, "brick_face")   # один димар: у цілої хати з зонтом, у пошкодженої цегляний
    bl = (-3.2, 0.0) if hit else ()
    win_front(b, y0, -1, (-3.2, 0.0, 3.2), 1.0, bl=bl)
    win_front(b, y1, 1, (-4.0, 4.0), 1.0)
    win_side(b, -L / 2, -1, (-1.0,), 1.0)
    win_side(b, L / 2, 1, (-1.0, 1.0), 1.0, bl=((-1.0,) if hit else ()))
    b.box(-3.9, y1 + 0.03, 0.5, 1.0, 0.06, 2.0, "door_red")
    b.box(0, 3.2, 0, 6.0, 1.6, 0.35, "step", top="step")                         # засклена веранда
    for px in (-3.0, -1.0, 1.0, 3.0):
        post(b, px, 3.9, 0.35, 1.95)                                              # верх під дахом веранди, не крізь нього
    for px in (-2.0, 0.0, 2.0):
        b.window(("y", 3.92, 1), px, 0.6, 1.8, 1.55)
    b.poly_up([(-3.4, 2.4, 2.75), (3.4, 2.4, 2.75), (3.4, 4.3, 2.35), (-3.4, 4.3, 2.35)], "fc_roof_xh")
    b.box(0, 4.15, 0.0, 1.2, 0.5, 0.25, "step")
    if hit:
        gutter(b, xa + (xb - xa) * 0.72, L / 2 + OV, y0 - OV, EAVE - 0.3)
    else:
        gutter(b, -L / 2 - OV, L / 2 + OV, y0 - OV, EAVE - 0.3)
    pipe(b, L / 2 - 0.35, y0, -1, OV, EAVE)
    bh = None
    if hit:
        rr = random.Random(54)
        plan_ = [lib.HeapSurface(-0.6, -3.95, 2.6, 0.55, 1.0, 51, bumps=6, lip=0.2, wob=0.15, lump=0.08, hummocks=3, hum_amp=0.5, sq=2.0, noise=1.5, feather=0.5)]
        bh = lib.rubble_heaps(b, plan_, 54, dens=9.0, skirt=0.25)
        lib.rubble_lumps(b, plan_, rr, 30, tmin=0.1, tmax=0.95, size=(0.2, 0.5))
    lib.weather(b, "wall_plaster", [("y", y0, -1, -L / 2, L / 2, 0.5, EAVE), ("y", y1, 1, -L / 2, L / 2, 0.5, EAVE), ("x", -L / 2, -1, y0, y1, 0.5, EAVE), ("x", L / 2, 1, y0, y1, 0.5, EAVE)], seed=3)
    lib.finish(b, "house_h1_hit" if hit else "house_h1", out, tri_limit=2600, footprint=(2, 1), anchor=(0, 0), hi=bh)


# ----------------------------------------------------------------------- H2
def house2():
    lib.reset()
    b = Builder()
    b.win_kind = 2                                                                # широкі двостулкові з фрамугою
    lib.palette(roof="brown_dark", eave=3.2, chim="ch_orange", row=0.25, frame=1)
    RING[:] = ["brick_muted", 0.1, False]
    L, D, EAVE, RIDGE = 11.0, 9.0, 3.2, 7.0
    y0, y1 = -D / 2, D / 2
    b.box(0, 0, 0, L + 0.08, D + 0.08, 0.5, "brick_grey")
    b.box(0, 0, 0.5, L - 0.02, D - 0.02, EAVE - 0.5, "brick_muted")
    b.gable(-L / 2, L / 2, y0, y1, EAVE, RIDGE, "tile_brown", "brick_muted", ridge_axis="x", overhang=0.4)
    b.box(0, 0, RIDGE, L + 0.8, 0.3, 0.18, "gutter")
    b.chimney2("brick", -2.5, 0.0, 6.4, 1.9, "brick_face")      # високий цегляний на гребені
    win_front(b, y1, 1, (-4.0, 4.0), 1.1, 1.6, 1.3)
    win_front(b, y0, -1, (-3.5, 0.0, 3.5), 1.1, 1.6, 1.3)
    win_side(b, -L / 2, -1, (-1.5, 1.5), 1.1, 1.6, 1.3)
    win_side(b, L / 2, 1, (-1.5, 1.5), 1.1, 1.6, 1.3)
    b.window(("x", L / 2, 1), 0.0, EAVE + 1.4, 0.6, 0.8, kind=3)                 # віконце горища у фронтоні
    lib.window_ring(b, "x", L / 2, 1, 0.0, EAVE + 1.4, 0.6, 0.8, t=0.08, mat="brick_muted")
    b.box(0, y1 + 1.0, 0, 3.2, 2.0, 2.7, "brick_muted", top="tile_brown")
    b.box(0, y1 + 2.02, 0, 1.2, 0.04, 2.1, "door_wood")
    b.box(0, y1 + 2.0, 0, 1.8, 0.9, 0.2, "step")
    b.window(("x", 1.6, 1), y1 + 1.0, 1.0, 0.9, 1.0)
    b.window(("x", -1.6, -1), y1 + 1.0, 1.0, 0.9, 1.0)
    b.box(L / 2 + 0.3, 0.0, 5.0, 0.15, 0.7, 0.7, "pvc")
    gutter(b, -L / 2 - 0.4, L / 2 + 0.4, y1 + 0.4, EAVE - 0.3)
    gutter(b, -L / 2 - 0.4, L / 2 + 0.4, y0 - 0.4, EAVE - 0.3)
    pipe(b, L / 2 - 0.35, y0, -1, 0.4, EAVE)
    lib.weather(b, "brick_muted", [("y", y0, -1, -L / 2, L / 2, 0.5, EAVE), ("y", y1, 1, -L / 2, L / 2, 0.5, EAVE), ("x", -L / 2, -1, y0, y1, 0.5, EAVE), ("x", L / 2, 1, y0, y1, 0.5, EAVE)], seed=5, patches=False)
    lib.finish(b, "house_h2", out, tri_limit=2200, footprint=(2, 2), target_cm=3.6)


# ----------------------------------------------------------------------- H3
def house3():
    lib.reset()
    b = Builder()
    lib.palette(wall=(0.63, 0.65, 0.58), roof="graphite_dark", eave=6.0, row=0.3, frame=2, trim=0.95)
    RING[:] = ["trim", 0.025, False]                                          # сучасна хата: без виступної лиштви, лише укіс
    L, D, EAVE, RIDGE = 10.0, 10.0, 6.0, 9.5
    y0, y1 = -D / 2, D / 2
    OV = 0.5
    b.box(0, 0, 0, L + 0.08, D + 0.08, 1.0, "brick_grey")
    b.box(0, 0, 1.0, L - 0.02, D - 0.02, EAVE - 1.0, "wall_plaster")
    b.gable(-L / 2, L / 2, y0, y1, EAVE, RIDGE, "tile_graphite", "wall_plaster", ridge_axis="x", overhang=OV)
    b.box(0, 0, RIDGE, L + 1.0, 0.3, 0.18, "gutter")
    # фотоелектрична батарея 5 x 3.4 м на скаті, який бачить камера (-Y)
    run = -(y0 - OV)
    sl = math.hypot(run, RIDGE - EAVE)
    ny, nz = (RIDGE - EAVE) / sl, run / sl

    def pv(x, s):
        return (x, -(run - s * run / sl + 0.05 * ny), EAVE + s * (RIDGE - EAVE) / sl + 0.05 * nz)
    b.poly_up([pv(-2.5, 1.2), pv(2.5, 1.2), pv(2.5, 4.6), pv(-2.5, 4.6)], "pv")
    for (xa_, sa, xb_, sb) in ((-2.6, 1.15, 2.6, 1.25), (-2.6, 4.55, 2.6, 4.65), (-2.6, 1.15, -2.5, 4.65), (2.5, 1.15, 2.6, 4.65)):
        q0, q1 = pv(xa_, sa), pv(xb_, sb)
        b.beam((q0[0], q0[1], q0[2] + 0.03), (q1[0], q1[1], q1[2] + 0.03), 0.09, "pv_frame", 0.09)
    for fl, z in ((0, 1.5), (1, 3.9)):                      # верхній ряд на 0.3 м нижче: карниз не ховає вікна
        win_front(b, y1, 1, (-3.5, 0.0, 3.5) if fl else (-3.5, 3.5), z, 1.3, 1.5)
        win_front(b, y0, -1, (-3.5, 0.0, 3.5), z, 1.3, 1.5)
        win_side(b, -L / 2, -1, (-2.0, 2.0), z, 1.3, 1.5)
        win_side(b, L / 2, 1, (-2.0, 2.0), z, 1.3, 1.5)
    b.box(0, y1 + 0.03, 1.0, 1.2, 0.06, 2.2, "metal_dark")
    for px in (-1.4, 1.4):
        post(b, px, y1 + 1.5, 1.0, 2.4)
    b.poly_up([(-1.8, y1, 3.5), (1.8, y1, 3.5), (1.8, y1 + 1.7, 3.1), (-1.8, y1 + 1.7, 3.1)], "tile_graphite")
    b.box(0, y1 + 1.4, 0.0, 3.2, 1.6, 1.0, "step", top="step")
    gutter(b, -L / 2 - OV, L / 2 + OV, y1 + OV, EAVE - 0.3)
    gutter(b, -L / 2 - OV, L / 2 + OV, y0 - OV, EAVE - 0.3)
    pipe(b, L / 2 - 0.35, y0, -1, OV, EAVE)
    b.window(("x", L / 2, 1), 0.0, 6.7, 0.9, 1.1)                                # вікно горища у фронтоні: середник і імпост — у шейдері
    lib.window_ring(b, "x", L / 2, 1, 0.0, 6.7, 0.9, 1.1)
    sills(b, L / 2, 0.0, 1, 0.9, 6.7, "x")
    b.chimney2("steel", 3.8, -3.5, 7.0, 1.4)                     # новіша хата: сталева труба з ковпаком біля звису
    lib.weather(b, "wall_plaster", [("y", y0, -1, -L / 2, L / 2, 1.0, EAVE), ("y", y1, 1, -L / 2, L / 2, 1.0, EAVE), ("x", -L / 2, -1, y0, y1, 1.0, EAVE), ("x", L / 2, 1, y0, y1, 1.0, EAVE)], seed=7, patches=False)
    lib.finish(b, "house_h3", out, tri_limit=2400, footprint=(2, 2), target_cm=3.6)


# ----------------------------------------------------------------------- H4
def house4():
    lib.reset()
    b = Builder()
    lib.palette(roof="oxide_dark", eave=3.0, chim="ch_orange", boards=(0.50, 0.55, 0.57), trim=(0.44, 0.37, 0.29))
    RING[:] = ["trim", 0.08, True]                                            # стара дерев'яна хата: віконниці
    b.win_kind = 0
    L, D, EAVE, RIDGE = 9.0, 6.0, 3.0, 6.5
    y0, y1 = -D / 2, D / 2
    b.box(0, 0, 0, L + 0.08, D + 0.08, 0.4, "brick_grey")
    b.box(0, 0, 0.4, L - 0.02, D - 0.02, EAVE - 0.4, "boards")
    b.gable(-L / 2, L / 2, y0, y1, EAVE, RIDGE, "tin_green", "boards", ridge_axis="x", overhang=0.4)
    b.box(0, 0, RIDGE, L + 0.8, 0.28, 0.16, "gutter")
    win_front(b, y1, 1, (-3.0, 3.0), 1.0, 1.0, 1.4)
    win_front(b, y0, -1, (-2.5, 2.5), 1.0, 1.0, 1.4)
    win_side(b, -L / 2, -1, (0.0,), 1.0, 1.0, 1.4)
    win_side(b, L / 2, 1, (0.0,), 1.0, 1.0, 1.4)
    b.box(0, y1 + 0.03, 0.4, 1.0, 0.06, 2.0, "door_wood")
    for px in (-1.1, 1.1):
        post(b, px, y1 + 1.4, 0.4, 2.2)
    b.poly_up([(-1.5, y1, 2.7), (1.5, y1, 2.7), (1.5, y1 + 1.6, 2.3), (-1.5, y1 + 1.6, 2.3)], "tin_green")
    b.box(0, y1 + 1.0, 0, 3.0, 1.4, 0.4, "step", top="step")
    b.chimney(L / 2 + 0.52, 1.0, 0.0, 1.0, 6.0, "brick_face")        # приставний цегляний 1 x 1 м до фронтону, від землі
    gutter(b, -L / 2 - 0.4, L / 2 + 0.4, y0 - 0.4, EAVE - 0.3)
    gutter(b, -L / 2 - 0.4, L / 2 + 0.4, y1 + 0.4, EAVE - 0.3)
    pipe(b, L / 2 - 0.35, y0, -1, 0.4, EAVE)
    lib.weather(b, "boards", [("y", y0, -1, -L / 2, L / 2, 0.4, EAVE), ("y", y1, 1, -L / 2, L / 2, 0.4, EAVE), ("x", -L / 2, -1, y0, y1, 0.4, EAVE), ("x", L / 2, 1, y0, y1, 0.4, EAVE)], seed=9, patches=False)
    lib.finish(b, "house_h4", out, tri_limit=1800, footprint=(2, 1))


# ----------------------------------------------------------------------- руїни
def ruin(name, L, D, keep, seed, footprint, chimney=None, tile="tile_graphite", corner=False, cap=1.5, open_c=1, low_runs=(), tall_open=False):
    """Руїна: низька купа (гребінь ≤1.5 м, 5-7 опуклостей контуру, заокруглена губа) із деталлю зі сканованих і плитових
    уламків 20-50 см, уламки стін з проломами ≥1.2 м і зазубреними верхами, стирчать не вище 1.9 м (один кут до поверху
    за потреби), нахилені крокви, плити на купі. Деталь купи запікається зі скан-джерела разом із AO."""
    lib.reset()
    b = Builder()
    rnd = random.Random(seed)
    x0, x1, y0, y1 = -L / 2, L / 2, -D / 2, D / 2
    # будинок читається: три кутові пеньки 1.8-3 м з плечима 0.9 м, дві довші прямі стіни 1-1.5 м; четвертий кут низький, а два боки біля нього — проломи
    A = 0.9
    cs = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]                                  # SW, SE, NE, NW
    dirs = [((1, 0), (0, 1)), ((-1, 0), (0, 1)), ((-1, 0), (0, -1)), ((1, 0), (0, -1))]
    kw = dict(top_tone=1.0, brick_mat="wall_brick", cap=0.22, step=0.45, diag_p=0.6, jit=0.8, tvar=0.3, foot=0.55, soot_h=0.0)
    for ci, c in enumerate(cs):
        for di, d in enumerate(dirs[ci]):
            low_ = ci == open_c and not tall_open
            if low_:                                                              # чистий низький пенечок поза купою читається сторонньою цеглою: кут лишається відкритим
                continue
            ln = A
            hc = (rnd.uniform(1.2, 1.8) if tall_open and ci == open_c else rnd.uniform(1.8, 3.0)) if not low_ else 0.5
            p1 = (c[0] + d[0] * ln, c[1] + d[1] * ln)
            hs = [hc, hc * 0.8, hc * 0.55] if not low_ else [0.5, 0.4]
            wall_run(b, c, p1, 0.4, hs, "wall_brick", "wall_plaster", seed * 7 + ci * 2 + di, hcap=3.2, **kw)
    breach = tuple(si_ for si_ in ((open_c) % 4, (open_c - 1) % 4) if si_ not in low_runs)   # сторони, що сходяться на відкритому куті, крім тих, де лежить низька стінка
    normals = [(0, -1), (1, 0), (0, 1), (-1, 0)]
    for si in range(4):
        if si in breach:
            continue
        low_side = si in low_runs
        c0, c1 = cs[si], cs[(si + 1) % 4]
        d = ((c1[0] - c0[0]) / math.hypot(c1[0] - c0[0], c1[1] - c0[1]), (c1[1] - c0[1]) / math.hypot(c1[0] - c0[0], c1[1] - c0[1]))
        q0 = (c0[0] + d[0] * (A + 0.3), c0[1] + d[1] * (A + 0.3))
        q1 = (c1[0] - d[0] * (A + 0.3), c1[1] - d[1] * (A + 0.3))
        hh = rnd.uniform(0.4, 0.8) if low_side else rnd.uniform(1.0, 1.5)
        wall_run(b, q0, q1, 0.4, [hh, hh * 0.9, hh * 1.1, hh], "wall_brick", "wall_plaster", seed * 11 + si, hcap=1.6, **kw)
    if os.environ.get("RUIN_WALLS_ONLY"):                                        # діагностика: лише стіни, щоб міряти їхній тон у кадрі
        lib.finish(b, name + "_walls", out, tri_limit=4200, footprint=footprint, anchor=(0, 0), ground_clip=True)
        return
    # --- купа ВСЕРЕДИНІ стін 0.6-1.0 м, край зведено нанівець за 0.4 м; назовні — лише зсув 0.8 м через два проломи, теж із м'яким краєм
    plan = [HeapSurface(0.0, 0.0, L / 2 - 0.25, D / 2 - 0.25, 1.0, seed + 1, bumps=rnd.choice((5, 6, 7)), lip=0.1, wob=0.12, hummocks=3, hum_amp=0.6, sq=4.0, noise=1.0, pw=1.5, feather=0.4)]
    plan[0].fit_peak(1.0)
    for si in breach:
        c0, c1 = cs[si], cs[(si + 1) % 4]
        mx, my = (c0[0] + c1[0]) / 2, (c0[1] + c1[1]) / 2
        nx, ny = normals[si]
        plan.append(HeapSurface(mx + nx * 0.3, my + ny * 0.3, 0.55 if nx else 1.0, 1.0 if nx else 0.55, 0.55, seed + 20 + si, bumps=5, lip=0.1, wob=0.08, lump=0.04, sq=2.0, noise=1.0, feather=0.5))
    peak = max(max(h_.z(h_.cx + h_.rx * u / 12.0, h_.cy + h_.ry * v / 12.0) for u in range(-12, 13) for v in range(-12, 13)) for h_ in plan)
    print("HEAPPEAK", name, round(peak, 3))
    assert 0.6 <= peak <= 1.2, f"{name}: гребінь купи {peak:.2f} м"
    bh = lib.rubble_heaps(b, plan, seed + 5, dens=10.0, skirt=0.3, rings=7, segs=36)

    def surf(x, y):                                                              # поверхня купи в точці (найвища з куп)
        return max(h_.z(x, y) for h_ in plan)

    lib.rubble_lumps(b, plan[:1], rnd, 70, tmin=0.03, tmax=0.97, size=(0.18, 0.45), outer=4)   # грудки 20-45 см дають силует і тінь
    lib.rubble_lumps(b, plan[1:], rnd, 12, tmin=0.1, tmax=0.95, size=(0.2, 0.4), outer=5)
    if chimney:                                                                   # димар: розвалився на кілька грудок із відбитими краями, втоплених у купу
        cx, cy = chimney
        for dx, dy, sz in ((0.0, 0.0, 0.62), (0.55, 0.3, 0.55), (-0.35, -0.45, 0.6)):
            b.chunk(cx + dx, cy + dy, surf(cx + dx, cy + dy) + sz * 0.5 - 0.12, sz, "chunk_brick", rnd, tone=(0.9, 1.1))
    for k in range(4):                                                            # підняті шматки: поле кидає тінь
        a = rnd.uniform(0, 2 * math.pi)
        t = rnd.uniform(0.2, 0.7)
        hsf = plan[0]
        r = t * hsf.radius(a)
        px, py = hsf.cx + hsf.rx * r * math.cos(a), hsf.cy + hsf.ry * r * math.sin(a)
        b.chunk(px, py, surf(px, py) + 0.12, rnd.uniform(0.5, 0.7), rnd.choice(("chunk_brick", "chunk_concrete", "chunk_brick")), rnd)
    # 2-3 крокви лежать на купі: початок і кінець на поверхні, напрямок довільний (не віялом від центру)
    for k in range(3):
        a = rnd.uniform(0, 2 * math.pi)
        r0 = rnd.uniform(0.4, 1.4)
        x0_, y0_ = r0 * math.cos(a) * 1.1, r0 * math.sin(a)
        a2 = rnd.uniform(0, 2 * math.pi)
        ln_ = rnd.uniform(1.3, 1.8)
        x1_, y1_ = x0_ + ln_ * math.cos(a2), y0_ + ln_ * math.sin(a2)
        z0_ = surf(x0_, y0_) + 0.02
        z1_ = max(0.1, surf(x1_, y1_) + 0.02)
        th = rnd.uniform(0.18, 0.26)
        b.beam((x0_, y0_, z0_), (x1_, y1_, z1_), th, "timber_dark", th * 1.2)
    lib.finish(b, name, out, tri_limit=5200, footprint=footprint, hi=None if os.environ.get("RUIN_NO_HI") else bh, ground_clip=True, ao=float(os.environ.get("RUIN_AO", "0.1")))


if want("h1"):
    house1(False)
if want("h1hit"):
    house1(True)
if want("h2"):
    house2()
if want("h3"):
    house3()
if want("h4"):
    house4()
if want("ruins"):
    ruin("ruin_h1", 5.8, 4.8, 0.8, 11, (1, 1), chimney=(0.9, -0.2), open_c=1, tile="fc_roof_x", cap=1.5)
    ruin("ruin_h3", 5.4, 5.4, 0.6, 29, (1, 1), open_c=2, tall_open=True, low_runs=(1,), tile="tile_graphite", corner=True, cap=1.6)
