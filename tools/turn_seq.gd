extends Node
## Знімає, як танк проходить поворот маршруту, справжнім екраном бою в реальному часі: чи
## дуга повороту лягає на заокруглення дороги, чи не смикається ніс. Кадри тримаються в
## пам'яті й пишуться в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . --position 6000,0 res://tools/turn_seq.tscn -- <out_dir> <map> <zoom> <road|stair> <кадрів/с> [turn]
## turn — юніт стоїть боком до першого кроку: видно доворот на місці перед стартом.
## road — перший кут дороги з трьома прямими клітинками з кожного боку; stair — сходинка
## по полю біля центру карти.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(720, 620)
const MEDIUM_TANK: int = 5
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 5:
		push_error("turn_seq: <out_dir> <map> <zoom> <road|stair> <fps>")
		get_tree().quit(1)
		return
	print("TURN start")
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	var cells: Array[Vector2i] = _road_corner(map) if a[3] == "road" else _stair(map)
	if cells.is_empty():
		push_error("turn_seq: no route found")
		get_tree().quit(1)
		return
	var start: Vector2i = cells[0]
	var path: Array[Vector2i] = cells.slice(1)
	var unit := Unit.create(999, MEDIUM_TANK, 0, start, (Board.facing_towards(start, path[0]) + (2 if a.size() > 5 and a[5] == "turn" else 0)) % 8)
	screen.call("_add_unit_view", unit)
	var view: UnitView = (screen.get("_unit_views") as Dictionary)[999]
	var mid: Vector2i = cells[cells.size() / 2]
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(mid)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var p: Vector3 = IsoCameraRig.cell_to_world(mid)
	var frames: Array[Image] = []
	# Кілька кадрів нерухомого старту: видно позу до руху.
	for f in 5:
		await RenderingServer.frame_post_draw
		frames.append(_crop(cam, p))
	var tween: Tween = view.move_along(path, EventPlayer._MOVE_STEP_DURATION).get_object()
	var dt: float = 1.0 / float(a[4])
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var tail: int = 0
	while tail < 10:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if el >= next:
			frames.append(_crop(cam, p))
			next += dt
			if not tween.is_running():
				tail += 1
	print("TURN %s %s z%s cells=%s frames=%d" % [a[1], a[3], a[2], cells, frames.size()])
	for i in frames.size():
		frames[i].save_png("%s/f_%04d.png" % [a[0], i])
	get_tree().quit()


func _crop(cam: Camera3D, p: Vector3) -> Image:
	var img: Image = get_viewport().get_texture().get_image()
	var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var base: Vector2 = cam.unproject_position(p)
	var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y / 2)
	return img.get_region(Rect2i(pos.clamp(Vector2i.ZERO, img.get_size() - CROP), CROP))


func _kind(map: MapData, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= map.width or c.y >= map.height:
		return -1
	return map.tiles[c.y * map.width + c.x]


## Перший кут дороги: дві дорожні сусідки під прямим кутом і по три прямі дорожні клітинки
## на кожному плечі — так видно і пряму, і дугу.
func _road_corner(map: MapData) -> Array[Vector2i]:
	for y in map.height:
		for x in map.width:
			var c := Vector2i(x, y)
			if _kind(map, c) != Terrain.Kind.ROAD:
				continue
			var arms: Array[Vector2i] = []
			for d in DIRS:
				if _kind(map, c + d) == Terrain.Kind.ROAD:
					arms.append(d)
			if arms.size() != 2 or arms[0] + arms[1] == Vector2i.ZERO:
				continue
			var ok := true
			for d in arms:
				for i in range(1, 4):
					ok = ok and _kind(map, c + d * i) == Terrain.Kind.ROAD
			if not ok:
				continue
			var out: Array[Vector2i] = []
			for i in range(3, 0, -1):
				out.append(c + arms[0] * i)
			out.append(c)
			for i in range(1, 4):
				out.append(c + arms[1] * i)
			return out
	return []


## Сходинка з одиничних кроків по полю біля центру: найтісніший випадок, дуги навпіл.
func _stair(map: MapData) -> Array[Vector2i]:
	for r in range(0, max(map.width, map.height)):
		for y in range(map.height / 2 - r, map.height / 2 + r + 1):
			for x in range(map.width / 2 - r, map.width / 2 + r + 1):
				var out: Array[Vector2i] = [Vector2i(x, y)]
				for i in 6:
					out.append(out[-1] + (Vector2i(1, 0) if i % 2 == 0 else Vector2i(0, 1)))
				var ok := true
				for c in out:
					ok = ok and _kind(map, c) == Terrain.Kind.FIELD
				if ok:
					return out
	return []
