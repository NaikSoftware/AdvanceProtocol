#!/bin/bash
# Збирає всі інфраструктурні моделі (паркани, стовпи, сіно, причепи…) прямо в assets/props.
# INFRA_ACG — розпаковані текстури ambientCG (tools/blender/buildings/fetch_textures.sh); INFRA_OUT — куди писати GLB.
cd "$(dirname "$0")/../../.."
B="${BLENDER:-blender}"
export INFRA_ACG="${INFRA_ACG:-$PWD/art-refs/buildings_tex}"
for s in fences poles hay props; do
  # падіння — за кодом виходу Blender: скрипт, що не має жодної з названих моделей, мовчить, і це не помилка
  "$B" -b --factory-startup --python-exit-code 1 -P "tools/blender/infra/$s.py" -- "$@" 2>&1 | grep -E "BUILT|Error|Traceback"
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "$s.py впав" >&2; exit 1; }
done
