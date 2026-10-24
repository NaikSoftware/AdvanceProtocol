"""Виправлення будинків після нормалізації (масштаб і початок координат вже встановлені).

blender -b --factory-startup -P fix_house.py -- in.glb out.glb <fix> [key=value ...]
  fix = h1   випрямити ґанок і цоколь: діагональні грані нижче карниза замінюються площинами
  fix = h2   замкнути задню стіну (у моделі її нема)
  fix = h3   сонячні панелі: синьо-чорні, низька насиченість, сітка не світліша за половину яскравості
  fix = h4   приглушити червоний димар
"""
import bpy, bmesh, sys, math, json, struct
import numpy as np
from mathutils import Vector

a = sys.argv[sys.argv.index('--') + 1:]
src, dst, fix = a[0], a[1], a[2]
opt = dict(x.split('=', 1) for x in a[3:])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = [x for x in bpy.data.objects if x.type == 'MESH'][0]
fp = list(ob.get('footprint_tiles', [])) if 'footprint_tiles' in ob.keys() else None
M = 8.0  # тайл -> метри

def base_image():
    for mat in bpy.data.materials:
        for nd in mat.node_tree.nodes:
            if nd.type == 'BSDF_PRINCIPLED':
                for l in nd.inputs['Base Color'].links:
                    im = getattr(l.from_node, 'image', None)
                    if im is not None:
                        return im

def mesh_edit(fn):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    fn(bm)
    bm.to_mesh(ob.data); bm.free()

def uv_color_mask(bm, pred):
    """Грані, чий середній колір текстури задовольняє pred(r,g,b) — повертає (грані, зразок кольору першої)."""
    im = base_image(); w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    uv = bm.loops.layers.uv.active
    out = []
    for f in bm.faces:
        u = sum(l[uv].uv.x for l in f.loops) / len(f.loops); v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
        c = px[min(h - 1, int((v % 1) * h)), min(w - 1, int((u % 1) * w)), :3]
        if pred(*c):
            out.append(f)
    return out

if fix == 'h1':
    # "діагональні" грані внизу: нормаль не вісьова й не вертикальна, нижче карниза (~2.6 м)
    def f_h1(bm):
        kill = []
        for f in bm.faces:
            n = f.normal
            hz = math.hypot(n.x, n.y)
            ang = math.degrees(math.atan2(abs(n.y), abs(n.x)))  # 0 або 90 — вісьова
            axial = min(ang, 90 - ang)
            top = max(v.co.z for v in f.verts) * M
            if top < 3.0 and hz > 0.2 and axial > 8 and f.calc_area() * M * M > 0.01:
                kill.append(f)
        print('H1 diagonal faces', len(kill))
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        uv = bm.loops.layers.uv.active
        r = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=8)
        for f in r['faces']:
            for l in f.loops:
                l[uv].uv = l.vert.link_loops[0][uv].uv
    mesh_edit(f_h1)

elif fix == 'h2':
    def f_h2(bm):
        # стіна по задній площині бокса: чотири кути з нижніх/верхніх вершин найзаднішого шару
        vs = [v.co for v in bm.verts]
        ymin = min(v.y for v in vs); ymax = max(v.y for v in vs)
        side = ymin if opt.get('side', 'min') == 'min' else ymax
        z1 = float(opt.get('top', 3.0)) / M
        near = [v for v in vs if abs(v.y - side) < 0.15 and v.z < z1]
        x0, x1 = min(v.x for v in near), max(v.x for v in near)
        uv = bm.loops.layers.uv.active
        p = [bm.verts.new((x0, side, 0)), bm.verts.new((x1, side, 0)), bm.verts.new((x1, side, z1)), bm.verts.new((x0, side, z1))]
        f = bm.faces.new(p)
        # колір цегли з боку будинку: беремо UV найближчої стінної вершини
        ref = min((v for v in bm.verts if v not in p and v.co.z < z1 and len(v.link_loops)), key=lambda v: (v.co - Vector((x0, side, z1 / 2))).length)
        for l in f.loops:
            l[uv].uv = ref.link_loops[0][uv].uv
        f.normal_update()
        print('H2 back wall', round(x1 - x0, 3), 'x', round(z1, 3))
    mesh_edit(f_h2)

elif fix == 'h3':
    im = base_image(); w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    blue = (b > r * 1.15) & (b > g * 1.05) & (mx > 0.08)   # синя панель, не стіна
    # синьо-чорне: низька насиченість і темно; світлі лінії сітки (високе значення) притемнюються до 50 %
    val = np.where(blue, np.minimum(mx, 0.12) * 0.5 + 0.0, mx)
    scale = np.where(mx > 1e-5, val / np.maximum(mx, 1e-5), 1.0)
    px[blue, 0] = (r * scale)[blue] * 0.9
    px[blue, 1] = (g * scale)[blue] * 0.95
    px[blue, 2] = (b * scale)[blue]
    # сітка: світлі пікселі поруч із панеллями
    # білі лінії сітки панелей: майже нейтральні й дуже світлі -> не світліші за половину значення
    grid = (mx > 0.6) & (mx - mn < 0.08) & (~blue)
    px[grid, :3] *= 0.45
    print('H3 blue px', int(blue.sum()), 'grid px', int(grid.sum()))
    im.pixels.foreach_set(px.ravel())

elif fix == 'h4':
    im = base_image(); w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    hot = (r > g * 1.6) & (r > b * 1.6) & (r > 0.35)
    # гарячий цегляно-червоний -> приглушена бура цегла
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    px[hot, 0] = (lum * 1.25)[hot]; px[hot, 1] = (lum * 0.95)[hot]; px[hot, 2] = (lum * 0.8)[hot]
    print('H4 hot px', int(hot.sum()))
    im.pixels.foreach_set(px.ravel())

elif fix in ('stump', 'boulder'):
    im = base_image()
    px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
    def chroma(p):
        # sRGB -> Lab, лише a*, b*: середня C* зображення
        c = np.where(p[:, :3] > 0.04045, ((p[:, :3] + 0.055) / 1.055) ** 2.4, p[:, :3] / 12.92)
        X = (c @ [0.4124, 0.3576, 0.1805]) / 0.95047; Y = c @ [0.2126, 0.7152, 0.0722]; Z = (c @ [0.0193, 0.1192, 0.9505]) / 1.08883
        f = lambda t: np.where(t > 0.008856, np.cbrt(t), 7.787 * t + 16 / 116)
        return float(np.mean(np.hypot(500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z)))))
    lum = (0.3 * px[:, 0] + 0.59 * px[:, 1] + 0.11 * px[:, 2])[:, None]
    if fix == 'stump':
        # зріз пня світліший: світлі теплі пікселі підсвітити
        mk = (lum[:, 0] > 0.28) & (px[:, 0] > px[:, 2] * 1.2)
        px[mk, :3] = np.minimum(1.0, px[mk, :3] * 1.4)
        print('H4 stump lightened px', int(mk.sum()), 'C*', round(chroma(px), 1))
    else:
        base = px.copy()
        for k in (1.0, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2):
            px[:, :3] = lum + (base[:, :3] - lum) * k
            if chroma(px) <= 6.0:
                break
        print('H4 boulder sat factor', k, 'C*', round(chroma(px), 1))
    im.pixels.foreach_set(px.ravel())

if fp:
    ob['footprint_tiles'] = fp
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
print('DONE size', [round(hi[i] - lo[i], 3) for i in range(3)], 'ymin', lo[1], 'extras', [n.get('extras') for n in g['nodes']])
