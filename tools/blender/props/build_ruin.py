"""Руїна з геометрії готового будинку: стіни зрізані до 2.5 м, обвал усередині, завал навколо.

blender -b --factory-startup -P build_ruin.py -- house.glb out.glb brick=<dir> rubble=<dir> sheet=<dir> [seed=1 apron=3 chimney=4.5 sheets=5]
<dir> — розпакований ambientCG 1K-JPG (CC0): <name>/<name>_1K-JPG_Color.jpg і _NormalGL.jpg.
Три матеріали: цегла (стіни, димар), скан щебеню (купи й уламки), гофролист. Текстури знебарвлені й
притемнені до chroma <= ~8, розгорнуті за світовими координатами (1 UV = 1.2 м), нормалі зі скану.
Одна купа — 7-11 уламків по <= 20 трикутників, різний поворот і розмір.
"""
import bpy, bmesh, sys, math, random, json, struct, os
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index('--') + 1:]
src, dst = a[0], a[1]
o = dict(x.split('=', 1) for x in a[2:])
M = 8.0
rng = random.Random(int(o.get('seed', 1)))
CUT = float(o.get('cut', 2.5)) / M
APRON = float(o.get('apron', 3.0)) / M
TILE = 7.6 / M
UVM = 1.2  # метрів на одиницю UV

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = [x for x in bpy.data.objects if x.type == 'MESH'][0]

def make_mat(name, d, value, sat):
    base = os.path.basename(d.rstrip('/'))
    col = bpy.data.images.load(f'{d}/{base}_1K-JPG_Color.jpg')
    nor = bpy.data.images.load(f'{d}/{base}_1K-JPG_NormalGL.jpg')
    nor.colorspace_settings.name = 'Non-Color'
    import numpy as np
    for im in (col, nor):
        im.scale(512, 512)
    px = np.array(col.pixels[:], dtype=np.float32).reshape(-1, 4)
    lum = (0.3 * px[:, 0] + 0.59 * px[:, 1] + 0.11 * px[:, 2])[:, None]
    px[:, :3] = (lum + (px[:, :3] - lum) * sat) * value
    col.pixels.foreach_set(px.ravel())
    col.pack(); nor.pack()
    col.name = name + '_albedo'; nor.name = name + '_normal'
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    t1 = nt.nodes.new('ShaderNodeTexImage'); t1.image = col
    t2 = nt.nodes.new('ShaderNodeTexImage'); t2.image = nor
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(t1.outputs['Color'], b.inputs['Base Color'])
    nt.links.new(t2.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    b.inputs['Roughness'].default_value = 0.9
    b.inputs['Metallic'].default_value = 0.0
    return m

mats = [make_mat('ruin_brick', o['brick'], 0.7, 0.45), make_mat('ruin_rubble', o['rubble'], 0.58, 0.3),
        make_mat('ruin_sheet', o['sheet'], 0.4, 0.12)]
MAT_WALL, MAT_RUB, MAT_SHEET = 0, 1, 2

bm = bmesh.new(); bm.from_mesh(ob.data)
for lay in list(bm.loops.layers.float_color) + list(bm.loops.layers.color):
    (bm.loops.layers.float_color if lay in list(bm.loops.layers.float_color) else bm.loops.layers.color).remove(lay)
uv = bm.loops.layers.uv.active

# --- зразок місця димаря (найчервоніша грань вихідної текстури) — лише для положення
import numpy as np
img = None
for mat in ob.data.materials:
    for nd in mat.node_tree.nodes:
        if nd.type == 'BSDF_PRINCIPLED':
            for l in nd.inputs['Base Color'].links:
                img = getattr(l.from_node, 'image', img)
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
def redness(f):
    u = sum(l[uv].uv.x for l in f.loops) / len(f.loops); v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
    c = px[min(h - 1, int((v % 1) * h)), min(w - 1, int((u % 1) * w)), :3]
    return c[0] - 0.5 * (c[1] + c[2])
brick_f = max(bm.faces, key=redness)
bpos = sum((v.co for v in brick_f.verts), Vector()) / len(brick_f.verts)

# --- зріз стін
bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, 0, CUT), plane_no=(0, 0, 1), dist=1e-6)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z > CUT + 1e-5], context='FACES')
bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.6 and f.calc_center_median().z > 0.05], context='FACES')
bm.to_mesh(ob.data); bm.free()
bpy.context.view_layer.objects.active = ob
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.quads_convert_to_tris(); bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.object.mode_set(mode='OBJECT')
n0 = len(ob.data.polygons)
if n0 > 500:
    m = ob.modifiers.new('d', 'DECIMATE'); m.ratio = 500 / n0
    bpy.ops.object.modifier_apply(modifier=m.name)

bm = bmesh.new(); bm.from_mesh(ob.data)
uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new('UVMap')
vs = [v.co for v in bm.verts]
x0, x1 = min(v.x for v in vs), max(v.x for v in vs)
y0, y1 = min(v.y for v in vs), max(v.y for v in vs)
hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
nx = max(1, math.ceil((2 * hx + 2 * APRON) / TILE)); ny = max(1, math.ceil((2 * hy + 2 * APRON) / TILE))
BX, BY = nx * TILE / 2, ny * TILE / 2

def proj(f):
    # UV за світовими координатами: 1 одиниця = UVM метрів; вісь — за домінантною нормаллю
    n = f.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    for l in f.loops:
        p = l.vert.co * M / UVM
        l[uv].uv = (p.y, p.z) if ax == 0 else (p.x, p.z) if ax == 1 else (p.x, p.y)

# --- стіни: зовнішня оболонка + внутрішня (дзеркальна, зсунута на 0.25 м)
for f in bm.faces:
    f.material_index = MAT_WALL
shell = [f for f in bm.faces if abs(f.normal.z) < 0.5]
r = bmesh.ops.duplicate(bm, geom=shell)
dup_f = [e for e in r['geom'] if isinstance(e, bmesh.types.BMFace)]
dup_v = {v for f in dup_f for v in f.verts}
bmesh.ops.reverse_faces(bm, faces=dup_f)
for v in dup_v:
    d = Vector((cx - v.co.x, cy - v.co.y, 0)); d.normalize()
    v.co += d * (0.25 / M)
bm.normal_update()
for f in bm.faces:
    proj(f)

def finish(faces, mat):
    for f in faces:
        f.material_index = mat
        proj(f)

def lump(pos, rad, sq):
    r = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=rad)
    rot = Matrix.Rotation(rng.uniform(0, 6.28), 3, 'Z') @ Matrix.Rotation(rng.uniform(-0.6, 0.6), 3, 'X')
    for v in r['verts']:
        v.co = rot @ Vector((v.co.x * rng.uniform(0.9, 1.3), v.co.y, v.co.z * sq)) + pos
    fs = [f for f in bm.faces if f.verts[0] in r['verts']]
    for f in fs:
        f.smooth = True
    finish(fs, MAT_RUB)

def heap(px_, py_, R, hz):
    # купа з 7-11 уламків: більші внизу, менші нагорі
    k = rng.randint(7, 9)
    for i in range(k):
        d = abs(rng.gauss(0, R * 0.45)); d = min(d, R)
        a_ = rng.uniform(0, 6.28)
        rad = rng.uniform(0.55, 1.05) / M * (1.0 - 0.35 * d / R)
        z = hz * (1 - d / R) * rng.uniform(0.4, 1.0) + rad * 0.35
        lump(Vector((px_ + d * math.cos(a_), py_ + d * math.sin(a_), z)), rad, rng.uniform(0.55, 0.9))

def sheet(px_, py_, ang_z, tilt):
    wsh, lsh = 0.95 / M, 2.0 / M
    p = [bm.verts.new((-wsh / 2, -lsh / 2, 0)), bm.verts.new((wsh / 2, -lsh / 2, 0)), bm.verts.new((wsh / 2, lsh / 2, 0)), bm.verts.new((-wsh / 2, lsh / 2, 0))]
    p2 = [bm.verts.new(v.co) for v in p]
    rot = Matrix.Rotation(ang_z, 3, 'Z') @ Matrix.Rotation(tilt, 3, 'X')
    for v in p + p2:
        v.co = rot @ v.co + Vector((px_, py_, 0.18 / M + abs(math.sin(tilt)) * lsh / 2))
    f1 = bm.faces.new(p); f2 = bm.faces.new(list(reversed(p2)))
    bm.normal_update()
    finish([f1, f2], MAT_SHEET)

if o.get('chimney'):
    bx = max(-hx * 0.5, min(hx * 0.5, bpos.x)) + cx; by = max(-hy * 0.5, min(hy * 0.5, bpos.y)) + cy
    r = bmesh.ops.create_cube(bm, size=1.0)
    s = 0.7 / M
    for v in r['verts']:
        v.co = Vector((v.co.x * s, v.co.y * s, (v.co.z + 0.5) * float(o['chimney']) / M)) + Vector((bx, by, 0))
    bm.normal_update()
    finish([f for f in bm.faces if f.verts[0] in r['verts']], MAT_WALL)

def in_walls(x, y, m=0.3 / M):
    return (cx - hx - m) < x < (cx + hx + m) and (cy - hy - m) < y < (cy + hy + m)

# --- обвал усередині
heap(cx - hx * 0.25, cy, min(hx, hy) * 0.7, 0.9 / M)
heap(cx + hx * 0.3, cy + hy * 0.15, min(hx, hy) * 0.6, 0.7 / M)
for sgn in (-1, 1):
    sheet(cx + sgn * hx * 0.35, cy + rng.uniform(-hy * 0.3, hy * 0.3), rng.uniform(0, math.pi), sgn * rng.uniform(0.25, 0.5))

# --- завал навколо: упритул до стін, у межах footprint
placed = 0; tries = 0
while placed < int(o.get('heaps', 14)) and tries < 2000:
    tries += 1
    x = rng.uniform(-BX + 0.12, BX - 0.12); y = rng.uniform(-BY + 0.12, BY - 0.12)
    if in_walls(x, y, 0.5 / M) or not in_walls(x, y, 3.2 / M):
        continue
    R = rng.uniform(1.2, 2.0) / M
    if abs(x) + R > BX - 0.04 or abs(y) + R > BY - 0.04:
        continue
    heap(x, y, R, rng.uniform(0.4, 0.8) / M)
    placed += 1
for i in range(int(o.get('sheets', 5))):
    for _ in range(60):
        x = rng.uniform(-BX + 0.15, BX - 0.15); y = rng.uniform(-BY + 0.15, BY - 0.15)
        if not in_walls(x, y, 0.4 / M):
            break
    sheet(x, y, rng.uniform(0, math.pi), rng.uniform(0.12, 0.4))

ob.data.materials.clear()
for m in mats:
    ob.data.materials.append(m)
bm.to_mesh(ob.data); bm.free()
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0002)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(45))
print('MATIDX2', sorted(set(p.material_index for p in ob.data.polygons)), len(ob.data.materials))
vs = [v.co for v in ob.data.vertices]
ob.data.transform(Matrix.Translation((0, 0, -min(v.z for v in vs))))
ob['footprint_tiles'] = [nx, ny]
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_apply=True, export_extras=True)

dd = open(dst, 'rb').read(); off = 12
while off < len(dd):
    cl, ct = struct.unpack_from('<II', dd, off)
    if ct == 0x4E4F534A:
        g = json.loads(dd[off + 8:off + 8 + cl]); break
    off += 8 + cl
prims = [p for m in g['meshes'] for p in m['primitives']]
lo = [min(g['accessors'][p['attributes']['POSITION']]['min'][i] for p in prims) for i in range(3)]
hi = [max(g['accessors'][p['attributes']['POSITION']]['max'][i] for p in prims) for i in range(3)]
tr = sum(g['accessors'][p['indices']]['count'] for p in prims) // 3
print('RUIN tris', tr, 'prims', len(prims), 'size', [round(hi[i] - lo[i], 3) for i in range(3)], 'tiles', nx, ny, 'ymin', lo[1],
      'normals', all('normalTexture' in m for m in g['materials']))
