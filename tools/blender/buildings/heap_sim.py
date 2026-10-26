"""Фізична симуляція завалу панельної будівлі: тверді тіла падають з висоти пролому на пагорб дрібної фракції.

Плити, шматки панелей (частина з віконним прорізом) і брили падають у Blender (rigid body, Bullet) із фіксованим зерном:
ті самі вхідні дані дають ті самі позиції. Модуль не знає про будівлю: приймає висоту пагорба й нерухомі коробки,
повертає для кожного уламка його контур, товщину й кінцеву матрицю.
"""
import math
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

FPS = 24


def _outline(rnd, L, W):
    """Опуклий контур плити L x W зі зрізаними (відколотими) кутами: плита не прямокутник, а зі сколами."""
    c = [(-L / 2, -W / 2), (L / 2, -W / 2), (L / 2, W / 2), (-L / 2, W / 2)]
    c = [(x * rnd.uniform(0.92, 1.0), y * rnd.uniform(0.92, 1.0)) for x, y in c]
    pts = []
    cut = rnd.sample(range(4), rnd.choice((2, 3)))
    for i, p in enumerate(c):
        if i in cut:
            a, d = c[i - 1], c[(i + 1) % 4]
            k1, k2 = rnd.uniform(0.12, 0.3), rnd.uniform(0.12, 0.3)
            pts.append((p[0] + (a[0] - p[0]) * k1, p[1] + (a[1] - p[1]) * k1))
            pts.append((p[0] + (d[0] - p[0]) * k2, p[1] + (d[1] - p[1]) * k2))
        else:
            pts.append(p)
    return pts


def _prism(pts, th):
    n = len(pts)
    v = [(x, y, th / 2) for x, y in pts] + [(x, y, -th / 2) for x, y in pts]
    f = [list(range(n))[::-1], list(range(n, 2 * n))]
    f += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    return v, f


def _panel(rnd, w, h, t, hole):
    """Шматок стінової панелі w x h x t; hole — з віконним прорізом (рамка з чотирьох брусів)."""
    if not hole:
        return _prism([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)], t)
    ow, oh = w * rnd.uniform(0.32, 0.42), h * rnd.uniform(0.3, 0.4)
    verts, faces = [], []

    def box(x0, x1, y0, y1):
        base = len(verts)
        for z in (t / 2, -t / 2):
            verts.extend([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)])
        faces.extend([[base, base + 1, base + 2, base + 3][::1], [base + 4, base + 7, base + 6, base + 5]])
        for i in range(4):
            j = (i + 1) % 4
            faces.append([base + i, base + 4 + i, base + 4 + j, base + j])
    box(-w / 2, w / 2, -h / 2, -oh / 2)
    box(-w / 2, w / 2, oh / 2, h / 2)
    box(-w / 2, -ow / 2, -oh / 2, oh / 2)
    box(ow / 2, w / 2, -oh / 2, oh / 2)
    return verts, faces


def _rock(rnd, size):
    """Брила: опукла оболонка 12-16 випадкових точок на витягнутій сфері."""
    n = rnd.randint(12, 16)
    a, b, c = size, size * rnd.uniform(0.6, 1.0), size * rnd.uniform(0.45, 0.8)
    pts = []
    for _ in range(n):
        v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
        pts.append((v.x * a / 2 * rnd.uniform(0.8, 1.0), v.y * b / 2 * rnd.uniform(0.8, 1.0), v.z * c / 2 * rnd.uniform(0.8, 1.0)))
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=list(bm.verts))
    bm.verts.ensure_lookup_table()
    verts = [tuple(v.co) for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return verts, faces


def _obj(name, verts, faces, loc, rot):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def _rigid(ob, kind, shape, mass=1.0):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.rigidbody.object_add(type=kind)
    rb = ob.rigid_body
    rb.collision_shape = shape
    rb.friction = 0.7
    rb.restitution = 0.03
    rb.use_margin = True
    rb.collision_margin = 0.004
    if kind == "ACTIVE":
        rb.mass = mass
        rb.linear_damping = 0.12
        rb.angular_damping = 0.3
    return rb


def _box_mesh(x0, x1, y0, y1, z0, z1):
    """Коробка з центром у початку об'єкта: форма BOX у Blender стоїть на початку, а не на центрі меша; повертає (verts, faces, центр)."""
    cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    hx, hy, hz = (x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz), (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    f = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    return v, f, (cx, cy, cz)


def simulate(seed, mound_h, boxes, region, counts, frames=240, floor_stubs=(), mound_grid=None):
    """Кидає уламки й повертає їхні кінцеві положення.

    mound_h(x, y) — висота пагорба дрібної фракції (нерухомий); boxes — нерухомі коробки (x0, x1, y0, y1, z0, z1): стіни крил, рештки задньої
    стіни; region = (x0, x1, y_in0, y_in1, y_out0, y_out1, z_lo, z_hi): звідки падають (всередині контуру й виштовхнуті назовні з боку фасаду);
    counts = (плит, панелей, брил); floor_stubs — (x0, x1, y0, y1, z_top, n): перекриття, на які падає по n дрібних шматків.
    Повертає {"pieces": [...], "floor": [...]}; елемент: kind, verts, faces, outline, th, matrix (4x4), size.
    """
    rnd = random.Random(seed)
    scene = bpy.context.scene
    scene.render.fps = FPS
    if scene.rigidbody_world is None:
        bpy.ops.rigidbody.world_add()
    rw = scene.rigidbody_world
    rw.substeps_per_frame = 30
    rw.solver_iterations = 40
    rw.point_cache.frame_start = 1
    rw.point_cache.frame_end = frames + 5
    scene.frame_start, scene.frame_end = 1, frames + 5
    scene.frame_set(1)
    made = []

    def passive(name, verts, faces, loc=(0, 0, 0), shape="MESH"):
        ob = _obj(name, verts, faces, loc, (0, 0, 0))
        _rigid(ob, "PASSIVE", shape)
        return ob

    passive("ground", *_box_mesh(-60, 60, -60, 60, -2.0, 0.0), shape="BOX")
    for i, bx in enumerate(boxes):
        passive("wall%d" % i, *_box_mesh(*bx), shape="BOX")
    for i, (x0, x1, y0, y1, zt, n) in enumerate(floor_stubs):
        passive("stub%d" % i, *_box_mesh(x0, x1, y0, y1, zt - 0.22, zt), shape="BOX")
        passive("stubw%d" % i, *_box_mesh(x0, x1, y0 - 0.2, y0, zt, zt + 1.2), shape="BOX")
        passive("stubv%d" % i, *_box_mesh(x0, x1, y1, y1 + 0.2, zt, zt + 1.2), shape="BOX")
    if mound_grid:                                                   # пагорб: трикутна сітка за висотою, нерухома
        (gx0, gx1, gy0, gy1, step) = mound_grid
        nx, ny = int((gx1 - gx0) / step) + 1, int((gy1 - gy0) / step) + 1
        verts = [(gx0 + i * step, gy0 + j * step, mound_h(gx0 + i * step, gy0 + j * step) - 0.02) for j in range(ny) for i in range(nx)]
        faces = []
        for j in range(ny - 1):
            for i in range(nx - 1):
                a = j * nx + i
                faces.append([a, a + 1, a + nx + 1, a + nx])
        # дно, щоб тіла не провалювались: сітка замкнена знизу площиною
        passive("mound", verts, faces, shape="MESH")

    pieces = []
    x0, x1, yi0, yi1, yo0, yo1, zlo, zhi = region
    rocks = ["rock"] * counts[2]
    panels = ["panel"] * counts[1]
    slabs = ["slab"] * counts[0]
    # порядок падіння: спершу дрібна фракція, плити лягають на вже насипане й спираються на нього під кутом; наприкінці ще дрібняк і шматки
    order = rocks[: len(rocks) // 3] + panels[: len(panels) // 2] + slabs[: len(slabs) // 2] + rocks[len(rocks) // 3: 2 * len(rocks) // 3] + slabs[len(slabs) // 2:] + panels[len(panels) // 2:] + rocks[2 * len(rocks) // 3:]
    layers = []                                                      # шар — набір кіл у плані, що не перекриваються: тіла починають падіння без перекриття

    def spot(rad, out):
        for li, lay in enumerate(layers):
            for _ in range(30):
                lo, hi = x0 + rad, x1 - rad                                  # тіло не заходить у стіни крил навіть краєм
                px = rnd.uniform(lo, hi) if lo < hi else (x0 + x1) / 2
                py = rnd.uniform(yo0 + rad, yo1 + rad) if out else rnd.uniform(yi0 + min(rad, 1.0), yi1)
                if all(math.hypot(px - qx, py - qy) > rad + qr + 0.05 for qx, qy, qr in lay):
                    lay.append((px, py, rad))
                    return px, py, zlo + li * 1.0
        layers.append([])
        return spot(rad, out)

    for k, kind in enumerate(order):
        if kind == "slab":
            L, W, th = rnd.uniform(3.0, 6.0), rnd.uniform(1.2, 3.0), rnd.uniform(0.16, 0.22)
            outline = _outline(rnd, L, W)
            verts, faces = _prism(outline, th)
            meta = dict(outline=outline, th=th, size=(L, W))
            vol, rad = L * W * th, math.hypot(L, W) / 2
        elif kind == "panel":
            w, h, t = rnd.uniform(0.4, 1.5), rnd.uniform(0.4, 1.4), rnd.uniform(0.14, 0.3)
            hole = w > 0.95 and h > 0.9 and rnd.random() < 0.45
            verts, faces = _panel(rnd, w, h, t, hole)
            meta = dict(outline=None, th=t, size=(w, h), hole=hole)
            vol, rad = w * h * t, math.hypot(w, h) / 2
        else:
            s = 0.2 + 0.4 * rnd.random() ** 0.8
            verts, faces = _rock(rnd, s)
            meta = dict(outline=None, th=s * 0.5, size=(s, s))
            vol, rad = s ** 3 * 0.35, s * 0.6
        out = rnd.random() < 0.38                                    # частину виштовхнуто назовні з боку фасаду
        px, py, pz = spot(rad, out)
        ob = _obj("p%d" % k, verts, faces, (px, py, pz), (rnd.uniform(-1.0, 1.0), rnd.uniform(-1.0, 1.0), rnd.uniform(0, 6.28)))
        _rigid(ob, "ACTIVE", "CONVEX_HULL", mass=max(0.05, vol * 2.4))
        pieces.append((ob, kind, verts, faces, meta))
    floor = []
    for i, (sx0, sx1, sy0, sy1, zt, n) in enumerate(floor_stubs):
        for j in range(n):
            s = rnd.uniform(0.2, 0.5)
            verts, faces = _rock(rnd, s)
            ob = _obj("f%d_%d" % (i, j), verts, faces, (rnd.uniform(sx0 + 0.4, sx1 - 0.4), rnd.uniform(sy0 + 0.4, sy1 - 0.4), zt + 0.6 + 0.4 * j),
                      (rnd.uniform(0, 6.28), rnd.uniform(0, 6.28), rnd.uniform(0, 6.28)))
            _rigid(ob, "ACTIVE", "CONVEX_HULL", mass=max(0.05, s ** 3 * 0.8))
            floor.append((ob, "rock", verts, faces, dict(outline=None, th=s * 0.5, size=(s, s), stub=i)))
    for f in range(2, frames + 1):
        scene.frame_set(f)
    bpy.context.view_layer.update()
    res = {"pieces": [], "floor": []}
    for lst, key in ((pieces, "pieces"), (floor, "floor")):
        for ob, kind, verts, faces, meta in lst:
            d = dict(kind=kind, verts=verts, faces=faces, matrix=ob.matrix_world.copy())
            d.update(meta)
            res[key].append(d)
    for ob in list(bpy.data.objects):                                # симуляція віддала положення: сцена лишається чистою для запікання
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.rigidbody.world_remove()
    scene.frame_set(1)
    return res
