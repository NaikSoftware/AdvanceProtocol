import bpy, sys, json, struct, math
from mathutils import Matrix

# blender -b --factory-startup -P norm_cc0.py -- in.gltf out.glb tri_limit obj1,obj2 [unit_per_metre=0.125]
a = sys.argv[sys.argv.index('--') + 1:]
src, dst, limit, names = a[0], a[1], int(a[2]), a[3].split(',')
k = float(a[4]) if len(a) > 4 else 0.125

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
keep = [o for o in bpy.data.objects if o.type == 'MESH' and (names == ['*'] or o.name in names)]
for o in list(bpy.data.objects):
    if o not in keep:
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action='DESELECT')
for o in keep:
    o.select_set(True)
bpy.context.view_layer.objects.active = keep[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(keep) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.mesh.remove_doubles(threshold=0.0001)
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

ob.data.transform(Matrix.Diagonal((k, k, k, 1)))
lo, hi = bbox()
ob.data.transform(Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))
for im in bpy.data.images:
    if im.size[0] > 256:
        im.scale(256, 256)
bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_apply=True)

d = open(dst, 'rb').read(); off = 12
while off < len(d):
    cl, ct = struct.unpack_from('<II', d, off)
    if ct == 0x4E4F534A:
        g = json.loads(d[off + 8:off + 8 + cl]); break
    off += 8 + cl
prims = [p for m in g['meshes'] for p in m['primitives']]
lo = [min(g['accessors'][p['attributes']['POSITION']]['min'][i] for p in prims) for i in range(3)]
hi = [max(g['accessors'][p['attributes']['POSITION']]['max'][i] for p in prims) for i in range(3)]
print('TRIS', n0, '->', n1, 'GLB prims', len(prims), 'size', [round(hi[i] - lo[i], 3) for i in range(3)], 'ymin', lo[1])
assert abs(lo[1]) < 1e-4
assert not [n for n in g['nodes'] if {'translation', 'rotation', 'scale', 'matrix'} & n.keys()]
