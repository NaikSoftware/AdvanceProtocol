"""Мости річкової карти: три різні силуети й зруйнований стан кожного.

Запуск: blender -b --factory-startup -P tools/blender/bridges/build_bridges.py -- <out_dir>

Один світ — одиниця = клітинка = 8 м. Вісь мосту — Y у Blender (у Godot це -Z), поперек — X,
вгору — Z. Нуль Z — найнижча точка моделі (низ опори чи понтона), а верх настилу лежить на
DECK_TOP над нею: сцена ставить модель на `deck_y(клітинка) - DECK_TOP`, тоді настил збігається
з дорогою на берегах, а підошва стоїть на дні русла.

Зруйнований стан не окремий малюнок: той самий збирач, що й цілий, віддає групи частин
(прольоти, секції, плити), а `broken` лише повертає й зсуває ці групи та додає уламки.
"""
import math
import json
import os
import struct
import sys

import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]
TEX_DIR = os.path.join(OUT, "bridge_tex")  # одна текстура на матеріал для всіх шести мостів
os.makedirs(TEX_DIR, exist_ok=True)

# --- матеріали: (колір sRGB, шорсткість, металічність). Колір береться з текстури 512 px, що лягає
# на клітинку (8 м), тобто ~1.6 см на піксель; тут лише середній тон для довідки.
MATS = {
    "concrete": ((0.50, 0.49, 0.47), 0.95, 0.0),
    "concrete_dust": ((0.68, 0.66, 0.62), 1.0, 0.0),
    "asphalt": ((0.16, 0.16, 0.165), 0.95, 0.0),
    "steel_olive": ((0.20, 0.24, 0.17), 0.7, 0.4),
    "timber": ((0.36, 0.28, 0.19), 0.95, 0.0),
    "steel_grey": ((0.30, 0.32, 0.31), 0.6, 0.5),
    "deckplate": ((0.42, 0.43, 0.38), 0.85, 0.3),
}
MAT_ORDER = list(MATS)

# Верх настилу над нулем Z (низом моделі). Бетон і панельний міст стоять на дні, понтон плаває:
# дно русла на 2.2-2.7 м під верхом берега, вода на 1.25 м.
DECK_TOP = {"centre": 0.30, "west": 0.30, "east": 0.22}


TILE_M = 1.0  # одна текстура = клітинка (одиниця світу)


class Box:
    """Паралелепіпед без днища: підвище не видно, а трикутників менше."""

    def __init__(self, mat, c, s, rot=None):
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        self.mat = mat
        self.v = [Vector(p) for p in (
            (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
            (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz))]
        if rot is not None:
            self.v = [rot @ p for p in self.v]
        self.v = [p + Vector(c) for p in self.v]
        self.uv = self._uv(c, s)

    def _uv(self, c, s):
        """Розгортка в метрах світу (тайл = 8 м = одна текстура 512 px, ~1.6 см/піксель):
        шов не залежить від розміру коробки, а щойно коробку повернули чи зсунули, текстура
        їде з нею. Асфальт — виняток: його текстура лежить упоперек, з крайовими лініями."""
        out = []
        for f in FACES:
            q = [self.v[i] for i in f]
            n = (q[1] - q[0]).cross(q[3] - q[0])
            ax = max(range(3), key=lambda k: abs(n[k]))
            if f == FACES[4] and self.mat == "asphalt":
                out.append([((p.x - c[0]) / s[0] + 0.5, p.y / TILE_M) for p in q])
            elif ax == 2:
                out.append([(p.x / TILE_M, p.y / TILE_M) for p in q])
            elif ax == 1:
                out.append([(p.x / TILE_M, p.z / TILE_M) for p in q])
            else:
                out.append([(p.y / TILE_M, p.z / TILE_M) for p in q])
        return out


def xf(group, m):
    for b in group:
        b.v = [m @ p for p in b.v]


def about(pivot, rot):
    """Поворот навколо точки pivot (rot — Matrix 3x3)."""
    p = Vector(pivot)
    return Matrix.Translation(p) @ rot.to_4x4() @ Matrix.Translation(-p)


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def zmin(group):
    return min(p.z for b in group for p in b.v)


def ground(group):
    """Опускає групу так, щоб її найнижча точка торкалась дна."""
    xf(group, Matrix.Translation((0, 0, -zmin(group))))


# ---------------------------------------------------------------- центр: бетонна балка, 3 клітинки
def concrete(broken):
    L, W = 3.0, 0.88
    DT = DECK_TOP["centre"]
    th = 0.14  # плита 1.1 м
    bot = DT - th

    def span(y0, y1):
        """Проліт: плита, асфальт, дві розмітки, два парапети."""
        n = y1 - y0
        yc = (y0 + y1) / 2
        g = [Box("concrete", (0, yc, bot + th / 2), (W, n, th)),
             Box("asphalt", (0, yc, DT + 0.004), (W - 0.2, n, 0.008))]
        for sx in (-1, 1):
            g.append(Box("concrete", (sx * (W / 2 - 0.03), yc, DT + 0.055), (0.06, n, 0.11)))
        return g

    # Бетон: два прольоти по 12 м й опора посередині. Береги тримають упори на кінцях.
    pier = [Box("concrete", (0, 0, bot / 2), (W - 0.12, 0.125, bot)),
            Box("concrete", (0, 0, bot - 0.015), (W + 0.02, 0.16, 0.03))]
    abut = [Box("concrete", (0, sy * (L / 2 - 0.09), bot / 2), (W + 0.02, 0.18, bot)) for sy in (-1, 1)]
    if not broken:
        return {"pier": pier, "abut": abut, "span1": span(-L / 2, 0), "span2": span(0, L / 2)}

    s1 = span(-L / 2, 0)
    # Другий проліт: плита біля берега провисла, середня плита обвалилась, третя лежить у воді.
    near = span(1.0, L / 2)
    xf(near, about((0, L / 2, DT - 0.02), rx(3)))
    xf(near, Matrix.Translation((0, -0.008, 0)))
    drop = span(0.42, 1.0 - 0.01)
    xf(drop, about((0, 1.0, DT - 0.03), rx(17)))
    xf(drop, Matrix.Translation((0.04, 0, 0)) @ about((0, 0.7, 0.2), rz(5)))
    fall = [Box("concrete", (0.12, 0.22, 0.08), (0.36, 0.34, 0.07), rx(9) @ rz(-14)),
            Box("concrete_dust", (-0.18, 0.4, 0.05), (0.24, 0.2, 0.05), ry(11) @ rz(30)),
            Box("concrete", (0.2, 0.78, 0.05), (0.2, 0.16, 0.05), rx(-18) @ rz(40))]
    # Парапет, що звис з обламаного краю, пил на уламках. Арматура дрібніша за 15 см: лише в текстурі.
    hang = [Box("concrete", (-W / 2 + 0.03, 0.34, 0.1), (0.05, 0.22, 0.09), rx(35) @ rz(8))]
    dust = [Box("concrete_dust", (0.0, 0.1, bot - 0.02), (0.5, 0.1, 0.04), rz(3))]
    return {"pier": pier, "abut": abut, "span1": s1, "near": near, "drop": drop,
            "fall": fall, "hang": hang, "dust": dust}


# ---------------------------------------------------------------- захід: панельна ферма
def bailey(broken):
    L = 2.0
    DT = DECK_TOP["west"]
    PL, PH = 3.0 / 8, 1.5 / 8  # панель 3.0 × 1.5 м
    N = 5
    y0 = -N * PL / 2
    rw = 3.7 / 8  # проїзна частина
    tw = 0.04  # стінка ферми (0.3 м)
    xt = rw / 2 + tw / 2

    def panel(i):
        ya, yb = y0 + i * PL, y0 + (i + 1) * PL
        yc = (ya + yb) / 2
        g = [Box("timber", (0, yc, DT - 0.02), (rw, PL, 0.04)),
             Box("steel_olive", (0, yc, DT - 0.05), (rw + 2 * tw, 0.03, 0.025)),
             Box("steel_olive", (0, ya + 0.015, DT - 0.045), (rw + 2 * tw, 0.02, 0.03))]
        diag_len = math.hypot(PL, PH)
        ang = math.degrees(math.atan2(PH, PL)) * (1 if i % 2 == 0 else -1)
        for sx in (-1, 1):
            g.append(Box("steel_olive", (sx * xt, yc, DT + 0.01), (tw, PL, 0.022)))  # нижній пояс
            g.append(Box("steel_olive", (sx * xt, yc, DT + PH - 0.005), (tw, PL, 0.022)))  # верхній
            g.append(Box("steel_olive", (sx * xt, ya + 0.01, DT + PH / 2), (tw, 0.02, PH)))  # стійка
            g.append(Box("steel_olive", (sx * xt, yc, DT + PH / 2), (tw - 0.01, diag_len, 0.014), rx(ang)))
        return g

    panels = [panel(i) for i in range(N)]
    end = [Box("steel_olive", (sx * xt, sy * (N * PL / 2), DT + PH / 2), (tw, 0.02, PH))
           for sx in (-1, 1) for sy in (-1, 1)]
    # Опори: бетонні лежні на кінцях переправи; їхня довжина не виходить за 2 клітинки.
    abut = [Box("concrete", (0, sy * (L / 2 - 0.08), (DT - 0.045) / 2), (0.7, 0.16, DT - 0.045))
            for sy in (-1, 1)]
    abut += [Box("concrete", (0, sy * (L / 2 - 0.08), DT - 0.045 + 0.0), (0.74, 0.16, 0.02)) for sy in (-1, 1)]
    if not broken:
        return {"abut": abut, "end": end, **{f"p{i}": p for i, p in enumerate(panels)}}

    # Західний кінець зірвався з опори: дві панелі провисли, середня випала й лежить на боці,
    # східна половина сіла на 4°. Між ними щілина ширша за 4 м.
    west = panels[0] + panels[1]
    xf(west, about((0, y0 + 2 * PL, DT), rx(11)))
    xf(west, Matrix.Translation((0.03, 0.0, 0)) @ about((0, y0, DT), rz(-4)))
    mid = panels[2]
    xf(mid, about((0, 0, DT + PH / 2), ry(38) @ rx(8)))
    xf(mid, Matrix.Translation((0.22, -0.02, -0.12)))
    ground(mid)
    east = panels[3] + panels[4] + end[2:]
    xf(east, about((0, L / 2 - 0.06, DT), rx(-3)))
    planks = [Box("timber", (0.1 * k - 0.05, 0.16 + 0.03 * k, 0.03 + 0.012 * k), (0.34, 0.07, 0.015), rz(10 * k - 15))
              for k in range(4)]
    return {"abut": abut, "west": west, "mid": mid, "east": east, "planks": planks, "endw": end[:2]}


# ---------------------------------------------------------------- схід: понтонний міст
def pontoon(broken):
    DT = DECK_TOP["east"]
    hw, hh = 0.85, 0.20  # корпус 6.8 м × 1.6 м
    rwid = 0.60

    def bay(y0, y1, ramp=False):
        n = y1 - y0
        yc = (y0 + y1) / 2
        g = [Box("steel_grey", (0, yc, hh / 2), (hw, n - 0.012, hh)),
             Box("deckplate", (0, yc, hh + 0.01), (rwid, n - 0.012, 0.02))]
        for sx in (-1, 1):
            g.append(Box("steel_grey", (sx * (rwid / 2 + 0.012), yc, hh + 0.016), (0.024, n - 0.012, 0.032)))
            g.append(Box("steel_grey", (sx * (hw / 2 - 0.03), yc, hh + 0.012), (0.06, n - 0.012, 0.024)))
            if not ramp:
                g.append(Box("steel_grey", (sx * (hw / 2 - 0.03), yc, hh + 0.04), (0.03, 0.03, 0.04)))
        return g

    # 2 клітинки замало для відсіків по 6.7 м з аппарелями: чотири відсіки довжини 0.45-0.55.
    bays = {"r0": bay(-1.0, -0.55, True), "b1": bay(-0.55, 0.0), "b2": bay(0.0, 0.55), "r1": bay(0.55, 1.0, True)}
    plates = [Box("steel_grey", (0, sy * 0.98, hh + 0.012), (rwid, 0.04, 0.012)) for sy in (-1, 1)]
    if not broken:
        return {**bays, "plates": plates}

    # Відсіки розійшлись: один знесло за течією й він сів на дно боком, другий розвернуло.
    b1 = bays["b1"]
    xf(b1, about((0, -0.55, 0), rz(-17)))
    b2 = bays["b2"]
    xf(b2, about((0, 0.275, 0), rz(-14) @ rx(-13) @ ry(3)))
    xf(b2, Matrix.Translation((0.24, 0.10, 0)))
    ground(b2)
    return {"r0": bays["r0"], "b1": b1, "b2": b2, "r1": bays["r1"], "plates": plates}


MODELS = {
    "bridge_river_centre": (concrete, False),
    "bridge_river_centre_broken": (concrete, True),
    "bridge_river_west": (bailey, False),
    "bridge_river_west_broken": (bailey, True),
    "bridge_river_east": (pontoon, False),
    "bridge_river_east_broken": (pontoon, True),
}


TEX = 512


def _noise(rng, sigma_x, sigma_y=None, size=TEX):
    """Тайлова шумова картинка: білий шум, відфільтрований у частотній області."""
    import numpy as np
    sigma_y = sigma_x if sigma_y is None else sigma_y
    f = np.fft.fft2(rng.standard_normal((size, size)))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    f *= np.exp(-0.5 * ((fx * size * sigma_x * 0.04) ** 2 + (fy * size * sigma_y * 0.04) ** 2) * 6.0)
    n = np.real(np.fft.ifft2(f))
    return (n - n.mean()) / (n.std() + 1e-9)


def make_texture(name):
    import numpy as np
    rng = np.random.default_rng(sum(map(ord, name)))
    base = np.array(MATS[name][0])
    yy, xx = np.mgrid[0:TEX, 0:TEX] / TEX  # yy — рядки (v), xx — стовпці (u)
    img = np.ones((TEX, TEX, 3)) * base
    lum = np.zeros((TEX, TEX))
    if name in ("concrete", "concrete_dust"):
        lum = 0.035 * _noise(rng, 12) + 0.025 * _noise(rng, 2.0) + 0.02 * _noise(rng, 0.7)
        lum -= 0.03 * np.clip(_noise(rng, 1.0, 14) - 0.8, 0, None)  # патьоки від води
        lum -= 0.04 * (_noise(rng, 0.6) > 2.4)  # пори
    elif name == "asphalt":
        lum = 0.02 * _noise(rng, 1.0) + 0.02 * _noise(rng, 0.5) + 0.01 * _noise(rng, 8)
        for cu in (0.28, 0.72):  # смуги, виїжджені колесами
            lum -= 0.025 * np.exp(-((xx - cu) / 0.07) ** 2)
        lum += 0.04 * (_noise(rng, 0.45) > 2.2)  # зерно щебеню
        for cu in (0.045, 0.955):  # крайові лінії
            w = (np.abs(xx - cu) < 0.011) * (_noise(rng, 2.0) > -1.2)
            img = np.where(w[..., None], np.array([0.62, 0.62, 0.58]) * (1 + 0.1 * _noise(rng, 0.6))[..., None], img)
        dash = (np.abs(xx - 0.5) < 0.008) & ((yy % 0.5) < 0.25) & (_noise(rng, 2.0) > -1.2)
        img = np.where(dash[..., None], np.array([0.60, 0.60, 0.56]) * (1 + 0.1 * _noise(rng, 0.6))[..., None], img)
    elif name == "steel_olive":
        lum = 0.04 * _noise(rng, 3) + 0.03 * _noise(rng, 0.6)
        wear = _noise(rng, 1.2) > 1.7
        img = np.where(wear[..., None], np.array([0.38, 0.22, 0.12]), img)  # облущена фарба
    elif name == "timber":
        rows = 32
        pid = np.floor(yy * rows)
        tint = rng.uniform(-0.06, 0.06, rows)[pid.astype(int)]
        lum = tint + 0.05 * _noise(rng, 14, 0.5) + 0.02 * _noise(rng, 0.6)
        seam = (yy * rows) % 1.0
        lum -= 0.16 * ((seam < 0.07) | (seam > 0.95))
        butt = (rng.uniform(0, 1, rows)[pid.astype(int)] - xx)
        lum -= 0.14 * (np.abs(butt) < 0.006)
    elif name == "steel_grey":
        lum = 0.04 * _noise(rng, 3) + 0.04 * _noise(rng, 0.8, 10) + 0.02 * _noise(rng, 0.5)
    elif name == "deckplate":
        lum = 0.025 * _noise(rng, 2.5) + 0.02 * _noise(rng, 0.5)
        lum -= 0.12 * (((xx * 4) % 1.0 < 0.012) | ((yy * 4) % 1.0 < 0.012))  # стики листів 2 м
        lum += 0.04 * (_noise(rng, 6) > 1.0)
    elif name == "rust":
        lum = 0.10 * _noise(rng, 1.5) + 0.05 * _noise(rng, 0.5)
    img = np.clip(img + lum[..., None], 0, 1)
    px = np.concatenate([img, np.ones((TEX, TEX, 1))], axis=2)
    # Blender: перший рядок — низ картинки; вертикаль не віддзеркалюється, бо v росте вгору.
    return px.astype("float32")


FACES = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]


def build(name, fn, broken):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = fn(broken)
    mats = {}
    for k in MAT_ORDER:
        c, r, m = MATS[k]
        img = bpy.data.images.new(f"bridge_{k}", TEX, TEX, alpha=False)
        img.pixels.foreach_set(make_texture(k).ravel())
        img.filepath_raw = f"{TEX_DIR}/{k}.png"
        img.file_format = "PNG"
        img.save()
        mat = bpy.data.materials.new(f"bridge_{k}")
        mat.use_nodes = True
        b = mat.node_tree.nodes["Principled BSDF"]
        t = mat.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        mat.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = r
        b.inputs["Metallic"].default_value = m
        mats[k] = mat
    verts, faces, midx, uvs = [], [], [], []
    for g in groups.values():
        for b in g:
            base = len(verts)
            verts += [tuple(p) for p in b.v]
            for f, uv in zip(FACES, b.uv):
                faces.append(tuple(base + i for i in f))
                midx.append(MAT_ORDER.index(b.mat))
                uvs += uv
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for k in MAT_ORDER:
        mesh.materials.append(mats[k])
    for p, mi in zip(mesh.polygons, midx):
        p.material_index = mi
    layer = mesh.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", [c for uv in uvs for c in uv])
    mesh.update()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Нормалі назовні: порядок обходу граней задано для додатного об'єму, перевіряємо явно.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    print(f"BRIDGE {name} x[{min(xs):.3f},{max(xs):.3f}] y[{min(ys):.3f},{max(ys):.3f}] "
          f"z[{min(zs):.3f},{max(zs):.3f}] tris={sum(len(p.vertices) - 2 for p in mesh.polygons)}")
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{name}.glb", export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_keep_originals=True)
    strip_image_views(f"{OUT}/{name}.glb")


def strip_image_views(path):
    """Експортер лишає в зовнішньої картинки і uri, і bufferView — це недійсне glTF."""
    d = open(path, "rb").read()
    n, _ = struct.unpack_from("<II", d, 12)
    g = json.loads(d[20:20 + n])
    for im in g.get("images", []):
        im.pop("bufferView", None)
    j = json.dumps(g, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    rest = d[20 + n:]
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(j) + len(rest)) + struct.pack("<II", len(j), 0x4E4F534A) + j + rest
    open(path, "wb").write(out)


for n, (f, b) in MODELS.items():
    build(n, f, b)
