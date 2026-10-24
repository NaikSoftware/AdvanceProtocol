"""Будує GLB лісу: плитки-маси крон (3 варіанти) і краєві клумпи (4 варіанти) для типу лісу.

Запуск:
  blender -b --factory-startup -P build_forest.py -- <art-refs/forest/atlas> <вихід> <ключ>...
Ключі: pine, mixed_late, mixed_summer, mixed_early, deciduous_late, ... shrub_late, shrub_summer,
shrub_early, shrub_conifer. Кожен ключ дає assets-файл forest_<ключ>.glb.

Метри -> одиниці гри: 1 тайл = 8 м = 1,0. Вихідна система координат тут як у Godot:
x вправо, y вгору, z до глядача; відкритий бік клумпа — z = -4 (перед моделі вздовж -Z).
Атлас: див. make_textures.py (три вікна 10x10 м по 640 px і аркуш 640 px із клітинками по 320 px).
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

ATL, OUT = sys.argv[sys.argv.index("--") + 1], sys.argv[sys.argv.index("--") + 2]
KEYS = sys.argv[sys.argv.index("--") + 3:]
S = 0.125  # метр -> одиниці гри
AT = 1280.0  # розмір атласу, px
PXM = 64.0  # px/м у вікні кроною
CROWNS = json.load(open(f"{ATL}/crowns.json"))

# Клітинки аркуша: (x0, y0) у px атласу, розмір 320.
SHEET = {"bark_a": (640, 640), "bark_b": (960, 640), "birch": (640, 960), "shrub": (960, 960)}


def tuv(px, py):
    return (px / AT, 1.0 - py / AT)


def win_uv(cell, mx, my):
    """Точка вікна кроною (метри від лівого верхнього кута 10x10) -> UV атласу."""
    mx = min(max(mx, 0.06), 9.94)
    my = min(max(my, 0.06), 9.94)
    return tuv((cell % 2) * 640 + mx * PXM, (cell // 2) * 640 + my * PXM)


def sheet_uv(name, u, v):
    x0, y0 = SHEET[name]
    u = 4 / 320 + u * (312 / 320)
    v = 4 / 320 + v * (312 / 320)
    return tuv(x0 + u * 320, y0 + v * 320)


def B(x, y, z):
    """Метри (x, y вгору, z до глядача) -> координати Blender у одиницях гри."""
    return (x * S, -z * S, y * S)


class MB:
    def __init__(self, name, mat):
        self.name = name
        self.mat = mat
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def face(self, pts, ref=None):
        """pts: [((x, y, z) у метрах, (u, v))]; ref — бажаний напрям нормалі."""
        vs = [self.bm.verts.new(B(*p)) for p, _ in pts]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return
        for loop, (_, uv) in zip(f.loops, pts):
            loop[self.uv].uv = uv
        if ref is not None and f.normal.dot(Vector(ref)) < 0:
            f.normal_flip()

    def tris(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def build(self):
        me = bpy.data.meshes.new(self.name)
        # Зварені вершини + гладка нормаль: крони освітлюються м'яко, а не гранями. UV лишаються
        # на кутах граней, тож шви атласу не страждають.
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.to_mesh(me)
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        self.bm.free()
        me.materials.append(self.mat)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def trunk(mb, x, z, h, r0, r1, name, rng, seg=8, sections=2, lean=0.0):
    """Стовбур-призма; нормалі назовні. v уздовж висоти на всю клітинку кори."""
    rings = []
    for j in range(sections + 1):
        t = j / sections
        r = r0 + (r1 - r0) * t
        cx = x + lean * t * h
        ring = [(cx + math.cos(i * math.tau / seg) * r, h * t, z + math.sin(i * math.tau / seg) * r)
                for i in range(seg + 1)]
        rings.append((ring, t))
    for j in range(sections):
        (a, ta), (b, tb) = rings[j], rings[j + 1]
        for i in range(seg):
            mx = (a[i][0] + a[i + 1][0]) / 2 - x
            mz = (a[i][2] + a[i + 1][2]) / 2 - z
            u0, u1 = i / seg, (i + 1) / seg
            f = [(a[i], sheet_uv(name, u0, ta)), (a[i + 1], sheet_uv(name, u1, ta)),
                 (b[i + 1], sheet_uv(name, u1, tb)), (b[i], sheet_uv(name, u0, tb))]
            mb.face(f, ref=(mx, -mz, 0))  # Blender: y = -z


def pick_crown(key, kind, rng):
    cands = [(c, r) for c, cell in enumerate(CROWNS[key]) for r in cell if r["kind"] == kind]
    if not cands:
        cands = [(c, r) for c, cell in enumerate(CROWNS[key]) for r in cell]
    return rng.choice(cands)


def crown(mb, key, kind, cx, cy, cz, R, profile, rng, seg=16):
    """Крона-диск або конус: вершина, потім кільця (частка радіуса, зсув по висоті).

    UV — вигляд зверху на справжню крону зі вікна: так видно ту саму масу голок чи гілок,
    що й на плитці-масі, без другої текстури."""
    cell, rec = pick_crown(key, kind, rng)
    rot = rng.uniform(0, math.tau)

    def uvp(px, pz):
        dx, dz = (px - cx) / R * rec["r"], (pz - cz) / R * rec["r"]
        c, s = math.cos(rot), math.sin(rot)
        return win_uv(cell, rec["cx"] + dx * c - dz * s, rec["cy"] + dx * s + dz * c)

    rings = []
    for rf, dy in profile:
        ring = []
        for i in range(seg):
            a = i * math.tau / seg + rng.uniform(-0.12, 0.12)
            r = R * rf * (1 + rng.uniform(-0.12, 0.12)) if rf > 0 else 0.0
            p = (cx + math.cos(a) * r, cy + dy + rng.uniform(-0.15, 0.15) * (rf > 0), cz + math.sin(a) * r)
            ring.append((p, uvp(p[0], p[2])))
        rings.append(ring)
    up = (0, 0, 1)
    for j in range(len(rings) - 1):
        a, b = rings[j], rings[j + 1]
        for i in range(seg):
            n = (i + 1) % seg
            if rings[j][0][0][0] == cx and profile[j][0] == 0:
                mb.face([a[0], b[i], b[n]], ref=up)
            else:
                mb.face([a[i], b[i], b[n], a[n]], ref=up)


DISC = [(0, 0.7), (0.4, 0.45), (0.8, 0.0), (1.0, -0.7)]
DOME = [(0, 1.1), (0.45, 0.8), (0.85, 0.1), (1.0, -0.9)]


def hull(mb, key, cell, top, relief, skirt_h, rng, half=False):
    """Лумпова оболонка крон: верх, спідниця, нижній шар. UV — вікно кроною планарно зверху."""
    n = 6
    z0, z1 = (-0.8, 4.9) if half else (-4.9, 4.9)
    nz = 3 if half else n
    ph = [rng.uniform(0, math.tau) for _ in range(4)]

    def hgt(x, z, rim):
        h = top + relief * (math.sin(x * 0.7 + ph[0]) * math.cos(z * 0.6 + ph[1])
                            + 0.5 * math.sin(x * 1.3 + z * 1.1 + ph[2]))
        return h - rim * 0.1

    xs = [-4.9 + 9.8 * i / n for i in range(n + 1)]
    zs = [z0 + (z1 - z0) * j / nz for j in range(nz + 1)]

    def pt(i, j):
        rim = 1.0 if i in (0, n) or j in (0, nz) else 0.0
        x, z = xs[i], zs[j]
        return ((x, hgt(x, z, rim), z), win_uv(cell, x + 5, z + 5))

    for j in range(nz):
        for i in range(n):
            q = [pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1)]
            mb.face(q, ref=(0, 0, 1))
    # Спідниця по краях: до висоти основи крон, трохи назовні.
    rim = [(i, 0) for i in range(n)] + [(n, j) for j in range(nz)] + [(n - i, nz) for i in range(n)] + [(0, nz - j) for j in range(nz)]
    nxt = rim[1:] + rim[:1]
    for (i0, j0), (i1, j1) in zip(rim, nxt):
        if half and j0 == nz and j1 == nz:
            continue  # тильний край не видно
        if half and i0 == i1 and i0 in (0, n):
            continue  # бічні стіни клумпа стирчали пласкими плитами біля кутів
        a, b = pt(i0, j0), pt(i1, j1)
        horizontal = j0 == j1

        def out(p, drop):
            x, y, z = p[0]
            ox, oz = min(max(x * 1.08, -5), 5), min(max(z * 1.08, -5), 5)
            along = (ox if horizontal else oz) + 5.0
            # Стіна показує ту саму масу голок, що й верх, у масштабі 1:1: UV іде вздовж краю й
            # униз, а не тягне верхню текстуру вертикальними смугами.
            return ((ox, skirt_h + rng.uniform(-0.6, 0.6), oz), win_uv(cell, along, 2.5 + drop * 0.7))

        def rim_pt(p):
            along = (p[0][0] if horizontal else p[0][2]) + 5.0
            return (p[0], win_uv(cell, along, 2.5))

        drop = max(0.5, (a[0][1] - skirt_h))
        mb.face([rim_pt(a), rim_pt(b), out(b, drop), out(a, drop)], ref=(a[0][0], 0.2, 0))
    if key.endswith("_late"):
        return  # голі гілки: другий шар закрив би землю, а сезон мусить її показувати
    # Нижній шар: інше вікно кроною, дзеркально, щоб бачились темніші крони під верхніми.
    m = 4
    for j in range(m):
        for i in range(m):
            def q(ii, jj):
                x = -3.6 + 7.2 * ii / m
                z = (z0 + 1.2) + (z1 - z0 - 2.4) * jj / m if half else -3.6 + 7.2 * jj / m
                return ((x, hgt(x, z, 0) - 4.2, z), win_uv((cell + 1) % 3, 5 - x, 5 + z))
            mb.face([q(i, j), q(i + 1, j), q(i + 1, j + 1), q(i, j + 1)], ref=(0, 0, 1))


def shrub(mb, cx, cz, w, h, rng):
    """Кущ-картка: 3 вертикальні квади навхрест і похила «шапка»; текстура — клітинка куща."""
    for k in range(3):
        a = k * math.pi / 3 + rng.uniform(-0.2, 0.2)
        dx, dz = math.cos(a) * w / 2, math.sin(a) * w / 2
        mb.face([((cx - dx, 0, cz - dz), sheet_uv("shrub", 0, 1)), ((cx + dx, 0, cz + dz), sheet_uv("shrub", 1, 1)),
                 ((cx + dx * 0.85, h, cz + dz * 0.85), sheet_uv("shrub", 1, 0)),
                 ((cx - dx * 0.85, h, cz - dz * 0.85), sheet_uv("shrub", 0, 0))], ref=(0, 0, 1))
    r = w * 0.45
    mb.face([((cx - r, h * 0.8, cz - r), sheet_uv("shrub", 0, 1)), ((cx + r, h * 0.8, cz - r), sheet_uv("shrub", 1, 1)),
             ((cx + r, h * 0.95, cz + r), sheet_uv("shrub", 1, 0)), ((cx - r, h * 0.95, cz + r), sheet_uv("shrub", 0, 0))], ref=(0, 0, 1))


def material(png, name):
    img = bpy.data.images.load(png)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    m.use_backface_culling = False
    return m


def patch_glb(path):
    """Alpha-cut і двобічність у матеріалі: експортер не завжди їх виставляє."""
    data = open(path, "rb").read()
    jl, jt = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + jl])
    for m in js["materials"]:
        m["alphaMode"] = "MASK"
        m["alphaCutoff"] = 0.5
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


# ---------- склад клумпів і плиток за типом ----------

TREES = {
    # (тип крони, кора, радіус стовбура, висота стовбура, радіус крони, висота центру крони, профіль)
    "pine": {
        "front": [("spruce", "bark_a", 0.16, 0, 2.4, 0, "cone"), ("pine", "bark_a", 0.2, 7.0, 2.2, 8.4, DISC),
                  ("spruce", "bark_a", 0.16, 0, 2.7, 0, "cone"), ("pine", "bark_a", 0.22, 8.0, 2.4, 9.4, DISC)],
        "mid": [("pine", "bark_a", 0.3, 12.0, 3.0, 13.2, DISC), ("pine", "bark_a", 0.28, 11.0, 2.8, 12.4, DISC)],
    },
    "mixed": {
        "front": [("spruce", "bark_a", 0.16, 0, 2.5, 0, "cone"), ("broad", "birch", 0.14, 7.5, 2.0, 8.6, DOME),
                  ("broad", "bark_b", 0.24, 6.0, 2.7, 7.4, DOME), ("pine", "bark_a", 0.2, 7.5, 2.2, 8.7, DISC)],
        "mid": [("pine", "bark_a", 0.3, 12.0, 3.0, 13.2, DISC), ("broad", "bark_b", 0.32, 9.5, 3.4, 11.0, DOME)],
    },
    "deciduous": {
        "front": [("broad", "birch", 0.14, 7.5, 2.0, 8.6, DOME), ("broad", "bark_b", 0.26, 5.5, 2.9, 7.0, DOME),
                  ("broad", "birch", 0.14, 8.0, 2.1, 9.2, DOME), ("broad", "bark_b", 0.28, 6.0, 3.0, 7.6, DOME)],
        "mid": [("broad", "bark_b", 0.36, 10.0, 3.8, 11.8, DOME), ("broad", "bark_b", 0.34, 9.5, 3.6, 11.2, DOME)],
    },
}
TOP = {"pine": 18.0, "mixed": 16.5, "deciduous": 15.5}
SKIRT = {"pine": 14.5, "mixed": 13.0, "deciduous": 11.5}


def place_tree(mb, key, spec, x, z, rng, scale=1.0):
    kind, bark, tr, th, R, cyc, prof = spec
    R *= scale
    if th > 0:
        trunk(mb, x, z, th, tr * 1.25, tr, bark, rng, seg=8, sections=3)
    if prof == "cone":
        # Ялина зеленіє до землі: три яруси, нижній найширший.
        top_y = rng.uniform(8.0, 10.0)
        for k in range(3):
            t = (k + 1) / 3
            crown(mb, key, "spruce", x, top_y - (2 - k) * 2.6, z,
                  R * (0.5 + 0.5 * t), [(0, 1.7), (0.5, 0.7), (1.0, -1.0)], rng, seg=16)
    else:
        crown(mb, key, kind, x, cyc, z, R, prof, rng, seg=22)


def edge_clump(mb, key, tname, v, rng):
    t = TREES[tname]
    hull(mb, key, v % 3, TOP[tname], 0.35, SKIRT[tname], rng, half=True)
    xs = [-3.0, -1.0, 1.0, 3.0]
    rng.shuffle(xs)
    n_front = 3 + (v % 2)
    for i in range(n_front):
        spec = t["front"][(i + v) % 4]
        place_tree(mb, key, spec, xs[i] + rng.uniform(-0.5, 0.5), rng.uniform(-3.0, -2.0), rng, rng.uniform(0.9, 1.1))
    for i in range(2):
        place_tree(mb, key, t["mid"][(i + v) % 2], (-2.0 if i == 0 else 2.2) + rng.uniform(-0.8, 0.8),
                   rng.uniform(-0.3, 0.8), rng, rng.uniform(0.95, 1.1))
    # Пояс кущів на відкритому боці: низький, густіший за інтер'єр.
    for k in range(7 + v % 2):
        w = rng.uniform(1.8, 3.6)
        x = min(max(-4.0 + k * 1.2 + rng.uniform(-0.6, 0.6), -5 + w / 2), 5 - w / 2)
        shrub(mb, x, rng.uniform(-5 + w * 0.5, -2.6), w, rng.uniform(1.6, 4.2), rng)


def canopy_tile(mb, key, tname, v, rng):
    hull(mb, key, v, TOP[tname] + rng.uniform(-0.4, 0.4), 0.35, SKIRT[tname], rng)
    spots = [(-3.0, -2.5), (2.8, -3.0), (-1.0, 2.9), (3.2, 2.2), (0.4, -0.2), (-3.4, 1.0)]
    rng.shuffle(spots)
    bark = "bark_b" if tname == "deciduous" else "bark_a"
    for (x, z) in spots[:5]:
        trunk(mb, x, z, TOP[tname] - 1.5, 0.3, 0.22, bark, rng, seg=6, sections=1)


def export(key):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rng = random.Random(sum(map(ord, key)))
    stats = {}
    tname = key.split("_")[0]
    mat = material(f"{ATL}/atlas_{key}.png", "forest_" + key)
    obs = []
    for v in range(3):
        mb = MB(f"Canopy_{v}", mat)
        canopy_tile(mb, key, tname, v, rng)
        stats[mb.name] = mb.tris()
        obs.append(mb.build())
    for v in range(4):
        mb = MB(f"Edge_{v}", mat)
        edge_clump(mb, key, tname, v, rng)
        stats[mb.name] = mb.tris()
        obs.append(mb.build())
    return obs, stats


def export_shrub(key):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rng = random.Random(sum(map(ord, key)))
    global SHEET, AT
    mat = material(f"{ATL}/shrub_{key.split('_')[1]}.png", "forest_" + key)
    old = (SHEET, AT)
    SHEET = {"shrub": (0, 0)}  # окремий малий атлас: лише клітинка куща
    AT = 320.0
    stats, obs = {}, []
    for i in range(3):
        mb = MB(f"Shrub_{i}", mat)
        w, h = [(2.2, 2.2), (3.4, 3.2), (4.8, 4.4)][i]
        shrub(mb, 0, 0, w, h, rng)
        stats[mb.name] = mb.tris()
        obs.append(mb.build())
    SHEET, AT = old
    return obs, stats


for key in KEYS:
    obs, stats = export_shrub(key) if key.startswith("shrub") else export(key)
    path = f"{OUT}/forest_{key}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="AUTO", export_texcoords=True,
                              export_normals=True, export_cameras=False, export_lights=False)
    patch_glb(path)
    for f in os.listdir(OUT):  # експортер лишає поруч копію атласу, а в GLB він уже вбудований
        if f.startswith(f"forest_{key}_") and f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    print("BUILT", key, json.dumps(stats))
