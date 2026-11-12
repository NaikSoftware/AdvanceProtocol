#!/usr/bin/env python3
"""The contrast gate for vehicle models (docs/art/unit-models-research.md, section 5): at the farthest zoom (z20) the model's
body and top differ from the ground around it by CIELAB dE >= 15, on Crossroads, River and Ridge, on meadow, ploughed
soil and next to a forest edge.

One command, any set and type (set = national set 0/1/2, type = unit type id: 5 medium, 6 tank destroyer, 7 light, 8 heavy):

    python3 tools/unit_contrast_gate.py --set 2 --type 8                       # shoot all three maps, print the table
    python3 tools/unit_contrast_gate.py --set 1 --type 5 6 7 8 --maps river    # several types, one map
    python3 tools/unit_contrast_gate.py --set 2 --type 8 --analyse-only        # re-read frames already shot

Needs $GODOT (default ~/.local/bin/godot) and a window; every Godot launch goes through tools/godot_run.sh. Frames land in
--out (default ~/.cache/ap-scratch/units/gate/set<N>_t<ID>/), a pair per place: <map>_<place>_m.png (with the model) and
_e.png (without). The Godot side is `unit_shot.tscn ... gate set=N` (tools/unit_shot.gd `_gate`): it places the model on
cells picked from the map data, freezes the cloud shadows (global cloud_shadow_strength 0, so the two frames of a pair are
identical and River/Ridge numbers repeat), zooms to the farthest zoom and shoots both frames.

Places (per map): meadow (field0a..c), ploughed (field1a..c), and forest sides forest{E,W,N,S}{2,3}: a field cell 2 or 3
cells from a forest in that direction. Names do not prove the ground kind, so the report checks them:
  * ploughed places must read at least 1.5 b* away from meadow places of the same map, else the line is flagged;
  * one forest place per sunny map should sit at least 3 L* darker than the meadow (a crown's cast shadow); if none does the
    report says so instead of pretending.
It also writes <out>/sheet.png, a contact sheet of every place for a look by eye.

Measures (8-bit sRGB frames -> CIELAB D65), per place:
  ground = median of the ring 7..18 px outside the model's footprint in the empty frame;
  body   = median of the model's pixels with the cast shadow removed (pixels darker than the empty frame with the same
           chromaticity are shadow);  top = median of the brighter half of the body (a stand-in for the up-facing top, as the
           frames carry no normal buffer).
The gate figure is dE(body, ground); dE(top, ground) is printed beside it. Exit code 1 if any body dE < 15.
"""
import argparse, glob, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LUMA = np.array([0.2126, 0.7152, 0.0722])
GATE = 15.0


def lab(rgb):
    c = np.asarray(rgb, float).reshape(-1, 3) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], -1)


def dilate(mask, n):
    for _ in range(n):
        p = np.pad(mask, 1)
        mask = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return mask


def measure(path_m):
    m = np.asarray(Image.open(path_m).convert("RGB")).astype(float)
    e = np.asarray(Image.open(path_m[:-6] + "_e.png").convert("RGB")).astype(float)
    h, w = m.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    # the model sits at the screen centre; the window also keeps rain and clouds elsewhere out of the mask
    diff = (np.abs(m - e).sum(-1) > 40) & (np.abs(xx - w / 2) < 60) & (np.abs(yy - h / 2) < 50)
    lm, le = m @ LUMA + 1e-3, e @ LUMA + 1e-3
    chroma = np.abs(m / lm[..., None] - e / le[..., None]).sum(-1)
    shadow = diff & (lm < le * 0.97) & (chroma < 0.10)
    body = diff & ~shadow
    if body.sum() < 30:
        return None
    px = m[body]
    top = px[lm[body] >= np.median(lm[body])]
    ring = dilate(diff, 18) & ~dilate(diff, 7)
    g, b, t = (np.median(lab(x), 0) for x in (e[ring], px, top))
    return dict(px=int(body.sum()), shadow=int(shadow.sum()), ground=g, body=b, top=t,
                d_body=float(np.linalg.norm(b - g)), d_top=float(np.linalg.norm(t - g)))


def shoot(set_id, type_id, maps, out):
    env = dict(os.environ)
    env.setdefault("GODOT", os.path.expanduser("~/.local/bin/godot"))
    for mp in maps:
        subprocess.run([os.path.join(REPO, "tools", "godot_run.sh"), "--path", REPO, "res://tools/unit_shot.tscn", "--",
                        out, mp, str(type_id), mp, "x", "gate", "set=%d" % set_id], cwd=REPO, env=env, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def report(out, label):
    rows = {}
    for f in sorted(glob.glob(os.path.join(out, "*_m.png"))):
        name = os.path.basename(f)[:-6]
        mp, place = name.split("_", 1)
        r = measure(f)
        rows.setdefault(mp, {})[place] = r
        if r is None:
            print("%-30s no model found in the frame" % name)
            continue
        print("%-30s px %5d (shadow %4d)  ground L%.0f a%+.1f b%+.1f  body L%.0f a%+.1f b%+.1f  dE body %5.1f  dE top %5.1f%s" % (
            name, r["px"], r["shadow"], *r["ground"], *r["body"], r["d_body"], r["d_top"], "" if r["d_body"] >= GATE else "   FAIL"))
    ok = True
    notes = []
    for mp, places in rows.items():
        good = {k: v for k, v in places.items() if v}
        if any(v["d_body"] < GATE for v in good.values()):
            ok = False
        meadow = [v for k, v in good.items() if k.startswith("field0")]
        plough = [v for k, v in good.items() if k.startswith("field1")]
        forest = {k: v for k, v in good.items() if k.startswith("forest")}
        if meadow and plough and abs(np.mean([p["ground"][2] for p in plough]) - np.mean([p["ground"][2] for p in meadow])) < 1.5:
            notes.append("%s: ploughed places read like meadow (b* within 1.5): check the frames by eye" % mp)
        if not plough:
            notes.append("%s: no ploughed place found" % mp)
        if meadow and forest and mp != "river":
            base = np.mean([p["ground"][0] for p in meadow])
            if min(v["ground"][0] for v in forest.values()) > base - 3:
                notes.append("%s: no forest place sits 3 L* darker than the meadow: no cast-shadow place verified" % mp)
    worst = min((v["d_body"] for places in rows.values() for v in places.values() if v), default=float("nan"))
    print("%s: tightest body dE %.1f -> %s" % (label, worst, "PASS" if ok else "FAIL"))
    for n in notes:
        print("  NOTE", n)
    # contact sheet of the places, labelled
    files = sorted(glob.glob(os.path.join(out, "*_m.png")))
    if files:
        cols, cw, ch = 4, 240, 180
        sheet = Image.new("RGB", (cols * cw, ((len(files) + cols - 1) // cols) * ch))
        for i, f in enumerate(files):
            im = Image.open(f).convert("RGB")
            w, h = im.size
            tile = im.crop((w // 2 - 120, h // 2 - 90, w // 2 + 120, h // 2 + 90))
            ImageDraw.Draw(tile).text((4, 4), os.path.basename(f)[:-6], fill=(255, 255, 0))
            sheet.paste(tile, ((i % cols) * cw, (i // cols) * ch))
        sheet.save(os.path.join(out, "sheet.png"))
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", type=int, required=True, help="national set 0, 1 or 2")
    ap.add_argument("--type", type=int, nargs="+", required=True, help="unit type ids (5 medium, 6 tank destroyer, 7 light, 8 heavy)")
    ap.add_argument("--maps", nargs="+", default=["crossroads", "river", "ridge"])
    ap.add_argument("--out", help="output directory (one subdirectory per type is added when several types are given)")
    ap.add_argument("--analyse-only", action="store_true", help="do not shoot, read the frames already in --out")
    a = ap.parse_args()
    base = a.out or os.path.expanduser("~/.cache/ap-scratch/units/gate")
    ok = True
    for t in a.type:
        out = a.out if (a.out and len(a.type) == 1) else os.path.join(base, "set%d_t%d" % (a.set, t))
        os.makedirs(out, exist_ok=True)
        if not a.analyse_only:
            shoot(a.set, t, a.maps, out)
        print("== set %d type %d  (%s)" % (a.set, t, out))
        ok = report(out, "set %d type %d" % (a.set, t)) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
