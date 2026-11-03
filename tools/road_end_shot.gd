extends Node
## Кадри кінців асфальту на справжньому ґрунті карти, камера гри на зумі 8 і 12. Не входить у гру.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/road_end_shot.tscn -- <out_dir> <map> <tag=x,y> [<tag=x,y> ...]
## Параметр --z=5,8 задає зуми (типово 8 і 12); --seq=N — ще N кадрів поспіль (<tag>_z<зум>_s<i>.png),
## щоб дивитись рух. Кадри <tag>_z<зум>.png пишуться наприкінці (save_png блокує ~1 с).

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
	# --broken=x,y;x,y — ці клітинки мосту зруйновані: кадр зруйнованої переправи на тому ж ґрунті.
	# Сам завантажений ресурс, не копія: шлях ресурсу дає карті погоду, макет села й моделі мостів.
	var map: MapData = load("res://maps/%s.tres" % args[1]) as MapData
	for a in args:
		if a.begins_with("--broken="):
			for c in a.substr(9).split(";"):
				map.tiles[int(c.get_slice(",", 1)) * map.width + int(c.get_slice(",", 0))] = Terrain.Kind.BRIDGE_DESTROYED
	screen.setup(map, 2, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	var shots: Array = []
	var zooms: Array = [8.0, 12.0]
	var seq: int = 0
	for a in args.slice(2):
		if a.begins_with("--seq="):
			seq = int(a.substr(6))
		if a.begins_with("--z="):
			zooms = []
			for zs in a.substr(4).split(","):
				zooms.append(float(zs))
	for a in args.slice(2):
		if a.begins_with("--"):
			continue
		var tag: String = a.get_slice("=", 0)
		var xy: PackedStringArray = a.get_slice("=", 1).split(",")
		rig.center_on(Vector2i(roundi(float(xy[0])), roundi(float(xy[1]))))
		for z: float in zooms:
			rig.zoom_by(z / rig.zoom_level)
			for f in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots.append(["%s/%s_z%d.png" % [args[0], tag, int(z)], get_viewport().get_texture().get_image()])
			_print_probes(args, "%s_z%d" % [tag, int(z)])
			for i in seq:
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				shots.append(["%s/%s_z%d_s%02d.png" % [args[0], tag, int(z), i], get_viewport().get_texture().get_image()])
	for s: Array in shots:
		(s[1] as Image).save_png(s[0])
	get_tree().quit()


## --probe=x,z;x,z;… — світові точки (на настилі мосту — на його верху, інакше на ґрунті): друкує їхні
## пікселі в кадрі рядками PROBE <кадр> <i> <px> <py>, щоб мірити тон по обидва боки стику.
func _print_probes(args: PackedStringArray, shot: String) -> void:
	var h: TerrainHeight = TerrainHeight.active
	var cam: Camera3D = get_viewport().get_camera_3d()
	for a in args:
		if not a.begins_with("--probe="):
			continue
		var pts: PackedStringArray = a.substr(8).split(";")
		for i in pts.size():
			var xz: PackedStringArray = pts[i].split(",")
			var p := Vector2(float(xz[0]), float(xz[1]))
			var y: float = h.at(p.x, p.y)
			for g in h.bridge_groups():
				if (g["cells"] as Array).has(Vector2i(roundi(p.x), roundi(p.y))):
					y = maxf(y, h.deck_y(Vector2i(roundi(p.x), roundi(p.y))) + 0.008)
			var s: Vector2 = cam.unproject_position(Vector3(p.x, y, p.y))
			print("PROBE %s %d %d %d" % [shot, i, roundi(s.x), roundi(s.y)])
