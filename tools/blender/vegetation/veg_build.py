"""Збирає GLB бібліотеки рослинності групи на сезон: вузол на рослину плюс її повалений варіант.

Запуск:
  blender -b --factory-startup -P veg_build.py -- <тека_атласу> <група> <сезон> <вихід.glb>
Вузол = окремий меш (один MultiMesh на варіант), дві поверхні: 0 — рослина (veg.gdshader;
над юнітом veg_fade_depth.gdshader з next_pass veg_fade.gdshader), 1 — м'яка пляма затінення
(veg_shade.gdshader). Атлас — <група>_veg_<сезон>.png поруч із GLB, albedo_tex обох шейдерів.
Масштаб гри: 1 тайл = 8 м = 1,0; земля на y = 0; початок координат — основа рослини.
Будова однакова в усіх сезонах (те саме зерно), змінюється лише атлас і частка пучків
голої крони, тож рослина на Річці й на Перехресті — та сама рослина.

<вузол>_fallen — повалений технікою: сніп і кущ — зім'ятий пучок 0,3–0,6 м, нахилений у бік
руху; дерево — купа зламаного гілля 0,3–0,8 м з обрубками стовбура й листям пори року.
"""
import json
import math
import os
import random
import shutil
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ATLAS_DIR, GROUP, SEASON, OUT = argv[:4]
TILE_M = 8.0
# Тон кори стовбура й гілок: стовбур стоїть у тіні крони, а розсіяне світло неба падає на нього
# повне — без цього стовбури світилися світліше за ґрунт (у лісі — bark_dark шейдера).
BARK_TONE = 0.45
# Тон хмизу й стебел зім'ятого куща: вони лежать на відкритому, не в тіні крони; з тоном стовбура
# купа виходила майже чорною на ґрунті.
HEAP_TONE = 0.75
FIXED = (1e-4, 0.0)  # UV2 (до перевертання, див. uv2()) нерухомої картки: листя для шейдера, але не розгортається до камери

# Розміри в метрах. sheaf: сніп очерету / рогозу; crown: кущ; tree: дерево зі скелетом гілок.
#   sheaf: rx, ry — півосі плями; h — висота снопа (від, до); cards — кількість карток.
#   crown: top — верх, base — низ крони, rx/ry — півосі, stems — стебел від землі, card — розмір
#   пучка (від, до), bare — частка пучків пізньої пори, vase/cone/row — форма.
#   tree: h — висота, cb — низ крони, w — ширина крони, r — радіус стовбура, fork — висота
#   розвилки (звідки скелетні гілки), limbs, rise — кут гілки від вертикалі (°), crook —
#   кривизна, leader — частка крони, куди доходить провідник, sec/ter — дочірніх гілок на
#   гілку, lobe_r — радіус клубу листя на кінці гілки, multi — стовбурів від землі,
#   pollard — верба «головою»: пучок прямих пагонів з голови.
TREE = {
    "apple": dict(h=4.5, cb=1.2, w=4.4, r=0.13, fork=1.0, limbs=4, rise=52, crook=0.22, leader=0.25, sec=2, ter=1,
                  lobe_r=0.85, cards=150, card=(1.0, 1.5), bare=0.15),
    "cherry": dict(h=5.6, cb=1.4, w=3.6, r=0.11, fork=1.1, limbs=4, rise=36, crook=0.15, leader=0.6, sec=2, ter=1,
                   lobe_r=0.75, cards=140, card=(0.9, 1.4), bare=0.15),
    "walnut": dict(h=11.0, cb=2.2, w=8.5, r=0.28, fork=1.7, limbs=4, rise=40, crook=0.2, leader=0.0, sec=2, ter=1,
                   lobe_r=1.8, cards=200, card=(1.5, 2.3), bare=0.15),
    "pear": dict(h=10.5, cb=2.0, w=5.0, r=0.24, fork=2.0, limbs=6, rise=22, crook=0.22, leader=0.85, sec=2, ter=1,
                 lobe_r=1.05, cards=200, card=(1.3, 1.9), bare=0.15),
    "oak": dict(h=12.5, cb=2.6, w=6.0, r=0.45, fork=2.6, limbs=6, rise=62, crook=0.42, leader=0.3, sec=2, ter=1,
                lobe_r=1.8, cards=200, card=(1.8, 2.7), bare=0.30, droop=0.06),
    "wwillow": dict(h=9.0, cb=2.0, w=5.5, r=0.40, fork=1.8, limbs=6, rise=42, crook=0.2, leader=0.2, sec=2, ter=1,
                    lobe_r=1.4, cards=200, card=(1.6, 2.3), bare=0.30),
}


def tree_variants(prefix, kind, n=3, extra=None):
    """n форм одного виду: зерно гілля, нахил стовбура до 8° і асиметрія крони різні, розміри ±12 %."""
    out = []
    for i in range(n):
        it = dict(TREE[kind], node="%s_%02d" % (prefix, i + 1), kind=kind, type="tree")
        rng = random.Random(it["node"] + "form")
        k = rng.uniform(0.88, 1.12)
        it.update(h=it["h"] * k, w=it["w"] * rng.uniform(0.88, 1.12), lean_deg=rng.uniform(1.5, 8.0),
                  asym=rng.uniform(0.1, 0.35))
        if extra and i < len(extra):
            it.update(extra[i])
        out.append(it)
    return out


ASSETS = {
    "bank": [
        dict(node="bank_reed_01", kind="reed", type="sheaf", rx=0.7, ry=0.6, h=(1.5, 2.8), cards=18),
        dict(node="bank_reed_02", kind="reed", type="sheaf", rx=1.1, ry=0.9, h=(1.7, 3.0), cards=30),
        dict(node="bank_reed_03", kind="reed", type="sheaf", rx=1.6, ry=0.6, h=(1.5, 2.9), cards=36),
        dict(node="bank_cattail_01", kind="cattail", type="sheaf", rx=0.5, ry=0.45, h=(1.2, 1.8), cards=10),
        dict(node="bank_cattail_02", kind="cattail", type="sheaf", rx=0.9, ry=0.6, h=(1.3, 2.0), cards=16),
        dict(node="bank_bush_willow_01", kind="willow", type="crown", top=3.0, base=0.5, rx=1.5, ry=1.4, stems=7,
             card=(1.0, 1.5), cards=70, vase=0.5, bare=0.15),
        dict(node="bank_bush_willow_02", kind="willow", type="crown", top=2.2, base=0.3, rx=1.8, ry=1.4, stems=6,
             card=(0.9, 1.4), cards=70, vase=0.3, bare=0.15),
        dict(node="bank_bush_willow_03", kind="willow", type="crown", top=3.6, base=0.6, rx=1.3, ry=1.1, stems=9,
             card=(0.9, 1.4), cards=75, vase=0.65, bare=0.15, lean=(0.4, 0.1)),
        dict(node="bank_bush_alder_01", kind="alder", type="crown", top=3.8, base=0.7, rx=1.6, ry=1.5, stems=5,
             card=(1.0, 1.6), cards=80, bare=0.40),
        dict(node="bank_bush_alder_02", kind="alder", type="crown", top=3.2, base=0.5, rx=1.9, ry=1.4, stems=4,
             card=(1.0, 1.6), cards=80, bare=0.40, lean=(-0.3, 0.2)),
        dict(node="bank_bush_alder_03", kind="alder", type="crown", top=4.0, base=1.0, rx=1.3, ry=1.3, stems=3,
             card=(1.0, 1.5), cards=75, vase=0.3, bare=0.40),
    ],
    "yard": tree_variants("yard_apple", "apple") + tree_variants("yard_cherry", "cherry")
    + tree_variants("yard_walnut", "walnut") + [
        dict(node="yard_lilac_01", kind="lilac", type="crown", top=2.8, base=0.6, rx=1.3, ry=1.2, stems=8,
             card=(0.9, 1.3), cards=70, vase=0.25, bare=0.40),
        dict(node="yard_elder_01", kind="elder", type="crown", top=3.0, base=0.8, rx=1.6, ry=1.5, stems=6,
             card=(1.0, 1.4), cards=70, vase=0.5, bare=0.15),
        dict(node="yard_berry_row_01", kind="berry", type="crown", top=1.1, base=0.15, rx=2.0, ry=0.4, stems=8,
             card=(0.55, 0.8), cards=36, row=True, bare=0.30),
        dict(node="yard_thuja_01", kind="thuja", type="crown", top=4.0, base=0.2, rx=0.7, ry=0.7, stems=1,
             card=(0.8, 1.1), cards=70, cone=True, bare=1.00),
    ],
    "meadow": [
        # Глід і шипшина: колючий каркас із гілок (frame — дочірніх гілок на стебло), пізньої пори
        # половина пучків (голі гілочки з гронами ягід).
        dict(node="meadow_hawthorn_01", kind="hawthorn", type="crown", top=2.9, base=0.4, rx=1.5, ry=1.4, stems=5,
             card=(1.0, 1.4), cards=80, bare=0.15, frame=2),
        dict(node="meadow_hawthorn_02", kind="hawthorn", type="crown", top=2.0, base=0.3, rx=1.3, ry=1.1, stems=4,
             card=(0.9, 1.3), cards=60, bare=0.15, frame=2),
        dict(node="meadow_dogrose_01", kind="dogrose", type="crown", top=1.7, base=0.15, rx=1.3, ry=1.1, stems=7,
             card=(0.8, 1.2), cards=50, vase=0.6, bare=0.15, frame=2),
    ] + tree_variants("meadow_pear", "pear") + tree_variants("meadow_oak", "oak")
    + tree_variants("meadow_willow", "wwillow", extra=[
        # Верба «головою»: товстий стовбур до 2,4 м і пучок прямих пагонів.
        dict(pollard=True, h=6.5, cb=2.4, w=5.0, fork=2.4, r=0.42, limbs=16, rise=12, crook=0.04, leader=0.0,
             sec=1, ter=0, lobe_r=0.9),
        # Кілька стовбурів від землі.
        dict(multi=3, fork=0.3, rise=24, limbs=3, leader=0.0, r=0.28),
    ]),
}
# Пізня пора: у спрайтах цих видів листя ≤ 15 %, лишається темний каркас гілочок.
LATE_BARE = {"willow", "alder", "apple", "cherry", "walnut", "lilac", "elder", "berry", "hawthorn", "dogrose", "pear", "oak", "wwillow"}
# Межі трикутників (мобільний бюджет): дерево, кущ біля хати, кущ на березі й на луці, сніп.
BUDGET = {"tree": 800, "yard": 400, "crown": 600, "sheaf": 300}


def uv2(u, v):
    """Експортер glTF перевертає V кожної UV-карти (v → 1 − v), тож UV2 пишеться вже
    перевернутим: у Godot шейдер мусить отримати саме зсув кута (u, v), 0 — для кори."""
    return (u, 1.0 - v)


def to_atlas(rect, u, v):
    x, y, w, h = rect
    return (x + u * w, 1.0 - (y + (1.0 - v) * h))


class Mesh:
    """Колір вершини:
    R — тон: у пучка — місце в кроні (нижня третина темніша); у кори — її яскравість (0,45 скрізь:
        стовбур, гілки, хмиз куп, стебла кущів — світла деревина на ігровому зумі читалась сміттям);
    G — ідентифікатор пучка, однаковий для всіх вершин картки чи гілки: шейдер гасить пучок
        цілим. Нижня половина [0; 0,5) — дерева: над юнітом їх тримає
        нижня межа прозорості fade_floor (гола крона пізньої пори юніта не ховає); верхня половина —
        усе інше (кущі, очерет, туя) прозоріє до звичайного рівня;
    B — 0, крім плями затінення: там висота крони (у двох тайлах), від неї довжина запеченої тіні.
    Плями затінення (shade) — окрема поверхня з іншим матеріалом (veg_shade.gdshader)."""

    def __init__(self, seed, floor=False):
        self.ids = random.Random(seed + "ids")
        self.floor = floor
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("UV2")
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.n = {}

    def new_id(self):
        # Запас від межі 0,5: експортер пише колір 16-бітним, і 0,5 + ε округлювалось би на інший бік.
        return (0.02 if self.floor else 0.52) + 0.46 * self.ids.random()

    def quad(self, co, rect, uv2s, shades, normal, pid=None, shade_surface=False):
        pid = self.new_id() if pid is None else pid
        vs = [self.bm.verts.new(p) for p in co]
        f = self.bm.faces.new(vs)
        f.material_index = 1 if shade_surface else 0
        for loop, (u, v), u2, s in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1)), uv2s, shades):
            loop[self.uv].uv = to_atlas(rect, u, v)
            loop[self.uv2].uv = uv2(*u2)
            loop[self.col] = (s, pid, 0.0, 1.0)
        for v in vs:
            self.n[v] = normal(v.co) if callable(normal) else normal

    def card(self, c, roll, size, rect, normal, shade):
        """Пучок, що розгортається до камери (як у лісі): 4 вершини в центрі, кут у UV2."""
        h = size / 2
        c = Vector(c)
        c.z = max(c.z, h * 0.8)
        cr, sr = math.cos(roll), math.sin(roll)
        uv2s = []
        for u, v in ((0, 0), (1, 0), (1, 1), (0, 1)):
            x, y = (u * 2 - 1) * h, (v * 2 - 1) * h
            uv2s.append(((x * cr - y * sr) / TILE_M, (x * sr + y * cr) / TILE_M))
        n = normal(c)
        self.quad([c] * 4, rect, uv2s, [shade] * 4, n)

    def fixed(self, corners, rect, shades, normal, pid=None):
        self.quad(corners, rect, [FIXED] * 4, shades, normal, pid)

    def shade(self, corners, rect, strength, lift=0.0):
        """Пляма затінення: м'яка, неправильна, затемнює ґрунт (strength — частка в центрі); lift —
        висота крони, м: на сонячній карті шейдер витягує пляму від сонця на довжину тіні."""
        self.quad(corners, rect, [FIXED] * 4, [strength] * 4, Vector((0, 0, 1)), shade_surface=True)
        b = min(lift / TILE_M / 2.0, 1.0)
        self.bm.faces.ensure_lookup_table()
        for loop in self.bm.faces[-1].loops:
            col = loop[self.col]
            loop[self.col] = (col[0], col[1], b, col[3])

    def tube(self, pts, radii, rect, sides=4, tone=BARK_TONE):
        """Стовбур чи гілка: трубка з кількох відрізків, смуга кори вздовж."""
        pid = self.new_id()
        rings = []
        total = sum((Vector(pts[i + 1]) - Vector(pts[i])).length for i in range(len(pts) - 1))
        acc = 0.0
        for i, (p, r) in enumerate(zip(pts, radii)):
            p = Vector(p)
            d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            t = ref.cross(d).normalized()
            b = d.cross(t)
            if i:
                acc += (p - Vector(pts[i - 1])).length
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                off = t * math.cos(a) + b * math.sin(a)
                v = self.bm.verts.new(p + off * r)
                self.n[v] = off
                ring.append((v, min(acc / max(total, 1e-6), 1.0)))
            rings.append(ring)
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(sides):
                j = (k + 1) % sides
                f = self.bm.faces.new((r0[k][0], r0[j][0], r1[j][0], r1[k][0]))
                for loop, (u, v) in zip(f.loops, ((0, r0[k][1]), (1, r0[j][1]), (1, r1[j][1]), (0, r1[k][1]))):
                    loop[self.uv].uv = to_atlas(rect, u, v)
                    loop[self.uv2].uv = uv2(0.0, 0.0)
                    loop[self.col] = (tone, pid, 0.0, 1.0)

    def tris(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def finish(self, name, mat, shade_mat):
        bm = self.bm
        me = bpy.data.meshes.new(name)
        bm.verts.index_update()
        order = list(bm.verts)
        for f in bm.faces:
            for v in f.verts:
                self.n.setdefault(v, f.normal)
        bm.to_mesh(me)
        bm.free()
        me.normals_split_custom_set_from_vertices([tuple(self.n[v]) for v in order])
        # Тон пучка — у COLOR_0: Godot читає лише його (див. ліс, build_library.py).
        me.color_attributes.active_color = me.color_attributes["Col"]
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
        me.materials.append(mat)
        me.materials.append(shade_mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        s = 1.0 / TILE_M
        ob.scale = (s, s, s)
        return ob


def sub_rect(rect, v0, v1):
    """Частина спрайта між v0 і v1 по висоті (0 — низ кадру)."""
    x, y, w, h = rect
    return [x, y + (1.0 - v1) * h, w, (v1 - v0) * h]


def shade_of(hfrac, rfrac):
    """Тон пучка: нижня третина й глибина крони темніші — туди світла доходить менше."""
    return min(max(0.5 + 0.5 * (0.9 * hfrac + 0.3 * (1.0 - rfrac * rfrac) - 0.1), 0.5), 1.0)


def check_budget(m, it, kind):
    t = m.tris()
    lim = BUDGET[kind]
    assert t <= lim, "%s: %d трикутників > %d" % (it["node"], t, lim)


def sheaf(it, rects, fallen):
    """Сніп очерету чи рогозу: вертикальні картки з довільним поворотом у плямі rx×ry.
    Повалений — зім'ятий сніп 0,3–0,6 м: низ стебел стоїть, верх зламаний і лягає в один бік,
    куди їхала техніка."""
    rng = random.Random(it["node"])
    m = Mesh(it["node"])
    sprites = rects["sprites"][it["kind"]]
    fall_dir = rng.uniform(0, 2 * math.pi)
    for i in range(it["cards"]):
        # Густіше до середини: край плями рідшає, як у справжньої куртини.
        r = math.sqrt(rng.random()) * 0.85
        a = rng.uniform(0, 2 * math.pi)
        x, y = math.cos(a) * r * it["rx"], math.sin(a) * r * it["ry"]
        h = rng.uniform(*it["h"]) * (1.0 - 0.25 * r * r)
        w = h * rng.uniform(0.3, 0.5)
        yaw = rng.uniform(0, math.pi)
        fd = fall_dir + rng.gauss(0, 0.3)
        hb = rng.uniform(0.25, 0.45)
        sag = rng.uniform(-0.1, 0.12)
        rect = rng.choice(sprites)
        # Нижче землі на різну глибину: на схилі берега картка не висить, а низ куртини не рівний.
        base = Vector((x, y, -rng.uniform(0.08, 0.35)))
        tilt = Vector((rng.gauss(0, 0.12), rng.gauss(0, 0.12), 0.0))
        if not fallen:
            d = Vector((math.cos(yaw), math.sin(yaw), 0.0))
            # Невеликий нахил назовні від середини: куртина розходиться віялом.
            up = (Vector((0, 0, 1)) + Vector((x, y, 0.0)) * 0.22 + tilt).normalized() * (h - base.z)
            m.fixed([base - d * w / 2, base + d * w / 2, base + d * w / 2 + up, base - d * w / 2 + up], rect,
                    (0.85, 0.85, 1.0, 1.0), Vector((-d.y, d.x, 0.0)))
        else:
            along = Vector((math.cos(fd), math.sin(fd), 0.0))
            side = Vector((-along.y, along.x, 0.0))
            pid = m.new_id()
            k = (hb + 0.1) / (h + 0.1)
            low = base + Vector((0, 0, hb + 0.1))
            m.fixed([base - side * w / 2, base + side * w / 2, low + side * w / 2, low - side * w / 2],
                    sub_rect(rect, 0.0, k), (0.5, 0.5, 0.65, 0.65), along, pid)
            tip = low + along * (h - hb) * 0.9 + Vector((0, 0, sag))
            m.fixed([low - side * w / 2, low + side * w / 2, tip + side * w / 2, tip - side * w / 2],
                    sub_rect(rect, k, 1.0), (0.6, 0.6, 0.62, 0.62), Vector((0, 0, 1)), pid)
    check_budget(m, it, "sheaf")
    return m


def litter(m, rects, rx, ry, rng, z=0.3, centre=Vector(), strength=0.25, lift=0.0):
    """Пляма затінення під рослиною (поверхня 1, veg_shade.gdshader): земля бою тіні сонця не
    показує, і без плями рослина стоїть, як на столі. Пляма піднята на z = 0,3 м над основою:
    нерівний рельєф у її межах інакше ховав більшу частину плями під землею."""
    a = rng.uniform(0, 2 * math.pi)
    ca, sa = math.cos(a), math.sin(a)
    corners = [centre + Vector((x * rx * ca - y * ry * sa, x * rx * sa + y * ry * ca, z)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    m.shade(corners, rects["sprites"]["litter"][0], strength, lift)


def crown(it, rects, fallen):
    """Кущ: пучки в еліпсоїді (ваза, конус, ряд) на кількох стеблах від землі.
    Повалений — зім'ятий пучок 0,3–0,6 м, витягнутий і нахилений у бік руху техніки."""
    rng = random.Random(it["node"])
    skel = random.Random(it["node"] + "skel")
    m = Mesh(it["node"])
    sprites = rects["sprites"][it["kind"]]
    bark = rects["bark"][it["kind"]]
    top, base = it["top"], it["base"]
    rx, ry = it["rx"], it["ry"]
    lean = Vector((*it.get("lean", (0.0, 0.0)), 0.0))
    cz = (top + base) / 2
    rz = (top - base) / 2
    ctr = Vector((0, 0, cz)) + lean * (cz / top)
    td = skel.uniform(0, 2 * math.pi)
    along = Vector((math.cos(td), math.sin(td), 0.0))
    side = Vector((-along.y, along.x, 0.0))

    def normal_of(p):
        s = Vector(((p.x - ctr.x) / rx, (p.y - ctr.y) / ry, (p.z - ctr.z) / rz))
        return s.normalized() if s.length > 1e-6 else Vector((0, 0, 1))

    # Пучки: точки в еліпсоїді, зсунуті до поверхні (r^0.4). Усі властивості пучка тягнуться
    # до вибірки пізньої пори, тож кущ однаковий у всі пори, лише голий рідший.
    cards = []
    while len(cards) < it["cards"]:
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        r = rng.random() ** 0.4
        p = Vector((v.x * rx * r, v.y * ry * r, v.z * rz * r))
        f = (p.z + rz) / (2 * rz)
        if it.get("cone"):
            # Туя: конус, вузький угорі.
            p.x *= 1.15 - f
            p.y *= 1.15 - f
        if it.get("vase"):
            # Кущ, що розходиться від землі вазою: низ крони вужчий.
            k = 1.0 - it["vase"] * (1.0 - f)
            p.x *= k
            p.y *= k
        if it.get("row"):
            p.x = rng.uniform(-rx, rx)
        cards.append((p + ctr, rng.uniform(*it["card"]), rng.choice(sprites), rng.uniform(0, 2 * math.pi)))
    keep = it.get("bare", 1.0) if (SEASON == "late" and it["kind"] in LATE_BARE) else 1.0
    cards = cards[:max(1, round(len(cards) * keep))]
    if fallen:
        return crushed(it, m, rects, bark, cards, td, base, top, skel)
    for p, size, rect, roll in cards:
        hfrac = min(max((p.z - base) / max(top - base, 0.5), 0.0), 1.0)
        rfrac = min(math.hypot((p.x - ctr.x) / rx, (p.y - ctr.y) / ry), 1.0)
        nrm = normal_of(p)
        m.card(p, roll, size, rect, lambda _c, n=nrm: n, shade_of(hfrac, rfrac))
    stems = []
    for k in range(it.get("stems", 0)):
        a = 2 * math.pi * k / max(it["stems"], 1) + skel.uniform(-0.4, 0.4)
        r0 = skel.uniform(0.05, 0.25) if not it.get("row") else 0.05
        x0 = skel.uniform(-rx * 0.9, rx * 0.9) if it.get("row") else math.cos(a) * r0
        y0 = 0.0 if it.get("row") else math.sin(a) * r0
        tip = Vector((x0 + math.cos(a) * rx * 0.5, y0 + math.sin(a) * ry * 0.5, base + (top - base) * 0.55)) + lean * 0.5
        if it.get("row"):
            tip = Vector((x0, math.sin(a) * ry * 0.4, top * 0.7))
        b0 = Vector((x0, y0, -0.1))
        rad = 0.035 if top > 2 else 0.015
        if it.get("frame"):
            # Стебла глоду й шипшини товщі за справжні (2–4 см): інакше на найближчому зумі вони
            # менші за піксель і кущ читається пухнастою масою без каркаса.
            rad = 0.05
        lm = dict(pts=[b0, b0.lerp(tip, 0.5) + Vector((0, 0, 0.1)), tip], r=[rad, rad * 0.7, rad * 0.35])
        stems.append(lm)
        m.tube(lm["pts"], lm["r"], bark, sides=3)
    if it.get("frame"):
        # Колючий каркас: від кожного стебла ще гілки — пізньої пори їх видно між пучками.
        for lm in branch_out(stems, it["frame"], skel, 0.6, 0.9):
            m.tube(lm["pts"], [max(min(x, 0.04), 0.03) for x in lm["r"]], bark, sides=3)
    litter(m, rects, rx * 0.85, ry * 0.85, skel, lift=(top + base) / 2)
    check_budget(m, it, "yard" if GROUP == "yard" else "crown")
    return m


def crushed(it, m, rects, bark, cards, travel, base, top, rng):
    """Кущ, який переїхала техніка: 5–9 зламаних стебел 0,4–0,8 м заввишки, похилених під 35–60° від
    вертикалі в один бік (куди їхала техніка), з просвітами між ними, колір кори куща (без світлих зламів); трохи листя дрібними
    пучками біля стебел, не килимом; м'яка пляма затінення."""
    along = Vector((math.cos(travel), math.sin(travel), 0.0))
    # 5–9 стебел з просвітами між ними: густий пучок читався чорною брилою.
    n = rng.randint(5, 9)
    rad = 0.05
    stems = []
    for k in range(n):
        b0 = Vector((rng.gauss(0, 0.45), rng.gauss(0, 0.45), -0.05))
        ang = travel + rng.gauss(0, 0.3)
        # Стебла 1–1,4 м під 35–60° від вертикалі (30–55° від землі), кінці не вище 0,8 м.
        ln = rng.uniform(1.0, 1.4)
        pitch = math.radians(rng.uniform(30, 55))
        d = Vector((math.cos(ang) * math.cos(pitch), math.sin(ang) * math.cos(pitch), math.sin(pitch)))
        tip = b0 + d * min(ln, 0.8 / math.sin(pitch))
        m.tube([b0, b0.lerp(tip, 0.5), tip], [rad, rad * 0.75, rad * 0.5], bark, sides=3, tone=HEAP_TONE)
        stems.append((b0, tip))
    for i, (_, size, rect, roll) in enumerate(cards[:max(3, len(cards) // 8)]):
        b0, tip = stems[i % n]
        q = b0.lerp(tip, rng.uniform(0.3, 0.9)) + Vector((rng.gauss(0, 0.1), rng.gauss(0, 0.1), 0.0))
        m.card(q, roll, rng.uniform(0.3, 0.45), rect, lambda _c: Vector((0, 0.3, 1)).normalized(), rng.uniform(0.55, 0.8))
    litter(m, rects, 1.0, 0.8, rng, centre=along * 0.3)
    check_budget(m, it, "yard" if GROUP == "yard" else "crown")
    return m


def grow_pts(start, d, length, nseg, crook, rng, droop=0.0):
    """Ламана гілки: nseg відрізків, напрям щоразу трохи відхиляється (кривизна виду)."""
    pts = [Vector(start)]
    d = Vector(d).normalized()
    for _ in range(nseg):
        pts.append(pts[-1] + d * length / nseg)
        d = (d + Vector((rng.gauss(0, crook), rng.gauss(0, crook), rng.gauss(0, crook) * 0.5 - droop))).normalized()
    return pts


def branch_out(parents, count, rng, len_lo, len_hi):
    """По count дочірніх гілок на кожну батьківську (як у лісі, src_broadleaf.branch_out): від
    середини батьківської вбік і вгору, два відрізки, кінець тоншає до 2 см."""
    out = []
    for lm in parents:
        pts = lm["pts"]
        ld = (pts[-1] - pts[0]).normalized()
        sd = ld.cross(Vector((0, 0, 1)))
        sd = sd.normalized() if sd.length > 1e-3 else Vector((1, 0, 0))
        for _ in range(count):
            t = rng.uniform(0.45, 0.85)
            k = min(int(t * (len(pts) - 1)), len(pts) - 2)
            b = pts[k].lerp(pts[k + 1], t * (len(pts) - 1) - k)
            d = (ld + sd * rng.choice((-1, 1)) * rng.uniform(0.5, 0.9) + Vector((0, 0, 0.25))).normalized()
            ln = (pts[-1] - pts[0]).length * rng.uniform(len_lo, len_hi)
            mid = b + d * ln * 0.55
            e = mid + (d + Vector((rng.gauss(0, 0.2), rng.gauss(0, 0.2), rng.gauss(0, 0.2) + 0.15))) / 1.2 * ln * 0.45
            r0 = max(lm["r"][k] * 0.55, 0.03)
            out.append(dict(pts=[b, mid, e], r=[r0, r0 * 0.6, 0.02]))
    return out


def heap(it, m, rects, bark, branches, cards, travel):
    """Дерево, яке переїхав танк: низька щільна купа хмизу 0,3–0,5 м заввишки, ~0,3 клітинки. Гілки 5–12 см
    завтовшки й 0,4–1,2 м завдовжки, здебільшого притиснуті в бік руху, частина стирчить угору; 2–3 короткі
    уламки стовбура ≤ 1 м. Колір — сіро-бура кора дерева з тоном HEAP_TONE: світла
    деревина й злами на ігровому зумі читались білим сміттям. Купа читається силуетом і тінню.
    Листя пори року — дрібні пучки; пізньої пори його мало й воно під гіллям."""
    rng = random.Random(it["node"] + "heap")
    along = Vector((math.cos(travel), math.sin(travel), 0.0))
    side = Vector((-along.y, along.x, 0.0))
    # Розмір купи: уздовж руху ~0,5 висоти дерева, поперек ~0,4 ширини крони, не більше 6 × 4 м.
    # Щільна купа ~0,3 клітинки: півосі 1,2 × 1,0 м незалежно від розміру дерева.
    la, ls = 1.2, 1.0
    late = SEASON == "late" and it["kind"] in LATE_BARE

    def spot(k=0.35):
        u, v = rng.gauss(0, k), rng.gauss(0, k)
        return along * la * max(-1.0, min(u, 1.0)) + side * ls * max(-1.0, min(v, 1.0))

    litter(m, rects, la * 0.9, ls * 1.0, rng, strength=0.25)
    # Уламки стовбура: 2–3 короткі, ≤ 1 м, лежать.
    r = min(it["r"] * 0.6, 0.15)
    for k in range(rng.randint(2, 3)):
        c = spot(0.3) + Vector((0, 0, r))
        yaw = travel + rng.gauss(0, 0.6)
        d = Vector((math.cos(yaw), math.sin(yaw), rng.uniform(-0.05, 0.15))).normalized()
        ln = rng.uniform(0.5, 1.0)
        m.tube([c - d * ln / 2, c + d * ln / 2], [r, r * 0.9], bark, sides=5, tone=HEAP_TONE)
    # Хмиз: гілки 5–12 см завтовшки; висота купи росте до середини.
    n = 36
    for k in range(n):
        rad = rng.uniform(0.025, 0.06)
        ln = rng.uniform(0.4, 1.2)
        yaw = travel + rng.gauss(0, 0.7)
        up = k % 6 == 0  # кожна шоста стирчить угору під 12–25°
        pitch = math.radians(rng.uniform(12, 25) if up else rng.uniform(-8, 12))
        d = Vector((math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch)))
        p0 = spot()
        centre = 1.0 - min((p0.x / la) ** 2 + (p0.y / ls) ** 2, 1.0)
        p0.z = rng.uniform(0.05, 0.12 + 0.3 * centre)
        p1 = p0 + d * ln
        p1.z = min(max(p1.z, 0.05), 0.5)
        m.tube([p0, p1], [rad, rad * 0.6], bark, sides=3, tone=HEAP_TONE)
    # Листя: дрібні пучки 0,3–0,5 м.
    room = (BUDGET["tree"] - m.tris()) // 2
    nc = min(len(cards), room, 40 if late else 160)
    for _, size, rect, roll in cards[:nc]:
        p = spot() + Vector((0, 0, rng.uniform(0.05, 0.2) if late else rng.uniform(0.1, 0.5)))
        m.card(p, roll, rng.uniform(0.3, 0.5), rect, lambda _c: Vector((0, 0.3, 1)).normalized(), rng.uniform(0.5, 0.8))
    check_budget(m, it, "tree")
    return m


def tree(it, rects, fallen):
    """Дерево зі скелетом: стовбур (або кілька, або верба «головою»), ≥ 3 скелетні гілки,
    другий і третій порядок гілок, клуби листя на кінцях гілок. Будова — з окремого зерна,
    тож однакова в усі пори; пізньої пори видно третій порядок гілок і менше пучків.
    Повалений (переїхав танк) — heap()."""
    skel = random.Random(it["node"] + "skel")
    crng = random.Random(it["node"] + "cards")
    m = Mesh(it["node"], floor=True)
    sprites = rects["sprites"][it["kind"]]
    bark = rects["bark"][it["kind"]]
    h, cb, R, r = it["h"], it["cb"], it["w"] / 2, it["r"]
    la = math.radians(it["lean_deg"])
    ldir = skel.uniform(0, 2 * math.pi)
    up = Vector((math.sin(la) * math.cos(ldir), math.sin(la) * math.sin(ldir), math.cos(la)))
    adir = skel.uniform(0, 2 * math.pi)
    pollard = it.get("pollard", False)
    trunks, limbs = [], []
    leader_top = None
    if it.get("multi"):
        n = it["multi"]
        for k in range(n):
            az = 2 * math.pi * k / n + skel.uniform(-0.4, 0.4)
            d = (up + Vector((math.cos(az), math.sin(az), 0.0)) * math.sin(math.radians(it["rise"]))).normalized()
            p0 = Vector((math.cos(az) * 0.12, math.sin(az) * 0.12, -0.15))
            pts = grow_pts(p0, d, (h - cb * 0.5) * skel.uniform(0.8, 0.95), 3, it["crook"], skel)
            trunks.append(dict(pts=pts, r=[r, r * 0.75, r * 0.45, 0.08]))
        limbs = list(trunks)
        trunks = []
        # Від кожного стовбура — ще дві гілки першого порядку.
        limbs += branch_out(limbs, 2, skel, 0.4, 0.55)
    else:
        F = up * it["fork"]
        trunks.append(dict(pts=[Vector((0, 0, -0.15)), up * it["fork"] * 0.5, F], r=[r * 1.2, r, r * 0.88]))
        if pollard:
            # «Голова» обрізаної верби: потовщення-наріст, з якого б'ють прямі пагони.
            trunks.append(dict(pts=[F - up * 0.15, F + up * 0.12, F + up * 0.4], r=[r * 1.1, r * 1.55, r * 0.9]))
        if it["leader"] > 0:
            pts = grow_pts(F, up, max(cb + it["leader"] * (h - cb) - F.z, 0.5), 2, it["crook"] * 0.5, skel)
            trunks.append(dict(pts=pts, r=[r * 0.85, r * 0.55, r * 0.25]))
            leader_top = pts[-1]
        n = it["limbs"]
        for i in range(n):
            az = 2 * math.pi * i / n + skel.uniform(-0.45, 0.45)
            start = F.lerp(leader_top, 0.1 + 0.7 * i / n) if (leader_top is not None and not pollard) else F
            rise = math.radians(it["rise"] * skel.uniform(0.8, 1.2))
            d = Vector((math.sin(rise) * math.cos(az), math.sin(rise) * math.sin(az), math.cos(rise)))
            reach = R * (1.0 + it["asym"] * math.cos(az - adir))
            L = reach / max(math.sin(rise), 0.3) * 0.82
            L = min(L, (h - it["lobe_r"] * 0.7 - start.z) / max(math.cos(rise), 0.2))
            if pollard:
                L = skel.uniform(2.6, 3.6)
            r0 = 0.05 if pollard else r * 0.55
            pts = grow_pts(start, d, L, 3, it["crook"], skel, it.get("droop", 0.0))
            limbs.append(dict(pts=pts, r=[r0, r0 * 0.7, r0 * 0.45, min(0.05, r0 * 0.3)]))
    sec = branch_out(limbs, it["sec"], skel, 0.35, 0.55)
    ter = branch_out(sec, it["ter"], skel, 0.45, 0.6)
    # Клуби листя — на кінцях гілок першого й другого порядку (у верби «головою» — уздовж
    # пагонів), а не в еліпсоїді: між клубами просвіти, обрис рваний.
    centres = [lm["pts"][-1] for lm in limbs + sec]
    if pollard:
        centres += [lm["pts"][1].lerp(lm["pts"][2], 0.5) for lm in limbs]
    if leader_top is not None:
        centres.append(leader_top + Vector((0, 0, it["lobe_r"] * 0.3)))
    radii = [it["lobe_r"] * skel.uniform(0.7, 1.25) for _ in centres]
    mid = sum(centres, Vector()) / len(centres)
    cards = []
    for _ in range(it["cards"]):
        i = crng.randrange(len(centres))
        d = Vector((crng.gauss(0, 1), crng.gauss(0, 1), crng.gauss(0, 1)))
        d.z = abs(d.z) * 0.8 - 0.2  # низ клубу камера не бачить
        d = d.normalized()
        p = centres[i] + d * radii[i] * crng.uniform(0.45, 1.0)
        p.z = min(max(p.z, cb * 0.85), h)
        cards.append((p, crng.uniform(*it["card"]), crng.choice(sprites), crng.uniform(0, 2 * math.pi)))

    if fallen:
        return heap(it, m, rects, bark, limbs + sec, cards, ldir)
    for lm in trunks:
        m.tube(lm["pts"], lm["r"], bark, sides=6)
    for lm in limbs:
        m.tube(lm["pts"], lm["r"], bark, sides=4)
    for lm in sec:
        m.tube(lm["pts"], lm["r"], bark, sides=3)
    if SEASON == "late":
        for lm in ter:
            m.tube(lm["pts"], lm["r"], bark, sides=3)
    n = len(cards)
    if SEASON == "late" and it["kind"] in LATE_BARE:
        n = round(len(cards) * it["bare"])
    twig = rects["sprites"].get(it["kind"] + "_bare")
    if SEASON == "late" and twig:
        # Гола крона: картки дрібного гілля (спрайти без листя) біля кінців гілок другого й
        # третього порядку — густа сіро-бура мережа з розкидом тону, а не 4–6 палиць із грудками.
        trng = random.Random(it["node"] + "twigs")
        tips = [lm["pts"][-1] for lm in ter + sec] + [lm["pts"][1] for lm in sec]
        room = (BUDGET["tree"] - m.tris()) // 2 - n
        for k in range(max(min(room, 4 * len(tips), 220), 0)):
            c = tips[k % len(tips)] + Vector([trng.gauss(0, 0.3 * it["lobe_r"]) for _ in range(3)])
            nrm = ((c - mid).normalized() + Vector((0, 0, 0.3))).normalized()
            m.card(c, trng.uniform(0, 2 * math.pi), trng.uniform(*it["card"]) * trng.uniform(0.6, 0.9),
                   trng.choice(twig), lambda _c, n_=nrm: n_, trng.uniform(0.6, 1.0))
    # Пляма затінення під кроною; на сонячній карті шейдер витягує її в тінь від сонця.
    # Сила 0,55 — близько до плями дотику будівель (PropLayer.CONTACT_ALPHA 0,6): поруч із хатою тінь
    # дерева не має бути слабшою.
    litter(m, rects, R * 0.8, R * 0.75, random.Random(it["node"] + "shade"), strength=0.55, lift=(cb + h) / 2)
    n = min(n, (BUDGET["tree"] - m.tris()) // 2)
    for p, size, rect, roll in cards[:n]:
        hfrac = min(max((p.z - cb) / max(h - cb, 0.5), 0.0), 1.0)
        rfrac = min(math.hypot(p.x, p.y) / max(R, 0.5), 1.0)
        nrm = (p - mid).normalized()
        nrm = (nrm + Vector((0, 0, 0.3))).normalized()
        m.card(p, roll, size, rect, lambda _c, n_=nrm: n_, shade_of(hfrac, rfrac))
    check_budget(m, it, "tree")
    return m


def material(png, name=None):
    img = bpy.data.images.load(png)
    img.alpha_mode = "STRAIGHT"
    mat = bpy.data.materials.new(name or os.path.basename(png)[:-4])
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def patch_glb(path, cutoff):
    """Alpha-cut і двобічність у матеріалі; атлас лишається зовнішнім файлом (uri), а його копію,
    яку експортер із keep_originals ще й кладе в бінарний блок, вирізаємо: інакше атлас лежав би в
    репозиторії двічі."""
    data = open(path, "rb").read()
    jl, jt = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + jl])
    bl = struct.unpack("<I", data[20 + jl:24 + jl])[0]
    bin_ = data[28 + jl:28 + jl + bl]
    for mt in js["materials"]:
        mt["alphaMode"] = "MASK"
        mt["alphaCutoff"] = cutoff
        mt["doubleSided"] = True
        pbr = mt.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        mt.pop("extensions", None)
    # Обидва матеріали (рослина й пляма) — на тому самому атласі: один запис images на uri.
    uris = {}
    for i, im in enumerate(js.get("images", [])):
        uris.setdefault(im.get("uri"), i)
    for tex in js.get("textures", []):
        tex["source"] = uris[js["images"][tex["source"]].get("uri")]
    drop = set()
    for im in js.get("images", []):
        assert "uri" in im, "%s: атлас без uri" % path
        if "bufferView" in im:
            drop.add(im.pop("bufferView"))
    keep_img = sorted(set(uris.values()))
    remap_img = {old: new for new, old in enumerate(keep_img)}
    js["images"] = [js["images"][i] for i in keep_img]
    for tex in js.get("textures", []):
        tex["source"] = remap_img[tex["source"]]
    keep = [i for i in range(len(js["bufferViews"])) if i not in drop]
    remap = {old: new for new, old in enumerate(keep)}
    out_bin = bytearray()
    views = []
    for old in keep:
        bv = js["bufferViews"][old]
        chunk = bin_[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        out_bin += b"\0" * (-len(out_bin) % 4)
        bv["byteOffset"] = len(out_bin)
        out_bin += chunk
        views.append(bv)
    out_bin += b"\0" * (-len(out_bin) % 4)
    js["bufferViews"] = views
    js["buffers"][0]["byteLength"] = len(out_bin)
    for acc in js.get("accessors", []):
        acc["bufferView"] = remap[acc["bufferView"]]
    nj = json.dumps(js, separators=(",", ":")).encode()
    nj += b" " * (-len(nj) % 4)
    total = 12 + 8 + len(nj) + 8 + len(out_bin)
    out = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<II", len(nj), jt) + nj
    out += struct.pack("<II", len(out_bin), 0x004E4942) + bytes(out_bin)
    open(path, "wb").write(out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    name = "%s_veg_%s" % (GROUP, SEASON)
    rects = json.load(open(os.path.join(ATLAS_DIR, name + ".json")))
    # Атлас — один файл поруч із GLB (uri); пляма затінення — окремий матеріал на тому самому атласі.
    png = os.path.join(os.path.dirname(OUT), name + ".png")
    shutil.copyfile(os.path.join(ATLAS_DIR, name + ".png"), png)
    mat = material(png)
    shade_mat = material(png, name + "_shade")
    obs = []
    for it in ASSETS[GROUP]:
        for fallen in (False, True):
            node = it["node"] + ("_fallen" if fallen else "")
            m = {"sheaf": sheaf, "crown": crown, "tree": tree}[it["type"]](it, rects, fallen)
            obs.append(m.finish(node, mat, shade_mat))
    for o in bpy.context.scene.objects:
        o.select_set(o in obs)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="AUTO", export_keep_originals=True, export_texcoords=True,
                              export_normals=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_cameras=False, export_lights=False)
    patch_glb(OUT, 0.5)
    for o in obs:
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        size = [(max(v[i] for v in bb) - min(v[i] for v in bb)) * TILE_M for i in range(3)]
        print("NODE %s tris %d size_m %.1f x %.1f x %.1f" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), *size))


main()
