#!/usr/bin/env bash
# Повний набір кадрів HUD для перегляду: карти по черзі (два слоти Godot на всю машину).
# Виклик: tools/hud_shots_r2.sh <out_dir>
OUT="${1:?out_dir}"
# Дві половини: один прогон Godot обмежений 180 с.
A1="idle,own_tank,move_preview,shot_preview,squad,drone,drone_preview"
A2="engineer,engineer_armed,engineer_pending,hold_enemy,hold_enemy_squad,pause,handover"
RIDGE="idle,shot_preview,handover,pause"
EN="shot_preview,engineer,handover"
cd "$(dirname "$0")/.." || exit 1
run() { # map size dpi locale states
	tools/godot_run.sh --path . res://tools/hud_shot.tscn -- "$OUT" "$1" "$2" "$4" "$5" hud=on --ui-dpi="$3" 2>&1 | grep -E "SCRIPT ERROR|HUD_SHOT (FAILED|/)|ERROR" | sed 's/^/  /'
}
for size in "1496x672 243" "1600x720 320"; do
	set -- $size
	for m in river crossroads; do
		run $m "$1" "$2" uk "$A1"
		run $m "$1" "$2" uk "$A2"
	done
	run ridge "$1" "$2" uk "$RIDGE"
done
run river 1496x672 243 en "$EN"
echo SHOTS_DONE
