"""F2 корівник, F3 ангар (ціла і пошкоджена), F4 зерносховища, F5 силоси, F6 АЗС.
Усі розміри в метрах із брифу; фронт (вхід) уздовж +Y."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, lump

out = lib.out_dir()
only = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []


def want(n):
    return not only or n in only


# ------------------------------------------------------------------ F2 корівник 60 x 12
def barn():
    lib.reset()
    b = Builder()
    W, Ln, EAVE, RIDGE = 12.0, 60.0, 3.5, 6.0
    b.box(0, 0, 0, W, Ln, EAVE, "wall_silicate")
    b.gable(-W / 2, W / 2, -Ln / 2, Ln / 2, EAVE, RIDGE, "fc_roof", "wall_silicate", ridge_axis="y", overhang=0.5)
    b.box(0, 0, RIDGE, 0.35, Ln + 1.0, 0.18, "metal_dark")             # коник
    for k in range(9):                                                   # ряд аераційних надбудов
        y = -Ln / 2 + 4.0 + k * 6.5
        b.box(0, y, RIDGE - 0.05, 1.3, 2.0, 0.85, "metal_dark", top="clad_roof")
    for sgn in (1, -1):                                                  # стрічка вікон під карнизом
        for k in range(10):
            y = -Ln / 2 + 3.0 + k * 5.5
            b.window(("x", sgn * (W / 2), sgn), y, 2.1, 2.2, 0.8, 0.05)
    # ворота на торці (фронт +Y) й бокові двері
    b.box(0, Ln / 2 + 0.05, 0, 4.0, 0.1, 3.0, "door_steel")
    b.box(0, -Ln / 2 - 0.05, 0, 3.0, 0.1, 2.8, "door_steel")
    for y in (-18.0, 8.0):
        b.box(W / 2 + 0.05, y, 0, 0.1, 1.6, 2.2, "door_steel")
    # кормова доріжка: бетонна смуга уздовж довгого боку
    b.box(W / 2 + 1.0, 0, 0, 2.0, Ln - 2.0, 0.06, "apron")
    lib.finish(b, "f2_livestock_barn", out, tri_limit=900, footprint=(2, 8), anchor=(0, 0))


# ------------------------------------------------------------------ F3 ангар 18 x 36
def hangar(damaged):
    lib.reset()
    b = Builder()
    W, Ln, EAVE, RIDGE = 18.0, 36.0, 6.0, 9.0
    x0, x1, y0, y1 = -W / 2, W / 2, -Ln / 2, Ln / 2
    OV = 0.45
    # цоколь, пілястри кожні 6 м, ринви й водостоки: силует і тіні, що читаються зверху
    b.box(0, 0, 0, W + 0.2, Ln + 0.2, 0.6, "silo_concrete")
    seg = Ln / 6
    if not damaged:
        b.box(0, 0, 0.6, W, Ln, EAVE - 0.6, "clad_wall")
        b.gable(x0, x1, y0, y1, EAVE, RIDGE, "clad_roof", "clad_wall", ridge_axis="y", overhang=OV)
        b.box(0, 0, RIDGE, 0.6, Ln + 0.9, 0.3, "metal_dark")                   # коник
        for k in range(1, 6):                                                    # світлові смуги на скатах
            y = y0 + k * seg - 3.0
            for sx in (-1, 1):
                b.poly_up([(sx * 3.0, y - 1.6, 8.08), (sx * 6.5, y - 1.6, 6.91), (sx * 6.5, y + 1.6, 6.91), (sx * 3.0, y + 1.6, 8.08)], "glass_roof")
    else:
        b.box(x0 + 0.1, 0, 0.6, 0.2, Ln, EAVE - 0.6, "clad_wall")
        # східна стіна з проломом: клаптик нерівний, обгорілий по краях
        b.box(x1 - 0.1, -13.0, 0.6, 0.2, 10.0, EAVE - 0.6, "clad_wall")
        b.box(x1 - 0.1, 14.5, 0.6, 0.2, 7.0, EAVE - 0.6, "clad_wall")
        b.box(x1 - 0.1, 3.5, 0.6, 0.2, 4.0, 1.9, "clad_burnt")
        b.box(x1 - 0.1, -6.0, 0.6, 0.2, 2.2, 4.2, "clad_burnt")
        b.box(x1 - 0.1, 10.3, 0.6, 0.2, 1.8, 3.1, "clad_burnt")
        b.box(0, y0 + 0.1, 0.6, W, 0.2, EAVE - 0.6, "clad_wall")
        b.box(0, y1 - 0.1, 0.6, W, 0.2, EAVE - 0.6, "clad_wall")
        b.box(0, 0, 0.62, W - 0.4, Ln - 0.4, 0.04, "floor_dark")                     # темна підлога з брудом
        # покрівля з нерівним проломом; клаптики біля коника й карниза обгорілі
        def sl(side, pts, mat):
            q = []
            for t, y in pts:
                q.append((side * (9.0 * (1 - t)), y, EAVE + 3.0 * t) if True else None)
            b.poly_up(q, mat)
        for k in range(6):
            ya, yb = y0 + k * seg, y0 + (k + 1) * seg
            if k not in (2, 3):
                sl(1, [(0, ya), (0, yb), (1, yb), (1, ya)], "clad_roof")
            if k != 2:
                sl(-1, [(0, ya), (0, yb), (1, yb), (1, ya)], "clad_roof")
        # залишки східного скату в проломі
        sl(1, [(0.72, -6.0), (1, -6.0), (1, -1.0), (0.86, -3.4)], "clad_burnt")
        sl(1, [(1, 1.2), (1, 6.0), (0.55, 6.0), (0.78, 3.2)], "clad_burnt")
        sl(1, [(0, -6.0), (0.27, -6.0), (0.17, -3.0), (0, -1.8)], "clad_burnt")
        sl(1, [(0, 2.2), (0.33, 3.6), (0.2, 6.0), (0, 6.0)], "clad_burnt")
        # західний скат: зубчастий розрив на одну секцію
        sl(-1, [(0.0, -6.0), (0.3, -6.0), (0.12, -2.2), (0, -3.0)], "clad_burnt")
        sl(-1, [(1, -6.0), (0.62, -6.0), (0.8, -4.0), (1, -3.2)], "clad_burnt")
        for gy in (y0, y1):
            b.poly([(x0, gy, EAVE), (x1, gy, EAVE), (0, gy, RIDGE)] if gy > 0 else [(x1, gy, EAVE), (x0, gy, EAVE), (0, gy, RIDGE)], "clad_wall")
        for k in range(7):                                                       # портальні рами
            y = y0 + k * seg
            for xs in (x0 + 0.3, x1 - 0.3):
                b.box(xs, y, 0.6, 0.3, 0.45, EAVE - 0.6, "metal_dark")
            b.beam((x0 + 0.3, y, EAVE), (0, y, RIDGE), 0.4, "metal_dark", 0.25)
            b.beam((x1 - 0.3, y, EAVE), (0, y, RIDGE), 0.4, "metal_dark", 0.25)
        import random
        rnd = random.Random(7)
        for k in range(11):                                                      # зігнуті листи навколо
            ang = rnd.uniform(0, math.pi)
            side = 1 if k % 3 else -1
            b.box(side * rnd.uniform(9.9, 10.8), rnd.uniform(-16, 16), 0.1, 1.1, rnd.uniform(1.6, 2.4), 0.05, "clad_burnt" if k % 4 == 0 else ("clad_roof" if k % 2 else "fc_roof"), rot=ang, tilt=rnd.uniform(-0.25, 0.25))
        b.box(11.0, 3.0, 2.6, 1.1, 3.6, 0.05, "clad_roof", tilt=math.radians(35))
        lump(b, 10.5, 5.5, 2.0, 1.0, "rubble", 11, 6)
    for sx in (x0 - 0.05, x1 + 0.05):                                            # ринви й стояки
        b.box(sx - (0.15 if sx < 0 else -0.15), 0, EAVE - 0.3, 0.3, Ln, 0.3, "metal_dark")
    for k in range(7):
        y = y0 + k * seg
        for sx in (x0, x1):
            b.box(sx + (-0.12 if sx < 0 else 0.12), min(max(y, y0 + 0.2), y1 - 0.2), 0.6, 0.25, 0.35, EAVE - 0.7, "clad_wall")
    # ролетні ворота 5 x 5 з обрамленням на обох торцях; бокові двері
    for gy, sg in ((y1, 1), (y0, -1)):
        for gx in (-4.6, 4.6):
            b.box(gx, gy + 0.08 * sg, 0.6, 5.2, 0.16, 5.4, "metal_dark")
            b.box(gx, gy + 0.14 * sg, 0.6, 5.0, 0.12, 5.0, "door_steel")
            b.box(gx, gy + 0.2 * sg, 5.2, 5.0, 0.12, 0.35, "metal_dark")
    b.box(x1 + 0.1, -8.0, 0.6, 0.2, 1.1, 2.1, "door_steel")
    lib.finish(b, "f3_hangar_damaged" if damaged else "f3_hangar", out, tri_limit=1400 if damaged else 1000, footprint=(3, 5), anchor=(0, 0))


# ------------------------------------------------------------------ F4 зерносховища
def bins():
    lib.reset()
    b = Builder()
    R, WALL, CONE = 3.5, 10.0, 2.0
    xs = (-12.0, -4.0, 4.0, 12.0)
    for x in xs:
        b.cyl(x, 0, 0, R + 0.3, 0.3, 20, "silo_concrete", cap=True)
        b.cyl(x, 0, 0.3, R, WALL - 0.3, 20, "galv", cap=False)
        b.cyl(x, 0, WALL, R + 0.25, CONE, 20, "galv", r_top=0.35, cap_mat="metal_dark")
        b.box(x, R + 0.1, 0.3, 0.5, 0.15, WALL - 0.3, "metal_dark")      # драбина
        b.box(x, R + 0.02, 0, 1.0, 0.1, 1.9, "door_steel")               # люк
    # елеваторна нория 20 м з головою і спуском до перекриття над бункерами
    lx, ly = 0.0, -6.5
    b.box(lx, ly, 0, 0.8, 0.8, 20.0, "galv", top="metal_dark")
    b.box(lx, ly, 20.0, 2.4, 1.8, 1.8, "galv", top="metal_dark")
    b.box(lx, ly + 1.4, 20.4, 0.5, 1.0, 0.5, "metal_dark")
    b.box(lx, ly, 0, 1.6, 1.6, 0.5, "silo_concrete")
    b.box(lx, ly + 3.5, 0, 0.9, 5.0, 0.7, "metal_dark")                 # приймальний бункер
    # поміст над вершинами по осі бункерів і зʼєднання з норією
    b.box(0, 0, WALL + CONE + 0.3, 32.0, 0.9, 0.12, "metal_dark")
    b.box(0, 0.42, WALL + CONE + 0.3, 32.0, 0.06, 0.9, "metal_dark")
    b.beam((lx, ly + 0.8, 19.8), (0.0, 0.0, WALL + CONE + 0.4), 0.45, "metal_dark", 0.6)
    for x in xs:
        b.box(x, 0, WALL + CONE - 0.2, 0.3, 0.3, 0.5, "metal_dark")
    lib.finish(b, "f4_grain_bins", out, tri_limit=900, footprint=(4, 2))


# ------------------------------------------------------------------ F5 силоси
def silos():
    lib.reset()
    b = Builder()
    R, H = 3.0, 25.0
    xs = [-15.0 + 6.0 * i for i in range(6)]
    for x in xs:
        b.cyl(x, 0, 0, R, H, 20, "silo_concrete", cap=True, cap_mat="silo_concrete")
        b.box(x, R, 0.0, 0.5, 0.15, H, "metal_dark")                    # драбина із захисною кліткою
    # верхня галерея транспортерів і надбудова норії
    b.box(0, 0, H, 35.0, 2.6, 2.4, "silo_concrete", top="bitumen")
    b.box(-15.0, 0, H, 5.0, 5.0, 4.5, "silo_concrete", top="bitumen")
    # нижній приймальний корпус із похилим транспортером
    b.box(-12.0, -6.5, 0, 12.0, 7.0, 7.0, "silo_concrete", top="bitumen")
    lib.finish(b, "f5_silo_battery", out, tri_limit=900, footprint=(5, 2))


# ------------------------------------------------------------------ F6 АЗС
def fuel():
    lib.reset()
    b = Builder()
    b.box(1.0, 0, 0, 29.0, 10.6, 0.08, "apron", top="apron")
    cx = -4.0
    for sx in (-5.5, 5.5):                                               # колони навісу
        for sy in (-2.6, 2.6):
            b.box(cx + sx, sy, 0, 0.5, 0.5, 4.2, "kiosk")
    b.box(cx, 0, 4.1, 15.0, 9.0, 0.9, "kiosk", top="canopy")            # фасція ~0.9 м
    b.box(cx, 0, 4.45, 15.06, 9.06, 0.22, "metal_dark")                 # темна смуга по фасції (без бренду)
    for ix in (-3.5, 3.5):
        b.box(cx + ix, 0, 0.08, 1.1, 5.0, 0.2, "apron", top="apron")
        for py in (-1.3, 1.3):
            b.box(cx + ix, py, 0.28, 0.6, 0.5, 1.5, "frame", top="dark")
    # магазин-кіоск 8 x 5 x 3: суцільне скління по фасаду, двері, виступ даху
    b.box(10.0, 0, 0.08, 8.0, 5.0, 3.0, "kiosk", top="bitumen")
    b.window(("y", 2.5, 1), 8.2, 0.9, 4.2, 1.5)
    b.window(("y", 2.5, 1), 12.3, 0.9, 1.3, 1.5)
    b.window(("y", -2.5, -1), 9.0, 1.1, 1.4, 1.3)
    b.window(("y", -2.5, -1), 11.5, 1.1, 1.4, 1.3)
    b.box(10.3, 2.5 + 0.03, 0.08, 1.0, 0.05, 2.1, "dark")
    b.box(10.0, 0, 3.08, 8.5, 5.5, 0.3, "kiosk", top="bitumen")
    b.box(10.0, 2.9, 2.55, 8.0, 0.8, 0.12, "metal_dark")                # козирок над вітриною
    lib.finish(b, "f6_fuel_station", out, tri_limit=500, footprint=(4, 2))


if want("barn"):
    barn()
if want("hangar"):
    hangar(False)
    hangar(True)
if want("bins"):
    bins()
if want("silos"):
    silos()
if want("fuel"):
    fuel()
