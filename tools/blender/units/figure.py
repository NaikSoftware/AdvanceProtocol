"""Soldier figures: generated source GLB -> assets/units/<unit>.glb and its kit variants (docs/art-direction.md, Unit models).

    blender --background --factory-startup --python figure.py -- <unit> [--crude]

A squad is four figures on fixed slots: the plain figure (<unit>, the rifle squad's) and, for the assault squad, the
same figure with a drone launch tube on its back (each `variants` entry, e.g. assault_soldier). Both files come out of
one run with one atlas layout, so the game draws a squad mixing them under one material. Config is the units.json
entry's `figure` block:
  out_dir, prefix  national set: the files go to assets/units/<out_dir>/ and `prefix` is cut off the unit keys
  yaw       degrees about Blender Z that turn the source's chest onto +Y (glTF/Godot -Z, the front)
  crown_rim_m, crown_rim_scale  metres above which the head is drawn in towards its axis (the helmet's rim flare)
  crown_cap_m, crown_squash  metres of the 1.8 m figure above which the helmet is pressed down to `crown_squash` of its
            height before the fit (a night-vision mount would otherwise be the crown and set the height)
  tris      triangle budget of one figure (four per squad, up to ~10 squads on screen)
  tex       atlas size, px; the right 1/16 is kept for flat kit colours (the tube)
  paint     flat tones (sRGB 0..255): uniform, helmet, kit (plate carrier, pouches, pack), gun, boots, skin;
            `kit_hue`, `kit_sat` pick the carrier out of the source colour; `gun_v` is the value below which low-saturation
            texels are the rifle; `rifle_front_m` and `rifle_capsule_m` pick a cloth-coloured rifle by position; `head_h`, `boots_h` are heights as
            fractions of the figure; `top_lift` multiplies (linear) the cloth tones of up-facing texels,
            `top_fade` (0..1) turns them towards grey
  variants  {<unit>: {tube: {length_m, diameter_m, bottom_m, colour, cap, shades}}}: a cylinder strapped upright on the back,
            real size, its side `colour`, its end caps `cap`; {<unit>: {body: {...}}}: the fallen soldier lying on his
            side; {<unit>: {crouch: {hip_m, knee_m, thigh_deg, shin_deg}}}: the second pose, crouched;
            {<unit>: {kneel: {hip_m, knee_m, front_sign, split_x_m, front, rear}}}: the same slot, kneeling on one knee
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
# A national set's figures live in assets/units/<out_dir>/ under the set 0 slugs: `prefix` is cut off every unit key
# (set1_rifle_soldier -> set1/rifle_soldier.glb), so a set's atlas names match set 0's.
PREFIX = fig.get("prefix", "")
OUT = os.path.join(REPO, "assets", "units", fig.get("out_dir", ""))
slug = lambda unit: unit[len(PREFIX):] if unit.startswith(PREFIX) else unit


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
if "crown_cap_m" in fig:
    # A mount or a spike on the helmet would set the 1.8 m and leave the man shorter under it: everything above
    # `crown_cap_m` is pressed down to `crown_squash` of its height before the fit.
    cap = z0 + fig["crown_cap_m"] / 1.8 * (z1 - z0)
    top = co[:, 2] > cap
    co[top, 2] = cap + (co[top, 2] - cap) * fig.get("crown_squash", 0.15)
    if "crown_rim_m" in fig:
        # The flare of a high-cut helmet (rails, ear flaps) is as wide as the torso seen from above and reads as a hat brim:
        # above `crown_rim_m` the head is drawn in towards its own axis, fully by 0.1 m higher, to `crown_rim_scale`.
        zn = (co[:, 2] - z0) / (z1 - z0) * 1.8
        head = (zn > fig["crown_rim_m"]) & (zn < fig["crown_rim_m"] + 0.15)
        ax, ay = np.median(co[head, 0]), np.median(co[head, 1])
        t = np.clip((zn - fig["crown_rim_m"]) / 0.1, 0.0, 1.0)
        k_rim = 1.0 + (fig.get("crown_rim_scale", 0.8) - 1.0) * t * t * (3.0 - 2.0 * t)
        co[:, 0] = ax + (co[:, 0] - ax) * k_rim
        co[:, 1] = ay + (co[:, 1] - ay) * k_rim
    hi.data.vertices.foreach_set("co", co.ravel()); hi.data.update()
    z1 = co[:, 2].max()
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

cls_map = None  # the paint classes per texel; the fallen body uses them to find the rifle
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
    ht.links.new(geo.outputs["Normal"], emit.inputs[0]); nrm = bake('EMIT')
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
    # A rifle the same colour as the cloth has no colour to find it by: the part of it that stands out in front of
    # the torso, `rifle_front_m` = [y_min, z_min, z_max] in metres, takes the rifle class by where it is.
    if "rifle_front_m" in p:
        y0, z0, z1 = p["rifle_front_m"]
        cls[used & (y > y0 * M) & (h > z0 / 1.8) & (h < z1 / 1.8) & (cls <= 3)] = 3
    # A rifle the colour of the cloth is found by where it lies: `rifle_capsule_m` = [from, to, radius, y_min], metres in
    # the figure's frame (front = +y), a capsule around the rifle's axis, cut off behind `y_min` so the chest stays cloth.
    if "rifle_capsule_m" in p:
        ca, cb, cr, cy0 = p["rifle_capsule_m"]
        P = np.stack([x, y, pos[..., 2]], -1) / M
        A, Bv = np.array(ca, np.float32), np.array(cb, np.float32)
        ab = Bv - A
        tt = np.clip(((P - A) @ ab) / (ab @ ab), 0.0, 1.0)
        dist = np.linalg.norm(P - (A + tt[..., None] * ab), axis=-1)
        cls[used & (dist < cr) & (y > cy0 * M) & (cls <= 3)] = 3
    cls_map = cls
    tones = [p.get(kname, dflt) for kname, dflt in (("uniform", UNIFORM), ("kit", [88, 88, 58]), ("helmet", UNIFORM),
                                                     ("gun", [30, 31, 31]), ("boots", [48, 46, 40]), ("skin", [146, 110, 88]))]
    flat = lin(srgb(tones))[cls]
    # What the camera sees of a figure is its up-facing tops (helmet crown, shoulders, pack top), and in the uniform's
    # middle value they sit on the ground's own tone: they are lifted, as the vehicle tops are, until the contrast gate
    # passes. Cloth only; the rifle, boots and face keep theirs.
    up = np.clip((nrm[..., 2] - 0.25) / 0.5, 0.0, 1.0)
    top = up * (cls <= 2)
    flat = flat * (1.0 + (p.get("top_lift", 1.0) - 1.0) * top)[..., None]
    # olive tops share the grass's hue: the vehicles' tops passed only near-neutral, so they fade towards grey of the
    # same luminance (`top_fade`); sides keep the uniform's olive
    grey = (flat @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    flat = flat + (grey - flat) * (p.get("top_fade", 0.0) * top)[..., None]
    # occlusion only darkens: open faces keep the tone, folds and armpits go to ~60 %
    shade = 1.0 - p.get("ao_gain", 0.45) * (1.0 - np.clip(ao, 0.0, 1.0) ** p.get("ao_gamma", 0.7))
    alb = enc(flat * shade[..., None])
    alb[~used] = srgb(UNIFORM)  # mips of the empty atlas bleed into island edges: keep them the figure's tone
    dbg = np.array([[1, 1, 1], [0, 1, 0], [0, 0, 1], [0, 0, 0], [1, 0.5, 0], [1, 0, 0]], np.float32)[cls]
    print("FIG class share", {i: round(float((cls[used] == i).mean()), 3) for i in range(6)})

# Flat kit colours in the right strip: one block per colour, sampled at its centre (PNG rows from the top).
kit_cols = []


def tube_shades(t):
    """The tube's side colours from lit to shaded: `shades` multiplies the colour (a flat tube reads as a paper roll)."""
    return [tuple(int(round(ch * m)) for ch in t["colour"]) for m in t.get("shades", [1.0])]


for v in fig.get("variants", {}).values():
    if "tube" in v:
        kit_cols += tube_shades(v["tube"]) + [tuple(v["tube"]["cap"])]
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
    albedo.name = "%s_albedo" % slug(unit)
    mat = bpy.data.materials.new(slug(unit)); mat.use_nodes = True
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
    ob.name = slug(unit); me.name = slug(unit)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, slug(unit) + ".glb")
    select_only(ob)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_apply=True, export_tangents=True,
                              export_vertex_color='NAME', export_vertex_color_name="Color",
                              export_all_vertex_colors=False, export_image_format='AUTO')
    return path


def tube(t, base):
    """The launch tube: behind the pack, real size. Side faces and the top end take the tube colour, the bottom end
    the cap."""
    r = t["diameter_m"] * 0.5 * M
    co = mesh_co(base)
    torso = (co[:, 2] > 0.5 * HEIGHT) & (co[:, 2] < 0.8 * HEIGHT)
    # the pack's back face: a high percentile, so a strap or an elbow behind the back does not push the tube off
    back = np.percentile(-co[torso, 1], 97)
    z0 = t["bottom_m"] * M
    bm = bmesh.new()
    # beside the pack and leaning out (side_m, tilt_deg), pivoting at its bottom: straight up the middle it hid the
    # helmet from behind, and the camera mostly sees a squad's back
    side = t.get("side_m", 0.0) * M
    lean = Matrix.Rotation(math.radians(t.get("tilt_deg", 0.0)), 4, 'Y')
    at = Matrix.Translation((side, -(back + r * 0.6), z0)) @ lean @ Matrix.Translation((0.0, 0.0, t["length_m"] * M * 0.5))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r, depth=t["length_m"] * M, matrix=at)
    me = bpy.data.meshes.new("tube"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("tube", me); bpy.context.collection.objects.link(ob)
    ul = me.uv_layers.new(name=base.data.uv_layers.active.name)
    shades = tube_shades(t)
    light = Vector(t.get("light", [0.6, -0.5, 0.0])).normalized()
    for poly in me.polygons:
        # only the bottom end is dark: the top end faces the camera and reads as the tube's colour
        if poly.normal.z < -0.5:
            at = kit_uv(t["cap"])
        elif poly.normal.z > 0.5 or len(shades) == 1:
            at = kit_uv(shades[0])
        else:
            # across the cylinder: the facets turned from the light step down through the shades
            lit = 0.5 + 0.5 * poly.normal.dot(light)
            at = kit_uv(shades[min(len(shades) - 1, int((1.0 - lit) * len(shades)))])
        for li in poly.loop_indices:
            ul.data[li].uv = at
    for poly in me.polygons:
        poly.use_smooth = abs(poly.normal.z) < 0.5
    return ob


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def make_body(b, base, unit):
    """A fallen soldier, not the standing one rotated flat: knees bent, face down and rolled onto one side so an
    arm lies under the torso, the rifle cut away and lying flat beside him. Same vertices' UVs, so the same atlas."""
    # the rifle: dark (gun-class) faces well off the body axis at hand height; gloves on the chest stay with the man
    bm = bmesh.new(); bm.from_mesh(base.data)
    uvl = bm.loops.layers.uv.active
    rifle = set()
    for f in bm.faces:
        u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
        v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
        c = f.calc_center_median()
        dark = cls_map is not None and cls_map[min(N - 1, int((1.0 - v) * N)), min(N - 1, int(u * N))] == 3
        if dark and math.hypot(c.x, c.y) > b.get("rifle_r_m", 0.3) * M and 0.3 * HEIGHT < c.z < 0.85 * HEIGHT:
            rifle.add(f.index)
    # only the largest connected piece is the rifle: dark knee pads and gloves would come away as floating shards
    bm.faces.ensure_lookup_table()
    best, seen_f = set(), set()
    for i in rifle:
        if i in seen_f:
            continue
        piece, stack = set(), [i]
        seen_f.add(i)
        while stack:
            j = stack.pop(); piece.add(j)
            for e in bm.faces[j].edges:
                for g in e.link_faces:
                    if g.index in rifle and g.index not in seen_f:
                        seen_f.add(g.index); stack.append(g.index)
        if len(piece) > len(best):
            best = piece
    rifle = best
    bm.free()

    def part(keep_rifle):
        bm = bmesh.new(); bm.from_mesh(base.data); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if (f.index in rifle) != keep_rifle], context='FACES')
        return bm

    man = part(False)
    knee, band = b.get("knee_m", 0.5) * M, 0.03
    near = [v.co.y for v in man.verts if abs(v.co.z - knee) < 0.01]
    py = sum(near) / max(1, len(near))
    bend = -math.radians(b.get("knee_deg", 45))
    for v in man.verts:
        w = smoothstep(knee + band, knee - band, v.co.z)
        if w > 0.0:
            a = bend * w
            y, z = v.co.y - py, v.co.z - knee
            v.co.y, v.co.z = py + y * math.cos(a) - z * math.sin(a), knee + y * math.sin(a) + z * math.cos(a)
    # face down (Blender +Y front goes to -Z, head to +Y), then a roll about the long axis
    lay = Matrix.Rotation(math.radians(b.get("roll_deg", 20)), 4, 'Y') @ Matrix.Rotation(-math.pi / 2, 4, 'X')
    bmesh.ops.transform(man, matrix=lay, verts=man.verts)
    xs = [v.co for v in man.verts]
    lo_v = Vector((min(c.x for c in xs), min(c.y for c in xs), min(c.z for c in xs)))
    hi_v = Vector((max(c.x for c in xs), max(c.y for c in xs), max(c.z for c in xs)))
    bmesh.ops.translate(man, vec=Vector((-(lo_v.x + hi_v.x) / 2, -(lo_v.y + hi_v.y) / 2, -lo_v.z)), verts=man.verts)
    half_x = (hi_v.x - lo_v.x) / 2

    gun = part(True)
    if gun.verts:
        pts = np.array([v.co[:] for v in gun.verts])
        ctr = Vector(pts.mean(0).tolist())
        axis = Vector(np.linalg.eigh(np.cov((pts - pts.mean(0)).T))[1][:, -1].tolist())
        flat = Vector((axis.x, axis.y, 0.0))
        bmesh.ops.translate(gun, vec=-ctr, verts=gun.verts)
        if flat.length > 1e-6:
            # the long axis onto the ground, then turned to lie along the body, a little askew
            tilt = axis.rotation_difference(flat).to_matrix().to_4x4()
            turn = math.radians(90.0 - b.get("rifle_yaw_deg", 10)) - math.atan2(flat.y, flat.x)
            bmesh.ops.transform(gun, matrix=Matrix.Rotation(turn, 4, 'Z') @ tilt, verts=gun.verts)
        zmin = min(v.co.z for v in gun.verts)
        at = b.get("rifle_at_m", [0.45, 0.2])
        bmesh.ops.translate(gun, vec=Vector((half_x + at[0] * M, at[1] * M, -zmin)), verts=gun.verts)
    gun_me = bpy.data.meshes.new(unit + "_rifle"); gun.to_mesh(gun_me); gun.free()
    man_me = bpy.data.meshes.new(unit)
    man.to_mesh(man_me); man.free()
    ob = bpy.data.objects.new(unit, man_me); bpy.context.collection.objects.link(ob)
    gob = bpy.data.objects.new(unit + "_rifle", gun_me); bpy.context.collection.objects.link(gob)
    bpy.ops.object.select_all(action='DESELECT')
    gob.select_set(True); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    print("FIG body", unit, "rifle faces", len(rifle), "tris", sum(len(q.vertices) - 2 for q in ob.data.polygons))
    return ob


def make_crouch(c, base, unit):
    """The same soldier crouched: thighs forward about the hip, shins back about the knee, feet back on the
    ground. Only vertices move, so the UVs and the atlas stay the plain figure's and one material covers both."""
    bm = bmesh.new(); bm.from_mesh(base.data)
    hip, knee, band = c.get("hip_m", 0.95) * M, c.get("knee_m", 0.5) * M, 0.03
    near_k = [v.co.y for v in bm.verts if abs(v.co.z - knee) < 0.01]
    near_h = [v.co.y for v in bm.verts if abs(v.co.z - hip) < 0.01]
    ky, hy = sum(near_k) / max(1, len(near_k)), sum(near_h) / max(1, len(near_h))
    shin, thigh = -math.radians(c.get("shin_deg", 95)), math.radians(c.get("thigh_deg", 55))

    def turn(co, py, pz, a):
        y, z = co.y - py, co.z - pz
        return py + y * math.cos(a) - z * math.sin(a), pz + y * math.sin(a) + z * math.cos(a)

    for v in bm.verts:
        z0 = v.co.z
        ws = smoothstep(knee + band, knee - band, z0)  # below the knee: the shin turns back
        if ws > 0.0:
            v.co.y, v.co.z = turn(v.co, ky, knee, shin * ws)
        wt = smoothstep(hip + band, hip - band, z0)  # below the hip: the whole leg turns forward
        if wt > 0.0:
            v.co.y, v.co.z = turn(v.co, hy, hip, thigh * wt)
    zmin = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, -zmin)), verts=bm.verts)
    me = bpy.data.meshes.new(unit); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(unit, me); bpy.context.collection.objects.link(ob)
    print("FIG crouch", unit, "top %.3f" % max(v.co.z for v in me.vertices))
    return ob


def make_kneel(c, base, unit):
    """A real kneel: the front leg's thigh forward and its shin leaning back, the rear leg's thigh near vertical and its
    shin lying back, the rear knee on the ground. The legs split at x = `split_x_m` (the gap between them;
    `front_sign` -1 makes the leg on the smaller x the front one); parts inside `rifle_capsule_m` stay with the torso. Angles in degrees: `front` and `rear` = [thigh from
    vertical, shin from vertical], positive forward."""
    bm = bmesh.new(); bm.from_mesh(base.data)
    hip, knee, band = c.get("hip_m", 0.95) * M, c.get("knee_m", 0.5) * M, 0.03
    fr, re = c["front"], c["rear"]
    sign = c.get("front_sign", -1)
    split = c.get("split_x_m", 0.0) * M

    def pivot(z, front):
        """Where this leg's axis crosses height z: the legs of a stride do not stand over each other, so one pivot for
        both would fling the leg that is stepping out."""
        ys = [v.co.y for v in bm.verts if abs(v.co.z - z) < 0.02 and ((v.co.x - split) * sign > 0) == front]
        return sum(ys) / max(1, len(ys))

    kys, hys = {w: pivot(knee, w) for w in (True, False)}, {w: pivot(hip, w) for w in (True, False)}
    cap = p.get("rifle_capsule_m")

    def turn(co, py, pz, a):
        y, z = co.y - py, co.z - pz
        return py + y * math.cos(a) - z * math.sin(a), pz + y * math.sin(a) + z * math.cos(a)

    def in_rifle(co):
        if cap is None:
            return False
        P = np.array([co.x, co.y, co.z]) / M
        A, Bv = np.array(cap[0]), np.array(cap[1])
        ab = Bv - A
        tt = min(1.0, max(0.0, float((P - A) @ ab) / float(ab @ ab)))
        return np.linalg.norm(P - (A + tt * ab)) < cap[2] + 0.03 and co.y > cap[3] * M

    side = {}
    for v in bm.verts:
        z0 = v.co.z
        if z0 > hip + band or in_rifle(v.co):
            continue
        wf = smoothstep(-0.02 * M, 0.02 * M, (v.co.x - c.get("split_x_m", 0.0) * M) * sign)
        thigh = math.radians(wf * fr[0] + (1 - wf) * re[0])
        shin_net = math.radians(wf * fr[1] + (1 - wf) * re[1])
        ky, hy = wf * kys[True] + (1 - wf) * kys[False], wf * hys[True] + (1 - wf) * hys[False]
        ws = smoothstep(knee + band, knee - band, z0)
        if ws > 0.0:
            v.co.y, v.co.z = turn(v.co, ky, knee, (shin_net - thigh) * ws)
        wt = smoothstep(hip + band, hip - band, z0)
        if wt > 0.0:
            v.co.y, v.co.z = turn(v.co, hy, hip, thigh * wt)
        side[v.index] = wf
    zmin = min(v.co.z for v in bm.verts)
    lows = {w: min([v.co.z for v in bm.verts if v.index in side and (side[v.index] > 0.5) == w] or [0.0]) for w in (True, False)}
    print("FIG kneel", unit, "front leg low %.3f rear leg low %.3f m (zmin %.3f m)" % ((lows[True] - zmin) / M, (lows[False] - zmin) / M, zmin / M))
    bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, -zmin)), verts=bm.verts)
    me = bpy.data.meshes.new(unit); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(unit, me); bpy.context.collection.objects.link(ob)
    print("FIG kneel", unit, "top %.3f m" % (max(v.co.z for v in me.vertices) / M))
    return ob


outs = {name: finish(lo, name)}
for unit, v in fig.get("variants", {}).items():
    if "body" in v:
        outs[unit] = finish(make_body(v["body"], lo, unit), unit)
        continue
    if "crouch" in v:
        outs[unit] = finish(make_crouch(v["crouch"], lo, unit), unit)
        continue
    if "kneel" in v:
        outs[unit] = finish(make_kneel(v["kneel"], lo, unit), unit)
        continue
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
    if "body" in fig.get("variants", {}).get(unit, {}):
        check(pa["max"][1] < 0.11, "%s lies low (top %.4f = %.2f m)" % (unit, pa["max"][1], pa["max"][1] / M))
    elif "kneel" in fig.get("variants", {}).get(unit, {}):
        check(0.65 * HEIGHT < pa["max"][1] < 0.85 * HEIGHT, "%s kneels (top %.2f m)" % (unit, pa["max"][1] / M))
    elif "crouch" in fig.get("variants", {}).get(unit, {}):
        check(0.6 * HEIGHT < pa["max"][1] < 0.92 * HEIGHT, "%s crouches (top %.2f m)" % (unit, pa["max"][1] / M))
    else:
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
            o.hide_render = o.name != slug(unit)
    for tag, rot in (("top", (0, 0, 0)), ("front", (math.radians(90), 0, math.radians(180))),
                     ("iso", (math.radians(38), 0, math.radians(-135))), ("iso_back", (math.radians(38), 0, math.radians(45)))):
        cam.rotation_euler = rot
        cam.location = Vector((0, 0, HEIGHT * 0.6)) + cam.rotation_euler.to_matrix() @ Vector((0, 0, 2.0))
        sc.render.filepath = os.path.join(work, "prev_%s_%s.png" % (unit, tag))
        bpy.ops.render.render(write_still=True)
sys.exit(1 if fails else 0)
