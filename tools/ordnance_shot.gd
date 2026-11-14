extends Node
## Знімає міни й політ дрона справжнім екраном бою; кадри лежать у пам'яті й пишуться в кінці
## (save_png блокує ~1 с). Не входить у гру. Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/ordnance_shot.tscn -- <out_dir> <map> <режим> <zoom> [тег]
## режими:
##   mines — пара (своя + розкрита ворожа) на дорозі, лузі й ріллі: mine_<тег>_<map>_<road|grass|plough>_z<zoom>.png
##   drone — справжній загін і справжня ціль: кадри польоту на всю дошку й 30 к/с довкола цілі
##   dc    — викликів малювання без мін і з десятьма
##   diff  — той самий кадр без міни й з нерозкритою ворожою: найбільша різниця пікселів

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 90
const CROP: Vector2i = Vector2i(560, 360)
const ASSAULT: int = 1
const MEDIUM_TANK: int = 5

var _screen: BattleScreen
var _rig: IsoCameraRig
var _map: MapData
var _out: String


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	_out = a[0]
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = WINDOW
	_map = (load("res://maps/%s.tres" % a[1]) as MapData).duplicate()
	_screen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(_screen)
	var zoom: float = float(a[3])
	var p: Vector2i = _pair(Terrain.Kind.FIELD, MapData.FieldSurface.MEADOW)
	if a[2] == "drone":
		# Справжній загін дронів і справжня ціль-танк на лузі, обидва розвідані.
		var spawns: Array[Dictionary] = [
			{"type_id": ASSAULT, "owner": 0, "pos": p, "facing": 2},
			{"type_id": MEDIUM_TANK, "owner": 1, "pos": p + Vector2i(3, 2), "facing": 6}]
		_map.spawns = spawns
	_screen.setup(_map, 2, 1)
	_rig = _screen.get_node("%CameraRig")
	var st: BattleState = MatchService.state
	for pl in st.player_count:
		st.vision[pl].seen.fill(1)
	_screen._rebuild_units_for_active_player(true)
	await _settle()
	match a[2]:
		"mines": await _mines(a[1], zoom, a[4])
		"drone": await _drone(a[1], zoom, p)
		"dc": await _dc()
		"diff": await _diff(zoom)
		"ring3": await _ring3(a[1], zoom)
	get_tree().quit()


func _settle(n: int = SETTLE_FRAMES) -> void:
	for f in n:
		await get_tree().process_frame


func _crop(at: Vector3) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var base: Vector2 = get_viewport().get_camera_3d().unproject_position(at)
	var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y / 2).clamp(Vector2i.ZERO, img.get_size() - CROP)
	return img.get_region(Rect2i(pos, CROP))


## Ліва клітинка пари сусідніх клітинок, довкола яких найбільше клітинок цього виду (4 × 3); surf —
## підтип поверхні (−1 — будь-який). Мін на дорозі інакше стояла б біля узбіччя.
func _pair(kind: int, surf: int = -1) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n: int = -1
	for y in range(2, _map.height - 3):
		for x in range(2, _map.width - 4):
			var n: int = 0
			var here := Vector2i(x, y)
			# Обидві клітинки пари мають бути саме цього виду й підтипу.
			if _map.tiles[y * _map.width + x] != kind or _map.tiles[y * _map.width + x + 1] != kind \
					or (surf >= 0 and (_map.surface_at(here) != surf or _map.surface_at(here + Vector2i(1, 0)) != surf)):
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 3):
					var q := Vector2i(x + dx, y + dy)
					if _map.tiles[q.y * _map.width + q.x] == kind and (surf < 0 or _map.surface_at(q) == surf):
						n += 1
			if n > best_n:
				best_n = n
				best = Vector2i(x, y)
	return best


func _state_with(cells: Array[Vector2i]) -> BattleState:
	var st: BattleState = BattleState.create(_map.to_board(), 2, 7)
	for i in cells.size():
		Mines.place(st, cells[i], i % 2)
		if i % 2 == 1:
			st.mines[i].known_to[0] = true
	return st


func _mines(map_name: String, zoom: float, tag: String) -> void:
	var layer: MineLayer = _screen.get_node("%MineLayer")
	var frames: Dictionary = {}
	for spec: Array in [["road", Terrain.Kind.ROAD, -1], ["grass", Terrain.Kind.FIELD, MapData.FieldSurface.MEADOW],
			["plough", Terrain.Kind.FIELD, MapData.FieldSurface.PLOUGHED]]:
		var p: Vector2i = _pair(spec[1], spec[2])
		layer.rebuild(_state_with([p, p + Vector2i(1, 0)] as Array[Vector2i]), 0)
		_rig.center_on(p)
		_rig.zoom_by(zoom / _rig.zoom_level)
		await _settle(40)
		frames[spec[0]] = await _crop(IsoCameraRig.cell_to_world(p) + Vector3(0.5, 0, 0))
	for k: String in frames:
		(frames[k] as Image).save_png("%s/mine_%s_%s_%s_z%d.png" % [_out, tag, map_name, k, int(zoom)])


## Загін пускає дрон по цілі; кадри буферизуються, пишуться в кінці. wide — вся траса (шість кадрів
## на поточному зумі), target — 30 к/с довкола цілі від 0,6 с до 1,1 с після команди.
func _drone(map_name: String, zoom: float, p: Vector2i) -> void:
	_rig.center_on(p + Vector2i(1, 1))
	_rig.zoom_by(zoom / _rig.zoom_level)
	await _settle(60)
	var st: BattleState = MatchService.state
	var squad: Unit = st.unit_at(p)
	var tank: Unit = st.unit_at(p + Vector2i(3, 2))
	var mid: Vector3 = IsoCameraRig.cell_to_world(p + Vector2i(1, 1)) + Vector3(0, 0.4, 0)
	var tgt: Vector3 = IsoCameraRig.cell_to_world(tank.pos)
	var err: String = MatchService.submit(DroneCommand.create(squad.id, tank.id))
	print("DRONE submit: '%s'" % err)
	var t0: int = Time.get_ticks_usec()
	var wide: Array = []
	var target: Array = []
	var next_w: float = 0.0
	var last_t: float = -1.0
	while true:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if el >= next_w and wide.size() < 10:
			wide.append([el, await _crop(mid)])
			next_w += 0.25
		if el >= 0.6 and el <= 1.5 and el - last_t >= 1.0 / 30.0:
			target.append([el, await _crop(tgt + Vector3(0, 0.1, 0))])
			last_t = el
		if el > 2.6:
			break
	for f: Array in wide:
		(f[1] as Image).save_png("%s/drone_%s_z%d_wide_%03d.png" % [_out, map_name, int(zoom), int(f[0] * 1000.0)])
	for f: Array in target:
		(f[1] as Image).save_png("%s/drone_%s_z%d_target_%03d.png" % [_out, map_name, int(zoom), int(f[0] * 1000.0)])


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


func _full() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _max_diff(a: Image, b: Image) -> Array:
	var worst: int = 0
	var count: int = 0
	for y in a.get_height():
		for x in a.get_width():
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var d: int = maxi(maxi(absi(ca.r8 - cb.r8), absi(ca.g8 - cb.g8)), absi(ca.b8 - cb.b8))
			if d > 0:
				count += 1
			worst = maxi(worst, d)
	return [worst, count]


## Нерозкрита ворожа міна для глядача: кадр дошки з водою й відбиттями той самий, що й без неї.
## Міна кладеться в справжній стан матчу, екран перебудовує шар для активного гравця. Водяна
## анімація дає власний шум, тож порівнюємо ще й два кадри БЕЗ зміни.
func _diff(zoom: float) -> void:
	var st: BattleState = MatchService.state
	var water := Vector2i(-1, -1)
	for y in _map.height:
		for x in _map.width:
			if water.x < 0 and _map.tiles[y * _map.width + x] == Terrain.Kind.WATER and x > 3 and y > 3 and x < _map.width - 4 and y < _map.height - 4:
				water = Vector2i(x, y)
	var land := Vector2i(-1, -1)
	for d in range(1, 6):
		for dx in range(-d, d + 1):
			var q := water + Vector2i(dx, d)
			if land.x < 0 and st.board.in_bounds(q) and st.board.kind_at(q) == Terrain.Kind.FIELD:
				land = q
	_rig.center_on(land)
	_rig.zoom_by(zoom / _rig.zoom_level)
	await _settle(60)
	var a: Image = await _full()
	var shots: Array[Image] = []
	for i in 3:
		_screen._rebuild_units_for_active_player(true)
		await _settle(60)
		shots.append(await _full())
	Mines.place(st, land, 1)
	_screen._rebuild_units_for_active_player(true)
	await _settle(60)
	var b: Image = await _full()
	# Вода анімована: кадри без міни різняться між собою. Піксель «стабільний», якщо він однаковий у
	# трьох кадрах без міни; міна має лишити нуль різниці саме там, а на воді — не більше шуму.
	var noise: Array = _max_diff(a, shots[0])
	var stable_diff: int = 0
	var stable_n: int = 0
	var water_diff: int = 0
	var control: int = 0
	for y in a.get_height():
		for x in a.get_width():
			var c: Color = a.get_pixel(x, y)
			var d_b: int = maxi(maxi(absi(c.r8 - b.get_pixel(x, y).r8), absi(c.g8 - b.get_pixel(x, y).g8)), absi(c.b8 - b.get_pixel(x, y).b8))
			if c == shots[0].get_pixel(x, y) and c == shots[1].get_pixel(x, y):
				stable_n += 1
				stable_diff = maxi(stable_diff, d_b)
				var q: Color = shots[2].get_pixel(x, y)
				control = maxi(control, maxi(maxi(absi(c.r8 - q.r8), absi(c.g8 - q.g8)), absi(c.b8 - q.b8)))
			else:
				water_diff = maxi(water_diff, d_b)
	print("DIFF water=%s land=%s mine_layer_children=%d noise_max=%d noise_px=%d stable_px=%d max_diff_on_stable=%d max_diff_on_animated=%d control_no_mine_on_stable=%d" % [
		water, land, _screen.get_node("%MineLayer").get_child_count(), noise[0], noise[1], stable_n, stable_diff, water_diff, control])
	a.save_png("%s/diff_a.png" % _out)
	b.save_png("%s/diff_b.png" % _out)


## Кільця трьох гравців на лузі: колір третього (зелений) проти трави.
func _ring3(map_name: String, zoom: float) -> void:
	var layer: MineLayer = _screen.get_node("%MineLayer")
	var p: Vector2i = _pair(Terrain.Kind.FIELD, MapData.FieldSurface.MEADOW)
	var st: BattleState = BattleState.create(_map.to_board(), 3, 7)
	for i in 3:
		Mines.place(st, p + Vector2i(i, 0), i)
		st.mines[i].known_to[0] = true
	layer.rebuild(st, 0)
	_rig.center_on(p)
	_rig.zoom_by(zoom / _rig.zoom_level)
	await _settle(40)
	(await _crop(IsoCameraRig.cell_to_world(p) + Vector3(1.0, 0, 0))).save_png("%s/ring3_%s_z%d.png" % [_out, map_name, int(zoom)])
	print("RING3 colours ", [UnitView.hp_fill_color(0), UnitView.hp_fill_color(1), UnitView.hp_fill_color(2)])
