#!/usr/bin/env python3
"""The contrast gate for vehicle models (docs/art/unit-models-research.md, section 5): at the farthest zoom (z20) the median
colour of the model's up-facing top differs from the ground around it by CIELAB dE >= 15 (a measured 14.5 passes), on
Crossroads, River and Ridge, on meadow, ploughed soil and next to a forest edge. The body median (cast shadow removed) is
printed beside it as the cautious figure; a body below 15 is a warning, not a failure.

One command, any set and type (set = national set 0/1/2, type = unit type id: 5 medium, 6 tank destroyer, 7 light, 8 heavy):

    python3 tools/unit_contrast_gate.py --set 2 --type 8                       # shoot all three maps, print the table
    python3 tools/unit_contrast_gate.py --set 1 --type 5 6 7 8 --maps river    # several types, one map
    python3 tools/unit_contrast_gate.py --set 2 --type 8 --analyse-only --out DIR   # re-read frames already shot

Needs $GODOT (default ~/.local/bin/godot) and a window; every Godot launch goes through tools/godot_run.sh. Frames land in a
fresh directory per run (--out DIR, default ~/.cache/ap-scratch/units/gate/<timestamp>/set<N>_t<ID>/; an existing non-empty
--out is refused unless --analyse-only), a triple per place: <map>_<place>_m.png (with the model), _e.png (without) and _k.png (the model flat magenta, the footprint). The
Godot side is `unit_shot.tscn ... gate set=N` (tools/unit_shot.gd `_gate`): it places the model on cells picked from the map
data, SWITCHES OFF the cloud shadows (global cloud_shadow_strength 0; they are not paused, so numbers are those of a cloud-free
map), zooms to the farthest zoom and shoots both frames. The run fails on: a set with no model file or no _SET_SPECS row; a
Godot error or timeout; a frame pair the Godot run announced but did not write (or an old one); a requested map with no
place; a place where the model cannot be found (under 30 body pixels); a map with no usable meadow, ploughed or forest place.

Places (per map): meadow field0a..d, ploughed field1a..d, and forest sides forest{E,W,N,S}{2,3}: a field cell 2 or 3 cells from
a forest in that direction. A place is ruled out of the gate, and printed with its reason, when
  * the model is more than a quarter hidden (a crown over it: below 0.75 of the median model size on that map), or
  * the ground ring is busy (more than 8 % of it 10 L* off its median: roofs, props) or the model body is 2 L* darker than the
    map's typical body (a pole or wire over it).
Those are the only exclusions. The ploughed places must read at least 1.5 b* away from the meadow of the same map or the run
says so. A sunny map (Crossroads, Ridge) with a forest place whose ground is at least 3 L* under the meadow gets that place
named as the canopy-shade sample; with none the report says "n/a (no shaded ground)", which is not a failure.
Also writes <out>/sheet.png, a contact sheet of every place for a look by eye.

Measures (8-bit sRGB frames -> CIELAB D65), per place:
  ground = median of the ring 8..18 px (Manhattan distance, diamond dilation) outside the model plus its cast shadow, in the
           empty frame;
  body   = median of the model's pixels inside its footprint (the flat-magenta frame, so the cast shadow and the model's own
           colour play no part); top = median of the brighter half of the body (a stand-in for the up-facing top, as
           the frames carry no normal buffer).
Exit code 1 on any failure, 2 on a bad request.
"""
import argparse, datetime, glob, os, re, subprocess, sys, time
import numpy as np
from PIL import Image, ImageDraw

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LUMA = np.array([0.2126, 0.7152, 0.0722])
GATE = 14.5          # the top median; 14.5 passes (section 5)
WARN_BODY = 15.0
MIN_BODY_PX = 30
SUNNY = ("crossroads", "ridge")
GODOT_TIMEOUT = 900  # seconds per map, waiting for a Godot slot included


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
    """None when the model is not in the frame (under MIN_BODY_PX body pixels)."""
    m = np.asarray(Image.open(path_m).convert("RGB")).astype(float)
    e = np.asarray(Image.open(path_m[:-6] + "_e.png").convert("RGB")).astype(float)
    if not os.path.exists(path_m[:-6] + "_k.png"):
        sys.exit("%s: no _k.png mask frame, the run predates the flat-colour mask; shoot it again" % path_m)
    k = np.asarray(Image.open(path_m[:-6] + "_k.png").convert("RGB")).astype(float)
    h, w = m.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    # the model sits at the screen centre; the window also keeps rain and clouds elsewhere out of the mask
    window = (np.abs(xx - w / 2) < 60) & (np.abs(yy - h / 2) < 50)
    # the footprint is the model drawn flat magenta (frame _k): it does not depend on the model's own colour, which
    # the with/without difference does (a low-contrast model would lose mask pixels)
    body = (np.abs(k - np.array([255.0, 0.0, 255.0])).sum(-1) < 90) & window
    lm, le = m @ LUMA + 1e-3, e @ LUMA + 1e-3
    chroma = np.abs(m / lm[..., None] - e / le[..., None]).sum(-1)
    shadow = window & ~body & (np.abs(m - e).sum(-1) > 40) & (lm < le * 0.97) & (chroma < 0.10)
    diff = body | shadow
    if body.sum() < MIN_BODY_PX:
        return None
    px = m[body]
    top = px[lm[body] >= np.median(lm[body])]
    ring = dilate(diff, 18) & ~dilate(diff, 7)
    g, b, t = (np.median(lab(x), 0) for x in (e[ring], px, top))
    ring_l = lab(e[ring])[:, 0]
    busy = float((np.abs(ring_l - np.median(ring_l)) > 10).mean())   # roofs, props: outliers in the ground ring
    return dict(px=int(body.sum()), shadow=int(shadow.sum()), ground=g, body=b, top=t, busy=busy,
                d_body=float(np.linalg.norm(b - g)), d_top=float(np.linalg.norm(t - g)))


def slugs_and_rows():
    src = open(os.path.join(REPO, "game", "battle", "unit_silhouettes.gd")).read()
    slugs = re.findall(r'"([a-z_]+)"', re.search(r"const MODEL_SLUGS[^=]*=\s*\[(.*?)\]", src, re.S).group(1))
    return slugs, src


def check_request(set_id, type_id):
    """A set with no model or no row would silently measure the set-0 model: refuse."""
    slugs, src = slugs_and_rows()
    if not 0 <= type_id < len(slugs):
        return "type %d is not a unit type" % type_id
    path = os.path.join(REPO, "assets", "units", ("" if set_id == 0 else "set%d/" % set_id) + slugs[type_id] + ".glb")
    if not os.path.exists(path):
        return "set %d has no model for type %d (%s): the game would show the set-0 model" % (set_id, type_id, os.path.relpath(path, REPO))
    if set_id > 0:
        block = re.search(r"const _SET_SPECS.*?\n\t%d: \{(.*?)\n\t\}," % set_id, src, re.S)
        if not block or not re.search(r"\t\t%d: \{" % type_id, block.group(1)):
            return "set %d type %d has a model but no _SET_SPECS row: the game ignores the model" % (set_id, type_id)
    return None


def shoot(set_id, type_id, maps, out):
    """Run the Godot gate mode per map; returns a list of failure strings."""
    env = dict(os.environ)
    env.setdefault("GODOT", os.path.expanduser("~/.local/bin/godot"))
    fails = []
    for mp in maps:
        t0 = time.time()
        try:
            r = subprocess.run([os.path.join(REPO, "tools", "godot_run.sh"), "--path", REPO, "res://tools/unit_shot.tscn", "--",
                                out, mp, str(type_id), mp, "x", "gate", "set=%d" % set_id], cwd=REPO, env=env,
                               capture_output=True, text=True, timeout=GODOT_TIMEOUT)
        except subprocess.TimeoutExpired:
            fails.append("%s: Godot run timed out after %d s" % (mp, GODOT_TIMEOUT))
            continue
        announced = re.findall(r"UNIT gate (\S+) cell", r.stdout)
        if r.returncode != 0 or "UNIT gate zoom" not in r.stdout:
            tail = " | ".join(l for l in (r.stdout + r.stderr).splitlines() if "rror" in l or "SCRIPT" in l)[:300]
            fails.append("%s: Godot run failed (exit %d)%s" % (mp, r.returncode, (": " + tail) if tail else ""))
            continue
        if not announced:
            fails.append("%s: the run found no place to shoot" % mp)
        for place in announced:
            for suffix in ("m", "e", "k"):
                f = os.path.join(out, "%s_%s_%s.png" % (mp, place, suffix))
                if not os.path.exists(f) or os.path.getmtime(f) < t0 - 1:
                    fails.append("%s %s: frame %s_%s.png missing or stale" % (mp, place, place, suffix))
    return fails


def report(out, label, maps):
    fails = []
    results = []
    for f in sorted(glob.glob(os.path.join(out, "*_m.png"))):
        name = os.path.basename(f)[:-6]
        mp, place = name.split("_", 1)
        results.append((name, mp, place, measure(f)))
    for mp in maps:
        if not any(m == mp for _, m, _, _ in results):
            fails.append("%s: no places measured" % mp)
    # the footprint still changes with the map's camera framing, so "hidden" is judged against the median size on
    # the same map
    typical = {mp: float(np.median([x["px"] for _, m2, _, x in results if x and m2 == mp] or [0])) for mp in maps}
    usable = {}
    for name, mp, place, r in results:
        if r is None:
            print("%-30s model not found in the frame   FAIL" % name)
            fails.append("%s: model not found (under %d body pixels)" % (name, MIN_BODY_PX))
            continue
        same_map = [x["body"][0] for _, m2, _, x in results if x and m2 == mp]
        why = ""
        if r["px"] < 0.75 * typical.get(mp, 0.0):
            why = "ruled out: model partly hidden (crown over it)"
        elif r["busy"] > 0.08:
            why = "ruled out: busy ground (prop or roof in the ring)"
        elif r["body"][0] < np.median(same_map) - 2.0:
            why = "ruled out: model shaded below the map's typical body (pole or wire over it)"
        flag = ""
        if not why:
            usable.setdefault(mp, {})[place] = r
            if r["d_top"] < GATE:
                flag = "   FAIL (top)"
                fails.append("%s: top dE %.1f < %.1f" % (name, r["d_top"], GATE))
            elif r["d_body"] < WARN_BODY:
                flag = "   warn: body < 15"
        print("%-30s px %5d (shadow %4d)  ground L%.0f a%+.1f b%+.1f  body L%.0f a%+.1f b%+.1f  dE top %5.1f  dE body %5.1f%s" % (
            name, r["px"], r["shadow"], *r["ground"], *r["body"], r["d_top"], r["d_body"], ("   " + why) if why else flag))
    notes = []
    for mp in maps:
        good = usable.get(mp, {})
        every = {pl: r for _, m2, pl, r in results if m2 == mp}
        meadow = [v for k, v in good.items() if k.startswith("field0")]
        plough = [v for k, v in good.items() if k.startswith("field1")]
        forest = {k: v for k, v in good.items() if k.startswith("forest")}
        if every and not meadow:
            fails.append("%s: no usable meadow place" % mp)
        if every and not any(k.startswith("field1") for k in every):
            fails.append("%s: no ploughed place was shot" % mp)
        elif every and not plough:
            fails.append("%s: no usable ploughed place" % mp)
        if every and not forest:
            fails.append("%s: no usable forest-edge place" % mp)
        if meadow and plough and abs(np.mean([p["ground"][2] for p in plough]) - np.mean([p["ground"][2] for p in meadow])) < 1.5:
            notes.append("%s: ploughed places read like meadow (b* within 1.5): check the frames by eye" % mp)
        if mp in SUNNY and meadow and forest:
            base = float(np.mean([p["ground"][0] for p in meadow]))
            shaded = [k for k, v in forest.items() if v["ground"][0] <= base - 3]
            notes.append("%s canopy shade: %s" % (mp, ("measured at " + ", ".join(shaded)) if shaded else "n/a (no shaded ground)"))
    best = min((v["d_top"] for places in usable.values() for v in places.values()), default=float("nan"))
    ok = not fails
    print("%s: tightest top dE %.1f -> %s" % (label, best, "PASS" if ok else "FAIL"))
    for n in notes:
        print("  NOTE", n)
    for fl in fails:
        print("  FAIL", fl)
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
    ap.add_argument("--out", help="output directory; with several types a set<N>_t<ID> subdirectory is added")
    ap.add_argument("--analyse-only", action="store_true", help="do not shoot, read the frames already in --out")
    a = ap.parse_args()
    for t in a.type:
        err = check_request(a.set, t)
        if err:
            print("unit_contrast_gate: " + err, file=sys.stderr)
            sys.exit(2)
    base = a.out or os.path.join(os.path.expanduser("~/.cache/ap-scratch/units/gate"), datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    ok = True
    for t in a.type:
        out = a.out if (a.out and len(a.type) == 1) else os.path.join(base, "set%d_t%d" % (a.set, t))
        if not a.analyse_only and os.path.isdir(out) and os.listdir(out):
            print("unit_contrast_gate: %s is not empty; pass a fresh --out (old frames would be scored)" % out, file=sys.stderr)
            sys.exit(2)
        os.makedirs(out, exist_ok=True)
        print("== set %d type %d  (%s)" % (a.set, t, out))
        fails = [] if a.analyse_only else shoot(a.set, t, a.maps, out)
        for fl in fails:
            print("  FAIL", fl)
        ok = (report(out, "set %d type %d" % (a.set, t), a.maps) and not fails) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
