#!/bin/bash
# Перезбирає пошкоджені стани й руїни та знімає їх (для швидкої ітерації).
cd "$(dirname "$0")/../../.."
B=/home/naik/.local/bin/blender
$B -b --factory-startup -P tools/blender/buildings/build_block.py -- art-refs/buildings_out 2>&1 | grep RESULT
$B -b --factory-startup -P tools/blender/buildings/build_houses.py -- art-refs/buildings_out h1hit ruins 2>&1 | grep RESULT
bash tools/blender/buildings/shoot.sh h5_panel_block_damaged house_h1_hit ruin_h1 ruin_h3
