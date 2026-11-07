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

Ліміт трикутників — max(1.5 x вихідник, FLOOR): вихідні стовпи мають по 72-108 трикутників, а кожен різ додає ~15-35,
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
FLOOR = 520                     # див. докстрінг
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
    """Свіжий злам: бетон — світліший за вивітрену поверхню, зі щебенем; дерево — середньо-бура розщеплена деревина (не біла);
    метал — темна сталь із рудими плямами."""
    rng = np.random.default_rng({"concrete": 11, "wood": 12, "metal": 13}[kind])
    n = 64
    if kind == "concrete":
        g = _blur(rng.random((n, n)), 1)
        stones = (_blur(rng.random((n, n)), 2) > 0.56).astype(float)
        a = np.array([0.50, 0.49, 0.46]) * (0.82 + 0.3 * g)[..., None]
        a = np.where(stones[..., None] > 0, np.array([0.36, 0.35, 0.33]) * (0.8 + 0.4 * g)[..., None], a)
        return _material("fracture_concrete", a, 0.95)
    if kind == "wood":
        fibre = np.repeat(_blur(rng.random((1, n)), 1), n, 0) * 0.6 + _blur(rng.random((n, n)), 1) * 0.4
        a = np.array([0.30, 0.21, 0.14]) * (0.72 + 0.5 * fibre)[..., None]
        return _material("fracture_wood", a, 0.95)
    g = _blur(rng.random((n, n)), 1)
    rust = (_blur(rng.random((n, n)), 3) > 0.52).astype(float)
    a = np.array([0.26, 0.27, 0.28]) * (0.8 + 0.4 * g)[..., None]
    a = np.where(rust[..., None] > 0, np.array([0.40, 0.22, 0.12]) * (0.8 + 0.4 * g)[..., None], a)
    return _material("fracture_metal", a, 0.7)


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
def pole(name, concrete):
    """Пеньок над землею, сегменти валу з косими зламами, відколи від кутів зламу (бетон) чи довгі скалки (дерево)."""
    rng = rng_for(name)
    bm, mats, _ = load(name)
    src_tris = tris(bm)
    src_bb = bbox(bm)
    # вал — найвища деталь; його вісь — вісь зламів
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
    mats.append(fracture_material("metal"))
    # межі зламів, м від землі: пеньок ~0.8-1 м, далі рівні сегменти; кількість залежить від висоти
    frac = (0.09, 0.40, 0.70) if H > 9 or not concrete else (0.10, 0.50)
    if not concrete:
        frac = (0.11, 0.42, 0.72)
    zs = [H * f * (1 + rng.uniform(-0.06, 0.06)) for f in frac]
    if not concrete:
        zs[0] = max(zs[0], 1.75)         # дерев'яний стовп ламається над бетонною приставкою (0-1.6 м), а не крізь неї
    pieces, rest = [], bm
    for z in zs:
        t = math.radians(rng.uniform(9, 24))
        phi = rng.uniform(0, 2 * math.pi)
        n = Vector((math.sin(t) * math.cos(phi), math.sin(t) * math.sin(phi), math.cos(t)))
        lo, hi = cut(rest, ax + Vector((0, 0, z * M)), n, fm)
        rest.free()
        pieces.append([lo, "stump" if not pieces else "segment"])
        rest = hi
    pieces.append([rest, "segment"])
    ends = [(i, 1) for i in range(len(pieces) - 1)] + [(i + 1, -1) for i in range(len(pieces) - 1)]
    rng.shuffle(ends)
    n_chunks = 5 if concrete else 4
    chunks = []
    for i, e in ends[:n_chunks]:
        b = pieces[i][0]
        caps = cap_faces(b, fm)
        f = max(caps, key=lambda f: e * f.calc_center_median().z)
        v = rng.choice(f.verts).co.copy()
        a = Vector((0, 0, e))
        if concrete:
            l = Vector((v.x - ax.x, v.y - ax.y, 0)).normalized()
            nrm = (l * 0.75 + a * 0.65).normalized()
            co = v - nrm * (rng.uniform(0.09, 0.14) * M)
        else:
            # скалка: площина майже вздовж валу, що виходить на бік за ~0.7-1.1 м від зламу
            l = Vector((v.x - ax.x, v.y - ax.y, 0)).normalized()
            s = 0.054 / rng.uniform(0.7, 1.1)
            nrm = (l + a * s).normalized()
            co = ax + l * (0.5 * 0.119 * M) + Vector((0, 0, f.calc_center_median().z))
        r = cut(b, co, nrm, fm)
        if r is None:
            continue
        b.free()
        pieces[i][0] = r[0]
        chunks.append([r[1], "chunk"])
    pieces += chunks
    if concrete:
        lim = limit(src_tris)
        for p in pieces:
            if p[1] == "chunk":
                continue
            for f in sorted(cap_faces(p[0], fm), key=lambda f: -f.calc_area())[:1]:
                if sum(tris(q[0]) for q in pieces) + 16 <= lim:
                    rebar(p[0], f, rng, rb)
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
            xs = [lo.x / M + (hi.x - lo.x) / M * (k / 5 + tilted(rng, 0.04)) for k in range(1, 5)]
            pieces += slice_x([[c, "board"]], xs, rng, 0.45)
    pieces = order(pieces)
    path, total, bb = export(name, name, pieces, mats)
    report(name, path, total, bb, sbb, st, len(pieces))


def sheet(name):
    """Профнастил: листи рвуться навпіл (один — упоперек, інші — по висоті), стовпи-труби лишаються цілими."""
    rng = rng_for(name)
    comps, mats, st, sbb, mn = fence_parts(name)
    fm = len(mats)
    mats.append(fracture_material("metal"))
    pieces = []
    k = 0
    for c, m in zip(comps, mn):
        if m.endswith("post"):
            pieces.append([c, "post"])
            continue
        lo, hi = bbox(c)
        if k % 2 == 0:
            x = lo.x + rng.uniform(0.3, 0.7) * (hi.x - lo.x)
            r = cut(c, (x, 0, 0.5 * (lo.z + hi.z)), (1, 0, tilted(rng, 0.35)), fm)
        else:
            z = lo.z + rng.uniform(0.4, 0.6) * (hi.z - lo.z)
            r = cut(c, (0.5 * (lo.x + hi.x), 0, z), (tilted(rng, 0.3), 0, 1), fm)
        k += 1
        c.free()
        pieces += [[r[0], "sheet"], [r[1], "sheet"]]
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
    mats.append(fracture_material("metal"))
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
        def vx(ps, xs, tilt=0.4, only=None):
            return slice_x(ps, xs, rng, tilt, None, only)

        def hz(ps, zs, tilt=0.0, idx=None):
            out = []
            for j, p in enumerate(ps):
                r = None
                if idx is None or j in idx:
                    for zc in zs:
                        r = cut(p[0], (0, 0, zc * M), (tilted(rng, tilt), 0, 1))
                        if r:
                            break
                if r is None:
                    out.append(p)
                else:
                    p[0].free()
                    out += [[r[0], p[1]], [r[1], p[1]]]
            return out
        ps = [[c, kind]]
        if kind == "picket":
            ps = vx(ps, [-4 + 8 * (i / 12) + rng.uniform(-0.1, 0.1) for i in range(1, 12)])
        elif kind == "sheet":
            ps = vx(ps, [-4 + 8 * (i / 10) + rng.uniform(-0.08, 0.08) for i in range(1, 10)], 0.12)
            ps = hz(ps, [0.9], 0.3, idx={0, 4, 8})
        elif kind == "chainlink":
            ps = vx(ps, [-1.46, 1.04, 3.54], 0.05)
            ps = vx(ps, [-2.7, -0.2, 2.3], 0.7)
            ps = hz(ps, [0.8], 0.3, idx={3, 4})
        elif kind == "brickbars":
            ps = hz(ps, [0.53], 0.0)
            for p_ in ps:                                    # цоколь і прути рвуться окремо: різні шматки, різні розрізи
                p_[1] = "plinth" if com(p_[0]).z < 0.53 * M else "bars"
            ps = slice_x(ps, [-2.5, -0.9, 0.8, 2.6], rng, 0.35, None, {"plinth"})
            ps = slice_x(ps, [-3.0, -1.5, 0.0, 1.6, 3.0], rng, 0.3, None, {"bars"})
        else:
            ps = hz(ps, [0.35], 0.0)
            ps = hz(ps, [0.65], 0.0)
            ps = hz(ps, [0.95], 0.0)
            ps = hz(ps, [1.25], 0.0)
            ps = vx(ps, [rng.uniform(-1.5, 1.5)], 0.5)
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
