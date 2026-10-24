"""Бетонний блок (джерсі), придорожня водопропускна труба, фермерський причіп.

Причіп: перед (дишло) уздовж +Y Blender = −Z Godot. Труба: вісь уздовж Y, два оголовки.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *


def concrete(name="road_concrete", seed=61):
    return concrete_mat(name, tile=1.5, seed=seed)


def jersey():
    mat = concrete()
    b = B(); bm = b.bm
    prof = [(-.30, 0), (.30, 0), (.30, .12), (.17, .42), (.10, .80), (-.10, .80), (-.17, .42), (-.30, .12)]
    rng = np.random.default_rng(7)
    rings = []
    for x in (-1.0, 1.0):
        ring = []
        for (y, z) in prof:
            dy, dz = 0.0, 0.0
            if z > 0.7 or y in (-.30, .30) and z > 0:      # сколи: верх і нижні кути зсунуто на кілька см
                dz = -rng.random() * 0.04; dy = (rng.random() - 0.5) * 0.02
            ring.append(bm.verts.new((x + (rng.random() - 0.5) * 0.01 * (1 if abs(x) > 0 else 0), y + dy, z + dz)))
        rings.append(ring)
    n = len(prof)
    for k in range(n):
        bm.faces.new([rings[0][k], rings[0][(k + 1) % n], rings[1][(k + 1) % n], rings[1][k]])
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[1])
    for f in bm.faces:
        f.material_index = b.mi(mat)
    finish(b, "infra_jersey_block")


def tube(b, mat, c, ro, ri, L, n=20, inner=None):
    bm = b.bm
    y0, y1 = c[1] - L / 2, c[1] + L / 2
    ang = [2 * math.pi * k / n for k in range(n)]
    V = {key: [bm.verts.new((c[0] + r * math.cos(a), y, c[2] + r * math.sin(a))) for a in ang]
         for key, (r, y) in {"o0": (ro, y0), "o1": (ro, y1), "i0": (ri, y0), "i1": (ri, y1)}.items()}
    i = b.mi(mat); j = b.mi(inner or mat)
    for k in range(n):
        k2 = (k + 1) % n
        for q, m in (([V["o0"][k], V["o1"][k], V["o1"][k2], V["o0"][k2]], i), ([V["i0"][k], V["i0"][k2], V["i1"][k2], V["i1"][k]], j),
                     ([V["o0"][k], V["o0"][k2], V["i0"][k2], V["i0"][k]], i), ([V["o1"][k], V["i1"][k], V["i1"][k2], V["o1"][k2]], i)):
            bm.faces.new(q).material_index = m


def ditch_decal():
    """Декаль канави 16 × 1,8 м (3 см/тексель): мокра темна земля з водяним блиском; дошка кладе дві смуги
    вздовж дороги по обидва боки труби, на 5,3 м від осі труби."""
    W, H = 512, 64
    v = (np.arange(H) + 0.5) / H
    n = np.tile(tile_noise(16, 4, 128, 83), (1, 4))[:H]
    width = 0.32 + 0.12 * n
    alpha = np.clip((width - np.abs(v[:, None] - 0.5)) / 0.07, 0, 1)
    wet = 0.5 + 0.5 * np.cos((v[:, None] - 0.5) * 8)
    col = np.array([0.17, 0.15, 0.12])[None, None, :] * (0.8 + 0.4 * n[..., None]) + 0.05 * wet[..., None]
    img = bpy.data.images.new("ditch", W, H, alpha=True)
    arr = np.concatenate([col, (alpha * 0.9)[..., None]], -1)
    img.pixels.foreach_set(arr.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(OUT, "infra_culvert_ditch.png"); img.file_format = "PNG"; img.save()


def culvert():
    mat = concrete("culvert_concrete", 63)
    ditch_decal()
    dark = pbr("culvert_dark", color=(0.02, 0.022, 0.02), rough=1.0)
    b = B()
    zc = 0.62
    for s in (-1, 1):
        b.box(mat, (0, s * 4.4, 0.75), (3.0, 0.4, 1.5))                        # оголовок
        b.box(mat, (0, s * 4.6, 1.52), (3.1, 0.5, 0.1))                        # верхня кромка
        b.box(mat, (0, s * 4.9, 0.04), (1.8, 0.6, 0.08))                       # лотковий фартух
        tube(b, mat, (0, s * 4.8, zc), 0.62, 0.5, 0.4, inner=dark)                         # виступ труби
        b.cyl(dark, (0, s * 4.62, zc), 0.5, 0.04, 20, axis="Y")                # темний зів
        for sx in (-1, 1):                                                     # відхилені крила
            b.box(mat, (sx * 1.7, s * 4.6, 0.45), (0.3, 1.0, 0.9),
                  Matrix.Rotation(sx * s * 0.45, 3, "Z"))
    finish(b, "infra_culvert")


def trailer(name, paint, seed):
    body = sheet_mat(f"trailer_body_{seed}", paint, seed)
    frame = pbr("trailer_frame", "MetalPlates013", tile=1.0, tint=(0.42, 0.41, 0.39), sat=0.3, rust=0.0, grime=0.0,
                rough=0.8, seed=seed + 1)
    tyre = rim = frame        # шасі, шини й диски — один матеріал
    b = B()
    y0, y1, fl = -3.75, 2.25, 1.01
    b.box(body, (0, (y0 + y1) / 2, fl), (2.4, y1 - y0, 0.08))                       # підлога
    for s in (-1, 1):
        b.box(body, (s * 1.2, (y0 + y1) / 2, fl + 0.55), (0.05, y1 - y0, 1.0))      # борт
        b.box(frame, (s * 1.22, (y0 + y1) / 2, fl + 1.07), (0.1, y1 - y0, 0.08))    # верхня обв'язка
        b.box(frame, (s * 0.6, (y0 + y1) / 2, 0.85), (0.14, y1 - y0 - 0.2, 0.2))    # лонжерони
    b.box(body, (0, y0, fl + 0.55), (2.4, 0.05, 1.0))                               # задній борт
    b.box(frame, (0, y0 - 0.03, fl + 1.07), (2.5, 0.08, 0.08))
    b.box(body, (0, y1, fl + 0.65), (2.4, 0.07, 1.3))                               # щит (до 2.3 м)
    b.box(frame, (0, y1, fl + 1.32), (2.46, 0.1, 0.08))
    for ay in (-2.4, -1.2):
        b.cyl(frame, (0, ay, 0.5), 0.07, 2.3, 8, axis="X")                          # осі
        for s in (-1, 1):
            b.cyl(tyre, (s * 1.05, ay, 0.5), 0.5, 0.4, 16, axis="X")
            b.cyl(rim, (s * 1.05 + s * 0.02, ay, 0.5), 0.28, 0.4, 10, axis="X")
    for s in (-1, 1):                                                               # дишло: А-подібна рама
        b.beam(frame, (s * 0.6, y1, 0.8), (0, 3.7, 0.75), 0.11)
    b.box(frame, (0, 3.66, 0.75), (0.32, 0.3, 0.14))
    b.box(frame, (0, y1 + 0.5, 0.78), (1.1, 0.14, 0.14))
    b.beam(frame, (0, 2.55, 1.0), (0, 2.38, 2.0), 0.07, 8)                          # гідроциліндр
    finish(b, name)


reset()
if want("infra_jersey_block"): jersey()
if want("infra_culvert"): culvert()
if want("infra_trailer_green"): trailer("infra_trailer_green", (0.47, 0.57, 0.53), 71)
if want("infra_trailer_rust"): trailer("infra_trailer_rust", (0.50, 0.38, 0.33), 73)
