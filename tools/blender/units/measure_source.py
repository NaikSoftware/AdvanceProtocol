"""Measure a generated source mesh before writing its unit config (plain Python, numpy + PIL).

    blender -b --factory-startup --python measure_source.py -- src.glb out_dir     # dump verts.npy
    python3 -I measure_source.py out_dir/verts.npy out_dir [fwd_axis x|y|-y] [[lat=a:b] wheel guesses x:z ...]

The first form (inside Blender) dumps the vertex cloud. The second prints the lateral profile by
height (track zone, skirt line), the hull length without the gun, and writes side slabs as PNGs
(2000 px per source unit, grid every 0.05 / 0.01) to read wheel centres off. Given rough wheel
centres `x:z` (z above ground) it refines each with a least-squares circle fit on the outer
tyre edge (in the lateral band lat=a:b, default 0.15:0.21). All numbers are in source units with the long axis on `fwd_axis` (x or y), z up.
"""
import sys
import numpy as np

if "bpy" in sys.modules or sys.argv[0].endswith("blender"):
    import bpy
    a = sys.argv[sys.argv.index("--") + 1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=a[0])
    out = []
    for o in bpy.data.objects:
        if o.type == 'MESH':
            co = np.empty(len(o.data.vertices) * 3); o.data.vertices.foreach_get("co", co)
            w = np.array(o.matrix_world)
            out.append(co.reshape(-1, 3) @ w[:3, :3].T + w[:3, 3])
    np.save(a[1] + "/verts.npy", np.concatenate(out).astype(np.float32))
    raise SystemExit

from PIL import Image

co = np.load(sys.argv[1]); out = sys.argv[2]
fwd = sys.argv[3] if len(sys.argv) > 3 else "x"
x, y, z = {"x": (co[:, 0], co[:, 1]), "y": (co[:, 1], -co[:, 0]), "-y": (-co[:, 1], co[:, 0])}[fwd] + (co[:, 2],)
g = z.min(); h = z - g
print(f"ground z {g:.4f}  height {h.max():.4f}  long {x.min():.4f}..{x.max():.4f}  lat ±{np.abs(y).max():.4f}")
for z0 in np.arange(0, 0.2, 0.03):
    m = (h >= z0) & (h < z0 + 0.03)
    hist, _ = np.histogram(np.abs(y[m]), bins=22, range=(0, 0.22))
    print(f"h {z0:.2f}-{z0+0.03:.2f} |lat| per 0.01:", hist.tolist())
m = np.abs(y) > 0.12
print(f"hull long range (|lat|>0.12): {x[m].min():.4f}..{x[m].max():.4f}")

S = 2000
def slab(y0, y1, name):
    m = (np.abs(y) >= y0) & (np.abs(y) < y1) & (h < 0.18)
    W, H = int((x.max() - x.min()) * S) + 1, int(0.18 * S)
    im = np.zeros((H, W), np.uint8)
    im[(H - 1 - (h[m] * S).astype(int)).clip(0, H - 1), ((x[m] - x.min()) * S).astype(int).clip(0, W - 1)] = 255
    im[:, ::100] = np.maximum(im[:, ::100], 70); im[::-20, :] = np.maximum(im[::-20, :], 40)
    Image.fromarray(im).save(f"{out}/{name}.png")
slab(0.17, 0.205, "slab_outer"); slab(0.12, 0.16, "slab_mid")

def fit(cx, cz, lat=(0.15, 0.21), rmax=0.055):
    """Circle fit to the outer rim of one wheel: points near the guess, outer 30 % by radius."""
    m = (np.abs(y) >= lat[0]) & (np.abs(y) < lat[1]) & ((x - cx) ** 2 + (h - cz) ** 2 < rmax ** 2)
    px, pz = x[m], h[m]
    for _ in range(3):
        r = np.hypot(px - cx, pz - cz)
        k = r > np.percentile(r, 70)
        A = np.c_[2 * px[k], 2 * pz[k], np.ones(k.sum())]
        sol = np.linalg.lstsq(A, px[k] ** 2 + pz[k] ** 2, rcond=None)[0]
        cx, cz = sol[0], sol[1]
    return cx, cz, float(np.sqrt(sol[2] + cx * cx + cz * cz))

band = (0.15, 0.21)
for arg in sys.argv[4:]:
    if arg.startswith("lat="):             # lateral band of the tyre faces, e.g. lat=0.13:0.17
        band = tuple(map(float, arg[4:].split(":")))
        continue
    gx, gz = map(float, arg.split(":"))
    cx, cz, r = fit(gx, gz, band)
    print(f"wheel guess {gx:+.3f}:{gz:.3f} -> centre x {cx:+.4f} h {cz:.4f} r {r:.4f}")
