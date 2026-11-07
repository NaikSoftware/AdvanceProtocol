"""Stage 1: source GLB -> work.blend with `hi` (bake source) and `lo` (game body), MODEL frame.

    blender --background --factory-startup --python prep.py -- <unit>

hi: the source oriented, scaled and grounded, running gear cut away, barrel stretched so the
muzzle lands on the spec. lo: hi minus gear, barrel, belly and loose detail islands, decimated to
cfg body_tris, a lathe barrel built from the measured profile, unwrapped into the body region of
the atlas. Gear and panels are added later (assemble.py) because they are not baked.
"""
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

cfg = lib.load(sys.argv[sys.argv.index("--") + 1])
k = cfg["k"]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=cfg["source"])
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)
meshes = list(bpy.data.objects)
for o in meshes:
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
hi.name = "hi"
me = hi.data


def verts(m):
    co = np.empty(len(m.vertices) * 3); m.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


co = verts(me)
zmin = co[:, 2].min()
lc = cfg["long_c"]
if cfg["fwd"] == "x":   # long = x, lat = y; turn +X onto +Y
    M = Matrix(((0, -k, 0, 0), (k, 0, 0, -lc * k), (0, 0, k, -zmin * k), (0, 0, 0, 1)))
else:                   # long = y already
    M = Matrix(((k, 0, 0, 0), (0, k, 0, -lc * k), (0, 0, k, -zmin * k), (0, 0, 0, 1)))
me.transform(M)
me.update()
print(f"PREP scale k={k:.4f} long_c={lc:.4f} zmin={zmin:.4f}")


def delete_faces(obj, mask):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(mask)[0]], context='FACES')
    bm.to_mesh(obj.data); bm.free(); obj.data.update()


def face_src(obj):
    """Face centres and normals, with centres in SOURCE terms (long, |lat|, h)."""
    n = len(obj.data.polygons)
    c = np.empty(n * 3); obj.data.polygons.foreach_get("center", c); c = c.reshape(-1, 3)
    nr = np.empty(n * 3); obj.data.polygons.foreach_get("normal", nr); nr = nr.reshape(-1, 3)
    return c[:, 1] / k + lc, np.abs(c[:, 0]) / k, c[:, 2] / k, c, nr


# Running gear: everything in the track zone below the skirt, what hides behind the skirt, and
# the open ends (sprocket, idler) where no skirt covers it.
cut = cfg["cut"]
lng, lat, h, _, _ = face_src(hi)
zone = (lat >= cut["lat"][0]) & (lat < cut["lat"][1])
gear = (zone & (h < cut["below_skirt_h"])) \
    | ((lat >= cut["lat"][0]) & (lat < cut["behind_skirt_lat"]) & (h < cut["gear_top_h"])) \
    | (zone & (h < cut["gear_top_h"]) & ((lng < cut["open_ends_long"][0]) | (lng > cut["open_ends_long"][1])))
print(f"PREP gear faces cut: {gear.sum()} of {len(gear)}")
delete_faces(hi, gear)

# Barrel: stretch along +Y from the mantlet so the muzzle sits at the spec length.
gun = cfg["gun"]
y0 = lib.m_long(cfg, gun["start_long"])
az = lib.m_len(cfg, gun["axis_h"])
co = verts(me)
r = np.hypot(co[:, 0], co[:, 2] - az)
sel = (co[:, 1] > y0) & (r < lib.m_len(cfg, gun["clear_r"]))
tip = co[sel, 1].max()
f = (cfg["spec"]["barrel"] - y0) / (tip - y0)
co[sel, 1] = y0 + (co[sel, 1] - y0) * f
me.vertices.foreach_set("co", co.ravel()); me.update()
print(f"PREP barrel: source tip {tip:.4f} -> {cfg['spec']['barrel']:.4f} (stretch {f:.3f}), axis height {az:.4f}")

# ---- lo -------------------------------------------------------------------------------------
# The battle camera sees tops and outward walls only, and a decimated generated mesh warps
# every plane, so lo is a heightfield of hi seen from above: a ray-cast grid with vertical walls
# down to each edge column's underside (skirt bottom, nose), then planar dissolve and collapse.
src = hi.copy(); src.data = hi.data.copy(); bpy.context.collection.objects.link(src)
lng, lat, h, c, nr = face_src(src)
delete_faces(src, (c[:, 1] > y0) & (np.hypot(c[:, 0], c[:, 2] - az) < lib.m_len(cfg, gun["clear_r"])))
from mathutils.bvhtree import BVHTree
from mathutils import Vector
bvh = BVHTree.FromObject(src, bpy.context.evaluated_depsgraph_get())
g = cfg.get("grid", 0.003)
hx = cfg["spec"]["hull"][0] / 2 + 0.01
co = verts(src.data)
ys = np.arange(co[:, 1].min() - g, co[:, 1].max() + g, g)
xs = np.arange(-hx, hx + g / 2, g)
top = np.full((len(ys), len(xs)), np.nan); bot = np.full_like(top, np.nan)
for j, y in enumerate(ys):
    for i, x in enumerate(xs):
        p = bvh.ray_cast(Vector((x, y, 5.0)), Vector((0, 0, -1)))[0]
        if p is not None:
            top[j, i] = p.z
            q = bvh.ray_cast(Vector((x, y, -1.0)), Vector((0, 0, 1)))[0]
            bot[j, i] = q.z if q is not None else p.z
bpy.data.objects.remove(src)
hit = ~np.isnan(top)


def window(a, r, fill):
    p = np.pad(a, r, constant_values=fill)
    return np.stack([p[u:u + a.shape[0], v:v + a.shape[1]] for u in range(2 * r + 1) for v in range(2 * r + 1)])


# Opening (erode, dilate) drops cables, rails and antennas sticking out of the footprint;
# a 5x5 median does the same on top of it. Both act below ~5 cm, which is texture-scale here.
R = cfg.get("median_cells", 2)
O = cfg.get("open_cells", 1)
hit = window(window(hit, O, False).all(0), O, False).any(0)
top = np.where(hit, np.median(window(np.where(hit, top, -1.0), R, -1.0), 0), np.nan)
bot = np.where(hit, np.median(window(np.where(hit, np.nan_to_num(bot, nan=0.0), 0.0), R, 0.0), 0), np.nan)
hit &= top > 0.0
bm = bmesh.new()
vid = {}
for j, i in zip(*np.nonzero(hit)):
    vid[j, i] = bm.verts.new((xs[i], ys[j], top[j, i]))
for j, i in zip(*np.nonzero(hit[:-1, :-1] & hit[1:, :-1] & hit[:-1, 1:] & hit[1:, 1:])):
    a, b, cc, d = vid[j, i], vid[j, i + 1], vid[j + 1, i + 1], vid[j + 1, i]
    # split along the diagonal with the smaller height step so cliffs stay straight
    if abs(a.co.z - cc.co.z) <= abs(b.co.z - d.co.z):
        bm.faces.new((a, b, cc)); bm.faces.new((a, cc, d))
    else:
        bm.faces.new((a, b, d)); bm.faces.new((b, cc, d))
bm.verts.ensure_lookup_table()
edges = [e for e in bm.edges if e.is_boundary]
ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
for v in ret["geom"]:
    if isinstance(v, bmesh.types.BMVert):
        # the new vertex sits where its source was; find the cell and drop it to that column's underside
        jj, ii = int(round((v.co.y - ys[0]) / g)), int(round((v.co.x - xs[0]) / g))
        v.co.z = min(bot[jj, ii], v.co.z)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
lo_me = bpy.data.meshes.new("lo"); bm.to_mesh(lo_me); bm.free()
lo = bpy.data.objects.new("lo", lo_me); bpy.context.collection.objects.link(lo)
bpy.ops.object.select_all(action='DESELECT')
lo.select_set(True); bpy.context.view_layer.objects.active = lo
n0 = len(lo_me.polygons)
mod = lo.modifiers.new("p", 'DECIMATE'); mod.decimate_type = 'DISSOLVE'; mod.angle_limit = math.radians(1.0)
bpy.ops.object.modifier_apply(modifier="p")
mod = lo.modifiers.new("t", 'TRIANGULATE'); bpy.ops.object.modifier_apply(modifier="t")
target = cfg["body_tris"]
mod = lo.modifiers.new("dec", 'DECIMATE'); mod.ratio = min(1.0, target / len(lo.data.polygons))
mod.use_symmetry = True; mod.symmetry_axis = 'X'
bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.dissolve_degenerate(threshold=1e-5)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
print(f"PREP lo body tris {len(lo.data.polygons)} (heightfield {top.shape}, {n0} faces)")

# Lathe barrel from the measured profile, stretched the same way as hi.
prof = []
for L, R in gun["profile"]:
    y = lib.m_long(cfg, L)
    prof.append((y0 + (y - y0) * f if L > gun["start_long"] else y, lib.m_len(cfg, R)))
n = gun["sides"]
bm = bmesh.new()
rings = []
for y, rr in prof:
    rings.append([bm.verts.new((rr * math.cos(2 * math.pi * i / n), y, az + rr * math.sin(2 * math.pi * i / n)))
                  for i in range(n)])
# muzzle: a lip, then the bore recessed a few cm so it reads dark
yt, rt = prof[-1]
rings.append([bm.verts.new((rt * 0.55 * math.cos(2 * math.pi * i / n), yt, az + rt * 0.55 * math.sin(2 * math.pi * i / n))) for i in range(n)])
rings.append([bm.verts.new((rt * 0.55 * math.cos(2 * math.pi * i / n), yt - 0.01, az + rt * 0.55 * math.sin(2 * math.pi * i / n))) for i in range(n)])
for a, b in zip(rings[:-1], rings[1:]):
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
bm.faces.new(list(reversed(rings[-1])))
bmr = bpy.data.meshes.new("barrel"); bm.to_mesh(bmr); bm.free()
bo = bpy.data.objects.new("barrel", bmr); bpy.context.collection.objects.link(bo)
bpy.ops.object.select_all(action='DESELECT')
bo.select_set(True); bpy.context.view_layer.objects.active = bo
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode='OBJECT')
lo.select_set(True); bpy.context.view_layer.objects.active = lo
bpy.ops.object.join()
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))

# Unwrap into the body region: left of the gear column, below the tread strip.
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003, area_weight=0.0,
                         correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')
uv = lo.data.uv_layers.active.data
a = np.empty(len(uv) * 2); uv.foreach_get("uv", a); a = a.reshape(-1, 2)
pad = 2.0 / lib.ATLAS
a[:, 0] = a[:, 0] * (lib.COL_U - 2 * pad) + pad
a[:, 1] = a[:, 1] * (1.0 - lib.STRIP - 2 * pad) + pad
uv.foreach_set("uv", a.ravel())
lo.data.uv_layers.active.name = "UVMap"

tris = sum(len(p.vertices) - 2 for p in lo.data.polygons)
print(f"PREP lo tris {tris}")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(cfg["work"], "work.blend"))
bpy.ops.object.select_all(action='DESELECT'); lo.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(cfg["work"], "lo_raw.glb"), use_selection=True,
                          export_apply=True, export_materials='NONE')
