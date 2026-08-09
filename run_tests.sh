#!/usr/bin/env bash
set -euo pipefail
: "${GODOT:?export GODOT=/home/naik/Downloads/Godot_v4.7.1-stable_linux.x86_64}"
export GODOT_PATH="$GODOT"
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit "$@"
