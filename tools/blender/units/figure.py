"""Soldier figures: generated source GLB -> assets/units/<unit>.glb and its kit variants (docs/art-direction.md, Unit models).

    blender --background --factory-startup --python figure.py -- <unit> [--crude]

A squad is four figures on fixed slots: the plain figure (<unit>, the rifle squad's) and, for the assault squad, the
same figure with a drone launch tube on its back (each `variants` entry, e.g. assault_soldier). Both files come out of
one run with one atlas layout, so the game draws a squad mixing them under one material. Config is the units.json
entry's `figure` block:
  yaw       degrees about Blender Z that turn the source's chest onto +Y (glTF/Godot -Z, the front)
  tris      triangle budget of one figure (four per squad, up to ~10 squads on screen)
  tex       atlas size, px; the right 1/16 is kept for flat kit colours (the tube)
  paint     flat tones (sRGB 0..255): uniform, helmet, kit (plate carrier, pouches, pack), gun, boots, skin;
            `kit_hue`, `kit_sat` pick the carrier out of the source colour; `head_h`, `boots_h` are heights as
            fractions of the figure
  variants  {<unit>: {tube: {length_m, diameter_m, bottom_m, colour, cap}}}: a cylinder strapped upright on the back,
            real size, its side `colour`, its end caps `cap`
`--crude` skips the bake and paints the whole figure the uniform tone: the farthest-zoom shape test.

Steps: import, yaw, scale to 1.8 m = 0.225 units with the body (not the rifle) centred on the origin and the soles on
y = 0, voxel remesh, decimate, smart UV, bake the source colour, AO and height onto the figure, repaint by class (flat
tone x AO: a camouflage pattern reads as filth from the battle camera), COLOR_0 black, export, add each variant's kit
and export it, then check every written file. Previews go to the work directory.
"""
import bpy, bmesh, json, math, os, struct, sys
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
HEIGHT = 0.225  # 1.8 m, 1 tile = 8 m
M = HEIGHT / 1.8  # model units per metre
KIT_U = 15.0 / 16.0  # atlas u from here on: flat kit colours, no figure islands

argv = sys.argv[sys.argv.index("--") + 1:]
name = argv[0]
crude = "--crude" in argv
cfg = json.load(open(os.path.join(HERE, "units.json")))[name]
fig = cfg["figure"]
work = os.path.join(os.environ.get("AP_UNIT_SCRATCH") or os.path.expanduser("~/.cache/ap-scratch/soldiers"), name)
os.makedirs(work, exist_ok=True)
N = fig.get("tex", 512)
p = fig.get("paint", {})


def mesh_co(ob):
    co = np.empty(len(ob.data.vertices) * 3); ob.data.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def select_only(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active = ob


# ---- import, yaw, scale, centre -----------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.expanduser(cfg["source"]))
for o in [o for o in bpy.data.objects if o.type != 'MESH']:
    bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
select_only(meshes[0])
for o in meshes:
    o.select_set(True)
bpy.ops.object.join()
hi = bpy.context.object; hi.name = "hi"
# Tripo leaves an identity node; anything else would be export junk too, so it is zeroed, not baked
hi.parent = None; hi.location = (0, 0, 0)
hi.rotation_mode = 'XYZ'  # the glTF importer leaves quaternion mode, which ignores rotation_euler
hi.rotation_euler = (0, 0, math.radians(fig.get("yaw", 0.0))); hi.scale = (1, 1, 1)
select_only(hi)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = mesh_co(hi)
z0, z1 = co[:, 2].min(), co[:, 2].max()
k = HEIGHT / (z1 - z0)
# The body, not the bbox, sits on the slot: a rifle held out front would otherwise shift the man.
band = (co[:, 2] > z0 + 0.3 * (z1 - z0)) & (co[:, 2] < z0 + 0.8 * (z1 - z0))
cx, cy = np.median(co[band, 0]), np.median(co[band, 1])
hi.location = (-cx * k, -cy * k, -z0 * k); hi.scale = (k, k, k)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = mesh_co(hi)
print("FIG model bbox", co.min(0).round(4).tolist(), co.max(0).round(4).tolist())

# ---- low-poly figure ----------------------------------------------------------------------------------
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "lo"
bpy.context.collection.objects.link(lo)
select_only(lo)
tris0 = sum(len(q.vertices) - 2 for q in lo.data.polygons)
# A one-step collapse of 1.5 M generated triangles leaves lumps and spikes; a voxel remesh (~1 cm) first gives the
# collapse a clean closed surface, and sub-centimetre straps it cannot hold are sub-pixel in the game anyway.
rm = lo.modifiers.new("rm", 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = fig.get("voxel_m", 0.012) * M
bpy.ops.object.modifier_apply(modifier="rm")
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.quads_convert_to_tris(); bpy.ops.object.mode_set(mode='OBJECT')
for _ in range(3):
    now = len(lo.data.polygons)
    if now <= fig["tris"]:
        break
    dec = lo.modifiers.new("dec", 'DECIMATE'); dec.ratio = fig["tris"] / now * 0.98
    bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50))
# small loose bits the decimation severed are sub-pixel and cost shadow triangles
bm = bmesh.new(); bm.from_mesh(lo.data)
bm.faces.ensure_lookup_table()
seen = set(); islands = []
for f in bm.faces:
    if f.index in seen:
        continue
    stack, isl = [f], []
    seen.add(f.index)
    while stack:
        g = stack.pop(); isl.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h.index not in seen:
                    seen.add(h.index); stack.append(h)
    islands.append(isl)
small = [f for isl in islands if sum(g.calc_area() for g in isl) < fig.get("min_island", 2e-5) for f in isl]
bmesh.ops.delete(bm, geom=small, context='FACES')
bm.to_mesh(lo.data); bm.free()
print("FIG tris", tris0, "->", len(lo.data.polygons), "islands", len(islands), "dropped faces", len(small))
# the collapse moves the soles and the helmet top inwards: re-fit to 1.8 m standing on y = 0
co = mesh_co(lo)
k2 = HEIGHT / (co[:, 2].max() - co[:, 2].min())
lo.scale = (k2, k2, k2); lo.location = (0, 0, -co[:, 2].min() * k2)
select_only(lo)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ---- UV: figure islands left of KIT_U ---------------------------------------------------------------------
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.012)
bpy.ops.object.mode_set(mode='OBJECT')
uv = np.empty(len(lo.data.loops) * 2, np.float32); lo.data.uv_layers.active.data.foreach_get("uv", uv)
lo.data.uv_layers.active.data.foreach_set("uv", uv * (KIT_U - 0.01))

# ---- bake and paint -----------------------------------------------------------------------------------------
srgb = lambda c: np.array(c, np.float32) / 255.0
lin = lambda c: np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
enc = lambda c: np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.clip(c, 0, None), 1 / 2.4) - 0.055)
UNIFORM = p.get("uniform", [110, 109, 70])

if crude:
    alb = np.ones((N, N, 3), np.float32) * srgb(UNIFORM)
else:
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 1
    try:
        pr = bpy.context.preferences.addons['cycles'].preferences
        pr.compute_device_type = 'OPTIX'; pr.get_devices()
        for d in pr.devices:
            d.use = d.type == 'OPTIX'
        sc.cycles.device = 'GPU'
    except Exception as e:  # CPU still works, only slower
        print("FIG no GPU:", e)
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.light_settings.distance = HEIGHT * 0.12
    img = bpy.data.images.new("bake", N, N, alpha=True, float_buffer=True)
    img.colorspace_settings.name = 'Non-Color'
    lm = bpy.data.materials.new("lo_bake"); lm.use_nodes = True
    lt = lm.node_tree
    tn = lt.nodes.new("ShaderNodeTexImage"); tn.image = img; lt.nodes.active = tn
    lo.data.materials.clear(); lo.data.materials.append(lm)
    src_img = next(i for i in bpy.data.images if i.size[0] > 0 and i.name != "bake")
    hm = bpy.data.materials.new("hi_bake"); hm.use_nodes = True
    ht = hm.node_tree
    emit = ht.nodes.new("ShaderNodeEmission")
    ht.links.new(emit.outputs[0], ht.nodes["Material Output"].inputs[0])
    st = ht.nodes.new("ShaderNodeTexImage"); st.image = src_img
    geo = ht.nodes.new("ShaderNodeNewGeometry")
    hi.data.materials.clear(); hi.data.materials.append(hm)

    def bake(kind, to_lo=True, **kw):
        # transparent, not black: alpha then tells the islands from the empty atlas. The AO bake hides hi, which lies
        # on the same surface and would shade everything.
        img.pixels.foreach_set(np.zeros(N * N * 4, np.float32))
        hi.hide_render = not to_lo
        bpy.ops.object.select_all(action='DESELECT')
        lo.select_set(True); bpy.context.view_layer.objects.active = lo
        if to_lo:
            hi.select_set(True)
        bpy.ops.object.bake(type=kind, use_selected_to_active=to_lo, cage_extrusion=HEIGHT * 0.02 if to_lo else 0.0,
                            max_ray_distance=HEIGHT * 0.06 if to_lo else 0.0, margin=2, margin_type='EXTEND',
                            target='IMAGE_TEXTURES', use_clear=False, **kw)
        hi.hide_render = False
        a = np.empty(N * N * 4, np.float32); img.pixels.foreach_get(a)
        return a.reshape(N, N, 4)[::-1].copy()  # PNG row order

    ht.links.new(st.outputs[0], emit.inputs[0]); src = bake('EMIT')
    ht.links.new(geo.outputs["Position"], emit.inputs[0]); pos = bake('EMIT')
    sc.cycles.samples = 64
    ao = bake('AO', to_lo=False)[..., 0]
    used = src[..., 3] > 0.5
    c = src[..., :3]  # sRGB values (the source texture is read as colour, emitted unchanged)
    mx, mn = c.max(-1), c.min(-1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    h = pos[..., 2] / HEIGHT
    cls = np.full(mx.shape, 0, np.int8)                       # 0 uniform
    kit = (np.abs(hue - p.get("kit_hue", 66)) < p.get("kit_hue_tol", 14)) & (sat > p.get("kit_sat", 0.33))
    # The carrier is also where it sits, not only its colour: the torso core between the arms, from the belt to the
    # collar, front face to pack (the forearms across the chest stand further forward).
    x, y = pos[..., 0], pos[..., 1]
    torso = (np.abs(x) < p.get("torso_half_m", 0.24) * M) & (h > 0.55) & (h < 0.79) & (y < p.get("chest_front_m", 0.27) * M)
    cls[kit | torso] = 1                                      # 1 plate carrier, pouches, pack
    cls[(mx < p.get("gun_v", 0.30)) & (sat < p.get("gun_sat", 0.30))] = 3   # 3 rifle, gloves, pads
    cls[h < p.get("boots_h", 0.075)] = 4                      # 4 boots
    skin = (hue < 40) & (sat > 0.15) & (mx > 0.3) & (h > p.get("head_h", 0.82))
    head = (h > p.get("head_h", 0.82)) & ~skin & (cls != 3)
    cls[head] = 2                                             # 2 helmet
    # Camouflage blotches the colour test calls kit, and dark lettering on the pouches it calls gun, would come back as
    # flecks (and markings are banned); a 7x7 majority over cloth and gun keeps whole carriers, helmets, rifles and
    # gloves and drops the flecks.
    cloth = used & (cls <= 3)
    votes = []
    for cl in range(4):
        a = np.pad((cloth & (cls == cl)).astype(np.float32), 3)
        s = np.pad(np.cumsum(np.cumsum(a, 0), 1), ((1, 0), (1, 0)))
        votes.append(s[7:, 7:] - s[:-7, 7:] - s[7:, :-7] + s[:-7, :-7])
    cls[cloth] = np.argmax(np.stack(votes, -1), -1)[cloth]
    cls[skin] = 5                                             # 5 face
    tones = [p.get(kname, dflt) for kname, dflt in (("uniform", UNIFORM), ("kit", [88, 88, 58]), ("helmet", UNIFORM),
                                                     ("gun", [30, 31, 31]), ("boots", [48, 46, 40]), ("skin", [146, 110, 88]))]
    flat = lin(srgb(tones))[cls]
    # occlusion only darkens: open faces keep the tone, folds and armpits go to ~60 %
    shade = 1.0 - p.get("ao_gain", 0.45) * (1.0 - np.clip(ao, 0.0, 1.0) ** p.get("ao_gamma", 0.7))
    alb = enc(flat * shade[..., None])
    alb[~used] = srgb(UNIFORM)  # mips of the empty atlas bleed into island edges: keep them the figure's tone
    dbg = np.array([[1, 1, 1], [0, 1, 0], [0, 0, 1], [0, 0, 0], [1, 0.5, 0], [1, 0, 0]], np.float32)[cls]
    print("FIG class share", {i: round(float((cls[used] == i).mean()), 3) for i in range(6)})

# Flat kit colours in the right strip: one block per colour, sampled at its centre (PNG rows from the top).
kit_cols = []
for v in fig.get("variants", {}).values():
    t = v["tube"]
    kit_cols += [tuple(t["colour"]), tuple(t["cap"])]
kit_cols = list(dict.fromkeys(kit_cols))
BLOCK = N // 16


def kit_uv(colour):
    """Blender UV of a kit colour's block centre."""
    i = kit_cols.index(tuple(colour))
    return (KIT_U + 0.5 / 16.0, 1.0 - (i + 0.5) * BLOCK / N)


for i, col in enumerate(kit_cols):
    alb[i * BLOCK:(i + 1) * BLOCK, int(KIT_U * N):] = srgb(col)


# ---- material, COLOR_0, export -----------------------------------------------------------------------
def write_png(arr, fn, sub=""):
    """Godot names an extracted texture <glb stem>_<png stem>, so every unit's atlas is albedo.png in its own folder."""
    os.makedirs(os.path.join(work, sub), exist_ok=True)
    im = bpy.data.images.new(fn, N, N, alpha=False)
    rgba = np.concatenate([np.clip(arr, 0, 1), np.ones((N, N, 1), np.float32)], -1)[::-1]
    im.pixels.foreach_set(rgba.ravel().astype(np.float32))
    im.filepath_raw = os.path.join(work, sub, fn + ".png"); im.file_format = 'PNG'; im.save()
    return im


if not crude:
    write_png(dbg, "classes")
bpy.data.objects.remove(hi)


def finish(ob, unit):
    """Material with this unit's own copy of the atlas (Godot extracts one per file), COLOR_0 black, export."""
    albedo = write_png(alb, "albedo", unit)
    albedo.name = "%s_albedo" % unit
    mat = bpy.data.materials.new(unit); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = albedo
    nt.links.new(tn.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = p.get("rough", 0.85)
    bsdf.inputs["Metallic"].default_value = 0.0
    ob.data.materials.clear(); ob.data.materials.append(mat)
    me = ob.data
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    # R = 0 (no team colour; the game sets it on the fallen), G and B = 0: no tracks, no wheels
    ca = me.color_attributes.new("Color", 'BYTE_COLOR', 'CORNER')
    ca.data.foreach_set("color", np.tile([0.0, 0.0, 0.0, 1.0], len(ca.data)).astype(np.float32))
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = me.color_attributes.find("Color")
    ob.name = unit; me.name = unit
    path = os.path.join(REPO, "assets", "units", unit + ".glb")
    select_only(ob)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_apply=True, export_tangents=True,
                              export_vertex_color='NAME', export_vertex_color_name="Color",
                              export_all_vertex_colors=False, export_image_format='AUTO')
    return path


def tube(t, base):
    """The launch tube: upright behind the pack, real size. Side faces take the tube colour, the ends the cap."""
    r = t["diameter_m"] * 0.5 * M
    co = mesh_co(base)
    torso = (co[:, 2] > 0.5 * HEIGHT) & (co[:, 2] < 0.8 * HEIGHT)
    # the pack's back face: a high percentile, so a strap or an elbow behind the back does not push the tube off
    back = np.percentile(-co[torso, 1], 97)
    z0 = t["bottom_m"] * M
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r, depth=t["length_m"] * M,
                          matrix=Matrix.Translation((0.0, -(back + r * 0.6), z0 + t["length_m"] * M * 0.5)))
    me = bpy.data.meshes.new("tube"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("tube", me); bpy.context.collection.objects.link(ob)
    ul = me.uv_layers.new(name=base.data.uv_layers.active.name)
    for poly in me.polygons:
        at = kit_uv(t["cap"] if abs(poly.normal.z) > 0.5 else t["colour"])
        for li in poly.loop_indices:
            ul.data[li].uv = at
    for poly in me.polygons:
        poly.use_smooth = abs(poly.normal.z) < 0.5
    return ob


outs = {name: finish(lo, name)}
for unit, v in fig.get("variants", {}).items():
    body = bpy.data.objects.new(unit, lo.data.copy()); bpy.context.collection.objects.link(body)
    t = tube(v["tube"], body)
    bpy.ops.object.select_all(action='DESELECT')
    t.select_set(True); body.select_set(True); bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    outs[unit] = finish(body, unit)

# ---- check the written files, never Blender's numbers ---------------------------------------------------
fails = []


def check(ok, msg):
    print(("ok   " if ok else "FAIL ") + msg)
    if not ok:
        fails.append(msg)


for unit, path in outs.items():
    data = open(path, "rb").read(); off = 12; g = None
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        if ctype == 0x4E4F534A:
            g = json.loads(data[off + 8:off + 8 + clen])
        off += 8 + clen
    prims = [q for m in g["meshes"] for q in m["primitives"]]
    check(len(prims) == 1, "%s one primitive (%d)" % (unit, len(prims)))
    check(len(g.get("materials", [])) == 1, "%s one material" % unit)
    check(not [n for n in g["nodes"] if {"translation", "rotation", "scale", "matrix"} & n.keys()], "%s no node transforms" % unit)
    at = prims[0]["attributes"]
    check(sorted(a for a in at if a.startswith("COLOR")) == ["COLOR_0"], "%s only COLOR_0" % unit)
    pa = g["accessors"][at["POSITION"]]
    check(abs(pa["min"][1]) < 1e-4, "%s soles on y = 0 (%.5f)" % (unit, pa["min"][1]))
    t = fig.get("variants", {}).get(unit, {}).get("tube")
    top = max(HEIGHT, (t["bottom_m"] + t["length_m"]) * M) if t else HEIGHT
    check(abs(pa["max"][1] - top) < 0.002, "%s top %.4f (figure 1.8 m, tube top %.3f)" % (unit, pa["max"][1], top))
    ntri = g["accessors"][prims[0]["indices"]]["count"] // 3
    check(ntri <= fig["tris"] + 64, "%s triangles %d <= %d + kit" % (unit, ntri, fig["tris"]))
    check(g["images"] and all(max(bpy.data.images[im["name"]].size) <= 1024 for im in g["images"] if im["name"] in bpy.data.images), "%s texture <= 1024 px" % unit)
    mt = g["materials"][0].get("pbrMetallicRoughness", {})
    check(mt.get("metallicFactor", 1.0) == 0.0, "%s metallic 0" % unit)
    print("FIG wrote", path, "tris", ntri, "verts", pa["count"], "bytes", len(data),
          "xz", [round(pa["min"][0], 4), round(pa["max"][0], 4), round(pa["min"][2], 4), round(pa["max"][2], 4)])

# ---- previews: straight down (image up = front), from the front, and the battle camera ---------------------------
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'; sc.render.resolution_x = sc.render.resolution_y = 384
sc.view_settings.view_transform = 'Standard'
sc.world = bpy.data.worlds.new("pw"); sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.58, 0.62, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.6
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sun.data.energy = 6.0
sun.rotation_euler = (math.radians(40), 0, math.radians(150)); sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); cam.data.type = 'ORTHO'; cam.data.ortho_scale = HEIGHT * 1.8
sc.collection.objects.link(cam); sc.camera = cam
for unit in outs:
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = o.name != unit
    for tag, rot in (("top", (0, 0, 0)), ("front", (math.radians(90), 0, math.radians(180))),
                     ("iso", (math.radians(38), 0, math.radians(-135))), ("iso_back", (math.radians(38), 0, math.radians(45)))):
        cam.rotation_euler = rot
        cam.location = Vector((0, 0, HEIGHT * 0.6)) + cam.rotation_euler.to_matrix() @ Vector((0, 0, 2.0))
        sc.render.filepath = os.path.join(work, "prev_%s_%s.png" % (unit, tag))
        bpy.ops.render.render(write_still=True)
sys.exit(1 if fails else 0)
