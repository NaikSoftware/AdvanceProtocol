"""Stage 3: paint the atlas from the baked maps (plain Python: numpy + PIL).

    python3 -I paint.py <unit>

Writes <work>/albedo.png (sRGB), normal.png and orm.png (R occlusion, G roughness, B metallic).
Everything on the body is a function of the baked object-space position, so camouflage blocks
keep their real size across UV islands. Lengths here are metres (model units x 8).
The tread strip, the wheel and sprocket cells are authored, not baked (lib.py layout).

Paint. No `paint` key in units.json: the digital camouflage below (national set 0). With
`"paint": {"scheme": "plain", "base": [r, g, b]}` the body is one tone (sRGB 0..255), still run through the
same occlusion, edge wear, streaks, dust, mud and roof darkening, plus a faint low-frequency mottle
(`mottle`, default 0.05) so it does not read as flat plastic. The same dict may carry the camo knobs
(`roof_dark`, `roof_cool`, `dust`, `wheel_mud`) to tune one palette. The generated texture never
colours the body; its luminance only finds sight glass and is normalised per model (plain scheme), so a
pale or dark Tripo texture cannot shift what counts as glass.

Painted metal (same dict, defaults fit every set): `paint_rough`, `rough_var`, `edge_polish`,
`bare_rough`, `bare_metal`, `bare_c`, `oil_dark`, `oil_gloss`, `normal_gain`, `pin_metal`.
Camo scheme only: `roof_fade` (up-facing faces faded to grey of the same value, for the contrast
gate), with its own defaults for `roof_dark`, `roof_cool` and `dust`.
"""
import sys, os
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

cfg = lib.load(sys.argv[1])
N = lib.ATLAS
d = np.load(os.path.join(cfg["work"], "maps.npz"))


def lin(*c):
    """sRGB 0..255 -> linear."""
    a = np.array(c, np.float32) / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def hash3(i, j, k, seed):
    h = np.sin(i * 12.9898 + j * 78.233 + k * 37.719 + seed * 17.13) * 43758.5453
    return h - np.floor(h)


def vnoise(p, scale, seed):
    """3D value noise, p in metres, feature size `scale` metres."""
    q = p / scale
    i = np.floor(q); f = q - i
    f = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hash3(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def fbm(p, scales, seed):
    return sum(w * vnoise(p, s, seed + n) for n, (s, w) in enumerate(scales))


P = d["pos"] * lib.TILE_M                     # metres; X lateral, Y forward, Z up
nz = d["nrm"][..., 2]
ao = d["ao"]
pt = d["point"]

# ---- digital camouflage ----------------------------------------------------------------------
# Four Korean colours, desaturated. Pixel blocks of `block` m; patches from noise at block
# centres, so every edge is a block edge. Three independent layers so colours touch in any order
# instead of nesting in rings.
PN = cfg.get("paint")
plain = bool(PN) and PN.get("scheme") == "plain"
C = {**cfg.get("camo", {}), **(PN or {})}
block = C.get("block_m", 0.16)
# khaki stays a mid-tone: brighter blocks plus dust read as pale glyphs on the hull sides
olive, khaki = lin(86, 90, 64), lin(*C.get("khaki", (124, 117, 90)))
brown, black = lin(94, 79, 61), lin(44, 44, 40)
Q = (np.floor(P / block) + 0.5) * block
jit = (hash3(np.floor(P[..., 0] / block), np.floor(P[..., 1] / block), np.floor(P[..., 2] / block), 5) - 0.5) * 0.18
n1 = fbm(Q, [(1.8, 0.65), (0.7, 0.35)], 11) + jit
n2 = fbm(Q, [(1.5, 0.6), (0.6, 0.4)], 23) + jit
n3 = fbm(Q, [(1.2, 0.6), (0.5, 0.4)], 37) + jit
col = np.where((n1 > np.quantile(n1, C.get("khaki_q", 0.68)))[..., None], khaki, olive)
col = np.where((n2 > np.quantile(n2, 0.72))[..., None], brown, col)
# from above the black patches read as soot at the far zoom: up-facing ones lose some contrast
roof = smooth(0.35, 0.8, nz)[..., None]
black_c = black + (olive - black) * C.get("roof_black_lift", 0.3) * roof
col = np.where((n3 > np.quantile(n3, 0.88))[..., None], black_c, col)
col = col * (1.0 + (hash3(*np.floor(P / block).transpose(2, 0, 1), 9)[..., None] - 0.5) * 0.06)
if not plain:
    # Contrast gate (docs/art/unit-models-research.md §5): from above the tops are most of the
    # tank, and an olive top sits at the grass's hue (b* +12 against +16..+22 on the sunny maps).
    # Tops are sun-faded towards a neutral grey of the same value (`roof_fade`), lighter than
    # before (no roof darkening) and less dusty; the sides keep the olive, and the blocks stay
    # darker than the faded olive, so the pattern still reads.
    fade = C.get("roof_fade", 1.0) * roof
    col = col * (1 - fade) + (col @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None] * fade
    C = {"roof_dark": -0.1, "roof_cool": (-0.08, 0.02, 0.28), "dust": 0.1, **C}
if plain:
    # one tone: sand etc. Blocks are gone, a soft mottle (metres-scale noise, no block edges) stays
    olive = lin(*PN["base"])
    mot = fbm(P, [(1.6, 0.6), (0.5, 0.4)], 101) - 0.5
    col = olive * (1.0 + mot[..., None] * 2.0 * C.get("mottle", 0.05)) * np.ones_like(col)

rough = np.full((N, N), C.get("rough", 0.78) if plain else 0.70, np.float32)
metal = np.zeros((N, N), np.float32)
# Painted armour, not plastic: matte paint (`paint_rough` on the camo scheme) whose sheen varies
# over metres — chalky faded patches and fresher ones (`rough_var`) — so no face carries one even highlight.
if not plain:
    rough[:] = C.get("paint_rough", 0.74)
rough = rough + C.get("rough_var", 0.06) * 2 * (fbm(P, [(2.5, 0.6), (0.8, 0.4)], 91) - 0.5)

# Generated colour: keep only what it says is near-black on the roof items (sight glass). It
# also paints whole parts dark (the gun), so the barrel and anything low are excluded.
tip = cfg["spec"]["barrel"] * lib.TILE_M
az = lib.m_len(cfg, cfg["gun"]["axis_h"]) * lib.TILE_M
rad = np.hypot(P[..., 0], P[..., 2] - az)
on_gun = (rad < 0.4) & (P[..., 1] > lib.m_long(cfg, cfg["gun"]["start_long"]) * lib.TILE_M)
src_l = (d["src"] @ np.array([0.2126, 0.7152, 0.0722], np.float32)) if "src" in d else np.ones((N, N))
if plain and "src" in d:
    # per-model: relative to the body's own median, so the threshold means "a third of the typical
    # texture value" for a pale or a dark source alike (0.035 / 0.012 of an olive texture of ~0.17)
    src_l = src_l / max(float(np.median(src_l[d["cov"] > 0.5])), 1e-4) * 0.17
glass = smooth(0.035, 0.012, src_l) * (d["cov"] > 0.5) * (P[..., 2] > cfg.get("glass_above_m", 2.35)) * ~on_gun
col = col * (1 - glass[..., None]) + lin(20, 22, 24) * glass[..., None]
rough = rough * (1 - glass) + 0.25 * glass

# ---- panel lines, edges, occlusion ----------------------------------------------------------
cav = np.clip((0.5 - pt) * 14, 0, 1)
edge = np.clip((pt - 0.5) * 14, 0, 1)
wear_n = fbm(P, [(0.25, 0.6), (0.08, 0.4)], 51)
chip = edge * smooth(0.45, 0.65, wear_n)
col = col * (1 - 0.55 * cav[..., None])
col = col * (1 - 0.45 * chip[..., None]) + (col * 1.7 + lin(70, 68, 62) * 0.3) * 0.45 * chip[..., None]
# Wear sits on edge lines. On small fragmented islands the baked edge mask covers whole patches;
# bare steel and polish there would read as bright blobs, so they keep to texels whose 15 cm
# neighbourhood is mostly not edge.
def box(a, k):
    """Mean over a (2k+1)^2 texel square."""
    ii = np.pad(a.astype(np.float32), k + 1, mode="edge").cumsum(0).cumsum(1)
    return ((ii[2 * k + 1:, 2 * k + 1:] - ii[:-2 * k - 1, 2 * k + 1:] - ii[2 * k + 1:, :-2 * k - 1]
             + ii[:-2 * k - 1, :-2 * k - 1]) / (2 * k + 1) ** 2)[:N, :N]


dens = box(edge > 0.3, 7)
line = smooth(0.5, 0.3, dens)
bare = chip * smooth(0.62, 0.75, wear_n) * line
col = col * (1 - bare[..., None]) + lin(*C.get("bare_c", (100, 98, 94))) * bare[..., None]
if not plain:
    # those edge-filled patches carry a dark camo block instead, matte: grey speckled metal there
    # read as blotches, plain olive as a hole in the pattern
    dark = smooth(0.45, 0.6, dens) * smooth(0.58, 0.72, wear_n)
    col = col * (1 - dark[..., None]) + black * dark[..., None]
# Rubbed edges: a satin band ~10-12 cm wide (2 px at 7 cm/px) along convex edges that face up,
# where crews, boots and rain rub the paint smooth; flat faces and side edges stay matte. Only
# where worn through is it bare steel.
rub = np.clip(box((edge * line) > 0.3, 5) * 6, 0, 1) * smooth(0.4, 0.6, nz) * smooth(0.3, 0.5, wear_n)
rough = rough - C.get("edge_polish", 0.24) * np.maximum(rub, chip * line)
rough = rough * (1 - bare) + C.get("bare_rough", 0.45) * bare
metal = metal + C.get("bare_metal", 1.0) * bare
col = col * (0.5 + 0.5 * ao[..., None])
if plain:
    # a single tone would read as resin: grime in recesses and panel joins, and large soft fade
    # blotches that mostly show on the up-facing tops
    rec = smooth(0.0, 0.4, 1 - ao)
    col = col * (1 - C.get("grime", 0.2) * rec[..., None])
    blot = fbm(P, [(2.5, 0.6), (1.0, 0.4)], 131) - 0.5
    col = col * (1 + C.get("blotch", 0.06) * 2 * blot[..., None] * (0.4 + 0.6 * roof))

# ---- streaks, dust, mud ---------------------------------------------------------------------
side = smooth(0.6, 0.2, np.abs(nz))
streak = fbm(P * np.array([1.0, 1.0, 0.08]), [(0.12, 0.7), (0.05, 0.3)], 61) - 0.5
col = col * (1 + side[..., None] * streak[..., None] * 0.22)
h = P[..., 2]
dust_n = fbm(P, [(0.9, 0.5), (0.25, 0.3), (0.06, 0.2)], 71)
up = np.clip(nz, 0, 1) ** 2
dust = np.clip(smooth(1.5, 0.3, h) * 0.8 + up * 0.35 * dust_n + up * (1 - ao) * 0.6, 0, 1)
dust = dust * smooth(0.25, 0.65, dust_n + 0.15)
dust_c = lin(152, 140, 116)
dmix = C.get("dust", 0.42)              # from above the roof is most of the tank: heavy dust reads washed out
dust_body = olive if plain else dust_c      # low dust must not lighten a sand body
col = col * (1 - dmix * dust[..., None]) + dust_body * dmix * dust[..., None]
mud = smooth(0.8, 0.25, h) * smooth(0.5, 0.7, fbm(P, [(0.3, 0.6), (0.08, 0.4)], 81))
col = col * (1 - 0.7 * mud[..., None]) + lin(74, 62, 48) * 0.7 * mud[..., None]
if plain:
    # splashed mud: a brown-grey ramp, 0 at `mud_h` m above the ground to `mud_max` darker at the bottom of skirts and sides
    mf = C.get("mud_from", cfg["cut"]["below_skirt_h"] * cfg["k"] * lib.TILE_M)   # skirt hem, metres
    ramp = np.clip(1 - (h - mf) / C.get("mud_h", 0.6), 0, 1)
    mx = C.get("mud_max", 0.85)
    col = col * (1 - mx * ramp[..., None]) + lin(92, 76, 56) * (mx * ramp)[..., None]
rough = np.clip(rough + 0.2 * dust + 0.1 * mud, 0, 1)
# Oil and fuel on the rear deck: darker, half-gloss patches, the one smooth area on a matte tank.
# Deck level only (hull height): a casemate roof at the rear is not an engine deck.
oil = roof[..., 0] * smooth(0.5, -1.5, P[..., 1]) * (h < cfg["spec"]["hull"][1] * lib.TILE_M + 0.15) \
    * smooth(0.58, 0.7, fbm(P, [(0.6, 0.6), (0.2, 0.4)], 95))
col = col * (1 - C.get("oil_dark", 0.15) * oil[..., None])
rough = rough - C.get("oil_gloss", 0.15) * oil

# ---- muzzle soot ----------------------------------------------------------------------------
soot = smooth(tip - 0.45, tip - 0.05, P[..., 1]) * (rad < 0.4)
col = col * (1 - 0.85 * soot[..., None])

# Roofs darker and a little cooler than the grass they sit on, so the turret outline holds at
# 22 cm/px (0.42 in linear is ~22 % in screen value); the sides keep their value.
col = col * (1 - C.get("roof_dark", 0.42) * roof) * (1 + roof * np.array(C.get("roof_cool", (-0.06, 0.0, 0.08)), np.float32))
if plain:
    # texels the occlusion map leaves open must not fall below a fraction of the base tone: the
    # baked point/cavity term turns scan noise on flat tops into dark flecks. Sight glass and the barrel are exempt.
    free = (ao > 0.85) & (glass < 0.5) & ~on_gun
    col = np.where(free[..., None], np.maximum(col, olive * C.get("floor", 0.75) * (1 - 0.6 * ramp)[..., None]), col)   # mud lowers the floor
    col = np.where(on_gun[..., None], col * C.get("gun_dark", 0.8), col)
# Engine-deck louvres (units.json `louvres`, MODEL metres): rows of dark slots across the hull on
# the up-facing deck, two grilles either side of a solid centre strip. Texture only: from above
# they mark the deck as an engine deck without a triangle.
lv = cfg.get("louvres")
if lv:
    ax = np.abs(P[..., 0])
    on = (P[..., 1] > lv["y"][0]) & (P[..., 1] < lv["y"][1]) & (ax < lv["x"]) & (ax > lv.get("centre", 0.12)) \
        & (roof[..., 0] > 0.5) & (P[..., 2] < lv.get("below_m", 9.0))
    slot = ((P[..., 1] - lv["y"][0]) / lv.get("period", 0.14)) % 1.0 < lv.get("slot", 0.45)
    col = col * (1 - 0.5 * (on & slot)[..., None]) * (1 - 0.12 * on[..., None])
    rough = np.where(on & slot, 0.9, rough)

# A shrunk turret (units.json turret) is darker again than the deck around it: small and low, it
# would otherwise dissolve into the hull at the far zoom.
t = cfg.get("turret")
if t:
    tc = t["tc"]
    ty = [lib.m_long(cfg, tc + (L - tc) * t["scale_long"] + t.get("shift_long", 0.0)) * lib.TILE_M for L in t["long"]]
    on_t = (P[..., 1] > ty[0]) & (P[..., 1] < ty[1]) & (np.abs(P[..., 0]) < lib.m_len(cfg, t["lat"] * t.get("scale_lat", 1.0)) * lib.TILE_M) \
        & (P[..., 2] > lib.m_len(cfg, t["base_h"]) * lib.TILE_M + 0.05) & ~on_gun
    col = col * (1 - t.get("dark", 0.25) * on_t[..., None])

# Baked relief a little deeper (`normal_gain`): bolts, panel joints and bevels catch the light at
# 7 cm/px, where a 1:1 bake reads as a moulded surface.
normal = d["normal"] * 2 - 1
normal[..., :2] *= C.get("normal_gain", 1.6)
normal = normal / np.linalg.norm(normal, axis=-1, keepdims=True) * 0.5 + 0.5
occl = ao.copy()

# ---- tread strip: one 2 m period, 12 links ----------------------------------------------------
S = int(N * lib.STRIP)
u = (np.arange(N) + 0.5) / N * lib.TREAD_PERIOD * lib.TILE_M       # metres along the track
v = (np.arange(S) + 0.5) / S                                       # 0 inner edge .. 1 outer edge
U, V = np.meshgrid(u, v)
links = cfg.get("tread_links", 12)
ph = (U / (lib.TREAD_PERIOD * lib.TILE_M) * links) % 1.0             # phase within a link
across = np.abs(V - 0.5) * 2                                        # 0 centre .. 1 edge


def periodic_noise(shape, cut, seed):
    """Noise that tiles in u (the strip repeats), low-passed to `cut` cycles."""
    r = np.random.default_rng(seed).standard_normal(shape)
    F = np.fft.fft2(r)
    fy = np.fft.fftfreq(shape[0])[:, None] * shape[0]; fx = np.fft.fftfreq(shape[1])[None, :] * shape[1] / 16
    F *= np.exp(-(fx ** 2 + fy ** 2) / (2 * cut ** 2))
    n = np.real(np.fft.ifft2(F)); n = (n - n.mean()) / (n.std() + 1e-9)
    return n


pad = (ph > 0.12) & (ph < 0.86) & (across > 0.10) & (across < 0.80)
conn = across >= 0.84
horn = (across <= 0.07) & (ph > 0.3) & (ph < 0.7)
height = np.where(pad, 1.0, 0.0) + np.where(conn, 0.55 + 0.25 * ((ph > 0.4) & (ph < 0.6)), 0.0) + np.where(horn, 0.8, 0.0)
tn = periodic_noise((S, N), 6, 3)
tcol = np.where(pad[..., None], lin(40, 39, 37), lin(70, 68, 64))
tcol = np.where(((~pad) & (~conn) & (~horn))[..., None], lin(22, 20, 18), tcol)
tdust = np.clip(0.45 + 0.25 * tn, 0, 0.8)
tcol = tcol * (1 - tdust[..., None] * 0.6) + dust_c * tdust[..., None] * 0.6 * np.where(pad | conn | horn, 1.0, 0.5)[..., None]
col[:S] = tcol
# pins, end connectors and guide horns are steel polished by the sprocket and the wheels
rough[:S] = np.where(pad, 0.88, np.where(conn | horn, 0.42, 0.62)) + 0.08 * tdust
metal[:S] = np.where(pad, 0.0, np.where(conn | horn, C.get("pin_metal", 0.8), 0.35))
occl[:S] = np.where(pad | conn | horn, 1.0, 0.55)


def height_normal(hm, strength, wrap):
    """Tangent-space normal (0..1, OpenGL Y up = towards PNG row 0) from a height map."""
    if wrap:
        gx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) * 0.5
    else:
        gx = np.gradient(hm, axis=1)
    gy = np.gradient(hm, axis=0)
    n = np.stack([-gx * strength, gy * strength, np.ones_like(hm)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


blur = lambda a: (a + np.roll(a, 1, 1) + np.roll(a, -1, 1) + np.roll(a, 1, 0) + np.roll(a, -1, 0)) / 5
normal[:S] = height_normal(blur(blur(height)), 3.0, True)

# ---- right column: wheel, sprocket ----------------------------------------------------------
c0 = int(lib.COL_U * N)
col[S:, c0:] = olive * 0.6
rough[S:, c0:] = 0.8; metal[S:, c0:] = 0.0; occl[S:, c0:] = 1.0
normal[S:, c0:] = (0.5, 0.5, 1.0)


def cell(name):
    r0, rows = lib.CELLS[name]
    return slice(r0, r0 + rows), slice(c0, c0 + lib.CELL)


def disc_coords(rows):
    y, x = np.mgrid[0:rows, 0:lib.CELL] + 0.5
    x = x / lib.CELL * 2 - 1; y = y / rows * 2 - 1
    return np.hypot(x, y), np.arctan2(y, x)


# Road wheel / idler face: rubber tyre, steel lip, painted dished disc, bolt ring, hub.
R, A = disc_coords(128)
wc = np.broadcast_to(olive * 0.95, (128, 128, 3)).copy()
wh = np.zeros((128, 128))
tyre = R > 0.80
wc[tyre] = lin(38, 37, 35); wh[tyre] = 0.6
lip = (R > 0.74) & (R <= 0.80); wc[lip] = lin(80, 80, 74); wh[lip] = 0.8
dish = (R > 0.30) & (R <= 0.74); wh[dish] = 0.3 + 0.4 * (R[dish] - 0.30) / 0.44
bolts = (np.abs(R - 0.36) < 0.035) & (np.cos(A * 8) > 0.93); wc[bolts] = lin(60, 60, 56); wh[bolts] = 0.6
hub = R <= 0.30; wc[hub] = lin(66, 66, 60); wh[hub] = 0.5 - 0.3 * (R[hub] < 0.12)
wn = np.random.default_rng(4).standard_normal((128, 128))
wd = np.clip(0.55 + 0.15 * wn - 0.3 * (R < 0.3), 0, 0.85)      # wheels are the dustiest part
wc = wc * (1 - wd[..., None] * 0.6) + dust_c * wd[..., None] * 0.6
ys, xs = cell("wheel")
col[ys, xs] = wc * C.get("wheel_mud", 0.62)   # mud-dark: beige dust read near-white at the close zoom
normal[ys, xs] = height_normal(blur(wh), 4.0, False)
rough[ys, xs] = np.where(tyre, 0.9, 0.75)
occl[ys, xs] = 1 - 0.4 * (R > 0.98)

# Sprocket: toothed steel ring, spoked disc, hub.
teeth = 13
sc = np.broadcast_to(olive * 0.85, (128, 128, 3)).copy()
sh = np.zeros((128, 128))
ring = (R > 0.72) & (R < 0.86 + 0.12 * (np.cos(A * teeth) > 0.2)); sc[ring] = lin(76, 74, 68); sh[ring] = 0.8
holes = (R > 0.38) & (R < 0.64) & (np.cos(A * 6) > 0.55); sc[holes] = lin(16, 15, 14); sh[holes] = -0.6
hubs = R <= 0.26; sc[hubs] = lin(62, 62, 58); sh[hubs] = 0.5
sd = np.clip(0.5 + 0.15 * np.random.default_rng(6).standard_normal((128, 128)), 0, 0.8)
sc = sc * (1 - sd[..., None] * 0.5) + dust_c * sd[..., None] * 0.5
ys, xs = cell("sprocket")
col[ys, xs] = sc * C.get("wheel_mud", 0.62)
normal[ys, xs] = height_normal(blur(sh), 4.0, False)
rough[ys, xs] = np.where(ring, 0.42, 0.78); metal[ys, xs] = np.where(ring, C.get("pin_metal", 0.8), 0.0)

def push_pull(img, known):
    """Fill unknown texels with the average of known ones nearby, coarse to fine, so mip levels
    never mix the gap colour into island edges."""
    if min(img.shape[:2]) <= 1 or known.all():
        return np.where(known[..., None], img, img[known].mean(0) if known.any() else img)
    h2, w2 = img.shape[0] // 2, img.shape[1] // 2
    k = known[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2).astype(np.float32)
    s = (img[:h2 * 2, :w2 * 2] * known[:h2 * 2, :w2 * 2, None]).reshape(h2, 2, w2, 2, -1)
    ks = k.sum((1, 3))
    small = push_pull(s.sum((1, 3)) / np.maximum(ks, 1)[..., None], ks > 0)
    up = np.repeat(np.repeat(small, 2, 0), 2, 1)
    up = np.pad(up, ((0, img.shape[0] - up.shape[0]), (0, img.shape[1] - up.shape[1]), (0, 0)), mode="edge")  # odd sizes
    return np.where(known[..., None], img, up)


# Body region only: the strip and the column are fully authored.
known = np.linalg.norm(d["pos"], axis=-1) > 1e-6
body = (slice(S, N), slice(0, c0))
orm = np.stack([np.clip(occl, 0, 1), np.clip(rough, 0.05, 1), np.clip(metal, 0, 1)], -1)
for a in (col, normal, orm):
    a[body] = push_pull(a[body], known[body])

out = cfg["work"]
Image.fromarray((srgb(col) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "albedo.png"))
Image.fromarray((np.clip(normal, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "normal.png"))
Image.fromarray((orm * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "orm.png"))
print("PAINT done")
