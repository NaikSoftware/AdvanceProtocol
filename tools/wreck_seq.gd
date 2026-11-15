extends Node
## Знімає уламки, що горять чи димлять, справжнім екраном бою в реальному часі, після заданого часу
## матчу: так видно, чи вогонь і дим не псуються, коли годинник ефектів виріс. Кадри тримаються в
## пам'яті й пишуться в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . --position 6000,0 res://tools/wreck_seq.tscn -- <out_dir> <map> <zoom> <life> <секунд> <кадрів/с> <секунд матчу> [nodepth|-] [x,y]
## life — частка горіння (1 — горить, 0,5 — вщухає, 0,25 — лише дим). Уламки — на полі біля центру карти.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(560, 620)
## Тип уламка за замовчуванням; змінна середовища WRECK_TYPE ставить інший (гармата, інженерна машина).
const MEDIUM_TANK: int = 5


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 7:
		push_error("wreck_seq: <out_dir> <map> <zoom> <life> <sec> <fps> <t0>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	# Дев'ятий аргумент x,y — клітинка уламків (напр. берег ставка); інакше поле біля центру.
	var cell := _field_near_centre(map)
	# WRECK_AT: shore (поле біля води), bridge (міст), інакше поле біля центру; WRECK_FACING — напрям гармати;
	# WRECK_NOBODIES — без тіл розрахунку (пара для порівняння)
	var at: String = OS.get_environment("WRECK_AT")
	if at != "":
		cell = _find_cell(map, at, cell)
	if a.size() > 8 and a[8].contains(","):
		cell = Vector2i(int(a[8].get_slice(",", 0)), int(a[8].get_slice(",", 1)))
	var layer: WreckLayer = screen.get("_wreck_layer")
	layer.set("_frame", int(float(a[6]) * WreckLayer.FLIPBOOK_FPS))
	# Народився давно: стовп уже повний, як у перебудованих зі стану уламків.
	var wtype: int = int(OS.get_environment("WRECK_TYPE")) if OS.get_environment("WRECK_TYPE") != "" else MEDIUM_TANK
	var wfacing: int = int(OS.get_environment("WRECK_FACING"))
	layer.set("_board", (screen.call("_state") as BattleState).board)
	layer.call("_add_node", cell, wtype, float(a[3]), wfacing, WreckLayer.LONG_AGO)
	if Casualties.has_crew(wtype) and OS.get_environment("WRECK_NOBODIES") == "":
		# розрахунок знищеної гармати лягає біля уламка
		layer.add_body(Casualties.Body.new(1, cell, 0, wtype, wfacing, 0, Casualties.CREW_FIGURES))
	if OS.get_environment("WRECK_SQUAD") != "" and OS.get_environment("WRECK_NOBODIES") == "":
		# для сравнения тону: тіла відділення на сусідньому тайлі, без вогню поруч
		layer.add_body(Casualties.Body.new(2, cell + Vector2i(2, 0), 0, 0, 0, 1, 3))
	layer.call("_refresh_effects")
	# nodepth — стовп диму без перевірки глибини й м'якого краю: чи ховає його щось непрозоре геометрично, а не порядком.
	if a.size() > 7 and a[7] == "nodepth":
		var sh := Shader.new()
		sh.code = WreckLayer.column_shader().code.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,").replace(
				"ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);", "")
		(layer.get("_column_mat") as ShaderMaterial).shader = sh
	var p: Vector3 = layer.to_global(layer.fire_centre(cell)) if layer.flame_size(cell).x > 0.0 else layer.to_global(IsoCameraRig.cell_to_world(cell))
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var fx_t0: float = layer.fx_time()
	print("WRECK geometry: lean=%s cam_fwd=%s root=%s" % [(layer.get("_column_mat") as ShaderMaterial).get_shader_parameter("lean"), -cam.global_transform.basis.z, layer.to_global(layer.fire_centre(cell)) if layer.flame_size(cell).x > 0.0 else Vector3.ZERO])
	var frames: Array[Image] = []
	var dt: float = 1.0 / float(a[5])
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var secs: float = float(a[4])
	while true:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if el >= next:
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var base: Vector2 = cam.unproject_position(p)
			var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y * 2 / 3)
			pos = pos.clamp(Vector2i.ZERO, img.get_size() - CROP)
			frames.append(img.get_region(Rect2i(pos, CROP)))
			next += dt
		if el >= secs:
			break
	print("WRECK %s z%s life=%s frames=%d fx_t=%.1f..%.1f cell=%s" % [a[1], a[2], a[3], frames.size(), fx_t0, layer.fx_time(), cell])
	for i in frames.size():
		frames[i].save_png("%s/f_%04d.png" % [a[0], i])
	get_tree().quit()


## Поле з водою поруч (shore) чи міст (bridge) найближче до центру; `fallback`, коли такого нема.
func _find_cell(map: MapData, what: String, fallback: Vector2i) -> Vector2i:
	var c := Vector2i(map.width / 2, map.height / 2)
	var best: Vector2i = fallback
	var best_d: int = 1 << 30
	for y in range(1, map.height - 1):
		for x in range(1, map.width - 1):
			var k: int = map.tiles[y * map.width + x]
			var ok: bool = false
			if what == "bridge":
				ok = k == Terrain.Kind.BRIDGE
			elif what == "shore" and k == Terrain.Kind.FIELD:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					ok = ok or map.tiles[(y + d.y) * map.width + x + d.x] == Terrain.Kind.WATER
			if ok:
				var dd: int = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
				if dd < best_d:
					best_d = dd
					best = Vector2i(x, y)
	return best


## Найближча до центру клітинка поля: уламки стоять на землі, не у воді й не в хаті.
func _field_near_centre(map: MapData) -> Vector2i:
	var c := Vector2i(map.width / 2, map.height / 2)
	var best := c
	var best_d: int = 1 << 30
	for y in map.height:
		for x in map.width:
			if map.tiles[y * map.width + x] == Terrain.Kind.FIELD:
				var d: int = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best
