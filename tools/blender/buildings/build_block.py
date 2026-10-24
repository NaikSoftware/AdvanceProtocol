"""H5: панельна триповерхівка 30 x 12 м і її пошкоджений варіант (влучання в східний торець)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder, lump

out = lib.out_dir()
LEN, DEP, FLOOR, NF = 30.0, 12.0, 3.1, 3
H = FLOOR * NF           # 9.3 м до плити даху
X0, X1, Y0, Y1 = -LEN / 2, LEN / 2, -DEP / 2, DEP / 2
STAIRS = (1, 5, 8)       # осі сходових кліток (кроки по 3 м)


def bay_x(i):
    return X0 + 1.5 + 3.0 * i


def windows(b, bays, floors, blown=()):
    for side, (y, sgn) in (("front", (Y1, 1)), ("back", (Y0, -1))):
        for i in bays:
            for f in floors:
                z = f * FLOOR + 0.95
                if i in STAIRS and f == 0 and side == "front":
                    continue
                if i in STAIRS:
                    if f == 0:
                        continue
                    # сходова клітка: вузьке високе вікно на проміжку між поверхами
                    b.window(("y", y, sgn), bay_x(i), f * FLOOR - 0.6, 0.9, 1.3, 0.07)
                    continue
                if (side, i, f) in blown:
                    # вибите вікно: чорний проріз і кіптява над ним
                    x = bay_x(i)
                    b.poly([(x - 0.7, y + 0.03 * sgn, z), (x + 0.7, y + 0.03 * sgn, z), (x + 0.7, y + 0.03 * sgn, z + 1.4), (x - 0.7, y + 0.03 * sgn, z + 1.4)][::sgn], "dark")
                    b.poly([(x - 0.9, y + 0.02 * sgn, z + 1.4), (x + 0.9, y + 0.02 * sgn, z + 1.4), (x + 0.5, y + 0.02 * sgn, z + 2.5), (x - 0.5, y + 0.02 * sgn, z + 2.3)][::sgn], "panel_scorched")
                    continue
                b.window(("y", y, sgn), bay_x(i), z, 1.4, 1.4)


def balconies(b, bays):
    for i in bays:
        if i in STAIRS:
            continue
        for f in (1, 2):
            x = bay_x(i)
            b.box(x, Y1 + 0.6, f * FLOOR - 0.05, 2.2, 1.2, 0.15, "panel", top="panel")
            b.box(x, Y1 + 1.15, f * FLOOR + 0.1, 2.2, 0.08, 0.9, "metal_dark")
            b.box(x - 1.06, Y1 + 0.6, f * FLOOR + 0.1, 0.08, 1.1, 0.9, "metal_dark")
            b.box(x + 1.06, Y1 + 0.6, f * FLOOR + 0.1, 0.08, 1.1, 0.9, "metal_dark")


def common(b, east_damage):
    mid = "panel"
    if not east_damage:
        b.box(0, 0, 0, LEN, DEP, H, mid, top="bitumen")
        # парапет по периметру даху
        for (cx, cy, sx, sy) in ((0, Y1 - 0.1, LEN, 0.2), (0, Y0 + 0.1, LEN, 0.2), (X0 + 0.1, 0, 0.2, DEP - 0.4), (X1 - 0.1, 0, 0.2, DEP - 0.4)):
            b.box(cx, cy, H, sx, sy, 0.5, mid)
        windows(b, range(10), range(NF))
        balconies(b, (0, 2, 3, 4, 6, 7, 9))
        for gx in (X0, X1):  # торці глухі, у кожному одне вікно сходового майданчика
            pass
    else:
        # західна частина 0..x=6 ціла, східна — перші два поверхи ціле, третій розбито
        xc = 6.0
        b.box((X0 + xc) / 2, 0, 0, xc - X0, DEP, H, mid, top="bitumen")
        for (cx, cy, sx, sy) in ((0 + (X0 + xc) / 2, Y1 - 0.1, xc - X0, 0.2), ((X0 + xc) / 2, Y0 + 0.1, xc - X0, 0.2), (X0 + 0.1, 0, 0.2, DEP - 0.4)):
            b.box(cx, cy, H, sx, sy, 0.5, mid)
        b.box((xc + X1) / 2, 0, 0, X1 - xc, DEP, 2 * FLOOR, mid, top="panel_scorched")
        windows(b, range(0, 7), range(NF))
        windows(b, range(7, 10), range(2), blown={("front", 7, 1), ("front", 9, 1), ("back", 8, 1), ("back", 7, 1), ("front", 8, 1)})
        balconies(b, (0, 2, 3, 4))
    # входи й козирки сходових кліток на фронтоні
    for i in STAIRS:
        b.box(bay_x(i), Y1 + 0.02, 0, 1.3, 0.04, 2.1, "dark")
        b.box(bay_x(i), Y1 + 0.6, 2.4, 2.4, 1.2, 0.15, "bitumen", top="bitumen")
    # надбудови сходових кліток, вентстояки й антена на даху
    for i in STAIRS:
        if east_damage and bay_x(i) > 6:
            continue
        b.box(bay_x(i), Y0 + 2.6, H, 2.6, 2.6, 2.4, mid, top="bitumen")
    for k, x in enumerate((-12, -7, -2, 3, 11.5, 13.5)):
        if east_damage and x > 6:
            continue
        b.cyl(x, 1.2 * (-1) ** k, H, 0.22, 1.6, 8, "metal_dark")
    return mid


def intact():
    lib.reset()
    b = Builder()
    common(b, False)
    lib.finish(b, "h5_panel_block", out, tri_limit=1500, footprint=(4, 2), anchor=(0, 0))


def damaged():
    lib.reset()
    b = Builder()
    common(b, True)
    xc = 6.0
    z2 = 2 * FLOOR
    # плита перекриття 2-го поверху, частково зірвана
    b.box((xc + X1) / 2, 0, z2 - 0.05, X1 - xc, DEP, 0.2, "panel_scorched", top="panel_scorched")
    # обрубки стін третього поверху: задня стіна драна, торець — щербатий
    b.box(9.0, Y0 + 0.2, z2, 5.0, 0.4, 2.2, "panel_scorched")
    b.box(13.4, Y0 + 0.2, z2, 3.0, 0.4, 3.1, "panel_scorched")
    b.box(X1 - 0.2, -3.0, z2, 0.4, 5.0, 1.4, "panel_scorched")
    b.box(X1 - 0.2, 4.3, z2, 0.4, 3.4, 2.7, "panel_scorched")
    b.box(7.2, Y1 - 0.2, z2, 2.6, 0.4, 1.7, "panel_scorched")
    # зубчастий край: додаткові обломи на зламі стін і краю плити
    for (x, y, sx, sy, h) in ((6.4, Y1 - 0.2, 0.9, 0.4, 2.6), (8.4, Y1 - 0.2, 0.6, 0.4, 0.8), (10.5, Y0 + 0.2, 0.8, 0.4, 2.9), (12.0, Y0 + 0.2, 0.5, 0.4, 1.0), (X1 - 0.2, 0.8, 0.4, 0.7, 2.2), (X1 - 0.2, 7.0, 0.4, 0.9, 1.0)):
        b.box(x, y, z2, sx, sy, h, "panel_scorched")
    # арматура, що стирчить із краю плити
    for k in range(7):
        yy = -5.0 + 1.6 * k
        b.beam((X1 - 0.5, yy, z2 - 0.1), (X1 + 0.5, yy + 0.1, z2 + 0.45), 0.09, "rust")
    for k in range(4):
        b.beam((6.5 + 1.8 * k, Y1 - 0.2, z2 - 0.1), (6.9 + 1.8 * k, Y1 + 0.7, z2 + 0.4), 0.09, "rust")
    # схил завалу від зламу до землі
    b.box(11.0, 6.7, 0.8, 7.0, 3.3, 0.6, "rubble", top="rubble", tilt=math.radians(-32))
    # перегородки кімнат, що лишилися
    b.box(8.0, 0.5, z2, 0.15, 6.0, 1.9, "panel")
    b.box(11.2, -1.8, z2, 0.15, 4.0, 1.3, "panel")
    b.box(10.0, 2.0, z2, 4.0, 0.15, 1.0, "panel")
    # впала плита даху: однією стороною на підлозі, іншою на уламках
    b.box(10.8, 1.0, z2 + 0.6, 7.0, 7.0, 0.22, "bitumen", top="bitumen", tilt=math.radians(-14), rot=math.radians(8))
    # зависла арматура/край плити на розломі
    b.box(7.0, 4.5, z2 + 1.9, 2.0, 1.2, 0.2, "panel_scorched", top="bitumen", tilt=math.radians(18), rot=math.radians(-6))
    # відкинуте сміття зовні: завал на фронті і збоку, смуга за будівлею
    lump(b, 11.0, 7.0, 2.2, 1.6, "rubble", 1, 14)
    lump(b, 15.4, 1.0, 1.6, 1.3, "rubble", 2, 8)
    lump(b, 10.0, -7.0, 1.8, 1.0, "rubble", 3, 6)
    lump(b, 14.0, -6.8, 1.8, 1.0, "rubble", 4, 5)
    lib.finish(b, "h5_panel_block_damaged", out, tri_limit=2500, footprint=(4, 2), anchor=(0, 0))


intact()
damaged()
