"""Збирає GLB бібліотеки рослинності групи на сезон: вузол на рослину плюс її повалений варіант.

Запуск:
  blender -b --factory-startup -P veg_build.py -- <тека_атласу> <група> <сезон> <вихід.glb>
Вузол = окремий меш (один MultiMesh на варіант), один матеріал на всю бібліотеку. Шейдер —
assets/props/vegetation/veg.gdshader (або veg_fade.gdshader над юнітом) з albedo_tex = атлас.
Масштаб гри: 1 тайл = 8 м = 1,0; земля на y = 0; початок координат — основа рослини.
Будова однакова в усіх сезонах (те саме зерно), змінюється лише атлас і частка пучків
голої крони, тож рослина на Річці й на Перехресті — та сама рослина.

<вузол>_fallen — повалений техникою: сніп очерету й кущ лягають на землю пласкими картками,
дерево падає на бік стовбуром і кроною вздовж землі.
"""
import json
import math
import os
import random
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ATLAS_DIR, GROUP, SEASON, OUT = argv[:4]
TILE_M = 8.0
FIXED = (1e-4, 0.0)  # UV2 (до перевертання, див. uv2()) нерухомої картки: листя для шейдера, але не розгортається до камери

# Розміри в метрах. sheaf: сніп очерету / рогозу; crown: кущ чи дерево.
#   rx, ry — півосі плями; h — висота снопа (від, до); cards — кількість карток.
#   crown: top — верх, base — низ крони, rx/ry — півосі крони, trunk — висота голого стовбура й
#   радіус біля землі, stems — кількість стовбурців куща від землі, card — розмір пучка (від, до),
#   bare — частка пучків голої крони (сезон late), lean — нахил (м на верх).
ASSETS = {
    "bank": [
        dict(node="bank_reed_01", kind="reed", type="sheaf", rx=0.7, ry=0.6, h=(1.6, 2.3), cards=14),
        dict(node="bank_reed_02", kind="reed", type="sheaf", rx=1.1, ry=0.9, h=(1.7, 2.5), cards=24),
        dict(node="bank_reed_03", kind="reed", type="sheaf", rx=1.6, ry=0.6, h=(1.5, 2.4), cards=28),
        dict(node="bank_cattail_01", kind="cattail", type="sheaf", rx=0.5, ry=0.45, h=(1.2, 1.8), cards=10),
        dict(node="bank_cattail_02", kind="cattail", type="sheaf", rx=0.9, ry=0.6, h=(1.3, 2.0), cards=16),
        dict(node="bank_bush_willow_01", kind="willow", type="crown", top=3.0, base=0.5, rx=1.5, ry=1.4, stems=7,
             card=(1.0, 1.5), cards=70, vase=0.5, bare=0.55),
        dict(node="bank_bush_willow_02", kind="willow", type="crown", top=2.2, base=0.3, rx=1.8, ry=1.4, stems=6,
             card=(0.9, 1.4), cards=70, vase=0.3, bare=0.55),
        dict(node="bank_bush_alder_01", kind="alder", type="crown", top=3.8, base=0.7, rx=1.6, ry=1.5, stems=5,
             card=(1.0, 1.6), cards=80, bare=0.5),
    ],
    "yard": [
        dict(node="yard_apple_01", kind="apple", type="crown", top=4.5, base=1.4, rx=2.3, ry=2.1, trunk=(1.4, 0.13),
             limbs=5, card=(1.1, 1.7), cards=120, bare=0.45, flat_top=0.25),
        dict(node="yard_apple_02", kind="apple", type="crown", top=5.2, base=1.6, rx=2.0, ry=1.9, trunk=(1.6, 0.12),
             limbs=4, card=(1.1, 1.7), cards=115, bare=0.45, lean=(0.5, 0.2)),
        dict(node="yard_cherry_01", kind="cherry", type="crown", top=5.0, base=1.5, rx=1.7, ry=1.6, trunk=(1.5, 0.11),
             limbs=5, card=(1.0, 1.5), cards=110, bare=0.4),
        dict(node="yard_walnut_01", kind="walnut", type="crown", top=10.0, base=2.8, rx=3.8, ry=3.5, trunk=(2.8, 0.28),
             limbs=6, card=(1.6, 2.5), cards=230, bare=0.45),
        dict(node="yard_lilac_01", kind="lilac", type="crown", top=2.8, base=0.6, rx=1.3, ry=1.2, stems=8,
             card=(0.9, 1.3), cards=70, vase=0.25, bare=0.7),
        dict(node="yard_elder_01", kind="elder", type="crown", top=3.0, base=0.8, rx=1.6, ry=1.5, stems=6,
             card=(1.0, 1.4), cards=70, vase=0.5, bare=0.5),
        dict(node="yard_berry_row_01", kind="berry", type="crown", top=1.1, base=0.15, rx=2.0, ry=0.4, stems=8,
             card=(0.55, 0.8), cards=36, row=True, bare=0.7),
        dict(node="yard_thuja_01", kind="thuja", type="crown", top=4.0, base=0.2, rx=0.7, ry=0.7, stems=1,
             card=(0.8, 1.1), cards=70, cone=True, bare=1.0),
    ],
    "meadow": [
        dict(node="meadow_hawthorn_01", kind="hawthorn", type="crown", top=2.9, base=0.4, rx=1.5, ry=1.4, stems=5,
             card=(1.0, 1.4), cards=80, bare=0.55),
        dict(node="meadow_hawthorn_02", kind="hawthorn", type="crown", top=2.0, base=0.3, rx=1.3, ry=1.1, stems=4,
             card=(0.9, 1.3), cards=60, bare=0.55),
        dict(node="meadow_dogrose_01", kind="dogrose", type="crown", top=1.7, base=0.15, rx=1.3, ry=1.1, stems=7,
             card=(0.8, 1.2), cards=50, vase=0.6, bare=0.6),
        dict(node="meadow_pear_01", kind="pear", type="crown", top=11.0, base=2.5, rx=3.4, ry=3.2, trunk=(2.5, 0.25),
             limbs=6, card=(1.6, 2.4), cards=230, bare=0.45, lean=(0.4, 0.0)),
        dict(node="meadow_oak_01", kind="oak", type="crown", top=12.5, base=2.6, rx=5.5, ry=5.0, trunk=(2.6, 0.45),
             limbs=7, card=(2.0, 3.0), cards=290, bare=0.6, flat_top=0.2),
        dict(node="meadow_willow_01", kind="wwillow", type="crown", top=9.0, base=2.0, rx=4.5, ry=4.2, trunk=(2.0, 0.40),
             limbs=7, card=(1.8, 2.6), cards=260, bare=0.55),
    ],
}
# Частка листків, що лишилась у пізньому сезоні (з veg_sprites.py): крона, де листків майже
# немає, рідшає пучками — крізь неї видно землю, як крізь голе дерево.
LATE_BARE = {"willow", "alder", "apple", "cherry", "walnut", "lilac", "elder", "berry", "hawthorn", "dogrose", "pear", "oak", "wwillow"}


def uv2(u, v):
    """Експортер glTF перевертає V кожної UV-карти (v → 1 − v), тож UV2 пишеться вже
    перевернутим: у Godot шейдер мусить отримати саме зсув кута (u, v), 0 — для кори."""
    return (u, 1.0 - v)


def to_atlas(rect, u, v):
    x, y, w, h = rect
    return (x + u * w, 1.0 - (y + (1.0 - v) * h))


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("UV2")
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.n = {}

    def quad(self, co, rect, uv2s, shades, normal):
        vs = [self.bm.verts.new(p) for p in co]
        f = self.bm.faces.new(vs)
        for loop, (u, v), u2, s in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1)), uv2s, shades):
            loop[self.uv].uv = to_atlas(rect, u, v)
            loop[self.uv2].uv = uv2(*u2)
            loop[self.col] = (s, s, s, 1.0)
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

    def fixed(self, corners, rect, shades, normal):
        self.quad(corners, rect, [FIXED] * 4, shades, normal)

    def tube(self, pts, radii, rect, sides=4):
        """Стовбур чи гілка: трубка з кількох відрізків, смуга кори вздовж."""
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
                    loop[self.col] = (1.0, 1.0, 1.0, 1.0)

    def finish(self, name, mat):
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
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        s = 1.0 / TILE_M
        ob.scale = (s, s, s)
        return ob


def sheaf(it, rects, fallen):
    """Сніп очерету чи рогозу: вертикальні картки з довільним поворотом у плямі rx×ry.
    Повалений — ті самі картки лягають майже пласко, стеблами в один бік (куди їхала техніка)."""
    rng = random.Random(it["node"])
    m = Mesh()
    sprites = rects["sprites"][it["kind"]]
    fall_dir = rng.uniform(0, 2 * math.pi)
    for i in range(it["cards"]):
        # Густіше до середини: край плями рідшає, як у справжньої куртини.
        r = math.sqrt(rng.random()) * 0.85
        a = rng.uniform(0, 2 * math.pi)
        x, y = math.cos(a) * r * it["rx"], math.sin(a) * r * it["ry"]
        h = rng.uniform(*it["h"]) * (1.0 - 0.25 * r * r)
        w = h * 0.5 * rng.uniform(0.9, 1.15)
        yaw = rng.uniform(0, math.pi)
        d = Vector((math.cos(yaw), math.sin(yaw), 0.0))
        nrm = Vector((-d.y, d.x, 0.0))
        rect = rng.choice(sprites)
        base = Vector((x, y, -0.1))  # нижче землі: на схилі берега картка не висить
        if not fallen:
            # Невеликий нахил назовні від середини: куртина розходиться віялом.
            out = Vector((x, y, 0.0)) * 0.12
            up = (Vector((0, 0, 1)) + out).normalized() * (h + 0.1)
            m.fixed([base - d * w / 2, base + d * w / 2, base + d * w / 2 + up, base - d * w / 2 + up], rect,
                    (0.55, 0.55, 1.0, 1.0), nrm)
        else:
            fd = fall_dir + rng.gauss(0, 0.35)
            along = Vector((math.cos(fd), math.sin(fd), 0.0))
            side = Vector((-along.y, along.x, 0.0))
            tip = along * h * 0.95 + Vector((0, 0, rng.uniform(0.15, 0.35)))
            b = Vector((x, y, 0.05))
            m.fixed([b - side * w / 2, b + side * w / 2, b + side * w / 2 + tip, b - side * w / 2 + tip], rect,
                    (0.6, 0.6, 0.85, 0.85), Vector((0, 0, 1)))
    return m


def crown(it, rects, fallen):
    rng = random.Random(it["node"])
    m = Mesh()
    sprites = rects["sprites"][it["kind"]]
    bark = rects["bark"][it["kind"]]
    top, base = it["top"], it["base"]
    rx, ry = it["rx"], it["ry"]
    lean = Vector((*it.get("lean", (0.0, 0.0)), 0.0))
    cz = (top + base) / 2
    rz = (top - base) / 2
    ctr = Vector((0, 0, cz)) + lean * (cz / top)
    is_tree = "trunk" in it
    shrub_flat = fallen and not is_tree
    fall = None
    if fallen and is_tree:
        # Дерево падає на бік: поворот навколо осі по землі, крона лягає вздовж. Поворот — до
        # розстановки пучків, щоб пучки не пішли під землю (card() тримає їх над нею).
        a = rng.uniform(0, 2 * math.pi)
        axis = Vector((math.cos(a), math.sin(a), 0.0))
        fall = Matrix.Translation((0, 0, it["trunk"][1] * 0.8)) @ Matrix.Rotation(math.radians(84), 4, axis)

    def T(p):
        if not fall:
            return Vector(p)
        # Крона, що впала, осідає: гілки ламаються під власною вагою, верхній бік не стирчить на всю ширину.
        q = fall @ Vector(p)
        return Vector((q.x, q.y, q.z * 0.45))

    def tube(pts, radii, sides):
        q = [T(p) for p in pts]
        q = [Vector((v.x, v.y, max(v.z, r * 0.6))) if fall else v for v, r in zip(q, radii)]
        m.tube([tuple(v) for v in q], radii, bark, sides=sides)

    def normal_of(p):
        s = Vector(((p.x - ctr.x) / rx, (p.y - ctr.y) / ry, (p.z - ctr.z) / rz))
        return s.normalized() if s.length > 1e-6 else Vector((0, 0, 1))

    # Пучки: точки в еліпсоїді крони, зсунуті до поверхні (r^0.4): усередині крони пучки не
    # видно, а крона читається об'ємом лише з повним краєм.
    keep = it.get("bare", 1.0) if (SEASON == "late" and it["kind"] in LATE_BARE) else 1.0
    # Крона дерева на відкритому місці — кілька лопатей навколо скелетних гілок, а не куля:
    # рваний обрис і просвіти між лопатями (на фото поодиноких дубів і груш так і є).
    lobes = [(Vector((0, 0, 0)), 1.0)]
    if is_tree:
        lobes = []
        for k in range(5):
            a = 2 * math.pi * k / 5 + rng.uniform(-0.4, 0.4)
            off = Vector((math.cos(a) * rx * 0.45, math.sin(a) * ry * 0.45, rng.uniform(-0.2, 0.35) * rz))
            lobes.append((off, rng.uniform(0.5, 0.65)))
        lobes.append((Vector((0, 0, rz * 0.3)), 0.6))
    pts = []
    while len(pts) < it["cards"]:
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        r = rng.random() ** 0.4
        lo, lk = rng.choice(lobes)
        p = Vector((v.x * rx * r * lk, v.y * ry * r * lk, v.z * rz * r * lk)) + lo
        if it.get("cone"):
            # Туя: конус, вузький угорі.
            f = (p.z + rz) / (2 * rz)
            p.x *= 1.15 - f
            p.y *= 1.15 - f
        if it.get("vase"):
            # Кущ, що розходиться від землі вазою: низ крони вужчий.
            f = (p.z + rz) / (2 * rz)
            k = 1.0 - it["vase"] * (1.0 - f)
            p.x *= k
            p.y *= k
        if it.get("flat_top") and p.z > rz * (1 - it["flat_top"]):
            p.z = rz * (1 - it["flat_top"]) + (p.z - rz * (1 - it["flat_top"])) * 0.4
        if it.get("row"):
            p.x = rng.uniform(-rx, rx)
        pts.append(p + ctr)
    pts = rng.sample(pts, max(1, round(len(pts) * keep)))
    for p in pts:
        hfrac = min(max((p.z - base) / max(top - base, 0.5), 0.0), 1.0)
        rfrac = min(math.hypot((p.x - ctr.x) / rx, (p.y - ctr.y) / ry), 1.0)
        shade = min(max(0.55 + 0.45 * (0.8 * hfrac + 0.35 * (1.0 - rfrac * rfrac) - 0.1), 0.55), 1.0)
        size = rng.uniform(*it["card"])
        rect = rng.choice(sprites)
        if shrub_flat:
            # Розчавлений кущ: пучки лежать на землі, пляма ширша, гілки зламані й розкидані.
            q = Vector((p.x * 1.3, p.y * 1.3, 0.04 + 0.25 * hfrac))
            a = rng.uniform(0, 2 * math.pi)
            ca, sa = math.cos(a), math.sin(a)
            corners = [q + Vector((x * ca - y * sa, x * sa + y * ca, 0.0)) * size / 2 for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            m.fixed(corners, rect, [shade * 0.9] * 4, Vector((0, 0, 1)))
        else:
            nrm = normal_of(p)
            m.card(T(p), rng.uniform(0, 2 * math.pi), size, rect, lambda _c, n=nrm: n, shade)
    # Стовбур і гілки.
    if is_tree:
        th, tr = it["trunk"]
        top_t = Vector((0, 0, th + 0.35 * (top - th) * 0.5)) + lean * 0.5
        tube([(0, 0, -0.15), (0, 0, th * 0.5), tuple(top_t)], [tr * 1.15, tr, tr * 0.8], 6)
        for k in range(it["limbs"]):
            a = 2 * math.pi * k / it["limbs"] + rng.uniform(-0.3, 0.3)
            tip = ctr + Vector((math.cos(a) * rx * 0.7, math.sin(a) * ry * 0.7, rng.uniform(-0.2, 0.5) * rz))
            mid = top_t.lerp(tip, 0.5) + Vector((0, 0, 0.3 * rz))
            tube([tuple(top_t), tuple(mid), tuple(tip)], [tr * 0.55, tr * 0.35, tr * 0.12], 3)
    else:
        for k in range(it.get("stems", 0)):
            a = 2 * math.pi * k / max(it["stems"], 1) + rng.uniform(-0.4, 0.4)
            r0 = rng.uniform(0.05, 0.25) if not it.get("row") else 0.05
            x0 = rng.uniform(-rx * 0.9, rx * 0.9) if it.get("row") else math.cos(a) * r0
            y0 = 0.0 if it.get("row") else math.sin(a) * r0
            tip = Vector((x0 + math.cos(a) * rx * 0.5, y0 + math.sin(a) * ry * 0.5, base + (top - base) * 0.55))
            if it.get("row"):
                tip = Vector((x0, math.sin(a) * ry * 0.4, top * 0.7))
            if shrub_flat:
                tip = Vector((tip.x * 1.8, tip.y * 1.8, 0.12))
            rad = 0.035 if top > 2 else 0.015
            tube([(x0, y0, -0.1), tuple(Vector((x0, y0, 0)).lerp(tip, 0.5) + Vector((0, 0, 0.1))), tuple(tip)],
                 [rad, rad * 0.7, rad * 0.35], 3)
    return m


def material(png):
    img = bpy.data.images.load(png)
    img.alpha_mode = "STRAIGHT"
    mat = bpy.data.materials.new(os.path.basename(png)[:-4])
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
    """Alpha-cut і двобічність у матеріалі: експортер не завжди їх виставляє."""
    data = open(path, "rb").read()
    jl, jt = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + jl])
    for mt in js["materials"]:
        mt["alphaMode"] = "MASK"
        mt["alphaCutoff"] = cutoff
        mt["doubleSided"] = True
        pbr = mt.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        mt.pop("extensions", None)
    nj = json.dumps(js, separators=(",", ":")).encode()
    nj += b" " * (-len(nj) % 4)
    rest = data[20 + jl:]
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(nj) + len(rest)) + struct.pack("<II", len(nj), jt) + nj + rest
    open(path, "wb").write(out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    name = "%s_veg_%s" % (GROUP, SEASON)
    rects = json.load(open(os.path.join(ATLAS_DIR, name + ".json")))
    mat = material(os.path.join(ATLAS_DIR, name + ".png"))
    obs = []
    for it in ASSETS[GROUP]:
        for fallen in (False, True):
            node = it["node"] + ("_fallen" if fallen else "")
            if it["type"] == "sheaf":
                m = sheaf(it, rects, fallen)
            else:
                m = crown(it, rects, fallen)
            obs.append(m.finish(node, mat))
    for o in bpy.context.scene.objects:
        o.select_set(o in obs)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="AUTO", export_texcoords=True,
                              export_normals=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                              export_cameras=False, export_lights=False)
    patch_glb(OUT, 0.5)
    for o in obs:
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        size = [(max(v[i] for v in bb) - min(v[i] for v in bb)) * TILE_M for i in range(3)]
        print("NODE %s tris %d size_m %.1f x %.1f x %.1f" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons), *size))


main()
