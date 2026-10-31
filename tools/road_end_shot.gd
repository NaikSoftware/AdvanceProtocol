extends Node
## Кадри кінців асфальту на справжньому ґрунті карти, камера гри на зумі 8 і 12. Не входить у гру.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/road_end_shot.tscn -- <out_dir> <map> <tag=x,y> [<tag=x,y> ...]
## Кадри <tag>_z8.png і <tag>_z12.png пишуться наприкінці (save_png блокує ~1 с).

const SETTLE_FRAMES: int = 45


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("road_end_shot: очікую <out_dir> <map> <tag=x,y>...")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	get_window().size = Vector2i(1280, 720)
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(load("res://maps/%s.tres" % args[1]) as MapData, 2, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	var shots: Array = []
	for a in args.slice(2):
		var tag: String = a.get_slice("=", 0)
		var xy: PackedStringArray = a.get_slice("=", 1).split(",")
		rig.center_on(Vector2i(roundi(float(xy[0])), roundi(float(xy[1]))))
		for z: float in [8.0, 12.0]:
			rig.zoom_by(z / rig.zoom_level)
			for f in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots.append(["%s/%s_z%d.png" % [args[0], tag, int(z)], get_viewport().get_texture().get_image()])
	for s: Array in shots:
		(s[1] as Image).save_png(s[0])
	get_tree().quit()
