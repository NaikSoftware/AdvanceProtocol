"""Плоскі шматки землі лісу: просіка, яку проламав танк, і тінь під лісом.

Запуск:
  blender -b --factory-startup -P build_ground.py -- <вихід.glb>
Пише GLB із двома вузлами й одним напівпрозорим матеріалом (alphaMode BLEND):
- Soil_Lane — 1 × 1 тайл на y = 0,01: розрита темна земля (L* ≈ 22) з двома коліями вздовж x,
  краї поперек смуги розмиті; дошка кладе по шматку на проламану клітинку, x — уздовж
  проламу. Без такої смуги просіка серед гілля губилась і на мінімальному зумі.
- Floor_Shade — 1,7 × 1,7 тайла на y = 0,005: м'яка темна пляма під кроною, що виходить
  трохи за край лісу. Без неї ліс висить над травою вирізаною аплікацією.
Обидва — по 2 трикутники. Справжні колії від гусениць малює дошка (карта шрамів); тут
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
    edge = np.clip((0.5 - np.abs(yy - 0.5) - 0.06 * n1) / 0.12, 0, 1)
    soil_a = edge * 0.95
    # Тінь під лісом: темна пляма з м'яким краєм, найтемніша в середині.
    # Плями сусідніх клітинок мають злитися в одну тінь, тож край дуже м'який, а середина
    # пласка й неглибока; на межі квадрата альфа рівно 0, інакше проступає сітка.
    r = np.hypot(xx - 0.5, yy - 0.5) * 2
    shade_a = np.clip((0.97 - r - 0.1 * (n1 - 0.5)) / 0.75, 0, 1) ** 1.2 * 0.55
    shade = np.dstack([np.full_like(r, 0.12), np.full_like(r, 0.13), np.full_like(r, 0.09)])
    img = np.zeros((N, 2 * N, 4))
    img[:, :N, :3], img[:, :N, 3] = soil, soil_a
    img[:, N:, :3], img[:, N:, 3] = shade, shade_a
    return img


def material(img):
    im = bpy.data.images.new("forest_ground", 2 * N, N, alpha=True)
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


def quad(name, size_m, z_m, u0, mat):
    h = size_m / 2 / TILE_M
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-h, -h, z_m / TILE_M), (h, -h, z_m / TILE_M), (h, h, z_m / TILE_M), (-h, h, z_m / TILE_M)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for li, (u, v) in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = (u0 + u * 0.5, v)
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
obs = [quad("Soil_Lane", TILE_M, 0.08, 0.0, mat), quad("Floor_Shade", TILE_M * 1.7, 0.04, 0.5, mat)]
for o in bpy.context.scene.objects:
    o.select_set(o in obs)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=True, export_texcoords=True, export_normals=True,
                          export_cameras=False, export_lights=False)
patch_glb(OUT)
print("GROUND", OUT)
