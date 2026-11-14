#!/usr/bin/env bash
# Повний набір кадрів HUD для перегляду: карти по черзі (два слоти Godot на всю машину).
# Виклик: tools/hud_shots.sh <out_dir>
OUT="${1:?out_dir}"
# Дві половини: один прогон Godot обмежений 180 с.
A1="idle,own_tank,move_preview,shot_preview,squad,drone,drone_preview"
A2="engineer,engineer_armed,engineer_pending,hold_enemy,hold_enemy_squad,pause,handover"
A3="toast_drone,toast_engineer,own_tank_to_shot,squad_shot,shot_infantry,shot_cover,shot_infantry_armour_ignored,hold_enemy_squad_spent,handover_p1,handover_2p_hurt,handover_3p,handover_3p_eliminated,handover_3p_even,handover_p3,handover_default"
A4="enemy,engineer_clear,engineer_repair_bridge,engineer_demolish_bridge,engineer_to_armed,squad_to_drone,hold_cluster,hold_engineer,mood"
RIDGE="idle,shot_preview,handover,pause"
EN="shot_preview,engineer,engineer_armed,handover,hold_enemy_squad,toast_drone"
cd "$(dirname "$0")/.." || exit 1
run() { # map size dpi locale states
	tools/godot_run.sh --path . res://tools/hud_shot.tscn -- "$OUT" "$1" "$2" "$4" "$5" hud=on --ui-dpi="$3" 2>&1 | tee -a "$OUT/log_$1_$2_$4.txt" | grep -E "SCRIPT ERROR|HUD_SHOT (FAILED|/)|ERROR" | sed 's/^/  /'
}
for size in "1496x672 243" "1600x720 320"; do
	set -- $size
	for m in river crossroads; do
		run $m "$1" "$2" uk "$A1"
		run $m "$1" "$2" uk "$A2"
		run $m "$1" "$2" uk "$A3"
		run $m "$1" "$2" uk "$A4"
	done
	run ridge "$1" "$2" uk "$RIDGE"
done
for size in "1496x672 243" "1600x720 320"; do
	set -- $size
	run river "$1" "$2" en "$EN"
done
echo SHOTS_DONE
