"""Круглі тюки: суха солома (сіро-охристий хакі) і білий плівковий силос; плюс штабель 2+1.

Тюк лежить на боці: вісь уздовж X, Ø 1,35 м, ширина 1,2 м. Полярна розгортка: колові смуги
на торцях — це шари скрутки, а не візерунок накладений зверху.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *

R, Wd, BEV = 0.675, 1.2, 0.07


def straw_mat():
    n = 128
    streak = tile_noise(3, 48, n, 41) * 0.6 + tile_noise(6, 96, n, 42) * 0.4      # смуги вздовж u
    blot = fbm(n, 43, 3)
    h = streak
    base = np.array([0.42, 0.38, 0.27]); dark = np.array([0.22, 0.20, 0.14])
    t = np.clip(0.35 + 0.6 * streak + 0.5 * (blot - 0.5), 0, 1)[..., None]
    a = dark + (base - dark) * t * 1.25
    return pbr("hay_straw", albedo=a, normal=np.concatenate([normal_from_height(h, 5.0), np.ones((n, n, 1))], -1),
               rough=0.95, tile=2.1)


def wrap_mat():
    n = 128
    band = tile_noise(2, 24, n, 51)                                              # складки плівки
    fine = tile_noise(8, 64, n, 52)
    h = band * 0.7 + fine * 0.3
    dirt = np.clip((fbm(n, 53, 4) - 0.45) * 2.2, 0, 1)[..., None]
    a = np.array([0.74, 0.76, 0.72]) * (0.88 + 0.12 * h[..., None])
    a = a * (1 - 0.35 * dirt)
    return pbr("hay_wrap", albedo=a, normal=np.concatenate([normal_from_height(h, 3.0), np.ones((n, n, 1))], -1),
               rough=0.3, tile=2.1)


def bale(b, mat, c=(0, 0, R), rot_jitter=0.0, seed=0, nseg=24):
    """Профіль обертання з фаскою по торцю; UV полярні: u — кут (2 повтори), v — радіус/осьова координата."""
    bm = b.bm
    prof = [(0.0, -Wd / 2), (R - BEV, -Wd / 2), (R, -Wd / 2 + BEV), (R, Wd / 2 - BEV), (R - BEV, Wd / 2), (0.0, Wd / 2)]
    rng = np.random.default_rng(seed)
    rings = []
    for (r, x) in prof:
        if r == 0.0:
            rings.append(bm.verts.new((c[0] + x, c[1], c[2])))
        else:
            ring = []
            for k in range(nseg):
                a = 2 * math.pi * k / nseg
                rr = r * (1 + (rng.random() - 0.5) * 0.02) if r > 0.5 else r
                ring.append(bm.verts.new((c[0] + x, c[1] + rr * math.cos(a), c[2] + 0.97 * rr * math.sin(a))))
            rings.append(ring)
    uv = bm.loops.layers.uv.verify()
    idx = b.mi(mat)

    def mk(vs, vfn):
        f = bm.faces.new(vs)
        f.material_index = idx
        b.skip_uv.add(f)
        th = [math.atan2(v.co.z - c[2], v.co.y - c[1]) / (2 * math.pi) * 2 for v in vs]
        if max(th) - min(th) > 1.0:
            th = [t + 2 if t < 0 else t for t in th]
        for l, t, v in zip(f.loops, th, vs):
            l[uv].uv = (t, vfn(v))

    def vr(v): return math.hypot(v.co.y - c[1], v.co.z - c[2]) / R * 0.5
    def vx(v): return (v.co.x - c[0] + Wd / 2) / Wd * 0.6
    for sgn in (1, -1):
        centre = rings[0] if sgn > 0 else rings[5]
        r0 = rings[1] if sgn > 0 else rings[4]
        for k in range(nseg):
            tri = [centre, r0[k], r0[(k + 1) % nseg]] if sgn > 0 else [centre, r0[(k + 1) % nseg], r0[k]]
            mk(tri, vr)
    for i in (1, 2, 3):
        a, bq = rings[i], rings[i + 1]
        for k in range(nseg):
            k2 = (k + 1) % nseg
            mk([a[k], a[k2], bq[k2], bq[k]], vx)


def build(name, mat, stack=False):
    b = B()
    if not stack:
        bale(b, mat)
    else:
        for i, (y, z) in enumerate(((-0.7, R), (0.7, R), (0.0, R + math.sqrt((2 * R * 0.99) ** 2 - 0.7 ** 2)))):
            bale(b, mat, (0, y, z), seed=i + 1)
    finish(b, name)


reset()
if want("infra_hay_round"): build("infra_hay_round", straw_mat())
if want("infra_hay_wrapped"): build("infra_hay_wrapped", wrap_mat())
if want("infra_hay_stack"): build("infra_hay_stack", straw_mat(), stack=True)
