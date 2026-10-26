extends Node
## Рослинність на справжньому ґрунті карти: екран бою (рельєф, ґрунт, вода, світло й погода карти),
## на одну клітинку ставляться вузли бібліотеки рослинності з матеріалами, як на дошці
## (VegetationLayer.veg_mesh), камера гри — на найближчому й найдальшому зумі. Не входить у гру.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/veg_board_shot.tscn -- <out_dir> <map> <library.glb> <node,node,...> [x,y] [--water] [--norain] [--neutral]
## --norain: без штрихів дощу (порожній кадр для маски tools/veg_measure.py має збігатися піксель у піксель);
## --neutral: біле сонце й без тону листя (для tools/veg_measure.py leaf).
## Без x,y — перша клітинка поля, що межує з водою (--water: сама клітинка води біля берега, для очерету).
## Вузли стають рядком через клітинку вздовж X на висоті рельєфу. Кадри: <tag>_z6.png і <tag>_z20.png,
## де tag — ім'я бібліотеки без .glb; пишуться наприкінці (save_png блокує ~1 с).

const SETTLE_FRAMES: int = 120


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("veg_board_shot: очікую <out_dir> <map> <library.glb> <nodes> [x,y] [--water]")
		get_tree().quit(1)
		return
	var out: String = args[0]
	var map: String = args[1]
	var lib: String = args[2]
	var nodes: PackedStringArray = args[3].split(",")
	var want_water: bool = args.has("--water")
	var norain: bool = args.has("--norain")
	var neutral: bool = args.has("--neutral")
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)

	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
	var board: Board = MatchService.state.board
	var weather: WeatherRig = screen.get("_weather")
	if norain and weather.rain != null:
		weather.rain.visible = false
	if neutral:
		weather.sun.light_color = Color(1, 1, 1)
		RenderingServer.global_shader_parameter_set(&"foliage_tint", Vector3.ONE)
	var cell := Vector2i(-1, -1)
	for a in args.slice(4):
		if a.contains(","):
			var xy: PackedStringArray = a.split(",")
			cell = Vector2i(int(xy[0]), int(xy[1]))
	if cell == Vector2i(-1, -1):
		cell = _bank_cell(board, want_water)
	if cell == Vector2i(-1, -1):
		push_error("veg_board_shot: на %s нема клітинки біля води" % map)
		get_tree().quit(1)
		return

	var scene: Node3D = (load(lib) as PackedScene).instantiate()
	var root := Node3D.new()
	(screen.get_node("%BoardView") as Node3D).add_child(root)
	var k: int = 0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var i: int = nodes.find(String(mi.name))
		if i < 0:
			continue
		var inst := MeshInstance3D.new()
		inst.mesh = VegetationLayer.veg_mesh(mi.mesh, -1.0, 0.0, (screen.get_node("%BoardView") as BoardView).structure_shadows)
		var x: float = float(cell.x) + (float(i) - float(nodes.size() - 1) * 0.5) * 1.0
		var z: float = float(cell.y)
		inst.position = Vector3(x, TerrainHeight.ground_y(x, z), z)
		root.add_child(inst)
		k += 1
	scene.free()
	print("VEGBOARD %s %s cell %s nodes %d" % [map, lib.get_file(), cell, k])

	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	rig.center_on(cell)
	var shots: Array = []
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(["%s/%s_z%d.png" % [out, lib.get_file().get_basename(), int(z)], get_viewport().get_texture().get_image()])
	for s: Array in shots:
		(s[1] as Image).save_png(s[0])
	get_tree().quit()


## Клітинка поля поруч із водою (або, з water, сама клітинка води поруч із полем) — ближча до
## центру дошки, щоб камера не впиралась у край.
func _bank_cell(board: Board, water: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	var centre := Vector2(board.width, board.height) * 0.5
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			var me: int = board.kind_at(c)
			if me != (Terrain.Kind.WATER if water else Terrain.Kind.FIELD):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if board.in_bounds(n) and board.kind_at(n) == (Terrain.Kind.FIELD if water else Terrain.Kind.WATER):
					var dist: float = Vector2(c).distance_to(centre)
					if dist < best_d:
						best_d = dist
						best = c
	return best
