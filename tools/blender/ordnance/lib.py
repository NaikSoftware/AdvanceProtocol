"""Спільне для мін і дрона: примітиви з вершинним кольором і експорт у GLB.

Запуск: blender -b --factory-startup -P <скрипт>.py
Будуємо в метрах; export(scale=1/8) переводить в одиниці гри (тайл = 1,0 = 8 м), +Y = перед, +Z = вгору, низ на z = 0.
Кольори задано в sRGB, у атрибут пишуться лінійні (Godot читає COLOR_0 як лінійний).
"""
import bpy, bmesh, os, math, json, struct
from mathutils import Matrix

OUT = os.path.abspath(os.environ.get("ORD_OUT", os.path.join(os.path.dirname(__file__), "..", "..", "..", "assets", "props", "ordnance")))


def lin(c):
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


class B:
    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def _paint(self, before, c):
        for f in self.bm.faces:
            if f not in before:
                for l in f.loops:
                    l[self.col] = lin(c)

    def _place(self, vs, at, rot):
        bmesh.ops.rotate(self.bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"))
        bmesh.ops.translate(self.bm, vec=at, verts=vs)

    def cone(self, c, at, r1, r2, h, seg=16, rot=0.0):
        """Зрізаний конус: низ на at, угору h, вісь вздовж Z."""
        before = set(self.bm.faces)
        vs = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r1, radius2=r2, depth=h)["verts"]
        bmesh.ops.translate(self.bm, vec=(0, 0, h / 2), verts=vs)
        self._place(vs, at, rot)
        self._paint(before, c)

    def box(self, c, at, size, rot=0.0):
        """Паралелепіпед із центром at."""
        before = set(self.bm.faces)
        vs = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        bmesh.ops.scale(self.bm, vec=size, verts=vs)
        self._place(vs, at, rot)
        self._paint(before, c)

    def ball(self, c, at, size, seg=12, rot=0.0):
        """Еліпсоїд із піврозмірами size."""
        before = set(self.bm.faces)
        vs = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=seg // 2, radius=1.0)["verts"]
        bmesh.ops.scale(self.bm, vec=size, verts=vs)
        self._place(vs, at, rot)
        self._paint(before, c)

    def export(self, name, scale=1.0):
        bm = self.bm
        bmesh.ops.scale(bm, vec=(scale, scale, scale), verts=bm.verts[:])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        me.materials.append(bpy.data.materials.new("ordnance"))
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        me.color_attributes.active_color = me.color_attributes["Col"]
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_cameras=False,
                                  export_lights=False, export_yup=True)
        check(path)
        bm.free()


def check(path):
    """Розбираємо записаний GLB, а не числа Blender: одна примітива, COLOR_0, без трансформу вузла."""
    d = open(path, "rb").read(); off = 12
    while off < len(d):
        n, t = struct.unpack_from("<II", d, off)
        if t == 0x4E4F534A:
            g = json.loads(d[off + 8:off + 8 + n]); break
        off += 8 + n
    prims = [p for m in g["meshes"] for p in m["primitives"]]
    assert len(prims) == 1, len(prims)
    assert "COLOR_0" in prims[0]["attributes"], list(prims[0]["attributes"])
    assert not [x for x in g["nodes"] if {"translation", "rotation", "scale", "matrix"} & x.keys()], "node transform"
    a = g["accessors"]
    pos = a[prims[0]["attributes"]["POSITION"]]
    print("BUILT", os.path.basename(path), "tris", a[prims[0]["indices"]]["count"] // 3, "min", pos["min"], "max", pos["max"])
