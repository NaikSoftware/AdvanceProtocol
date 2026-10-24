"""Рендерить крони сосни й ялини зверху (ортографічно) із карток-гілок Poly Haven CC0.

Запуск:
  blender -b --factory-startup -P render_conifer_crowns.py -- <спрайти> <вихід> [семпли]
Дає <вихід>/crown_{pine_a,pine_b,spruce_a,spruce_b}.png, RGBA 1024x1024 на вікно 8x8 м
(128 px/м); прозорий фон, alpha = покриття. Освітлення похмуре: небо плюс слабке сонце,
тому внутрішні гілки темніші за верхні.
"""
import math
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SPR, OUT = argv[0], argv[1]
SAMPLES = int(argv[2]) if len(argv) > 2 else 48
WINDOW_M = 8.0
RES = 1024


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(path, tint):
    img = bpy.data.images.load(path)
    m = bpy.data.materials.new("twig")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[7].default_value = tint
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.85
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], mix.inputs[6])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    nt.links.new(mix.outputs[2], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.4  # просвіт крізь хвою: глибокі шари не чорніють
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m, img


def card(mat, img, length, base, tilt, yaw, pos):
    """Картка стеблом від початку координат уздовж +Y; нахил навколо X, поворот навколо Z."""
    w = length * img.size[0] / img.size[1]
    bm = bmesh.new()
    v = [bm.verts.new((-w / 2, 0, 0)), bm.verts.new((w / 2, 0, 0)),
         bm.verts.new((w / 2, length, 0)), bm.verts.new((-w / 2, length, 0))]
    f = bm.faces.new(v)
    uv = bm.loops.layers.uv.new()
    for loop, (u, vv) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = (u, vv)
    me = bpy.data.meshes.new("c")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("c", me)
    ob.data.materials.append(mat)
    ob.rotation_euler = Euler((tilt, 0, yaw), "XYZ")
    # Спершу нахил навколо X, потім yaw навколо Z: порядок Euler "XYZ" це робить.
    ob.location = pos
    bpy.context.scene.collection.objects.link(ob)
    return ob


def pine(rng, mats):
    """Плоскувата крона Ø ~6 м: товсті гілки віялом, голки пучками на кінцях."""
    n = 150
    for i in range(n):
        r0 = 1.25 * math.sqrt(rng.uniform(0.0, 1.0))
        yaw = rng.uniform(0, math.tau)
        base = Vector((math.cos(yaw) * r0, math.sin(yaw) * r0, rng.uniform(0, 1.2) + (1.25 - r0) * 0.6))
        m, img = rng.choice(mats)
        length = rng.uniform(1.3, 2.0)
        # +Y картки дивиться назовні: yaw - 90° щоб вісь Y збіглась із радіальним напрямком
        card(m, img, length, 0, rng.uniform(0.05, 0.6), yaw - math.pi / 2, base)


def pine_core(rng, mats):
    for _ in range(14):
        m, img = rng.choice(mats)
        card(m, img, rng.uniform(0.9, 1.4), 0, 0.15, rng.uniform(0, math.tau),
             Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1.0)))


def spruce(rng, mats):
    """Конус Ø ~4 м, вершина вгорі: мутовки з гілками, що звисають донизу."""
    whorls = 16
    for k in range(whorls):
        t = k / (whorls - 1)  # 0 = вершина
        z = 9.0 - 8.0 * t
        reach = 0.4 + 1.9 * t
        cnt = 6 + int(5 * t)
        off = rng.uniform(0, math.tau)
        for j in range(cnt):
            yaw = off + j * math.tau / cnt + rng.uniform(-0.2, 0.2)
            m, img = rng.choice(mats)
            length = reach * rng.uniform(0.9, 1.25) + 0.25
            card(m, img, length, 0, -rng.uniform(0.35, 0.8), yaw - math.pi / 2,
                 Vector((0, 0, z + rng.uniform(-0.2, 0.2))))


def render(path):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.transparent_max_bounces = 128  # багато шарів карток: за замовчуванням 8 дають чорні плями
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = WINDOW_M
    cam.location = (0, 0, 40)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 1.6
    sun.rotation_euler = (math.radians(25), math.radians(15), 0)
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.65, 0.68, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.4
    sc.world = w
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# Темніше й холодніше за літню хвою: пізня осінь, мокро.
JOBS = [("pine_a", "pine", 11), ("pine_b", "pine", 29), ("spruce_a", "fir", 5), ("spruce_b", "fir", 41)]
for name, kind, seed in JOBS:
    clear()
    rng = random.Random(seed)
    files = [f"{SPR}/pine_0.png", f"{SPR}/pine_1.png"] if kind == "pine" else [
        f"{SPR}/fir_{i}.png" for i in range(4)]
    tint = (0.62, 0.68, 0.62, 1) if kind == "pine" else (0.5, 0.58, 0.5, 1)
    mats = [material(f, tint) for f in files]
    (pine if kind == "pine" else spruce)(rng, mats)
    if kind == "pine":
        pine_core(rng, mats)
    render(f"{OUT}/crown_{name}.png")
    print("rendered", name)
