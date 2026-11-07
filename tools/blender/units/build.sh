#!/usr/bin/env bash
# Build one unit model end to end: prep -> bake -> paint -> assemble (exports and verifies
# assets/units/<unit>.glb). Scratch goes to ~/.cache/ap-scratch/units/pipe/<unit>.
# Generated sources (Tripo GLBs, ~45 MB each, kept out of the repo) live in
# ~/.local/share/advance-protocol/unit-sources/<unit>.glb, as units.json `source` says.
#   tools/blender/units/build.sh heavy_tank [--from bake|paint|assemble]
# A new unit is a units.json entry: measure the source with measure_source.py, run prep, pick the
# recognition panel spots with panel_spots.py (needs prep's work.blend), then build.
set -euo pipefail
unit="$1"; from="${3:-prep}"
here="$(cd "$(dirname "$0")" && pwd)"
blender="${BLENDER:-$HOME/.local/opt/blender-5.2.3-linux-x64/blender}"
run() { "$blender" --background --factory-startup --python "$here/$1" -- "$unit"; }
stages=(prep bake paint assemble)
go=0
for s in "${stages[@]}"; do
  [[ "$s" == "$from" ]] && go=1
  (( go )) || continue
  echo "== $s"
  if [[ "$s" == paint ]]; then python3 -I "$here/paint.py" "$unit"; else run "$s.py"; fi
done
