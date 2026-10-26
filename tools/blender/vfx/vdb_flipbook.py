"""Render a free JangaFX EmberGen VDB sequence (CC0) into per-frame PNGs for assemble.py.

Run: blender -b --factory-startup -P vdb_flipbook.py -- <vdb dir> <out dir> <name> key=value ...
keys: rotx (deg, 90 turns Y-up into Z-up), height (metres the sim's vertical extent maps to), pitch (camera
elevation, deg), cell (px), samples, frames (a:b:step, VDB file indices), cx/cz (fraction of the bbox the
frame is centred on), frame_m (width of the frame in metres), kind (fire|smoke|dust), dens (density gain),
col (r,g,b smoke albedo), gain (emission gain), top (overcast top-light strength).
Light is River overcast: a grey sky plus one large soft area light overhead, no sun.
"""
import sys, os, glob, math, bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
vdir, outdir, name = argv[0], argv[1], argv[2]
K = dict(a.split("=", 1) for a in argv[3:])
f = lambda k, d: float(K.get(k, d))
rotx, height, pitch = f("rotx", 90), f("height", 4.0), f("pitch", 45)
cell, samples = int(f("cell", 192)), int(f("samples", 96))
cellw = int(f("cellw", cell))  # cell is the height; cellw < cell gives a tall flipbook cell
vstretch = f("vstretch", 1.0)  # stretch the sim along its vertical axis: taller, more licking flames
kind = K.get("kind", "smoke")
dens_gain, gain, top = f("dens", 3.0), f("gain", 6.0), f("top", 1.0)
col = tuple(float(x) for x in K.get("col", "0.35,0.35,0.35").split(","))
_fa = K.get("frames", "0:0:1").split(":")
heat, tau = f("heat", 0.0), f("tau", 7.0)
lift, l0, l1 = f("lift", 0.0), f("l0", 0), f("l1", 40)  # the cloud rises by `lift` m between rendered frames l0 and l1
a, b, st = int(_fa[0]), int(_fa[1]), float(_fa[2])

files = sorted(glob.glob(vdir + "/*.vdb"), key=lambda p: int("".join(c for c in os.path.basename(p).rsplit(".", 1)[0].split("_")[-1] if c.isdigit()) or 0))
sel = [files[min(len(files) - 1, round(a + k * st))] for k in range(int((b - a) / st) + 1)] if b else files[::int(st)]

def set_lift(idx):
    """Rise of the whole volume: a ground burst's fireball lifts off instead of only spreading sideways."""
    t = min(max((idx - l0) / max(l1 - l0, 1), 0.0), 1.0)
    vo.location.z = lift * t * t * (3 - 2 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.object.volume_import(filepath=files[0], files=[{"name": os.path.basename(p)} for p in files], directory=vdir)
vo = bpy.context.object
vol = vo.data
vol.sequence_mode = "CLIP"
vol.frame_start, vol.frame_offset, vol.is_sequence = 1, 0, True
sc.frame_start, sc.frame_end = 1, len(files)
vo.rotation_euler = (math.radians(rotx), 0, 0)
sc.frame_set(1)
vol.grids.load()


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def hexc(h):
    return lin(tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)))


# --- shader
mat = bpy.data.materials.new("V")
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial")
shaders = []


def N(t, **kw):
    n = nt.nodes.new(t)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def mul(a, b):
    n = N("ShaderNodeMath", operation="MULTIPLY")
    for i, x in enumerate((a, b)):
        if isinstance(x, (int, float)):
            n.inputs[i].default_value = x
        else:
            nt.links.new(x, n.inputs[i])
    return n.outputs[0]


def rng(v, a, b, c, d):
    n = N("ShaderNodeMapRange", clamp=True)
    n.inputs["From Min"].default_value, n.inputs["From Max"].default_value = a, b
    n.inputs["To Min"].default_value, n.inputs["To Max"].default_value = c, d
    nt.links.new(v, n.inputs["Value"])
    return n.outputs["Result"]


gen = N("ShaderNodeTexCoord")
sp = N("ShaderNodeSeparateXYZ")
nt.links.new(gen.outputs["Generated"], sp.inputs[0])
fade = float(K.get("fade", 0.14))
up = K.get("up", "Y")  # local axis that is vertical in the VDB (Y before the 90 degree turn)
vert = sp.outputs[up]
side = [sp.outputs[a] for a in "XYZ" if a != up]
edge = rng(vert, 1 - 2.2 * fade, 1.0, 1.0, 0.0)  # open top
for sx in side:
    edge = mul(edge, rng(sx, 0.0, fade, 0.0, 1.0))
    edge = mul(edge, rng(sx, 1 - fade, 1.0, 1.0, 0.0))
if K.get("fadebottom", "0") == "1":
    edge = mul(edge, rng(vert, 0.0, fade, 0.0, 1.0))
# height above the base (m) for the flame grading
geo = N("ShaderNodeNewGeometry")
sp2 = N("ShaderNodeSeparateXYZ")
nt.links.new(geo.outputs["Position"], sp2.inputs[0])
hn = N("ShaderNodeMath", operation="SUBTRACT")
nt.links.new(sp2.outputs["Z"], hn.inputs[0])
hn.inputs[1].default_value = float(K.get("fbase", 0.0))
hh = rng(hn.outputs[0], 0.0, float(K.get("fh", 1.7)), 0.0, 1.0)
if "density" in [g.name for g in vol.grids]:
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "density"
    mu = nt.nodes.new("ShaderNodeMath")
    mu.operation = "MULTIPLY"
    mu.inputs[1].default_value = dens_gain
    nt.links.new(mul(at.outputs["Fac"], edge), mu.inputs[0])
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (*lin(col), 1)
    pv.inputs["Anisotropy"].default_value = 0.2
    nt.links.new(mu.outputs[0], pv.inputs["Density"])
    shaders.append(pv.outputs[0])
fgrid = next((g.name for g in vol.grids if g.name in ("flames", "flame", "temperature")), None)
if kind == "fire" and fgrid:
    fl = nt.nodes.new("ShaderNodeAttribute")
    fl.attribute_name = fgrid
    sc_ = nt.nodes.new("ShaderNodeMath")
    sc_.operation = "MULTIPLY"
    sc_.inputs[1].default_value = f("ramp", 1.0)
    flv = mul(fl.outputs["Fac"], edge)
    if K.get("vgrade", "0") == "1":  # cool with height: yellow-white base, red tips
        flv = mul(flv, rng(hh, 0.0, 1.0, 1.35, 0.35))
    nt.links.new(flv, sc_.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position, cr.elements[0].color = 0.0, (*hexc("#4A1204"), 1)
    cr.elements.new(0.3).color = (*hexc("#B8400F"), 1)
    cr.elements.new(0.6).color = (*hexc("#E0702A"), 1)
    cr.elements[3].position, cr.elements[3].color = 1.0, (*hexc("#FFD9A0"), 1)
    nt.links.new(sc_.outputs[0], ramp.inputs["Fac"])
    em = nt.nodes.new("ShaderNodeEmission")
    gm = nt.nodes.new("ShaderNodeMath")
    gm.operation = "MULTIPLY"
    gm.inputs[1].default_value = gain
    nt.links.new(sc_.outputs[0], gm.inputs[0])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(gm.outputs[0], em.inputs["Strength"])
    ab = nt.nodes.new("ShaderNodeVolumeAbsorption")
    am = nt.nodes.new("ShaderNodeMath")
    am.operation = "MULTIPLY"
    am.inputs[1].default_value = f("fabs", 6.0)
    nt.links.new(mul(sc_.outputs[0], rng(hh, 0.0, 1.0, 1.0, float(K.get("tipabs", 1.0)))) if K.get("vgrade", "0") == "1" else sc_.outputs[0], am.inputs[0])
    nt.links.new(am.outputs[0], ab.inputs["Density"])
    shaders += [em.outputs[0], ab.outputs[0]]
    if K.get("soot", "0") != "0":  # dark smoke clinging to the upper part of the flames
        ps = N("ShaderNodeVolumePrincipled")
        ps.inputs["Color"].default_value = (0.01, 0.01, 0.01, 1)
        nt.links.new(mul(mul(fl.outputs["Fac"], edge), mul(rng(hh, 0.35, 1.0, 0.0, 1.0), float(K["soot"]))), ps.inputs["Density"])
        shaders.append(ps.outputs[0])
last = shaders[0]
for s in shaders[1:]:
    ad = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(last, ad.inputs[0])
    nt.links.new(s, ad.inputs[1])
    last = ad.outputs[0]
nt.links.new(last, out.inputs["Volume"])
vo.data.materials.append(mat)

# --- framing: bbox of the middle frame, then scale the sim so its vertical extent is `height` metres
sc.frame_set(max(1, len(files) // 2))
bb = [vo.matrix_world @ Vector(c) for c in vo.bound_box]
zmin, zmax = min(v.z for v in bb), max(v.z for v in bb)
_sx = height / max(zmax - zmin, 1e-6)
vo.scale = (_sx, _sx * vstretch, _sx)  # local Y is the vertical axis after the 90 degree turn
bpy.context.view_layer.update()
bb = [vo.matrix_world @ Vector(c) for c in vo.bound_box]
ctr = sum(bb, Vector()) / 8
frame_m = f("frame_m", max(max(v.x for v in bb) - min(v.x for v in bb), max(v.z for v in bb) - min(v.z for v in bb)) * 1.15)
fx, fz = f("cx", 0.5), f("cz", 0.5)
zlo = min(v.z for v in bb)
target = Vector((ctr.x, ctr.y, zlo + frame_m * fz))
print("bbox m", [round(c, 2) for c in (min(v.x for v in bb), max(v.x for v in bb), min(v.y for v in bb), max(v.y for v in bb), zmin * vo.scale[0], zlo)], "frame_m", frame_m)

# --- burning bed: a flat glowing, flickering surface under the flames, so the fire stands on something
bed_w = None
if float(K.get("bed", 0)) > 0:
    r_ = float(K["bed"])
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=r_, fill_type="NGON", location=(ctr.x, ctr.y, zlo + float(K.get("bedz", 0.0))))
    bo = bpy.context.object
    bm = bpy.data.materials.new("Bed")
    bm.use_nodes = True
    bt = bm.node_tree
    bt.nodes.clear()
    bout = bt.nodes.new("ShaderNodeOutputMaterial")
    tc_ = bt.nodes.new("ShaderNodeTexCoord")
    vl = bt.nodes.new("ShaderNodeVectorMath")
    vl.operation = "LENGTH"
    bt.links.new(tc_.outputs["Object"], vl.inputs[0])
    rr = bt.nodes.new("ShaderNodeMath")
    rr.operation = "DIVIDE"
    rr.inputs[1].default_value = r_
    bt.links.new(vl.outputs["Value"], rr.inputs[0])
    bn = bt.nodes.new("ShaderNodeTexNoise")
    bn.noise_dimensions = "4D"
    bn.inputs["Scale"].default_value = 3.5 / r_
    bn.inputs["Detail"].default_value = 6
    bn.inputs["Roughness"].default_value = 0.65
    bt.links.new(tc_.outputs["Object"], bn.inputs["Vector"])
    bed_w = bn.inputs["W"]
    edgef = bt.nodes.new("ShaderNodeMapRange")
    edgef.inputs["From Min"].default_value, edgef.inputs["From Max"].default_value = 0.1, 1.0
    edgef.inputs["To Min"].default_value, edgef.inputs["To Max"].default_value = 1.0, 0.0
    edgef.clamp = True
    bt.links.new(rr.outputs[0], edgef.inputs["Value"])
    bheat = bt.nodes.new("ShaderNodeMath")  # noise x radial falloff = patchy hot spots
    bheat.operation = "MULTIPLY"
    bt.links.new(bn.outputs["Fac"], bheat.inputs[0])
    bt.links.new(edgef.outputs["Result"], bheat.inputs[1])
    hs = bt.nodes.new("ShaderNodeMapRange")
    hs.inputs["From Min"].default_value, hs.inputs["From Max"].default_value = 0.05, 0.7
    hs.clamp = True
    bt.links.new(bheat.outputs[0], hs.inputs["Value"])
    rmp = bt.nodes.new("ShaderNodeValToRGB")
    c2 = rmp.color_ramp
    c2.elements[0].position, c2.elements[0].color = 0.0, (*hexc("#4A1204"), 1)
    c2.elements.new(0.35).color = (*hexc("#C04A12"), 1)
    c2.elements.new(0.7).color = (*hexc("#F08A30"), 1)
    c2.elements[3].position, c2.elements[3].color = 1.0, (*hexc("#FFD9A0"), 1)
    bt.links.new(hs.outputs["Result"], rmp.inputs["Fac"])
    bem = bt.nodes.new("ShaderNodeEmission")
    bem.inputs["Strength"].default_value = float(K.get("bedgain", 3.0))
    bt.links.new(rmp.outputs["Color"], bem.inputs["Color"])
    tr = bt.nodes.new("ShaderNodeBsdfTransparent")
    mx = bt.nodes.new("ShaderNodeMixShader")
    bt.links.new(hs.outputs["Result"], mx.inputs[0])
    bt.links.new(tr.outputs[0], mx.inputs[1])
    bt.links.new(bem.outputs[0], mx.inputs[2])
    bt.links.new(mx.outputs[0], bout.inputs["Surface"])
    bo.data.materials.append(bm)

# --- camera at the game angle
sc.render.engine = "CYCLES"
sc.cycles.samples = samples
sc.cycles.use_denoising = True
sc.cycles.volume_bounces = 2
sc.cycles.sample_clamp_indirect = 1.0
sc.cycles.volume_step_rate = 0.5
try:
    pref = bpy.context.preferences.addons["cycles"].preferences
    pref.compute_device_type = "OPTIX"
    pref.get_devices()
    for d in pref.devices:
        d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
except Exception as e:
    print("gpu", e)
sc.render.resolution_x, sc.render.resolution_y = cellw, cell
sc.render.film_transparent = True
sc.view_settings.view_transform = "Standard"
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
cam = bpy.data.objects.new("C", bpy.data.cameras.new("C"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = frame_m
el = math.radians(pitch)
cam.location = target + Vector((0, -math.cos(el), math.sin(el))) * 60
cam.rotation_euler = (math.radians(90 - pitch), 0, 0)
sc.camera = cam
# overcast: grey sky + one big soft light overhead
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.82, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
al = bpy.data.objects.new("A", bpy.data.lights.new("A", "AREA"))
sc.collection.objects.link(al)
al.data.shape, al.data.size, al.data.energy = "SQUARE", max(frame_m * 2, 8), 6000 * top * (frame_m / 8) ** 2
al.location = target + Vector((0, 0, 40))

# --- auto-fit: low-res prepass over the frames, union of the alpha, then frame it with a margin
import numpy as np
big = frame_m * 2.0
pre_cell = 96
cam.data.ortho_scale = big
sc.render.resolution_x = sc.render.resolution_y = pre_cell
sc.cycles.samples = 16
sc.cycles.use_denoising = False
boxes = []
tmp = os.path.join(outdir, "_pre_%s.png" % name)
for p_ in sel[:: max(1, len(sel) // 8)] + [sel[-1]]:
    sc.frame_set(files.index(p_) + 1)
    set_lift(sel.index(p_))
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(tmp)
    px = np.array(im.pixels[:], np.float32).reshape(pre_cell, pre_cell, 4)
    bpy.data.images.remove(im)
    u = px[..., 3] > float(K.get("athr", 0.04))
    # opening: drop isolated noisy pixels so one firefly cannot stretch the frame
    nb = sum(np.roll(np.roll(u, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)) - u
    u = u & (nb >= 4)
    ys, xs = np.nonzero(u)
    if len(xs):
        boxes.append((xs.min(), xs.max() + 1, ys.min(), ys.max() + 1))  # y from the bottom (Blender image rows)
if boxes:
    # the typical frame, not the union: single tall tongues may run out of the frame and fade there
    bx = np.array(boxes, float)
    if K.get("fit") == "typ":
        x0, x1, y0, y1 = (float(np.percentile(bx[:, 0], 25)), float(np.percentile(bx[:, 1], 75)),
                          float(np.percentile(bx[:, 2], 25)), float(np.percentile(bx[:, 3], 60)))
    else:  # union of all sampled frames
        x0, x1, y0, y1 = bx[:, 0].min(), bx[:, 1].max(), bx[:, 2].min(), bx[:, 3].max()
    mpp = big / pre_cell
    mg = f("margin", 0.14)
    wm, hm = (x1 - x0) * mpp, (y1 - y0) * mpp
    fm = max(hm, wm * cell / cellw) * (1 + 2 * mg)  # frame height: must hold the content height and, via the aspect, its width
    cxm = ((x0 + x1) / 2 - pre_cell / 2) * mpp
    cym = ((y0 + y1) / 2 - pre_cell / 2) * mpp
    if K.get("ground", "0") == "1":  # ground effects: keep the floor a fixed distance above the frame bottom
        cym = (y0 * mpp - big / 2) + fm * (0.5 - 0.06)
    # offsets are in camera-plane metres: x along world X, y along the tilted up vector
    up = Vector((0, math.sin(el), math.cos(el)))  # camera up in world
    target = target + Vector((cxm, 0, 0)) + up * cym
    frame_m = fm
    print("autofit frame_m", round(fm, 2), "content", round(wm, 2), "x", round(hm, 2))
cam.data.ortho_scale = frame_m
cam.location = target + Vector((0, -math.cos(el), math.sin(el))) * 60
al.location = target + Vector((0, 0, 40))
al.data.size = max(frame_m * 2, 8)
al.data.energy = 6000 * top * (frame_m / 8) ** 2
sc.render.resolution_x, sc.render.resolution_y = cellw, cell
sc.cycles.samples = samples
sc.cycles.use_denoising = True
# blast point: the ground contact of the volume at the first rendered frame, projected into the cell
from bpy_extras.object_utils import world_to_camera_view
sc.frame_set(files.index(sel[0]) + 1)
set_lift(0)
bpy.context.view_layer.update()
bb0 = [vo.matrix_world @ Vector(c) for c in vo.bound_box]
P0 = Vector((sum(v.x for v in bb0) / 8, sum(v.y for v in bb0) / 8, min(v.z for v in bb0)))
ax, ay, _ = world_to_camera_view(sc, cam, P0)
print("ANCHOR x_from_left=%.3f y_from_top=%.3f frame_m=%.2f cell_w_m=%.2f" % (ax, 1 - ay, frame_m, frame_m * cellw / cell))
os.makedirs(os.path.join(outdir, name), exist_ok=True)
for i, p in enumerate(sel):
    idx = files.index(p)
    sc.frame_set(idx + 1)
    set_lift(i)
    if bed_w is not None:
        bed_w.default_value = i * 0.3
    if heat and kind == "fire" and fgrid:  # the first frames burn hottest: whiter core, then it cools
        e = math.exp(-i / tau)
        sc_.inputs[1].default_value = f("ramp", 1.0) * (1 + 1.6 * heat * e)
        gm.inputs[1].default_value = gain * (1 + 2.0 * heat * e)
    sc.render.filepath = os.path.join(outdir, name, "f_%03d.png" % i)
    bpy.ops.render.render(write_still=True)
    print("rendered", i, idx)
