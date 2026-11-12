"""Check an exported unit GLB against the asset contract (docs/art-direction.md, Unit models).
Reads the file itself, never Blender's numbers. Exit 1 on any failure.

    python3 -I verify_glb.py <unit>
"""
import json, struct, sys, os
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

cfg = lib.load(sys.argv[1])
path = os.path.join(lib.REPO, "assets", "units", cfg["out"] + ".glb")
data = open(path, "rb").read()
off, g, binc = 12, None, None
while off < len(data):
    clen, ctype = struct.unpack_from("<II", data, off)
    if ctype == 0x4E4F534A:
        g = json.loads(data[off + 8:off + 8 + clen])
    elif ctype == 0x004E4942:
        binc = data[off + 8:off + 8 + clen]
    off += 8 + clen

NC = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NN = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def acc(i):
    a = g["accessors"][i]; bv = g["bufferViews"][a["bufferView"]]
    dt = NC[a["componentType"]]; n = NN[a["type"]]
    stride = bv.get("byteStride", 0) or np.dtype(dt).itemsize * n
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    raw = np.frombuffer(binc, np.uint8, count=stride * (a["count"] - 1) + np.dtype(dt).itemsize * n, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, (a["count"], np.dtype(dt).itemsize * n), (stride, 1))
    out = np.frombuffer(rows.copy().tobytes(), dt).reshape(a["count"], n).astype(np.float64)
    if a.get("normalized"):
        out /= np.iinfo(dt).max
    return out


fails = []
def check(ok, msg):
    print(("ok   " if ok else "FAIL ") + msg)
    if not ok:
        fails.append(msg)


prims = [p for m in g["meshes"] for p in m["primitives"]]
check(len(prims) == 1, f"one primitive ({len(prims)})")
check(len(g.get("materials", [])) == 1, f"one material ({len(g.get('materials', []))})")
check(not [n for n in g["nodes"] if {"translation", "rotation", "scale", "matrix"} & n.keys()], "no node transforms")
at = prims[0]["attributes"]
check(sorted(k for k in at if k.startswith("COLOR")) == ["COLOR_0"], f"only COLOR_0 ({sorted(at)})")
for need in ("NORMAL", "TANGENT", "TEXCOORD_0", "TEXCOORD_1"):
    check(need in at, f"has {need}")
pos = acc(at["POSITION"]); col4 = acc(at["COLOR_0"]); col = col4[:, :3]; uv2 = acc(at["TEXCOORD_1"])
tris = g["accessors"][prims[0]["indices"]]["count"] // 3
check(3000 <= tris <= 4500, f"triangles {tris} in 3000..4500")
check(abs(pos[:, 1].min()) < 1e-4, f"y_min {pos[:, 1].min():.6f} == 0")

spec = cfg["spec"]
gun = (np.abs(pos[:, 0]) < 0.06) & (pos[:, 2] < -spec["hull"][2] / 2 - 0.005)
hull = pos[~gun & (col[:, 1] < 0.5) & (col[:, 2] < 0.5)]
hx = hull[:, 0].max() - hull[:, 0].min(); hz = hull[:, 2].max() - hull[:, 2].min()
cxz = (hull[:, 0].max() + hull[:, 0].min()) / 2, (hull[:, 2].max() + hull[:, 2].min()) / 2
print(f"     hull X {hx:.4f} (spec {spec['hull'][0]}), Z {hz:.4f} (spec {spec['hull'][2]}), "
      f"height {pos[:, 1].max():.4f}, centre x {cxz[0]:+.4f} z {cxz[1]:+.4f}")
check(abs(cxz[0]) < 0.012 and abs(cxz[1]) < 0.012, "hull footprint centred on the origin")
check(hx <= spec["hull"][0] + 0.01 and hz <= spec["hull"][2] + 0.01, "hull inside the spec box")
tip = pos[np.argmin(pos[:, 2])]
print(f"     muzzle vertex {tip.round(4).tolist()} (spec z {-spec['barrel']}, y {spec['hull'][1] + 0.05:.3f})")
check(abs(tip[0]) < 0.03 and abs(tip[2] + spec["barrel"]) < 0.01, "front is -Z, muzzle at the spec length")
row = lib.set_row(cfg)
if cfg.get("out", "").startswith("set"):
    check(row is not None, "a set model has its _SET_SPECS row")
if row:
    # the game reads the set's row for this model: it must describe the model as built
    check(abs(hx - row["hull"][0]) <= 0.002 and abs(hz - row["hull"][2]) <= 0.002, f"_SET_SPECS hull {row['hull'][0]} x {row['hull'][2]} matches the model ({hx:.4f} x {hz:.4f})")
    check(abs(tip[2] + row["barrel"]) < 0.01 and abs(tip[1] - (row["hull"][1] + 0.05)) < 0.005,
          f"_SET_SPECS barrel {row['barrel']} and bore height {row['hull'][1] + 0.05:.3f} match the muzzle vertex {tip.round(4).tolist()}")

trk = col[:, 1] > 0.5; whl = col[:, 2] > 0.5
other = ~(trk | whl)

# Beyond the ends of the track loop the body is the bow and the rear plate. Nothing there may
# hang below the hull bottom: the skirts over the loop, and at each end the bottom edge measured
# on the source (units.json ends_bottom_h, [rear, front], SOURCE heights) — a post, hitch or
# mud flap reaching down past it fails.
z0, z1 = pos[trk, 2].min(), pos[trk, 2].max()
body = other & ~gun
floor = pos[body & (pos[:, 2] >= z0) & (pos[:, 2] <= z1), 1].min()
ends = cfg.get("ends_bottom_h")
check(ends is not None, "units.json has ends_bottom_h")
for name, end, h in (("rear", body & (pos[:, 2] > z1), (ends or [0, 0])[0]), ("bow", body & (pos[:, 2] < z0), (ends or [0, 0])[1])):
    if end.any():
        lim = max(floor, h * cfg["k"]) - 0.004
        check(pos[end, 1].min() >= lim, f"{name}: nothing below the hull bottom ({pos[end, 1].min():.4f} >= {lim:.4f})")
print(f"     verts: track {trk.sum()} wheel {whl.sum()} other {other.sum()}")
check(trk.any() and whl.any(), "track and wheel masks present")
# owners are told apart by the HP bar, not the model: no owner-colour mask anywhere
check(col[:, 0].max() < 0.5, "no owner marking (COLOR_0 R is 0)")
u, v = uv2[trk, 0], uv2[trk, 1]
print(f"     track UV2 u {u.min():.4f}..{u.max():.4f}  v {v.min():.4f}..{v.max():.4f}")
check(u.min() > -1e-4 and v.min() > -1e-4 and v.max() < 1 + 1e-4, "track UV2 v in 0..1, u from 0")
check(abs((u.max() / lib.TREAD_PERIOD) - round(u.max() / lib.TREAD_PERIOD)) < 1e-3, "track loop is whole tread periods")
# bottom run (lowest track verts): u must grow towards the front (-Z) so travel moves it rearwards
low = trk & (pos[:, 1] < 0.003)
lz, lu = pos[low, 2], uv2[low, 0]
check(np.corrcoef(lz, lu)[0, 1] < -0.9, f"bottom run u grows towards the front (corr {np.corrcoef(lz, lu)[0, 1]:.3f})")
d = np.hypot(pos[whl, 1] - uv2[whl, 0], pos[whl, 2] - uv2[whl, 1])
print(f"     wheel vertex distance from axle {d.min():.4f}..{d.max():.4f}; axle heights {np.unique(uv2[whl, 0].round(4)).tolist()}")
check(d.max() < 0.06, "wheel UV2 is the axle centre (every wheel vertex within a radius of it)")
# every wheel turns at travel / its own radius: alpha carries the rate relative to the road wheels
check(col4.shape[1] == 4, "COLOR_0 has alpha")
if col4.shape[1] == 4:
    rate = 2.0 * col4[whl, 3]
    road_r = cfg["gear"]["road"]["r"] * cfg["k"]
    err = np.abs(rate * d - road_r).max()        # every wheel vertex sits on its rim
    check(err < 0.002, f"wheel spin rate x wheel radius == road wheel radius (worst {err:.4f})")
# the game turns wheels by travel / _SPECS.wheel, so that number must be the road wheels' radius
road = cfg["gear"]["road"]["r"] * cfg["k"]
check(abs(road - (row["wheel"] if row else spec["wheel"])) <= 0.002, f"{'_SET_SPECS' if row else '_SPECS'} wheel {row['wheel'] if row else spec['wheel']} matches road wheel radius {road:.4f} (±0.002)")
check(np.abs(uv2[other]).max() < 1e-5, "UV2 is (0, 0) off tracks and wheels")
img = {i["name"] if "name" in i else i.get("uri") for i in g.get("images", [])}
check(len(g.get("images", [])) == 3, f"three textures embedded ({img})")
sys.exit(1 if fails else 0)
