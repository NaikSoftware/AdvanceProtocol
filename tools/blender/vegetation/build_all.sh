#!/bin/bash
# Повне збирання рослинності: спрайти (Blender, GPU), атласи (python), бібліотеки GLB.
# Спрайти й атласи лягають у $VEG_SRC (поза репозиторієм), GLB — у assets/props/vegetation/.
# Після збирання: $GODOT --headless --path . --import і git checkout project.godot.
# Потрібні: blender на PATH, python3 з numpy і Pillow. SKIP_SPRITES=1 бере вже готові спрайти.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
VEG_SRC="${VEG_SRC:-$HOME/.cache/ap-scratch/bank-veg}"
if [ -z "${SKIP_SPRITES:-}" ]; then
  for k in reed cattail willow alder apple cherry walnut lilac elder berry thuja hawthorn dogrose pear oak wwillow; do
    for s in late summer early; do
      blender -b --factory-startup -P "$HERE/veg_sprites.py" -- "$VEG_SRC/src" $k $s 6 1 | grep -E "^SPRITE|Error" | tail -1
    done
  done
fi
for g in bank yard meadow; do
  for s in late summer early; do
    python3 -I "$HERE/veg_atlas.py" "$VEG_SRC/src" $g $s "$VEG_SRC/atlas"
    blender -b --factory-startup -P "$HERE/veg_build.py" -- "$VEG_SRC/atlas" $g $s "$ROOT/assets/props/vegetation/${g}_veg_$s.glb" | grep -E "^NODE|Error"
  done
done
