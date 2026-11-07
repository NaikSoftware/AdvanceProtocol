"""Stage 4: lo + procedural running gear + recognition panels -> assets/units/<unit>.glb.

    blender --background --factory-startup --python assemble.py -- <unit>

COLOR_0: R recognition panel, G track faces, B rotating wheel faces, black elsewhere.
UV2 (TEXCOORD_1 as Godot reads it): track = (arc length in model units, 0 inner .. 1 outer edge);
wheel = (axle y, axle z) in Godot axes; (0, 0) elsewhere. The glTF exporter writes v as 1 - v,
so every UV2 is stored pre-flipped here.
Arc length runs counter-clockwise seen from +X (bottom run towards the front, top run towards the
rear), the same on both sides; the loop total is snapped to whole tread periods so the seam,
placed on the top run under the skirt, does not jump.
"""
import bpy, bmesh, sys, os, math, subprocess
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

cfg = lib.load(sys.argv[sys.argv.index("--") + 1])
k = cfg["k"]
bpy.ops.wm.open_mainfile(filepath=os.path.join(cfg["work"], "work.blend"))
bpy.data.objects.remove(bpy.data.objects["hi"])
lo = bpy.data.objects["lo"]
G = cfg["gear"]
L = lambda v: v * k                                  # source length -> model


def uv2_store(u, v):
    return (u, 1.0 - v)                              # pre-flip: Godot reads (u, v)


def new_part(name):
    bm = bmesh.new()
    return bm, bm.loops.layers.uv.new("UVMap"), bm.loops.layers.uv.new("UV2"), \
        bm.loops.layers.color.new("Color")


def face(bm, uvl, uv2l, cl, verts, uvs, uv2s, color, want=None):
    f = bm.faces.new(verts)
    for lp, a, b in zip(f.loops, uvs, uv2s):
        lp[uvl].uv = a; lp[uv2l].uv = uv2_store(*b); lp[cl] = color
    if want is not None:
        f.normal_update()
        if f.normal.dot(want) < 0:
            f.normal_flip()
    return f


def finish(bm, name):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(ob)
    return ob


def cell_map(name, du, dv):
    """du, dv in -1..1 -> Blender UV inside a column cell."""
    u0, v0, u1, v1 = lib.cell_uv(name)
    return ((u0 + u1) / 2 + du * (u1 - u0) / 2 * 0.96, (v0 + v1) / 2 + dv * (v1 - v0) / 2 * 0.96)


# ---- track loop -------------------------------------------------------------------------------
t = L(G["track_t"])
circ = [(lib.m_long(cfg, x), L(G["road"]["h"]), L(G["road"]["r"])) for x in G["road"]["long"]]
circ += [(lib.m_long(cfg, G[w]["long"]), L(G[w]["h"]), L(G[w]["r"])) for w in ("sprocket", "idler")]
pts = []
for cy, cz, r in circ:
    for i in range(48):
        a = 2 * math.pi * i / 48
        pts.append((cy + (r + t / 2) * math.cos(a), cz + (r + t / 2) * math.sin(a)))
pts = sorted(set(pts))


def cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


lower, upper = [], []
for p in pts:                                        # monotone chain: counter-clockwise hull
    while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 1e-12:
        lower.pop()
    lower.append(p)
for p in reversed(pts):
    while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 1e-12:
        upper.pop()
    upper.append(p)
hull = lower[:-1] + upper[:-1]
# keep every 2nd arc point: 15 degree steps are plenty at 2-6 px per wheel
keep = [hull[0]]
for p in hull[1:]:
    if math.dist(p, keep[-1]) > L(0.007):
        keep.append(p)
hull = np.array(keep)
# start the loop at the middle of the top run, where the skirt hides the seam
top = np.argmax(hull[:, 1] - 0.01 * np.abs(hull[:, 0] - hull[:, 0].mean()))
hull = np.roll(hull, -top, 0)
seg = np.linalg.norm(np.diff(np.vstack([hull, hull[:1]]), axis=0), axis=1)
total = seg.sum()
snap = max(1, round(total / lib.TREAD_PERIOD)) * lib.TREAD_PERIOD
arc = np.concatenate([[0], np.cumsum(seg)]) * (snap / total)
centre = hull.mean(0)
lat0, lat1 = L(G["track_lat"][0]), L(G["track_lat"][1])
print(f"ASM track loop {len(hull)} pts, length {total:.4f} -> u total {snap:.4f}")

bm, uvl, uv2l, cl = new_part("track")
green = (0.0, 1.0, 0.0, 1.0)
for side in (1, -1):
    ring = np.vstack([hull, hull[:1]])
    nrm = []
    for i, p in enumerate(ring):                     # outward normal in the YZ plane per vertex
        a, b = ring[i - 1] if i else ring[-2], ring[i + 1] if i + 1 < len(ring) else ring[1]
        tg = (b - a) / (np.linalg.norm(b - a) + 1e-12)
        nrm.append(np.array([tg[1], -tg[0]]))
    V = {}
    for i, (p, n) in enumerate(zip(ring, nrm)):
        for key, off in (("o", t / 2), ("i", -t / 2)):
            q = p + n * off
            V[key, i, 0] = bm.verts.new((side * lat0, q[0], q[1]))
            V[key, i, 1] = bm.verts.new((side * lat1, q[0], q[1]))
    for i in range(len(ring) - 1):
        s0, s1 = arc[i], arc[i + 1]
        mid = (ring[i] + ring[i + 1]) / 2
        out_dir = Vector((0, *(mid - centre)))
        uv0 = lambda s, vv: (s / lib.TREAD_PERIOD, 1.0 - vv * lib.STRIP)
        for key, sign in (("o", 1), ("i", -1)):      # outer tread and inner surface
            vs = [V[key, i, 0], V[key, i + 1, 0], V[key, i + 1, 1], V[key, i, 1]]
            st = [(s0, 0), (s1, 0), (s1, 1), (s0, 1)]
            face(bm, uvl, uv2l, cl, vs, [uv0(*x) for x in st], st, green, out_dir * sign)
        vs = [V["o", i, 1], V["o", i + 1, 1], V["i", i + 1, 1], V["i", i, 1]]   # outer rim
        st = [(s0, 1), (s1, 1), (s1, 1), (s0, 1)]
        face(bm, uvl, uv2l, cl, vs, [uv0(*x) for x in st], st, green, Vector((side, 0, 0)))
parts = [finish(bm, "track")]

# ---- wheels -----------------------------------------------------------------------------------
bm, uvl, uv2l, cl = new_part("wheels")
blue = (0.0, 0.0, 1.0, 1.0)
n = G["sides"]
w0, w1 = L(G["wheel_lat"][0]), L(G["wheel_lat"][1])
wheels = [(c, "wheel") for c in circ[:-2]] + [(circ[-2], "sprocket"), (circ[-1], "wheel")]
for side in (1, -1):
    for (cy, cz, r), cname in wheels:
        ax = (cz, -cy)                               # Godot (y, z) of the axle
        outer = [bm.verts.new((side * w1, cy + r * math.cos(2 * math.pi * i / n), cz + r * math.sin(2 * math.pi * i / n))) for i in range(n)]
        inner = [bm.verts.new((side * w0, cy + r * math.cos(2 * math.pi * i / n), cz + r * math.sin(2 * math.pi * i / n))) for i in range(n)]
        uvs = [cell_map(cname, math.cos(2 * math.pi * i / n) * side, math.sin(2 * math.pi * i / n)) for i in range(n)]
        face(bm, uvl, uv2l, cl, outer, uvs, [ax] * n, blue, Vector((side, 0, 0)))
        tyre = cell_map("wheel", 0.9, 0.0)
        for i in range(n):
            j = (i + 1) % n
            mid = Vector((0, math.cos(2 * math.pi * (i + 0.5) / n), math.sin(2 * math.pi * (i + 0.5) / n)))
            face(bm, uvl, uv2l, cl, [outer[i], outer[j], inner[j], inner[i]], [tyre] * 4, [ax] * 4, blue, mid)
bmesh.ops.triangulate(bm, faces=bm.faces)
parts.append(finish(bm, "wheels"))

# ---- recognition panels, strapped to the surface beneath ---------------------------------------
# Cloth on a roof: every vertex rests on what is under it, and over a bump the cloth falls back
# at `panel_slope` (rise per run) instead of tenting flat across. The panel must lie wholly on one
# roof, flat or sloped: a sample more than `panel_dip` below the footprint's best-fit plane is
# hanging off an edge, and
# the build fails rather than ship a flap. Pick `at` with panel_spots.py.
dg = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(lo, dg)
bm, uvl, uv2l, cl = new_part("panels")
red = (1.0, 0.0, 0.0, 1.0)
cell_sz = cfg.get("panel_cell", 0.025)
for p in cfg["panels"]:
    cx, cy = p["at"]
    sx, sy = p["size_m"][0] / lib.TILE_M, p["size_m"][1] / lib.TILE_M
    NX, NY = max(2, math.ceil(sx / cell_sz)), max(2, math.ceil(sy / cell_sz))
    gx = cx + (np.arange(NX + 1) / NX - 0.5) * sx
    gy = cy + (np.arange(NY + 1) / NY - 0.5) * sy
    # each vertex rests on the highest point within half a cell of it, so no rim pokes through
    # between vertices; sampled 4x finer than the cloth grid
    F = 4
    fx = cx + (np.arange(NX * F + 1) / (NX * F) - 0.5) * sx
    fy = cy + (np.arange(NY * F + 1) / (NY * F) - 0.5) * sy
    zf = np.zeros((len(fy), len(fx)))
    for j, yy in enumerate(fy):
        for i, xx in enumerate(fx):
            hit = bvh.ray_cast(Vector((xx, yy, 2.0)), Vector((0, 0, -1)))[0]
            zf[j, i] = hit.z if hit else 0.0
    zp = np.pad(zf, F // 2, mode="edge")
    z = np.max([zp[a:a + len(fy):F, b:b + len(fx):F] for a in range(F + 1) for b in range(F + 1)], 0)
    jj, ii = np.mgrid[0:zf.shape[0], 0:zf.shape[1]]
    A = np.c_[ii.ravel(), jj.ravel(), np.ones(zf.size)]
    res = zf.ravel() - A @ np.linalg.lstsq(A, zf.ravel(), rcond=None)[0]
    print(f"ASM panel {p['name']}: at x {cx:+.3f} y {cy:+.3f}, {NX}x{NY} cells, surface {zf.min():.3f}..{zf.max():.3f}, "
          f"off its plane {res.min():+.3f}..{res.max():+.3f}")
    if -res.min() > cfg.get("panel_dip", 0.02):
        sys.exit(f"ASM panel {p['name']} hangs off an edge ({-res.min():.3f} below its plane); move it with panel_spots.py")
    rest = z + cfg.get("panel_lift", 0.003)
    cz_ = rest.copy()
    fall = cfg.get("panel_slope", 1.0) * min(sx / NX, sy / NY)
    for _ in range(NX + NY):
        pad = np.pad(cz_, 1, mode="edge")
        nb = np.maximum.reduce([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]])
        cz_ = np.maximum(rest, nb - fall)
    V = [[bm.verts.new((gx[i], gy[j], cz_[j, i])) for i in range(NX + 1)] for j in range(NY + 1)]
    for j in range(NY):
        for i in range(NX):
            vs = [V[j][i], V[j][i + 1], V[j + 1][i + 1], V[j + 1][i]]
            uvs = [cell_map("panel", (ii / NX) * 2 - 1, (jj / NY) * 2 - 1) for ii, jj in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            face(bm, uvl, uv2l, cl, vs, uvs, [(0, 0)] * 4, red, Vector((0, 0, 1)))
bmesh.ops.triangulate(bm, faces=bm.faces)
parts.append(finish(bm, "panels"))

# ---- lo: black mask, UV2 (0, 0) ----------------------------------------------------------------
me = lo.data
if "UV2" not in me.uv_layers:
    me.uv_layers.new(name="UV2")
uv2 = me.uv_layers["UV2"].data
uv2.foreach_set("uv", np.tile(uv2_store(0.0, 0.0), len(uv2)).astype(np.float32))
me.uv_layers.active = me.uv_layers["UVMap"]
ca = me.color_attributes.new("Color", 'BYTE_COLOR', 'CORNER')
ca.data.foreach_set("color", np.tile([0.0, 0.0, 0.0, 1.0], len(ca.data)).astype(np.float32))

bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
lo.select_set(True); bpy.context.view_layer.objects.active = lo
bpy.ops.object.join()
ob = lo; ob.name = cfg["name"]; ob.data.name = cfg["name"]
me = ob.data
me.color_attributes.active_color = me.color_attributes["Color"]
me.color_attributes.render_color_index = me.color_attributes.find("Color")
me.uv_layers.active = me.uv_layers["UVMap"]; me.uv_layers["UVMap"].active_render = True
print("ASM uv layers", [u.name for u in me.uv_layers], "colors", [c.name for c in me.color_attributes])

# ---- material -----------------------------------------------------------------------------------
ob.data.materials.clear()
mat = bpy.data.materials.new(cfg["name"]); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]


def image(fn, data):
    im = bpy.data.images.load(os.path.join(cfg["work"], fn))
    if data:
        im.colorspace_settings.name = 'Non-Color'
    im.name = f"{cfg['name']}_{fn[:-4]}"
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = im
    return n


alb = image("albedo.png", False)
nt.links.new(alb.outputs[0], bsdf.inputs["Base Color"])
nmap = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(image("normal.png", True).outputs[0], nmap.inputs["Color"])
nt.links.new(nmap.outputs[0], bsdf.inputs["Normal"])
sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(image("orm.png", True).outputs[0], sep.inputs[0])
nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
ob.data.materials.append(mat)

tris = sum(len(p.vertices) - 2 for p in me.polygons)
print(f"ASM tris {tris}")
out = os.path.join(lib.REPO, "assets", "units", cfg["name"] + ".glb")
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True, export_tangents=True,
                          export_vertex_color='NAME', export_vertex_color_name="Color",
                          export_all_vertex_colors=False, export_image_format='AUTO')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(cfg["work"], "final.blend"))
r = subprocess.run(["python3", "-I",os.path.join(lib.HERE, "verify_glb.py"), cfg["name"]])
sys.exit(r.returncode)
