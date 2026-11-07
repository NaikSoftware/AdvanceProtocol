extends Node
## Зламані моделі, розкидані по справжньому ґрунту карти (екран бою: рельєф, ґрунт, світло й небо карти), камерою гри.
## Знімає лежачі шматки поруч із тими, що лишаються на місці (пеньки, стовпи, цоколь), на заданому зумі.
## Запуск (потрібне вікно, не --headless):
##   tools/godot_run.sh --path . res://tools/broken_board_shot.tscn -- <out_dir> <map> <zoom> <model,model,...> [x,y] [--bank]
## --bank: клітинка поля біля води (мул на River); без x,y — клітинка поля найближча до центру дошки.
## Кадр: <out_dir>/<map>_z<zoom>_<тег>.png, де тег — перша модель; усі моделі стоять рядком уздовж Z.

const SETTLE_FRAMES: int = 120
const STAY: Array[String] = ["stump", "berm", "plinth"]


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("broken_board_shot: <out_dir> <map> <zoom> <models> [x,y] [--bank]")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = Vector2i(1280, 720)
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(load("res://maps/%s.tres" % a[1]) as MapData, 2, 1)
	var board: Board = MatchService.state.board
	var cell := _field_cell(board, a.has("--bank"))
	for s in a.slice(4):
		if s.contains(","):
			cell = Vector2i(int(s.get_slice(",", 0)), int(s.get_slice(",", 1)))
	var root := Node3D.new()
	(screen.get_node("%BoardView") as Node3D).add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var models: PackedStringArray = a[3].split(",")
	for i in models.size():
		var origin := Vector3(float(cell.x), 0.0, float(cell.y) + (float(i) - float(models.size() - 1) * 0.5) * 0.9)
		_place(root, "res://assets/props/broken/%s_broken.glb" % models[i], origin, rng)
	print("BROKENBOARD %s cell %s models %s" % [a[1], cell, a[3]])
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	rig.center_on(cell)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var tag: String = "%s/%s_z%s_%s" % [a[0], a[1], a[2], models[0]]
	img.save_png(tag + ".png")
	# вирізка 1:1 навколо моделей: на зумі 8 шматок — кілька пікселів, у кадрі повного вікна його не видно
	var at: Vector2 = get_viewport().get_camera_3d().unproject_position(root.to_global(Vector3(cell.x, 0.0, cell.y)))
	var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var size := Vector2i(560, 360)
	var pos := (Vector2i(int(at.x * k), int(at.y * k)) - size / 2).clamp(Vector2i.ZERO, img.get_size() - size)
	img.get_region(Rect2i(pos, size)).save_png(tag + "_crop.png")
	get_tree().quit()


func _place(root: Node3D, path: String, origin: Vector3, rng: RandomNumberGenerator) -> void:
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var part: String = String((mi.get_meta("extras", {}) as Dictionary).get("part", ""))
		var c: Vector3 = mi.position
		var sz: Vector3 = mi.get_aabb().size
		var out := MeshInstance3D.new()
		out.mesh = mi.mesh
		root.add_child(out)
		if STAY.has(part):
			out.position = Vector3(origin.x + c.x, TerrainHeight.ground_y(origin.x + c.x, origin.z + c.z) + c.y, origin.z + c.z)
			continue
		var x: float = origin.x + c.x * 1.25 + rng.randf_range(-0.1, 0.1)
		var z: float = origin.z + c.z * 1.25 + rng.randf_range(-0.12, 0.12)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var rest: float = sz.y * 0.5
		if sz.y > sz.z * 1.2:
			# високий шматок лягає: повертається довкола своєї осі X на ~90° і опускається на товщину z
			b = b * Basis(Vector3.RIGHT, rng.randf_range(1.4, 1.7) * (1.0 if rng.randf() < 0.5 else -1.0))
			rest = sz.z * 0.5
		out.basis = b
		out.position = Vector3(x, TerrainHeight.ground_y(x, z) + rest + 0.003, z)
	scene.free()


func _field_cell(board: Board, bank: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	var centre := Vector2(board.width, board.height) * 0.5
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if board.kind_at(c) != Terrain.Kind.FIELD:
				continue
			var ok: bool = not bank
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if bank and board.in_bounds(c + d) and board.kind_at(c + d) == Terrain.Kind.WATER:
					ok = true
			if ok and Vector2(c).distance_to(centre) < best_d:
				best_d = Vector2(c).distance_to(centre)
				best = c
	return best
