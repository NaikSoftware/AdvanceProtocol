extends Node
## Зламані моделі на справжньому ґрунті карти (екран бою: рельєф, ґрунт, світло й небо карти), камерою гри, з тими самими
## матеріалами, що й цілі пропси в бою (PropLayer._tuned_mesh: притемнені опори, prop_thin для парканів). Поруч із розкиданими
## шматками стоїть цілий примірник тієї ж моделі, щоб порівняти яскравість.
## Запуск (потрібне вікно, не --headless):
##   tools/godot_run.sh --path . res://tools/broken_board_shot.tscn -- <out_dir> <map> <zoom> <model,model,...|all> [x,y] [--bank]
## --bank: клітинка поля біля води (мул на River); без x,y — клітинка поля найближча до центру дошки.
## Кожна модель — свій кадр <out_dir>/<map>_z<zoom>_<model>.png і вирізка 1:1 _crop.png; у лог іде
## LUM <model> intact=<середня>/<верхні 10 %> pieces=<середня>/<верхні 10 %>: яскравість пікселів, що відрізняються від
## порожнього кадру, окремо для цілого примірника (ліворуч) і шматків (праворуч).
## Цілий примірник паркану двору — зібрані шматки, а не справжній батч-вузол (той вибирає вид через INSTANCE_CUSTOM).

const SETTLE_FRAMES: int = 90
const STAY: Array[String] = ["stump", "berm", "plinth"]
const ALL: Array[String] = ["infra_pole_concrete_10kv", "infra_pole_concrete_04kv", "infra_pole_wood", "infra_fence_picket",
		"infra_fence_sheet_green", "infra_fence_sheet_brown", "infra_fence_euro", "infra_fence_yard_picket",
		"infra_fence_yard_sheet", "infra_fence_yard_chainlink", "infra_fence_yard_brickbars", "infra_fence_yard_slat"]
const SIDE: float = 0.55   # зсув цілого й розкиданого від клітинки вздовж Z, тайлів

var _cam: Camera3D


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("broken_board_shot: <out_dir> <map> <zoom> <models|all> [x,y] [--bank]")
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
	var models: Array[String] = ALL.duplicate() if a[3] == "all" else Array(a[3].split(","), TYPE_STRING, "", null)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	rig.center_on(cell)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	_cam = get_viewport().get_camera_3d()
	var root := Node3D.new()
	(screen.get_node("%BoardView") as Node3D).add_child(root)
	await _settle()
	var empty: Image = get_viewport().get_texture().get_image()
	var rng := RandomNumberGenerator.new()
	for m in models:
		for c in root.get_children():
			c.free()
		rng.seed = 7
		var o := Vector3(float(cell.x), 0.0, float(cell.y))
		_place(root, m, o + Vector3(0, 0, -SIDE), rng, false)
		_place(root, m, o + Vector3(0, 0, SIDE), rng, true)
		await _settle()
		var img: Image = get_viewport().get_texture().get_image()
		var tag: String = "%s/%s_z%s_%s" % [a[0], a[1], a[2], m]
		img.save_png(tag + ".png")
		var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
		var p_i: Vector2 = _cam.unproject_position(root.to_global(o + Vector3(0, 0.05, -SIDE))) * k
		var p_p: Vector2 = _cam.unproject_position(root.to_global(o + Vector3(0, 0.05, SIDE))) * k
		var size := Vector2i(560, 360)
		var mid := Vector2i(((p_i + p_p) * 0.5).round())
		var pos := (mid - size / 2).clamp(Vector2i.ZERO, img.get_size() - size)
		img.get_region(Rect2i(pos, size)).save_png(tag + "_crop.png")
		var li: Vector2 = _lum(img, empty, p_i, 90.0 * k)
		var lp: Vector2 = _lum(img, empty, p_p, 90.0 * k)
		print("LUM %s intact=%.1f/%.1f pieces=%.1f/%.1f" % [m, li.x, li.y, lp.x, lp.y])
	get_tree().quit()


func _settle() -> void:
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## Середня й верхні-10-% яскравість (0..255) пікселів у квадраті навколо точки, що помітно відрізняються від порожнього кадру.
func _lum(img: Image, empty: Image, at: Vector2, r: float) -> Vector2:
	var vals: Array[float] = []
	var x0: int = maxi(0, int(at.x - r))
	var x1: int = mini(img.get_width() - 1, int(at.x + r))
	var y0: int = maxi(0, int(at.y - r))
	var y1: int = mini(img.get_height() - 1, int(at.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c: Color = img.get_pixel(x, y)
			var e: Color = empty.get_pixel(x, y)
			if absf(c.r - e.r) + absf(c.g - e.g) + absf(c.b - e.b) > 0.06:
				vals.append((0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0)
	if vals.is_empty():
		return Vector2.ZERO
	vals.sort()
	var sum: float = 0.0
	for v in vals:
		sum += v
	var top: int = maxi(1, vals.size() / 10)
	var tsum: float = 0.0
	for i in range(vals.size() - top, vals.size()):
		tsum += vals[i]
	return Vector2(sum / vals.size(), tsum / top)


## Модель, за чиїм описом (spec) ставляться матеріали: паркани двору — вид штахету, бо їхні шматки мають власні UV
## (обрізаний атлас), а не батч-шейдер із вибором виду.
func _spec_name(model: String) -> StringName:
	return &"infra_fence_picket" if model.begins_with("infra_fence_yard_") else StringName(model)


func _tuned(model: String, mi: MeshInstance3D, top: float) -> Mesh:
	var mesh: Mesh = PropLayer._tuned_mesh(_spec_name(model), mi.mesh, [])
	for s in mesh.get_surface_count():
		var sm := mesh.surface_get_material(s) as ShaderMaterial
		if sm != null and sm.get_shader_parameter("top_local") != null:
			# верх секції в координатах шматка (його початок — у центрі мас), як у цілої моделі
			sm.set_shader_parameter("top_local", top - mi.position.y)
	return mesh


func _place(root: Node3D, model: String, origin: Vector3, rng: RandomNumberGenerator, scatter: bool) -> void:
	var scene: Node3D = (load("res://assets/props/broken/%s_broken.glb" % model) as PackedScene).instantiate()
	var top: float = 0.0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, mi.position.y + mi.get_aabb().end.y)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var part: String = String((mi.get_meta("extras", {}) as Dictionary).get("part", ""))
		var c: Vector3 = mi.position
		var sz: Vector3 = mi.get_aabb().size
		var out := MeshInstance3D.new()
		out.mesh = _tuned(model, mi, top)
		root.add_child(out)
		if not scatter or STAY.has(part):
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
