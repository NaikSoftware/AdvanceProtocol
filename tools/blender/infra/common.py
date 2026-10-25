"""Спільне для скриптів tools/blender/infra: матеріали, примітиви, експорт у GLB.

Запуск: blender -b --factory-startup -P <скрипт>.py -- [імена активів]
Будуємо в метрах (+Y = перед, +Z = вгору), на виході множимо на 1/8 (один тайл = 8 м = 1.0).
Текстури ambientCG беруться з каталогу $INFRA_ACG (розпаковані 1K-JPG), зменшуються до 512 px
і тонуються/старяться тут же — у GLB вшиті вже готові.
"""
import bpy, bmesh, os, sys, json, struct, math
import numpy as np
from mathutils import Matrix, Vector

S = 0.125
ACG = os.environ.get("INFRA_ACG", "")
OUT = os.environ.get("INFRA_OUT", os.path.join(os.path.dirname(__file__), "..", "..", "..", "assets", "props"))
OUT = os.path.abspath(OUT)
SIZE = 512


def args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


# ---------- текстури ----------
def tile_noise(cx, cy, size, seed):
    g = np.random.default_rng(seed).random((cy, cx))
    ys = np.arange(size) * cy / size
    xs = np.arange(size) * cx / size
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = ys - y0; fx = xs - x0
    fy = (fy * fy * (3 - 2 * fy))[:, None]; fx = (fx * fx * (3 - 2 * fx))[None, :]
    y0, y1 = y0[:, None] % cy, (y0[:, None] + 1) % cy
    x0, x1 = x0[None, :] % cx, (x0[None, :] + 1) % cx
    return (g[y0, x0] * (1 - fx) + g[y0, x1] * fx) * (1 - fy) + (g[y1, x0] * (1 - fx) + g[y1, x1] * fx) * fy


def fbm(size, seed, base=4, octaves=4):
    out = np.zeros((size, size)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        out += amp * tile_noise(base * 2 ** o, base * 2 ** o, size, seed + o); tot += amp; amp *= 0.5
    return out / tot


def normal_from_height(h, k):
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    n = np.stack([-dx * k, -dy * k, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def _img_from_array(name, arr, jpeg=True, srgb=True):
    h, w = arr.shape[:2]
    if srgb:                                   # масиви — у sRGB-значеннях; Blender кодує лінійні при збереженні
        arr = np.concatenate([srgb_to_lin(np.clip(arr[..., :3], 0, 1)), arr[..., 3:]], -1)
    if arr.shape[2] == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1))], -1)
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=True)
    if not srgb:
        img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.clip(arr, 0, 1).astype(np.float32).ravel())
    img.file_format = "JPEG" if jpeg else "PNG"
    return img


def load_acg(mat, kind, size=SIZE):
    path = os.path.join(ACG, mat, f"{mat}_1K-JPG_{kind}.jpg")
    img = bpy.data.images.load(path)
    if kind != "Color":
        img.colorspace_settings.name = "Non-Color"
    img.scale(size, size)
    a = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    a = a.reshape(size, size, 4)[..., :3].astype(np.float64)
    return lin_to_srgb(a) if kind == "Color" else a


def srgb_to_lin(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c): return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.clip(c, 0, None) ** (1 / 2.4) - 0.055)


_mat_cache = {}


def acg_albedo(src, tint, sat, rust, seed, grime=0.0, paint=None, contrast=1.0, size=SIZE):
    """Albedo ambientCG: десатурація, тон, плями іржі та бруду з тайлового шуму."""
    a = load_acg(src, "Color", size)
    lum = (a * [0.2126, 0.7152, 0.0722]).sum(-1, keepdims=True)
    a = lum + (a - lum) * sat
    mean = a.mean((0, 1), keepdims=True)
    a = mean + (a - mean) * contrast
    if paint is not None:                       # фарба: яскравість із текстури, колір заданий
        a = np.repeat(a.mean(-1, keepdims=True) / a.mean(), 3, -1) * np.array(paint)
    a = a * np.array(tint)
    if rust > 0:
        m = np.clip((fbm(size, seed, 3) - 0.5) * 4 + 0.5, 0, 1)[..., None] * rust
        a = a * (1 - m) + np.array([0.36, 0.17, 0.08]) * (lum * 1.6 + 0.2) * m
    if grime > 0:
        m = np.clip((fbm(size, seed + 40, 6) - 0.4) * 3, 0, 1)[..., None] * grime
        a = a * (1 - 0.55 * m)
    return np.clip(a, 0, 1)


def pbr(name, src=None, tile=1.0, tint=(1, 1, 1), sat=1.0, rust=0.0, grime=0.0, rough=0.8, metal=0.0,
        seed=1, res=None, tile_v=None, paint=None, contrast=1.0, color=None, albedo=None, normal=None, alpha=False, double_sided=False):
    """Матеріал: tile — скільки метрів вкриває одна текстура; color — суцільний колір без текстур."""
    if name in _mat_cache:
        return _mat_cache[name]
    # ~1,5–3 см на тексель: менша деталь на екрані (7 см/px) однаково не читається
    size = res or int(min(512, max(64, 2 ** round(math.log2(tile / 0.02)))))
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if color is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    else:
        if albedo is None:
            albedo = acg_albedo(src, tint, sat, rust, seed, grime, paint, contrast, size)
        ti = nt.nodes.new("ShaderNodeTexImage")
        ti.image = _img_from_array(name + "_a", albedo, jpeg=not alpha)
        nt.links.new(ti.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            nt.links.new(ti.outputs["Alpha"], bsdf.inputs["Alpha"])
        if normal is None and src:
            normal = np.concatenate([load_acg(src, "NormalGL", size), np.ones((size, size, 1))], -1)
        if normal is not None and os.environ.get("INFRA_NONORMAL") != "1":
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = _img_from_array(name + "_n", normal, srgb=False)
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if alpha:
        if hasattr(m, "blend_method"):
            m.blend_method = "CLIP"
    m.use_backface_culling = not double_sided
    m["alpha_mask"] = alpha
    m["tile"] = tile
    m["tile_v"] = tile_v or tile
    m["cm_texel"] = round(tile / (albedo.shape[0] if albedo is not None else size) * 100, 2)
    _mat_cache[name] = m
    return m


# ---------- геометрія ----------
class B:
    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []
        self.empties = []
        self.skip_uv = set()
        self.tone = 1.0
        self.col = self.bm.loops.layers.float_color.new("Color")

    def mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _tag(self, mat, verts):
        i = self.mi(mat)
        for v in verts:
            for f in v.link_faces:
                f.material_index = i
                for l in f.loops:
                    l[self.col] = (self.tone, self.tone, self.tone, 1.0)

    def box(self, mat, c, size, rot=None):
        r = rot if rot is not None else Matrix.Identity(3)
        M = Matrix.Translation(c) @ r.to_4x4() @ Matrix.Diagonal((*size, 1))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=M)
        self._tag(mat, res["verts"])

    def beam(self, mat, p0, p1, r, n=4, caps=True):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        M = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=n, radius1=r, radius2=r,
                                    depth=d.length, matrix=M)
        self._tag(mat, res["verts"])

    def cyl(self, mat, c, r, h, n=12, axis="Z", r2=None):
        rot = {"Z": Matrix.Identity(4), "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
               "Y": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
        M = Matrix.Translation(c) @ rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=n, radius1=r,
                                    radius2=r if r2 is None else r2, depth=h, matrix=M)
        self._tag(mat, res["verts"])

    def frustum(self, mat, w0, w1, h, base=(0, 0, 0)):
        """Квадратний усічений стовп, низ w0, верх w1."""
        bm = self.bm
        z0, z1 = base[2], base[2] + h
        vs = [bm.verts.new((base[0] + sx * w / 2, base[1] + sy * w / 2, z))
              for z, w in ((z0, w0), (z1, w1)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        for q in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            bm.faces.new([vs[i] for i in q])
        self._tag(mat, vs)

    def uv_box(self, tile_of):
        """Кубічна проєкція в метрах; пропускає грані, що вже мають свої UV."""
        bm = self.bm
        uv = bm.loops.layers.uv.verify() if not bm.loops.layers.uv else bm.loops.layers.uv[0]
        bm.normal_update()
        for f in bm.faces:
            if f in self.skip_uv:
                continue
            m = self.mats[f.material_index]
            t = tile_of(m); tv = m.get("tile_v", t)
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            a, b = [(1, 2), (0, 2), (0, 1)][ax]
            for l in f.loops:
                l[uv].uv = (l.vert.co[a] / t, l.vert.co[b] / (tv if b == 2 else t))


def finish(b, name, wires=(), center=True, extra_tile=None, jpeg=True):
    bm = b.bm
    tile_of = lambda m: m.get("tile", 1.0)
    b.uv_box(tile_of)
    for f in bm.faces:                     # грані без тону (ручні) — білі, інакше вершинний колір їх вимкне
        for l in f.loops:
            if l[b.col][3] == 0.0:
                l[b.col] = (1.0, 1.0, 1.0, 1.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.scale(bm, vec=(S, S, S), verts=bm.verts[:])
    xs = [v.co.x for v in bm.verts]; ys = [v.co.y for v in bm.verts]; zs = [v.co.z for v in bm.verts]
    dx = -(min(xs) + max(xs)) / 2 if center else 0.0
    dy = -(min(ys) + max(ys)) / 2 if center else 0.0
    dz = -min(zs)
    bmesh.ops.translate(bm, vec=(dx, dy, dz), verts=bm.verts[:])
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    for m in b.mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    objs = [ob]
    for wn, p in wires:
        e = bpy.data.objects.new(wn, None)
        e.empty_display_type = "PLAIN_AXES"
        e.location = (p[0] * S + dx, p[1] * S + dy, p[2] * S + dz)
        bpy.context.scene.collection.objects.link(e)
        objs.append(e)
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_image_format="JPEG" if jpeg else "AUTO", export_jpeg_quality=80, export_vertex_color="ACTIVE", export_cameras=False, export_lights=False,
                              export_yup=True)
    if any(m.get("alpha_mask") for m in b.mats):
        patch_alpha_mask(path)
    print("BUILT", json.dumps(report(path, tris)))
    # чистимо сцену для наступного активу
    for o in objs:
        bpy.data.objects.remove(o)
    bpy.data.meshes.remove(me)
    bm.free()


def patch_alpha_mask(path):
    """Експортер ставить BLEND; для листя/штахету потрібен MASK (без сортування прозорих)."""
    d = open(path, "rb").read()
    clen, _ = struct.unpack_from("<II", d, 12)
    g = json.loads(d[20:20 + clen])
    for m in g["materials"]:
        if m.get("alphaMode") == "BLEND":
            m["alphaMode"] = "MASK"; m["alphaCutoff"] = 0.5
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    rest = d[20 + clen:]
    out = d[:12] + struct.pack("<II", len(js), 0x4E4F534A) + js + rest
    out = out[:8] + struct.pack("<I", len(out)) + out[12:]
    open(path, "wb").write(out)


def report(path, tris):
    d = open(path, "rb").read(); off = 12
    while off < len(d):
        clen, ctype = struct.unpack_from("<II", d, off)
        if ctype == 0x4E4F534A:
            g = json.loads(d[off + 8:off + 8 + clen]); break
        off += 8 + clen
    prims = [p for m in g["meshes"] for p in m["primitives"]]
    lo = [min(g["accessors"][p["attributes"]["POSITION"]]["min"][i] for p in prims) for i in range(3)]
    hi = [max(g["accessors"][p["attributes"]["POSITION"]]["max"][i] for p in prims) for i in range(3)]
    t = sum(g["accessors"][p["indices"]]["count"] // 3 for p in prims)
    return {"file": os.path.basename(path), "kb": len(d) // 1024, "prims": len(prims), "tris": t,
            "min": [round(x, 4) for x in lo], "max": [round(x, 4) for x in hi],
            "empties": [n["name"] for n in g["nodes"] if n["name"].startswith("wire")],
            "alpha": [m.get("alphaMode") for m in g.get("materials", []) if m.get("alphaMode")]}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mat_cache.clear()


def want(name):
    a = args()
    return not a or name in a


# ---------- спільні матеріали: фарбований лист і бетон ----------
def sheet_mat(name, paint, seed, tile=1.15, size=64):
    """Профнастил: вертикальні хвилі й стик листа лише в нормалі й albedo; без хмарних плям."""
    u = (np.arange(size) + 0.5) / size
    wave = np.sin(u * 2 * np.pi * 14)
    h = np.tile(wave * 0.5 + 0.5, (size, 1))
    h[:, :2] = 1.0                                   # край листа
    streak = tile_noise(10, 2, size, seed)           # ледь помітні вертикальні розводи
    shade = 0.9 + 0.1 * h + 0.06 * (streak - 0.5)
    a = np.array(paint)[None, None, :] * shade[..., None]
    a[:, :1] *= 0.6                                  # тінь стику
    return pbr(name, albedo=a, normal=np.concatenate([normal_from_height(h, 3.0), np.ones((size, size, 1))], -1),
               tile=tile, rough=0.6, metal=0.1)


CONCRETE_GREY = (0.64, 0.64, 0.62)


def concrete_mat(name, tile=1.5, tile_v=None, relief=None, seed=61, size=128, top_z=None, shade=0.18,
                 ground=True, k=5.0, seams=False):
    """Блідий бетон одного значення для всіх виробів. relief(size) -> висоти 0..1 (йдуть у нормаль);
    бруд знизу (до 0,3 м від землі), патьоки під верхом (top_z, м) і плями з періодом у плитку."""
    tv = tile_v or tile
    a = acg_albedo("Concrete034", (1, 1, 1), 0.3, 0, seed, 0.0, paint=CONCRETE_GREY, contrast=0.3, size=size)
    a = a * (0.9 + 0.2 * fbm(size, seed + 7, 2, 3))[..., None]           # велика пляма
    z = ((np.arange(size) + 0.5) / size * tv)[:, None]                      # метри над землею (рядок = v)
    if ground:
        a = a * (1 - 0.4 * np.exp(-z / 0.3))[..., None]
    if top_z:
        streak = np.clip(tile_noise(24, 1, size, seed + 3) * 1.6 - 0.45, 0, 1)
        ramp = np.clip((z - (top_z - 0.5)) / 0.5, 0, 1) * (z <= top_z + 0.02)
        a = a * (1 - 0.35 * streak * ramp)[..., None]
    n = load_acg("Concrete034", "NormalGL", size)
    pit = 0.5 * tile_noise(48, 48, size, seed + 5) + 0.5 * tile_noise(16, 16, size, seed + 6)
    h = (relief(size) if relief is not None else np.ones((size, size))) + 0.3 * pit
    if seams:                                                               # стики опалубки через 0,25 м
        h = h - 0.6 * (np.abs(np.sin(np.pi * z / 0.25)) ** 40)
    r = normal_from_height(h, k)
    n = np.concatenate([n[..., :2] - 0.5 + (r[..., :2] - 0.5) + 0.5, r[..., 2:]], -1)
    if relief is not None:
        a = a * (1 - shade + shade * np.clip(relief(size), 0, 1))[..., None]
    return pbr(name, albedo=a, normal=np.concatenate([n, np.ones((size, size, 1))], -1), tile=tile, tile_v=tv,
               rough=0.92)


def box_mask(size, u0, u1, v0, v1, soft=0.012):
    u = (np.arange(size) + 0.5) / size
    f = lambda x, a, b: np.clip((x - a) / soft, 0, 1) * np.clip((b - x) / soft, 0, 1)
    return f(u, u0, u1)[None, :] * f(u, v0, v1)[:, None]
