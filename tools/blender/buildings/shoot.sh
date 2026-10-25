#!/bin/bash
# Копіює GLB у assets/props, імпортує й знімає превʼю камерою гри (потрібне вікно).
# Використання: shoot.sh <name> ...
cd "$(dirname "$0")/../../.."
for n in "$@"; do cmp -s "art-refs/buildings_out/$n.glb" "assets/props/$n.glb" || cp "art-refs/buildings_out/$n.glb" assets/props/; done
rm -f assets/props/*.import assets/props/*.jpg
timeout 120 /home/naik/.local/bin/godot --headless --import --path . >/dev/null 2>&1
git checkout project.godot
timeout 170 /home/naik/.local/bin/godot --path . res://tools/prop_preview.tscn -- "$PWD/art-refs/buildings" ${FLAGS:---graze --back --tank --side} "$@" 2>&1 | grep -E "PROP|ERROR"
