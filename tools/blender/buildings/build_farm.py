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
    if not damaged:
        b.box(0, 0, 0, W, Ln, EAVE, "clad_wall")
        b.gable(x0, x1, y0, y1, EAVE, RIDGE, "clad_roof", "clad_wall", ridge_axis="y", overhang=0.3)
        b.box(0, 0, RIDGE, 0.4, Ln + 0.6, 0.15, "metal_dark")
    else:
        # довгі стіни: західна ціла, східна з проломом у середині
        b.box(x0 + 0.1, 0, 0, 0.2, Ln, EAVE, "clad_wall")
        b.box(x1 - 0.1, -12.5, 0, 0.2, 11.0, EAVE, "clad_wall")
        b.box(x1 - 0.1, 14.0, 0, 0.2, 8.0, EAVE, "clad_wall")
        b.box(x1 - 0.1, 5.5, 0, 0.2, 5.0, 2.3, "clad_wall")           # нижній уламок пролому
        b.box(0, y0 + 0.1, 0, W, 0.2, EAVE, "clad_wall")
        b.box(0, y1 - 0.1, 0, W, 0.2, EAVE, "clad_wall")
        # підлога всередині видна крізь розрив даху
        b.box(0, 0, 0, W - 0.4, Ln - 0.4, 0.05, "apron")
        # покрівля: смуги по 6 м, у східній та частково західній відсутні листи
        seg = Ln / 6
        for k in range(6):
            ya, yb = y0 + k * seg, y0 + (k + 1) * seg
            ym = (ya + yb) / 2
            if k not in (2, 3):
                b.poly([(x1 + 0.3, ya, EAVE - 0.05), (x1 + 0.3, yb, EAVE - 0.05), (0, yb, RIDGE), (0, ya, RIDGE)], "clad_roof")
            if k != 2:
                b.poly([(x0 - 0.3, yb, EAVE - 0.05), (x0 - 0.3, ya, EAVE - 0.05), (0, ya, RIDGE), (0, yb, RIDGE)], "clad_roof")
        for gy in (y0, y1):
            xm = 0
            b.poly([(x0, gy, EAVE), (x1, gy, EAVE), (xm, gy, RIDGE)] if gy > 0 else [(x1, gy, EAVE), (x0, gy, EAVE), (xm, gy, RIDGE)], "clad_wall")
        # портальні рами кожні 6 м (колони + ригелі), лише їхній силует
        for k in range(7):
            y = y0 + k * seg
            for xs in (x0 + 0.3, x1 - 0.3):
                b.box(xs, y, 0, 0.3, 0.45, EAVE, "metal_dark")
            b.beam((x0 + 0.3, y, EAVE), (0, y, RIDGE), 0.4, "metal_dark", 0.25)
            b.beam((x1 - 0.3, y, EAVE), (0, y, RIDGE), 0.4, "metal_dark", 0.25)
        for k in range(6):                                              # прогони над розривом
            if k in (2, 3):
                for t in (0.3, 0.6, 0.9):
                    ya = y0 + 2 * seg
                    b.beam((x1 - 0.3 - t * 8.4, ya, EAVE + t * 2.7), (x1 - 0.3 - t * 8.4, y0 + 4 * seg, EAVE + t * 2.7), 0.12, "metal_dark")
                break
        # зігнуті листи, що висять і валяються поруч
        import random
        rnd = random.Random(7)
        for k in range(11):
            ang = rnd.uniform(0, math.pi)
            side = 1 if k % 3 else -1
            b.box(side * rnd.uniform(9.9, 10.8), rnd.uniform(-16, 16), 0.1, 1.1, rnd.uniform(1.6, 2.4), 0.05, "clad_roof" if k % 2 else "fc_roof", rot=ang, tilt=rnd.uniform(-0.25, 0.25))
        b.box(11.0, 3.0, 2.6, 1.1, 3.6, 0.05, "clad_roof", tilt=math.radians(35))
        lump(b, 10.5, 5.5, 2.0, 1.0, "rubble", 11, 6)
    # два ролетні ворота 5 x 5 на фронтоні +Y
    for gx in (-4.6, 4.6):
        b.box(gx, y1 + 0.06, 0, 5.0, 0.12, 5.0, "door_steel")
    lib.finish(b, "f3_hangar_damaged" if damaged else "f3_hangar", out, tri_limit=1400 if damaged else 300, footprint=(3, 5), anchor=(0, 0))


# ------------------------------------------------------------------ F4 зерносховища
def bins():
    lib.reset()
    b = Builder()
    R, WALL, CONE = 3.5, 10.0, 2.0
    xs = (-12.0, -4.0, 4.0, 12.0)
    for x in xs:
        b.cyl(x, 0, 0, R + 0.3, 0.3, 20, "silo_concrete", cap=False)
        b.cyl(x, 0, 0.3, R, WALL - 0.3, 20, "galv", cap=False)
        b.cyl(x, 0, WALL, R + 0.25, CONE, 20, "galv", r_top=0.35, cap_mat="metal_dark")
        b.box(x, R + 0.1, 0.3, 0.5, 0.15, WALL - 0.3, "metal_dark")      # драбина
        b.box(x, R + 0.02, 0, 1.0, 0.1, 1.9, "door_steel")               # люк
    # елеваторна нория 20 м з головою і спуском до перекриття над бункерами
    lx, ly = 0.0, -6.5
    b.box(lx, ly, 0, 1.6, 1.6, 20.0, "galv", top="metal_dark")
    b.box(lx, ly, 20.0, 2.6, 2.2, 1.8, "galv", top="metal_dark")
    b.box(lx, ly, 0, 3.0, 3.0, 0.5, "silo_concrete")
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
    b.beam((-14.0, -4.0, 6.5), (-15.0, -1.5, H + 0.5), 0.6, "metal_dark", 1.0)
    lib.finish(b, "f5_silo_battery", out, tri_limit=900, footprint=(5, 2))


# ------------------------------------------------------------------ F6 АЗС
def fuel():
    lib.reset()
    b = Builder()
    b.box(1.0, 0, 0, 29.0, 10.6, 0.08, "apron", top="apron")
    cx = -4.0
    # навіс 15 x 9 на висоті 5 м
    for sx in (-5.5, 5.5):
        for sy in (-2.6, 2.6):
            b.box(cx + sx, sy, 0, 0.5, 0.5, 4.5, "kiosk")
    b.box(cx, 0, 4.5, 15.0, 9.0, 0.5, "kiosk", top="canopy")
    for ix in (-3.5, 3.5):
        b.box(cx + ix, 0, 0.08, 1.1, 5.0, 0.2, "apron", top="apron")
        for py in (-1.3, 1.3):
            b.box(cx + ix, py, 0.28, 0.6, 0.5, 1.5, "frame", top="dark")
    # магазин-кіоск 8 x 5 x 3 з плоским дахом
    b.box(10.0, 0, 0.08, 8.0, 5.0, 3.0, "kiosk", top="bitumen")
    b.window(("y", 2.5, 1), 8.0, 1.0, 2.2, 1.2, 0.07)
    b.window(("y", 2.5, 1), 11.8, 1.0, 1.4, 1.2, 0.07)
    b.box(10.0, 2.5 + 0.02, 0.08, 1.0, 0.04, 2.1, "dark")
    b.box(10.0, 0, 3.08, 8.4, 5.4, 0.25, "kiosk", top="bitumen")
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
