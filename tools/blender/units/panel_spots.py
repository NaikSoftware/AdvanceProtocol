"""Find where a recognition panel can lie on a unit's roof (after prep.py has built `lo`).

    blender -b --factory-startup --python panel_spots.py -- <unit>        # <work>/hmap.npy + hmap.png
    python3 -I panel_spots.py <unit> <across_m> <along_m> <y_lo> <y_hi>   # list spots in that band

The map is the top height of `lo` in MODEL units (front at the top of the PNG, grid every 0.05,
alternate 1 cm height bands shaded). The search lists panel centres `at` [x, y] whose footprint
lies flat on one roof plane, level or sloped: the spread of heights off the best-fit plane is at
most `panel_flat_tol` (no overhang off an edge, no kit under the cloth). Put the chosen centre in units.json `panels[].at`.
"""
import sys, os
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

G, X0, Y0 = 0.0025, -0.30, -0.55

if "bpy" in sys.modules or sys.argv[0].endswith("blender"):
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    cfg = lib.load(sys.argv[sys.argv.index("--") + 1])
    bpy.ops.wm.open_mainfile(filepath=os.path.join(cfg["work"], "work.blend"))
    bvh = BVHTree.FromObject(bpy.data.objects["lo"], bpy.context.evaluated_depsgraph_get())
    xs, ys = np.arange(X0, -X0, G), np.arange(Y0, -Y0, G)
    H = np.zeros((len(ys), len(xs)))
    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            h = bvh.ray_cast(Vector((x, y, 2.0)), Vector((0, 0, -1)))[0]
            H[j, i] = h.z if h else 0.0
    np.save(os.path.join(cfg["work"], "hmap.npy"), H)
    print("SPOTS heightmap saved, max", round(float(H.max()), 4))
    raise SystemExit

from PIL import Image, ImageDraw

cfg = lib.load(sys.argv[1])
H = np.load(os.path.join(cfg["work"], "hmap.npy"))
F = H[::-1]
rgb = np.stack([(np.clip(F / F.max(), 0, 1) * 255).astype(np.uint8)] * 3, -1)
band = (np.floor(F / 0.01) % 2).astype(bool)
rgb[band] = (rgb[band] * 0.75).astype(np.uint8)
S = 3
im = Image.fromarray(rgb).resize((F.shape[1] * S, F.shape[0] * S), Image.NEAREST)
d = ImageDraw.Draw(im)
for v in np.arange(-0.55, 0.551, 0.05):
    r = (len(F) - 1 - (v - Y0) / G) * S
    d.line([(0, r), (im.width, r)], fill=(200, 60, 60)); d.text((2, r), f"{v:+.2f}", fill=(255, 255, 0))
for v in np.arange(-0.30, 0.301, 0.05):
    c = (v - X0) / G * S
    d.line([(c, 0), (c, im.height)], fill=(60, 60, 200)); d.text((c + 2, 2), f"{v:+.2f}", fill=(0, 255, 255))
im.save(os.path.join(cfg["work"], "hmap.png"))
if len(sys.argv) < 6:
    raise SystemExit
sx, sy = float(sys.argv[2]) / lib.TILE_M, float(sys.argv[3]) / lib.TILE_M
ylo, yhi = float(sys.argv[4]), float(sys.argv[5])
tol = cfg.get("panel_flat_tol", 0.025)
nx, ny = int(round(sx / G)), int(round(sy / G))
jj, ii = np.mgrid[0:ny + 1:2, 0:nx + 1:2]
A = np.c_[ii.ravel(), jj.ravel(), np.ones(jj.size)]
pinv = np.linalg.pinv(A)
ok = []
for j in range(0, H.shape[0] - ny, 2):
    cy = Y0 + (j + ny / 2) * G
    if not ylo <= cy <= yhi:
        continue
    for i in range(0, H.shape[1] - nx, 2):
        f = H[j:j + ny + 1:2, i:i + nx + 1:2].ravel()
        if f.min() < 0.02:
            continue
        r = f - A @ (pinv @ f)                  # off the best-fit plane: flat or sloped roofs alike
        ok.append((X0 + (i + nx / 2) * G, cy, float(np.median(f)), float(r.max() - r.min())))
good = [q for q in ok if q[3] <= tol]
print(f"{len(good)} spots for {sx * 8:.2f} x {sy * 8:.2f} m in y {ylo}..{yhi} (off-plane spread <= {tol})")
# none flat enough: show the least uneven, so a smaller panel can be judged
for x, y, m, sp in (sorted(good, key=lambda q: (-q[2], abs(q[0]))) or sorted(ok, key=lambda q: q[3]))[:12]:
    print(f"  at [{x:+.3f}, {y:+.3f}]  level {m:.3f}  off-plane spread {sp:.4f}")
