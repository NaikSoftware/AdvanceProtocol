#!/bin/bash
# Збирає всі будівлі в art-refs/buildings_out (або в перший аргумент).
cd "$(dirname "$0")/../../.."
OUT="${1:-art-refs/buildings_out}"
for s in towers block farm; do
  /home/naik/.local/bin/blender -b --factory-startup -P "tools/blender/buildings/build_$s.py" -- "$OUT" 2>&1 | grep -E "RESULT|Error|Traceback|line |assert"
done
