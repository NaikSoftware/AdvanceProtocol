"""Four-view contact sheet of a GLB for close inspection: top, side, and the battle camera
angle (yaw 45, pitch -52) from front-left and rear-right.

    blender --background --factory-startup --python render_views.py -- in.glb out.png [--size 640] [--fwd x|y]

`--fwd x` treats +X as the model's front (a raw generated source); the default `y` is a
finished unit (front along Blender +Y). EEVEE with a sun and a grey floor so shading and
contact read like the game; this is an inspection aid, not the in-engine judgement.
"""
import bpy, sys, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
size = int(argv[argv.index("--size") + 1]) if "--size" in argv else 640
fwd = argv[argv.index("--fwd") + 1] if "--fwd" in argv else "y"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
lo = np.full(3, 1e9); hi = np.full(3, -1e9)
for o in meshes:
    co = np.empty(len(o.data.vertices) * 3); o.data.vertices.foreach_get("co", co)
    w = np.array(o.matrix_world); co = co.reshape(-1, 3) @ w[:3, :3].T + w[:3, 3]
    lo = np.minimum(lo, co.min(0)); hi = np.maximum(hi, co.max(0))
ctr = Vector(((lo + hi) / 2).tolist()); ext = float(max(hi - lo))
yaw0 = 0.0 if fwd == "y" else -90.0  # rotate the view so the model's front is "north"

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = sc.render.resolution_y = size
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w"); sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.58, 0.62, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
sc.view_settings.view_transform = 'Standard'

sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
sun.data.energy = 3.5; sun.data.angle = math.radians(3)
sun.rotation_euler = (math.radians(40), 0, math.radians(yaw0 + 150))
sc.collection.objects.link(sun)
bpy.ops.mesh.primitive_plane_add(size=ext * 6, location=(ctr.x, ctr.y, lo[2]))
fl = bpy.context.object
fm = bpy.data.materials.new("floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.33, 0.31, 1)
fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
fl.data.materials.append(fm)

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = 'ORTHO'; cam.data.ortho_scale = ext * 1.08
cam.data.clip_end = ext * 50
sc.collection.objects.link(cam); sc.camera = cam

def view(pitch, yaw):
    """pitch: degrees below horizon; yaw: degrees around Z from the model's front."""
    p, y = math.radians(pitch), math.radians(yaw + yaw0)
    d = Vector((math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p)))
    cam.location = ctr + d * ext * 10
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()

tiles = []
for i, (p, y) in enumerate([(90, 0.001), (0.0, 90), (52, -45), (52, 135)]):
    view(p, y)
    sc.render.filepath = out + f".{i}.png"
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(sc.render.filepath)
    a = np.array(im.pixels[:], dtype=np.float32).reshape(size, size, 4)
    tiles.append(a)
# Blender pixel rows run bottom-up: the battle-angle pair lands on the top row of the PNG.
sheet = np.concatenate([np.concatenate(tiles[:2], 1), np.concatenate(tiles[2:], 1)], 0)
img = bpy.data.images.new("sheet", size * 2, size * 2)
img.pixels = sheet.ravel().tolist()
img.filepath_raw = out; img.file_format = 'PNG'; img.save()
import os
for i in range(4):
    os.remove(out + f".{i}.png")
print("SHEET", out, "bbox", lo.round(4).tolist(), hi.round(4).tolist())
