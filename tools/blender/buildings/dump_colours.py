"""Друкує наближений альбедо кожного матеріалу (sRGB) і позначає ті, де R-G > 25 (рожеві/лососеві)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

lib.reset()
for name, m in sorted(lib.mats().items()):
    ap = m.get("approx")
    if ap is None:
        continue
    srgb = [round(255 * (max(0.0, c) ** (1 / 2.2))) for c in ap]
    flag = "  <-- R-G>25" if srgb[0] - srgb[1] > 25 else ""
    print("COLOUR %-14s %s  R-G=%d%s" % (name, tuple(srgb), srgb[0] - srgb[1], flag))
