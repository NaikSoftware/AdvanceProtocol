extends Node
## Знімає міни й політ дрона справжнім екраном бою: обрізки лежать у пам'яті й пишуться в кінці
## (save_png блокує ~1 с). Не входить у гру. Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/ordnance_shot.tscn -- <out_dir> <map> mines <zoom>
##   $GODOT --path . res://tools/ordnance_shot.tscn -- <out_dir> <map> drone <zoom>
## mines: для дороги й поля пара клітинок (своя + розкрита ворожа), по кадру на кожну.
## drone: шість кадрів польоту від клітинки до клітинки за 4 тайли, останній — після влучання.
## dc: викликів малювання без мін і з десятьма.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 90
const CROP: Vector2i = Vector2i(560, 360)
const DRONE_TIMES: Array[float] = [0.04, 0.2, 0.4, 0.6, 0.85, 1.05]

var _screen: BattleScreen
var _rig: IsoCameraRig
var _map: MapData
var _out: String


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	_out = a[0]
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = WINDOW
	_screen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(_screen)
	_map = load("res://maps/%s.tres" % a[1]) as MapData
	_screen.setup(_map, 2, 1)
	_rig = _screen.get_node("%CameraRig")
	await _settle()
	match a[2]:
		"mines": await _mines(a[1], float(a[3]))
		"drone": await _drone(a[1], float(a[3]))
		"dc": await _dc()
	get_tree().quit()


func _settle(n: int = SETTLE_FRAMES) -> void:
	for f in n:
		await get_tree().process_frame


func _frame(at: Vector3) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var base: Vector2 = get_viewport().get_camera_3d().unproject_position(at)
	var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y / 2).clamp(Vector2i.ZERO, img.get_size() - CROP)
	return img.get_region(Rect2i(pos, CROP))


## Дві сусідні клітинки одного виду ґрунту: на дорозі й на полі.
func _pair(kind: int) -> Vector2i:
	for y in _map.height:
		for x in _map.width - 1:
			var p := Vector2i(x, y)
			if _map.tiles[y * _map.width + x] == kind and _map.tiles[y * _map.width + x + 1] == kind \
					and _map.tiles[y * _map.width + x + 2 if x + 2 < _map.width else y * _map.width + x] == kind \
					and x > 3 and y > 3 and x < _map.width - 4 and y < _map.height - 4:
				return p
	return Vector2i(-1, -1)


func _state_with(cells: Array[Vector2i]) -> BattleState:
	var st: BattleState = BattleState.create(_map.to_board(), 2, 7)
	for i in cells.size():
		Mines.place(st, cells[i], i % 2)
		if i % 2 == 1:
			st.mines[i].known_to[0] = true
	return st


func _mines(map_name: String, zoom: float) -> void:
	var layer: MineLayer = _screen.get_node("%MineLayer")
	var frames: Dictionary = {}
	for kind: int in [Terrain.Kind.ROAD, Terrain.Kind.FIELD]:
		var p: Vector2i = _pair(kind)
		if p.x < 0:
			continue
		layer.rebuild(_state_with([p, p + Vector2i(1, 0)] as Array[Vector2i]), 0)
		_rig.center_on(p)
		_rig.zoom_by(zoom / _rig.zoom_level)
		await _settle(40)
		frames["%s_%d" % [map_name, kind]] = await _frame(IsoCameraRig.cell_to_world(p) + Vector3(0.5, 0, 0))
	for k: String in frames:
		(frames[k] as Image).save_png("%s/mine_%s_z%d.png" % [_out, k, int(zoom)])


func _drone(map_name: String, zoom: float) -> void:
	var p: Vector2i = _pair(Terrain.Kind.FIELD)
	var q: Vector2i = p + Vector2i(3, 2)
	_rig.center_on(p + Vector2i(1, 1))
	_rig.zoom_by(zoom / _rig.zoom_level)
	await _settle(60)
	var units: Node = _screen.get("_units")
	var from: Vector3 = IsoCameraRig.cell_to_world(p)
	var to: Vector3 = IsoCameraRig.cell_to_world(q)
	BattleFx.spawn_drone(units, from, to)
	var hit_done: bool = false
	var frames: Array[Image] = []
	var t0: int = Time.get_ticks_usec()
	var i: int = 0
	while i < DRONE_TIMES.size():
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if not hit_done and el >= BattleFx.DRONE_FLIGHT_SEC:
			BattleFx.spawn_hit(units, to, BattleFx.Weapon.DRONE, true)
			hit_done = true
		if el >= DRONE_TIMES[i]:
			frames.append(await _frame((from + to) * 0.5 + Vector3(0, 0.5, 0)))
			i += 1
	for j in frames.size():
		frames[j].save_png("%s/drone_%s_z%d_%d.png" % [_out, map_name, int(zoom), j])


func _dc() -> void:
	var layer: MineLayer = _screen.get_node("%MineLayer")
	var p: Vector2i = _pair(Terrain.Kind.FIELD)
	_rig.center_on(p)
	await _settle(40)
	var base: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var cells: Array[Vector2i] = []
	for i in 10:
		cells.append(p + Vector2i(i % 5, i / 5))
	layer.rebuild(_state_with(cells), 0)
	await _settle(10)
	var withm: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("DC none=%d with10=%d" % [base, withm])
