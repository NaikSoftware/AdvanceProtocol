"""Stage 2: bake hi -> lo into data maps (numpy, PNG row order) for paint.py.

    blender --background --factory-startup --python bake.py -- <unit>

Writes <work>/maps.npz: pos, nrm (object space), point (Cycles pointiness), src (the generated
colour, rough), cov (1 where a ray found hi), normal (tangent, 0..1) and ao. Texels whose ray
missed hi (walls over cut-away gear) fall back to lo's own position and normal. Painting is a
separate step so the look can be iterated without re-baking.
"""
import bpy, sys, os
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

cfg = lib.load(sys.argv[sys.argv.index("--") + 1])
bpy.ops.wm.open_mainfile(filepath=os.path.join(cfg["work"], "work.blend"))
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
try:
    pr = bpy.context.preferences.addons['cycles'].preferences
    pr.compute_device_type = 'OPTIX'; pr.get_devices()
    for d in pr.devices:
        d.use = d.type == 'OPTIX'
    sc.cycles.device = 'GPU'
except Exception as e:  # CPU still works, only slower
    print("BAKE no GPU:", e)
sc.cycles.samples = 1
sc.world = sc.world or bpy.data.worlds.new("w")
sc.world.light_settings.distance = lib.m_len(cfg, cfg.get("ao_dist", 0.05))

hi, lo = bpy.data.objects["hi"], bpy.data.objects["lo"]
N = lib.ATLAS
img = bpy.data.images.new("bake", N, N, alpha=True, float_buffer=True)
img.colorspace_settings.name = 'Non-Color'

lm = bpy.data.materials.new("lo_bake"); lm.use_nodes = True
lt = lm.node_tree
tex = lt.nodes.new("ShaderNodeTexImage"); tex.image = img
lt.nodes.active = tex
lo_emit = lt.nodes.new("ShaderNodeEmission")
lt.links.new(lo_emit.outputs[0], lt.nodes["Material Output"].inputs[0])
lgeo = lt.nodes.new("ShaderNodeNewGeometry")
lo.data.materials.clear(); lo.data.materials.append(lm)

src_img = next((i for i in bpy.data.images if i.size[0] > 0 and i.name != "bake"), None)
hm = bpy.data.materials.new("hi_bake"); hm.use_nodes = True
ht = hm.node_tree
emit = ht.nodes.new("ShaderNodeEmission")
ht.links.new(emit.outputs[0], ht.nodes["Material Output"].inputs[0])
geo = ht.nodes.new("ShaderNodeNewGeometry")
stex = ht.nodes.new("ShaderNodeTexImage"); stex.image = src_img
one = ht.nodes.new("ShaderNodeRGB"); one.outputs[0].default_value = (1, 1, 1, 1)
hi.data.materials.clear(); hi.data.materials.append(hm)


def grab():
    a = np.empty(N * N * 4, np.float32); img.pixels.foreach_get(a)
    return a.reshape(N, N, 4)[::-1].copy()  # Blender rows run bottom-up


ext = lib.m_len(cfg, cfg.get("cage", 0.014))
ray = lib.m_len(cfg, cfg.get("ray", 0.045))


def bake(kind, to_lo=True, **kw):
    bpy.ops.object.select_all(action='DESELECT')
    lo.select_set(True); bpy.context.view_layer.objects.active = lo
    if to_lo:
        hi.select_set(True)
    bpy.ops.object.bake(type=kind, use_selected_to_active=to_lo, cage_extrusion=ext if to_lo else 0.0,
                        max_ray_distance=ray if to_lo else 0.0, margin=6, margin_type='EXTEND',
                        target='IMAGE_TEXTURES', use_clear=True, **kw)
    return grab()


def hi_emit(sock):
    ht.links.new(sock, emit.inputs[0])


out = {}
# lo's own geometry first: the fallback where hi is missing
lt.links.new(lgeo.outputs["Position"], lo_emit.inputs[0]); lo_pos = bake('EMIT', False)
lt.links.new(lgeo.outputs["Normal"], lo_emit.inputs[0]); lo_nrm = bake('EMIT', False)
hi_emit(one.outputs[0]); cov = bake('EMIT')
out["cov"] = cov[..., 0] * cov[..., 3]
out["used"] = lo_pos[..., 3]  # texels inside an island or its margin
hit = out["cov"][..., None] > 0.5
hi_emit(geo.outputs["Position"]); out["pos"] = np.where(hit, bake('EMIT')[..., :3], lo_pos[..., :3])
hi_emit(geo.outputs["Normal"]); out["nrm"] = np.where(hit, bake('EMIT')[..., :3], lo_nrm[..., :3])
hi_emit(geo.outputs["Pointiness"]); out["point"] = np.where(hit[..., 0], bake('EMIT')[..., 0], 0.5)
if (cfg.get("paint") or {}).get("scheme") == "plain" and "added" in hi.data.attributes:
    # cuboids added by prep have a few vertices, so their pointiness is an interpolated gradient across big
    # flat faces and paints dirt blotches: texels on them get the neutral cavity value
    at = ht.nodes.new("ShaderNodeAttribute"); at.attribute_name = "added"
    hi_emit(at.outputs["Fac"]); added = bake('EMIT')[..., 0]
    out["point"] = np.where(hit[..., 0] & (added > 0.5), 0.5, out["point"])
if src_img is not None:
    ht.links.new(stex.outputs[0], emit.inputs[0]); out["src"] = bake('EMIT')[..., :3]
nm = bake('NORMAL', normal_space='TANGENT')[..., :3]
out["normal"] = np.where(hit, nm, np.array([0.5, 0.5, 1.0], np.float32))
sc.cycles.samples = cfg.get("ao_samples", 128)
ao = bake('AO')[..., 0]
out["ao"] = np.where(hit[..., 0], ao, 1.0)
np.savez_compressed(os.path.join(cfg["work"], "maps.npz"), **out)
print("BAKE hi coverage of lo texels", float((out["cov"] > 0.5).sum() / max(1, (out["used"] > 0.5).sum())))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(cfg["work"], "work.blend"))
