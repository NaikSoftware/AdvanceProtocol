"""Turn bake_flipbook.py frames into RGBA flipbook atlases, validate them, draw contact strips.

python3 -I assemble.py <frames_root> <out_dir> <name|all> [--kenney <particle-pack dir>]

Per atlas: window the alpha to zero near the cell border (soft edges, no hard frame border), cross-fade
two cycles into a seamless loop where the effect loops, grade the colour into the brief's Lab range,
fill RGB under transparent pixels (no dark halos when the GPU filters between frames).
"""
import sys, os, glob
import numpy as np
from PIL import Image, ImageFilter

# kind: loop | once. m = real width of one cell in metres (the camera frame of the bake).
# lab: target (L lo, L hi) for the alpha-weighted mean colour; amax: cap on peak alpha.
ATLAS = {
    "smoke_column": dict(src="smoke_puff", kind="puff", n=64, cols=8, rows=8, fps=4, m=22.1,
                              lab=(12, 27), tgt_L=26, ab=((-1, 2), (-3, 4))),
    "smoke_column_thin": dict(src="smoke_puff", kind="puff", n=64, cols=8, rows=8, fps=4, m=22.1,
                              lab=(35, 45), tgt_L=40, amax=0.35, ab=((-1, 2), (-3, 4))),
    "wreck_fire": dict(src="wreck_fire", kind="loop", n=64, cols=16, rows=4, fps=8, bonfire=1, raw=1, m=2.93, sway=0.05,
                            lab=None),
    "explosion": dict(src="explosion", kind="once", topramp=(0.06, 0.30), n=64, cols=8, rows=8, fps=48, m=22.4, lab=None),
    "dirt_burst": dict(src="dirt_burst", kind="once", n=64, cols=8, rows=8, fps=40, m=13.7, desat=0.65,
                       lab=(28, 38), tgt_L=33, ab=((2, 4), (6, 10))),
    "impact_flash": dict(src="flash", kind="once", tail=6, topramp=(0.06, 0.26), n=16, cols=4, rows=4, fps=60, m=6.7, lab=None),
}
GRASS = np.array([92, 104, 70], np.float32) / 255  # muted late-autumn grass, L* ~ 41
CM_PX = (7, 22)  # closest / farthest zoom, cm per screen pixel


def srgb2lab(rgb):
    c = np.where(rgb > 0.04045, ((rgb + 0.055) / 1.055) ** 2.4, rgb / 12.92)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def mean_lab(frames):
    """Alpha-weighted mean Lab of straight-colour frames (N,H,W,4 float 0..1)."""
    a = frames[..., 3:4]
    rgb = (frames[..., :3] * a).sum((0, 1, 2)) / max(a.sum(), 1e-9)
    return srgb2lab(rgb)


def window(n, margin_zero=0.05, margin_full=0.18, bottom=(0.03, 0.09)):
    """(wy, wx): alpha factors. The bottom ramp is short because ground effects stand on the floor."""
    def ramp(d, z, f):
        t = np.clip((d - z) / (f - z), 0, 1)
        return t * t * (3 - 2 * t)
    u = np.linspace(0, 1, n)  # 0 = top row
    wx = ramp(np.minimum(u, 1 - u), margin_zero, margin_full)
    wy = np.minimum(ramp(u, margin_zero, margin_full), ramp(1 - u, *bottom))
    return wy, wx


def load(src_dir):
    """Frames, lightly sharpened: Mantaflow smoke is diffusive and the folds need a firmer edge."""
    fs = sorted(glob.glob(src_dir + "/f_*.png"))
    sh = ImageFilter.UnsharpMask(radius=1.4, percent=25, threshold=1)
    return np.stack([np.asarray(Image.open(f).convert("RGBA").filter(sh), np.float32) / 255 for f in fs])


def loopify(fr, n):
    """fr: 2n consecutive sim frames. out[i] fades from the later cycle into the earlier one:
    out[0] = fr[n], out[n] would be fr[n] again, so the loop is seamless."""
    w = (np.arange(n) / n).reshape(-1, 1, 1, 1)
    a, b = fr[n:2 * n], fr[:n]
    pa = a[..., :3] * a[..., 3:]
    pb = b[..., :3] * b[..., 3:]
    al = a[..., 3:] * (1 - w) + b[..., 3:] * w
    pm = pa * (1 - w) + pb * w
    return np.concatenate([pm / np.maximum(al, 1e-6), al], -1)


def _blur(a, r):
    from scipy.ndimage import gaussian_filter
    return gaussian_filter(a, r, mode="constant")


def bonfire(fr, cfg):
    """Turn the thin, stringy flame sheets of the sim into a full, soft, bright flame body.

    Shape comes from the sim (its alpha, blurred and filled), colour from the height in the flame:
    near-white to pale yellow in the lower 40%, yellow-orange in the middle, orange-red and fading in the
    top 20%. Thin dark-grey wisps above the tips hand over to the smoke column (alpha <= 0.4).
    """
    n, H, W, _ = fr.shape
    a0 = fr[..., 3]
    union = a0.max(0)
    rows = np.nonzero(_blur(union, 1.5).max(1) > 0.35)[0]
    top, bot = int(rows.min()), int(rows.max())
    base_to_tip = ((bot - np.arange(H)) / max(bot - top, 1)).clip(0, 1)[:, None]
    stops_u = [0.0, 0.40, 0.60, 0.80, 1.0]
    stops_c = np.array([(255, 246, 205), (255, 236, 175), (255, 200, 92), (244, 140, 46), (210, 74, 24)], np.float32) / 255
    col = np.stack([np.interp(base_to_tip[:, 0], stops_u, stops_c[:, k]) for k in range(3)], -1)[:, None, :]  # H,1,3
    rng = np.random.default_rng(5)
    out = np.zeros_like(fr)
    if cfg.get("raw"):
        return _raw_flame(fr, base_to_tip[:, 0], cfg, rng)
    for i in range(n):
        a = a0[i]
        body = np.clip(_blur(a, 2.2) * float(cfg.get("fill", 2.6)), 0, 1)
        body = _blur(body, float(cfg.get("soft", 1.3)))
        # keep a little of the sim's own brightness variation as texture
        lum = fr[i, ..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        tex = _blur(lum, 1.0)
        tex = np.clip(tex / max(float(np.percentile(tex[a > 0.3], 90)) if (a > 0.3).any() else 1.0, 1e-3), 0, 1.2)
        tx = 0.9 + 0.12 * (tex - 0.6)
        edge = np.clip(1 - body * 1.4, 0, 1)[..., None]  # rim: one step cooler than the core
        up = np.clip(base_to_tip + 0.18, 0, 1)
        col2 = np.stack([np.interp(up[:, 0], stops_u, stops_c[:, k]) for k in range(3)], -1)[:, None, :]
        rgb = (col * (1 - 0.55 * edge) + col2 * 0.55 * edge) * tx[..., None]
        al = body * (1 - np.clip((base_to_tip - 0.80) / 0.20, 0, 1) ** 1.5 * 0.92)
        # smoke wisps: the flame silhouette dragged upwards and smeared, dark grey, thin
        w = np.zeros((H, W), np.float32)
        for k, (dy, r, g) in enumerate(((int(H * 0.16), 5.0, 0.30), (int(H * 0.30), 8.0, 0.22))):
            sh = np.roll(body, -dy, 0)
            sh[H - dy:] = 0
            sh = np.roll(sh, int(round(6 * np.sin(i * 0.37 + k * 2))), 1)
            nz = _blur(rng.random((H, W)).astype(np.float32), 5.0)
            nz = (nz - nz.min()) / max(nz.max() - nz.min(), 1e-6)
            w = np.maximum(w, _blur(sh, r) * g * (0.5 + nz))
        w = np.clip(w, 0, 0.4)
        w = w * (1 - al)
        soot = np.array([0.20, 0.18, 0.17], np.float32)
        a_out = al + w * (1 - al)
        rgb_out = (rgb * al[..., None] + soot * (w * (1 - al))[..., None]) / np.maximum(a_out[..., None], 1e-6)
        out[i, ..., :3] = np.clip(rgb_out, 0, 1)
        out[i, ..., 3] = np.clip(a_out, 0, 1)
    return _sway(out, base_to_tip[:, 0], cfg)


def _sway(out, h, cfg):
    """Licking: the upper flame leans and whips sideways. Sum of harmonics of the loop period, so frame
    63 -> 0 stays continuous; harmonics 1..4 with fixed phases make it non-rhythmic to the eye."""
    from scipy.ndimage import shift as ndshift
    n, H, W, _ = out.shape
    amp = float(cfg.get("sway", 0.07)) * W
    ph = (0.4, 2.1, 4.0, 5.3)
    wt = (1.0, 0.7, 0.45, 0.3)
    res = np.empty_like(out)
    for i in range(n):
        t = 2 * np.pi * i / n
        lean = sum(w * np.sin((k + 1) * t + p_) for k, (w, p_) in enumerate(zip(wt, ph)))
        # a second, faster whip that only the tip feels
        whip = sum(w * np.sin((k + 2) * 2 * t + p_ * 1.7) for k, (w, p_) in enumerate(zip(wt, ph)))
        for r in range(H):
            dx = amp * (lean * h[r] ** 1.4 + 0.6 * whip * h[r] ** 3)
            res[i, r] = ndshift(out[i, r], (dx, 0), order=1, mode="constant")
    return res


def _raw_flame(fr, h, cfg, rng):
    """The sim's own emission and soft alpha, kept: only a cooler tint towards the tips, a short fade at the
    very top, <= 1 px blur and thin smoke wisps. No fill, so the licks and gaps inside the body stay."""
    n, H, W, _ = fr.shape
    out = np.zeros_like(fr)
    hh = h[:, None]
    t = (np.clip((hh - 0.45) / 0.55, 0, 1) ** 1.3) * float(cfg.get("tip", 0.6))
    orange = np.array([232, 92, 26], np.float32) / 255
    for i in range(n):
        a = fr[i, ..., 3]
        rgb = fr[i, ..., :3]
        edge = np.clip(1 - a * 1.2, 0, 1)[..., None] * 0.45  # thin, see-through parts run orange-red
        tt = np.clip(t[..., None] + edge, 0, 0.85)
        lum = (rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
        rgb = rgb * (1 - tt) + orange * np.clip(lum * 1.15, 0.45, 1.0) * tt
        # hot base: a gamma lift that keeps the licks and gaps (a blend towards white would flatten them)
        rgb = np.clip(rgb, 0, 1) ** (1 - float(cfg.get("heat", 0.8)) * np.clip((0.7 - hh) / 0.7, 0, 1))[..., None]
        a = a * (1 - 0.7 * np.clip((hh - 0.82) / 0.18, 0, 1))
        pre = np.concatenate([rgb * a[..., None], a[..., None]], -1)
        pre = np.stack([_blur(pre[..., k], 0.8) for k in range(4)], -1)
        al = pre[..., 3]
        # smoke wisps from the blurred silhouette, dragged up
        w = np.zeros((H, W), np.float32)
        base = _blur(al, 2.0)
        for k, (dy, r, g) in enumerate(((int(H * 0.14), 5.0, 0.30), (int(H * 0.28), 8.0, 0.22))):
            sh = np.roll(base, -dy, 0)
            sh[H - dy:] = 0
            sh = np.roll(sh, int(round(6 * np.sin(i * 0.37 + k * 2))), 1)
            nz = _blur(rng.random((H, W)).astype(np.float32), 5.0)
            nz = (nz - nz.min()) / max(nz.max() - nz.min(), 1e-6)
            w = np.maximum(w, _blur(sh, r) * g * (0.5 + nz))
        w = np.clip(w, 0, 0.4) * (1 - al)
        soot = np.array([0.20, 0.18, 0.17], np.float32)
        a_out = al + w
        rgb_out = (pre[..., :3] + soot * w[..., None]) / np.maximum(a_out[..., None], 1e-6)
        out[i, ..., :3] = np.clip(rgb_out, 0, 1)
        out[i, ..., 3] = np.clip(a_out, 0, 1)
    return _sway(out, h, cfg)


def luma_report(fr):
    """Alpha-weighted mean luma (0..255) of the flame body: lower half and upper half of its rows."""
    a = fr[..., 3]
    body = a > 0.6
    rows = np.nonzero(body.any((0, 2)))[0]
    mid = (rows.min() + rows.max()) // 2
    L = (fr[..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)) * 255
    low = body.copy()
    low[:, :mid + 1] = False
    up = body.copy()
    up[:, mid:] = False
    return float(L[low].mean()), float(L[up].mean())


def process(cfg, frames):
    n = cfg["n"]
    fr = frames
    if cfg["kind"] == "loop":
        fr = loopify(fr[-2 * n:], n)
    else:
        fr = fr[:n].copy()
    if cfg.get("bonfire"):
        fr = bonfire(fr, cfg)
        print("flame luma lower half %.0f, upper half %.0f (alpha > 0.6)" % luma_report(fr))
    if cfg.get("tail"):  # a flash must end empty, the sim stops while it is still bright
        k = cfg["tail"]
        fr[-k:, ..., 3] *= np.linspace(1, 0, k + 1)[1:].reshape(-1, 1, 1).astype(np.float32)
    if cfg["kind"] == "puff":  # a puff is born and dies empty, so the loop closes without a seam
        t = np.arange(n, dtype=np.float32)
        up = np.clip(t / 3, 0, 1)
        dn = np.clip((n - 1 - t) / 8, 0, 1)
        fr[..., 3] *= (up * dn * up * dn * (3 - 2 * up * dn)).reshape(-1, 1, 1)
    H = fr.shape[1]
    if cfg.get("vgrade"):
        # flames cool with height: a hot yellow-white root, orange body, dark red and soot-grey thin tips.
        # The rows come from the alpha of all frames together, so the grading does not jump between frames.
        a_all = fr[..., 3].max(0)
        rows = np.nonzero(a_all.max(1) > 0.25)[0]
        top, bot = rows.min(), rows.max()
        u = np.clip(1 - (np.arange(H) - top) / max(bot - top, 1), 0, 1).astype(np.float32).reshape(1, H, 1, 1)
        wr = np.clip((0.40 - u) / 0.40, 0, 1)
        wt = np.clip((u - 0.40) / 0.60, 0, 1)
        hot = np.array([1.0, 0.92, 0.62], np.float32)
        tip = np.array([0.34, 0.09, 0.03], np.float32)
        soot = np.array([0.07, 0.055, 0.05], np.float32)
        rgb = fr[..., :3]
        rgb = rgb * (1 - 0.9 * wr) + hot * 0.9 * wr
        rgb = rgb * (1 - 0.65 * wt) + tip * 0.65 * wt
        ws = wt * wt
        rgb = rgb * (1 - 0.7 * ws) + soot * 0.7 * ws
        fr[..., :3] = np.clip(rgb, 0, 1)
        fr[..., 3:] *= 1 - cfg["vgrade"] * wt
    if cfg.get("glow"):  # soft halo under sharp flame sheets: blur the premultiplied frame and put it behind
        from PIL import ImageFilter as IF
        for i in range(fr.shape[0]):
            pre = np.concatenate([fr[i, ..., :3] * fr[i, ..., 3:], fr[i, ..., 3:]], -1)
            ch = [np.asarray(Image.fromarray((pre[..., k] * 255).astype(np.uint8)).filter(IF.GaussianBlur(cfg["glow_r"])), np.float32) / 255 for k in range(4)]
            bl = np.stack(ch, -1) * cfg["glow"]
            a0 = fr[i, ..., 3:]
            o = pre + bl * (1 - a0)
            al = np.clip(o[..., 3:], 1e-6, 1)
            fr[i] = np.concatenate([np.clip(o[..., :3] / al, 0, 1), al], -1)
    wy, _ = window(H)
    if cfg.get("topramp"):  # the sim box ends in a straight cut near the top; fade it out more gently there
        z, f_ = cfg["topramp"]
        t = np.clip((np.arange(H) / (H - 1) - z) / (f_ - z), 0, 1)
        wy = np.minimum(wy, t * t * (3 - 2 * t))
    _, wx = window(fr.shape[2])
    fr = fr.copy()
    fr[..., 3] *= wy[None, :, None] * wx[None, None, :]
    if "amax" in cfg:  # cap the peak opacity (thinning smoke)
        pk = np.percentile(fr[..., 3], 99.9)
        fr[..., 3] *= cfg["amax"] / pk
    if cfg.get("desat"):  # pull chroma toward grey so the loam stays inside the brief's a*/b* band
        lum = fr[..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        fr[..., :3] = lum[..., None] + (fr[..., :3] - lum[..., None]) * (1 - cfg["desat"])
    if cfg.get("tgt_L"):  # gain on straight colour until the alpha-weighted mean L* hits the target
        lo, hi = 0.05, 8.0
        base = fr[..., :3].copy()
        for _ in range(30):
            g = (lo * hi) ** 0.5
            fr[..., :3] = np.clip(base * g, 0, 1)
            if mean_lab(fr)[0] < cfg["tgt_L"]:
                lo = g
            else:
                hi = g
    # fill colour under (almost) transparent pixels with the frame's mean colour
    for i in range(fr.shape[0]):
        a = fr[i, ..., 3:]
        mc = (fr[i, ..., :3] * a).sum((0, 1)) / max(a.sum(), 1e-9)
        t = np.clip(a / 0.03, 0, 1)
        fr[i, ..., :3] = fr[i, ..., :3] * t + mc * (1 - t)
    return fr


def pack(fr, cols, rows):
    n, H, W, _ = fr.shape
    img = np.zeros((rows * H, cols * W, 4), np.float32)
    for i in range(n):
        r, c = divmod(i, cols)
        img[r * H:(r + 1) * H, c * W:(c + 1) * W] = fr[i]
    return img


def save(img, path):
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)


def validate(name, cfg, fr):
    n, H, W, _ = fr.shape
    a = fr[..., 3]
    ring = max(2, H // 64)
    edge = max(a[:, :ring].max(), a[:, -ring:].max(), a[:, :, :ring].max(), a[:, :, -ring:].max())
    ys, xs = np.mgrid[0:H, 0:W]
    tot = a.sum((1, 2)) + 1e-9
    cx = ((a * xs).sum((1, 2)) / tot / W - 0.5)
    cy = ((a * ys).sum((1, 2)) / tot / H - 0.5)
    sel = tot > 0.01 * tot.max()
    lab = mean_lab(fr)
    ok_lab = True
    if cfg.get("lab"):
        ok_lab = cfg["lab"][0] <= lab[0] <= cfg["lab"][1]
    if cfg.get("ab"):
        ok_lab &= cfg["ab"][0][0] <= lab[1] <= cfg["ab"][0][1] and cfg["ab"][1][0] <= lab[2] <= cfg["ab"][1][1]
    print("%-18s edge_alpha=%.4f  |cx|max=%.3f cy mean=%.3f  mean Lab=(%.1f %.1f %.1f) %s  peak alpha=%.2f" % (
        name, edge, np.abs(cx[sel]).max(), cy[sel].mean(), lab[0], lab[1], lab[2],
        "OK" if ok_lab else "OUT-OF-RANGE", np.percentile(a, 99.9)))
    return edge == 0 and ok_lab


def _cells(fr, i, cm, cfg, rng_):
    H, W = fr.shape[1:3]
    pw = max(8, int(round(cfg["m"] * 100 / cm)))
    ph = max(8, int(round(pw * H / W)))
    im = Image.fromarray((fr[i] * 255).astype(np.uint8), "RGBA").resize((pw, ph), Image.LANCZOS)
    a = np.asarray(im, np.float32) / 255
    g = np.clip(GRASS + rng_.normal(0, 0.02, (ph, pw, 1)), 0, 1)
    return g * (1 - a[..., 3:]) + a[..., :3] * a[..., 3:]


def contact_strip(name, cfg, fr, out):
    """Frames played over grass at both zooms: row 1 at 7 cm/px, row 2 at 22 cm/px (a 3x
    nearest-neighbour copy of it follows so the far read can be judged at all)."""
    n = fr.shape[0]
    idx = np.linspace(0, n - 1, 10).astype(int)
    rng = np.random.default_rng(1)
    rows = [np.concatenate([_cells(fr, i, cm, cfg, rng) for i in idx], 1) for cm in CM_PX]
    W = rows[0].shape[1]
    far3 = np.kron(rows[1], np.ones((3, 3, 1), np.float32))
    pad = lambda r: np.pad(r, ((0, 0), (0, max(0, W - r.shape[1])), (0, 0)), constant_values=0.1)[:, :W]
    sheet = np.concatenate([pad(rows[0]), pad(rows[1]), pad(far3)], 0)
    Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8)).save(out)


def preview_gif(name, cfg, fr, out):
    """Playback over grass: left 7 cm/px (closest zoom), right 22 cm/px enlarged 3x (nearest)."""
    rng = np.random.default_rng(2)
    frames = []
    for i in list(range(fr.shape[0])) * (2 if cfg["kind"] in ("loop", "puff") else 1):
        a = _cells(fr, i, CM_PX[0], cfg, rng)
        b = np.kron(_cells(fr, i, CM_PX[1], cfg, rng), np.ones((3, 3, 1), np.float32))
        h = max(a.shape[0], b.shape[0])
        cols = [np.pad(c, ((0, h - c.shape[0]), (4, 4), (0, 0)), constant_values=0.1) for c in (a, b)]
        frames.append(Image.fromarray((np.concatenate(cols, 1) * 255).astype(np.uint8)))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=max(20, int(1000 / cfg["fps"])), loop=0)


def kenney_sparks(pack_dir, out):
    cells = []
    for i in range(1, 8):
        im = Image.open(os.path.join(pack_dir, "PNG (Transparent)", "trace_0%d.png" % i)).convert("RGBA").resize((256, 256), Image.LANCZOS)
        a = np.asarray(im, np.float32) / 255
        tint = np.array([255, 230, 176], np.float32) / 255  # brief: sparks #FFE6B0
        core = np.clip((a[..., 3:] - 0.6) / 0.4, 0, 1)
        rgb = tint * (1 - core) + core  # hot core goes white
        cells.append(np.concatenate([rgb, a[..., 3:]], -1))
    cells.append(np.zeros_like(cells[0]))
    img = pack(np.stack(cells), 4, 2)
    save(img, out)
    return np.stack(cells)


def main():
    root, outd, which = sys.argv[1:4]
    os.makedirs(outd, exist_ok=True)
    names = list(ATLAS) if which == "all" else which.split(",")
    for nm in names:
        if nm == "sparks":
            continue
        cfg = ATLAS[nm]
        fr = process(cfg, load(os.path.join(root, cfg["src"])))
        validate(nm, cfg, fr)
        save(pack(fr, cfg["cols"], cfg["rows"]), os.path.join(outd, nm + ".png"))
        contact_strip(nm, cfg, fr, os.path.join(outd, "strip_" + nm + ".png"))
        preview_gif(nm, cfg, fr, os.path.join(outd, "preview_" + nm + ".gif"))
    if "--kenney" in sys.argv:
        kenney_sparks(sys.argv[sys.argv.index("--kenney") + 1], os.path.join(outd, "armour_sparks.png"))


if __name__ == "__main__":
    main()
