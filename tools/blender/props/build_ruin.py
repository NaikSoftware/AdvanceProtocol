"""Руїна з геометрії готового будинку: стіни зрізані до 2.5 м, обвал усередині, завал навколо.

blender -b --factory-startup -P build_ruin.py -- house.glb out.glb seed=1 apron=3 chimney=1 sheets=5
Усе в метрах/8 (тайлах), як і вихідна модель. Колір завалу — плоскі зразки з текстури будинку
з розкидом по вершинах; текстура знебарвлена до chroma <= ~8, як у решти Blender-набору.
"""
import bpy, bmesh, sys, math, random, json, struct
import numpy as np
from mathutils import Vector, Matrix, noise

a = sys.argv[sys.argv.index('--') + 1:]
src, dst = a[0], a[1]
o = dict(x.split('=', 1) for x in a[2:])
M = 8.0
rng = random.Random(int(o.get('seed', 1)))
CUT = float(o.get('cut', 2.5)) / M
APRON = float(o.get('apron', 3.0)) / M
TILE = 7.6 / M

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = [x for x in bpy.data.objects if x.type == 'MESH'][0]

# --- текстура: знебарвити (руїна: пил, кіптява), зразки кольору
img = None
for mat in bpy.data.materials:
    for nd in mat.node_tree.nodes:
        if nd.type == 'BSDF_PRINCIPLED':
            for l in nd.inputs['Base Color'].links:
                img = getattr(l.from_node, 'image', img)
            for name, val in (('Roughness', 0.9), ('Metallic', 0.0)):
                for l in list(nd.inputs[name].links):
                    mat.node_tree.links.remove(l)
                nd.inputs[name].default_value = val
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
lum = (0.3 * px[..., 0] + 0.59 * px[..., 1] + 0.11 * px[..., 2])[..., None]
px[..., :3] = (lum + (px[..., :3] - lum) * 0.35) * 0.62   # знебарвлено й притемнено: пил і кіптява
img.pixels.foreach_set(px.ravel())

def sample(u, v):
    return px[min(h - 1, int((v % 1) * h)), min(w - 1, int((u % 1) * w)), :3]

bm = bmesh.new(); bm.from_mesh(ob.data)
uv = bm.loops.layers.uv.active
for lay in list(bm.loops.layers.float_color) + list(bm.loops.layers.color):
    (bm.loops.layers.float_color if lay in list(bm.loops.layers.float_color) else bm.loops.layers.color).remove(lay)
col = bm.loops.layers.float_color.new('Col')
for f in bm.faces:
    for l in f.loops:
        l[col] = (1, 1, 1, 1)

def face_uv(f):
    n = len(f.loops)
    return (sum(l[uv].uv.x for l in f.loops) / n, sum(l[uv].uv.y for l in f.loops) / n)

# --- зразки UV: тиньк/стіна (нижня частина), дах, цегла (найчервоніший)
walls = [f for f in bm.faces if max(abs(f.normal.z) for _ in [0]) < 0.4 and max(v.co.z for v in f.verts) < 0.4]
roofs = [f for f in bm.faces if f.normal.z > 0.35 and min(v.co.z for v in f.verts) > 0.3]
def redness(f):
    c = sample(*face_uv(f)); return c[0] - 0.5 * (c[1] + c[2])
brick_f = max(bm.faces, key=redness)
uv_wall = face_uv(rng.choice(walls)) if walls else (0.5, 0.5)
uv_roof = face_uv(rng.choice(roofs)) if roofs else (0.5, 0.5)
uv_brick = face_uv(brick_f)
brick_c = [v.co.copy() for v in brick_f.verts]
def lumc(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
PAL = []
cand = [face_uv(f) for f in bm.faces]
rng.shuffle(cand)
for u_ in cand:
    c = sample(*u_)
    if 0.09 < lumc(c) < 0.3:
        PAL.append(u_)
    if len(PAL) >= 10:
        break
if not PAL:
    PAL = [uv_wall, uv_roof]

# --- зріз стін
bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, 0, CUT), plane_no=(0, 0, 1), dist=1e-6)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z > CUT + 1e-5], context='FACES')
bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.6 and f.calc_center_median().z > 0.05], context='FACES')  # стеля/підлоги зсередини
bm.to_mesh(ob.data); bm.free()
bpy.context.view_layer.objects.active = ob
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.quads_convert_to_tris(); bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.object.mode_set(mode='OBJECT')
n0 = len(ob.data.polygons)
if n0 > 700:
    m = ob.modifiers.new('d', 'DECIMATE'); m.ratio = 700 / n0
    bpy.ops.object.modifier_apply(modifier=m.name)

bm = bmesh.new(); bm.from_mesh(ob.data)
uv = bm.loops.layers.uv.active
col = bm.loops.layers.float_color.get('Col') or bm.loops.layers.float_color.new('Col')

# --- габарит стін
vs = [v.co for v in bm.verts]
x0, x1 = min(v.x for v in vs), max(v.x for v in vs)
y0, y1 = min(v.y for v in vs), max(v.y for v in vs)
hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
nx = max(1, math.ceil((2 * hx + 2 * APRON) / TILE)); ny = max(1, math.ceil((2 * hy + 2 * APRON) / TILE))
BX, BY = nx * TILE / 2, ny * TILE / 2   # межі footprint навколо початку координат

# --- кіптява: зовнішня стіна темнішає з висотою, нерівно
for f in bm.faces:
    k = rng.uniform(0.75, 1.0)
    for l in f.loops:
        z = l.vert.co.z / CUT
        s = 0.4 * k * (1.0 - 0.55 * z * z)
        l[col] = (s, s, s, 1)

# --- внутрішня оболонка: дзеркальні грані, зсунуті всередину на 0.25 м, темніші (сажа)
shell = [f for f in bm.faces if abs(f.normal.z) < 0.5]
r = bmesh.ops.duplicate(bm, geom=shell)
dup_f = [e for e in r['geom'] if isinstance(e, bmesh.types.BMFace)]
dup_v = {v for f in dup_f for v in f.verts}
bmesh.ops.reverse_faces(bm, faces=dup_f)
for v in dup_v:
    d = Vector((cx - v.co.x, cy - v.co.y, 0)); d.normalize()
    v.co += d * (0.25 / M)
for f in dup_f:
    for l in f.loops:
        s = 0.3 * (1 - 0.3 * l.vert.co.z / CUT)
        l[col] = (s, s, s, 1)

def put_uv(f, u):
    # u == None: кожна грань бере випадковий зразок палітри — купа виходить рябою, а не плоскою плямою
    if u is None:
        c = f.calc_center_median()
        k = (noise.noise(Vector((c.x, c.y, c.z)) * (M / 1.1)) + 1) / 2
        u = PAL[min(len(PAL) - 1, int(k * len(PAL)))]
    for l in f.loops:
        l[uv].uv = u

def tint(f, base, jit=0.18):
    k = base * (1 + rng.uniform(-jit, jit))
    for l in f.loops:
        l[col] = (k, k, k, 1)

def add_piece(geom_fn, u, base, jit=0.18, **kw):
    r = geom_fn(**kw)
    fs = [e for e in r['geom'] if isinstance(e, bmesh.types.BMFace)]
    for f in fs:
        put_uv(f, u); tint(f, base, jit)
    return r

def heap(px_, py_, rx, ry, hz, u, base):
    r = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    vv = [e for e in r['verts']]
    for v in vv:
        v.co.x *= rx; v.co.y *= ry; v.co.z = max(v.co.z, 0.0) * hz
        v.co.x += rng.uniform(-0.1, 0.1) * rx; v.co.y += rng.uniform(-0.1, 0.1) * ry; v.co.z *= rng.uniform(0.8, 1.15)
        v.co.x += px_; v.co.y += py_
    low = [f for f in bm.faces if f.verts[0] in vv and all(v.co.z <= 1e-6 for v in f.verts)]
    bmesh.ops.delete(bm, geom=low, context='FACES')
    for f in bm.faces:
        if f.verts[0] in vv and f not in low and f.is_valid:
            put_uv(f, u); tint(f, base, 0.25)

def chunk(px_, py_, s, u, base):
    r = bmesh.ops.create_cube(bm, size=s)
    rot = Matrix.Rotation(rng.uniform(0, math.pi), 3, 'Z') @ Matrix.Rotation(rng.uniform(-0.5, 0.5), 3, 'X')
    for v in r['verts']:
        v.co = rot @ Vector((v.co.x * rng.uniform(0.7, 1.4), v.co.y, v.co.z * rng.uniform(0.5, 1.0)))
        v.co += Vector((px_, py_, s * 0.3))
    for f in bm.faces:
        if f.verts[0] in r['verts']:
            put_uv(f, u); tint(f, base, 0.3)

def sheet(px_, py_, ang_z, tilt, u, base):
    # гофрований лист: 0.95 x 2.0 м, двобічний
    wsh, lsh = 0.95 / M, 2.0 / M
    p = [bm.verts.new((-wsh / 2, -lsh / 2, 0)), bm.verts.new((wsh / 2, -lsh / 2, 0)), bm.verts.new((wsh / 2, lsh / 2, 0)), bm.verts.new((-wsh / 2, lsh / 2, 0))]
    rot = Matrix.Rotation(ang_z, 3, 'Z') @ Matrix.Rotation(tilt, 3, 'X')
    for v in p:
        v.co = rot @ v.co + Vector((px_, py_, 0.18 / M * 1 + abs(math.sin(tilt)) * lsh / 2))
    p2 = [bm.verts.new(v.co) for v in p]
    f1 = bm.faces.new(p); f2 = bm.faces.new(list(reversed(p2)))
    for f in (f1, f2):
        put_uv(f, u); tint(f, base, 0.2)

# --- димар: стовп цегли (лише коли просять), стоїть на землі
if o.get('chimney'):
    bx = sum(c.x for c in brick_c) / len(brick_c); by = sum(c.y for c in brick_c) / len(brick_c)
    bx, by = max(-hx * 0.5, min(hx * 0.5, bx)) + cx, max(-hy * 0.5, min(hy * 0.5, by)) + cy
    s = 0.7 / M
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r['verts']:
        v.co = Vector((v.co.x * s, v.co.y * s, (v.co.z + 0.5) * float(o['chimney']) / M)) + Vector((bx, by, 0))
    for f in bm.faces:
        if f.verts[0] in r['verts']:
            put_uv(f, uv_brick); tint(f, 0.55, 0.1)

def in_walls(x, y, m=0.3 / M):
    return (cx - hx - m) < x < (cx + hx + m) and (cy - hy - m) < y < (cy + hy + m)

# --- обвал усередині: купа до ~0.8 м і два зсунуті листи даху
heap(cx, cy, hx * 0.75, hy * 0.75, 0.9 / M, None, 0.55)
for sgn in (-1, 1):
    sheet(cx + sgn * hx * 0.35, cy + rng.uniform(-hy * 0.3, hy * 0.3), rng.uniform(0, math.pi), sgn * rng.uniform(0.25, 0.5), uv_roof, 0.5)
    sheet(cx + sgn * hx * 0.2, cy, rng.uniform(0, math.pi), -sgn * 0.3, uv_roof, 0.45)

# --- завал навколо: 2-5 м, усе в межах footprint з відступом 0.1 тайла
pts = 0
tries = 0
while pts < 30 and tries < 1500:
    tries += 1
    x = rng.uniform(-BX + 0.1, BX - 0.1); y = rng.uniform(-BY + 0.1, BY - 0.1)
    # завал лежить упритул до стін: далі 3.2 м від стіни купи не ставимо
    if in_walls(x, y, 0.6 / M) or not in_walls(x, y, 3.2 / M):
        continue
    rx = rng.uniform(0.8, 1.8) / M; ry = rng.uniform(0.8, 1.8) / M
    if abs(x) + rx > BX - 0.05 or abs(y) + ry > BY - 0.05:
        continue
    heap(x, y, rx, ry, rng.uniform(0.4, 0.8) / M, None, rng.uniform(0.4, 0.7))
    pts += 1
placed = 0
tries = 0
while placed < 60 and tries < 800:
    tries += 1
    x = rng.uniform(-BX + 0.1, BX - 0.1); y = rng.uniform(-BY + 0.1, BY - 0.1)
    if in_walls(x, y, 0.1 / M):
        continue
    chunk(x, y, rng.uniform(0.25, 0.55) / M, None, rng.uniform(0.4, 0.75))
    placed += 1
ns = int(o.get('sheets', 5))
for i in range(ns):
    for _ in range(50):
        x = rng.uniform(-BX + 0.15, BX - 0.15); y = rng.uniform(-BY + 0.15, BY - 0.15)
        if not in_walls(x, y, 0.4 / M):
            break
    sheet(x, y, rng.uniform(0, math.pi), rng.uniform(0.12, 0.4), uv_roof, rng.uniform(0.5, 0.9))

# --- межі: усе, що вилізло за footprint, відсікається
for f in list(bm.faces):
    c = f.calc_center_median()
    if abs(c.x) > BX or abs(c.y) > BY:
        bmesh.ops.delete(bm, geom=[f], context='FACES')

bm.to_mesh(ob.data); bm.free()
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0003)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
# початок координат: основа в y = 0 (під землю нічого)
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
print('RUIN tris', tr, 'size', [round(hi[i] - lo[i], 3) for i in range(3)], 'tiles', nx, ny, 'ymin', lo[1], 'attrs', list(prims[0]['attributes'].keys()))
