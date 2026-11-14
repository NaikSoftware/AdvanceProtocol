"""Протитанкова міна: диск-корпус, верхня плита, запал, ручка. Чотири варіанти:
  mine_own        — закопана врівень у розритому ґрунті, над ґрунтом лише верх;
  mine_enemy      — відкопана, лежить на поверхні всім корпусом біля відвалу ґрунту;
  mine_own_road / mine_enemy_road — те саме на асфальті: закопати в нього не можна, тож замість
                    ґрунту биті шматки асфальту, а своя лежить на поверхні нижчим корпусом.
Справжня міна ~0,3 м; на дошці (тайл = 8 м) вона була б менша за піксель, тож модель збільшена
в MINE_FACTOR разів (одна стала, не залежить від зуму; тут і в MineLayer.MINE_FACTOR вона має збігатись). Збільшено лише міну й плями довкола.
Будуємо в метрах, на виході множимо на 1/8 (тайл = 8 м = 1,0).

blender -b --factory-startup -P tools/blender/ordnance/mine.py     (MINE_FACTOR=5 — інше збільшення)
"""
import sys, os, math, random
TAU = 2 * math.pi
sys.path.insert(0, os.path.dirname(__file__))
from lib import *

F = float(os.environ.get("MINE_FACTOR", "5.0"))
OUT_SUFFIX = os.environ.get("MINE_SUFFIX", "")   # для порівняльних збірок різних збільшень

SOIL = (0.23, 0.165, 0.105)
SOIL_LIGHT = (0.33, 0.25, 0.16)
ASPHALT = (0.30, 0.30, 0.31)
ASPHALT_DARK = (0.17, 0.17, 0.18)
BODY = (0.13, 0.15, 0.08)          # темний корпус: контраст із світлою плитою
PLATE = (0.67, 0.65, 0.51)         # ~(170,165,130)
FUSE = (0.32, 0.28, 0.16)
CONTACT = (0.06, 0.055, 0.05)      # темний контактний пояс довкола корпусу


def soil(b, r, seed, lip=False):
    """Розритий ґрунт без чистого кола: край із ~10-сантиметрових виступів, окремі грудки; для
    відкопаної — ще невеликий насип-валик довкола міни."""
    rnd = random.Random(seed)
    b.cone(SOIL, (0, 0, 0), r * 0.82, r * 0.7, 0.05, 12)
    n = 18
    for i in range(n):
        a = TAU * (i + rnd.random() * 0.5) / n
        d = r * (0.78 + rnd.random() * 0.2)
        lr = 0.1 + rnd.random() * 0.1                      # виступ 10–20 см
        b.cone(SOIL if i % 3 else SOIL_LIGHT, (math.cos(a) * d, math.sin(a) * d, 0.0), lr, lr * 0.8, 0.04 + rnd.random() * 0.03, 6, rnd.random())
    for i in range(5):
        a = i * 1.26 + rnd.random() * 0.4
        d = r * (0.45 + rnd.random() * 0.3)
        b.cone(SOIL_LIGHT if i % 2 else SOIL, (math.cos(a) * d, math.sin(a) * d, 0.0), r * (0.25 + rnd.random() * 0.1), r * 0.18, 0.06 + rnd.random() * 0.025, 7, rnd.random())
    for i in range(4):                                     # грудки: дрібні округлі нерівності
        a = rnd.random() * TAU
        d = r * (0.5 + rnd.random() * 0.4)
        b.ball(SOIL_LIGHT if i % 2 else SOIL, (math.cos(a) * d, math.sin(a) * d, 0.06), (0.1 + rnd.random() * 0.06, 0.09 + rnd.random() * 0.05, 0.07), 8, rnd.random())
    if lip:
        R = 0.15 * F * 1.15 + 0.12
        for i in range(14):
            a = TAU * i / 14 + rnd.random() * 0.2
            b.ball(SOIL_LIGHT, (math.cos(a) * R, math.sin(a) * R, 0.07), (0.17, 0.12, 0.07), 8, a)


def asphalt(b, r, seed):
    """Биті шматки асфальту: кутасті плити різної висоти й трьох сірих, між ними темні крихти."""
    rnd = random.Random(seed)
    greys = [ASPHALT_DARK, ASPHALT, (0.38, 0.38, 0.4)]
    b.cone(ASPHALT_DARK, (0, 0, 0), r * 0.85, r * 0.75, 0.03, 9)
    for i in range(14):
        a = i * 0.9 + rnd.random() * 0.5
        d = r * (0.35 + rnd.random() * 0.55)
        w = r * (0.1 + rnd.random() * 0.14)
        b.cone(greys[(i + rnd.randrange(2)) % 3], (math.cos(a) * d, math.sin(a) * d, 0.02 + rnd.random() * 0.03),
               w, w * (0.5 + rnd.random() * 0.4), 0.04 + rnd.random() * 0.05, rnd.choice((4, 5, 6)), rnd.random() * 3)


def device(b, top_z, body_h):
    """Корпус (його верх на top_z), контактний пояс, світла плита, запал, ручка. body_h = 0 — закопана."""
    R = 0.15 * F
    if body_h > 0:
        b.cone(BODY, (0, 0, top_z - body_h), R, R * 0.97, body_h, 20)
    # Темний контактний пояс ~15 % ширший за корпус — відділяє міну від ґрунту й асфальту.
    b.cone(CONTACT, (0, 0, top_z - max(body_h, 0.02 * F)), R * 1.15, R * 1.15, 0.01 * F, 20)
    b.cone(PLATE, (0, 0, top_z), R * 0.86, R * 0.76, 0.014 * F, 20)
    t = top_z + 0.014 * F
    b.cone(FUSE, (0, 0, t), 0.05 * F, 0.04 * F, 0.014 * F, 12)
    # Ручка: планка на двох стійках через плиту.
    b.box(BODY, (0, 0.085 * F, t + 0.012 * F), (0.12 * F, 0.016 * F, 0.016 * F))
    b.box(BODY, (0.055 * F, 0.085 * F, t + 0.004 * F), (0.014 * F, 0.016 * F, 0.012 * F))
    b.box(BODY, (-0.055 * F, 0.085 * F, t + 0.004 * F), (0.014 * F, 0.016 * F, 0.012 * F))


def own(b):
    soil(b, 0.26 * F, 7)                # ~1,5 × контактний пояс
    device(b, 0.06, 0.0)                # врівень: над ґрунтом лише верх


def enemy(b):
    soil(b, 0.26 * F, 11, lip=True)
    device(b, 0.05 + 0.07 * F, 0.07 * F)


def own_road(b):
    asphalt(b, 0.28 * F, 5)
    device(b, 0.05 + 0.04 * F, 0.04 * F)  # на поверхні, нижчий корпус


def enemy_road(b):
    asphalt(b, 0.28 * F, 9)
    device(b, 0.05 + 0.07 * F, 0.07 * F)


for name, fn in (("mine_own", own), ("mine_enemy", enemy), ("mine_own_road", own_road), ("mine_enemy_road", enemy_road)):
    b = B(); fn(b); b.export(name + OUT_SUFFIX, scale=0.125)
