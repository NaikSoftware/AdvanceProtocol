"""Спільне для джерел крон: кластери листя, розкладка карток, спрайти пучків, стовбур.

Імпортується зі скриптів-джерел, що вже поставили дерево в сцену (Blender, `-b`).
Крона в грі — хмара карток із вирізами по alpha, по картці на кластер листя справжнього
дерева. Суцільну оболонку з проєкцією рендерів відкинуто: її межа на екрані — прямі
ребра оболонки, хоч як підрізай alpha, і крона читається гранованою плитою.
Що лишає у <out>/<tag>/:
  sprite_NN.png  пучок хвої чи листя ~2,4 м: ортографічно, камера обрізана шаром ±1,2 м,
                 тож це справжній місцевий пучок із рваним краєм, а не вся товща крони;
  cards.json     картки (центр, напрям, поворот, розмір, затінення), висоти крони;
  trunk.png      стовбур збоку (якщо є що рендерити).
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Vector

SPRITE_RES = 256
SPRITE_M = 2.4


def setup_render(samples=64):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
            if any(d.type == kind for d in prefs.devices):
                for d in prefs.devices:
                    d.use = d.type == kind
                sc.cycles.device = "GPU"
                break
        except TypeError:
            continue
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False  # денойзер розмиває хвою в кашу
    sc.cycles.max_bounces = 4
    sc.cycles.transparent_max_bounces = 32
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    # Рівне біле небо: у спрайті лишається альбедо, притінене глибиною пучка, а напрям
    # світла дає гра через нормалі карток.
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 1.0
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def aim(cam, target, d, dist):
    cam.location = Vector(target) - Vector(d) * dist
    cam.rotation_euler = (-Vector(d)).to_track_quat("Z", "Y").to_euler()


def face_points(objs, mat_pred, stride=1):
    """Центри граней з матеріалом, що проходить mat_pred, у світових координатах."""
    out = []
    for ob in objs:
        me = ob.data
        n = len(me.polygons)
        c = np.empty(n * 3)
        me.polygons.foreach_get("center", c)
        mi = np.empty(n, dtype=np.int32)
        me.polygons.foreach_get("material_index", mi)
        ok = np.array([mat_pred(m.name if m else "") for m in me.materials] or [False])
        sel = ok[mi]
        c = c.reshape(-1, 3)[sel][::stride]
        M = np.array(ob.matrix_world)
        out.append(c @ M[:3, :3].T + M[:3, 3])
    return np.concatenate(out)


def clusters(pts, voxel):
    """Центроїди й кількості точок листя у вокселях."""
    lo = pts.min(0)
    idx = np.floor((pts - lo) / voxel).astype(int)
    keys, inv, counts = np.unique(idx, axis=0, return_inverse=True, return_counts=True)
    sums = np.zeros((len(keys), 3))
    np.add.at(sums, inv.ravel(), pts)
    return sums / counts[:, None], counts


def card_layout(pts, voxel, max_cards, keep_above=0.0, size_k=1.35, seed=1):
    """Картка на кожен густий кластер: центр у центроїді, лице назовні від осі й угору.

    keep_above — частка висоти крони, нижче якої кластери відкидаються: сосна в
    насадженні самоочищується, і крона сидить у верхній третині стовбура.
    """
    rng = np.random.default_rng(seed)
    cent, cnt = clusters(pts, voxel)
    z0, z1 = pts[:, 2].min(), pts[:, 2].max()
    keep = cent[:, 2] >= z0 + keep_above * (z1 - z0)
    cent, cnt = cent[keep], cnt[keep]
    order = np.argsort(-cnt)[:max_cards]
    cent, cnt = cent[order], cnt[order]
    axis_r = np.hypot(cent[:, 0], cent[:, 1])
    r_max = max(axis_r.max(), 0.5)
    cards = []
    for c, n, ar in zip(cent, cnt, axis_r):
        out = np.array([c[0], c[1], 0.0]) / max(ar, 1e-3)
        h = (c[2] - z0) / max(z1 - z0, 1e-3)
        # Лице переважно назовні: пласкі горизонтальні картки збоку (камера на 38°)
        # видно ребром, і вони стирчать, як тарілки.
        d = out * 0.8 * min(1.0, ar / (0.35 * r_max)) + np.array([0, 0, 0.3 + 0.25 * h])
        d += rng.normal(0, 0.25, 3)
        d /= np.linalg.norm(d)
        size = voxel * size_k * (0.8 + 0.4 * min(1.0, n / np.median(cnt)))
        # Глибші й нижчі пучки темніші: світло неба туди доходить гірше.
        shade = 0.55 + 0.25 * min(1.0, ar / r_max) + 0.2 * h
        cards.append({"c": c.round(3).tolist(), "n": d.round(3).tolist(), "roll": float(rng.uniform(0, 2 * math.pi)),
                      "size": round(float(size), 3), "shade": round(float(min(shade, 1.0)), 3)})
    return cards, float(cent[:, 2].min())


def render_sprites(cam, pts, out, n_sprites, size_m=SPRITE_M, res=SPRITE_RES, outer=0.0, seed=3, prefix="sprite"):
    """Пучки з різних місць крони: половина згори, половина під 45° назовні.

    outer — перцентиль відстані від осі, ближче за який пучки не беруться: кінці гілок,
    де хвоя стирчить променями, читаються сосною, а середина крони — темною масою.
    """
    rng = np.random.default_rng(seed)
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = res
    cent, cnt = clusters(pts, size_m * 0.6)
    ok = cnt >= np.percentile(cnt, 50)
    if outer:
        ok &= np.hypot(cent[:, 0], cent[:, 1]) >= np.percentile(np.hypot(cent[:, 0], cent[:, 1]), outer)
    good = cent[ok]
    pick = good[rng.choice(len(good), size=min(n_sprites, len(good)), replace=False)]
    cam.data.ortho_scale = size_m
    dist = 30.0
    cam.data.clip_start = dist - size_m / 2
    cam.data.clip_end = dist + size_m / 2
    files = []
    for i, c in enumerate(pick):
        if i % 2 == 0:
            d = (0.0, 0.0, -1.0)
        else:
            o = np.array([c[0], c[1], 0.0])
            o = o / max(np.linalg.norm(o), 1e-3)
            d = tuple((-o * 0.707 + np.array([0, 0, -0.707])).tolist())
        aim(cam, c, d, dist)
        path = os.path.join(out, "%s_%02d.png" % (prefix, i))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        files.append(os.path.basename(path))
    return files


def skirt_cards(pts, crown_base, step=1.25, size=1.5, seed=5):
    """Картки від низу крони до землі: ялина на краю лісу зелена до самого низу, і край
    стоїть стіною, а не частоколом стовбурів."""
    rng = np.random.default_rng(seed)
    low = pts[pts[:, 2] < crown_base + 1.5]
    r0 = float(np.percentile(np.hypot(low[:, 0], low[:, 1]), 85)) if len(low) else 1.5
    cards = []
    z = crown_base - step * 0.5
    while z > size * 0.45:
        r = r0 * (1.0 + 0.12 * (crown_base - z) / max(crown_base, 1.0))
        n = max(4, int(2 * math.pi * r / 1.1))
        for k in range(n):
            a = 2 * math.pi * (k + rng.uniform(-0.3, 0.3)) / n
            rr = r * rng.uniform(0.75, 1.0)
            c = [rr * math.cos(a), rr * math.sin(a), z + rng.uniform(-0.2, 0.2)]
            cards.append({"c": [round(x, 3) for x in c], "n": [math.cos(a), math.sin(a), 0.3],
                          "roll": float(rng.uniform(0, 2 * math.pi)), "size": size, "shade": 0.6})
        z -= step
    return cards


def render_trunk(cam, out, height, width, base=0.0):
    """Стовбур збоку однією смугою: ортографічно, кадр завширшки з комель і запасом."""
    sc = bpy.context.scene
    sc.render.resolution_y = 1024
    sc.render.resolution_x = max(32, int(math.ceil(1024 * width * 1.4 / height / 8)) * 8)
    cam.data.ortho_scale = height
    cam.data.clip_start = 0.1
    cam.data.clip_end = 400
    aim(cam, (0, 0, base + height / 2), (0, 1, 0), 150)
    sc.render.filepath = os.path.join(out, "trunk.png")
    bpy.ops.render.render(write_still=True)


def save_meta(out, data):
    with open(os.path.join(out, "cards.json"), "w") as f:
        json.dump(data, f, indent=1)
