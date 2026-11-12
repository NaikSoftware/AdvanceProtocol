"""Contrast gate of a unit model against the ground around it, from tools/unit_gate.gd frames.

    python3 -I tools/unit_gate.py <out_dir> [map_t<type> ...]

Per place: mask = magenta pixels of _C; body = mask pixels not darker than in _S by more than 15 %
(self-shadow excluded), colour = median of the body in _A<n>; ground = median of a ring 3..12 px
around the mask in _B (no model, so no cast shadow). ΔE is CIE76. `cloud` repeats it with the ground
under a cloud shadow (linear ground x (1 - cloud_shadow_strength) of the map's look, the shader's
own factor), the worst case where the model is darker than the ground.
Places where less than 70 % of the model shows (crowns overhang the cell) are skipped. All
forest_* and gap_* places (field cell at a forest edge, or one cell from it) are samples. On a
sunny map the one with the darkest ground ring is labelled `canopy_` when that ring is at least
4 L* darker than the open field, i.e. in a canopy's cast shadow; otherwise the script says none
was found. Check the canopy frame by eye: a dark ground can pass for a shadow.
The gate (§5) passes when every place on every map has ΔE >= 15, both open and under cloud.
"""
import sys, glob, os, re
import numpy as np
from PIL import Image

CLOUD = {"crossroads": 0.0, "river": 0.35, "ridge": 0.3}     # game/battle/look/<map>.tres
SUNNY = {"crossroads", "ridge"}


def lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lab_lin(c):
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    x, y, z = (np.asarray(c, float) @ m.T / np.array([0.95047, 1.0, 1.08883])).T
    f = lambda t: np.where(t > 216 / 24389, np.cbrt(t), (24389 / 27 * t + 16) / 116)
    return np.array([116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))])


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def img(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(float)


def place(base):
    C, B, S = img(base + "_C.png"), img(base + "_B.png"), img(base + "_S.png")
    mask = (C[..., 0] > 200) & (C[..., 1] < 60) & (C[..., 2] > 200)
    ring = dilate(mask, 12) & ~dilate(mask, 3)
    ground = np.median(lin(B[ring]), 0)
    tints = sorted(glob.glob(base + "_A*.png"), key=lambda p: int(re.findall(r"_A(\d+)\.png$", p)[0]))
    rows = []
    for t in tints:
        A = img(t)
        lum = lambda X: X @ np.array([0.2126, 0.7152, 0.0722])
        body = mask & (lum(A) >= 0.85 * lum(S)) if t.endswith("_A0.png") else body
        rows.append(np.median(lin(A[body]), 0))
    return mask.sum(), body.sum(), ground, rows


def main():
    out = sys.argv[1]
    tags = sys.argv[2:] or sorted({re.match(r"(.+?_t\d+)_", os.path.basename(p)).group(1)
                                   for p in glob.glob(out + "/*_C.png")})
    worst = {}
    print(f"{'place':34s} {'px':>5s} {'body':>5s} {'ground Lab':>18s} {'model Lab':>18s} {'dE':>5s} {'cloud':>5s}")
    for tag in tags:
        m = tag.split("_t")[0]
        res = {}
        for c in sorted(glob.glob(f"{out}/{tag}_*_C.png")):
            base = c[:-6]
            res[base[len(out) + 1 + len(tag) + 1:]] = place(base)
        names = {k: k for k in res}
        full = max(r[0] for r in res.values())
        for k in res:
            if res[k][0] < 0.7 * full:
                names[k] = None   # crowns or a wall hide the model: not a sample (the game fades them)
        forest = sorted((k for k in res if k.startswith(("forest_", "gap_")) and names[k]), key=lambda k: lab_lin(res[k][2])[0])
        open_l = max((lab_lin(res[k][2])[0] for k in ("meadow", "plough") if k in res), default=0.0)
        if m in SUNNY and forest and lab_lin(res[forest[0]][2])[0] <= open_l - 4:
            names[forest[0]] = "canopy_" + forest[0]
        elif m in SUNNY:
            print(f"{tag}: no forest place in a canopy's cast shadow (darkest ring not 4 L* under the open field)")
        for k, (px, nb, g, rows) in res.items():
            if names[k] is None:
                continue
            gl, gc = lab_lin(g), lab_lin(g * (1 - CLOUD.get(m, 0.0)))
            for i, mc in enumerate(rows):
                ml = lab_lin(mc)
                d, dc = np.linalg.norm(ml - gl), np.linalg.norm(ml - gc)
                key = (tag, i)
                worst[key] = min(worst.get(key, 99), d, dc)
                print(f"{tag + '_' + names[k] + ('' if len(rows) == 1 else f'_A{i}'):34s} {px:5d} {nb:5d} "
                      f"{np.array2string(gl.round(1)):>18s} {np.array2string(ml.round(1)):>18s} {d:5.1f} {dc:5.1f}")
    print("worst per tint:", {f"{t}_A{i}": round(v, 1) for (t, i), v in sorted(worst.items())})


main()
