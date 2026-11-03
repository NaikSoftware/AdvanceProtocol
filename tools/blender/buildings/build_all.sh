#!/bin/bash
# Збирає всі будівлі в art-refs/buildings_out (або в перший аргумент). Падіння Blender зупиняє збирання.
set -o pipefail
cd "$(dirname "$0")/../../.."
B="${BLENDER:-blender}"
OUT="${1:-art-refs/buildings_out}"
mkdir -p "$OUT"; touch "$OUT/.gdignore"  # атласи PNG не мають потрапити в імпорт Godot
for s in towers block farm houses ruins; do
  "$B" -b --factory-startup --python-exit-code 1 -P "tools/blender/buildings/build_$s.py" -- "$OUT" 2>&1 | grep -E "RESULT|Error|Traceback|line |assert" || { echo "build_$s.py впав" >&2; exit 1; }
done
