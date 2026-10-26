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
                  base_dirt=0.0, patch=None, rough=0.85, sat=1.0, streak_col=(0.0, 0.0, 0.0), streak_xy=1.3, corr=None, bump=0.006, patch_scale=0.55, runs=None, recolor=None, vmul=False, ash=None, seam_bump=1.0):
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
        elif axis == "zv":
            c = sep.outputs[2]
        elif axis == "ang8":
            # кут навколо найближчої осі бункера (центри кожні 8 м від -12), у метрах дуги
            lx = math("SUBTRACT", math("MODULO", math("ADD", sep.outputs[0], 16.0), 8.0), 4.0)
            c = math("MULTIPLY", math("ARCTAN2", sep.outputs[1], lx), 3.5)
        else:
            c = sep.outputs["XYZ".index(axis.upper())]
        f = math("FRACT", math("DIVIDE", math("ADD", c, 10000.0), period))
        d = math("ABSOLUTE", math("SUBTRACT", f, 0.5))
        line = math("GREATER_THAN", d, 0.5 - width / period)
        if axis == "zv":                                   # лише вертикальні грані: верх стіни не смугується
            nzg = N("ShaderNodeNewGeometry")
            nzs = N("ShaderNodeSeparateXYZ")
            L(nzg.outputs["Normal"], nzs.inputs[0])
            line = math("MULTIPLY", line, math("SUBTRACT", 1.0, math("ABSOLUTE", nzs.outputs[2]), clamp=True))
        base = mix(base, (0.0, 0.0, 0.0), math("MULTIPLY", line, strength), "MIX")
        hparts.append(math("MULTIPLY", line, -0.012 * seam_bump))
    if ash is not None:
        # попіл на кромках: Bevel-нормаль розходиться з гранню лише біля ребра, звідти й світліший колір
        acol, again, arad = ash
        bv = N("ShaderNodeBevel")
        bv.inputs["Radius"].default_value = arad
        bv.samples = 8
        ge = N("ShaderNodeNewGeometry")
        dt = N("ShaderNodeVectorMath")
        dt.operation = "DOT_PRODUCT"
        L(bv.outputs["Normal"], dt.inputs[0])
        L(ge.outputs["Normal"], dt.inputs[1])
        fa = math("MULTIPLY", math("SUBTRACT", 1.0, dt.outputs["Value"], clamp=True), again, clamp=True)
        base = mix(base, acol, fa, "MIX")
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
        "fc_roof_x": make_material("fc_roof_x", "Concrete034", 1.2, (0.18, 0.18, 0.17), seams=[("x", 1.1, 0.05, 0.4)], corr=("x", 0.3, 0.007), streak=0.1, patch=((0.12, 0.16, 0.10), 0.05)),
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
        "brick_face": make_material("brick_face", "Bricks105", 1.0, recolor=(0.58, 0.30, 0.20), streak=0.2, base_dirt=0.5, bump=0.02, patch=((0.09, 0.06, 0.04), 0.2), patch_scale=1.6),
        # руїна: цегла крупніша, ніж у житла, і з виразними шарами кожні 30 см, щоб ряди читались на 12 px/м
        "brick_ruin": make_material("brick_ruin", "Bricks105", 0.55, recolor=(0.309, 0.274, 0.254), streak=0.2, base_dirt=0.5, bump=0.03, patch=((0.07, 0.065, 0.06), 0.2), patch_scale=1.6, seams=[("zv", 0.30, 0.035, 0.55)]),
        "tile_graphite": make_material("tile_graphite", "CorrugatedSteel005", 1.0, (0.20, 0.21, 0.22), seams=[("y", 0.35, 0.05, 0.7), ("x", 1.1, 0.05, 0.4)], corr=("y", 0.35, 0.035), streak=0.1),
        "tile_brown": make_material("tile_brown", "CorrugatedSteel005", 1.0, (0.28, 0.20, 0.16), seams=[("y", 0.35, 0.05, 0.7), ("x", 1.1, 0.05, 0.4)], corr=("y", 0.35, 0.035), streak=0.1),
        "tin_green": make_material("tin_green", "CorrugatedSteel005", 1.0, (0.33, 0.37, 0.34), seams=[("x", 1.0, 0.05, 0.5)], corr=("x", 0.2, 0.035), streak=0.08),
        "tin_ochre": make_material("tin_ochre", "CorrugatedSteel005", 1.0, (0.55, 0.46, 0.32), seams=[("x", 1.0, 0.05, 0.45)], corr=("x", 0.2, 0.018), streak=0.08),
        "step": make_material("step", "Concrete034", 1.0, (0.50, 0.49, 0.46), streak=0.4, base_dirt=0.5),
        "gutter": make_material("gutter", flat=(0.30, 0.31, 0.31)),
        "rebar": make_material("rebar", flat=(0.11, 0.06, 0.04)),
        "soot": make_material("soot", flat=(0.045, 0.04, 0.036)),
        "clad_vc": make_material("clad_vc", "CorrugatedSteel005", 1.0, (0.46, 0.40, 0.34), seams=[("zv", 0.5, 0.04, 0.3)], corr=("h", 0.2, 0.008), streak=1.0, base_dirt=0.5, patch=((0.18, 0.09, 0.05), 0.25), vmul=True),
        "boards_ruin": make_material("boards_ruin", "Planks021", 1.0, (0.30, 0.27, 0.24), sat=0.35, seams=[("h", 0.2, 0.02, 0.8)], streak=1.0, base_dirt=0.5, bump=0.02),
        "panel_in": make_material("panel_in", flat=(0.30, 0.29, 0.27)),
        "panel_frag": make_material("panel_frag", "Concrete034", 1.2, (0.43, 0.41, 0.38), streak=0.4, base_dirt=0.5, bump=0.02),
        # напівруїни: ті самі світлі штукатурка, цегла й сірі дахи, що в цілих будинків; кіптява й руйнування зверху
        "wall_half": make_material("wall_half", "Plaster001", 2.5, (0.66, 0.62, 0.55), streak=0.35, base_dirt=0.5, bump=0.004, patch=((0.40, 0.21, 0.14), 0.22), patch_scale=1.0, vmul=True),
        "wall_half_d": make_material("wall_half_d", "Plaster001", 2.5, (0.46, 0.43, 0.38), streak=0.4, base_dirt=0.5, bump=0.004, patch=((0.30, 0.15, 0.10), 0.22), patch_scale=1.0, vmul=True),
        "boards_vc": make_material("boards_vc", "Planks021", 1.0, (0.50, 0.45, 0.38), sat=0.35, seams=[("h", 0.2, 0.02, 0.85)], streak=1.0, base_dirt=0.5, bump=0.02, vmul=True),
        # дошки 18 см: м'які зміни тону без крупи (плоский колір, вертикальні шви, низькочастотні розводи)
        "boards_soft": make_material("boards_soft", flat=(0.36, 0.325, 0.28), seams=[("h", 0.18, 0.02, 0.4)], streak=0.5, base_dirt=0.4, seam_bump=0.0),
        "tile_small": make_material("tile_small", flat=(0.17, 0.18, 0.20), seams=[("y", 0.26, 0.04, 0.75), ("x", 0.30, 0.03, 0.4)], streak=0.15, seam_bump=0.0),
        "gutter_d": make_material("gutter_d", flat=(0.14, 0.145, 0.15), streak=0.3),
        "plinth_flat": make_material("plinth_flat", flat=(0.33, 0.32, 0.30), base_dirt=0.5, streak=0.4),
        "door_panel": make_material("door_panel", flat=(0.30, 0.22, 0.15), seams=[("h", 0.22, 0.015, 0.5)], streak=0.3, seam_bump=0.0),
        "mud_skirt": make_material("mud_skirt", flat=(0.10, 0.082, 0.065), streak=0.6, base_dirt=0.2),
        "boards_soft_vc": make_material("boards_soft_vc", flat=(0.36, 0.325, 0.28), seams=[("h", 0.18, 0.02, 0.4)], streak=0.5, base_dirt=0.4, vmul=True, seam_bump=0.0),
        "galv_rim": make_material("galv_rim", "CorrugatedSteel005", 1.0, (0.30, 0.29, 0.28), seams=[("ang8", 1.1, 0.04, 0.3)], streak=0.9, base_dirt=0.4, patch=((0.16, 0.08, 0.05), 0.3)),
        "sheet_char": make_material("sheet_char", "CorrugatedSteel005", 1.0, (0.34, 0.31, 0.28), streak=0.8, base_dirt=0.3, patch=((0.22, 0.11, 0.06), 0.3)),
        "floor_char": make_material("floor_char", "Planks021", 1.0, (0.17, 0.145, 0.125), sat=0.4, seams=[("h", 0.2, 0.02, 0.8)], streak=0.6, base_dirt=0.3, bump=0.025),
        "heap_base_buff": make_material("heap_base_buff", flat=(0.2, 0.165, 0.13)),
        "panel_light": make_material("panel_light", "Concrete034", 1.2, (0.26, 0.255, 0.25), streak=0.1, base_dirt=0.2),
        "rubble": make_rubble_material("rubble", [(0.30, (0.09, 0.05, 0.032)), (0.46, (0.115, 0.07, 0.044)), (0.66, (0.125, 0.104, 0.074)), (0.82, (0.08, 0.074, 0.06)), (0.95, (0.036, 0.03, 0.024)), (1.01, (0.21, 0.18, 0.10))]),
        "heap": make_rubble_material("heap", [(0.34, (0.09, 0.05, 0.032)), (0.50, (0.115, 0.07, 0.044)), (0.68, (0.125, 0.104, 0.074)), (0.86, (0.08, 0.074, 0.06)), (1.01, (0.036, 0.03, 0.024))]),
        "rubble_steel": make_rubble_material("rubble_steel", [(0.35, (0.05, 0.05, 0.05)), (0.6, (0.12, 0.13, 0.13)), (0.75, (0.15, 0.115, 0.095)), (0.9, (0.14, 0.14, 0.14)), (1.01, (0.24, 0.22, 0.15))], 3.0),
        "soot_v": make_soot_material(),
        # ребра шиферу — в альбедо (смуги 0.4 м згладжуються міпами), а рельєф нормалі ледь помітний: на ковзному світлі не мигає
        "fc_roof_burnt": make_material("fc_roof_burnt", "Concrete034", 1.2, (0.07, 0.07, 0.07), seams=[("x", 1.1, 0.05, 0.3), ("x", 0.4, 0.09, 0.14)], corr=("x", 0.4, 0.005), streak=1.0),
        # дахи малих будинків: плоский колір (без крупи текстури), шви листів кожні 0.5 м, черепиця 0.30 x 0.30 м
        "fc_roof_xh": make_material("fc_roof_xh", flat=(0.15, 0.155, 0.16), seams=[("x", 0.5, 0.03, 0.4)], streak=0.15, seam_bump=0.0),
        "fc_roof_h": make_material("fc_roof_h", flat=(0.32, 0.325, 0.31), seams=[("y", 0.5, 0.03, 0.3)], streak=0.15, seam_bump=0.0),
        "blown_dark": make_material("blown_dark", flat=(0.09, 0.09, 0.095)),
        "tin_red": make_material("tin_red", "CorrugatedSteel005", 1.0, (0.34, 0.25, 0.21), seams=[("x", 1.0, 0.05, 0.4)], corr=("x", 0.2, 0.03), streak=0.3, patch=((0.2, 0.12, 0.08), 0.3)),
        # обвуглена деревина: майже чорна, а попіл світлим сірим лише на кромках
        "timber_dark": make_material("timber_dark", "Planks021", 1.0, (0.026, 0.021, 0.018), sat=0.5, streak=0.5, base_dirt=0.2, bump=0.02, ash=((0.22, 0.215, 0.205), 3.5, 0.03)),
        "cavity": make_material("cavity", flat=(0.05, 0.049, 0.048)),
        "insul": make_material("insul", flat=(0.21, 0.21, 0.175)),
        "pump": make_material("pump", flat=(0.022, 0.026, 0.03)),
        "wall_ruin": make_material("wall_ruin", "Bricks105", 0.55, recolor=(0.320, 0.278, 0.259), streak=0.35, base_dirt=0.5, bump=0.035, patch=((0.17, 0.16, 0.145), 0.3), patch_scale=1.1, vmul=True, seams=[("zv", 0.30, 0.035, 0.55)]),
        "panel_vc": make_material("panel_vc", "Concrete034", 1.2, (0.56, 0.54, 0.50), seams=[("h", 3.0, 0.04, 0.55), ("z", 3.1, 0.05, 0.5)], streak=0.3, base_dirt=0.5, vmul=True),
        # джерело запікання купи: темна основа, а уламки 20-50 см на ній світліші, тож щілини між ними читаються як шви
        "heap_base": make_material("heap_base", flat=(0.06, 0.044, 0.034)),
        "heap_buff": make_rubble_material("heap_buff", [(0.30, (0.46, 0.23, 0.13)), (0.50, (0.52, 0.31, 0.19)), (0.68, (0.64, 0.57, 0.46)), (0.84, (0.78, 0.76, 0.69)), (0.94, (0.20, 0.17, 0.14)), (1.01, (0.49, 0.41, 0.30))]),
        "rubble_buff": make_rubble_material("rubble_buff", [(0.30, (0.46, 0.23, 0.13)), (0.50, (0.52, 0.31, 0.19)), (0.68, (0.64, 0.57, 0.46)), (0.84, (0.78, 0.76, 0.69)), (0.94, (0.20, 0.17, 0.14)), (1.01, (0.49, 0.41, 0.30))]),
        "heap_base_grey": make_material("heap_base_grey", flat=(0.055, 0.048, 0.042)),
        "rubble_hi": make_rubble_material("rubble_hi", [(0.34, (0.15, 0.07, 0.04)), (0.52, (0.16, 0.09, 0.055)), (0.68, (0.15, 0.12, 0.09)), (0.84, (0.095, 0.088, 0.075)), (0.95, (0.045, 0.036, 0.03)), (1.01, (0.22, 0.19, 0.11))]),
        "heap_grey": make_rubble_material("heap_grey", [(0.62, (0.17, 0.165, 0.15)), (0.80, (0.20, 0.18, 0.155)), (0.92, (0.12, 0.095, 0.075)), (1.01, (0.07, 0.065, 0.058))]),
        "pump_light": make_material("pump_light", flat=(0.12, 0.13, 0.14)),
        "cavity_black": make_material("cavity_black", flat=(0.003, 0.003, 0.003)),
        "pv_frame": make_material("pv_frame", flat=(0.10, 0.10, 0.105)),
        "brick_dark": make_material("brick_dark", "Bricks105", 1.0, recolor=(0.36, 0.28, 0.24), streak=0.5, base_dirt=0.6, bump=0.02),
        "slab_dark": make_material("slab_dark", "Concrete034", 1.2, (0.30, 0.285, 0.265), streak=0.3, base_dirt=0.5, bump=0.035, patch=((0.07, 0.065, 0.06), 0.25), ash=((0.46, 0.44, 0.40), 2.5, 0.05)),
        "heap_house": make_rubble_material("heap_house", [(0.40, (0.24, 0.216, 0.176)), (0.70, (0.095, 0.05, 0.032)), (0.88, (0.08, 0.074, 0.06)), (1.01, (0.036, 0.03, 0.024))]),
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


def mound_radius(seed, tongues=0):
    """Нормований радіус контуру купи за кутом (той самий, що в mound): 6-8 опуклостей без довгих прямих."""
    import random
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(4)]
    tong = [(rnd.uniform(0, 6.28), rnd.uniform(0.15, 0.3)) for _ in range(tongues)]

    def radius(a):
        r = 1.0 + 0.2 * math.sin(3 * a + ph[0]) + 0.13 * math.sin(5 * a + ph[1]) + 0.14 * math.sin(7 * a + ph[2]) + 0.05 * math.sin(11 * a + ph[3])
        for (ta, tw) in tong:
            d = abs((a - ta + math.pi) % (2 * math.pi) - math.pi)
            r += tw * max(0.0, 1 - d / 0.7)
        return min(1.45, max(0.6, r))
    return radius, ph


def mound(b, cx, cy, rx, ry, hmax, seed, mat="heap", rings=6, segs=20, z0=0.0, tongues=0, lump=0.45, jitter=0.0):
    """Низька широка купа одним замкненим мешем: косинусний профіль із заокругленим гребенем, лобастий контур,
    детермінований рельєф (низька й висока деталізація мають однаковий силует); jitter — лише для високого джерела запікання.
    Центр — одна вершина: кільце t=0 мало різні висоти в одній точці й давало голку над купою."""
    import random
    radius, ph = mound_radius(seed, tongues)
    jr = random.Random(seed * 7 + 1)
    kk = 2 * math.pi / 1.75
    apex = b.bm.verts.new((cx, cy, z0 + hmax + lump * math.sin(kk * cx + ph[0]) * math.sin(kk * cy + ph[1])))
    ring = [[apex] * segs]
    for k in range(1, rings + 1):
        t = k / rings
        row = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            r = t * radius(a)
            px, py = cx + rx * r * math.cos(a), cy + ry * r * math.sin(a)
            if k < rings:
                noise = 1.0 + (0.1 * math.sin(2 * a + ph[2] + 3 * t) + 0.08 * math.sin(5 * a + ph[3] - 4 * t) + 0.06 * math.sin(9 * a + ph[0] + 6 * t)) * min(1.0, t * 3) + (jr.uniform(-jitter, jitter) if jitter else 0.0)
                z = z0 + hmax * 0.5 * (1 + math.cos(math.pi * min(1.0, t))) * noise
                if lump:
                    z += lump * math.sin(kk * px + ph[0]) * math.sin(kk * py + ph[1]) * (1 - t)
            else:
                z = z0 - 0.12
            row.append(b.bm.verts.new((px, py, max(z0 - 0.12, z))))
        ring.append(row)
    fs = []
    for i in range(segs):
        j = (i + 1) % segs
        fs.append(b.bm.faces.new((ring[1][i], ring[1][j], apex)))
        for k in range(1, rings):
            fs.append(b.bm.faces.new((ring[k][i], ring[k + 1][i], ring[k + 1][j], ring[k][j])))
    b._finish(fs, mat)


class HeapSurface:
    """Поверхня купи: парабола від гребеня до губи висотою lip (так край ніколи не тонший за губу), 5-7 опуклостей
    контуру з розмахом 0.3-0.6 м і м'які хвилі, що гаснуть у центрі (без радіальних зломів на вершині).
    z(x, y) дає ту саму висоту, що й меш, тож крокви й димар стоять на справжній поверхні."""

    def __init__(self, cx, cy, rx, ry, hmax, seed, bumps=6, lip=0.3, wob=0.2, lump=0.14, hummocks=0, hum_amp=0.35, pw=2.0, sq=0.0):
        import random
        rnd = random.Random(seed)
        self.cx, self.cy, self.rx, self.ry = cx, cy, rx, ry
        self.hmax, self.bumps, self.lip, self.wob, self.lump, self.pw, self.sq = hmax, bumps, lip, wob, lump, pw, sq
        self.ph = [rnd.uniform(0, 2 * math.pi) for _ in range(6)]
        # горби й одна западина (де був будинок): гауси 1-1.6 м, щоб купа читалась як звал, а не як диск
        self.hum = []
        for k in range(hummocks):
            ang, rr = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, 0.62)
            amp = rnd.uniform(0.5, 1.0) * hum_amp * (-0.4 if k == 0 else 1.0)
            self.hum.append((cx + rx * rr * math.cos(ang), cy + ry * rr * math.sin(ang), rnd.uniform(0.9, 1.6), amp))
        self.s = 1.0

    def fit_peak(self, target):
        """Масштабує рельєф над губою так, щоб найвища точка була рівно target (горби не складаються понад задум)."""
        self.s = 1.0
        peak = max(self.z(self.cx + self.rx * u / 20.0, self.cy + self.ry * v / 20.0) for u in range(-20, 21) for v in range(-20, 21))
        self.s = (target - self.lip) / max(1e-3, peak - self.lip)

    def radius(self, a):
        ph, k = self.ph, self.bumps
        r = 1.0 + 0.065 * math.sin(k * a + ph[0]) + 0.03 * math.sin((k - 1) * a + ph[1]) + 0.025 * math.sin((k + 1) * a + ph[2])
        if self.sq:                                                      # суперелліпс: купа тримає квадратний слід будинку, а не круглий диск
            r *= (abs(math.cos(a)) ** self.sq + abs(math.sin(a)) ** self.sq) ** (-1.0 / self.sq)
        return r

    def z(self, x, y):
        u, v = (x - self.cx) / self.rx, (y - self.cy) / self.ry
        a = math.atan2(v, u)
        t = math.hypot(u, v) / self.radius(a)
        if t >= 1.0:
            return 0.0
        return self._z(x, y, a, t)

    def _z(self, x, y, a, t):
        ph = self.ph
        e = 1.0 - t * t
        f = min(1.0, t / 0.35)
        f = f * f * (3 - 2 * f)
        z = (self.hmax - self.lip) * (1.0 - t ** self.pw)
        z += self.wob * e * f * (0.6 * math.sin(2 * a + ph[3] + 3 * t) + 0.4 * math.sin(5 * a + ph[4] - 4 * t))
        kk = 2 * math.pi / 1.9
        z += self.lump * e * math.sin(kk * x + ph[5]) * math.sin(kk * y + ph[0])
        for (hx, hy, sg, am) in self.hum:
            z += am * e * math.exp(-((x - hx) ** 2 + (y - hy) ** 2) / (2 * sg * sg))
        return self.lip + max(-0.1, z) * self.s


def heap_mound(b, hs, mat="heap", rings=6, segs=36, jitter=0.0, seed=0, skirt=1.0, skirt_mat=None):
    """Меш купи за HeapSurface: кільця до губи (t=1, висота lip) і три кільця заокругленої губи, що опускаються під землю
    за 0.5 м; центр — одна грань-шапка, не віяло. jitter — адитивний шум лише для високого джерела запікання. Повертає найвищу вершину."""
    import random
    jr = random.Random(seed * 7 + 3)
    lip = hs.lip
    rm = 0.5 * (hs.rx + hs.ry)
    rim = [(0.0, lip), (0.22 * skirt / rm, 0.78 * lip), (0.40 * skirt / rm, 0.38 * lip), (0.52 * skirt / rm, -0.12)]
    ring = []
    top = 0.0
    for k in range(1, rings + 1):
        row = []
        t = k / rings
        for i in range(segs):
            a = 2 * math.pi * i / segs
            r = t * hs.radius(a)
            px, py = hs.cx + hs.rx * r * math.cos(a), hs.cy + hs.ry * r * math.sin(a)
            z = hs._z(px, py, a, t) + (jr.uniform(-jitter, jitter) * (1 - t * t) * min(1.0, t * 6.0) if jitter else 0.0)   # біля центру клини вузькі: шум менший за їхню ширину, інакше виходить зірка гострих гребенів
            row.append(b.bm.verts.new((px, py, z)))
            top = max(top, z)
        ring.append(row)
    for dt, zr in rim[1:]:
        row = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            r = hs.radius(a) * (1.0 + dt)
            px, py = hs.cx + hs.rx * r * math.cos(a), hs.cy + hs.ry * r * math.sin(a)
            row.append(b.bm.verts.new((px, py, zr + (jr.uniform(-jitter, jitter) * 0.3 if jitter and zr > 0 else 0.0))))
        ring.append(row)
    fs = [b.bm.faces.new(ring[0])]                                  # центральна шапка однією гранню: без віяла тонких клинів, у яких розгортка давала шви й чорну пляму
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(len(ring) - 1):
            f_ = b.bm.faces.new((ring[k][i], ring[k + 1][i], ring[k + 1][j], ring[k][j]))
            if skirt_mat and k >= rings - 1:                      # круті боки губи проєкція зверху розтягує в смуги: вони мають власний процедурний матеріал
                b._finish([f_], skirt_mat)
            else:
                fs.append(f_)
    b._finish(fs, mat)
    return top


def wall_run(b, p0, p1, thick, heights, mat, top_mat, seed=0, pitch=1.0, soot_h=1.5, top_tone=0.8, inner_tone=0.9, brick_mat="brick_ruin", hcap=3.2, jag=1.0, cap=0.4, step=1.0, diag_p=0.35, jit=1.0):
    """Уламок стіни p0-p1: сегменти різної ширини, кожен ламається ще на 1-3 шматки з різними верхами (різниця 0.2-0.5 м,
    тож жодного рівного верху), випадкова ходьба висот довкола задуму heights (не вище hcap); верхні 0.4 м — відкрита
    цегла. Торці між сусідніми шматками малюються лише там, де один вищий за другий."""
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
    pieces = []                                   # (x0, x1, h0, h1) вздовж стіни; висота 0 — пролом
    h = None
    for i in range(len(cuts) - 1):
        t = (cuts[i] + cuts[i + 1]) / 2 / ln
        hb = hat(t)
        if hb <= 0.05:
            pieces.append((cuts[i], cuts[i + 1], 0.0, 0.0))
            h = None
            continue
        h = hb if h is None else max(0.3, min(hb + 0.5, min(hcap, h + jag * step * rnd.choice((-0.6, -0.4, -0.2, 0.2, 0.35, 0.6, -1.0, 0.9)))))
        diag = jag * (rnd.uniform(0.4, 1.1) * (0.5 + 0.5 * step) * rnd.choice((-1, 1)) if rnd.random() < diag_p else rnd.uniform(-0.1, 0.1))
        ha, hc = max(0.2, h - diag / 2), max(0.2, h + diag / 2)
        w = cuts[i + 1] - cuts[i]
        nsub = 1 if w < 0.55 else (2 if w < 1.0 else rnd.choice((2, 3)))
        fr = [k / nsub for k in range(nsub + 1)]
        for k in range(nsub):
            def hh(f, edge):
                z = ha + (hc - ha) * f
                if edge:                          # зазубрина кожного шматка 0.1-0.25 м вгору чи вниз, разом 0.2-0.5 м
                    z += jag * jit * rnd.choice((-1, 1)) * rnd.uniform(0.06, 0.25)
                return max(0.2, min(hcap, z))
            pieces.append((cuts[i] + w * fr[k], cuts[i] + w * fr[k + 1], hh(fr[k], True), hh(fr[k + 1], True)))

    def quad(pts, tones, m):
        f = b.poly([tuple(q) for q in pts], m)
        for lp, t in zip(f.loops, tones):
            lp[b.wtone] = (t, t, t, 1.0)

    def V(q, z):
        return Vector((q.x, q.y, z))

    for i, (xa, xc, ha, hc) in enumerate(pieces):
        if ha <= 0.05 and hc <= 0.05:
            continue
        a = Vector((p0[0], p0[1], 0)) + u * xa
        c = Vector((p0[0], p0[1], 0)) + u * xc
        pb = [a + nrm, c + nrm, c - nrm, a - nrm]
        br_a, br_c = max(0.0, ha - cap), max(0.0, hc - cap)
        lo_a, lo_c = max(0.0, br_a - soot_h), max(0.0, br_c - soot_h)
        for (q0, q1, tn) in ((pb[0], pb[1], 1.0), (pb[2], pb[3], inner_tone)):
            flip = q0 is pb[2]
            ah, ch = (hc, ha) if flip else (ha, hc)
            ba, bc = (br_c, br_a) if flip else (br_a, br_c)
            la, lc = (lo_c, lo_a) if flip else (lo_a, lo_c)
            quad([V(q0, 0), V(q1, 0), V(q1, lc), V(q0, la)], (tn,) * 4, mat)
            quad([V(q0, la), V(q1, lc), V(q1, bc), V(q0, ba)], (tn, tn, tn * top_tone, tn * top_tone), mat)
            b.poly([tuple(q) for q in (V(q0, ba), V(q1, bc), V(q1, ch), V(q0, ah))], brick_mat)
        b.poly([tuple(q) for q in (V(pb[0], ha), V(pb[1], hc), V(pb[2], hc), V(pb[3], ha))], brick_mat)
        prev = pieces[i - 1] if i > 0 and pieces[i - 1][1] >= xa - 1e-6 and pieces[i - 1][3] > 0.05 else None
        nxt = pieces[i + 1] if i + 1 < len(pieces) and pieces[i + 1][0] <= xc + 1e-6 and pieces[i + 1][2] > 0.05 else None
        lo_end = min(hc, nxt[2]) if nxt else 0.0
        lo_start = min(ha, prev[3]) if prev else 0.0
        if hc - lo_end > 0.02:
            b.poly([tuple(q) for q in (V(pb[1], lo_end), V(pb[2], lo_end), V(pb[2], hc), V(pb[1], hc))], brick_mat)
        if ha - lo_start > 0.02:
            b.poly([tuple(q) for q in (V(pb[3], lo_start), V(pb[0], lo_start), V(pb[0], ha), V(pb[3], ha))], brick_mat)


def prism(b, prof, thick, origin, yaw, lean, mat, top_mat=None, in_mat=None, inner=(0.0, 0.0)):
    """Призма з довільним профілем у площині стіни: prof — точки (u, z) проти годинникової, вісь u уздовж стіни, товщина по нормалі,
    lean — нахил від виска. Верхні грані — top_mat, грань, що дивиться в бік inner, — in_mat, решта — mat."""
    n = len(prof)
    cy_, sy_ = math.cos(yaw), math.sin(yaw)
    cl, sl = math.cos(lean), math.sin(lean)

    def T(u, z, d):
        nn, zz = d * cl - z * sl, d * sl + z * cl
        return Vector((origin[0] + u * cy_ - nn * sy_, origin[1] + u * sy_ + nn * cy_, origin[2] + zz))
    fr = [b.bm.verts.new(T(u, z, thick / 2)) for (u, z) in prof]
    bk = [b.bm.verts.new(T(u, z, -thick / 2)) for (u, z) in prof]
    cen = sum((v.co for v in fr + bk), Vector()) / (2 * n)
    faces = [b.bm.faces.new(fr), b.bm.faces.new(bk[::-1])]
    for i in range(n):
        j = (i + 1) % n
        faces.append(b.bm.faces.new((fr[i], bk[i], bk[j], fr[j])))
    iv = Vector((inner[0], inner[1], 0.0))
    for f in faces:
        vs = [v.co for v in f.verts]
        nrm = Vector()
        for k in range(len(vs)):
            a, c = vs[k], vs[(k + 1) % len(vs)]
            nrm += Vector(((a.y - c.y) * (a.z + c.z), (a.z - c.z) * (a.x + c.x), (a.x - c.x) * (a.y + c.y)))
        if nrm.length < 1e-9:
            b._finish([f], mat)
            continue
        nrm.normalize()
        fc = sum(vs, Vector()) / len(vs)
        if nrm.dot(fc - cen) < 0:
            nrm = -nrm
        if nrm.z > 0.5 and top_mat:
            b._finish([f], top_mat)
        elif in_mat and iv.length > 0 and nrm.dot(iv) > 0.7:
            b._finish([f], in_mat)
        else:
            b._finish([f], mat)


def panel_wall(b, p0, p1, thick, heights, mat, seed=0, piece=3.0, tilt=0.05, inner=(0.0, 1.0), lips=(), wall_tone=0.5, in_mat=None):
    """Збірна стіна з панелей по piece м: кожна ламається на 2-3 шматки з косим, зламаним у вершині верхом (східцями вниз в один
    бік, без рівних квадратних вирізів), легке відхилення від виска, губи плит перекриттів на лініях поверхів, кіптява вгору по
    зовнішньому боці. Внутрішня грань світліша (in_mat), щоб затінена внутрішність не чорніла. Повертає точки, де вкорінені стрижні."""
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
        f1 = rnd.uniform(0.28, 0.45)
        f2 = rnd.uniform(0.25, 0.4)
        fr = [f1, f2, max(0.15, 1.0 - f1 - f2)]
        d1 = rnd.uniform(0.3, 0.9)
        d2 = d1 + rnd.uniform(0.3, 1.0)
        drops = (0.0, d1, d2) if rnd.random() < 0.5 else (d2, d1, 0.0)           # східці тільки в один бік уздовж панелі
        offs = 0.0
        for k in range(3):
            ww = w * fr[k]
            off = -w / 2 + offs + ww / 2
            offs += ww
            hh = max(0.6, h - drops[k])
            slope = rnd.uniform(-0.9, 0.9)                                         # косий верх 0.3-0.9 м упоперек шматка
            hl, hr = max(0.35, hh + slope / 2), max(0.35, hh - slope / 2)
            hm = (hl + hr) / 2 + rnd.uniform(0.05, 0.3)                            # злам угору посередині: контур не «столик»
            mu = rnd.uniform(-0.2, 0.2) * ww
            prof = [(-ww / 2, 0.0), (ww / 2, 0.0), (ww / 2, hr), (mu, hm), (-ww / 2, hl)]
            px, py = cx + u.x * off, cy + u.y * off
            prism(b, prof, thick, (px, py, 0.0), yaw + rnd.uniform(-0.06, 0.06), tl + rnd.uniform(-0.05, 0.05), mat, top_mat=mat, in_mat=in_mat, inner=inner)
            roots.append((px + u.x * ww * rnd.uniform(-0.3, 0.3), py + u.y * ww * rnd.uniform(-0.3, 0.3), hm))
            # кіптява зовні: темніше вгорі, м'яко згасає донизу (тон відносно тла стіни wall_tone); верх слідує косому верху шматка
            sx, sy = px + outer.x * (thick / 2 + 0.02), py + outer.y * (thick / 2 + 0.02)
            q = [(sx - u.x * ww / 2, sy - u.y * ww / 2, max(0.1, hl - 2.4)), (sx + u.x * ww / 2, sy + u.y * ww / 2, max(0.1, hr - 2.4)),
                 (sx + u.x * ww / 2, sy + u.y * ww / 2, hr), (sx - u.x * ww / 2, sy - u.y * ww / 2, hl)]
            nn = (Vector(q[1]) - Vector(q[0])).cross(Vector(q[2]) - Vector(q[1]))
            tones = (wall_tone, wall_tone, wall_tone * 0.6, wall_tone * 0.6)           # вершинний тон читається як sRGB: 0.5 ≈ тон панелі, 0.3 — помітно темніше, але не чорне
            if nn.dot(outer) < 0:
                q, tones = q[::-1], tones[::-1]
            b.soot(q, tones, 1)
        for lz in lips:
            if lz < h - 0.4:
                lx, ly = cx + inner[0] * 0.55, cy + inner[1] * 0.55
                b.box_e(lx, ly, lz, w * rnd.uniform(0.6, 0.95), 1.1, 0.2, mat, euler=(0, 0, yaw + rnd.uniform(-0.05, 0.05)), top=mat)
    return roots


def chip_slab(b, cx, cy, cz, sx, sy, th, euler, mat, top, seed, rebar=3, per_edge=3):
    """Плита з відколотими краями: контур — прямокутник, вершини й середини сторін зсунуті всередину на 0-0.5 м (відкушені кути,
    виломи), а не гострі прямі ребра; з відколів стирчать уламки арматури. Повертає кінці стрижнів."""
    import random
    from mathutils import Euler
    rnd = random.Random(seed)
    cs = [(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)]
    pts = []
    for i in range(4):
        a, c = cs[i], cs[(i + 1) % 4]
        for k in range(per_edge):
            t = k / per_edge if k == 0 else (k + rnd.uniform(-0.25, 0.25)) / per_edge
            p = (a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t)
            depth = rnd.uniform(0.0, 0.18) if k == 0 else (rnd.uniform(0.1, 0.5) if rnd.random() < 0.5 else rnd.uniform(0.0, 0.15))
            ln_ = math.hypot(p[0], p[1])
            pts.append((p[0] - p[0] / ln_ * depth, p[1] - p[1] / ln_ * depth))
    rot = Euler(euler).to_matrix()
    top_v = [b.bm.verts.new(Vector(rot @ Vector((x, y, th / 2))) + Vector((cx, cy, cz))) for (x, y) in pts]
    bot_v = [b.bm.verts.new(Vector(rot @ Vector((x, y, -th / 2))) + Vector((cx, cy, cz))) for (x, y) in pts]
    n = len(pts)
    ft = b.bm.faces.new(top_v)
    fb = b.bm.faces.new(bot_v[::-1])
    sides = [b.bm.faces.new((top_v[i], bot_v[i], bot_v[(i + 1) % n], top_v[(i + 1) % n])) for i in range(n)]
    b._finish([ft], top)
    b._finish([fb] + sides, mat)
    ends = []
    for k in range(rebar):
        i = rnd.randrange(n)
        x, y = pts[i]
        ln_ = math.hypot(x, y)
        dx, dy = x / ln_, y / ln_
        p0 = Vector(rot @ Vector((x, y, 0.0))) + Vector((cx, cy, cz))
        p1 = Vector(rot @ Vector((x + dx * rnd.uniform(0.4, 0.9), y + dy * rnd.uniform(0.4, 0.9), rnd.uniform(0.0, 0.3)))) + Vector((cx, cy, cz))
        b.beam(p0, p1, 0.05, "rebar")
        ends.append(p1)
    return ends


def burn_ring(b, axis, c, u, z, w, h, sgn, g_side=0.65, g_bot=0.3, g_top=1.1, t_in=0.045, t_out=0.145, ztop=None):
    """Кіптява навколо прорізу: темніша за стіну (≈0.45 її тону), м'яко згасає назовні, найсильніша над прорізом.
    axis 'y': стіна з нормаллю по Y на y=c, u — координата по X; axis 'x': нормаль по X."""
    e = 0.02 * sgn
    def P(du, zz):
        return (u + du, c + e, zz) if axis == "y" else (c + e, u + du, zz)
    hw = w / 2
    inner = [(-hw, z), (hw, z), (hw, z + h), (-hw, z + h)]
    zt = (lambda v: min(v, ztop)) if ztop else (lambda v: v)                    # кіптява не виходить над верх стіни: інакше висить плитою над дахом
    outer = [(-hw - g_side, z - g_bot), (hw + g_side, z - g_bot), (hw + g_side * 0.7, zt(z + h + g_top)), (-hw - g_side * 0.7, zt(z + h + g_top))]
    outn = Vector((0, sgn, 0)) if axis == "y" else Vector((sgn, 0, 0))
    for i in range(4):
        j = (i + 1) % 4
        pts = [P(*inner[i]), P(*inner[j]), P(*outer[j]), P(*outer[i])]
        n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        tones = (t_in, t_in, t_out, t_out)
        if n.dot(outn) < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)


def opening(b, axis, c, u, z, w, h, sgn, k=None):
    """Вибитий проріз вікна: опалена рамка (відкіс) ~0.1 м, всередині градієнт ~(35..45) sRGB, над перемичкою
    кіптява, що згасає на 0.3-0.5 м. axis 'y': стіна з нормаллю по Y на y=c; axis 'x': нормаль по X."""
    e = 0.025 * sgn
    outn = Vector((0, sgn, 0)) if axis == "y" else Vector((sgn, 0, 0))

    def P(du, zz, off=0.0):
        return (u + du, c + e + off * sgn, zz) if axis == "y" else (c + e + off * sgn, u + du, zz)

    def face(pts, tones):
        n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        if n.dot(outn) < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)
    hw = w / 2
    r = 0.1
    inner = [(-hw + r, z + r), (hw - r, z + r), (hw - r, z + h - r), (-hw + r, z + h - r)]
    outer = [(-hw, z), (hw, z), (hw, z + h), (-hw, z + h)]
    k_ = k if k else (11.0 if axis == "x" else 4.5)                                    # торець у тіні: піднімаємо тон, щоб проріз читався
    face([P(*inner[0], 0.01), P(*inner[1], 0.01), P(*inner[2], 0.01), P(*inner[3], 0.01)], (0.06 * k_, 0.06 * k_, 0.03 * k_, 0.03 * k_))
    for i in range(4):
        j = (i + 1) % 4
        face([P(*outer[i]), P(*outer[j]), P(*inner[j], 0.005), P(*inner[i], 0.005)], (0.07, 0.07, 0.05, 0.05))
    # кіптява над перемичкою 0.4 м, ширша за проріз
    face([P(-hw - 0.15, z + h), P(hw + 0.15, z + h), P(hw + 0.05, z + h + 0.45), P(-hw - 0.05, z + h + 0.45)], (0.06, 0.06, 0.145, 0.145))


def opening2(b, axis, c, u, z, w, h, sgn, floor=True, ztop=None, streak=0.9):
    """Проріз із глибиною: підлога (світліша смуга знизу), задня стіна (темна), освітлений відкіс збоку, підвіконня, уламок рамки
    й кіптява над перемичкою. Грані лежать у площині стіни: глибину дають тони, а не діра в меші. axis 'y': нормаль по Y, 'x': по X."""
    e = 0.025 * sgn
    outn = Vector((0, sgn, 0)) if axis == "y" else Vector((sgn, 0, 0))

    def P(du, zz, off=0.0):
        return (u + du, c + e + off * sgn, zz) if axis == "y" else (c + e + off * sgn, u + du, zz)

    def face(pts, tones):
        n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[1]))
        if n.dot(outn) < 0:
            pts, tones = pts[::-1], tones[::-1]
        b.soot(pts, tones, 1)
    hw = w / 2
    fh = min(0.4, h * 0.25) if floor else 0.0
    # задня стіна: темніша вгорі, трохи світліша біля підлоги
    face([P(-hw, z + fh, 0.004), P(hw, z + fh, 0.004), P(hw, z + h, 0.004), P(-hw, z + h, 0.004)], (0.27, 0.27, 0.15, 0.15))
    if fh:                                                                       # підлога: світла смуга з ледь помітним сміттям
        face([P(-hw, z, 0.006), P(hw, z, 0.006), P(hw, z + fh, 0.006), P(-hw, z + fh, 0.006)], (0.40, 0.40, 0.27, 0.27))
    face([P(-hw, z, 0.01), P(-hw + 0.16, z + 0.02, 0.01), P(-hw + 0.16, z + h - 0.02, 0.01), P(-hw, z + h, 0.01)], (0.46, 0.38, 0.38, 0.46))   # освітлений відкіс
    face([P(hw - 0.12, z + 0.02, 0.01), P(hw, z, 0.01), P(hw, z + h, 0.01), P(hw - 0.12, z + h - 0.02, 0.01)], (0.16, 0.12, 0.12, 0.16))        # відкіс у тіні
    if floor:
        face([P(-hw - 0.08, z - 0.08), P(hw + 0.08, z - 0.08), P(hw + 0.08, z + 0.04, 0.012), P(-hw - 0.08, z + 0.04, 0.012)], (0.62, 0.62, 0.55, 0.55))   # підвіконня
    top = min(z + h + streak, ztop) if ztop else z + h + streak
    if top > z + h + 0.05:
        face([P(-hw - 0.3, z + h), P(hw + 0.3, z + h), P(hw + 0.1, top), P(-hw - 0.1, top)], (0.2, 0.2, 0.62, 0.62))              # потік кіптяви вгору
    # уламок рамки: стійка й шматок перемички, що лишились
    if axis == "y":
        b.box(u + hw - 0.05, c + 0.04 * sgn, z, 0.07, 0.07, min(h, 0.9), "pvc")
    else:
        b.box(c + 0.04 * sgn, u + hw - 0.05, z, 0.07, 0.07, min(h, 0.9), "pvc")


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

def unwrap(me, flat, atlas_px, weights=None, planar=()):
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
    # купи (planar): кожна замкнена купа — один острівець із проєкцією зверху, тож між гранями купи немає швів (окремі острівці
    # на кожну грань давали на дальніх міпах видимі радіальні шви від вершини); поверхня купи однозначна по висоті, перекриття немає
    pl = [p for p in me.polygons if p.material_index in planar and p.material_index not in flat]
    parent = {}

    def find(a_):
        while parent.setdefault(a_, a_) != a_:
            parent[a_] = parent[parent[a_]]
            a_ = parent[a_]
        return a_
    for p in pl:
        vs_ = list(p.vertices)
        for v_ in vs_[1:]:
            parent[find(v_)] = find(vs_[0])
    plset = {p.index for p in pl}
    groups = {}
    for p in pl:
        groups.setdefault(find(p.vertices[0]), []).append(p)
    for polys in groups.values():
        cos_ = [me.vertices[me.loops[l].vertex_index].co for p in polys for l in p.loop_indices]
        x0_, y0_ = min(c.x for c in cos_), min(c.y for c in cos_)
        ls_, loc_ = [], []
        for p in polys:
            for l in p.loop_indices:
                c = me.vertices[me.loops[l].vertex_index].co
                ls_.append(l)
                loc_.append((c.x - x0_, c.y - y0_))
        wt_ = weights[polys[0].material_index] if weights else 1.0
        islands.append((ls_, loc_, max(max(c[0] for c in loc_), 1e-3) * wt_, max(max(c[1] for c in loc_), 1e-3) * wt_, wt_))
    for poly in me.polygons:
        if poly.material_index in flat or poly.index in plset:
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


HEAP_SLOTS = {"heap", "heap_grey", "heap_house", "heap_buff"}


def heap_bake(me, b, hi, mt, img, nimg, atlas_px, ao=0.65):
    """Запікає деталь високополігональної купи (скани + щільна основа) на низькополігональні грані з матеріалом
    купи: альбедо і тангентну нормаль, прямо в основний атлас (лише текселі цих граней)."""
    idx = [i for i, s_ in enumerate(b.slots) if s_ in HEAP_SLOTS]
    if not idx:
        return
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in idx], context="FACES")
    lowme = bpy.data.meshes.new("low_heap")
    bm.to_mesh(lowme)
    bm.free()
    for p in lowme.polygons:
        p.material_index = 0
    lowmat = bpy.data.materials.new("low_bake")
    lowmat.use_nodes = True
    node = lowmat.node_tree.nodes.new("ShaderNodeTexImage")
    lowme.materials.append(lowmat)
    low = bpy.data.objects.new("low_heap", lowme)
    bpy.context.scene.collection.objects.link(low)
    # низька копія має те саме згладжування, що й експорт (30°): тангентна карта нормалей рахується від згладжених нормалей,
    # а з плоских вона на гладкому меші дає видимі грані й радіальну зірку на вершині купи
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(30))
    bmesh.ops.recalc_face_normals(hi.bm, faces=hi.bm.faces)
    himesh = bpy.data.meshes.new("high_heap")
    hi.bm.to_mesh(himesh)
    for s_ in hi.slots:
        himesh.materials.append(mt[s_])
    # основа купи — гладка (інакше її грані дають у карті нормалей радіальну зірку від центру), уламки на ній — гранчасті
    smooth = {i for i, s_ in enumerate(hi.slots) if s_.startswith("heap_base")}
    for poly in himesh.polygons:
        poly.use_smooth = poly.material_index in smooth
    high = bpy.data.objects.new("high_heap", himesh)
    bpy.context.scene.collection.objects.link(high)
    himg = bpy.data.images.new("hbake", atlas_px, atlas_px)
    himg.generated_color = (1.0, 0.0, 1.0, 1.0)
    node.image = himg
    lowmat.node_tree.nodes.active = node
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    kw = dict(use_selected_to_active=True, cage_extrusion=1.2, max_ray_distance=3.0, margin=6, margin_type="EXTEND", use_clear=False)
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, **kw)
    nim2 = bpy.data.images.new("hnorm", atlas_px, atlas_px, alpha=False)
    nim2.generated_color = (0.5, 0.5, 1.0, 1.0)
    nim2.colorspace_settings.name = "Non-Color"
    node.image = nim2
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", **kw)
    aoimg = bpy.data.images.new("hao", atlas_px, atlas_px)
    aoimg.generated_color = (1.0, 1.0, 1.0, 1.0)
    node.image = aoimg
    sc_ = bpy.context.scene
    old_samples = sc_.cycles.samples
    sc_.cycles.samples = 24
    bpy.ops.object.bake(type="AO", **kw)
    sc_.cycles.samples = old_samples
    H = np.array(himg.pixels[:]).reshape(-1, 4)
    AO = np.array(aoimg.pixels[:]).reshape(-1, 4)[:, :3].mean(axis=1)
    N2 = np.array(nim2.pixels[:]).reshape(-1, 4)
    mask = (np.abs(H[:, 0] - 1.0) + np.abs(H[:, 1]) + np.abs(H[:, 2] - 1.0)) > 0.03
    A = np.array(img.pixels[:]).reshape(-1, 4)
    H[:, :3] *= (1.0 - ao * (1.0 - np.clip(AO, 0, 1)))[:, None]      # порожнини між уламками темніші на ao (за замовчуванням ~65%)
    A[mask] = H[mask]
    img.pixels[:] = A.ravel().tolist()
    NN = np.array(nimg.pixels[:]).reshape(-1, 4)
    NN[mask] = N2[mask]
    nimg.pixels[:] = NN.ravel().tolist()
    img.save()
    nimg.save()
    print("HEAPBAKE texels", int(mask.sum()))
    for o in (low, high):
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")


def rubble_heaps(b, plan, seed, dens=7.0, skirt=0.5, skirt_mat="mud_skirt", low="heap_buff", base="heap_base_buff", rock="rubble_buff"):
    """Купи із скан-джерелом для запікання: темна основа, уламки 20-85 см зверху; круті боки губи — темний мул, а не світла смуга."""
    import random
    bh = Builder()
    hr = random.Random(seed)
    for k, h in enumerate(plan):
        big = h.rx * h.ry > 8
        heap_mound(b, h, low, rings=7 if big else 3, segs=32 if big else 16, skirt=skirt, skirt_mat=skirt_mat)
        heap_mound(bh, h, base, rings=16 if big else 6, segs=96 if big else 40, jitter=0.04, seed=seed + k, skirt=skirt)
        for _ in range(int(math.pi * h.rx * h.ry * dens)):
            a = hr.uniform(0, 2 * math.pi)
            t = math.sqrt(hr.uniform(0, 1.0)) * 1.12
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py) if t < 1.0 else h.lip * max(0.0, 1.0 - (t - 1.0) / 0.12) * 0.8
            q = hr.random()
            size = hr.uniform(0.2, 0.42) if q < 0.7 else (hr.uniform(0.42, 0.6) if q < 0.95 else hr.uniform(0.6, 0.85))
            bh.rock(px, py, z + 0.04, size, rock, hr, buried=0.3)
    return bh


def rubble_lumps(b, plan, rnd, n_each=8, tmin=0.1, tmax=1.0, size=(0.22, 0.42), mats=("brick_face", "wall_plaster", "brick_face", "brick_dark")):
    """Грудки цегли й штукатурки 20-40 см по всій купі: справжня геометрія дає тінь і силует, а не лише запечену плями."""
    for h in plan:
        for _ in range(n_each):
            a = rnd.uniform(0, 2 * math.pi)
            t = rnd.uniform(tmin, tmax)
            r = t * h.radius(a)
            px, py = h.cx + h.rx * r * math.cos(a), h.cy + h.ry * r * math.sin(a)
            z = h.z(px, py)
            sz = rnd.uniform(*size)
            b.box_e(px, py, z + sz * 0.2, sz * rnd.uniform(0.8, 1.4), sz * rnd.uniform(0.55, 1.0), sz * rnd.uniform(0.4, 0.8), rnd.choice(mats),
                    euler=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(0, 3.14)))


def finish(b, name, out_dir, atlas_px=None, tri_limit=None, target_cm=3.2, footprint=(1, 1), anchor=None, density=None, hi=None, ground_clip=False, ao=0.65):
    """Меш → обʼєкт, UV, запікання атласу, один матеріал, масштаб 1/8, експорт, перевірка."""
    mt = mats()
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    b.bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for s in b.slots:
        me.materials.append(mt[s])
    if ground_clip:                                   # вкопані частини (уламки, крокви, губа купи) не мають зсувати об'єкт угору
        for v in me.vertices:
            if v.co.z < 0.0:
                v.co.z = 0.0
        me.update()
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
    planar = [i for i, s in enumerate(b.slots) if s in HEAP_SLOTS]
    # найменший атлас, що дає щільність не грубішу за target_cm (але не більше 2048)
    for atlas_px in (256, 512, 1024, 2048):
        cm = unwrap(me, flat, atlas_px, [(density or {}).get(sn, 1.0) for sn in b.slots], planar if hi is not None else ())
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
    if hi is not None:
        heap_bake(me, b, hi, mt, img, nimg, atlas_px, ao)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)

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
