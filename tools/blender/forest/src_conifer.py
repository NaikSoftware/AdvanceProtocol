"""Джерело крон хвойних: дерева Poly Haven (CC0) pine_tree_01 і fir_tree_01, рівень LOD1.

Запуск:
  blender -b --factory-startup -P src_conifer.py -- <файл.blend> <об'єкт> <вихід> <тег>
      [воксель=1.7] [карток=45] [частка_без_крони=0] [спрайтів=0]
Приклад: ... -- pine_tree_01_1k.blend pine_tree_01_a_LOD1 out pine_a 1.7 45 0.55 6
LOD0 (4–6 млн граней) не потрібен: спрайт іде з ~1 см на піксель, а LOD1 дає 0,4–0,7 млн.
Файл .blend лишається поза репозиторієм: Godot ламає імпорт, якщо бачить .blend у проєкті.
"""
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crown_lib as cl  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
LIB, NAME, OUT, TAG = argv[:4]
VOXEL = float(argv[4]) if len(argv) > 4 else 1.7
CARDS = int(argv[5]) if len(argv) > 5 else 45
KEEP_ABOVE = float(argv[6]) if len(argv) > 6 else 0.0
SPRITES = int(argv[7]) if len(argv) > 7 else 0
out = os.path.join(OUT, TAG)
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(LIB, link=False) as (src, dst):
    dst.objects = [NAME]
ob = dst.objects[0]
bpy.context.scene.collection.objects.link(ob)

hidden = bpy.data.materials.new("hidden")
hidden.use_nodes = True
nt = hidden.node_tree
nt.nodes.clear()
nt.links.new(nt.nodes.new("ShaderNodeBsdfTransparent").outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])

mats = list(ob.data.materials)
is_trunk = [bool(m) and "trunk" in m.name for m in mats]

# Стовбур у початок координат: картки й стовбур у GLB стоять на одній осі.
trunk_pts = cl.face_points([ob], lambda n: "trunk" in n)
base = trunk_pts[trunk_pts[:, 2] < trunk_pts[:, 2].min() + 1.0]
ob.location = (-base[:, 0].mean(), -base[:, 1].mean(), -trunk_pts[:, 2].min())
bpy.context.view_layer.update()

twig = cl.face_points([ob], lambda n: "twig" in n)
top = float(twig[:, 2].max())
trunk_pts = cl.face_points([ob], lambda n: "trunk" in n)
low = trunk_pts[trunk_pts[:, 2] < 1.5]
trunk_w = float(2 * np.percentile(np.hypot(low[:, 0], low[:, 1]), 90))

cards, crown_base = cl.card_layout(twig, VOXEL, CARDS, KEEP_ABOVE)
cam = cl.setup_render()
for i, t in enumerate(is_trunk):
    if t:
        ob.data.materials[i] = hidden
sprites = cl.render_sprites(cam, twig, out, SPRITES) if SPRITES else []

for i, m in enumerate(mats):
    ob.data.materials[i] = m if is_trunk[i] else hidden
th = max(crown_base + 1.0, 4.0)
cl.render_trunk(cam, out, th, trunk_w)

cl.save_meta(out, {"tag": TAG, "source": os.path.basename(LIB) + ":" + NAME, "cards": cards, "sprites": sprites,
                   "crown_base": crown_base, "top": top, "trunk_width": trunk_w, "trunk_render_height": th})
print("DONE", TAG, "cards", len(cards), "crown_base", round(crown_base, 2), "top", round(top, 2),
      "trunk_w", round(trunk_w, 2), "sprites", len(sprites))
