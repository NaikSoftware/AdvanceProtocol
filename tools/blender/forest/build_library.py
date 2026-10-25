"""Збирає GLB бібліотеки крон: на кожен вузол — оболонка крони плюс стовбур, один матеріал.

Запуск:
  blender -b --factory-startup -P build_library.py -- <spec.json> <тека_джерел> <тека_атласу> <вихід.glb>
Вузол = окремий меш = окремий MultiMesh на дошці (один виклик малювання на варіант).
Масштаб гри: 1 тайл = 8 м = 1,0; земля на y = 0; початок координат — вісь стовбура.

Порядок збирання з нуля (джерела — у теці поза репозиторієм):
  1. src_conifer.py на кожне дерево Poly Haven (pine_tree_01 a/b/c, fir_tree_01 a/b);
  2. src_leaf_sprites.py на кожен набір × сезон (birch, broad, oak, shrub × late, summer, early);
  3. src_broadleaf.py (будова листяних, кущів і повалених стовбурів);
  4. specs/make_broadleaf_specs.py, далі make_atlas.py і цей скрипт на кожен spec.
"""
import json
import math
import os
import random
import struct
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SPEC, SRC, ATLAS_DIR, OUT = argv[:4]
TILE_M = 8.0


def to_atlas(rect, u, v):
    x, y, w, h = rect
    return (x + u * w, 1.0 - (y + (1.0 - v) * h))


def trunk(bm, uvl, rect, base_r, top_r, height, uv_top, sides, lean=(0.0, 0.0)):
    """Стовбур-призма; кожна грань показує всю смугу кори, вісь трохи нахилена."""
    ring0, ring1 = [], []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        ring0.append(bm.verts.new((base_r * math.cos(a), base_r * math.sin(a), 0.0)))
        ring1.append(bm.verts.new((lean[0] + top_r * math.cos(a), lean[1] + top_r * math.sin(a), height)))
    normals = {}
    for i in range(sides):
        j = (i + 1) % sides
        f = bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        for loop, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, uv_top), (0, uv_top))):
            loop[uvl].uv = to_atlas(rect, u, v)
    for i, vt in enumerate(ring0 + ring1):
        a = 2 * math.pi * (i % sides) / sides
        normals[vt] = Vector((math.cos(a), math.sin(a), 0.0))
    return normals


def card(bm, uvl, uv2l, col, c, roll, size, rect, normal_of, shade):
    """Пучок: чотири вершини в центрі c, зсув кута — в UV2 (одиниці гри, після 1/8).

    Шейдер forest_crown розгортає картку до камери; roll крутить пучок у площині екрана,
    щоб однакові спрайти не стояли однаково.
    """
    h = size / 2
    c = Vector(c)
    c.z = max(c.z, h * 0.8)  # нижній край пучка не йде під землю
    cr, sr = math.cos(roll), math.sin(roll)
    tone = (shade, shade, shade, 1.0)
    vs = [bm.verts.new(c) for _ in range(4)]
    f = bm.faces.new(vs)
    for loop, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        x, y = (u * 2 - 1) * h, (v * 2 - 1) * h
        loop[uvl].uv = to_atlas(rect, u, v)
        loop[uv2l].uv = ((x * cr - y * sr) / TILE_M, (x * sr + y * cr) / TILE_M)
        loop[col] = tone
    return {v: normal_of(c, None) for v in vs}


def flat(bm, uvl, col, c, roll, size, rect, shade):
    """Картка, що лежить на землі (гілля поваленого лісу): звичайна геометрія, UV2 = 0, тож
    шейдер її не розгортає до камери."""
    h = size / 2
    cr, sr = math.cos(roll), math.sin(roll)
    co = [Vector(c) + Vector((x * cr - y * sr, x * sr + y * cr, 0.0)) * h for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    vs = [bm.verts.new(p) for p in co]
    f = bm.faces.new(vs)
    for loop, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uvl].uv = to_atlas(rect, u, v)
        loop[col] = (shade, shade, shade, 1.0)
    return {v: Vector((0, 0, 1)) for v in vs}


def limb(bm, uvl, rect, pts, radii, sides=3):
    """Гілка-трубка з кількох відрізків; смуга кори вздовж, як у стовбура."""
    rings = []
    total = sum((Vector(pts[i + 1]) - Vector(pts[i])).length for i in range(len(pts) - 1))
    acc = 0.0
    normals = {}
    for i, (p, r) in enumerate(zip(pts, radii)):
        p = Vector(p)
        d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        t = ref.cross(d).normalized()
        b = d.cross(t)
        if i:
            acc += (p - Vector(pts[i - 1])).length
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            off = t * math.cos(a) + b * math.sin(a)
            v = bm.verts.new(p + off * r)
            normals[v] = off
            ring.append((v, acc / max(total, 1e-6)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            f = bm.faces.new((r0[k][0], r0[j][0], r1[j][0], r1[k][0]))
            for loop, (u, v) in zip(f.loops, ((0, r0[k][1]), (1, r0[j][1]), (1, r1[j][1]), (0, r1[k][1]))):
                loop[uvl].uv = to_atlas(rect, u, v)
    return normals



def build_node(item, rects):
    d = os.path.join(SRC, item["src"])
    meta = json.load(open(os.path.join(d, "cards.json")))
    rng = random.Random(item["node"])
    # Масштаб усього дерева: джерела мають 14–25 м, а для читання з камери гри дерева
    # нижчі (сосна 12–14 м, листяні 10–12 м); пропорції крони й стовбура лишаються.
    fs = item.get("scale", 1.0)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    uv2l = bm.loops.layers.uv.new("UV2")
    col = bm.loops.layers.float_color.new("Col")
    vnorm = {}
    cards = meta["cards"]
    keep = item.get("card_keep", 1.0)
    fs_card = 1.0
    if item.get("max_cards") and len(cards) > item["max_cards"]:
        # Проксі тіні: менше пучків, але більших — сумарна площа та сама (×0,85 на
        # перекриття), тож пляма тіні тієї ж величини й так само дірява.
        n = item["max_cards"]
        fs_card = 0.85 * math.sqrt(len(cards) / n)
        cards = random.Random(item["node"] + "proxy").sample(cards, n)
        keep = 1.0
    if keep < 1.0 and cards:
        # Голе дерево: та сама будова, але менше пучків — крізь крону видно землю.
        cards = random.Random(item["node"] + "keep").sample(cards, max(1, round(len(cards) * keep)))
    cb, top = meta["crown_base"], meta["top"]
    R = max([math.hypot(cd["c"][0], cd["c"][1]) for cd in cards] + [0.5])
    ctr = Vector(meta.get("centre", (0, 0, (cb + top) / 2)))
    rad = Vector(meta.get("radii", (R, R, max((top - cb) / 2, 0.5))))

    def normal_of(p, n):
        s = Vector(((p.x - ctr.x) / rad.x, (p.y - ctr.y) / rad.y, (p.z - ctr.z) / rad.z))
        s = s.normalized() if s.length > 1e-6 else Vector((0, 0, 1))
        return s

    sprites = rects["sprites"].get(item.get("sprites"), [])
    scale = item.get("card_scale", 1.0) * fs_card
    for cd in cards:
        # Тон пучка — від його місця в кроні: верх і зовнішній край світлі, низ і глибина
        # темні, тож крона читається одним об'ємом зі світлим і тіньовим боком. Випадковий
        # тон на кожну картку (два пучки поруч — світлий і темний) робив з крони рябий шум.
        hfrac = min(max((cd["c"][2] - cb) / max(top - cb, 0.5), 0.0), 1.0)
        rfrac = min(math.hypot(cd["c"][0] - ctr.x, cd["c"][1] - ctr.y) / max(rad.x, 0.5), 1.0)
        shade = min(max(0.6 + 0.3 * hfrac + 0.1 * rfrac + 0.04 * math.sin(cd["roll"] * 7.31), 0.55), 1.0)
        vnorm.update(card(bm, uvl, uv2l, col, cd["c"], cd["roll"], cd["size"] * scale,
                          rng.choice(sprites), normal_of, shade))
    flat_sprites = rects["sprites"].get(item.get("flat_sprites", "litter"), [])
    for fl in meta.get("flats", []):
        vnorm.update(flat(bm, uvl, col, fl["c"], fl["roll"], fl["size"], rng.choice(flat_sprites), fl["shade"]))
    n_cards = len(bm.faces)
    trect = rects["trunks"].get(item.get("trunk_of", item["node"]))
    if item.get("trunk", True):
        tt = cb + item.get("trunk_into_crown", 0.3) * (top - cb)
        # trunk_radius — у метрах готового дерева, після масштабу `scale`.
        r = item.get("trunk_radius", meta["trunk_width"] * 0.3 * fs) / fs
        th = meta["trunk_render_height"]
        vnorm.update(trunk(bm, uvl, trect, r, r * 0.45, tt, min(1.0, tt / th),
                           item.get("trunk_sides", 5), tuple(item.get("lean", (0.0, 0.0)))))
    for lm in ([] if item.get("max_cards") else meta.get("limbs", [])):
        vnorm.update(limb(bm, uvl, trect, lm["pts"], lm["r"], lm.get("sides", 3)))
    bm.faces.ensure_lookup_table()
    for f in bm.faces[n_cards:]:  # кора без затінення пучків
        for loop in f.loops:
            loop[col] = (1.0, 1.0, 1.0, 1.0)
    for f in bm.faces:
        for loop in f.loops:
            if loop.vert not in vnorm:
                vnorm[loop.vert] = f.normal
    if fs != 1.0:
        for v in bm.verts:
            v.co *= fs
        for face in bm.faces:
            for loop in face.loops:
                loop[uv2l].uv = (loop[uv2l].uv[0] * fs, loop[uv2l].uv[1] * fs)
    me = bpy.data.meshes.new(item["node"])
    bm.verts.index_update()
    order = list(bm.verts)
    bm.to_mesh(me)
    bm.free()
    me.normals_split_custom_set_from_vertices([tuple(vnorm[v]) for v in order])
    ob = bpy.data.objects.new(item["node"], me)
    bpy.context.scene.collection.objects.link(ob)
    s = 1.0 / TILE_M
    ob.scale = (s, s, s)
    return ob


def material(png, name):
    img = bpy.data.images.load(png)
    img.alpha_mode = "STRAIGHT"
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def patch_glb(path, cutoff):
    """Alpha-cut і однобічність у матеріалі: експортер не завжди їх виставляє."""
    data = open(path, "rb").read()
    jl, jt = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + jl])
    for m in js["materials"]:
        m["alphaMode"] = "MASK"
        m["alphaCutoff"] = cutoff
        # Двобічно: картки з дальнього боку крони видно крізь просвіти ближніх.
        m["doubleSided"] = True
        pbr = m.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        m.pop("extensions", None)
    nj = json.dumps(js, separators=(",", ":")).encode()
    nj += b" " * (-len(nj) % 4)
    rest = data[20 + jl:]
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(nj) + len(rest)) + struct.pack("<II", len(nj), jt) + nj + rest
    open(path, "wb").write(out)


PROXY_FOR = ("Pine", "Spruce", "Birch", "Oak", "Hero", "Shrub")
PROXY_CARDS = 14
PROXY_CARDS_SHRUB = 6  # підлісок здебільшого стоїть у тіні крон


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    spec = json.load(open(SPEC))
    rects = json.load(open(os.path.join(ATLAS_DIR, spec["atlas"] + ".json")))
    mat = material(os.path.join(ATLAS_DIR, spec["atlas"] + ".png"), spec["atlas"])
    obs = []
    for item in spec["items"]:
        if "card_keep" in spec and "card_keep" not in item:
            item["card_keep"] = spec["card_keep"]
        ob = build_node(item, rects)
        ob.data.materials.append(mat)
        obs.append(ob)
        if item["node"].startswith(PROXY_FOR):
            # Сітка лише для тіні (cast_shadow = SHADOWS_ONLY): той самий атлас, ~14 пучків
            # і тригранний стовбур замість сотень трикутників крони в тіньовому проході.
            px = dict(item, node=item["node"] + "_Shadow", trunk_of=item["node"], max_cards=PROXY_CARDS_SHRUB if item["node"].startswith("Shrub") else PROXY_CARDS, trunk_sides=3)
            ob = build_node(px, rects)
            ob.data.materials.append(mat)
            obs.append(ob)
    for o in bpy.context.scene.objects:
        o.select_set(o in obs)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="AUTO", export_texcoords=True,
                              export_normals=True, export_vertex_color="ACTIVE", export_cameras=False, export_lights=False)
    patch_glb(OUT, spec.get("alpha_cutoff", 0.5))
    for o in obs:
        print("NODE", o.name, "tris", sum(len(p.vertices) - 2 for p in o.data.polygons))


main()
