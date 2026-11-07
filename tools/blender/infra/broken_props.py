"""Зламані версії стовпів і парканів: той самий предмет, розрізаний на справжні шматки.

Запуск (з кореня репозиторію):
    blender -b --factory-startup --python-exit-code 1 -P tools/blender/infra/broken_props.py -- [імена моделей]
Без імен збираються всі. Вихід — assets/props/broken/<модель>_broken.glb (BROKEN_OUT змінює каталог).

Контракт для анімації: діти сцени — вузли piece_00, piece_01, …; початок кожного — у центрі мас шматка; складені на
місці вони дають вихідну модель (ті самі одиниці, осі, масштаб). Тому шматки не будуються наново, а вирізаються
з імпортованого вихідного GLB: матеріали, атлас, UV і колір вершин лишаються тими самими, змінюється лише топологія.
Вузол несе extras «part» (stump/segment/chunk/post/slab/…), щоб анімація знала, що можна лишити на землі.

Площина різу — єдина операція: цілий шматок ділиться надвоє, обидві половини отримують кришку з матеріалом зламу
(свіжий бетон, мідно-бурий волокнистий дротик дерева, голий метал). Злам косий, а не рівний, і від кутів відколюються
дрібні уламки — рівний зріз із верху читається як різ пилкою. Усе детерміноване (зерно з імені моделі).

Ліміт трикутників — max(1.5 x вихідник, FLOOR=700): вихідні стовпи мають по 72-108 трикутників, а кожен різ додає ~15-35,
тож пропорція 1.5 x не вміщує навіть пеньок із трьома сегментами. FLOOR — стеля для таких мікромоделей; на екрані
в сотні разів більший бюджет.
"""
import bpy, bmesh, os, sys, json, struct, math, random, zlib
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.environ.get("BROKEN_SRC", os.path.join(ROOT, "assets", "props"))
OUT = os.environ.get("BROKEN_OUT", os.path.join(SRC, "broken"))
M = 0.125                       # метр у одиницях сцени: один тайл = 8 м
FLOOR = 700                     # див. докстрінг
YARD_KINDS = ("picket", "sheet", "chainlink", "brickbars", "slat")
ATLAS_N, ATLAS_HB = 5, 192 + 24     # блоків в атласі парканів дворів і висота блоку з полями (yard_fences.py)


def args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


# ---------- завантаження й підготовка ----------
def load(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()      # вирізані шматки мають нову форму: старі нормалі брехали б
    except RuntimeError:
        pass
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    return bm, list(ob.data.materials), ob


def tris(bm):
    return len(bm.calc_loop_triangles())


def key(v):
    return (round(v.co.x * 1e5), round(v.co.y * 1e5), round(v.co.z * 1e5))


def components(bm):
    """Окремі предмети меша (стовп, дошка, плита): GLB розщеплює вершини по нормалях, тож зв'язок шукається за позицією."""
    par = {}

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    for f in bm.faces:
        ks = [key(v) for v in f.verts]
        for k in ks:
            par.setdefault(k, k)
        for k in ks[1:]:
            par[find(k)] = find(ks[0])
    groups = {}
    for i, f in enumerate(bm.faces):
        groups.setdefault(find(key(f.verts[0])), set()).add(i)
    out = []
    for keep in groups.values():
        c = bm.copy()
        bmesh.ops.delete(c, geom=[f for i, f in enumerate(c.faces) if i not in keep], context="FACES")
        bmesh.ops.delete(c, geom=[v for v in c.verts if not v.link_faces], context="VERTS")
        out.append(c)
    return out


def is_closed(bm):
    return bool(bm.edges) and all(len(e.link_faces) == 2 for e in bm.edges)


def tidy(bm):
    """Зварити дублі вершин і склеїти пари трикутників назад у чотирикутники: різ по чотирикутнику дає вдвічі менше граней."""
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.join_triangles(bm, faces=bm.faces[:], cmp_seam=False, cmp_sharp=False, cmp_uvs=True, cmp_vcols=False,
                             cmp_materials=True, angle_face_threshold=0.01, angle_shape_threshold=math.pi)
    return bm


def bbox(bm):
    vs = [v.co for v in bm.verts]
    return Vector(min(v[i] for v in vs) for i in range(3)), Vector(max(v[i] for v in vs) for i in range(3))


# ---------- матеріали зламу ----------
def _img(name, arr):
    n = arr.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False)
    rgba = np.concatenate([np.clip(arr, 0, 1), np.ones((n, n, 1))], -1).astype(np.float32)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def _material(name, arr, rough):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _img(name + "_a", arr)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    return mat


def _blur(a, k=2):
    for _ in range(k):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return a


def fracture_material(kind):
    """Свіжий злам: бетон — світліший за вивітрену поверхню (~1.2 x), зі щебенем; дерево — темніша за вал сіро-бура
    розщеплена деревина (не біла); метал — яскрава свіжа оцинковка; арматура — темна іржава сталь."""
    rng = np.random.default_rng({"concrete": 11, "wood": 12, "metal": 13, "rebar": 14}[kind])
    n = 64
    if kind == "concrete":
        g = _blur(rng.random((n, n)), 1)
        stones = (_blur(rng.random((n, n)), 2) > 0.56).astype(float)
        a = np.array([0.64, 0.63, 0.60]) * (0.86 + 0.28 * g)[..., None]
        a = np.where(stones[..., None] > 0, np.array([0.48, 0.47, 0.45]) * (0.85 + 0.3 * g)[..., None], a)
        return _material("fracture_concrete", a, 0.95)
    if kind == "wood":
        fibre = np.repeat(_blur(rng.random((1, n)), 1), n, 0) * 0.6 + _blur(rng.random((n, n)), 1) * 0.4
        a = np.array([0.27, 0.22, 0.17]) * (0.75 + 0.45 * fibre)[..., None]
        return _material("fracture_wood", a, 0.95)
    g = _blur(rng.random((n, n)), 1)
    if kind == "metal":
        a = np.array([0.62, 0.64, 0.66]) * (0.85 + 0.3 * g)[..., None]
        return _material("fracture_metal", a, 0.45)
    rust = (_blur(rng.random((n, n)), 3) > 0.5).astype(float)
    a = np.array([0.22, 0.16, 0.12]) * (0.8 + 0.4 * g)[..., None]
    a = np.where(rust[..., None] > 0, np.array([0.38, 0.20, 0.10]) * (0.8 + 0.4 * g)[..., None], a)
    return _material("fracture_rebar", a, 0.7)


# ---------- різ ----------
def style_faces(bm, faces, idx, no, tile_m=0.5):
    """Матеріал зламу, UV в метрах площиною різу (щоб крупність щебеню не залежала від розміру шматка) і білий колір вершин."""
    uvl, col = bm.loops.layers.uv.active, bm.loops.layers.color.active
    t1 = no.cross(Vector((0, 0, 1)) if abs(no.z) < 0.9 else Vector((1, 0, 0))).normalized()
    t2 = no.cross(t1)
    for f in faces:
        f.material_index = idx
        for l in f.loops:
            p = l.vert.co / M
            l[uvl].uv = (p.dot(t1) / tile_m, p.dot(t2) / tile_m)
            l[col] = (1.0, 1.0, 1.0, 1.0)


def cut(bm, co, no, cap_idx=None):
    """Розріз площиною: (з боку мінус нормалі, з боку плюс нормалі); порожній бік — None. Кришки — матеріалом cap_idx;
    без нього (картка без об'єму) краї лишаються відкритими."""
    no = Vector(no).normalized()
    co = Vector(co)
    res = []
    for side in (-1, 1):
        b = bm.copy()
        r = bmesh.ops.bisect_plane(b, geom=b.verts[:] + b.edges[:] + b.faces[:], dist=1e-7, plane_co=co, plane_no=no,
                                   clear_outer=(side < 0), clear_inner=(side > 0))
        if not b.faces:
            b.free()
            res.append(None)
            continue
        if cap_idx is not None:
            edges = [g for g in r["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
            if edges:
                fill = bmesh.ops.triangle_fill(b, use_beauty=True, use_dissolve=False, edges=edges, normal=no)
                caps = [g for g in fill["geom"] if isinstance(g, bmesh.types.BMFace)]
                style_faces(b, caps, cap_idx, no)
                bmesh.ops.recalc_face_normals(b, faces=b.faces[:])
        res.append(b)
    if res[0] is None or res[1] is None:         # площина минула шматок
        for b in res:
            if b:
                b.free()
        return None
    return res[0], res[1]


def cap_faces(bm, cap_idx):
    return [f for f in bm.faces if f.material_index == cap_idx]


def rebar(bm, face, rng, mat_idx, n=2, length_m=0.10, r_m=0.014):
    """Кілька стирчачих прутів арматури з грані зламу: торчать у сусідній шматок, тож у складеному вигляді не видно."""
    c = face.calc_center_median()
    nrm = face.normal.normalized()
    verts = [l.vert.co.copy() for l in face.loops]
    rng.shuffle(verts)
    mats = Matrix.Identity(4)
    for v in verts[:n]:
        p = c + (v - c) * 0.12
        mx = Matrix.Translation(p + nrm * (length_m * M / 2 - 0.01 * M)) @ nrm.to_track_quat("Z", "Y").to_matrix().to_4x4()
        r = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=3, radius1=r_m * M, radius2=r_m * 0.6 * M,
                                  depth=length_m * M, matrix=mx)
        fs = {f for v_ in r["verts"] for f in v_.link_faces}
        style_faces(bm, fs, mat_idx, nrm)


def _bar(bm, p0, p1, r, mat_idx, nrm):
    d = p1 - p0
    mx = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=3, radius1=r, radius2=r, depth=d.length, matrix=mx)
    style_faces(bm, {f for v in res["verts"] for f in v.link_faces}, mat_idx, nrm)


def rebar_cage(bm, face, rng, mat_idx, up):
    """Оголена арматура з грані зламу: 3-4 прути r~3 см, 0.4-0.7 м, кожен з одним зігином 15-40° до осі. Прути йдуть
    уздовж осі в сусідній шматок (зігин — до осі, довжина після нього коротка), тож у складеному вигляді лишаються
    всередині нього."""
    c = face.calc_center_median()
    nrm = face.normal.normalized()
    n = rng.choice((3, 4))
    a0 = rng.uniform(0, 2 * math.pi)
    for i in range(n):
        a = a0 + 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        off = Vector((math.cos(a), math.sin(a), 0)) * (0.035 * M)
        p0 = c + off
        p0.z = c.z - (off.x * nrm.x + off.y * nrm.y) / nrm.z          # точка лежить у площині зламу
        L1, L2 = rng.uniform(0.28, 0.45) * M, rng.uniform(0.12, 0.18) * M
        k = math.radians(rng.uniform(15, 40))
        d2 = (up * math.cos(k) + (-off).normalized() * math.sin(k)).normalized()
        p1 = p0 + up * L1
        _bar(bm, p0 - up * 0.01 * M, p1, 0.03 * M, mat_idx, nrm)
        _bar(bm, p1, p1 + d2 * L2, 0.03 * M, mat_idx, nrm)


def apply(ps, co, no, cap_idx=None, only=None):
    """Площина різу для всіх шматків зі списку, які вона перетинає (і чий тег у only, якщо задано)."""
    out = []
    for p in ps:
        r = cut(p[0], co, no, cap_idx) if (only is None or p[1] in only) else None
        if r is None:
            out.append(p)
        else:
            p[0].free()
            out += [[r[0], p[1]], [r[1], p[1]]]
    return out


def snap(p, rng, cap_idx=None, z_m=None):
    """Стовп ламається біля землі косим різом: (пеньок, верхівка) або None. Площина йде через вісь самого стовпа."""
    lo, hi = bbox(p[0])
    z = lo.z + (z_m if z_m is not None else rng.uniform(0.2, 0.4)) * M
    co = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, z)
    return cut(p[0], co, (rng.choice((-1, 1)) * rng.uniform(0.3, 0.5), rng.uniform(-0.3, 0.3), 1), cap_idx)


def snap_some(ps, tags, idxs, rng, cap_idx=None):
    """Ламає стовпи з тегом post під номерами idxs (за порядком зліва направо); пеньок отримує тег stump."""
    posts = sorted([p for p in ps if p[1] in tags], key=lambda p: com(p[0]).x)
    for i in idxs:
        if i >= len(posts):
            continue
        p = posts[i]
        r = snap(p, rng, cap_idx)
        if r is None:
            continue
        p[0].free()
        ps.remove(p)
        ps += [[r[0], "stump"], [r[1], p[1]]]
    return ps


def com(bm):
    """Центр мас: замкнене тіло — за об'ємом, відкрита картка — за площею."""
    lt = bm.calc_loop_triangles()
    if is_closed(bm):
        vol, cen = 0.0, Vector()
        for t in lt:
            a, b, c = (l.vert.co for l in t)
            v = a.dot(b.cross(c)) / 6.0
            vol += v
            cen += v * (a + b + c) / 4.0
        if abs(vol) > 1e-14:
            return cen / vol
    area, cen = 0.0, Vector()
    for t in lt:
        a, b, c = (l.vert.co for l in t)
        s = (b - a).cross(c - a).length / 2.0
        area += s
        cen += s * (a + b + c) / 3.0
    return cen / area


# ---------- експорт ----------
def rewrite_json(path, fn):
    d = open(path, "rb").read()
    clen, _ = struct.unpack_from("<II", d, 12)
    g = json.loads(d[20:20 + clen])
    fn(g)
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out = d[:12] + struct.pack("<II", len(js), 0x4E4F534A) + js + d[20 + clen:]
    open(path, "wb").write(struct.pack("<I", 0x46546C67) + struct.pack("<II", 2, len(out)) + out[12:])


def src_materials(name):
    d = open(os.path.join(SRC, name + ".glb"), "rb").read()
    clen, _ = struct.unpack_from("<II", d, 12)
    return {m["name"]: m for m in json.loads(d[20:20 + clen]).get("materials", [])}


def export(out_name, src_name, pieces, mats):
    """pieces — [(bmesh, part)] у порядку іменування; кожен шматок зсувається так, щоб початок був у центрі мас."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    objs = []
    total = 0
    for i, (bm, part) in enumerate(pieces):
        b0, b1 = bbox(bm)
        lo = Vector(min(a, b) for a, b in zip(lo, b0))
        hi = Vector(max(a, b) for a, b in zip(hi, b1))
        c = com(bm)
        bmesh.ops.translate(bm, vec=-c, verts=bm.verts[:])
        total += tris(bm)
        me = bpy.data.meshes.new(f"piece_{i:02d}")
        bm.to_mesh(me)
        bm.free()
        for m in mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(f"piece_{i:02d}", me)
        ob.location = c
        ob["part"] = part
        bpy.context.scene.collection.objects.link(ob)
        objs.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, out_name + "_broken.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_image_format="AUTO", export_vertex_color="ACTIVE", export_cameras=False,
                              export_lights=False, export_yup=True, export_extras=True)
    sm = src_materials(src_name)

    def fix(g):
        # експортер губить режим альфи імпортованих матеріалів (штахет, атлас парканів): повертаємо як у вихідника
        for m in g.get("materials", []):
            m["name"] = m["name"].rsplit(".", 1)[0] if m["name"][-4:-3] == "." and m["name"][-3:].isdigit() else m["name"]   # копія матеріалу з суфіксом .00N
            for k in ("alphaMode", "alphaCutoff", "doubleSided"):
                m.pop(k, None)
            s = sm.get(m["name"])
            if s:
                for k in ("alphaMode", "alphaCutoff", "doubleSided"):
                    if k in s:
                        m[k] = s[k]
        for me in g["meshes"]:
            for p in me["primitives"]:
                if "COLOR_1" in p["attributes"] and "COLOR_0" not in p["attributes"]:
                    p["attributes"]["COLOR_0"] = p["attributes"].pop("COLOR_1")
    rewrite_json(path, fix)
    return path, total, (lo, hi)


def limit(src_tris):
    return max(int(src_tris * 1.5), FLOOR)


def report(label, path, total, bb, src_bb, src_tris, n):
    d = (max(abs(a - b) for a, b in zip(bb[0], src_bb[0])), max(abs(a - b) for a, b in zip(bb[1], src_bb[1])))
    print("BUILT", json.dumps({"file": os.path.basename(path), "pieces": n, "tris": total, "src_tris": src_tris,
                               "ratio": round(total / src_tris, 2), "limit": limit(src_tris),
                               "aabb_err_m": round(max(d) / M, 4)}))
    assert total <= limit(src_tris), f"{label}: {total} трикутників понад ліміт {limit(src_tris)}"
    assert max(d) / M < 0.02, f"{label}: габарит шматків розходиться з вихідником на {max(d) / M:.3f} м"


def rng_for(name):
    return random.Random(zlib.crc32(name.encode()))


def sort_key_x(bm):
    return com(bm).x


# ---------- стовпи ----------
# Межі зламів — частки висоти; сегменти навмисно різної довжини (>= 1.5 x між найдовшим і найкоротшим).
BREAKS = {"infra_pole_concrete_10kv": (0.095, 0.30, 0.74), "infra_pole_concrete_04kv": (0.10, 0.68),
          "infra_pole_wood": (0.22, 0.68)}


def tilt_normal(rng, lo_deg, hi_deg):
    t = math.radians(rng.uniform(lo_deg, hi_deg))
    phi = rng.uniform(0, 2 * math.pi)
    return Vector((math.sin(t) * math.cos(phi), math.sin(t) * math.sin(phi), math.cos(t)))


def pole(name, concrete):
    """Пеньок над землею, сегменти валу з косими зламами. Бетон: від кутів зламу відколюються крупні уламки, з грані стирчить
    арматура. Дерево: злам східцями (проміжна колода між двома косими різами) і довгі скалки."""
    rng = rng_for(name)
    bm, mats, _ = load(name)
    src_tris = tris(bm)
    src_bb = bbox(bm)
    comps = components(bm)
    shaft = max(comps, key=lambda c: bbox(c)[1].z - bbox(c)[0].z)
    sb = bbox(shaft)
    ax = Vector(((sb[0].x + sb[1].x) / 2, (sb[0].y + sb[1].y) / 2, 0))
    for c in comps:
        c.free()
    bm = tidy(bm)
    H = (sb[1].z - sb[0].z) / M
    fm = len(mats)
    mats.append(fracture_material("concrete" if concrete else "wood"))
    rb = len(mats)
    mats.append(fracture_material("rebar"))
    pieces, chunks, rest = [], [], bm
    for f in BREAKS[name]:
        z = H * f
        lo, hi = cut(rest, ax + Vector((0, 0, z * M)), tilt_normal(rng, 9, 24), fm)
        rest.free()
        pieces.append([lo, "stump" if not pieces else "segment"])
        if not concrete:
            r = cut(hi, ax + Vector((0, 0, (z + rng.uniform(0.2, 0.4)) * M)), tilt_normal(rng, 6, 14), fm)
            if r:
                hi.free()
                chunks.append([r[0], "chunk"])
                hi = r[1]
        rest = hi
    pieces.append([rest, "segment"])
    ends = [(i, 1) for i in range(len(pieces) - 1)] + [(i + 1, -1) for i in range(len(pieces) - 1)]
    for i, e in ends:
        b = pieces[i][0]
        caps = [f for f in cap_faces(b, fm) if f.normal.z * e > 0.5]
        if not caps:
            continue
        f = max(caps, key=lambda f: f.calc_area())
        v = rng.choice(f.verts).co.copy()
        a = Vector((0, 0, e))
        l = Vector((v.x - ax.x, v.y - ax.y, 0)).normalized()
        if concrete:
            nrm = (l * 0.55 + a * 0.83).normalized()
            co = v - nrm * (rng.uniform(0.22, 0.34) * M)
        else:
            # скалка: площина майже вздовж валу, що виходить на бік за 0.4-0.8 м від зламу; товщина ~4 см
            nrm = (l + a * (0.04 / rng.uniform(0.4, 0.8))).normalized()
            co = ax + l * (0.65 * 0.119 * M) + Vector((0, 0, f.calc_center_median().z))
        r = cut(b, co, nrm, fm)
        if r is None:
            continue
        b.free()
        pieces[i][0] = r[0]
        chunks.append([r[1], "chunk"])
    if concrete:
        for p in pieces[:-1]:
            ups = [f for f in cap_faces(p[0], fm) if f.normal.z > 0.5]
            if ups:
                rebar_cage(p[0], max(ups, key=lambda f: f.calc_area()), rng, rb, Vector((0, 0, 1)))
    pieces += chunks
    path, total, bb = export(name, name, [(b, part) for b, part in pieces], mats)
    report(name, path, total, bb, src_bb, src_tris, len(pieces))


# ---------- паркани ----------
def fence_parts(name):
    bm, mats, _ = load(name)
    src_tris = tris(bm)
    src_bb = bbox(bm)
    comps = [tidy(c) for c in components(bm)]
    return comps, mats, src_tris, src_bb, [mats[next(iter(c.faces)).material_index].name for c in comps]


def order(pieces):
    pieces.sort(key=lambda p: (com(p[0]).x, com(p[0]).z))
    return pieces


def tilted(rng, t):
    return rng.uniform(-t, t)


def slice_x(pieces, xs, rng, tilt, cap_idx=None, only=None):
    """Вертикальні (косі) розрізи по x (м) усіх шматків, які площина перетинає."""
    for x in xs:
        new = []
        for p in pieces:
            r = cut(p[0], (x * M, 0, 0.7 * M), (1, 0, tilted(rng, tilt)), cap_idx) if (only is None or p[1] in only) else None
            if r is None:
                new.append(p)
            else:
                p[0].free()
                new += [[r[0], p[1]], [r[1], p[1]]]
        pieces = new
    return pieces


def picket(name):
    """Штахет: картки секцій рвуться на косі смуги, два стовпи ламаються біля землі."""
    rng = rng_for(name)
    comps, mats, st, sbb, mn = fence_parts(name)
    fm = len(mats)
    mats.append(fracture_material("wood"))
    pieces = []
    for c, m in zip(comps, mn):
        if m.endswith("post"):
            pieces.append([c, "post"])
        else:
            lo, hi = bbox(c)
            xs = [lo.x / M + (hi.x - lo.x) / M * (k / 5 + tilted(rng, 0.05)) for k in range(1, 5)]
            pieces += slice_x([[c, "board"]], xs, rng, 0.25)
    pieces = snap_some(pieces, {"post"}, (1, 3), rng, fm)
    pieces = order(pieces)
    path, total, bb = export(name, name, pieces, mats)
    report(name, path, total, bb, sbb, st, len(pieces))


def sheet(name):
    """Профнастил: кожен лист рветься двома нерівними розривами (косий упоперек і косий по висоті в більшій частині),
    два стовпи-труби ламаються біля землі. Згин листа в спокої не передати: складена модель мусить збігатися з вихідною,
    тож згин — це розрив по лінії згину на окремі шматки, а гнути їх буде анімація."""
    rng = rng_for(name)
    comps, mats, st, sbb, mn = fence_parts(name)
    fm = len(mats)
    mats.append(fracture_material("metal"))
    pieces = []
    for c, m in zip(comps, mn):
        if m.endswith("post"):
            pieces.append([c, "post"])
            continue
        lo, hi = bbox(c)
        x = lo.x + rng.uniform(0.25, 0.7) * (hi.x - lo.x)
        r = cut(c, (x, 0, 0.5 * (lo.z + hi.z)), (1, 0, tilted(rng, 0.7)), fm)
        c.free()
        halves = [[r[0], "sheet"], [r[1], "sheet"]]
        big = max(halves, key=lambda p: bbox(p[0])[1].x - bbox(p[0])[0].x)
        b0, b1 = bbox(big[0])
        z = b0.z + rng.uniform(0.35, 0.65) * (b1.z - b0.z)
        r = cut(big[0], ((b0.x + b1.x) / 2, 0, z), (tilted(rng, 0.5), 0, 1), fm)
        halves.remove(big)
        big[0].free()
        pieces += halves + [[r[0], "sheet"], [r[1], "sheet"]]
    pieces = snap_some(pieces, {"post"}, (1, 2), rng, fm)
    pieces = order(pieces)
    path, total, bb = export(name, name, pieces, mats)
    report(name, path, total, bb, sbb, st, len(pieces))


def euro(name):
    """Єврозабір: стовпи цілі, плити тріскаються по діагоналі на 2-3 частини, валики ґрунту — окремі шматки (лишаються)."""
    rng = rng_for(name)
    comps, mats, st, sbb, mn = fence_parts(name)
    fm = len(mats)
    mats.append(fracture_material("concrete"))
    rb = len(mats)
    mats.append(fracture_material("rebar"))
    pieces = []
    slabs = []
    for c, m in zip(comps, mn):
        if m.endswith("post"):
            pieces.append([c, "post"])
        elif len(c.faces) <= 2:
            pieces.append([c, "berm"])
        else:
            slabs.append(c)
    three = set(rng.sample(range(len(slabs)), max(1, len(slabs) // 8)))
    for i, c in enumerate(slabs):
        lo, hi = bbox(c)
        cx, cz = (lo.x + hi.x) / 2, (lo.z + hi.z) / 2
        L, h = hi.x - lo.x, hi.z - lo.z
        sgn = rng.choice((-1, 1))
        shifts = (rng.uniform(-0.3, 0.3) * L,) if i not in three else (-0.27 * L, 0.27 * L)
        parts = [[c, "slab"]]
        for s in shifts:
            dx = sgn * rng.uniform(0.2, 0.7) * h
            nrm = (h, 0, -dx)
            pt = Vector((cx + s, 0, cz))
            nxt = []
            for p in parts:
                pb = bbox(p[0])
                if not pb[0].x < pt.x < pb[1].x:
                    nxt.append(p)
                    continue
                r = cut(p[0], pt, nrm, fm)
                if r is None:
                    nxt.append(p)
                    continue
                p[0].free()
                nxt += [[r[0], "slab"], [r[1], "slab"]]
            parts = nxt
        pieces += parts
    pieces = snap_some(pieces, {"post"}, (1, 3), rng, fm)
    # арматура на гранях зламу, скільки вміщує ліміт трикутників
    lim = limit(st)
    for p in pieces[::2]:
        f = max(cap_faces(p[0], fm), key=lambda f: f.calc_area(), default=None)
        if f and sum(tris(q[0]) for q in pieces) + 16 <= lim:
            rebar(p[0], f, rng, rb)
    pieces = order(pieces)
    path, total, bb = export(name, name, pieces, mats)
    report(name, path, total, bb, sbb, st, len(pieces))


# ---------- паркани дворів: плоскі картки з атласом ----------
def crop_atlas(mat, k):
    """Атлас — п'ять блоків одним зображенням: шматку одного виду потрібен лише його блок, інакше кожен із п'яти файлів
    ніс би весь атлас."""
    nt = mat.node_tree
    for node in nt.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            img = node.image
            w, h = img.size
            px = np.empty(w * h * 4, np.float32)
            img.pixels.foreach_get(px)
            px = px.reshape(h, w, 4)
            blk = px[(ATLAS_N - 1 - k) * ATLAS_HB:(ATLAS_N - k) * ATLAS_HB]
            new = bpy.data.images.new(img.name + f"_{YARD_KINDS[k]}", w, ATLAS_HB, alpha=True)
            new.pixels.foreach_set(blk.ravel())
            new.alpha_mode = img.alpha_mode
            new.pack()
            node.image = new


# Стовпи-колони в текстурі картки: (центр першого, ширина), м; крок 2.5 м (yard_fences.py).
YARD_POSTS = {"picket": (0.05, 0.10), "chainlink": (0.04, 0.08), "brickbars": (0.19, 0.38), "slat": (0.05, 0.10)}
YARD_PITCH = 2.5


def card_pieces(card, kind, rng):
    """Шматки картки виду. Стовпи (колони текстури) виділяються першими цілими — жоден розріз не ділить їх уздовж, лишаються
    не ближче 0.15 м до стовпа; кожен стовп ламається раз біля землі косим різом. Цоколь цегляного паркану лишається
    пеньками на місці (плоска картка на землі читалась би смугою фарби)."""
    ps = [[card, kind]]
    posts = []
    if kind in YARD_POSTS:
        x0, w = YARD_POSTS[kind]
        centres = [-4 + x0 + YARD_PITCH * k for k in range(4)]
        for cx in centres:
            for ex in (cx - w / 2, cx + w / 2):
                if -3.999 < ex < 3.999:
                    ps = apply(ps, (ex * M, 0, 0.7 * M), (1, 0, 0))
        for p in ps:
            x = com(p[0]).x / M
            if any(abs(x - cx) < w / 2 for cx in centres):
                p[1] = "post"
        posts = [p for p in ps if p[1] == "post"]

    def panels():
        return [p for p in ps if p[1] != "post" and p[1] != "stump"]

    def wide(p):
        b0, b1 = bbox(p[0])
        return (b1.x - b0.x) / M

    def split_vertical(p, tilt, lo_m=0.3):
        b0, b1 = bbox(p[0])
        if wide(p) < 2 * lo_m + 0.4:
            return [p]
        x = rng.uniform(b0.x / M + lo_m, b1.x / M - lo_m)
        return apply([p], (x * M, 0, 0.7 * M), (1, 0, tilted(rng, tilt)))
    if kind == "picket":
        for p in panels():
            ps.remove(p)
            ps += split_vertical(p, 0.6)
    elif kind == "chainlink":
        for p in panels():
            ps.remove(p)
            ps += split_vertical(p, 0.7, 0.5)
    elif kind == "slat":
        for p in panels():
            ps.remove(p)
            b0, b1 = bbox(p[0])
            cx = (b0.x + b1.x) / 2
            t = rng.choice((-1, 1)) * rng.uniform(0.4, 0.7)       # косий розрив дощок на випадковій висоті, не ряд клавіш
            parts = apply([p], (cx, 0, rng.uniform(0.3, 1.2) * M), (t, 0, 1))
            for q in parts:
                if wide(q) > 1.2 and rng.random() < 0.5:
                    ps_split = split_vertical(q, 0.5, 0.5)
                    ps += ps_split
                else:
                    ps.append(q)
    elif kind == "brickbars":
        for p in panels():
            ps.remove(p)
            b0, b1 = bbox(p[0])
            ps += apply([p], ((b0.x + b1.x) / 2, 0, 0.53 * M), (rng.choice((-1, 1)) * 0.15, 0, 1))
        for p in ps:
            p[1] = "plinth" if p[1] != "post" and com(p[0]).z < 0.53 * M else p[1]
        plinth = [p for p in ps if p[1] == "plinth"]
        for j, p in enumerate(plinth):
            ps.remove(p)
            if j % 2 == 0:                                   # ступінчастий різ: нижній ряд і верхній — різні x
                b0, b1 = bbox(p[0])
                for q in apply([p], ((b0.x + b1.x) / 2, 0, 0.27 * M), (rng.choice((-1, 1)) * 0.15, 0, 1)):
                    q[1] = "plinth"
                    ps += [q]
            else:
                ps.append(p)
        for p in [q for q in ps if q[1] == kind]:
            ps.remove(p)
            ps += split_vertical(p, 0.4, 0.4)
    else:                                                    # профнастил: 3-4 розриви через 1.2-2.4 м, більші шматки рвуться ще й упоперек
        x = -4.0
        while True:
            x += rng.uniform(1.2, 2.4)
            if x > 3.0:
                break
            ps = apply(ps, (x * M, 0, 0.7 * M), (1, 0, tilted(rng, 0.7)))
        for p in sorted(ps, key=wide, reverse=True)[:2]:
            ps.remove(p)
            ps += apply([p], (0, 0, rng.uniform(0.6, 1.2) * M), (tilted(rng, 0.5), 0, 1))
    if posts:
        ps = snap_some(ps, {"post"}, range(4), rng)
    return ps


def yard(name):
    bm, mats, ob = load(name)
    src_tris = tris(bm)
    src_bb = bbox(bm)
    # картки видів стикаються кутами на землі, тож за позицією їх не розрізнити: вид кожної видно з її блоку атласу
    uvl = bm.loops.layers.uv.active
    bykind = {}
    for f in bm.faces:
        k = ATLAS_N - 1 - int(min(l[uvl].uv.y for l in f.loops) * ATLAS_N + 1e-6)
        bykind.setdefault(YARD_KINDS[k], (k, set()))[1].add(f.index)
    for kind, (k, idx) in list(bykind.items()):
        c = bm.copy()
        bmesh.ops.delete(c, geom=[f for f in c.faces if f.index not in idx], context="FACES")
        bmesh.ops.delete(c, geom=[v for v in c.verts if not v.link_faces], context="VERTS")
        bykind[kind] = (k, tidy(c))
    assert set(bykind) == set(YARD_KINDS), sorted(bykind)
    src = mats[0]
    for kind in YARD_KINDS:
        rng = rng_for(name + kind)
        k, c = bykind[kind]
        c = c.copy()
        uvl = c.loops.layers.uv.active
        for f in c.faces:                                    # v блоку k атласу -> v обрізаного зображення
            for l in f.loops:
                l[uvl].uv.y = l[uvl].uv.y * ATLAS_N - (ATLAS_N - 1 - k)
        mat = src.copy()
        mat.name = src.name
        crop_atlas(mat, k)
        ps = card_pieces(c, kind, rng)
        ps = order(ps)
        path, total, bb = export(f"{name}_{kind}", name, ps, [mat])
        report(f"{name}_{kind}", path, total, bb, bbox(bykind[kind][1]), 2, len(ps))


BUILD = {
    "infra_pole_concrete_10kv": lambda n: pole(n, True),
    "infra_pole_concrete_04kv": lambda n: pole(n, True),
    "infra_pole_wood": lambda n: pole(n, False),
    "infra_fence_picket": picket,
    "infra_fence_sheet_green": sheet,
    "infra_fence_sheet_brown": sheet,
    "infra_fence_euro": euro,
    "infra_fence_yard": yard,
}

for n, f in BUILD.items():
    if not args() or n in args():
        f(n)
