import bpy, sys, json, struct, math
from mathutils import Matrix

# blender -b --factory-startup -P norm_box.py -- in.glb out.glb tri_limit X Y Z tex
# X, Y(height), Z in metres (stated size); 1 tile = 8 m. Long horizontal axis goes to X.
a = sys.argv[sys.argv.index('--') + 1:]
src, dst, limit = a[0], a[1], int(a[2])
tx, ty, tz = [float(v) / 8.0 for v in a[3:6]]
tex = int(a[6])
early = len(a) > 7 and a[7] == 'early'

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode='OBJECT')
n0 = len(ob.data.polygons)
if n0 > limit:
    m = ob.modifiers.new('d', 'DECIMATE')
    m.ratio = limit / n0 * 0.97
    bpy.ops.object.modifier_apply(modifier=m.name)
n1 = len(ob.data.polygons)
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))

def bbox():
    vs = [v.co for v in ob.data.vertices]
    return ([min(v[i] for v in vs) for i in range(3)], [max(v[i] for v in vs) for i in range(3)])

lo, hi = bbox()
d = [hi[i] - lo[i] for i in range(3)]
# the target's long horizontal side is X; rotate the model so its own long side matches
if (tx >= tz) != (d[0] >= d[1]):
    ob.data.transform(Matrix.Rotation(math.radians(90), 4, 'Z'))
    lo, hi = bbox(); d = [hi[i] - lo[i] for i in range(3)]
s = (tx / d[0], tz / d[1], ty / d[2])
print('FIT_FACTORS X,Y(blender),Z-up', [round(v, 3) for v in s], 'spread', round(max(s) / min(s), 2))
ob.data.transform(Matrix.Diagonal((s[0], s[1], s[2], 1)))
lo, hi = bbox()
ob.data.transform(Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))
if early:
    import numpy as np
    done = set()
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for nd in mat.node_tree.nodes:
            if nd.type != 'BSDF_PRINCIPLED':
                continue
            for l in nd.inputs['Base Color'].links:
                im = getattr(l.from_node, 'image', None)
                if im is None or im.name in done:
                    continue
                done.add(im.name)
                px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
                r, g, b = px[:, 0], px[:, 1], px[:, 2]
                m = (g > r * 1.03) & (g > b * 1.1)
                # зелене листя -> жовто-оранжеве (рання осінь), кора й земля без змін
                px[m, 0] = np.minimum(1.0, g[m] * 1.35)
                px[m, 1] = g[m] * 0.85
                px[m, 2] = b[m] * 0.45
                im.pixels.foreach_set(px.ravel())
    print('EARLY recoloured', sorted(done))
for im in bpy.data.images:
    if im.size[0] > tex:
        im.scale(tex, tex)
bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True)
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
print('TRIS', n0, '->', n1, 'GLB prims', len(prims), 'size(x,y,z)', [round(hi[i] - lo[i], 3) for i in range(3)], 'ymin', lo[1])
assert abs(lo[1]) < 1e-4
assert not [n for n in g['nodes'] if {'translation', 'rotation', 'scale', 'matrix'} & n.keys()]
