"""Give a soldier figure's Godot import files the unit-model settings (docs/art-direction.md, Unit models, Import settings).

    python3 -I figure_import.py rifle_soldier assault_soldier

Run after a first `godot --headless --import` wrote the default .import files, then import again. The GLB takes
the [params] of the reference vehicle import (scout_car); the extracted albedo is VRAM-compressed (mode 2).
"""
import os, re, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
UNITS = os.path.join(REPO, "assets", "units")
ref = open(os.path.join(UNITS, "scout_car.glb.import")).read()
ref_params = ref[ref.index("[params]"):]


def patch(path, keys):
    s = open(path).read()
    for k, v in keys.items():
        s, n = re.subn(r"(?m)^%s=.*$" % re.escape(k), "%s=%s" % (k, v), s)
        if n == 0:
            s = s.rstrip("\n") + "\n%s=%s\n" % (k, v)
    open(path, "w").write(s)


for name in sys.argv[1:]:
    glb = os.path.join(UNITS, name + ".glb.import")
    s = open(glb).read()
    open(glb, "w").write(s[:s.index("[params]")] + ref_params)
    png = os.path.join(UNITS, name + "_albedo.png.import")
    if os.path.exists(png):
        patch(png, {"compress/mode": "2"})
    print("patched", name)
