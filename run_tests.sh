#!/usr/bin/env bash
set -euo pipefail
: "${GODOT:?export GODOT=/home/naik/.local/bin/godot}"
export GODOT_PATH="$GODOT"
# .godot/ is gitignored, so a fresh checkout has no import cache yet and GUT's
# class_names fail to resolve; import once here (idempotent, cheap, must not abort the run).
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit "$@"
