#!/usr/bin/env bash
set -euo pipefail
: "${GODOT:?export GODOT=/home/naik/.local/bin/godot}"
export GODOT_PATH="$GODOT"
# .godot/ is gitignored, so a fresh checkout has no import cache yet and GUT's
# class_names fail to resolve; import once here (idempotent, cheap, must not abort the run).
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
default_dir=(-gdir=res://tests -ginclude_subdirs)
headless_flag=(--headless)
force_headless=0
gut_args=()
for arg in "$@"; do
	case "$arg" in
		--windowed) headless_flag=() ;;
		--headless) force_headless=1 ;;
		--normal) export RIVER_E2E_SPEED=normal ;;
		--fast|--speedup) export RIVER_E2E_SPEED=fast ;;
		-gtest=*|-gdir=*)
			default_dir=()
			case "$arg" in
				*full_river_e2e*) headless_flag=() ;;
			esac
			gut_args+=("$arg")
			;;
		*) gut_args+=("$arg") ;;
	esac
done
if [ "$force_headless" -eq 1 ]; then
	headless_flag=(--headless)
fi
"$GODOT" "${headless_flag[@]}" --path . -s addons/gut/gut_cmdln.gd "${default_dir[@]}" -gexit "${gut_args[@]}"
