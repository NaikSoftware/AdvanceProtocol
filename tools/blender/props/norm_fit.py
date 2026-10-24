"""Нормалізація згенерованого GLB: лише рівномірне масштабування, ніколи розтяг по осях.

blender -b --factory-startup -P norm_fit.py -- in.glb out.glb key=value ...

Ключі:
  tris=N        ліміт трикутників
  tex=N         максимальний розмір текстури
  rot=D         поворот навколо вертикалі (градуси, кратно 90), щоб фасад дивився на +Y Blender (= -Z Godot)
  mode=tiles    будівля: вписати в ціле число тайлів (7.6 м на тайл), footprint_tiles іде в extras
  stated=L,S    реальні габарити (довга й коротка сторони, м); масштаб не перевищує реальний
  mode=height   вписати за висотою: h=<м>
  mode=crown    вписати за шириною крони: crown=<м>
  double=1      (mode=tiles) два дзеркальні екземпляри поруч уздовж X
  dry=1         прибрати мокрий вигляд: стала шорсткість, без металу
  thin=F        видалити частку F зелених острівців листя (насіння фіксоване)
  early=1       зелене листя -> жовто-оранжеве
"""
import bpy, bmesh, sys, json, struct, math, random
from mathutils import Matrix

TILE_M = 7.6   # 8 м тайл мінус запас на карнизи й рубель: будівля не заходить у сусідню клітинку

args = sys.argv[sys.argv.index('--') + 1:]
src, dst = args[0], args[1]
o = dict(a.split('=', 1) for a in args[2:])
limit = int(o.get('tris', 4000)); tex = int(o.get('tex', 512))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for ob in list(bpy.data.objects):
    if ob.type != 'MESH':
        bpy.data.objects.remove(ob)
meshes = [x for x in bpy.data.objects if x.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for x in meshes:
    x.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.name = 'prop'

def bbox():
    vs = [v.co for v in ob.data.vertices]
    return ([min(v[i] for v in vs) for i in range(3)], [max(v[i] for v in vs) for i in range(3)])

def base_images():
    out = {}
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for nd in mat.node_tree.nodes:
            if nd.type == 'BSDF_PRINCIPLED':
                for l in nd.inputs['Base Color'].links:
                    im = getattr(l.from_node, 'image', None)
                    if im is not None:
                        out[im.name] = im
    return out

def is_leaf(r, g, b):
    return (g > r * 1.03) & (g > b * 1.1)

# --- фасад на +Y
if float(o.get('rot', 0)) != 0:
    ob.data.transform(Matrix.Rotation(math.radians(float(o['rot'])), 4, 'Z'))

# --- проріджування листя: острівці зв'язності, що здебільшого зелені
if 'thin' in o:
    import numpy as np
    im = list(base_images().values())[0]
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bm = bmesh.new(); bm.from_mesh(ob.data); uv = bm.loops.layers.uv.active
    seen = set(); islands = []
    for f in bm.faces:
        if f.index in seen:
            continue
        st = [f]; seen.add(f.index); isl = []
        while st:
            c = st.pop(); isl.append(c)
            for e in c.edges:
                for n in e.link_faces:
                    if n.index not in seen:
                        seen.add(n.index); st.append(n)
        islands.append(isl)
    leaf = []
    for isl in islands:
        cols = []
        for f in isl[:40]:
            u = sum(l[uv].uv.x for l in f.loops) / len(f.loops); v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
            cols.append(px[min(h - 1, int((v % 1) * h)), min(w - 1, int((u % 1) * w)), :3])
        m = np.mean(cols, axis=0)
        if is_leaf(m[0], m[1], m[2]):
            leaf.append(isl)
    random.seed(7)
    drop = random.sample(leaf, int(len(leaf) * float(o['thin'])))
    bmesh.ops.delete(bm, geom=[f for isl in drop for f in isl], context='FACES')
    bm.to_mesh(ob.data); bm.free()
    print('THIN islands', len(islands), 'leaf', len(leaf), 'dropped', len(drop))

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode='OBJECT')
n0 = len(ob.data.polygons)
tgt = limit // (4 if o.get('quad') else 2 if o.get('double') else 1)
if n0 > tgt:
    m = ob.modifiers.new('d', 'DECIMATE'); m.ratio = tgt / n0 * 0.97
    bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))

# --- мокрий вигляд: шорсткість стала, металу нема (вологість дає шейдер)
if o.get('dry'):
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for nd in mat.node_tree.nodes:
            if nd.type == 'BSDF_PRINCIPLED':
                for name, val in (('Roughness', 0.82), ('Metallic', 0.0)):
                    for l in list(nd.inputs[name].links):
                        mat.node_tree.links.remove(l)
                    nd.inputs[name].default_value = val

lo, hi = bbox()
d = [hi[i] - lo[i] for i in range(3)]
mode = o.get('mode', 'height')
extras = None
if mode == 'tiles':
    L, S = [float(v) for v in o['stated'].split(',')]
    # природні габарити в одиницях моделі; реальний масштаб — із заявленої довгої сторони
    real = L / max(d[0], d[1])
    best = None
    for nx in range(1, 5):
        for nz in range(1, 5):
            s = min(nx * TILE_M / d[0], nz * TILE_M / d[1], real)
            if s >= 0.75 * real and (best is None or nx * nz < best[0]):
                best = (nx * nz, nx, nz, s)
    _, nx, nz, s = best
    if o.get('fixed'):
        nx, nz = [int(v) for v in o['fixed'].split(',')]
        s = min(nx * TILE_M / d[0], nz * TILE_M / d[1], real)
    ob.data.transform(Matrix.Diagonal((s, s, s, 1)))
    extras = [nx, nz]
    print('FIT tiles', nx, nz, 'scale', round(s, 4), 'real-scale ratio', round(s / real, 2))
elif mode == 'crown':
    s = float(o['crown']) / max(d[0], d[1]); ob.data.transform(Matrix.Diagonal((s, s, s, 1)))
    print('FIT crown scale', round(s, 4), 'natural w/h', round(max(d[0], d[1]) / d[2], 2))
else:
    s = float(o['h']) / d[2]; ob.data.transform(Matrix.Diagonal((s, s, s, 1)))
    print('FIT height scale', round(s, 4), 'natural w/h', round(max(d[0], d[1]) / d[2], 2))
if 'trim' in o:
    # крона надто широка за пропорціями моделі: зрізати гілки далі за R метрів від осі стовбура (центр основи)
    lo, hi = bbox()
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    bm = bmesh.new(); bm.from_mesh(ob.data)
    R = float(o['trim'])
    kill = [f for f in bm.faces if math.hypot(f.calc_center_median().x - cx, f.calc_center_median().y - cy) > R]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(ob.data); bm.free()
    print('TRIM removed', len(kill))
ob.data.transform(Matrix.Scale(1 / 8.0, 4))   # метри -> тайли (1 тайл = 8 м): масштаб до моделі нормовано в метрах

def mirror_join(axis):
    # дзеркальна копія з іншого боку: однаковий шматок двічі читався б клоном
    global ob, extras
    lo, hi = bbox()
    cp = ob.copy(); cp.data = ob.data.copy(); bpy.context.collection.objects.link(cp)
    v = [1, 1, 1]; v[axis] = -1
    cp.data.transform(Matrix.Diagonal((*v, 1)))
    cp.data.flip_normals()
    t = [0, 0, 0]; t[axis] = 2 * hi[axis]
    cp.data.transform(Matrix.Translation(t))
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); cp.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    extras = [extras[0] * (2 if axis == 0 else 1), extras[1] * (2 if axis == 1 else 1)]

if o.get('double') or o.get('quad'):
    mirror_join(0)
if o.get('quad'):
    mirror_join(1)

lo, hi = bbox()
ob.data.transform(Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))

if o.get('early'):
    import numpy as np
    for im in base_images().values():
        px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
        r, g, b = px[:, 0], px[:, 1], px[:, 2]
        mk = is_leaf(r, g, b)
        px[mk, 0] = np.minimum(1.0, g[mk] * 1.45)
        px[mk, 1] = np.minimum(1.0, g[mk] * 1.15)
        px[mk, 2] = b[mk] * 0.3
        im.pixels.foreach_set(px.ravel())

for im in bpy.data.images:
    if im.size[0] > tex:
        im.scale(tex, tex)
if extras:
    ob['footprint_tiles'] = extras
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
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
print('TRIS', n0, 'size(x,y,z)', [round(hi[i] - lo[i], 3) for i in range(3)], 'ymin', lo[1], 'extras', [n.get('extras') for n in g['nodes']] + [m.get('extras') for m in g['meshes']])
assert abs(lo[1]) < 1e-4
assert not [n for n in g['nodes'] if {'translation', 'rotation', 'scale', 'matrix'} & n.keys()]
