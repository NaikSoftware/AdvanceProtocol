"""F7 сталевий водотрубний бак і F7b цегляна водонапірна вежа."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Builder

out = lib.out_dir()

# F7: бак Ø3 x 6 м на колоні Ø1.4 м, разом 18 м
lib.reset()
b = Builder()
b.cyl(0, 0, 0, 1.0, 0.4, 12, "apron")                 # фундамент
b.cyl(0, 0, 0.4, 0.7, 11.6, 12, "steel_paint", cap=False)
b.cyl(0, 0, 12.0, 0.9, 0.5, 16, "steel_paint", r_top=1.5, cap=False)   # перехід під бак
b.cyl(0, 0, 12.5, 1.5, 4.8, 16, "steel_paint", cap=False)
b.cyl(0, 0, 17.3, 1.5, 0.7, 16, "steel_paint", r_top=0.3, cap_mat="steel_paint")  # кришка
b.box(1.05, 0, 0.4, 0.08, 0.5, 11.6, "metal_dark")      # драбина
b.box(0, 0, 12.5, 3.4, 0.1, 0.1, "metal_dark")          # поручень
lib.finish(b, "f7_water_tower", out, tri_limit=300, footprint=(1, 1))

# F7b: цегляна водонапірна вежа, Ø5 м шахта, 22 м разом зі сталевим баком
lib.reset()
b = Builder()
b.cyl(0, 0, 0, 2.7, 0.5, 20, "silo_concrete", cap=False)
b.cyl(0, 0, 0.5, 2.5, 15.5, 20, "brick", r_top=2.3, cap=False)
for k in range(5):  # вузькі віконні прорізи по висоті
    b.box(0, 2.5 - 0.02 * k, 3.0 + k * 2.8, 0.6, 0.12, 1.3, "dark")
b.box(0, 2.55, 0.5, 1.4, 0.15, 2.4, "dark")                             # двері
b.cyl(0, 0, 16.0, 2.9, 0.6, 20, "silo_concrete", cap=True)             # карниз
b.cyl(0, 0, 16.6, 3.1, 3.6, 20, "steel_paint", cap=False)               # бак
b.cyl(0, 0, 20.2, 3.2, 1.8, 20, "metal_dark", r_top=0.4, cap=True)      # шатро
lib.finish(b, "f7b_brick_tower", out, tri_limit=400, footprint=(1, 1))
