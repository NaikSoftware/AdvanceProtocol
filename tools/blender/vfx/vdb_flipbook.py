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
kind = K.get("kind", "smoke")
dens_gain, gain, top = f("dens", 3.0), f("gain", 6.0), f("top", 1.0)
col = tuple(float(x) for x in K.get("col", "0.35,0.35,0.35").split(","))
a, b, st = (int(x) for x in K.get("frames", "0:0:1").split(":"))

files = sorted(glob.glob(vdir + "/*.vdb"), key=lambda p: int("".join(c for c in os.path.basename(p).rsplit(".", 1)[0].split("_")[-1] if c.isdigit()) or 0))
sel = files[a:b + 1:st] if b else files[::st]

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
if "density" in [g.name for g in vol.grids]:
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "density"
    mu = nt.nodes.new("ShaderNodeMath")
    mu.operation = "MULTIPLY"
    mu.inputs[1].default_value = dens_gain
    nt.links.new(at.outputs["Fac"], mu.inputs[0])
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
    nt.links.new(fl.outputs["Fac"], sc_.inputs[0])
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
    nt.links.new(sc_.outputs[0], am.inputs[0])
    nt.links.new(am.outputs[0], ab.inputs["Density"])
    shaders += [em.outputs[0], ab.outputs[0]]
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
vo.scale = (height / max(zmax - zmin, 1e-6),) * 3
bpy.context.view_layer.update()
bb = [vo.matrix_world @ Vector(c) for c in vo.bound_box]
ctr = sum(bb, Vector()) / 8
frame_m = f("frame_m", max(max(v.x for v in bb) - min(v.x for v in bb), max(v.z for v in bb) - min(v.z for v in bb)) * 1.15)
fx, fz = f("cx", 0.5), f("cz", 0.5)
zlo = min(v.z for v in bb)
target = Vector((ctr.x, ctr.y, zlo + frame_m * fz))
print("bbox m", [round(c, 2) for c in (min(v.x for v in bb), max(v.x for v in bb), min(v.y for v in bb), max(v.y for v in bb), zmin * vo.scale[0], zlo)], "frame_m", frame_m)

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
sc.render.resolution_x = sc.render.resolution_y = cell
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
sc.cycles.samples = 6
sc.cycles.use_denoising = False
u = np.zeros((pre_cell, pre_cell), bool)
tmp = os.path.join(outdir, "_pre.png")
for p_ in sel[:: max(1, len(sel) // 8)]:
    sc.frame_set(files.index(p_) + 1)
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(tmp)
    px = np.array(im.pixels[:], np.float32).reshape(pre_cell, pre_cell, 4)
    bpy.data.images.remove(im)
    u |= px[..., 3] > float(K.get("athr", 0.04))
ys, xs = np.nonzero(u)
if len(xs):
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1  # y from the bottom (Blender image rows)
    mpp = big / pre_cell
    mg = f("margin", 0.14)
    wm, hm = (x1 - x0) * mpp, (y1 - y0) * mpp
    fm = max(wm, hm) * (1 + 2 * mg)
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
sc.render.resolution_x = sc.render.resolution_y = cell
sc.cycles.samples = samples
sc.cycles.use_denoising = True
os.makedirs(os.path.join(outdir, name), exist_ok=True)
for i, p in enumerate(sel):
    idx = files.index(p)
    sc.frame_set(idx + 1)
    sc.render.filepath = os.path.join(outdir, name, "f_%03d.png" % i)
    bpy.ops.render.render(write_still=True)
    print("rendered", i, idx)
