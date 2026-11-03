#!/usr/bin/env bash
# Запуск Godot для агентів: не більше двох одночасно на машині, кожен до 180 с.
# Забуті екземпляри й паралельні прогони вантажать машину і зсувають заміри викликів малювання.
# Виклик: tools/godot_run.sh [--solo] <аргументи godot...>
# --solo займає обидва слоти: замір бюджету кадру без сусіда.
GODOT_BIN="${GODOT:-$HOME/.local/bin/godot}"
LOCKS="${XDG_CACHE_HOME:-$HOME/.cache}/advance-protocol"
mkdir -p "$LOCKS" || exit 1
L1="$LOCKS/godot-slot1.lock"
L2="$LOCKS/godot-slot2.lock"
if [ "$1" = "--solo" ]; then
	shift
	exec flock "$L1" flock "$L2" timeout -k 10 180 "$GODOT_BIN" "$@"
fi
while true; do
	for L in "$L1" "$L2"; do
		exec 9>"$L"
		if flock -n 9; then
			timeout -k 10 180 "$GODOT_BIN" "$@"
			rc=$?
			flock -u 9
			exit $rc
		fi
	done
	sleep 2
done
