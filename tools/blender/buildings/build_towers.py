"""F7 сталевий водотрубний бак і F7b цегляна водонапірна вежа."""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder

out = lib.out_dir()

# F7: бак Ø3 x 6 м на колоні Ø1.4 м, разом 18 м
lib.reset()
b = Builder()
b.cyl(0, 0, 0, 0.95, 0.4, 12, "steel_paint")                                   # фундамент
b.cyl(0, 0, 0.4, 0.7, 11.6, 12, "steel_paint", cap=False)                # колона Ø1.4
b.cyl(0, 0, 12.0, 0.9, 0.5, 16, "steel_paint", r_top=1.5, cap=False)     # перехід під бак
b.cyl(0, 0, 12.5, 1.5, 4.8, 16, "steel_paint", cap=False)
b.cyl(0, 0, 17.3, 1.5, 0.7, 16, "steel_paint", r_top=0.3, cap_mat="steel_paint")  # кришка
b.ladder(0, 0.8, 0.4, 11.6, "x")                                       # зовнішня драбина колони
b.ladder(0, 1.58, 12.5, 4.6, "x")                                        # драбина бака
b.box(0, 0.72, 0.4, 0.9, 0.08, 2.0, "dark")                              # люк-двері біля основи
b.box(0, 0, 12.0, 3.4, 0.12, 0.12, "metal_dark")                         # поручень
lib.finish(b, "f7_water_tower", out, tri_limit=700, footprint=(1, 1))

# F7b: цегляна водонапірна вежа, Ø5 м шахта, 22 м разом зі сталевим баком
lib.reset()
b = Builder()


def r_at(z):
    return 2.5 - 0.2 * (z - 0.5) / 15.5


b.cyl(0, 0, 0, 2.7, 0.5, 20, "silo_concrete", cap=True)
b.cyl(0, 0, 0.5, 2.5, 15.0, 20, "brick", r_top=r_at(15.5), cap=False)
for ang, z in ((math.pi / 2, 5.5), (math.pi / 2, 10.5), (0.0, 8.0), (math.pi, 8.0), (-math.pi / 2, 9.0)):
    b.cyl_arch(0, 0, r_at, ang, z, 0.75, 1.7, "dark")            # арковi віконні ніші
b.cyl_arch(0, 0, r_at, math.pi / 2, 0.5, 1.3, 2.6, "dark")       # двері
b.ladder(r_at(8.0) + 0.05, 0, 0.5, 15.0, "y")                    # пожежна драбина
for k, (rr, zz) in enumerate(((2.45, 15.3), (2.6, 15.55), (2.75, 15.8), (2.9, 16.05))):
    b.cyl(0, 0, zz, rr, 0.25, 20, "brick", cap=True)              # ступінчастий карниз під баком
b.cyl(0, 0, 16.3, 3.1, 3.9, 20, "steel_paint", cap=False)        # бак
b.cyl(0, 0, 20.2, 3.2, 1.8, 20, "metal_dark", r_top=0.4, cap=True)  # шатро
lib.finish(b, "f7b_brick_tower", out, tri_limit=900, footprint=(1, 1))
