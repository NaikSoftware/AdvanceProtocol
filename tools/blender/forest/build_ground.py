"""Плоский шматок землі лісу: просіка, яку проламав танк.

Запуск:
  blender -b --factory-startup -P build_ground.py -- <вихід.glb>
Пише GLB з одним вузлом і одним напівпрозорим матеріалом (alphaMode BLEND):
- Soil_Lane — 1,3 × 1,3 тайла на y = 0,01: розрита темна земля (L* ≈ 22) з двома коліями
  вздовж x; край поперек смуги рваний і гуляє на ±0,25 тайла, кінці вздовж x тануть, тож
  сусідні шматки перекриваються без шва. Дошка кладе по шматку на проламану клітинку, x —
  уздовж проламу. Без такої смуги просіка серед гілля губилась і на мінімальному зумі.
2 трикутники. Справжні колії від гусениць малює дошка (карта шрамів); тут
лише земля самої просіки.
"""
import json
import math
import struct
import sys

import bpy
import numpy as np

OUT = sys.argv[sys.argv.index("--") + 1]
TILE_M = 8.0
N = 256


def noise(rng, n, cells):
    g = rng.random((cells + 1, cells + 1))
    x = np.linspace(0, cells, n, endpoint=False)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    a = g[i][:, i] * (1 - f)[None, :] + g[i][:, i + 1] * f[None, :]
    b = g[i + 1][:, i] * (1 - f)[None, :] + g[i + 1][:, i + 1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def textures():
    rng = np.random.default_rng(5)
    yy, xx = (np.mgrid[0:N, 0:N] + 0.5) / N
    n1 = noise(rng, N, 8) * 0.6 + noise(rng, N, 32) * 0.4
    # Просіка: темна земля, дві вологі колії, край поперек смуги рваний і м'який.
    soil = np.dstack([0.24 + 0.08 * n1, 0.19 + 0.06 * n1, 0.15 + 0.05 * n1])
    for c in (0.33, 0.67):
        rut = np.exp(-((yy - c - 0.02 * (n1 - 0.5)) / 0.045) ** 2)
        soil *= (1 - 0.45 * rut)[..., None]
    # Край просіки рваний і м'який: межа поперек смуги гуляє на ±0,2 ширини квадрата
    # (±0,25 тайла при 1,3 тайла), а кінці вздовж смуги тануть — сусідні шматки
    # перекриваються, і ніде не лишається прямої лінії по межі клітинки.
    n2 = noise(rng, N, 4)
    half = 0.32 + 0.2 * (n2 - 0.5) + 0.06 * (n1 - 0.5)
    edge = np.clip((half - np.abs(yy - 0.5)) / 0.1, 0, 1)
    ends = np.clip((0.5 - np.abs(xx - 0.5) - 0.06 * (n1 - 0.5)) / 0.18, 0, 1)
    soil_a = edge * ends * 0.95
    img = np.zeros((N, N, 4))
    img[..., :3], img[..., 3] = soil, soil_a
    return img


def material(img):
    im = bpy.data.images.new("forest_ground", N, N, alpha=True)
    # Blender зберігає пікселі знизу вгору; 8-бітне зображення бере значення як є, у sRGB.
    px = img[::-1]
    im.pixels.foreach_set(px.astype(np.float32).ravel())
    im.filepath_raw = "//forest_ground.png"
    im.file_format = "PNG"
    im.pack()
    m = bpy.data.materials.new("forest_ground")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = im
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def quad(name, size_m, z_m, mat):
    h = size_m / 2 / TILE_M
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-h, -h, z_m / TILE_M), (h, -h, z_m / TILE_M), (h, h, z_m / TILE_M), (-h, h, z_m / TILE_M)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for li, (u, v) in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u, v)
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def patch_glb(path):
    data = open(path, "rb").read()
    jl, jt = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + jl])
    for m in js["materials"]:
        m["alphaMode"] = "BLEND"
        m["doubleSided"] = False
        pbr = m.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        m.pop("extensions", None)
    nj = json.dumps(js, separators=(",", ":")).encode()
    nj += b" " * (-len(nj) % 4)
    rest = data[20 + jl:]
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(nj) + len(rest)) + struct.pack("<II", len(nj), jt) + nj + rest
    open(path, "wb").write(out)


bpy.ops.wm.read_factory_settings(use_empty=True)
mat = material(textures())
obs = [quad("Soil_Lane", TILE_M * 1.3, 0.08, mat)]
for o in bpy.context.scene.objects:
    o.select_set(o in obs)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=True, export_texcoords=True, export_normals=True,
                          export_cameras=False, export_lights=False)
patch_glb(OUT)
print("GROUND", OUT)
