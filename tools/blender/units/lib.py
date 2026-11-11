"""Shared config, frames and atlas layout for the unit pipeline (Blender and plain Python).

Frames. SOURCE is the generated GLB as imported: long axis on cfg["fwd"], lateral the other
horizontal axis, `h` the height above its lowest vertex. MODEL is Blender after prep: front along
+Y (glTF/Godot -Z), X lateral, Z up, ground at 0, hull footprint centred on the origin, 1 unit =
1 tile = 8 m. Godot reads MODEL as (X, Z, -Y).

Atlas (1024², one material). PNG row 0 is the top, which is Godot v = 0 and Blender v = 1:
  rows    0..63   tread strip, full width: one 0.25-unit (2 m) tread period, tiles in u
  column  u >= COL_U, below the strip: road-wheel face, sprocket face
  the rest: baked body islands
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCRATCH = os.path.expanduser("~/.cache/ap-scratch/units/pipe")

TILE_M = 8.0
ATLAS = 1024
STRIP = 1.0 / 16.0        # tread strip height, fraction of the atlas
TREAD_PERIOD = 0.25       # model units per tread repeat (2 m)
COL_U = 0.875             # body islands live left of this; gear cells right of it
CELL = 128                # px per gear cell
# Cells in the right column, as (row0, rows) in PNG pixels.
CELLS = {"wheel": (64, 128), "sprocket": (192, 128)}


def load(name):
    with open(os.path.join(HERE, "units.json")) as f:
        cfg = json.load(f)[name]
    cfg["name"] = name
    cfg.setdefault("out", name)  # path under assets/units/ without .glb; sets write set2/<slug>
    cfg["source"] = os.path.expanduser(cfg["source"])
    cfg["spec"] = spec(cfg["type_id"])
    lo, hi = cfg["hull_long"]
    sx, sz = cfg["spec"]["hull"][0], cfg["spec"]["hull"][2]
    # Uniform fit: the tighter of hull width and hull length governs.
    cfg["k"] = min(sx / (2.0 * cfg["hull_lat"]), sz / (hi - lo))
    cfg["long_c"] = 0.5 * (lo + hi)
    t = cfg.get("turret")
    if t:
        # prep.py shrinks the turret about its centre and lowers it onto its ring, and moves the
        # gun with it; every stage reads the moved gun from here
        g = cfg["gun"]
        t["axis_h0"] = g["axis_h"]
        # scaled about the box centre, or about its front ("anchor": "front") to cut a bustle
        tc = t["long"][1] if t.get("anchor") == "front" else 0.5 * (t["long"][0] + t["long"][1])
        t["tc"] = tc
        # shift_long moves the whole turret (and its gun) along the hull, + towards the bow
        t["dlong"] = tc + (t["long"][1] - tc) * t["scale_long"] - t["long"][1] + t.get("shift_long", 0.0)
        t["drop"] = (g["axis_h"] - t["base_h"]) * (1.0 - t["scale_h"])
        g["start_long"] += t["dlong"]
        g["axis_h"] -= t["drop"]
        g["profile"] = [[L + t["dlong"], r] for L, r in g["profile"]]
    cfg["work"] = os.path.join(SCRATCH, name)
    os.makedirs(cfg["work"], exist_ok=True)
    return cfg


def spec(type_id):
    """Hull box, barrel length and wheel radius of a type, parsed from the silhouette table the game uses."""
    src = open(os.path.join(REPO, "game", "battle", "unit_silhouettes.gd")).read()
    block = src[src.index("const _SPECS"):]
    rows = re.findall(r'\{"hull": Vector3\(([^)]*)\), "barrel": ([0-9.]+)(?:, "wheel": ([0-9.]+))?', block)
    hull = [float(v) for v in rows[type_id][0].split(",")]
    return {"hull": hull, "barrel": float(rows[type_id][1]), "wheel": float(rows[type_id][2] or 0)}


def m_long(cfg, v):
    """Source long coordinate -> model Y."""
    return (v - cfg["long_c"]) * cfg["k"]


def m_len(cfg, v):
    """Source length (lateral offset, height, radius) -> model units."""
    return v * cfg["k"]


def cell_uv(name):
    """Blender UV rectangle (u0, v0, u1, v1) of a right-column cell."""
    r0, rows = CELLS[name]
    return (COL_U, 1.0 - (r0 + rows) / ATLAS, COL_U + CELL / ATLAS, 1.0 - r0 / ATLAS)
