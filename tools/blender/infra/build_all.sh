#!/bin/bash
# Збирає всі інфраструктурні моделі (паркани, стовпи, сіно, причепи…) прямо в assets/props.
# INFRA_ACG — розпаковані текстури ambientCG (tools/blender/buildings/fetch_textures.sh); INFRA_OUT — куди писати GLB.
set -o pipefail
cd "$(dirname "$0")/../../.."
B="${BLENDER:-blender}"
export INFRA_ACG="${INFRA_ACG:-$PWD/art-refs/buildings_tex}"
for s in fences poles hay props; do
  "$B" -b --factory-startup --python-exit-code 1 -P "tools/blender/infra/$s.py" -- "$@" 2>&1 | grep -E "BUILT|Error|Traceback" || { echo "$s.py впав" >&2; exit 1; }
done
