"""Спрайти пучків сосни з гілочок Poly Haven pine_tree_01 (CC0): pine_tree_01_twig_a..g_LOD1.

Запуск:
  blender -b --factory-startup -P src_pine_tufts.py -- <pine_tree_01_1k.blend> <вихід> [спрайтів=10]
Пише <вихід>/pine_tufts/sprite_NN.png. Кожен спрайт — 6–9 гілочок по 0,3–0,7 м, розкладених
віялом від спільного центру, як пагони на кінці соснової гілки: згори хвоя читається
променями. Пучок, вирізаний шаром зі всієї крони, давав пласку лапату масу, схожу на листя.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crown_lib as cl  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
LIB, OUT = argv[:2]
N = int(argv[2]) if len(argv) > 2 else 10
NAMES = ["pine_tree_01_twig_%s_LOD1" % c for c in "abcdefg"]

bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(LIB, link=False) as (src, dst):
    dst.objects = [n for n in NAMES if n in src.objects]
protos = []
for ob in dst.objects:
    me = ob.data
    # Основа гілочки — у початок координат: вона росте від центру пучка назовні.
    lo = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), 0))
    for v in me.vertices:
        v.co -= Vector((lo.x + (max(w.co.x for w in me.vertices) - lo.x) / 2, lo.y, 0))
    protos.append(me)

cam = cl.setup_render(samples=48)
sc = bpy.context.scene
sc.render.resolution_x = sc.render.resolution_y = 256
cam.data.ortho_scale = 1.3
cam.data.clip_start = 1.0
cam.data.clip_end = 100.0
out = os.path.join(OUT, "pine_tufts")
os.makedirs(out, exist_ok=True)
rng = random.Random(7)
for i in range(N):
    for o in list(sc.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o)
    k = rng.randint(6, 9)
    for j in range(k):
        me = rng.choice(protos)
        o = bpy.data.objects.new("tw", me)
        sc.collection.objects.link(o)
        yaw = 2 * math.pi * j / k + rng.uniform(-0.3, 0.3)
        # Гілочка лежить уздовж +Y; нахил угору 15–40°, поворот навколо осі пучка.
        o.rotation_euler = Euler((math.radians(rng.uniform(15, 40)), 0, yaw - math.pi / 2), "XYZ")
        f = rng.uniform(0.75, 1.05)
        o.scale = (f, f, f)
        o.location = (rng.gauss(0, 0.04), rng.gauss(0, 0.04), rng.gauss(0, 0.03))
    d = (0, 0, -1) if i % 2 == 0 else (0.0, 0.707, -0.707)
    cl.aim(cam, (0, 0, 0.08), d, 30)
    sc.render.filepath = os.path.join(out, "sprite_%02d.png" % i)
    bpy.ops.render.render(write_still=True)
    print("TUFT", i, k)
