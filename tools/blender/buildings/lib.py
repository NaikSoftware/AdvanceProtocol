"""Спільна бібліотека будівель: геометрія з прямокутних і циліндричних частин, матеріали
ambientCG для запікання, запікання в один атлас, експорт у GLB.

Запуск з build_*.py: blender -b --factory-startup -P build_x.py -- <out_dir>
Одиниці: метри, фронт будівлі вздовж +Y (Blender), що в Godot стає -Z. Перед експортом усе
масштабується на 1/8 (тайл = 8 м = 1.0), початок координат у центрі підошви на землі.
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TEX_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "..", "art-refs", "buildings_tex"))
TILE = 8.0


# --------------------------------------------------------------------------- матеріали

def _img(name):
    path = os.path.join(TEX_DIR, name, f"{name}_1K-JPG_Color.jpg")
    return bpy.data.images.load(path, check_existing=True)


def make_material(name, tex=None, scale=1.0, tint=(1, 1, 1), flat=None, seams=(), streak=0.0,
                  base_dirt=0.0, patch=None, rough=0.85, sat=1.0, streak_col=(0.0, 0.0, 0.0), streak_xy=1.3, corr=None, bump=0.006, patch_scale=0.55, runs=None, recolor=None, vmul=False):
    """Матеріал, який запікається в атлас. Текстура тайлиться в метрах (box-проєкція в
    координатах обʼєкта), тож не залежить від UV. seams: (вісь, період м, ширина м, сила);
    вісь h = горизонталь стіни, x/y/z = координата обʼєкта. patch: (колір, частка) —
    плями моху, іржі або кіптяви."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new
    out = N("ShaderNodeOutputMaterial")
    bsdf = N("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = rough
    L(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = N("ShaderNodeTexCoord")
    sep = N("ShaderNodeSeparateXYZ")
    L(tc.outputs["Object"], sep.inputs["Vector"])

    def math(op, a=None, b=None, clamp=False):
        n = N("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                L(v, n.inputs[i])
        return n.outputs[0]

    def mix(a, b, fac, blend="MIX"):
        n = N("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = blend
        L(fac, n.inputs[0]) if not isinstance(fac, (int, float)) else n.inputs[0].__setattr__("default_value", fac)
        for i, v in ((6, a), (7, b)):
            if isinstance(v, (tuple, list)):
                n.inputs[i].default_value = (*v, 1.0)
            else:
                L(v, n.inputs[i])
        return n.outputs[2]

    hparts = []
    if flat is not None:
        col = (*flat, 1.0)
        base = None
    else:
        mp = N("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1 / scale,) * 3
        L(tc.outputs["Object"], mp.inputs["Vector"])
        it = N("ShaderNodeTexImage")
        it.image = _img(tex)
        it.projection = "BOX"
        it.projection_blend = 0.0
        L(mp.outputs["Vector"], it.inputs["Vector"])
        base = it.outputs["Color"]
        texcol = base
        bw = N("ShaderNodeRGBToBW")
        L(texcol, bw.inputs[0])
        hparts.append(math("MULTIPLY", bw.outputs[0], bump))
        if recolor is not None:
            gs = N("ShaderNodeHueSaturation")
            gs.inputs["Saturation"].default_value = 0.0
            L(texcol, gs.inputs["Color"])
            base = mix(gs.outputs["Color"], recolor, 1.0, "MULTIPLY")
            texcol = None
    if base is None:
        base = mix(flat, flat, 0.0)
    elif recolor is None:
        base = mix(base, tint, 1.0, "MULTIPLY")
        if sat != 1.0:
            hs = N("ShaderNodeHueSaturation")
            hs.inputs["Saturation"].default_value = sat
            L(base, hs.inputs["Color"])
            base = hs.outputs["Color"]

    # смуги потьоків: шум, розтягнутий по висоті
    if streak > 0:
        x, y, z = sep.outputs
        v = N("ShaderNodeCombineXYZ")
        L(math("MULTIPLY", x, streak_xy), v.inputs[0])
        L(math("MULTIPLY", y, streak_xy), v.inputs[1])
        L(math("MULTIPLY", z, 0.08), v.inputs[2])
        nz = N("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = 4.0
        L(v.outputs[0], nz.inputs["Vector"])
        cr = N("ShaderNodeValToRGB")
        cr.color_ramp.elements[0].position = 0.42
        cr.color_ramp.elements[1].position = 0.7
        L(nz.outputs["Fac"], cr.inputs[0])
        base = mix(base, streak_col, math("MULTIPLY", cr.outputs[0], streak * 0.55), "MIX")
    # забруднення біля землі
    if base_dirt > 0:
        h = math("SUBTRACT", 1.0, math("DIVIDE", sep.outputs[2], 2.5, clamp=True))
        base = mix(base, (0.0, 0.0, 0.0), math("MULTIPLY", h, base_dirt), "MIX")
    # плями (мох, іржа, кіптява)
    if patch is not None:
        pcol, frac = patch
        v = N("ShaderNodeMapping")
        v.inputs["Scale"].default_value = (patch_scale,) * 3
        L(tc.outputs["Object"], v.inputs["Vector"])
        nz = N("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = 6.0
        L(v.outputs[0], nz.inputs["Vector"])
        cr = N("ShaderNodeValToRGB")
        cr.color_ramp.elements[0].position = 1.0 - frac
        cr.color_ramp.elements[1].position = 1.0 - frac + 0.12
        L(nz.outputs["Fac"], cr.inputs[0])
        base = mix(base, pcol, cr.outputs[0], "MIX")
    # шви
    for axis, period, width, strength in seams:
        if axis == "h":
            nrm = N("ShaderNodeNewGeometry")
            ns = N("ShaderNodeSeparateXYZ")
            L(nrm.outputs["Normal"], ns.inputs[0])
            ax = math("ABSOLUTE", ns.outputs[0])
            ay = math("ABSOLUTE", ns.outputs[1])
            c = math("ADD", math("MULTIPLY", sep.outputs[0], ay), math("MULTIPLY", sep.outputs[1], ax))
        elif axis == "ang8":
            # кут навколо найближчої осі бункера (центри кожні 8 м від -12), у метрах дуги
            lx = math("SUBTRACT", math("MODULO", math("ADD", sep.outputs[0], 16.0), 8.0), 4.0)
            c = math("MULTIPLY", math("ARCTAN2", sep.outputs[1], lx), 3.5)
        else:
            c = sep.outputs["XYZ".index(axis.upper())]
        f = math("FRACT", math("DIVIDE", math("ADD", c, 10000.0), period))
        d = math("ABSOLUTE", math("SUBTRACT", f, 0.5))
        line = math("GREATER_THAN", d, 0.5 - width / period)
        base = mix(base, (0.0, 0.0, 0.0), math("MULTIPLY", line, strength), "MIX")
        hparts.append(math("MULTIPLY", line, -0.012))
    if vmul:
        vcm = N("ShaderNodeVertexColor")
        vcm.layer_name = "wtone"
        base = mix(base, vcm.outputs["Color"], 1.0, "MULTIPLY")
    # потьоки вниз від швів і заклепок: тонкі вертикальні смуги, що згасають нижче шва
    if runs is not None:
        period, rcol, rstr = runs[:3]
        # стовпці-смуги: кожен кут навколо осі й кожен поверх між швами мають свій випадковий хеш
        ang = math("MULTIPLY", math("ARCTAN2", sep.outputs[1], sep.outputs[0]), 24.0)
        cid = math("FLOOR", ang)
        zid = math("FLOOR", math("DIVIDE", math("ADD", sep.outputs[2], 0.001), period))
        hsh = math("FRACT", math("MULTIPLY", math("SINE", math("ADD", math("MULTIPLY", cid, 12.9898), math("MULTIPLY", zid, 78.233))), 43758.5453))
        on = math("LESS_THAN", hsh, 0.33)
        f = math("FRACT", math("DIVIDE", math("ADD", sep.outputs[2], 10000.0), period))
        fall = math("POWER", f, 1.6)               # найтемніше під швом, згасає на 1.5-3 м
        base = mix(base, rcol, math("MULTIPLY", math("MULTIPLY", on, fall), rstr), "MIX")
    # рельєф: хвилястість, текстурний рельєф і канавки швів — у карту нормалей
    if corr is not None:
        axis, pitch, amp = corr
        if axis == "h":
            nrm = N("ShaderNodeNewGeometry")
            ns = N("ShaderNodeSeparateXYZ")
            L(nrm.outputs["Normal"], ns.inputs[0])
            cc = math("ADD", math("MULTIPLY", sep.outputs[0], math("ABSOLUTE", ns.outputs[1])), math("MULTIPLY", sep.outputs[1], math("ABSOLUTE", ns.outputs[0])))
        else:
            cc = sep.outputs["XYZ".index(axis.upper())]
        wv = math("SUBTRACT", math("PINGPONG", math("MULTIPLY", cc, 2.0 / pitch), 1.0), 0.5)
        hparts.append(math("MULTIPLY", wv, amp * 2.0))
    if hparts:
        tot = hparts[0]
        for q in hparts[1:]:
            tot = math("ADD", tot, q)
        bn = N("ShaderNodeBump")
        bn.inputs["Strength"].default_value = 1.0
        bn.inputs["Distance"].default_value = 1.0
        L(tot, bn.inputs["Height"])
        L(bn.outputs["Normal"], bsdf.inputs["Normal"])
    L(base, bsdf.inputs["Base Color"])
    try:
        if flat is not None:
            m["approx"] = tuple(flat)
        elif recolor is not None:
            m["approx"] = tuple(c * 0.31 for c in recolor)
        elif tex is not None:
            im = _img(tex)
            if "mean_rgb" not in im:
                px = list(im.pixels[:])
                step = max(4, len(px) // 40000 // 4 * 4)
                rs = px[0::step]
                gs = px[1::step]
                bs_ = px[2::step]
                im["mean_rgb"] = (sum(rs) / len(rs), sum(gs) / len(gs), sum(bs_) / len(bs_))
            mr = im["mean_rgb"]
            m["approx"] = tuple((mr[i] ** 2.2) * tint[i] for i in range(3))
    except Exception:
        pass
    return m


def make_window_material():
    """Вікно одним квадом за локальними UV (шар "local"): зовнішній темний відкіс імітує
    заглиблення 10-15 см, далі рама, середник і скло. Тон з атрибута wtone: 0 небесно-сіре
    скло, 0.5 темне, 1 тепла штора."""
    m = bpy.data.materials.new("window")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    bs = N("ShaderNodeBsdfPrincipled")
    bs.inputs["Roughness"].default_value = 0.35
    L(bs.outputs["BSDF"], out.inputs["Surface"])
    uvn = N("ShaderNodeUVMap")
    uvn.uv_map = "local"
    ca = N("ShaderNodeVertexColor")
    ca.layer_name = "wtone"
    sep = N("ShaderNodeSeparateXYZ")
    L(uvn.outputs["UV"], sep.inputs[0])

    def math(op, a, b=None, clamp=False):
        n = N("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                L(v, n.inputs[i])
        return n.outputs[0]

    def mixc(a, b, fac):
        n = N("ShaderNodeMix")
        n.data_type = "RGBA"
        if isinstance(fac, (int, float)):
            n.inputs[0].default_value = fac
        else:
            L(fac, n.inputs[0])
        for i, v in ((6, a), (7, b)):
            if isinstance(v, tuple):
                n.inputs[i].default_value = (*v, 1.0)
            else:
                L(v, n.inputs[i])
        return n.outputs[2]

    u, v = sep.outputs[0], sep.outputs[1]
    edge = math("MINIMUM", math("MINIMUM", u, math("SUBTRACT", 1.0, u)), math("MINIMUM", v, math("SUBTRACT", 1.0, v)))
    reveal = math("LESS_THAN", edge, 0.05)
    frame = math("LESS_THAN", edge, 0.15)
    mull = math("LESS_THAN", math("ABSOLUTE", math("SUBTRACT", u, 0.5)), 0.03)
    sill = math("LESS_THAN", math("ABSOLUTE", math("SUBTRACT", v, 0.62)), 0.025)
    mask = math("MAXIMUM", math("MAXIMUM", frame, mull), sill)
    sky = math("MULTIPLY", math("ABSOLUTE", math("SUBTRACT", math("ADD", u, v), 1.0)), 0.5)
    glass_sky = mixc((0.085, 0.10, 0.115), (0.04, 0.05, 0.06), sky)
    tone = N("ShaderNodeSeparateColor")
    L(ca.outputs["Color"], tone.inputs[0])
    t = tone.outputs[0]
    g1 = mixc(glass_sky, (0.02, 0.025, 0.03), math("MULTIPLY", t, 2.0, True))
    g2 = mixc(g1, (0.11, 0.105, 0.10), math("SUBTRACT", math("MULTIPLY", t, 2.0), 1.0, True))
    fr = mixc(g2, (0.5, 0.5, 0.48), mask)
    rv = mixc(fr, (0.05, 0.045, 0.04), reveal)
    L(rv, bs.inputs["Base Color"])
    # рельєф: відкіс глибоко, скло злегка заглиблене відносно рами
    h = math("ADD", math("MULTIPLY", reveal, -0.12), math("MULTIPLY", math("SUBTRACT", 1.0, mask), -0.03))
    bn = N("ShaderNodeBump")
    bn.inputs["Distance"].default_value = 1.0
    L(h, bn.inputs["Height"])
    L(bn.outputs["Normal"], bs.inputs["Normal"])
    return m


def make_rubble_material(name, palette, scale=4.0):
    """Уламки 5-40 см: мозаїка Вороного, кожна клітинка — свій матеріал із палітри (цегла ~#6b4a3e,
    штукатурка, бетон, кіптява), темні щілини між уламками і рельєф для карти нормалей.
    palette — список (поріг, лінійний колір); клітинка бере перший колір, чий поріг більший за її випадкове число."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    bs = N("ShaderNodeBsdfPrincipled")
    bs.inputs["Roughness"].default_value = 0.95
    L(bs.outputs["BSDF"], out.inputs["Surface"])
    tc = N("ShaderNodeTexCoord")
    vc = N("ShaderNodeTexVoronoi")
    vc.voronoi_dimensions = "3D"
    vc.feature = "F1"
    vc.inputs["Scale"].default_value = scale
    L(tc.outputs["Object"], vc.inputs["Vector"])
    ve = N("ShaderNodeTexVoronoi")
    ve.voronoi_dimensions = "3D"
    ve.feature = "DISTANCE_TO_EDGE"
    ve.inputs["Scale"].default_value = scale
    L(tc.outputs["Object"], ve.inputs["Vector"])
    vf = N("ShaderNodeTexVoronoi")
    vf.voronoi_dimensions = "3D"
    vf.feature = "F1"
    vf.inputs["Scale"].default_value = scale * 3.3
    L(tc.outputs["Object"], vf.inputs["Vector"])
    bw = N("ShaderNodeRGBToBW")
    L(vc.outputs["Color"], bw.inputs[0])
    ramp = N("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    prev = 0.0
    for i, (thr, col) in enumerate(palette):
        if i >= len(els):
            els.new(prev)
        els[i].position = prev
        els[i].color = (*col, 1.0)
        prev = thr
    L(bw.outputs[0], ramp.inputs[0])
    # яскравість: різна для кожного уламка + дрібна крихта
    bwf = N("ShaderNodeRGBToBW")
    L(vf.outputs["Color"], bwf.inputs[0])
    bwv = N("ShaderNodeRGBToBW")
    L(vc.outputs["Color"], bwv.inputs[0])
    mapr = N("ShaderNodeMapRange")
    mapr.inputs["From Min"].default_value = 0.0
    mapr.inputs["From Max"].default_value = 0.1
    mapr.inputs["To Min"].default_value = 0.2
    mapr.inputs["To Max"].default_value = 1.0
    mapr.clamp = True
    L(ve.outputs["Distance"], mapr.inputs["Value"])
    mx = N("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    L(ramp.outputs["Color"], mx.inputs[6])
    comb = N("ShaderNodeCombineColor")
    for k in range(3):
        mm = N("ShaderNodeMath")
        mm.operation = "ADD"
        a = N("ShaderNodeMath")
        a.operation = "MULTIPLY"
        L(mapr.outputs[0], a.inputs[0])
        a.inputs[1].default_value = 0.8
        b2 = N("ShaderNodeMath")
        b2.operation = "MULTIPLY"
        L(bwf.outputs[0], b2.inputs[0])
        b2.inputs[1].default_value = 0.4
        L(a.outputs[0], mm.inputs[0])
        L(b2.outputs[0], mm.inputs[1])
        L(mm.outputs[0], comb.inputs[k])
    L(comb.outputs[0], mx.inputs[7])
    L(mx.outputs[2], bs.inputs["Base Color"])
    # рельєф: щілини глибокі, кожен уламок має свою висоту
    h1 = N("ShaderNodeMath")
    h1.operation = "MULTIPLY"
    L(mapr.outputs[0], h1.inputs[0])
    h1.inputs[1].default_value = 0.2
    h2 = N("ShaderNodeMath")
    h2.operation = "MULTIPLY"
    L(bwv.outputs[0], h2.inputs[0])
    h2.inputs[1].default_value = 0.14
    h3 = N("ShaderNodeMath")
    h3.operation = "ADD"
    L(h1.outputs[0], h3.inputs[0])
    L(h2.outputs[0], h3.inputs[1])
    bn = N("ShaderNodeBump")
    bn.inputs["Distance"].default_value = 1.0
    L(h3.outputs[0], bn.inputs["Height"])
    L(bn.outputs["Normal"], bs.inputs["Normal"])
    tot = sum(1 for _ in palette)
    w, prev = [0.0, 0.0, 0.0], 0.0
    for thr, col in palette:
        for i in range(3):
            w[i] += col[i] * (min(thr, 1.0) - prev)
        prev = min(thr, 1.0)
    m["approx"] = tuple(w)
    return m


def make_soot_material():
    """Кіптява з м'яким вертикальним градієнтом: тон береться з вершинного кольору грані."""
    m = bpy.data.materials.new("soot_v")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    bs = N("ShaderNodeBsdfPrincipled")
    L(bs.outputs["BSDF"], out.inputs["Surface"])
    ca = N("ShaderNodeVertexColor")
    ca.layer_name = "wtone"
    L(ca.outputs["Color"], bs.inputs["Base Color"])
    return m


_SCANS = None
MATS = {}
FLAT = {"frame", "dark"}


def mats():
    """Каталог матеріалів; створюється один раз на сцену."""
    if MATS:
        return MATS
    g = lambda v: (v, v, v)
    MATS.update({
        # нейтрально-теплий бетон панелей, шви між панелями 3 м і по поверхах
        "panel": make_material("panel", "Concrete034", 1.2, (0.56, 0.54, 0.50), seams=[("h", 3.0, 0.04, 0.55), ("z", 3.1, 0.05, 0.5)], streak=0.3, base_dirt=0.5, patch=((0.12, 0.13, 0.10), 0.14)),
        # кіптява плавними потьоками, без плям-«корів»
        "panel_scorched": make_material("panel_scorched", "Concrete034", 1.2, (0.20, 0.19, 0.18), seams=[("h", 3.0, 0.04, 0.4), ("z", 3.1, 0.05, 0.4)], streak=1.6, streak_xy=2.5, base_dirt=0.5),
        "char": make_material("char", flat=(0.03, 0.028, 0.026)),
        "bitumen": make_material("bitumen", "Asphalt031", 1.0, g(0.38), patch=((0.04, 0.045, 0.04), 0.2)),
        # шифер: смуги листів ~1.1 м вздовж коника і хвиля кроком 15 см униз по скату
        "fc_roof": make_material("fc_roof", "Concrete034", 1.2, (0.40, 0.40, 0.38), seams=[("y", 1.1, 0.05, 0.35)], corr=("y", 0.2, 0.016), streak=0.1, patch=((0.12, 0.16, 0.10), 0.05)),
        "fc_roof_x": make_material("fc_roof_x", "Concrete034", 1.2, (0.18, 0.18, 0.17), seams=[("x", 1.1, 0.05, 0.4)], corr=("x", 0.3, 0.012), streak=0.1, patch=((0.12, 0.16, 0.10), 0.05)),
        "wall_silicate": make_material("wall_silicate", "Plaster001", 1.0, (0.58, 0.57, 0.53), seams=[("z", 0.25, 0.05, 0.2)], streak=0.6, base_dirt=0.4),
        "clad_wall": make_material("clad_wall", "CorrugatedSteel005", 1.0, (0.60, 0.66, 0.60), seams=[("h", 1.0, 0.04, 0.4)], corr=("h", 0.2, 0.01), streak=1.0, base_dirt=0.5),
        # профнастил даху: ребра тільки від карниза до коника
        "clad_roof": make_material("clad_roof", "CorrugatedSteel005", 1.0, (0.34, 0.36, 0.32), seams=[("y", 1.0, 0.05, 0.5)], corr=("y", 0.2, 0.035), streak=0.3, patch=((0.2, 0.1, 0.05), 0.07)),
        "glass_roof": make_material("glass_roof", "CorrugatedSteel005", 1.0, (0.42, 0.50, 0.52), corr=("y", 0.2, 0.004), streak=0.3),
        "boards": make_material("boards", "Planks021", 1.0, (0.50, 0.45, 0.38), sat=0.35, seams=[("h", 0.2, 0.02, 0.85)], streak=1.0, base_dirt=0.5, bump=0.02),
        "brick_grey": make_material("brick_grey", "Bricks105", 1.0, (0.58, 0.54, 0.51), sat=0.3, streak=0.9, base_dirt=0.5),
        "floor_dark": make_material("floor_dark", "Concrete034", 1.5, g(0.10), patch=((0.02, 0.02, 0.02), 0.3)),
        "clad_burnt": make_material("clad_burnt", "CorrugatedSteel005", 1.0, (0.12, 0.12, 0.11), streak=1.0),
        "door_steel": make_material("door_steel", "CorrugatedSteel005", 1.0, (0.22, 0.34, 0.29), seams=[("z", 0.25, 0.03, 0.5)], corr=("z", 0.25, 0.008), base_dirt=0.5),
        "galv": make_material("galv", "CorrugatedSteel005", 1.0, (0.62, 0.66, 0.70), seams=[("z", 1.5, 0.04, 0.35), ("ang8", 1.1, 0.04, 0.3)], corr=("z", 0.25, 0.01), streak=0.8, base_dirt=0.4),
        "silo_concrete": make_material("silo_concrete", "Concrete034", 1.5, (0.55, 0.54, 0.51), seams=[("z", 1.5, 0.03, 0.2)], streak=0.3, base_dirt=0.6, patch=((0.1, 0.12, 0.09), 0.2)),
        # цегла: червоно-коричнева ~RGB 110/70/58, лише яскравість із текстури
        "brick": make_material("brick", "Bricks105", 1.3, recolor=(0.50, 0.20, 0.135), streak=0.7, base_dirt=0.4, bump=0.012, patch=((0.10, 0.06, 0.045), 0.4), patch_scale=0.6),
        # сталь: плями іржі лише великі (>3 м), плюс потьоки під швами
        "steel_paint": make_material("steel_paint", flat=(0.15, 0.19, 0.16), seams=[("z", 1.5, 0.05, 0.3)], base_dirt=0.3, patch=((0.11, 0.14, 0.12), 0.5), patch_scale=0.7, runs=(3.0, (0.30, 0.10, 0.04), 1.0, 18.0)),
        "metal_dark": make_material("metal_dark", "MetalPlates013", 1.0, g(0.8), streak=0.5),
        "rust": make_material("rust", "Rust004", 1.0, g(1.0)),
        "galv_cone": make_material("galv_cone", "CorrugatedSteel005", 1.0, (0.50, 0.54, 0.58), seams=[("ang8", 0.9, 0.05, 0.5)], base_dirt=0.1),
        "clad_inner": make_material("clad_inner", "CorrugatedSteel005", 1.0, (0.16, 0.17, 0.16), base_dirt=0.5),
        "pvc": make_material("pvc", flat=(0.40, 0.40, 0.38)),
        "pv": make_material("pv", flat=(0.04, 0.046, 0.062), seams=[("x", 1.0, 0.03, 0.7), ("y", 1.7, 0.03, 0.7)], patch=((0.08, 0.09, 0.115), 0.22), patch_scale=0.5),
        "wall_plaster": make_material("wall_plaster", "Plaster001", 1.0, (0.68, 0.64, 0.56), streak=0.2, base_dirt=0.5, bump=0.008, patch=((0.34, 0.31, 0.27), 0.25), patch_scale=0.9),
        "brick_face": make_material("brick_face", "Bricks105", 1.0, recolor=(0.61, 0.26, 0.145), streak=0.2, base_dirt=0.5, bump=0.02, patch=((0.09, 0.06, 0.04), 0.2), patch_scale=1.6),
        "tile_graphite": make_material("tile_graphite", "CorrugatedSteel005", 1.0, (0.20, 0.21, 0.22), seams=[("y", 0.35, 0.05, 0.7), ("x", 1.1, 0.05, 0.4)], corr=("y", 0.35, 0.035), streak=0.1),
        "tile_brown": make_material("tile_brown", "CorrugatedSteel005", 1.0, (0.28, 0.20, 0.16), seams=[("y", 0.35, 0.05, 0.7), ("x", 1.1, 0.05, 0.4)], corr=("y", 0.35, 0.035), streak=0.1),
        "tin_green": make_material("tin_green", "CorrugatedSteel005", 1.0, (0.33, 0.37, 0.34), seams=[("x", 1.0, 0.05, 0.5)], corr=("x", 0.2, 0.035), streak=0.08),
        "tin_ochre": make_material("tin_ochre", "CorrugatedSteel005", 1.0, (0.55, 0.46, 0.32), seams=[("x", 1.0, 0.05, 0.45)], corr=("x", 0.2, 0.018), streak=0.08),
        "step": make_material("step", "Concrete034", 1.0, (0.50, 0.49, 0.46), streak=0.4, base_dirt=0.5),
        "gutter": make_material("gutter", flat=(0.30, 0.31, 0.31)),
        "rebar": make_material("rebar", flat=(0.11, 0.06, 0.04)),
        "soot": make_material("soot", flat=(0.045, 0.04, 0.036)),
        "panel_light": make_material("panel_light", "Concrete034", 1.2, (0.26, 0.255, 0.25), streak=0.1, base_dirt=0.2),
        "rubble": make_rubble_material("rubble", [(0.30, (0.115, 0.055, 0.034)), (0.46, (0.145, 0.085, 0.05)), (0.66, (0.16, 0.13, 0.09)), (0.82, (0.10, 0.092, 0.075)), (0.95, (0.045, 0.038, 0.03)), (1.01, (0.26, 0.22, 0.12))]),
        "heap": make_rubble_material("heap", [(0.34, (0.115, 0.055, 0.034)), (0.50, (0.145, 0.085, 0.05)), (0.68, (0.16, 0.13, 0.09)), (0.86, (0.10, 0.092, 0.075)), (1.01, (0.045, 0.038, 0.03))]),
        "rubble_steel": make_rubble_material("rubble_steel", [(0.35, (0.05, 0.05, 0.05)), (0.6, (0.12, 0.13, 0.13)), (0.75, (0.15, 0.115, 0.095)), (0.9, (0.14, 0.14, 0.14)), (1.01, (0.24, 0.22, 0.15))], 3.0),
        "soot_v": make_soot_material(),
        "fc_roof_burnt": make_material("fc_roof_burnt", "Concrete034", 1.2, (0.07, 0.07, 0.07), seams=[("x", 1.1, 0.05, 0.3)], corr=("x", 0.2, 0.02), streak=1.0),
        "tin_red": make_material("tin_red", "CorrugatedSteel005", 1.0, (0.34, 0.25, 0.21), seams=[("x", 1.0, 0.05, 0.4)], corr=("x", 0.2, 0.03), streak=0.3, patch=((0.2, 0.12, 0.08), 0.3)),
        "timber_dark": make_material("timber_dark", flat=(0.03, 0.02, 0.014)),
        "cavity": make_material("cavity", flat=(0.014, 0.0135, 0.013)),
        "insul": make_material("insul", flat=(0.21, 0.21, 0.175)),
        "pump": make_material("pump", flat=(0.022, 0.026, 0.03)),
        "wall_ruin": make_material("wall_ruin", "Plaster001", 1.0, (0.44, 0.37, 0.30), streak=0.35, base_dirt=0.5, bump=0.035, patch=((0.19, 0.08, 0.045), 0.42), patch_scale=1.1, vmul=True),
        "panel_vc": make_material("panel_vc", "Concrete034", 1.2, (0.56, 0.54, 0.50), seams=[("h", 3.0, 0.04, 0.55), ("z", 3.1, 0.05, 0.5)], streak=0.3, base_dirt=0.5, vmul=True),
        "heap_grey": make_rubble_material("heap_grey", [(0.70, (0.115, 0.107, 0.088)), (0.80, (0.115, 0.055, 0.034)), (0.90, (0.16, 0.13, 0.09)), (1.01, (0.045, 0.038, 0.03))]),
        "pump_light": make_material("pump_light", flat=(0.12, 0.13, 0.14)),
        "cavity_black": make_material("cavity_black", flat=(0.003, 0.003, 0.003)),
        "pv_frame": make_material("pv_frame", flat=(0.10, 0.10, 0.105)),
        "brick_dark": make_material("brick_dark", "Bricks105", 1.0, recolor=(0.45, 0.22, 0.13), streak=0.5, base_dirt=0.6, bump=0.02),
        "slab_dark": make_material("slab_dark", "Concrete034", 1.2, (0.34, 0.32, 0.30), streak=0.2, base_dirt=0.5),
        "window": make_window_material(),
        "frame": make_material("frame", flat=(0.55, 0.55, 0.53)),
        "dark": make_material("dark", flat=(0.02, 0.02, 0.02)),
        "apron": make_material("apron", "Concrete034", 1.5, (0.42, 0.42, 0.40), seams=[("x", 5.0, 0.04, 0.6), ("y", 5.0, 0.04, 0.6)], streak=0.5, patch=((0.05, 0.05, 0.05), 0.25)),
        "kiosk": make_material("kiosk", "Plaster001", 1.0, (0.78, 0.75, 0.68), streak=1.0, base_dirt=0.6),
        "canopy": make_material("canopy", "CorrugatedSteel005", 1.0, (0.58, 0.58, 0.55), seams=[("x", 1.2, 0.05, 0.3)], streak=0.2),
    })
    return MATS
    g = lambda v: (v, v, v)
    MATS.update({
        # сірувато-бежева панель 3 м x поверх, шви між панелями
        "panel": make_material("panel", "Concrete034", 1.2, (0.50, 0.50, 0.47), seams=[("h", 3.0, 0.04, 0.55), ("z", 3.1, 0.05, 0.5)], streak=1.0, base_dirt=0.6, patch=((0.12, 0.13, 0.10), 0.14)),
        "panel_scorched": make_material("panel_scorched", "Concrete034", 1.2, (0.22, 0.21, 0.20), seams=[("h", 3.0, 0.04, 0.4), ("z", 3.1, 0.05, 0.4)], streak=1.0, base_dirt=0.5, patch=((0.01, 0.01, 0.01), 0.5)),
        "bitumen": make_material("bitumen", "Asphalt031", 1.0, g(0.38), patch=((0.04, 0.045, 0.04), 0.2)),
        "fc_roof": make_material("fc_roof", "Concrete034", 1.2, (0.33, 0.33, 0.32), seams=[("x", 1.1, 0.04, 0.3), ("y", 1.1, 0.04, 0.3)], streak=0.25, patch=((0.12, 0.16, 0.10), 0.06)),
        "wall_silicate": make_material("wall_silicate", "Plaster001", 1.0, (0.86, 0.86, 0.82), seams=[("z", 0.25, 0.05, 0.2)], streak=1.0, base_dirt=0.4),
        "clad_wall": make_material("clad_wall", "CorrugatedSteel005", 1.0, (0.62, 0.70, 0.62), seams=[("h", 1.0, 0.015, 0.55)], streak=1.0, base_dirt=0.5),
        "clad_roof": make_material("clad_roof", "CorrugatedSteel005", 1.0, (0.34, 0.36, 0.32), seams=[("y", 1.0, 0.04, 0.3), ("x", 1.0, 0.04, 0.3)], streak=0.4, patch=((0.2, 0.1, 0.05), 0.07)),
        "glass_roof": make_material("glass_roof", "CorrugatedSteel005", 1.0, (0.36, 0.42, 0.44), streak=0.5),
        "floor_dark": make_material("floor_dark", "Concrete034", 1.5, g(0.2), patch=((0.03, 0.03, 0.03), 0.3)),
        "boards": make_material("boards", "Planks021", 1.0, (0.50, 0.50, 0.48), sat=0.25, seams=[("h", 0.2, 0.012, 0.5)], streak=1.0, base_dirt=0.5),
        "brick_grey": make_material("brick_grey", "Bricks105", 1.0, (0.58, 0.54, 0.51), sat=0.3, streak=0.9, base_dirt=0.5),
        "clad_burnt": make_material("clad_burnt", "CorrugatedSteel005", 1.0, (0.12, 0.12, 0.11), streak=1.0),
        "door_steel": make_material("door_steel", "CorrugatedSteel005", 1.0, (0.20, 0.36, 0.30), seams=[("z", 0.25, 0.03, 0.5)], base_dirt=0.5),
        "galv": make_material("galv", "CorrugatedSteel005", 1.0, (0.62, 0.66, 0.70), seams=[("z", 1.5, 0.04, 0.35), ("ang8", 1.1, 0.04, 0.3)], streak=0.8, base_dirt=0.4),
        "silo_concrete": make_material("silo_concrete", "Concrete034", 1.5, (0.52, 0.52, 0.5), seams=[("z", 1.5, 0.02, 0.4)], streak=1.0, base_dirt=0.6, patch=((0.1, 0.12, 0.09), 0.2)),
        "brick": make_material("brick", "Bricks105", 1.0, (0.66, 0.46, 0.38), sat=0.5, streak=0.9, base_dirt=0.5),
        "steel_paint": make_material("steel_paint", "PaintedMetal012", 1.0, (0.5, 0.5, 0.48), streak=1.6, streak_xy=6.0, base_dirt=0.5, streak_col=(0.28, 0.11, 0.05)),
        "metal_dark": make_material("metal_dark", "MetalPlates013", 1.0, g(0.8), streak=0.5),
        "rust": make_material("rust", "Rust004", 1.0, g(1.0)),
        "window": make_window_material(),
        "frame": make_material("frame", flat=(0.55, 0.55, 0.53)),
        "dark": make_material("dark", flat=(0.02, 0.02, 0.02)),
        "apron": make_material("apron", "Concrete046", 1.5, (0.5, 0.5, 0.47), seams=[("x", 5.0, 0.03, 0.7), ("y", 5.0, 0.03, 0.7)], streak=0.6, patch=((0.05, 0.05, 0.05), 0.25)),
        "rubble": make_material("rubble", "Concrete034", 0.8, (0.30, 0.27, 0.25), patch=((0.2, 0.1, 0.07), 0.4)),
 "canopy": make_material("canopy", "CorrugatedSteel005", 1.0, (0.58, 0.58, 0.55), seams=[("x", 1.2, 0.05, 0.3)], streak=0.2),
    })
    return MATS


# --------------------------------------------------------------------------- геометрія

class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.slots = []
        self.local = self.bm.loops.layers.uv.new("local")
        self.wtone = self.bm.loops.layers.color.new("wtone")
        import random
        self.rnd = random.Random(5)

    def _slot(self, name):
        if name not in self.slots:
            self.slots.append(name)
        return self.slots.index(name)

    def _finish(self, faces, mat):
        i = self._slot(mat)
        for f in faces:
            f.material_index = i

    def box(self, cx, cy, z0, sx, sy, sz, mat, rot=0.0, top=None, tilt=0.0):
        """Паралелепіпед; низ не будується (знизу не видно). top — матеріал верхньої грані.
        tilt — нахил навколо осі X, щоб показувати зігнуті листи."""
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = r["verts"]
        bmesh.ops.scale(self.bm, vec=(sx, sy, sz), verts=verts)
        bmesh.ops.translate(self.bm, vec=(0, 0, sz / 2), verts=verts)
        if tilt:
            bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(tilt, 3, "X"), verts=verts)
        if rot:
            bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(rot, 3, "Z"), verts=verts)
        bmesh.ops.translate(self.bm, vec=(cx, cy, z0), verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        down = [f for f in faces if f.normal.z < -0.9]
        bmesh.ops.delete(self.bm, geom=down, context="FACES_ONLY")
        faces = [f for f in faces if f.is_valid]
        self._finish(faces, mat)
        if top:
            self._finish([f for f in faces if f.normal.z > 0.9], top)
        return faces

    def beam(self, p0, p1, w, mat, d=None):
        """Балка між двома точками (двотавр спрощений до бруса w x d)."""
        from mathutils import Quaternion
        a, c = Vector(p0), Vector(p1)
        dirv = c - a
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = r["verts"]
        bmesh.ops.scale(self.bm, vec=(w, d or w, dirv.length), verts=verts)
        q = Vector((0, 0, 1)).rotation_difference(dirv.normalized())
        bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=q.to_matrix(), verts=verts)
        bmesh.ops.translate(self.bm, vec=(a + c) / 2, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        self._finish(faces, mat)

    def poly_out(self, pts, mat, centre):
        """Многокутник, нормаль якого дивиться від точки centre (для стінок циліндрів)."""
        v = [Vector(p) for p in pts]
        n = (v[1] - v[0]).cross(v[2] - v[1])
        mid = sum(v, Vector()) / len(v)
        return self.poly(pts if n.dot(mid - Vector(centre)) >= 0 else pts[::-1], mat)

    def cyl_arch(self, cx, cy, r_at, ang, z0, w, h, mat):
        """Арковий проріз (темний) на похилій циліндричній стіні: r_at(z) — радіус на висоті z."""
        arc = [(-w / 2 + w * i / 6, h - w / 2 + math.sqrt(max((w / 2) ** 2 - (-w / 2 + w * i / 6) ** 2, 0.0))) for i in range(7)]
        loc = [(-w / 2, 0.0), (w / 2, 0.0)] + arc[::-1]
        pts = []
        for xl, zl in loc:
            z = z0 + zl
            r = r_at(z) + 0.02
            th = ang + xl / r
            pts.append((cx + r * math.cos(th), cy + r * math.sin(th), z))
        self.poly_out(pts, mat, (cx, cy, z0 + h / 2))

    def ladder(self, x, y, z0, h, along="x", mat="metal_dark"):
        """Драбина з поручнями і щаблями, видна зверху як силует і тінь."""
        sx, sy = (0.5, 0.06) if along == "x" else (0.06, 0.5)
        for d in (-0.24, 0.24):
            self.box(x + (d if along == "x" else 0), y + (d if along == "y" else 0), z0, 0.06 if along == "x" else 0.1, 0.06 if along == "y" else 0.1, h, mat)
        n = int(h / 0.4)
        for k in range(n):
            self.box(x, y, z0 + 0.3 + k * 0.4, sx, sy, 0.04, mat)

    def poly_up(self, pts, mat):
        """Многокутник, нормаль якого дивиться вгору (для скатів і плит)."""
        v = [Vector(p) for p in pts]
        n = (v[1] - v[0]).cross(v[2] - v[1])
        return self.poly(pts if n.z >= 0 else pts[::-1], mat)

    def rock(self, cx, cy, cz, size, mat, rnd, buried=0.3):
        """Уламок зі скану Poly Haven (CC0, ~110 трикутників): випадкова деталь, масштаб, поворот; наполовину вкопаний."""
        from mathutils import Euler
        global _SCANS
        if _SCANS is None:
            with open(os.path.join(HERE, "debris_scans.json")) as fh:
                _SCANS = json.load(fh)
        piece = _SCANS[rnd.choice(sorted(_SCANS))]
        sx, sy, sz = size * rnd.uniform(0.8, 1.3), size * rnd.uniform(0.7, 1.2), size * rnd.uniform(0.5, 0.95)
        rot = Euler((rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(0, 3.14))).to_matrix()
        vs = []
        for v in piece["v"]:
            p = rot @ Vector((v[0] * sx, v[1] * sy, v[2] * sz))
            vs.append(self.bm.verts.new((cx + p.x, cy + p.y, cz - sz * buried + p.z)))
        faces = []
        for f in piece["f"]:
            try:
                faces.append(self.bm.faces.new([vs[i] for i in f]))
            except ValueError:
                pass
        self._finish(faces, mat)

    def soot(self, pts, tones, side=1):
        """Кіптява: грань з вершинними тонами (темніше внизу, світліше вгорі)."""
        f = self.poly(pts if side > 0 else pts[::-1], "soot_v")
        loops = list(f.loops)
        seq = tones if side > 0 else tones[::-1]
        for lp, t in zip(loops, seq):
            lp[self.wtone] = (t, t, t, 1.0)
        return f

    def box_e(self, cx, cy, cz, sx, sy, sz, mat, euler=(0.0, 0.0, 0.0), top=None):
        """Брила з довільним поворотом навколо центру (уламки, зламані балки)."""
        from mathutils import Euler
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = r["verts"]
        bmesh.ops.scale(self.bm, vec=(sx, sy, sz), verts=verts)
        bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=Euler(euler).to_matrix(), verts=verts)
        bmesh.ops.translate(self.bm, vec=(cx, cy, cz), verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        self._finish(faces, mat)
        if top:
            self._finish([f for f in faces if f.normal.z > 0.5], top)

    def hip(self, x0, x1, y0, y1, z_eave, z_ridge, mat, mat_end=None, overhang=0.0):
        """Вальмовий дах: коник уздовж X завдовжки (x1-x0)-(y1-y0)."""
        mat_end = mat_end or mat
        d = (y1 - y0) / 2
        xa, xb, ya, yb = x0 - overhang, x1 + overhang, y0 - overhang, y1 + overhang
        xr0, xr1 = x0 + d, x1 - d
        ym = (y0 + y1) / 2
        self.poly([(xa, ya, z_eave), (xb, ya, z_eave), (xr1, ym, z_ridge), (xr0, ym, z_ridge)], mat)
        self.poly([(xb, yb, z_eave), (xa, yb, z_eave), (xr0, ym, z_ridge), (xr1, ym, z_ridge)], mat)
        self.poly([(xa, yb, z_eave), (xa, ya, z_eave), (xr0, ym, z_ridge)], mat_end)
        self.poly([(xb, ya, z_eave), (xb, yb, z_eave), (xr1, ym, z_ridge)], mat_end)

    def poly(self, pts, mat):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        self._finish([f], mat)
        return f

    def gable(self, x0, x1, y0, y1, z_eave, z_ridge, mat, wall_mat, ridge_axis="x", overhang=0.0):
        """Двосхилий дах на прямокутнику; ridge_axis — вздовж якої осі йде коньок."""
        if ridge_axis == "x":
            ym = (y0 + y1) / 2
            ya, yb = y0 - overhang, y1 + overhang
            xa, xb = x0 - overhang, x1 + overhang
            self.poly([(xa, ya, z_eave), (xb, ya, z_eave), (xb, ym, z_ridge), (xa, ym, z_ridge)], mat)
            self.poly([(xb, yb, z_eave), (xa, yb, z_eave), (xa, ym, z_ridge), (xb, ym, z_ridge)], mat)
            self.poly([(x0, y0, z_eave), (x0, y1, z_eave), (x0, ym, z_ridge)], wall_mat)
            self.poly([(x1, y1, z_eave), (x1, y0, z_eave), (x1, ym, z_ridge)], wall_mat)
        else:
            xm = (x0 + x1) / 2
            xa, xb = x0 - overhang, x1 + overhang
            ya, yb = y0 - overhang, y1 + overhang
            self.poly([(xb, ya, z_eave), (xb, yb, z_eave), (xm, yb, z_ridge), (xm, ya, z_ridge)], mat)
            self.poly([(xa, yb, z_eave), (xa, ya, z_eave), (xm, ya, z_ridge), (xm, yb, z_ridge)], mat)
            self.poly([(x1, y0, z_eave), (x0, y0, z_eave), (xm, y0, z_ridge)], wall_mat)
            self.poly([(x0, y1, z_eave), (x1, y1, z_eave), (xm, y1, z_ridge)], wall_mat)

    def cyl(self, cx, cy, z0, r, h, seg, mat, r_top=None, cap=True, cap_mat=None):
        """Циліндр або зрізаний конус. cap — верхня кришка."""
        rt = r if r_top is None else r_top
        bot = [self.bm.verts.new((cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg), z0)) for i in range(seg)]
        top = [self.bm.verts.new((cx + rt * math.cos(2 * math.pi * i / seg), cy + rt * math.sin(2 * math.pi * i / seg), z0 + h)) for i in range(seg)]
        side = []
        for i in range(seg):
            j = (i + 1) % seg
            side.append(self.bm.faces.new((bot[i], bot[j], top[j], top[i])))
        self._finish(side, mat)
        if cap and rt > 1e-6:
            c = self.bm.faces.new(top[::-1])
            self._finish([c], cap_mat or mat)
        return side

    def cone(self, cx, cy, z0, r, h, seg, mat):
        apex = self.bm.verts.new((cx, cy, z0 + h))
        bot = [self.bm.verts.new((cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg), z0)) for i in range(seg)]
        fs = [self.bm.faces.new((bot[i], bot[(i + 1) % seg], apex)) for i in range(seg)]
        self._finish(fs, mat)

    def window(self, face, pos, z0, w, h, frame=None):
        """Вікно одним квадом. face: ('y', y, +1/-1) — стіна з нормаллю по Y; ('x', x, ±1) — по X.
        pos — координата вздовж стіни (центр). Рама й скло — у шейдері."""
        axis, c, sgn = face
        off = 0.03 * sgn
        a, bb = pos - w / 2, pos + w / 2
        if axis == "y":
            pts = [(a, c + off, z0), (bb, c + off, z0), (bb, c + off, z0 + h), (a, c + off, z0 + h)]
        else:
            pts = [(c + off, a, z0), (c + off, bb, z0), (c + off, bb, z0 + h), (c + off, a, z0 + h)]
        if (axis == "y") == (sgn < 0):
            pts = pts[::-1]
            loc = [(0, 1), (1, 1), (1, 0), (0, 0)][::-1]
            loc = [(1, 0), (0, 0), (0, 1), (1, 1)]
        else:
            loc = [(0, 0), (1, 0), (1, 1), (0, 1)]
        f = self.poly(pts, "window")
        layer = self.local
        tone = self.rnd.choices((0.0, 0.5, 1.0), weights=(85, 9, 6))[0]
        for lp, uvv in zip(f.loops, loc):
            lp[layer].uv = uvv
            lp[self.wtone] = (tone, tone, tone, 1.0)

    def tris(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)


def mound(b, cx, cy, rx, ry, hmax, seed, mat="heap", rings=6, segs=20, z0=0.0, tongues=3, lump=0.4):
    """Купа уламків одним мешем: контур із частками й язиками, низькочастотні западини й піки."""
    import random
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(4)]
    tong = [(rnd.uniform(0, 6.28), rnd.uniform(0.2, 0.4)) for _ in range(tongues)]
    rad = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        r = 1.0 + 0.22 * math.sin(3 * a + ph[0]) + 0.16 * math.sin(5 * a + ph[1]) + rnd.uniform(-0.2, 0.2)
        for (ta, tw) in tong:
            d = abs((a - ta + math.pi) % (2 * math.pi) - math.pi)
            r += tw * max(0.0, 1 - d / 0.6)
        rad.append(min(1.55, max(0.45, r)))
    ring = []
    for k in range(rings + 1):
        t = k / rings
        row = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            r = t * rad[i]
            noise = 1.0 + 0.4 * math.sin(2 * a + ph[2] + 3 * t) + 0.3 * math.sin(5 * a + ph[3] - 4 * t) + 0.25 * math.sin(9 * a + ph[0] + 7 * t) + rnd.uniform(-0.3, 0.3)
            z = z0 + hmax * (1 - t ** 2.3) * noise * rnd.uniform(0.75, 1.05) if k < rings else z0 - 0.12
            px, py = cx + rx * r * math.cos(a), cy + ry * r * math.sin(a)
            if k < rings and lump:
                kk = 2 * math.pi / 1.75
                z += lump * math.sin(kk * px + ph[0]) * math.sin(kk * py + ph[1]) * (1 - t)
            row.append(b.bm.verts.new((px, py, max(z0 - 0.12, z))))
        ring.append(row)
    fs = []
    top = b.bm.verts.new((cx, cy, z0 + hmax * 0.95))
    for i in range(segs):
        j = (i + 1) % segs
        fs.append(b.bm.faces.new((ring[0][i], ring[0][j], top)))
        for k in range(rings):
            fs.append(b.bm.faces.new((ring[k][i], ring[k + 1][i], ring[k + 1][j], ring[k][j])))
    b._finish(fs, mat)


def wall_run(b, p0, p1, thick, heights, mat, top_mat, seed=0, pitch=1.0, soot_h=1.5, top_tone=0.8, inner_tone=0.9, brick_mat="brick_face"):
    """Уламок стіни p0-p1: сегменти різної ширини (0.5-2.4 м), випадкова ходьба висот із ≥3 глибинами й похилими
    зламами; верхні 0.4 м — відкрита цегла (як у купі), решта — штукатурка. Висоти heights задають огляд."""
    import random
    rnd = random.Random(seed)
    n0 = len(heights) - 1
    d = Vector((p1[0] - p0[0], p1[1] - p0[1], 0))
    ln = d.length
    u = d.normalized()
    nrm = Vector((-u.y, u.x, 0)) * thick / 2

    def hat(t):
        x = t * n0
        i = min(n0 - 1, int(x))
        return heights[i] * (1 - (x - i)) + heights[i + 1] * (x - i)
    cuts = [0.0]
    while cuts[-1] < ln - 0.3:
        cuts.append(min(ln, cuts[-1] + rnd.uniform(0.35, 1.5)))
    cuts[-1] = ln
    segs = []
    h = None
    for i in range(len(cuts) - 1):
        t = (cuts[i] + cuts[i + 1]) / 2 / ln
        hb = hat(t)
        if hb <= 0.05:
            segs.append((0.0, 0.0))
            h = None
            continue
        h = hb if h is None else max(0.3, min(3.2, h + rnd.choice((-0.6, -0.4, -0.2, 0.2, 0.35, 0.6, -1.0, 0.9))))
        diag = rnd.uniform(0.5, 1.1) * rnd.choice((-1, 1)) if rnd.random() < 0.35 else rnd.uniform(-0.1, 0.1)
        segs.append((max(0.2, h - diag / 2), max(0.2, h + diag / 2)))

    def quad(pts, tones, m):
        f = b.poly([tuple(q) for q in pts], m)
        for lp, t in zip(f.loops, tones):
            lp[b.wtone] = (t, t, t, 1.0)

    def V(q, z):
        return Vector((q.x, q.y, z))

    for i in range(len(segs)):
        a = Vector((p0[0], p0[1], 0)) + u * cuts[i]
        c = Vector((p0[0], p0[1], 0)) + u * cuts[i + 1]
        ha, hc = segs[i]
        if ha <= 0.05 and hc <= 0.05:
            continue
        pb = [a + nrm, c + nrm, c - nrm, a - nrm]
        br_a, br_c = max(0.0, ha - 0.4), max(0.0, hc - 0.4)
        lo_a, lo_c = max(0.0, br_a - soot_h), max(0.0, br_c - soot_h)
        for (q0, q1, tn) in ((pb[0], pb[1], 1.0), (pb[2], pb[3], inner_tone)):
            flip = q0 is pb[2]
            ah, ch = (hc, ha) if flip else (ha, hc)
            ba, bc = (br_c, br_a) if flip else (br_a, br_c)
            la, lc = (lo_c, lo_a) if flip else (lo_a, lo_c)
            quad([V(q0, 0), V(q1, 0), V(q1, lc), V(q0, la)], (tn,) * 4, mat)
            quad([V(q0, la), V(q1, lc), V(q1, bc), V(q0, ba)], (tn, tn, tn * top_tone, tn * top_tone), mat)
            f = b.poly([tuple(q) for q in (V(q0, ba), V(q1, bc), V(q1, ch), V(q0, ah))], brick_mat)
        b.poly([tuple(q) for q in (V(pb[0], ha), V(pb[1], hc), V(pb[2], hc), V(pb[3], ha))], brick_mat)
        b.poly([tuple(q) for q in (V(pb[1], 0), V(pb[2], 0), V(pb[2], hc), V(pb[1], hc))], brick_mat)
        b.poly([tuple(q) for q in (V(pb[3], 0), V(pb[0], 0), V(pb[0], ha), V(pb[3], ha))], brick_mat)


def panel_wall(b, p0, p1, thick, heights, mat, seed=0, piece=3.0, tilt=0.05, inner=(0.0, 1.0), lips=(), wall_tone=0.14):
    """Збірна стіна з прямих панелей по piece м: два рівні зламаного верху, легке відхилення від виска, губи
    плит перекриттів на лініях поверхів, кіптява вгору по зовнішньому боці. Повертає точки, де вкорінені стрижні."""
    import random
    rnd = random.Random(seed)
    d = Vector((p1[0] - p0[0], p1[1] - p0[1], 0))
    ln = d.length
    u = d.normalized()
    n = max(1, int(round(ln / piece)))
    w = ln / n
    roots = []
    yaw = math.atan2(u.y, u.x)
    outer = Vector((-inner[0], -inner[1], 0))
    for i in range(n):
        h = heights[min(i, len(heights) - 1)]
        if h <= 0.05:
            continue
        cx = p0[0] + u.x * w * (i + 0.5)
        cy = p0[1] + u.y * w * (i + 0.5)
        tl = rnd.uniform(-tilt, tilt)
        for (k, frac, drop) in ((0, 0.55, 0.0), (1, 0.45, rnd.uniform(0.5, 1.3))):
            ww = w * frac
            off = (-w / 2 + ww / 2) if k == 0 else (-w / 2 + w * 0.55 + ww / 2)
            hh = max(0.4, h - drop)
            px, py = cx + u.x * off, cy + u.y * off
            b.box_e(px, py, hh / 2, ww, thick, hh, mat, euler=(tl, 0.0, yaw), top=mat)
            roots.append((px + u.x * ww * rnd.uniform(-0.3, 0.3), py + u.y * ww * rnd.uniform(-0.3, 0.3), hh))
            # кіптява зовні: темніше вгорі, м'яко згасає донизу (тон відносно тла стіни wall_tone)
            sx, sy = px + outer.x * (thick / 2 + 0.02), py + outer.y * (thick / 2 + 0.02)
            q = [(sx - u.x * ww / 2, sy - u.y * ww / 2, max(0.1, hh - 1.6)), (sx + u.x * ww / 2, sy + u.y * ww / 2, max(0.1, hh - 1.6)),
                 (sx + u.x * ww / 2, sy + u.y * ww / 2, hh), (sx - u.x * ww / 2, sy - u.y * ww / 2, hh)]
            nn = (Vector(q[1]) - Vector(q[0])).cross(Vector(q[2]) - Vector(q[1]))
            tones = (wall_tone, wall_tone, wall_tone * 0.45, wall_tone * 0.45)
            if nn.dot(outer) < 0:
                q, tones = q[::-1], tones[::-1]
            b.soot(q, tones, 1)
        for lz in lips:
            if lz < h - 0.4:
                lx, ly = cx + inner[0] * 0.55, cy + inner[1] * 0.55
                b.box_e(lx, ly, lz, w * rnd.uniform(0.6, 0.95), 1.1, 0.2, mat, euler=(0, 0, yaw + rnd.uniform(-0.05, 0.05)), top=mat)
    return roots


def burn_ring(b, axis, c, u, z, w, h, sgn, g_side=0.65, g_bot=0.3, g_top=1.1, t_in=0.045, t_out=0.145):
    """Кіптява навколо прорізу: темніша за стіну (≈0.45 її тону), м'яко згасає назовні, найсильніша над прорізом.
    axis 'y': стіна з нормаллю по Y на y=c, u — координата по X; axis 'x': нормаль по X."""
    e = 0.02 * sgn
    def P(du, zz):
        return (u + du, c + e, zz) if axis == "y" else (c + e, u + du, zz)
    hw = w / 2
    inner = [(-hw, z), (hw, z), (hw, z + h), (-hw, z + h)]
    outer = [(-hw - g_side, z - g_bot), (hw + g_side, z - g_bot), (hw + g_side * 0.7, z + h + g_top), (-hw - g_side * 0.7, z + h + g_top)]
    outn = Vector((0, sgn, 0)) if axis == "y" else Vector((sgn, 0, 0))
    for i in range(4):
        j = (i + 1) % 4
        pts = [P(*inner[i]), P(*inner[j]), P(*outer[j]), P(*outer[i])]
        n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        tones = (t_in, t_in, t_out, t_out)
        if n.dot(outn) < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)


def bent_sheet(b, p0, p1, width, mat, bend=0.35, axis="y"):
    """Зігнутий лист покрівлі: дві грані з перегином посередині; ширина вздовж осі axis."""
    p0, p1 = Vector(p0), Vector(p1)
    mid = (p0 + p1) / 2
    pm = mid + Vector((0, 0, bend))
    thin, wide = (0.1, width) if axis == "y" else (width, 0.1)
    b.beam(p0, pm, thin, mat, wide)
    b.beam(pm, p1, thin, mat, wide)


def chunks(b, cx, cy, r, hmax, n, mats, seed, z0=0.0, smin=0.5, smax=1.5):
    """Купа кутастих уламків: нерівні багатогранники, повернуті випадково; вища до центру."""
    import random
    rnd = random.Random(seed)
    for _ in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        d = r * math.sqrt(rnd.uniform(0, 1))
        sz = rnd.uniform(smin, smax)
        zc = z0 + hmax * (1 - d / r) * rnd.uniform(0.35, 1.0) + sz * 0.25
        b.rock(cx + d * math.cos(a), cy + d * math.sin(a), zc, sz, rnd.choice(mats), rnd)


def lump(b, cx, cy, r, h, mat, seed, n=1):
    """Куча уламків: грубі нахилені призми, що перекриваються."""
    import random
    rnd = random.Random(seed)
    for _ in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0, r * 0.6)
        s = rnd.uniform(0.2, 0.45) * r
        hh = h * rnd.uniform(0.3, 1.0) * (1 - d / (r * 0.8))
        b.box(cx + d * math.cos(a), cy + d * math.sin(a), 0, s, s * rnd.uniform(0.6, 1.1), max(hh, 0.2), mat, rot=rnd.uniform(0, 3), top=mat)


# --------------------------------------------------------------------------- вихід

def unwrap(me, flat, atlas_px, weights=None):
    """Власна розгортка: кожна грань — плоский острівець у метричному масштабі (однакова
    щільність текселів), острівці укладаються полицями. Вбудована smart_project дає різну
    щільність по осях. Плоскі матеріали (скло, рама, темне) відображаються на малі квадрати-
    зразки у верхній смужці атласу."""
    if "UVMap" in me.uv_layers:
        me.uv_layers.remove(me.uv_layers["UVMap"])
    uvl = me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uvl
    uvl.active_render = True
    islands = []
    for poly in me.polygons:
        if poly.material_index in flat:
            continue
        n = poly.normal
        ls = list(poly.loop_indices)
        pts = [me.vertices[me.loops[l].vertex_index].co for l in ls]
        e = pts[1] - pts[0]
        uax = e.normalized()
        vax = n.cross(uax).normalized()
        loc = [((q - pts[0]).dot(uax), (q - pts[0]).dot(vax)) for q in pts]
        u0 = min(c[0] for c in loc)
        v0 = min(c[1] for c in loc)
        loc = [(c[0] - u0, c[1] - v0) for c in loc]
        w = max(c[0] for c in loc)
        h = max(c[1] for c in loc)
        if h > w:  # книжкові острівці повертаємо, щоб полиці були щільнішими
            loc = [(c[1], w - c[0]) for c in loc]
            w, h = h, w
        wt = weights[poly.material_index] if weights else 1.0
        islands.append((ls, loc, max(w, 1e-3) * wt, max(h, 1e-3) * wt, wt))
    usable = 1.0 - 0.06
    gap = 5.0 / atlas_px
    lo, hi = 1e-4, 1.0
    for _ in range(40):
        sc = (lo + hi) / 2
        x = y = row = 0.0
        ok = True
        for _ls, _loc, w, h, _wt in sorted(islands, key=lambda t: -t[3]):
            ww, hh = w * sc + gap, h * sc + gap
            if x + ww > 1.0:
                x, y, row = 0.0, y + row, 0.0
            row = max(row, hh)
            x += ww
        if y + row > usable:
            ok = False
        lo, hi = (sc, hi) if ok else (lo, sc)
    sc = lo
    x = y = row = 0.0
    for ls, loc, w, h, wt in sorted(islands, key=lambda t: -t[3]):
        ww, hh = w * sc + gap, h * sc + gap
        if x + ww > 1.0:
            x, y, row = 0.0, y + row, 0.0
        row = max(row, hh)
        for l, c in zip(ls, loc):
            uvl.data[l].uv = (x + gap / 2 + c[0] * sc * wt, y + gap / 2 + c[1] * sc * wt)
        x += ww
    for poly in me.polygons:
        if poly.material_index in flat:
            k = flat.index(poly.material_index)
            u0, v0, d = 0.01 + 0.035 * k, 0.975, 0.02
            corners = [(u0, v0), (u0 + d, v0), (u0 + d, v0 + d), (u0, v0 + d)]
            for i, l in enumerate(poly.loop_indices):
                uvl.data[l].uv = corners[i % 4]
    return 100 / (sc * atlas_px)  # см на тексель, ураховуючи метри


def finish(b, name, out_dir, atlas_px=None, tri_limit=None, target_cm=3.2, footprint=(1, 1), anchor=None, density=None):
    """Меш → обʼєкт, UV, запікання атласу, один матеріал, масштаб 1/8, експорт, перевірка."""
    mt = mats()
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    b.bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for s in b.slots:
        me.materials.append(mt[s])
    # центр підошви в початок координат
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    cx, cy = anchor if anchor else ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
    # слід у цілих тайлах: меш має лежати всередині, виступ (завал, апрон) — не більше 0.1 тайла
    lim = (footprint[0] * TILE / 2 + 0.1 * TILE, footprint[1] * TILE / 2 + 0.1 * TILE)
    assert max(abs(min(xs) - cx), abs(max(xs) - cx)) <= lim[0] and max(abs(min(ys) - cy), abs(max(ys) - cy)) <= lim[1], f"{name}: меш виходить за слід {footprint}: x {min(xs)-cx:.1f}..{max(xs)-cx:.1f}, y {min(ys)-cy:.1f}..{max(ys)-cy:.1f}"
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)

    flat = [i for i, s in enumerate(b.slots) if s in FLAT]
    # найменший атлас, що дає щільність не грубішу за target_cm (але не більше 2048)
    for atlas_px in (256, 512, 1024, 2048):
        cm = unwrap(me, flat, atlas_px, [(density or {}).get(sn, 1.0) for sn in b.slots])
        if cm <= target_cm:
            break
    ATLAS[:] = [atlas_px, round(cm, 2)]

    # запікання
    img = bpy.data.images.new("atlas", atlas_px, atlas_px)
    bake_nodes = []
    for m in me.materials:
        nt = m.node_tree
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        nt.nodes.active = n
        bake_nodes.append(n)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=6, margin_type="EXTEND", use_clear=True)
    os.makedirs(out_dir, exist_ok=True)
    jpg = os.path.join(out_dir, name + "_atlas.jpg")
    img.filepath_raw = jpg
    img.file_format = "JPEG"
    sc.render.image_settings.quality = 90
    img.save()
    # карта нормалей (тангентна, OpenGL) із тієї самої процедурної висоти
    nimg = bpy.data.images.new("normal", atlas_px, atlas_px, alpha=False)
    nimg.generated_color = (0.5, 0.5, 1.0, 1.0)
    nimg.colorspace_settings.name = "Non-Color"
    for n in bake_nodes:
        n.image = nimg
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=6, margin_type="EXTEND", use_clear=True)
    if atlas_px <= 1024:
        nimg.filepath_raw = os.path.join(out_dir, name + "_normal.png")
        nimg.file_format = "PNG"
    else:
        nimg.filepath_raw = os.path.join(out_dir, name + "_normal.jpg")
        nimg.file_format = "JPEG"
    nimg.save()

    px = np.array(img.pixels[:]).reshape(-1, 4)[:, :3]
    px = px[px.sum(axis=1) > 0.002]
    lin = np.where(px <= 0.04045, px / 12.92, ((px + 0.055) / 1.055) ** 2.4)
    y = 0.2126 * lin[:, 0] + 0.7152 * lin[:, 1] + 0.0722 * lin[:, 2]
    lstar = np.where(y > 0.008856, 116 * np.cbrt(y) - 16, 903.3 * y)
    mean_l = float(lstar.mean())

    # один матеріал на запеченому атласі
    # запікали в метрах (матеріали тайляться в метрах); тепер метри → тайли
    from mathutils import Matrix
    me.transform(Matrix.Scale(1 / TILE, 4) @ Matrix.Translation((-cx, -cy, -min(zs))))
    me.update()
    me.materials.clear()
    me.uv_layers.remove(me.uv_layers["local"])
    if "wtone" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["wtone"])
    fm = bpy.data.materials.new(name)
    fm.use_nodes = True
    nt = fm.node_tree
    bs = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nimg
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.uv_map = "UVMap"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    bs.inputs["Roughness"].default_value = 0.9
    bs.inputs["Metallic"].default_value = 0.0
    me.materials.append(fm)

    ob["footprint_tiles"] = list(footprint)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    glb = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_materials="EXPORT", export_extras=True, export_image_format="AUTO")
    return verify(glb, tri_limit, mean_l, footprint)


ATLAS = [0, 0]


def verify(path, tri_limit, mean_l, footprint):
    import json
    import struct
    d = open(path, "rb").read()
    off = 12
    g = None
    while off < len(d):
        clen, ctype = struct.unpack_from("<II", d, off)
        if ctype == 0x4E4F534A:
            g = json.loads(d[off + 8:off + 8 + clen])
            break
        off += 8 + clen
    prims = [p for m in g["meshes"] for p in m["primitives"]]
    assert len(prims) == 1, f"{len(prims)} примітивів"
    assert "normalTexture" in g["materials"][prims[0]["material"]], "нема normalTexture"
    acc = g["accessors"]
    p = prims[0]
    lo = acc[p["attributes"]["POSITION"]]["min"]
    hi = acc[p["attributes"]["POSITION"]]["max"]
    tris = acc[p["indices"]]["count"] // 3
    assert abs(lo[1]) < 1e-4, f"y_min={lo[1]}"
    fx, fz = footprint[0] / 2 + 0.1, footprint[1] / 2 + 0.1
    assert -fx <= lo[0] and hi[0] <= fx and -fz <= lo[2] and hi[2] <= fz, "меш поза слідом"
    ex = [n.get("extras") for n in g["nodes"] if n.get("extras")] + [m.get("extras") for m in g["meshes"] if m.get("extras")]
    assert any("footprint_tiles" in e for e in ex), "нема footprint_tiles у extras"
    assert not [n for n in g["nodes"] if {"translation", "rotation", "scale", "matrix"} & n.keys()], "трансформ на вузлі"
    if tri_limit:
        assert tris <= tri_limit, f"{tris} трикутників > {tri_limit}"
    res = dict(file=os.path.basename(path), tris=tris, size_tiles=(round(hi[0] - lo[0], 3), round(hi[1] - lo[1], 3), round(hi[2] - lo[2], 3)),
               verts=acc[p["attributes"]["POSITION"]]["count"], bytes=len(d), mean_L=round(mean_l, 1), atlas=ATLAS[0], cm_texel=ATLAS[1])
    print("RESULT", res)
    return res


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def out_dir():
    return sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(HERE, "out")
