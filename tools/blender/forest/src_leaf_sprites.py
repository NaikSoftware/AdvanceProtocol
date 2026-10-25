"""Спрайти пучків листяних порід і кущів: процедурна гілка з листками, рендер згори й під 45°.

Запуск:
  blender -b --factory-startup -P src_leaf_sprites.py -- <вихід> <набір> <сезон> [спрайтів=8] [зерно=1]
набір: birch | broad | oak | shrub; сезон: late | summer | early | turned (пожовкла крона
ранньої осені).
Пише <вихід>/<набір>_<сезон>/sprite_NN.png — шматок крони ~2,4 м, як у хвойних
(crown_lib.SPRITE_M). Готових CC0-моделей берези, дуба чи липи немає, а атласи від
генератора мають темний обвід і білий ореол по краю; тут листок і гілка — геометрія,
тож край пучка рваний сам собою, а колір кожного листка задано числом.
Лист 5–12 см на екрані менший за піксель; видно лише маси, у які він збирається на
кінцях пагонів (0,3–1 м) — саме тому листки сидять купками на останніх двох рівнях.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crown_lib as cl  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, KIND, SEASON = argv[:3]
N = int(argv[3]) if len(argv) > 3 else 8
SEED = int(argv[4]) if len(argv) > 4 else 1

# Будова: довжина першого відрізка (м), розгалуження, кут, опускання кінців, листок (м),
# листків на вузол, частка листків, що лишилась (за сезоном), кольори (sRGB).
P = {
    "birch": dict(seg=0.6, depth=6, kids=(2, 3), spread=36, droop=0.35, leaf=0.05, per_node=6, twig_r=0.011),
    "broad": dict(seg=0.65, depth=6, kids=(2, 3), spread=44, droop=0.05, leaf=0.075, per_node=6, twig_r=0.013),
    "oak": dict(seg=0.6, depth=6, kids=(2, 3), spread=55, droop=0.0, leaf=0.085, per_node=7, twig_r=0.015),
    "shrub": dict(seg=0.55, depth=6, kids=(2, 3), spread=40, droop=0.1, leaf=0.07, per_node=6, twig_r=0.011),
}[KIND]
KEEP = {"summer": 1.0, "early": 0.9, "turned": 0.92, "late": {"oak": 0.08, "birch": 0.008}.get(KIND, 0.02)}[SEASON]
BARK = (0.33, 0.30, 0.27) if KIND != "birch" else (0.30, 0.27, 0.25)
GREENS = [(0.20, 0.30, 0.10), (0.24, 0.34, 0.12), (0.17, 0.26, 0.09), (0.28, 0.36, 0.14)]
EARLY = [(0.40, 0.42, 0.16), (0.46, 0.45, 0.17), (0.34, 0.38, 0.15)]
ORANGE = [(0.58, 0.40, 0.14), (0.62, 0.48, 0.16)]
BROWN = [(0.36, 0.25, 0.15), (0.30, 0.21, 0.13), (0.40, 0.29, 0.17)]
YELLOW = [(0.62, 0.52, 0.20), (0.55, 0.47, 0.20)]
TAN = [(0.50, 0.38, 0.22), (0.46, 0.35, 0.20), (0.54, 0.42, 0.25)]


def leaf_colour(rng):
    if SEASON == "summer":
        return rng.choice(GREENS)
    if SEASON == "early":
        return rng.choice(ORANGE) if rng.random() < 0.15 else rng.choice(EARLY)
    if SEASON == "turned":
        # Крона, що вже пожовкла: береза жовта, дуб світло-бурий, з рештками зеленого.
        if rng.random() < 0.15:
            return rng.choice(EARLY)
        return rng.choice(TAN) if KIND == "oak" else rng.choice(YELLOW)
    return rng.choice(BROWN) if KIND in ("oak", "broad", "shrub") else rng.choice(YELLOW)


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[c ** 2.2 for c in rgb], 1)
    b.inputs["Roughness"].default_value = 0.9
    return m


def grow(rng, bm, leaves, p, d, length, radius, level):
    """Пагін: відрізок і 2–3 дочірні; листки купками на двох останніх рівнях."""
    d = (d + Vector((0, 0, -P["droop"] * (1 - level / P["depth"])))).normalized()
    e = p + d * length
    seg = bmesh.ops.create_cone(bm, cap_ends=False, segments=4, radius1=radius, radius2=radius * 0.75,
                                depth=length, matrix=Matrix.Translation((p + e) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4())
    for v in seg["verts"]:
        v[bm.verts.layers.int["kind"]] = 0
    if level >= P["depth"] - 2:
        for _ in range(P["per_node"]):
            if rng.random() > KEEP:
                continue
            t = rng.random()
            q = p + (e - p) * t + Vector([rng.gauss(0, 0.04) for _ in range(3)])
            leaves.append((q, leaf_colour(rng)))
    if level == P["depth"]:
        return
    k = rng.randint(*P["kids"])
    for i in range(k):
        ax = d.orthogonal().normalized()
        rot = Matrix.Rotation(2 * math.pi * i / k + rng.uniform(-0.5, 0.5), 3, d)
        tilt = Matrix.Rotation(math.radians(P["spread"] * rng.uniform(0.6, 1.2)), 3, rot @ ax)
        nd = (tilt @ d).normalized()
        nd = (nd + Vector((0, 0, 0.25))).normalized()  # пагони тягнуться до світла
        grow(rng, bm, leaves, e, nd, length * rng.uniform(0.62, 0.78), max(radius * 0.68, P["twig_r"] * 0.5), level + 1)


def build(seed):
    rng = random.Random(seed)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o)
    bm = bmesh.new()
    bm.verts.layers.int.new("kind")
    leaves = []
    # Гілка входить у кадр від осі дерева, тобто з краю, і розходиться віялом до центру.
    a0 = rng.uniform(0, 2 * math.pi)
    for j in range(2):
        a = a0 + j * rng.uniform(1.6, 2.6)
        # Товстий початок гілки — за краєм кадру: інакше він стирчить із крони сірим сучком.
        start = Vector((math.cos(a), math.sin(a), 0)) * 1.45 + Vector((0, 0, -0.4))
        d = (-start + Vector((0, 0, 0.9))).normalized()
        grow(rng, bm, leaves, start, d, P["seg"] * rng.uniform(0.85, 1.1), P["twig_r"] * 2.5, 0)
    me = bpy.data.meshes.new("twig")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("twig", me)
    ob.data.materials.append(mat("bark", BARK))
    bpy.context.scene.collection.objects.link(ob)
    # Листки — п'ятикутники, повернуті здебільшого лицем угору, як листя до світла.
    lb = bmesh.new()
    cols = {}
    for q, c in leaves:
        s = P["leaf"] * rng.uniform(0.8, 1.2)
        n = Vector((rng.gauss(0, 0.5), rng.gauss(0, 0.5), 1.0)).normalized()
        r = n.to_track_quat("Z", "Y").to_matrix() @ Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z")
        pts = [Vector((0, -0.5, 0)), Vector((0.3, -0.1, 0)), Vector((0.22, 0.35, 0)), Vector((0, 0.5, 0)), Vector((-0.22, 0.35, 0)), Vector((-0.3, -0.1, 0))]
        vs = [lb.verts.new(q + r @ (p * s)) for p in pts]
        f = lb.faces.new(vs)
        f.material_index = cols.setdefault(c, len(cols))
    lme = bpy.data.meshes.new("leaves")
    lb.to_mesh(lme)
    lb.free()
    lo = bpy.data.objects.new("leaves", lme)
    for c, i in sorted(cols.items(), key=lambda kv: kv[1]):
        lo.data.materials.append(mat("leaf%d" % i, c))
    bpy.context.scene.collection.objects.link(lo)
    return len(leaves)


bpy.ops.wm.read_factory_settings(use_empty=True)
cam = cl.setup_render(samples=48)
sc = bpy.context.scene
sc.render.resolution_x = sc.render.resolution_y = cl.SPRITE_RES
cam.data.ortho_scale = cl.SPRITE_M
cam.data.clip_start = 1.0
cam.data.clip_end = 100.0
out = os.path.join(OUT, "%s_%s" % (KIND, SEASON))
os.makedirs(out, exist_ok=True)
for i in range(N):
    n = build(SEED * 100 + i)
    d = (0, 0, -1) if i % 2 == 0 else (0.0, 0.707, -0.707)
    cl.aim(cam, (0, 0, 0.1), d, 30)
    sc.render.filepath = os.path.join(out, "sprite_%02d.png" % i)
    bpy.ops.render.render(write_still=True)
    print("SPRITE", KIND, SEASON, i, "leaves", n)
