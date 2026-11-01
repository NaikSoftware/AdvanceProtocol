"""Спрайти рослинності: пучки крони кущів і дерев та кущики очерету й рогозу.

Запуск:
  blender -b --factory-startup -P veg_sprites.py -- <вихід> <вид> <сезон> [спрайтів] [зерно]
сезон: late (Річка, пізня осінь) | summer (Перехрестя, пізнє літо) | early (Хребет, рання осінь).
Пише <вихід>/<вид>_<сезон>/sprite_NN.png.

Пучок крони — як у лісі (forest/src_leaf_sprites.py): процедурна гілка з листками й плодами,
рендер згори й під 45°, кадр ~2,4 м (менший для низьких кущів). Сніп очерету чи рогозу —
група стебел із листками й пухнастою верхівкою або качаном, рендер збоку (картка стоїть вертикально).
Готових CC0-моделей цих рослин немає, тож усе — геометрія з чисел нижче.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "forest"))
import crown_lib as cl  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, KIND, SEASON = argv[:3]
N = int(argv[3]) if len(argv) > 3 else 6
SEED = int(argv[4]) if len(argv) > 4 else 1

# Кольори sRGB. Зелень — як у лісі (GREENS у src_leaf_sprites), щоб садки й луки сиділи
# поруч із ним.
G = [(0.20, 0.30, 0.10), (0.24, 0.34, 0.12), (0.17, 0.26, 0.09), (0.28, 0.36, 0.14)]
G_DARK = [(0.13, 0.22, 0.08), (0.16, 0.25, 0.09), (0.12, 0.19, 0.08)]
G_GREY = [(0.34, 0.40, 0.33), (0.41, 0.46, 0.40), (0.29, 0.35, 0.28)]  # верба: сріблясто-сіро-зелена, без жовтизни
EARLY = [(0.40, 0.42, 0.16), (0.46, 0.45, 0.17), (0.34, 0.38, 0.15)]
YELLOW = [(0.62, 0.52, 0.20), (0.55, 0.47, 0.20), (0.58, 0.50, 0.24)]
BROWN = [(0.36, 0.25, 0.15), (0.30, 0.21, 0.13), (0.40, 0.29, 0.17)]
OLIVE = [(0.32, 0.32, 0.15), (0.38, 0.36, 0.17), (0.28, 0.28, 0.14)]
RED = [(0.55, 0.20, 0.10), (0.62, 0.28, 0.12), (0.50, 0.24, 0.12)]

# Будова пучка: seg — перший відрізок (м), depth, kids, spread (°), droop, leaf — довжина
# листка (м), shape — ovate | lance | scale, per_node, twig_r, bark, sm — кадр спрайта (м).
# leaves[сезон] — (частка листків, що лишилась, палітра, домішка: (частка, палітра)).
# fruit[сезон] — (частка вузлів із плодом, діаметр м, палітра).
K = {
    "willow": dict(seg=0.6, depth=6, kids=(2, 3), spread=24, droop=0.0, leaf=0.10, shape="lance", per_node=7,
                   twig_r=0.010, bark=(0.42, 0.36, 0.18), sm=2.4,
                   leaves={"summer": (1.0, G_GREY, None), "early": (0.9, G_GREY, (0.3, EARLY)), "late": (0.06, OLIVE, (0.4, YELLOW))}),
    "alder": dict(seg=0.6, depth=6, kids=(2, 3), spread=40, droop=0.05, leaf=0.08, shape="ovate", per_node=6,
                  twig_r=0.012, bark=(0.34, 0.31, 0.27), sm=2.4,
                  leaves={"summer": (1.0, G_DARK, None), "early": (0.95, G_DARK, (0.15, G)), "late": (0.04, BROWN, (0.3, OLIVE))},
                  fruit={"late": (0.10, 0.02, [(0.12, 0.09, 0.07)]), "early": (0.08, 0.02, [(0.20, 0.22, 0.10)])}),
    "apple": dict(seg=0.55, depth=6, kids=(2, 3), spread=50, droop=0.12, leaf=0.075, shape="ovate", per_node=6,
                  twig_r=0.013, bark=(0.33, 0.30, 0.27), sm=2.4,
                  leaves={"summer": (1.0, G, None), "early": (0.85, EARLY, (0.3, G)), "late": (0.025, YELLOW, (0.5, BROWN))},
                  fruit={"summer": (0.10, 0.08, [(0.62, 0.20, 0.10), (0.66, 0.58, 0.20), (0.55, 0.30, 0.10)]),
                         "early": (0.07, 0.08, [(0.62, 0.20, 0.10), (0.66, 0.58, 0.20)]),
                         "late": (0.02, 0.08, [(0.45, 0.30, 0.10)])}),
    "cherry": dict(seg=0.6, depth=6, kids=(2, 3), spread=38, droop=0.05, leaf=0.075, shape="lance", per_node=6,
                   twig_r=0.012, bark=(0.30, 0.20, 0.18), sm=2.4,
                   leaves={"summer": (1.0, G_DARK, (0.3, G)), "early": (0.8, RED, (0.5, EARLY)), "late": (0.02, BROWN, None)}),
    "walnut": dict(seg=0.75, depth=6, kids=(2, 3), spread=48, droop=0.08, leaf=0.12, shape="ovate", per_node=6,
                   twig_r=0.016, bark=(0.42, 0.40, 0.37), sm=2.8,
                   leaves={"summer": (1.0, G, (0.3, EARLY)), "early": (0.9, EARLY, (0.3, YELLOW)), "late": (0.035, YELLOW, (0.4, BROWN))}),
    "lilac": dict(seg=0.45, depth=6, kids=(2, 3), spread=30, droop=0.0, leaf=0.08, shape="ovate", per_node=6,
                  twig_r=0.010, bark=(0.34, 0.32, 0.30), sm=2.0,
                  leaves={"summer": (1.0, G_DARK, (0.2, G)), "early": (0.95, G_DARK, (0.3, G)), "late": (0.06, OLIVE, (0.3, BROWN))},
                  fruit={"late": (0.08, 0.03, [(0.33, 0.25, 0.16)]), "early": (0.08, 0.03, [(0.33, 0.25, 0.16)])}),
    "elder": dict(seg=0.5, depth=6, kids=(2, 3), spread=45, droop=0.2, leaf=0.09, shape="lance", per_node=7,
                  twig_r=0.011, bark=(0.40, 0.38, 0.33), sm=2.2,
                  leaves={"summer": (1.0, G, None), "early": (0.85, EARLY, (0.3, G)), "late": (0.08, OLIVE, (0.5, BROWN))},
                  fruit={"summer": (0.12, 0.09, [(0.10, 0.06, 0.09)]), "early": (0.08, 0.08, [(0.12, 0.07, 0.10)])}),
    "berry": dict(seg=0.28, depth=5, kids=(2, 3), spread=40, droop=0.15, leaf=0.06, shape="ovate", per_node=6,
                  twig_r=0.007, bark=(0.38, 0.27, 0.20), sm=1.2,
                  leaves={"summer": (1.0, G, None), "early": (0.85, EARLY, (0.25, RED)), "late": (0.05, BROWN, None)},
                  fruit={"summer": (0.08, 0.025, [(0.55, 0.10, 0.10), (0.12, 0.06, 0.08)])}),
    "thuja": dict(seg=0.45, depth=6, kids=(3, 3), spread=30, droop=0.0, leaf=0.07, shape="scale", per_node=8,
                  twig_r=0.008, bark=(0.30, 0.22, 0.17), sm=1.8,
                  leaves={"summer": (1.0, G_DARK, None), "early": (1.0, G_DARK, None), "late": (1.0, [(0.17, 0.21, 0.11), (0.20, 0.24, 0.12), (0.15, 0.19, 0.10)], (0.25, G_DARK))}),
    "hawthorn": dict(seg=0.45, depth=6, kids=(2, 3), spread=55, droop=0.0, leaf=0.05, shape="ovate", per_node=7,
                     twig_r=0.010, bark=(0.30, 0.27, 0.24), sm=2.0,
                     leaves={"summer": (1.0, G_DARK, (0.3, G)), "early": (0.85, EARLY, (0.3, G_DARK)), "late": (0.05, BROWN, None)},
                     fruit={"summer": (0.04, 0.013, [(0.46, 0.14, 0.08)]), "early": (0.08, 0.013, [(0.62, 0.12, 0.07)]),
                            "late": (0.05, 0.013, [(0.60, 0.13, 0.08), (0.52, 0.11, 0.08)])}),
    "dogrose": dict(seg=0.35, depth=5, kids=(2, 3), spread=40, droop=0.35, leaf=0.05, shape="ovate", per_node=6,
                    twig_r=0.008, bark=(0.30, 0.22, 0.16), sm=1.6,
                    leaves={"summer": (1.0, G, None), "early": (0.8, EARLY, (0.35, RED)), "late": (0.04, BROWN, None)},
                    fruit={"summer": (0.03, 0.015, [(0.55, 0.18, 0.08)]), "early": (0.07, 0.015, [(0.72, 0.16, 0.07)]),
                           "late": (0.04, 0.015, [(0.64, 0.15, 0.08), (0.56, 0.13, 0.08)])}),
    "pear": dict(seg=0.6, depth=6, kids=(2, 3), spread=32, droop=0.0, leaf=0.07, shape="ovate", per_node=6,
                 twig_r=0.013, bark=(0.28, 0.26, 0.24), sm=2.6,
                 leaves={"summer": (1.0, G_DARK, (0.3, G)), "early": (0.9, EARLY, (0.25, RED)), "late": (0.04, BROWN, None)}),
    "oak": dict(seg=0.65, depth=6, kids=(2, 3), spread=58, droop=0.0, leaf=0.085, shape="ovate", per_node=7,
                twig_r=0.016, bark=(0.32, 0.30, 0.27), sm=2.8,
                leaves={"summer": (1.0, G, None), "early": (0.95, G, (0.3, EARLY)), "late": (0.09, BROWN, (0.3, [(0.50, 0.38, 0.22)]))}),
    "wwillow": dict(seg=0.65, depth=6, kids=(2, 3), spread=30, droop=0.45, leaf=0.10, shape="lance", per_node=7,
                    twig_r=0.011, bark=(0.40, 0.34, 0.18), sm=2.8,
                    leaves={"summer": (1.0, G_GREY, None), "early": (0.9, G_GREY, (0.3, EARLY)), "late": (0.06, OLIVE, (0.5, YELLOW))}),
}

# Кущики: висота (м), стебел, ширина кадру (м), колір стебел і листків, верхівка / качан.
REED = {
    # Літо й рання осінь — сіро-оливкові стебла з рудуватою верхівкою, яскравістю як трава поруч.
    # Пізня осінь — солом'яно-буре сухе листя й стебла (не темніші за суху траву берега) і
    # сріблясто-бежева пухнаста верхівка.
    "reed": dict(h=(1.5, 3.0), n=60, w=1.25, leaf_w=0.035, leaf_l=(0.25, 0.45), leaves_per=4,
                 stem={"summer": [(0.52, 0.52, 0.36), (0.47, 0.48, 0.33)], "early": [(0.53, 0.50, 0.32), (0.48, 0.47, 0.30)],
                       "late": [(0.37, 0.31, 0.21), (0.33, 0.28, 0.19), (0.39, 0.34, 0.24)]},
                 leaf={"summer": [(0.49, 0.51, 0.34), (0.55, 0.55, 0.36), (0.44, 0.47, 0.31)],
                       "early": [(0.50, 0.49, 0.30), (0.55, 0.53, 0.32), (0.46, 0.46, 0.28)],
                       "late": [(0.37, 0.31, 0.22), (0.31, 0.27, 0.20), (0.41, 0.35, 0.25), (0.27, 0.24, 0.20)]},
                 # Верхівка очерету: 25–40 см, пізнього літа буро-фіолетова, восени пухнаста сіро-біла.
                 head="plume", head_l=(0.25, 0.4),
                 head_c={"summer": [(0.60, 0.42, 0.28), (0.56, 0.39, 0.27)], "early": [(0.60, 0.44, 0.30), (0.56, 0.41, 0.28)],
                         "late": [(0.50, 0.47, 0.42), (0.45, 0.42, 0.37)]}),
    # Рогіз — передусім довге дугасте листя від землі; качан лише на частині стебел (head_p).
    "cattail": dict(h=(1.2, 2.0), n=40, w=1.1, leaf_w=0.03, leaf_l=(0.9, 1.6), leaves_per=0,
                    stem={"summer": [(0.49, 0.51, 0.34)], "early": [(0.50, 0.49, 0.30)], "late": [(0.45, 0.38, 0.25)]},
                    leaf={"summer": [(0.49, 0.51, 0.34), (0.55, 0.55, 0.36), (0.44, 0.47, 0.31)],
                          "early": [(0.50, 0.49, 0.30), (0.55, 0.53, 0.32), (0.46, 0.46, 0.28)],
                          "late": [(0.37, 0.30, 0.19), (0.32, 0.26, 0.18), (0.40, 0.33, 0.22), (0.28, 0.24, 0.18)]},
                    # Качан рогозу: 18–22 см завдовжки, бурий (не чорний), веретеном; намальований 7 см
                    # завтовшки замість справжніх 2,5: тонший на найближчому зумі менший за піксель, а
                    # товщий читається цеглиною.
                    head="spike", head_l=(0.18, 0.22), head_p=0.45,
                    head_c={"summer": [(0.45, 0.30, 0.18)], "early": [(0.45, 0.30, 0.18)], "late": [(0.36, 0.26, 0.17)]}),
}
# Рендер кущика в SHEAF_SS разів більший за клітинку атласу; атлас зменшує його (Lanczos), і край
# тонкого стебла виходить м'якою альфою, а не сходинками.
SHEAF_SS = 4

_mats = {}


def mat(rgb):
    key = tuple(round(c, 3) for c in rgb)
    if key not in _mats:
        m = bpy.data.materials.new("m%d" % len(_mats))
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*[c ** 2.2 for c in rgb], 1)
        b.inputs["Roughness"].default_value = 0.9
        _mats[key] = m
    return _mats[key]


def add_obj(name, bm, faces_col):
    """Одна сітка, матеріал на грань — з faces_col (індекс у списку кольорів)."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    cols = []
    for c in faces_col:
        if c not in cols:
            cols.append(c)
    for c in cols:
        ob.data.materials.append(mat(c))
    for p, c in zip(me.polygons, faces_col):
        p.material_index = cols.index(c)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def clear():
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o)


# ---------------------------------------------------------------- пучки крони

def build_twig(seed):
    P = K[KIND]
    keep, pal, mix = P["leaves"][SEASON]
    fruit = P.get("fruit", {}).get(SEASON)
    rng = random.Random(seed)
    clear()
    sm = P["sm"] / 2.4  # пропорції гілки під розмір кадру
    leafy = keep > 0.5
    leaf_levels = 3 if leafy else 2
    per_node = round(P["per_node"] * (2.2 if leafy else 1.0))
    leaf_m = P["leaf"] * 0.75
    scatter = (0.07 if leafy else 0.04) * sm
    # Голий пучок — темний каркас гілочок: тонкі світло-сірі гілочки на далеких mip
    # розпливались рожевою імлою, тож без листя вони товщі й темніші.
    twig_r = P["twig_r"] * (1.0 if leafy else 1.7)
    # Голі гілочки сіро-бурі, приглушені: жовтуваті гілки верби читались залишками листя.
    grey = sum(P["bark"]) / 3
    bark = P["bark"] if leafy else tuple((grey + (c - grey) * 0.3) * 0.55 for c in P["bark"])
    bm = bmesh.new()
    leaves, fruits = [], []

    def colour():
        if mix and rng.random() < mix[0]:
            return rng.choice(mix[1])
        return rng.choice(pal)

    def grow(p, d, length, radius, level):
        d = (d + Vector((0, 0, -P["droop"] * (1 - level / P["depth"])))).normalized()
        e = p + d * length
        bmesh.ops.create_cone(bm, cap_ends=False, segments=4, radius1=radius, radius2=radius * 0.75, depth=length,
                              matrix=Matrix.Translation((p + e) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4())
        if level >= P["depth"] - leaf_levels:
            for _ in range(per_node):
                if rng.random() > keep:
                    continue
                q = p + (e - p) * rng.random() + Vector([rng.gauss(0, scatter) for _ in range(3)])
                leaves.append((q, colour()))
            if fruit and rng.random() < fruit[0] * 3:
                # Ягоди гронами (глід і шипшина — по 5–15 ягід 1–1,5 см): поодинока ягода менша за піксель, гроно читається точкою.
                fc0 = rng.choice(fruit[2])
                for _ in range(rng.randint(5, 15) if fruit[1] < 0.02 else (rng.randint(3, 5) if fruit[1] < 0.06 else 1)):
                    fruits.append((e + Vector([rng.gauss(0, 0.025) for _ in range(3)]), fc0))
        if level == P["depth"]:
            return
        k = rng.randint(*P["kids"])
        for i in range(k):
            ax = d.orthogonal().normalized()
            rot = Matrix.Rotation(2 * math.pi * i / k + rng.uniform(-0.5, 0.5), 3, d)
            tilt = Matrix.Rotation(math.radians(P["spread"] * rng.uniform(0.6, 1.2)), 3, rot @ ax)
            nd = ((tilt @ d).normalized() + Vector((0, 0, 0.25))).normalized()
            grow(e, nd, length * rng.uniform(0.62, 0.78), max(radius * 0.68, twig_r * 0.5), level + 1)

    a0 = rng.uniform(0, 2 * math.pi)
    for j in range(2):
        a = a0 + j * rng.uniform(1.6, 2.6)
        start = Vector((math.cos(a), math.sin(a), 0)) * 1.45 * sm + Vector((0, 0, -0.4 * sm))
        d = (-start + Vector((0, 0, 0.9 * sm))).normalized()
        grow(start, d, P["seg"] * rng.uniform(0.85, 1.1), twig_r * 2.5, 0)
    # Голе гілля — сіро-бура мережа з розкидом тону, а не однотонні палички.
    tones = [bark] if leafy else [tuple(c * k for c in bark) for k in (0.75, 1.0, 1.3)]
    add_obj("twig", bm, [rng.choice(tones) for _ in range(len(bm.faces))])

    lb = bmesh.new()
    fc = []
    if P["shape"] == "lance":
        pts = [Vector((0, -0.5, 0)), Vector((0.09, -0.15, 0)), Vector((0.07, 0.25, 0)), Vector((0, 0.5, 0)), Vector((-0.07, 0.25, 0)), Vector((-0.09, -0.15, 0))]
    elif P["shape"] == "scale":
        # Туя: пласкі віялові гілочки, повернуті здебільшого боком, щільні.
        pts = [Vector((0, -0.5, 0)), Vector((0.4, -0.1, 0)), Vector((0.45, 0.3, 0)), Vector((0, 0.5, 0)), Vector((-0.45, 0.3, 0)), Vector((-0.4, -0.1, 0))]
    else:
        pts = [Vector((0, -0.5, 0)), Vector((0.3, -0.1, 0)), Vector((0.22, 0.35, 0)), Vector((0, 0.5, 0)), Vector((-0.22, 0.35, 0)), Vector((-0.3, -0.1, 0))]
    up = 0.25 if P["shape"] == "scale" else 1.0
    for q, c in leaves:
        s = leaf_m * rng.uniform(0.8, 1.2)
        n = Vector((rng.gauss(0, 0.5), rng.gauss(0, 0.5), up)).normalized()
        r = n.to_track_quat("Z", "Y").to_matrix() @ Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z")
        lb.faces.new([lb.verts.new(q + r @ (p * s)) for p in pts])
        fc.append(c)
    for q, c in fruits:
        bmesh.ops.create_icosphere(lb, subdivisions=1, radius=fruit[1] / 2, matrix=Matrix.Translation(q))
        fc.extend([c] * (len(lb.faces) - len(fc)))
    if lb.faces:
        add_obj("leaves", lb, fc)
    else:
        lb.free()
    return len(leaves)


# ---------------------------------------------------------------- кущики очерету й рогозу

def blade(bm, base, d, length, width, droop, fc, c):
    """Стрічка листка: 5 відрізків, звужується до кінця, кінець опускається."""
    side = d.cross(Vector((0, 0, 1)))
    side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
    prev = None
    p = base.copy()
    dd = d.copy()
    for i in range(6):
        t = i / 5
        w = width * (1 - t) * (0.5 if i == 0 else 1) + 0.002
        pair = (bm.verts.new(p - side * w / 2), bm.verts.new(p + side * w / 2))
        if prev:
            bm.faces.new((prev[0], prev[1], pair[1], pair[0]))
            fc.append(c)
        prev = pair
        dd = (dd + Vector((0, 0, -droop))).normalized()
        p = p + dd * length / 5


def build_sheaf(seed):
    R = REED[KIND]
    rng = random.Random(seed)
    clear()
    bm = bmesh.new()
    fc = []
    # Стебла купками з просвітами між ними: рівномірна стіна стебел на mip ставала смугою.
    groups = [rng.uniform(-R["w"] * 0.38, R["w"] * 0.38) for _ in range(5)]
    for _ in range(R["n"]):
        x = rng.choice(groups) + rng.gauss(0, R["w"] * 0.035)
        y = rng.uniform(-0.25, 0.25)
        # Куполом: до краю кущика стебла нижчі, і висота кожного рвана — верх не рівна лінія.
        dome = 1.0 - 0.45 * min((x / (R["w"] * 0.5)) ** 2, 1.0)
        h = R["h"][1] * dome * rng.uniform(0.55, 1.0)
        lean = Vector((rng.gauss(0, 0.09) + x * 0.12, rng.gauss(0, 0.05), 1.0)).normalized()
        base = Vector((x, y, -0.05))
        top = base + lean * h
        sc = rng.choice(R["stem"][SEASON])
        # Стебло: чотиригранна трубка, звужена до вістря; намальована 2–3 см замість справжніх
        # 7–9 мм — тонше на найближчому зумі менше за піксель.
        bmesh.ops.create_cone(bm, cap_ends=False, segments=4, radius1=0.014, radius2=0.004, depth=h,
                              matrix=Matrix.Translation((base + top) / 2) @ lean.to_track_quat("Z", "Y").to_matrix().to_4x4())
        fc.extend([sc] * (len(bm.faces) - len(fc)))
        if R["leaves_per"]:
            # Очерет: сухі листки відходять від стебла під 35–70° і звисають кінцями — косі риски
            # ламають ряд вертикалей.
            for k in range(R["leaves_per"]):
                t = 0.1 + 0.75 * (k + rng.random() * 0.5) / R["leaves_per"]
                a = rng.uniform(0, 2 * math.pi)
                d = Vector((math.cos(a), math.sin(a) * 0.5, rng.uniform(0.4, 1.4))).normalized()
                blade(bm, base + lean * h * t, d, rng.uniform(*R["leaf_l"]), R["leaf_w"], rng.uniform(0.08, 0.25), fc,
                      rng.choice(R["leaf"][SEASON]))
        else:
            # Рогіз: два листки від землі, довгі, дугою назовні.
            for k in range(2):
                a = rng.uniform(0, 2 * math.pi)
                d = Vector((math.cos(a) * 0.45, math.sin(a) * 0.2, 1.0)).normalized()
                blade(bm, base + Vector((rng.gauss(0, 0.04), 0, 0)), d, rng.uniform(0.5, 0.9) * h, R["leaf_w"],
                      rng.uniform(0.02, 0.09), fc, rng.choice(R["leaf"][SEASON]))
        hl = rng.uniform(*R["head_l"])
        hc = rng.choice(R["head_c"][SEASON])
        if R["head"] == "plume":
            if rng.random() < 0.85:
                # Верхівка: віяло тонких гілочок, що схиляються на один бік.
                side = rng.choice((-1, 1))
                # Верхівка — розпушене віяло тонких нитей різної довжини: широкі стрічки зливалися в
                # круглі грудки. Нитки тонші, їх більше, розкид кутів ширший, кінці звисають.
                for k in range(30):
                    d = Vector((side * rng.uniform(0.1, 1.0), rng.gauss(0, 0.35), rng.uniform(0.1, 1.0))).normalized()
                    blade(bm, top - lean * hl * rng.uniform(0.0, 0.8), d, hl * rng.uniform(0.35, 0.95),
                          0.03 if SEASON == "late" else 0.025, rng.uniform(0.1, 0.3), fc, hc)
        elif rng.random() < R["head_p"]:
            # Веретено зі звуженими кінцями, а не циліндр із пласкими торцями.
            c0 = top - lean * (0.12 + hl / 2)
            for z0, r0, r1 in ((-hl / 4, 0.022, 0.035), (hl / 4, 0.035, 0.018)):
                bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=r0, radius2=r1, depth=hl / 2,
                                      matrix=Matrix.Translation(c0 + lean * z0) @ lean.to_track_quat("Z", "Y").to_matrix().to_4x4())
            fc.extend([hc] * (len(bm.faces) - len(fc)))
    add_obj("sheaf", bm, fc)
    return R["n"]


def render():
    sc = bpy.context.scene
    out = os.path.join(OUT, "%s_%s" % (KIND, SEASON))
    os.makedirs(out, exist_ok=True)
    if KIND in REED:
        R = REED[KIND]
        # Верхівка стирчить над стеблом, тож кадр очерету вищий на її довжину, щоб межа кадру не зрізала
        # її прямою. Качан рогозу сидить нижче вістря — йому запас не потрібен.
        h = R["h"][1] + (R["head_l"][1] if R["head"] == "plume" else 0.0) + 0.1
        # Вертикальний кадр 1:2; низ кадру — земля (z = −0.05 за кадром).
        sc.render.resolution_x, sc.render.resolution_y = 128 * SHEAF_SS, 256 * SHEAF_SS
        cam.data.ortho_scale = h
        for i in range(N):
            n = build_sheaf(SEED * 100 + i)
            cl.aim(cam, (0, 0, h / 2 - 0.05), (0, 1, 0), 30)
            sc.render.filepath = os.path.join(out, "sprite_%02d.png" % i)
            bpy.ops.render.render(write_still=True)
            print("SPRITE", KIND, SEASON, i, "stems", n)
        return
    sm = K[KIND]["sm"]
    sc.render.resolution_x = sc.render.resolution_y = cl.SPRITE_RES
    cam.data.ortho_scale = sm
    for i in range(N):
        n = build_twig(SEED * 100 + i)
        d = (0, 0, -1) if i % 2 == 0 else (0.0, 0.707, -0.707)
        cl.aim(cam, (0, 0, 0.1), d, 30)
        sc.render.filepath = os.path.join(out, "sprite_%02d.png" % i)
        bpy.ops.render.render(write_still=True)
        print("SPRITE", KIND, SEASON, i, "leaves", n)


bpy.ops.wm.read_factory_settings(use_empty=True)
cam = cl.setup_render(samples=48)
cam.data.clip_start = 1.0
cam.data.clip_end = 100.0
render()
