"""Низький польовий мур: суцільний, 8 м довжини, 0.9 м висоти, без просвітів.

blender -b --factory-startup -P build_wall.py -- rock_diffuse.jpg out.glb
Текстура — скельний діффуз (CC0), знебарвлений і затемнений, з мохом; без окремої геометрії для каменів
менших за 0.25 м: нерівність дає шум вершин і верхній рядок кладки.
"""
import bpy, bmesh, sys, math, random, json, struct
import numpy as np
from mathutils import Vector

src, dst = sys.argv[sys.argv.index('--') + 1:][:2]
M = 8.0
rng = random.Random(5)
L, T0, T1, H = 8.0 / M, 0.62 / M, 0.5 / M, 0.9 / M

bpy.ops.wm.read_factory_settings(use_empty=True)
# текстура не береться з атласу скелі (там чорні поля): шум + щілини кладки + моховий наліт, 256 px = 2 м
rs = np.random.RandomState(11)
def vnoise(n, k):
    g = rs.rand(k, k).astype(np.float32)
    big = np.kron(g, np.ones((n // k, n // k), dtype=np.float32))
    for _ in range(3):
        big = (big + np.roll(big, 1, 0) + np.roll(big, 1, 1) + np.roll(big, -1, 0) + np.roll(big, -1, 1)) / 5
    return big
N = 256
base = 0.22 + 0.10 * vnoise(N, 16) + 0.05 * vnoise(N, 64)
yy, xx = np.mgrid[0:N, 0:N]
row = (yy // 45)
seam = ((yy % 45) < 3) | (((xx + row * 37) % 90) < 3)
base = np.where(seam, base * 0.45, base)
moss = np.clip(vnoise(N, 8) * 1.6 - 0.55, 0, 1)
rgb = np.stack([base * (1 - 0.25 * moss), base * (1 + 0.12 * moss), base * (1 - 0.35 * moss)], -1)
px = np.ones((N, N, 4), dtype=np.float32); px[..., :3] = np.clip(rgb, 0, 1)
img = bpy.data.images.new('wall_albedo', N, N)
px = px.reshape(-1, 4)
img.pixels.foreach_set(px.ravel())
img.pack()
img.name = 'wall_albedo'

# нормаль зі «висоти» (щілини кладки темні = заглиблення), метод скінченних різниць
hgt = (base * (1 - 0.3 * moss)).astype(np.float32)
gx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 14.0
gy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 14.0
nrm = np.stack([-gx, -gy, np.ones_like(gx)], -1)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
npx = np.ones((N, N, 4), dtype=np.float32); npx[..., :3] = nrm * 0.5 + 0.5
nimg = bpy.data.images.new('wall_normal', N, N, is_data=True)
nimg.colorspace_settings.name = 'Non-Color'
nimg.pixels.foreach_set(npx.reshape(-1, 4).ravel())
print('WALLNORMAL mean', float(npx[..., :3].mean()))
nimg.update(); nimg.pack()

mat = bpy.data.materials.new('wall'); mat.use_nodes = True
bsdf = mat.node_tree.nodes['Principled BSDF']
tex = mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = img
mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
nt_ = mat.node_tree.nodes.new('ShaderNodeTexImage'); nt_.image = nimg
nmn = mat.node_tree.nodes.new('ShaderNodeNormalMap')
mat.node_tree.links.new(nt_.outputs['Color'], nmn.inputs['Color'])
mat.node_tree.links.new(nmn.outputs['Normal'], bsdf.inputs['Normal'])
bsdf.inputs['Roughness'].default_value = 0.9

mesh = bpy.data.meshes.new('wall'); ob = bpy.data.objects.new('wall', mesh)
bpy.context.scene.collection.objects.link(ob); ob.data.materials.append(mat)
bm = bmesh.new()
# тіло: призма, що звужується догори, густо розбита для нерівності
r = bmesh.ops.create_cube(bm, size=1.0)
for v in r['verts']:
    t = T0 if v.co.z < 0 else T1
    v.co = Vector((v.co.x * L, v.co.y * t, (v.co.z + 0.5) * H * 0.82))
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.x - e.verts[1].co.x) > L * 0.5], cuts=15, use_grid_fill=True)
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > H * 0.5], cuts=3, use_grid_fill=True)
for v in bm.verts:
    if v.co.z > 1e-4:
        v.co += Vector((rng.uniform(-1, 1) * 0.01 / M, rng.uniform(-1, 1) * 0.03 / M, rng.uniform(-1, 1) * 0.02 / M))
bm.normal_update()
mid = Vector((0, 0, H * 0.41))
bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.dot(f.calc_center_median() - mid) < 0])
# верхній рядок: нерівні камені впритул, перекриваючи тіло
x = -L / 2 + 0.2 / M
while x < L / 2 - 0.2 / M:
    sx = rng.uniform(0.45, 0.8) / M
    sy = rng.uniform(0.45, 0.6) / M
    sz = rng.uniform(0.16, 0.28) / M
    c = bmesh.ops.create_cube(bm, size=1.0)
    for v in c['verts']:
        v.co = Vector((v.co.x * sx + x + sx / 2, v.co.y * sy + rng.uniform(-0.03, 0.03) / M, v.co.z * sz + H * 0.82 + sz * 0.3 - 0.05 / M))
    bm.normal_update()
    cc = Vector((x + sx / 2, 0, H * 0.82))
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.verts[0] in c['verts'] and f.normal.dot(f.calc_center_median() - Vector((x + sx / 2, 0, H * 0.82 + sz * 0.2))) < 0])
    x += sx * 0.85
# UV: потриплярна проєкція, 1 м = 0.5 UV
uv = bm.loops.layers.uv.new('UVMap')
for f in bm.faces:
    n = f.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    for l in f.loops:
        p = l.vert.co * M * 0.5
        l[uv].uv = (p.y, p.z) if ax == 0 else (p.x, p.z) if ax == 1 else (p.x, p.y)
bm.to_mesh(mesh); bm.free()
bpy.context.view_layer.objects.active = ob; ob.select_set(True)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_apply=True)

dd = open(dst, 'rb').read(); off = 12
while off < len(dd):
    cl, ct = struct.unpack_from('<II', dd, off)
    if ct == 0x4E4F534A:
        g = json.loads(dd[off + 8:off + 8 + cl]); break
    off += 8 + cl
prims = [p for m in g['meshes'] for p in m['primitives']]
lo = [min(g['accessors'][p['attributes']['POSITION']]['min'][i] for p in prims) for i in range(3)]
hi = [max(g['accessors'][p['attributes']['POSITION']]['max'][i] for p in prims) for i in range(3)]
print('WALL tris', sum(g['accessors'][p['indices']]['count'] for p in prims) // 3, 'size', [round(hi[i] - lo[i], 3) for i in range(3)], 'ymin', lo[1])
