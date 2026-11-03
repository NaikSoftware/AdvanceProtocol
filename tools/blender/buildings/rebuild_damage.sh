#!/bin/bash
# Перезбирає пошкоджені стани й руїни та знімає їх (для швидкої ітерації).
set -o pipefail
cd "$(dirname "$0")/../../.."
B="${BLENDER:-blender}"
"$B" -b --factory-startup --python-exit-code 1 -P tools/blender/buildings/build_block.py -- art-refs/buildings_out 2>&1 | grep RESULT || exit 1
"$B" -b --factory-startup --python-exit-code 1 -P tools/blender/buildings/build_houses.py -- art-refs/buildings_out h1hit 2>&1 | grep RESULT || exit 1
"$B" -b --factory-startup --python-exit-code 1 -P tools/blender/buildings/build_ruins.py -- art-refs/buildings_out 2>&1 | grep RESULT || exit 1
bash tools/blender/buildings/shoot.sh h5_panel_block_damaged house_h1_hit ruin_half_house1 ruin_half_house2 ruin_half_shed
