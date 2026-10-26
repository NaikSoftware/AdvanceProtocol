"""Бере скани Poly Haven (CC0) з ~/.cache/ap-scratch/buildings/scans, зводить кожен до ~100 трикутників і
записує нормовану геометрію (макс. розмір 1, центр у нулі) у debris_scans.json."""
import json
import os

import bmesh
import bpy

SRC = os.path.expanduser("~/.cache/ap-scratch/buildings/scans")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "debris_scans.json")
NAMES = ["rock_07", "rock_09", "stone_01", "namaqualand_boulder_05", "namaqualand_boulder_06", "namaqualand_rocks_01"]
TARGET = 110

lib = {}
for n in NAMES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, n, n + "_1k.gltf"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(me)
    bm.free()
    tris0 = sum(len(p.vertices) - 2 for p in me.polygons)
    mod = ob.modifiers.new("d", "DECIMATE")
    mod.ratio = min(1.0, TARGET / max(tris0, 1))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    vs = [v.co.copy() for v in bm.verts]
    mn = [min(v[i] for v in vs) for i in range(3)]
    mx = [max(v[i] for v in vs) for i in range(3)]
    s = 1.0 / max(mx[i] - mn[i] for i in range(3))
    cen = [(mn[i] + mx[i]) / 2 for i in range(3)]
    verts = [[round((v[0] - cen[0]) * s, 4), round((v[1] - cen[1]) * s, 4), round((v[2] - cen[2]) * s, 4)] for v in vs]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    lib[n] = {"v": verts, "f": faces}
    print("SCAN", n, "tris", tris0, "->", len(faces))
    bm.free()
json.dump(lib, open(OUT, "w"))
