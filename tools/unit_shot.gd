extends Node
## Знімає модель юніта на справжньому екрані бою: дві моделі й коробка-заступник поруч для
## масштабу, на зумі 6 (найближчий), 8 і 20 (найдальший), і чотири кадри руху на зумі 8, поки один танк
## їде на тайл уперед (гусениці й колеса мають крутитися). Кадри тримаються в пам'яті й пишуться
## в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/unit_shot.tscn -- <out_dir> <map> <type_id> [tag]
## Шостий аргумент pair=<type_b>:<facing> ставить type_id і type_b на сусідні тайли носом до носа
## (facing 0 — уздовж осі, 1 — по діагоналі) і знімає лише два зуми: чи не залазить ствол у сусіда.
## Шостий аргумент lineup ставить чотири танки справжніми юнітами трьох гравців (смуги HP у кольорі
## власника) і знімає один кадр на найближчому зумі; type_id тоді ігнорується.
## Сьомий аргумент set=N у звичайному режимі бере моделі набору N.
## Шостий аргумент gate [set=N] (його запускає tools/unit_contrast_gate.py) знімає модель типу type_id на найдальшому зумі на різних ґрунтах і біля
## лісу, кожне місце двома кадрами — з моделлю (_m), без (_e) і з моделлю суцільним пурпуром (_k, маска контуру) для ΔE.
## Шостий аргумент spin [set=N] ставить одну модель типу type_id нерухомо на найближчому зумі й знімає три кадри (_s0, _s1, _s2): перші два
## з однаковим `travel` (контроль), третій — на пів радіуса колеса далі; між ними мають змінитися лише колеса.
## Шостий аргумент rear [set=N] ставить чотири танки набору N (важкий, середній, винищувач, легкий) у ряд через тайл,
## самими моделями без смуг HP (смуга ховає ствол сусіда), і знімає на зумі 6 два кадри: тилом до камери (_f0) і носом до неї (_f4).
## Шостий аргумент sets ставить ті самі чотири танки для кожного з трьох гравців: рядки — набори
## (власники 0, 1, 2), стовпці — ролі (важкий, середній, винищувач, легкий); кадри на найближчому й найдальшому зумі, type_id ігнорується.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 60
## Скільки триває проїзд на один тайл і коли знімати кадри руху (чотири, у справжній швидкості).
const MOVE_SEC: float = 1.2
const MOVE_SHOTS: Array[float] = [0.2, 0.5, 0.8, 1.1]


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("unit_shot: <out_dir> <map> <type_id> [tag]")
		get_tree().quit(1)
		return
	var out: String = a[0]
	var tag: String = a[3] if a.size() > 3 else a[1]
	var type_id: int = int(a[2])
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	if a.size() > 5 and a[5] == "lineup":
		await _lineup(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "real":
		await _real(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "sets":
		await _sets(screen, map, out, tag, a.size() > 6 and a[6] == "forest", a.size() > 6 and a[6] == "sel")
		return
	if a.size() > 5 and a[5] == "squads":
		await _squads(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "facings":
		await _facings(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "walk":
		await _walk(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "squads_forest":
		await _squads_forest(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "forest_n2":
		await _forest_n2(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "forest_deep":
		await _forest_deep(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "fall":
		await _fall(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "guns_bridge":
		await _guns_bridge(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "squad_bridge":
		await _squad_bridge(screen, map, out, tag, int(a[6].substr(9)) if a.size() > 6 and a[6].begins_with("standing=") else 0)
		return
	if a.size() > 5 and a[5] == "bridge_seq":
		await _bridge_seq(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "shore":
		await _shore(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "spots":
		await _spots(screen, map, out, tag)
		return
	if a.size() > 5 and a[5] == "fleet":
		await _fleet(screen, map, out, tag, int(a[6].substr(4)) if a.size() > 6 and a[6].begins_with("set=") else 0)
		return
	if a.size() > 5 and a[5] == "rear":
		var rset: int = int(a[6].substr(4)) if a.size() > 6 and a[6].begins_with("set=") else 0
		await _rear(screen, map, out, tag, rset)
		return
	if a.size() > 5 and a[5] == "spin":
		await _spin(screen, map, out, tag, type_id, int(a[6].substr(4)) if a.size() > 6 and a[6].begins_with("set=") else 0)
		return
	if a.size() > 5 and a[5] == "gate":
		var gset: int = int(a[6].substr(4)) if a.size() > 6 and a[6].begins_with("set=") else 0
		# zoom=<z>: відділення міряються на найближчому, бо на найдальшому боєць — 2 × 6 пікселів
		var gzoom: float = float(a[7].substr(5)) if a.size() > 7 and a[7].begins_with("zoom=") else IsoCameraRig.MAX_ZOOM
		await _gate(screen, map, out, tag, type_id, gset, gzoom)
		return
	screen.setup(map, 2, 1)
	var cell := _field_near_centre(map)
	if a.size() > 5 and a[5].begins_with("pair="):
		var pv: PackedStringArray = a[5].substr(5).split(":")
		var f: int = int(pv[1])
		var ahead: Vector2i = Vector2i(0, -1) if f == 0 else Vector2i(1, -1)
		_place(UnitSilhouettes.build_merged(type_id), cell, f)
		_place(UnitSilhouettes.build_merged(int(pv[0])), cell + ahead, f + 4)
		var prig: IsoCameraRig = screen.get_node("%CameraRig")
		for fr in SETTLE_FRAMES:
			await get_tree().process_frame
		prig.center_on(cell)
		var pshots: Array = []
		for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
			prig.zoom_by(z / prig.zoom_level)
			for fr in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			pshots.append(["%s/%s_z%d.png" % [out, tag, int(z)], get_viewport().get_texture().get_image()])
		for ps: Array in pshots:
			(ps[1] as Image).save_png(ps[0])
		print("UNIT pair %s at %s: %d frames" % [a[5], cell, pshots.size()])
		get_tree().quit()
		return
	var set_id: int = int(a[6].substr(4)) if a.size() > 6 and a[6].begins_with("set=") else 0
	# Перша модель дивиться на північ, друга — на південний схід, коробка-заступник — ліворуч.
	# SHOT_FACING (0..7) повертає першу модель, друга лишається на три сектори далі: так знімають і «носом до камери»
	var f0: int = int(OS.get_environment("SHOT_FACING"))
	_place(UnitSilhouettes.build_merged(type_id, -1, set_id), cell, f0)
	_place(UnitSilhouettes.build_merged(type_id, -1, set_id), cell + Vector2i(1, 0), (f0 + 3) % 8)
	_place(UnitSilhouettes.build(type_id), cell + Vector2i(-1, 0), 0)
	var mover: Node3D = UnitSilhouettes.build_merged(type_id, -1, set_id)
	_place(mover, cell + Vector2i(0, 2), 0)
	print("UNIT placed at %s" % cell)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell + Vector2i(0, 1))
	var shots: Array = []
	for z: float in [IsoCameraRig.MIN_ZOOM, 8.0, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(["%s/%s_z%d.png" % [out, tag, int(z)], get_viewport().get_texture().get_image()])
	rig.zoom_by(8.0 / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	# Проїзд: вузол рухається на тайл до -Z, `travel` — пройдений шлях, як у UnitView.
	var hull := mover.get_node("Hull") as GeometryInstance3D
	var start: Vector3 = mover.position
	var t0: int = Time.get_ticks_usec()
	var next: int = 0
	while true:
		await get_tree().process_frame
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		var k: float = clampf(el / MOVE_SEC, 0.0, 1.0)
		mover.position = start + Vector3(0.0, 0.0, -k)
		mover.position.y = _ground(mover.position)
		hull.set_instance_shader_parameter("travel", k)
		if next < MOVE_SHOTS.size() and el >= MOVE_SHOTS[next]:
			await RenderingServer.frame_post_draw
			shots.append(["%s/%s_move%d.png" % [out, tag, next], get_viewport().get_texture().get_image()])
			print("UNIT move shot %d at %.2f s, travel %.3f" % [next, el, k])
			next += 1
		if k >= 1.0:
			break
	for s: Array in shots:
		(s[1] as Image).save_png(s[0])
	print("UNIT %s type %d cell %s: %d frames" % [a[1], type_id, cell, shots.size()])
	get_tree().quit()


func _place(n: Node3D, cell: Vector2i, facing: int) -> void:
	add_child(n)
	n.position = IsoCameraRig.cell_to_world(cell)
	n.rotation.y = -float(facing) * PI / 4.0
	n.position.y = _ground(n.position)


## Найвища точка рельєфу під кутами тайла навколо центру: модель не тоне в схилі.
func _ground(p: Vector3) -> float:
	var th: TerrainHeight = TerrainHeight.active
	if th == null:
		return 0.0
	var y: float = th.at(p.x, p.z)
	for d: Vector2 in [Vector2(-0.25, -0.45), Vector2(0.25, -0.45), Vector2(-0.25, 0.45), Vector2(0.25, 0.45)]:
		y = maxf(y, th.at(p.x + d.x, p.z + d.y))
	return y


## Найближча до центру клітинка поля, у якої поле й три сусіди праворуч, ліворуч і нижче.
## `field_only`: без щабля з дорогою; не знайшовши, повертає (−1, −1).
func _field_near_centre(map: MapData, near_forest: bool = false, need: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1)], clear: Array[Vector2i] = [], field_only: bool = false) -> Vector2i:
	var c := Vector2i(map.width / 2, map.height / 2)
	var no_water: Array[int] = [Terrain.Kind.WATER, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	# Щаблі від суворого до м'якого: юніти — на полі, довкола (`clear`) ні лісу, ні забудови, ні води (крони й стіни
	# налазять на сусідню клітинку, а вода біля відділення — це вже не поле, і кадр міряв би тон на річці); далі
	# дозволено ліс і забудову довкола; далі юніти й на дорозі. Вода довкола не дозволена ніколи.
	var stages: Array = [[[Terrain.Kind.FIELD], no_water + [Terrain.Kind.FOREST, Terrain.Kind.BUILDING]],
		[[Terrain.Kind.FIELD], no_water], [[Terrain.Kind.FIELD, Terrain.Kind.ROAD], no_water]]
	if field_only:
		stages.pop_back()
	for stage: Array in stages:
		var best := Vector2i(-1, -1)
		var best_d: int = 1 << 30
		for y in map.height:
			for x in map.width:
				var ok: bool = true
				for d: Vector2i in need:
					var q := Vector2i(x, y) + d
					if q.x < 0 or q.y < 0 or q.x >= map.width or q.y >= map.height or not (map.tiles[q.y * map.width + q.x] in stage[0]):
						ok = false
				for d: Vector2i in clear:
					var q := Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < map.width and q.y < map.height and map.tiles[q.y * map.width + q.x] in stage[1]:
						ok = false
				if ok and near_forest:
					# Поле з лісом за 3-4 клітинки: край лісу в кадрі разом із юнітами.
					ok = false
					for fy in range(maxi(0, y - 4), mini(map.height, y + 5)):
						for fx in range(maxi(0, x - 4), mini(map.width, x + 5)):
							if map.tiles[fy * map.width + fx] == Terrain.Kind.FOREST and maxi(absi(fx - x), absi(fy - y)) >= 3:
								ok = true
				var dd: int = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
				if ok and dd < best_d:
					best_d = dd
					best = Vector2i(x, y)
		if best.x >= 0:
			return best
	if field_only:
		return Vector2i(-1, -1)
	push_error("unit_shot: на карті нема поля під потрібні клітинки, беру середину")
	return c


## Найближча до центру клітинка поля, праворуч і ліворуч від якої є ще по `half` клітинок поля (рядок завширшки 2*half + 1).
func _field_row_near_centre(map: MapData, width: int) -> Vector2i:
	var half: int = width / 2
	var c := Vector2i(map.width / 2, map.height / 2)
	var best := c
	var best_d: int = 1 << 30
	for y in range(1, map.height - 1):
		for x in range(half, map.width - half):
			var ok: bool = true
			for dx in range(-half, half + 1):
				if map.tiles[y * map.width + x + dx] != Terrain.Kind.FIELD:
					ok = false
			var dd: int = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
			if ok and dd < best_d:
				best_d = dd
				best = Vector2i(x, y)
	if best_d == 1 << 30:
		push_error("unit_shot: на мапі немає рядка з %d клітинок поля, танки стануть у центрі на будь-якій місцевості" % width)
	return best


## Важкий і легкий — гравець 1, середній — 2, винищувач — 3; гравець 1 активний і бачить усіх поруч.
func _lineup(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	# копія без шляху взяла б типовий вигляд бою, а не погоду й сезон цієї карти
	m.take_over_path(map.resource_path)
	var c := _field_near_centre(m)
	m.spawns = [
		{"type_id": 8, "owner": 0, "pos": c + Vector2i(-1, 0), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": c, "facing": 0},
		{"type_id": 6, "owner": 2, "pos": c + Vector2i(1, 0), "facing": 0},
		{"type_id": 7, "owner": 0, "pos": c + Vector2i(1, 1), "facing": 0},
	]
	screen.setup(m, 3, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c + Vector2i(0, 0))
	rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
	for f in SETTLE_FRAMES * 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_z%d.png" % [out, tag, int(IsoCameraRig.MIN_ZOOM)])
	print("UNIT lineup at %s" % c)
	get_tree().quit()


## Справжні юніти двох гармат, інженерної машини й танка (смуги HP, крони, ґрунт карти) на найближчому й найдальшому зумі:
## остаточна перевірка впізнаваності гармат — разом із розрахунком, не окрема модель.
## Шостий аргумент guns_bridge: польова гармата й гаубиця на двох клітинках мосту, напрям — SHOT_FACING. Мост
## несе похідне положення гармат: станини зведені, розрахунок — з боків.
func _guns_bridge(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := Vector2i(m.width / 2, m.height / 2)
	var bridge: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			if m.tiles[y * m.width + x] == Terrain.Kind.BRIDGE:
				bridge.append(Vector2i(x, y))
	bridge.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return (p - c).length_squared() < (q - c).length_squared())
	var f0: int = int(OS.get_environment("SHOT_FACING"))
	m.spawns = [
		{"type_id": 9, "owner": 0, "pos": bridge[0], "facing": f0},
		{"type_id": 10, "owner": 1, "pos": bridge[1], "facing": f0},
	]
	screen.setup(m, 2, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(bridge[0])
	for z: float in [IsoCameraRig.MIN_ZOOM, 8.0]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_z%d.png" % [out, tag, int(z)])
	print("UNIT guns_bridge at %s %s" % [bridge[0], bridge[1]])
	get_tree().quit()


func _real(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := _field_near_centre(m)
	m.spawns = [
		{"type_id": 9, "owner": 0, "pos": c + Vector2i(-2, 0), "facing": 0},
		{"type_id": 10, "owner": 1, "pos": c, "facing": 0},
		{"type_id": 11, "owner": 2, "pos": c + Vector2i(2, 0), "facing": 0},
		{"type_id": 8, "owner": 0, "pos": c + Vector2i(0, 2), "facing": 0},
	]
	screen.setup(m, 3, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c)
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_z%d.png" % [out, tag, int(z)])
	print("UNIT real at %s" % c)
	get_tree().quit()


## Рядок на набір, стовпець на роль: так видно, що ролі читаються однаково в кожному наборі.
func _sets(screen: BattleScreen, map: MapData, out: String, tag: String, near_forest: bool = false, select: bool = false) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	# Кожен із дванадцяти танків стоїть на полі, і довкола них немає лісу чи забудови: на дворі
	# модель залазить у будівлю, а крони з сусідньої клітинки накривають танк.
	var cells: Array[Vector2i] = []
	var around: Array[Vector2i] = []
	for col in 4:
		for row in 3:
			cells.append(Vector2i(col - 1, row * 2 - 2))
	for dx in range(-2, 4):
		for dy in range(-3, 4):
			around.append(Vector2i(dx, dy))
	var c := _field_near_centre(m, near_forest, cells, around)
	var roles: Array[int] = [8, 5, 6, 7]
	m.spawns = []
	for owner in 3:
		for col in roles.size():
			m.spawns.append({"type_id": roles[col], "owner": owner, "pos": c + Vector2i(col - 1, owner * 2 - 2), "facing": (col * 3 + owner * 2) % 8})
	screen.setup(m, 3, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c)
	if select:
		# Виділений юніт гравця 1: контури зон лягають поверх плям-контактів.
		screen._controller.tap_cell(c + Vector2i(1, -2))
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
	# Найближчий, середній (8) і найдальший зум: тінь юніта на сонячних картах міняється з відстанню.
	for z: float in [IsoCameraRig.MIN_ZOOM, 8.0, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_z%d.png" % [out, tag, int(z)])
	print("UNIT sets at %s" % c)
	get_tree().quit()


## Танк на асфальті, на настилі мосту й на березі біля води: так видно, як пляма-контакт лягає на мокре
## покриття і воду. Кадри `<tag>_<road|bridge|shore>_z<зум>.png`.
func _spots(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var mid := Vector2i(m.width / 2, m.height / 2)
	var best: Dictionary = {}
	for y in range(1, m.height - 1):
		for x in range(1, m.width - 1):
			var p := Vector2i(x, y)
			var k: int = m.outer_kind_at(p)
			var want: String = ""
			if k == Terrain.Kind.ROAD:
				want = "road"
			elif k == Terrain.Kind.BRIDGE:
				want = "bridge"
			elif k == Terrain.Kind.FIELD:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if m.outer_kind_at(p + d) == Terrain.Kind.WATER:
						want = "shore"
			if want != "" and (not best.has(want) or (p - mid).length_squared() < (best[want] - mid).length_squared()):
				best[want] = p
	var names: Array = ["road", "bridge", "shore"]
	m.spawns = []
	for i in names.size():
		if best.has(names[i]):
			m.spawns.append({"type_id": 5, "owner": i, "pos": best[names[i]], "facing": 2})
	screen.setup(m, 3, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var shots: Array = []
	for n: String in best:
		rig.center_on(best[n])
		for z: float in [IsoCameraRig.MIN_ZOOM, 8.0]:
			rig.zoom_by(z / rig.zoom_level)
			for f in SETTLE_FRAMES * 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots.append(["%s/%s_%s_z%d.png" % [out, tag, n, int(z)], get_viewport().get_texture().get_image()])
	for sh: Array in shots:
		(sh[1] as Image).save_png(sh[0])
	print("UNIT spots %s" % str(best))
	get_tree().quit()


## Місця для виміру контрасту (їх читає tools/unit_contrast_gate.py): до чотирьох клітинок на вид поверхні поля
## (дев'ять сусідів того самого виду; назви field0a.. — луг, field1a.. — рілля) і клітинки поля за два-три кроки від лісу
## з кожного боку (forestE2, forestN3 ...). Модель дивиться на північ; камера однакова в обох кадрах, хмарні тіні вимкнені.
func _gate(screen: BattleScreen, map: MapData, out: String, tag: String, type_id: int, set_id: int, zoom: float = IsoCameraRig.MAX_ZOOM) -> void:
	screen.setup(map, 2, 1)
	var c := Vector2i(map.width / 2, map.height / 2)
	var picks: Dictionary = {}
	var relaxed: Dictionary = {}
	var sides: Dictionary = {}
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(4, map.height - 4):
		for x in range(4, map.width - 4):
			var p := Vector2i(x, y)
			if map.tiles[y * map.width + x] != Terrain.Kind.FIELD:
				continue
			var sv: int = map.surface_at(p)
			# 3x3 of one field surface; the visible ground is drawn in natural shapes, so up to three
			# well separated cells per surface are shot and the report keeps the ones that really are plough
			var same: bool = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var q := Vector2i(x + dx, y + dy)
					if map.tiles[q.y * map.width + q.x] != Terrain.Kind.FIELD or map.surface_at(q) != sv:
						same = false
			if same:
				if not picks.has(sv):
					picks[sv] = []
				picks[sv].append(p)
			# fallback when a surface has no uniform 3x3 anywhere: the cell's own surface, four orthogonal neighbours field
			var all_field: bool = true
			for d in dirs:
				if map.tiles[(y + d.y) * map.width + x + d.x] != Terrain.Kind.FIELD:
					all_field = false
			if all_field:
				if not relaxed.has(sv):
					relaxed[sv] = []
				relaxed[sv].append(p)
			# a field cell k = 2..3 cells from a forest in direction d (field in between and behind): k = 1 would sit under
			# the crown; the report decides which of these places really have darker ground
			for d in dirs:
				for kk in range(2, 4):
					var fk: Vector2i = p + d * kk
					if fk.x < 0 or fk.y < 0 or fk.x >= map.width or fk.y >= map.height:
						continue
					var clear: bool = true
					for j in range(0, kk):
						var q2: Vector2i = p + d * j
						if map.tiles[q2.y * map.width + q2.x] != Terrain.Kind.FIELD:
							clear = false
					var b0: Vector2i = p - d
					if clear and map.tiles[fk.y * map.width + fk.x] == Terrain.Kind.FOREST and map.tiles[b0.y * map.width + b0.x] == Terrain.Kind.FIELD:
						var key := Vector3i(d.x, d.y, kk)
						if not sides.has(key) or (p - c).length_squared() < (sides[key] - c).length_squared():
							sides[key] = p
	var cells: Array = []
	var by_dist := func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared()
	for sv in [0, 1]:
		var list: Array = picks.get(sv, [])
		list.sort_custom(by_dist)
		var chosen: Array[Vector2i] = []
		for cand: Vector2i in list:
			var far: bool = true
			for o in chosen:
				if (o - cand).length_squared() < 25:
					far = false
			if far and chosen.size() < 4:
				chosen.append(cand)
		# a surface with fewer than three uniform 3x3 cells (Crossroads meadow) is topped up, after the uniform ones,
		# with cells of that surface whose four neighbours are field
		if chosen.size() < 3 and relaxed.has(sv):
			var rl: Array = relaxed[sv]
			rl.sort_custom(by_dist)
			for cand: Vector2i in rl:
				var far: bool = true
				for o in chosen:
					if (o - cand).length_squared() < 25:
						far = false
				if far and chosen.size() < 3:
					chosen.append(cand)
		for i in chosen.size():
			cells.append(["field%d%s" % [sv, "abcd"[i]], chosen[i]])
	var names: Dictionary = {Vector2i(1, 0): "forestE", Vector2i(-1, 0): "forestW", Vector2i(0, 1): "forestS", Vector2i(0, -1): "forestN"}
	for key: Vector3i in sides:
		cells.append(["%s%d" % [names[Vector2i(key.x, key.y)], key.z], sides[key]])
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	# Хмарні тіні рухаються з часом: без заморозки кадри пари «з моделлю / без» різняться, а числа не повторюються.
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_strength", 0.0)
	rig.zoom_by(zoom / rig.zoom_level)
	for f in SETTLE_FRAMES * 3:
		await get_tree().process_frame
	print("UNIT gate zoom %.2f" % rig.zoom_level)
	for cl: Array in cells:
		var cell: Vector2i = cl[1]
		# Відділення таким, яким воно стоїть на початку матчу: штурмове — зі своїми трубами дрона.
		var drones: int = int(UnitTypes.get_type(type_id).get("drones", 0))
		var m: Node3D = UnitSilhouettes.build_merged(type_id, -1, set_id, drones)
		_place(m, cell, 0)
		# Крона над ним гасне так само, як над юнітом у грі: гейт міряє те, що бачить гравець.
		# _shown_cells теж: екран сам пересилає їх дошці після перебудови юнітів, і перезаписав би наше.
		screen._shown_cells.assign([cell])
		screen._board_view.set_reveal_cells([cell] as Array[Vector2i], true)
		if (UnitSilhouettes.spec(type_id, set_id).extras as Array).has(&"figures"):
			# Відділення стоїть ступнями на основі 0,05 над своїм початком, а гра опускає його на `SQUAD_SINK`.
			m.position.y -= UnitView.SQUAD_SINK
		rig.center_on(cell)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var with_m: Image = get_viewport().get_texture().get_image()
		# Третій кадр: та сама модель суцільним пурпуром без освітлення. Це маска контуру, яка не залежить від кольору
		# моделі (контраст зображення зі «з моделлю / без» губить пікселі в низькоконтрастної моделі).
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = Color(1.0, 0.0, 1.0)
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = flat
		# Крізь розчинену крону (35 %) пурпур уже не чистий: на масці її не малюємо — маска позначає все,
		# що гравець бачить крізь неї, а виміри однаково на кадрах із кроною.
		var soft: Array[Node] = screen._board_view._forest._soft_nodes
		for nd: Node in soft:
			(nd as Node3D).visible = false
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var mask: Image = get_viewport().get_texture().get_image()
		for nd: Node in soft:
			(nd as Node3D).visible = true
		if cl == cells[0]:
			var tris: int = 0
			for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
				for si in mi.mesh.get_surface_count():
					tris += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			print("UNIT gate model type %d set %d drones %d: %d tris" % [type_id, set_id, drones, tris])
		m.queue_free()
		for f in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var empty: Image = get_viewport().get_texture().get_image()
		with_m.save_png("%s/%s_%s_m.png" % [out, tag, cl[0]])
		empty.save_png("%s/%s_%s_e.png" % [out, tag, cl[0]])
		mask.save_png("%s/%s_%s_k.png" % [out, tag, cl[0]])
		print("UNIT gate %s cell %s" % [cl[0], cell])
	get_tree().quit()



func _spin(screen: BattleScreen, map: MapData, out: String, tag: String, type_id: int, set_id: int = 0) -> void:
	screen.setup(map, 2, 1)
	var cell := _field_near_centre(map)
	var m: Node3D = UnitSilhouettes.build_merged(type_id, -1, set_id)
	_place(m, cell, 0)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell)
	rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
	var hull := m.get_node("Hull") as GeometryInstance3D
	var shots: Array = []
	# s0 і s1 — той самий travel (контроль: кадри мають збігтися), s2 — пів радіуса колеса (пів радіана)
	var r: float = float(UnitSilhouettes.spec(type_id, set_id).get("wheel", 0.06))
	for i in 3:
		hull.set_instance_shader_parameter("travel", 0.5 * r if i == 2 else 0.0)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(["%s/%s_s%d.png" % [out, tag, i], get_viewport().get_texture().get_image()])
	for s: Array in shots:
		(s[1] as Image).save_png(s[0])
	print("UNIT spin %s type %d at %s: %d frames" % [tag, type_id, cell, shots.size()])
	get_tree().quit()


## Шостий аргумент squads: справжні відділення. Верхній ряд — стрілецьке, штурмове з двома дронами, стрілецьке й штурмове
## з одним (чи розрізняються формою на найдальшому зумі); середній — стрілецьке з 3, 2 і 1 стоячою фігурою та знищене;
## нижній — відділення, у яке влучили тричі, поки воно двічі йшло на тайл праворуч: тіла на трьох тайлах. Кадри _z6, _z8, _z20.
func _squads(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	# Ряди через один; карта без такої ділянки поля (River) — ряди впритул, але теж на полі, не на дорозі.
	var c := Vector2i(-1, -1)
	var step: int = 2
	for st: int in [2, 1]:
		var cells: Array[Vector2i] = []
		var around: Array[Vector2i] = []
		for col in 4:
			for row in 3:
				cells.append(Vector2i(col - 1, row * st))
		cells.append(Vector2i(-2, 0))
		for dx in range(-3, 4):
			for dy in range(-2, 2 * st + 2):
				around.append(Vector2i(dx, dy))
		c = _field_near_centre(m, false, cells, around, true)
		step = st
		if c.x >= 0:
			break
	if c.x < 0:
		push_error("unit_shot: на карті нема поля під відділення, беру середину")
		c = Vector2i(m.width / 2, m.height / 2)
	m.spawns = []
	for col in 4:
		m.spawns.append({"type_id": col % 2, "owner": 0, "pos": c + Vector2i(col - 1, 0), "facing": [0, 0, 6, 6][col]})
	for col in 4:
		m.spawns.append({"type_id": 0, "owner": 0, "pos": c + Vector2i(col - 1, step), "facing": 1})
	m.spawns.append({"type_id": 1, "owner": 0, "pos": c + Vector2i(-1, 2 * step), "facing": 2})
	# середній танк набору 0 поруч зі стрілецьким: нація читається тоном, тож тон бійця й техніки порівнюють поруч
	m.spawns.append({"type_id": 5, "owner": 0, "pos": c + Vector2i(-2, 0), "facing": 0})
	for sp: Dictionary in m.spawns:
		var q: Vector2i = sp["pos"]
		print("UNIT spawn type %d at %s on %s" % [sp["type_id"], q, Terrain.Kind.keys()[m.tiles[q.y * m.width + q.x]]])
	screen.setup(m, 2, 1)
	var state: BattleState = MatchService.state
	for u: Unit in state.alive_units():
		var col: int = u.pos.x - c.x + 1
		if u.pos.y == c.y and col == 3:
			u.drones_left = 1
		elif u.pos.y == c.y + step:
			# 3, 2, 1 стоячі й знищене: HP на межі чверті, як рахує правило фігур
			u.hp = [u.max_hp() * 3 / 4, u.max_hp() / 2, u.max_hp() / 4, 0][col]
			Casualties.record(state, u, u.max_hp())
		elif u.pos.y == c.y + 2 * step:
			# той самий шлях, що й у грі: влучання записує тіла на тайлі, де відділення стоїть у цю мить
			for hit in 3:
				var before: int = u.hp
				u.hp = u.max_hp() * (3 - hit) / 4
				Casualties.record(state, u, before)
				if hit < 2:
					u.pos += Vector2i(1, 0)
	state.refresh_vision_all()
	screen._rebuild_units_for_active_player(true)
	screen._rebuild_wrecks()
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c + Vector2i(0, step / 2))
	var shots: Dictionary = {}
	for z: float in [IsoCameraRig.MIN_ZOOM, 8.0, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_z%d.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
		# Екранні точки для вимірювання тонів (tools поза грою): тип, HP-ряд, тайл і проєкція його середини.
		var cam: Camera3D = get_viewport().get_camera_3d()
		for u: Unit in state.units.values():
			var sp: Vector2 = cam.unproject_position(Vector3(u.pos.x, 0.08, u.pos.y))
			print("MEAS z%d type %d hp %d pos %s px %d %d" % [int(z), u.type_id, u.hp, u.pos, sp.x, sp.y])
		for b: Casualties.Body in state.bodies:
			var bp: Vector2 = cam.unproject_position(Vector3(b.pos.x, 0.03, b.pos.y))
			print("MEAS z%d body %d pos %s px %d %d" % [int(z), b.count, b.pos, bp.x, bp.y])
		# Пари для маски вимірювання: той самий кадр без юнітів і без тіл — різниця є рівно фігури й тіла.
		if z != 8.0:
			for v: UnitView in screen._unit_views.values():
				for n: Node3D in [v._hp_bar, v._hp_label, v._drone_icon]:
					n.visible = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			shots["%s/%s_z%d_noui.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
			for v: Node3D in screen._unit_views.values():
				v.visible = false
			screen._contacts.visible = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			shots["%s/%s_z%d_nounits.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
			for v: UnitView in screen._unit_views.values():
				v.visible = true
				v._hp_bar.visible = true
				v._hp_label.visible = true
				v._drone_icon.visible = v._drones_left > 0
			screen._contacts.visible = true
			for mi: MultiMeshInstance3D in screen._wreck_layer.fallen_meshes():
				mi.visible = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			shots["%s/%s_z%d_nobodies.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
			# Силует тіл суцільним пурпуром без світла: вимірюється лише тканина, а не тінь і пляма під тілом.
			var flat := StandardMaterial3D.new()
			flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flat.albedo_color = Color(1.0, 0.0, 1.0)
			var mats: Array[Material] = []
			for mi: MultiMeshInstance3D in screen._wreck_layer.fallen_meshes():
				mats.append(mi.material_override)
				mi.material_override = flat
				mi.visible = true
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			shots["%s/%s_z%d_bodymask.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
			var k: int = 0
			for mi: MultiMeshInstance3D in screen._wreck_layer.fallen_meshes():
				mi.material_override = mats[k]
				k += 1
			await RenderingServer.frame_post_draw
		if z == IsoCameraRig.MIN_ZOOM:
			# Той самий кадр без тіні-контакту: різниця пари — рівно те, на скільки пляма темнить ґрунт.
			var strength: float = WeatherRig.unit_contact
			RenderingServer.global_shader_parameter_set(&"unit_contact_shadow", 0.0)
			for f in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots["%s/%s_z%d_nocontact.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
			RenderingServer.global_shader_parameter_set(&"unit_contact_shadow", strength)
	# Слід відділення окремо: тіла на трьох тайлах нижнього ряду.
	rig.center_on(c + Vector2i(0, 2 * step))
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_trail_z%d.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	print("UNIT squads at %s" % c)
	get_tree().quit()


## Шостий аргумент squads_forest: стрілецьке відділення на тайлі лісу (крона над ним гасне) і штурмове на полі поруч,
## з того боку лісу, куди падає тінь від сонця (у тіні крон). Кадри _forest_z6 і _forest_z20.
## Шостий аргумент walk: стрілецьке відділення йде на схід два тайли, тоді на південь три (вигляд, move_along
## як у грі), на зумі 8. Кадри _walk_start (стоїть на схід) і _walk_mid (посеред південної ділянки: бійці
## мусять дивитись на південь, а не тримати схід до кінця шляху).
func _walk(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var need: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	var c: Vector2i = _field_near_centre(m, false, need)
	m.spawns = [{"type_id": 0, "owner": 0, "pos": c, "facing": 2}]
	screen.setup(m, 2, 1)
	var view: UnitView = screen._unit_views[MatchService.state.unit_at(c).id]
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	rig.center_on(c + Vector2i(1, 1))
	rig.zoom_by(8.0 / rig.zoom_level)
	for f in SETTLE_FRAMES * 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var start: Image = get_viewport().get_texture().get_image()
	var path: Array[Vector2i] = [c + Vector2i(1, 0), c + Vector2i(2, 0), c + Vector2i(2, 1), c + Vector2i(2, 2), c + Vector2i(2, 3)]
	view.move_along(path, 0.6)
	var mid: Image = null
	var t0: int = Time.get_ticks_msec()
	while mid == null and Time.get_ticks_msec() - t0 < 8000:
		await RenderingServer.frame_post_draw
		if IsoCameraRig.world_to_cell(view.position) == c + Vector2i(2, 2):
			mid = get_viewport().get_texture().get_image()
			print("UNIT walk mid: rotation %.1f°, figures built for bucket %d" % [view.rotation_degrees.y, view._built_face])
	start.save_png("%s/%s_walk_start.png" % [out, tag])
	if mid != null:
		mid.save_png("%s/%s_walk_mid.png" % [out, tag])
	print("UNIT walk at %s" % c)
	get_tree().quit()


## Вісім відділень на полі, кожне на своєму з 8 напрямів (стрілецьке й штурмове з двома дронами через одне):
## жодні двоє бійців не стоять один за одним уздовж погляду на жодному напрямі. Наближення й віддалення.
func _facings(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var cells: Array[Vector2i] = []
	var around: Array[Vector2i] = []
	for col in 4:
		for row in 2:
			cells.append(Vector2i(col - 1, row))
	for dx in range(-2, 4):
		for dy in range(-1, 3):
			around.append(Vector2i(dx, dy))
	var c: Vector2i = _field_near_centre(m, false, cells, around, true)
	if c.x < 0:
		c = _field_near_centre(m, false, cells)
	m.spawns = []
	for f in 8:
		m.spawns.append({"type_id": f % 2, "owner": 0, "pos": c + Vector2i(f % 4 - 1, f / 4), "facing": f})
	screen.setup(m, 2, 1)
	for u: Unit in MatchService.state.alive_units():
		if u.type_id == 1:
			u.drones_left = 2
	MatchService.state.refresh_vision_all()
	screen._rebuild_units_for_active_player(true)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c + Vector2i(0, 0))
	var shots: Dictionary = {}
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_facings_z%d.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
		var cam: Camera3D = get_viewport().get_camera_3d()
		for u: Unit in MatchService.state.units.values():
			var sp: Vector2 = cam.unproject_position(Vector3(u.pos.x, 0.08, u.pos.y))
			print("UNIT z%d facing %d type %d at %s px %d,%d" % [int(z), u.facing, u.type_id, u.pos, int(sp.x), int(sp.y)])
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	get_tree().quit(0)


func _squads_forest(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := Vector2i(m.width / 2, m.height / 2)
	# Напрям сонця відомий лише після setup(): відділення ставляться спершу будь-де, потім переставляються.
	var spots: Array[Vector2i] = []
	for y in range(2, m.height - 2):
		for x in range(2, m.width - 2):
			if m.tiles[y * m.width + x] == Terrain.Kind.FIELD and spots.size() < 2:
				spots.append(Vector2i(x, y))
	m.spawns = [
		{"type_id": 0, "owner": 0, "pos": spots[0], "facing": 0},
		{"type_id": 1, "owner": 0, "pos": spots[1], "facing": 2},
	]
	screen.setup(m, 2, 1)
	var shade := Vector2i(1, 0)
	var best_dot: float = -INF
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Vector2(d).dot(WeatherRig.sun_ground) > best_dot:
			best_dot = Vector2(d).dot(WeatherRig.sun_ground)
			shade = d
	var forest := Vector2i(-1, -1)
	for y in range(2, m.height - 2):
		for x in range(2, m.width - 2):
			var f := Vector2i(x, y)
			var n: Vector2i = f + shade
			if m.tiles[y * m.width + x] == Terrain.Kind.FOREST and m.tiles[n.y * m.width + n.x] == Terrain.Kind.FIELD:
				if forest.x < 0 or (f - c).length_squared() < (forest - c).length_squared():
					forest = f
	var state: BattleState = MatchService.state
	state.unit_at(spots[0]).pos = forest
	state.unit_at(spots[1]).pos = forest + shade
	state.refresh_vision_all()
	screen._rebuild_units_for_active_player(true)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(forest)
	var shots: Dictionary = {}
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_forest_z%d.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	print("UNIT squads_forest at %s, shade side %s" % [forest, shade])
	get_tree().quit()


## Шостий аргумент squad_bridge [standing=N]: стрілецьке відділення на мосту, у якого лишилось N стоячих (типово
## знищене), і живе поруч на березі. Кадри _bridge_z6 і _bridge_z20 (з N > 0 — _bridge_sN_z6 і _bridge_sN_z20).
func _squad_bridge(screen: BattleScreen, map: MapData, out: String, tag: String, standing: int = 0) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var bridge := Vector2i(-1, -1)
	var c := Vector2i(m.width / 2, m.height / 2)
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			if m.tiles[y * m.width + x] == Terrain.Kind.BRIDGE and (bridge.x < 0 or (p - c).length_squared() < (bridge - c).length_squared()):
				bridge = p
	# живе відділення — на найближчому до мосту полі, не на ньому самому
	var bank := Vector2i(-1, -1)
	for y in m.height:
		for x in m.width:
			var q := Vector2i(x, y)
			if m.tiles[y * m.width + x] == Terrain.Kind.FIELD and (bank.x < 0 or (q - bridge).length_squared() < (bank - bridge).length_squared()):
				bank = q
	m.spawns = [
		{"type_id": 0, "owner": 0, "pos": bridge, "facing": 0},
		{"type_id": 1, "owner": 0, "pos": bank, "facing": 2},
	]
	screen.setup(m, 2, 1)
	var state: BattleState = MatchService.state
	var dead: Unit = state.unit_at(bridge)
	var before: int = dead.hp
	dead.hp = dead.max_hp() * standing / 4
	Casualties.record(state, dead, before)
	state.refresh_vision_all()
	screen._rebuild_units_for_active_player(true)
	screen._rebuild_wrecks()
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(bridge)
	var shots: Dictionary = {}
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var name: String = "bridge" if standing == 0 else "bridge_s%d" % standing
		shots["%s/%s_%s_z%d.png" % [out, tag, name, int(z)]] = get_viewport().get_texture().get_image()
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	_print_deck(screen, m.to_board(), bridge)
	print("UNIT squad_bridge at %s" % bridge)
	get_tree().quit()


## Видимі середини тіл на мосту `bridge`: убік — частка чистої ширини настилу (0 — один поручень, 1 — другий),
## уздовж — тайли від середини клітинки.
func _print_deck(screen: BattleScreen, board: Board, bridge: Vector2i) -> void:
	var along_z: bool = WreckLayer._is_water(board, bridge + Vector2i(1, 0)) or WreckLayer._is_water(board, bridge + Vector2i(-1, 0))
	var along := Vector3(0.0, 0.0, 1.0) if along_z else Vector3(1.0, 0.0, 0.0)
	var across := Vector3(along.z, 0.0, along.x)
	var half: float = WreckLayer.BODY_DECK_HALF_ROAD
	var rows: Array = []
	for xf: Transform3D in screen._wreck_layer.body_transforms():
		var rel: Vector3 = WreckLayer.body_centre(xf) - Vector3(bridge.x, 0.0, bridge.y)
		if absf(rel.dot(along)) > 0.5 or absf(rel.dot(across)) > 0.5:
			continue
		rows.append([rel.dot(along), (rel.dot(across) + half) / (half * 2.0)])
	rows.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for r: Array in rows:
		print("UNIT deck body along %.3f across %.2f of clear width" % [r[0], r[1]])


## Шостий аргумент bridge_seq: стрілецьке відділення на мосту падає 100 → 75 → 50 → 25 трьома влучаннями; кадр на
## зумі 6 після кожного (_seq_75, _seq_50, _seq_25) — раніші тіла мусять лишатися на місці.
func _bridge_seq(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var bridge := Vector2i(-1, -1)
	var c := Vector2i(m.width / 2, m.height / 2)
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			if m.tiles[y * m.width + x] == Terrain.Kind.BRIDGE and (bridge.x < 0 or (p - c).length_squared() < (bridge - c).length_squared()):
				bridge = p
	m.spawns = [{"type_id": 0, "owner": 0, "pos": bridge, "facing": 0}]
	screen.setup(m, 2, 1)
	var state: BattleState = MatchService.state
	var u: Unit = state.unit_at(bridge)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	rig.center_on(bridge)
	rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
	var shots: Dictionary = {}
	for left in [3, 2, 1]:
		var before: int = u.hp
		u.hp = u.max_hp() * left / 4
		Casualties.record(state, u, before)
		state.refresh_vision_all()
		screen._rebuild_units_for_active_player(true)
		screen._rebuild_wrecks()
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_seq_%d.png" % [out, tag, left * 25]] = get_viewport().get_texture().get_image()
		print("UNIT seq hp %d" % u.hp)
		_print_deck(screen, m.to_board(), bridge)
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	print("UNIT bridge_seq at %s" % bridge)
	get_tree().quit()


## Шостий аргумент shore: два стрілецькі відділення на полі над водою (сусід по ребру — вода), одне з трьома стоячими,
## друге з одним; тіла тих, хто впав, — поруч. Кадри _shore_z6 і _shore_z20: жодне тіло не заходить у воду й не
## лягає під ноги стоячому.
func _shore(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := Vector2i(m.width / 2, m.height / 2)
	var shores: Array[Vector2i] = []
	for y in range(1, m.height - 1):
		for x in range(1, m.width - 1):
			var p := Vector2i(x, y)
			if m.tiles[y * m.width + x] != Terrain.Kind.FIELD:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if m.tiles[(p + d).y * m.width + (p + d).x] == Terrain.Kind.WATER:
					shores.append(p)
					break
	shores.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return (p - c).length_squared() < (q - c).length_squared())
	var first: Vector2i = shores[0]
	var second := Vector2i(-1, -1)
	for q: Vector2i in shores:
		var d: Vector2i = q - first
		if maxi(absi(d.x), absi(d.y)) == 2:
			second = q
			break
	m.spawns = [{"type_id": 0, "owner": 0, "pos": first, "facing": 2}]
	if second.x >= 0:
		m.spawns.append({"type_id": 0, "owner": 0, "pos": second, "facing": 6})
	screen.setup(m, 2, 1)
	var state: BattleState = MatchService.state
	var left: Array[int] = [3, 1]
	var k: int = 0
	for u: Unit in state.alive_units():
		var before: int = u.hp
		u.hp = u.max_hp() * left[k % 2] / 4
		Casualties.record(state, u, before)
		k += 1
	state.refresh_vision_all()
	screen._rebuild_units_for_active_player(true)
	screen._rebuild_wrecks()
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(first)
	var shots: Dictionary = {}
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_shore_z%d.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	print("UNIT shore at %s and %s" % [first, second])
	get_tree().quit()


## Шостий аргумент fleet [set=N] ставить в один ряд чотири танки (важкий, середній, винищувач, легкий) і три колісні машини набору 0
## (бронеавто, транспортер, розвідувальна) і знімає кадри _z6 і _z20: чи ділять вони одну фарбу.
func _fleet(screen: BattleScreen, map: MapData, out: String, tag: String, set_id: int = 0) -> void:
	screen.setup(map, 2, 1)
	var c := _field_row_near_centre(map, 7)
	# усі дванадцять типів у двох рядах: гармати довші за тайл, тож ряди розставлені через клітинку і сусіди не налягають
	var roles: Array[int] = [8, 5, 6, 7, 2, 3, 4, 9, 10, 11, 0, 1]
	for i in roles.size():
		_place(UnitSilhouettes.build_merged(roles[i], -1, set_id), c + Vector2i(i % 6 - 3, floori(i / 6.0) * 2 - 1), 0)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c)
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_z%d.png" % [out, tag, int(z)])
	print("UNIT fleet at %s" % c)
	get_tree().quit()


## Ряд із чотирьох танків набору: кадр _f0 — тилом до камери, видно корму й моторну палубу; _f4 — носом до камери.
func _rear(screen: BattleScreen, map: MapData, out: String, tag: String, set_id: int) -> void:
	screen.setup(map, 2, 1)
	var c := _field_row_near_centre(map, 7)
	var roles: Array[int] = [8, 5, 6, 7]
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(c)
	rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
	for facing: int in [4, 0]:
		var nodes: Array[Node3D] = []
		for i in roles.size():
			var m: Node3D = UnitSilhouettes.build_merged(roles[i], -1, set_id)
			_place(m, c + Vector2i(i * 2 - 3, 0), facing)
			nodes.append(m)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_f%d_z6.png" % [out, tag, facing])
		for n in nodes:
			n.queue_free()
		for f in 6:
			await get_tree().process_frame
	print("UNIT rear set %d at %s" % [set_id, c])
	get_tree().quit()


## Шостий аргумент forest_n2: справжнє стрілецьке відділення на клітинці гейту forestN2 (поле, ліс за два кроки
## на північ; на Ridge між ним і камерою — ліс на сусідній клітинці, і його крони гаснуть, як у грі) і виділене штурмове з двома
## дронами (значок біля золотого контуру зони). Кадри _n2_z6, _n2_z20. Далі — ворожий бік: живе відділення
## в лісі й тіла знищеного на полі поруч, обидва поза розвіданим глядача: крона над ворогом не гасне, тіл нема.
## Кадри _hidden_z6, _hidden_z20.
func _forest_n2(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := Vector2i(m.width / 2, m.height / 2)
	var kind := func(q: Vector2i) -> int:
		return m.tiles[q.y * m.width + q.x] if q.x >= 0 and q.y >= 0 and q.x < m.width and q.y < m.height else -1
	var n2 := Vector2i(-1, -1)
	for y in range(4, m.height - 4):
		for x in range(4, m.width - 4):
			var p := Vector2i(x, y)
			if kind.call(p) == Terrain.Kind.FIELD and kind.call(p + Vector2i(0, -1)) == Terrain.Kind.FIELD \
					and kind.call(p + Vector2i(0, -2)) == Terrain.Kind.FOREST and kind.call(p + Vector2i(0, 1)) == Terrain.Kind.FIELD:
				if n2.x < 0 or (p - c).length_squared() < (n2 - c).length_squared():
					n2 = p
	# ворог: лісова клітинка з полем поруч, щонайменше за 12 клітинок від відділень глядача (поза їхнім оглядом)
	var hide := Vector2i(-1, -1)
	var field := Vector2i(-1, -1)
	for y in range(3, m.height - 3):
		for x in range(3, m.width - 3):
			var p := Vector2i(x, y)
			if kind.call(p) != Terrain.Kind.FOREST or absi(p.x - n2.x) + absi(p.y - n2.y) < 12:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				if kind.call(p + d) == Terrain.Kind.FIELD and hide.x < 0:
					hide = p
					field = p + d
	var side := Vector2i(0, 1)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
		if kind.call(n2 + d) == Terrain.Kind.FIELD:
			side = d
			break
	m.spawns = [
		{"type_id": 0, "owner": 0, "pos": n2, "facing": 0},
		{"type_id": 1, "owner": 0, "pos": n2 + side, "facing": 2},
		{"type_id": 0, "owner": 1, "pos": hide, "facing": 4},
		{"type_id": 0, "owner": 1, "pos": field, "facing": 4},
	]
	screen.setup(m, 2, 1)
	var state: BattleState = MatchService.state
	var dead: Unit = state.unit_at(field)
	var before: int = dead.hp
	dead.hp = 0
	Casualties.record(state, dead, before)
	state.refresh_vision_all()
	screen._rebuild_units_for_active_player(true)
	screen._rebuild_wrecks()
	var assault: Unit = state.unit_at(n2 + side)
	(screen.get("_controller") as InputController).select_unit(assault)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var shots: Dictionary = {}
	for place: Array in [["n2", n2], ["hidden", hide]]:
		rig.center_on(place[1])
		for z: float in [IsoCameraRig.MIN_ZOOM, 8.0, IsoCameraRig.MAX_ZOOM]:
			rig.zoom_by(z / rig.zoom_level)
			for f in SETTLE_FRAMES * 2:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots["%s/%s_%s_z%d.png" % [out, tag, place[0], int(z)]] = get_viewport().get_texture().get_image()
			if place[0] == "n2" and z == IsoCameraRig.MIN_ZOOM:
				# пара для виміру прозорості: крон нема, запечена тінь лісу на ґрунті лишається
				var fl: ForestLayer = screen._board_view._forest
				var hidden: Array[Node3D] = []
				for ch: Node in fl.get_children():
					if ch is Node3D and (ch as Node3D).visible and ch.name != &"Forest_Shadow":
						(ch as Node3D).visible = false
						hidden.append(ch)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				shots["%s/%s_n2_z6_nocrowns.png" % [out, tag]] = get_viewport().get_texture().get_image()
				for ch: Node3D in hidden:
					ch.visible = true
				await RenderingServer.frame_post_draw
			if place[0] == "n2" and z < 9.0:
				await _ab_pair(screen, shots, "%s/%s_n2_z%d" % [out, tag, int(z)])
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	print("UNIT forest_n2 at %s, enemy hidden at %s (seen %s), bodies at %s (seen %s, shown %s)" % [n2, hide,
			state.vision[0].is_seen(hide), field, state.vision[0].is_seen(field), state.bodies[0].shown_to(0)])
	get_tree().quit()


## Шостий аргумент fall: танк стріляє в сусіднє стрілецьке відділення справжньою командою (програвач подій як у грі),
## кадри кожні 0,1 с упродовж 2 с на зумі 8 — бійці падають з реальною швидкістю. Кадри _fall_00.._fall_19.
func _fall(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var need: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0)]
	var c := _field_near_centre(m, false, need, [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(0, -2)])
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": c + Vector2i(-1, 0), "facing": 2},
		{"type_id": 0, "owner": 1, "pos": c, "facing": 6},
	]
	screen.setup(m, 2, 1)
	var state: BattleState = MatchService.state
	var tank: Unit = state.unit_at(c + Vector2i(-1, 0))
	var squad: Unit = state.unit_at(c)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	rig.center_on(c)
	rig.zoom_by(8.0 / rig.zoom_level)
	for f in SETTLE_FRAMES * 2:
		await get_tree().process_frame
	# дві фігури стоять (30 HP), тож постріл танка валить щонайменше одну
	squad.hp = 30
	screen._rebuild_units_for_active_player(true)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var hp0: int = squad.hp
	print("UNIT fall submit '%s'" % MatchService.submit(FireCommand.create(tank.id, squad.id)))
	var t0: int = Time.get_ticks_msec()
	# кожен кадр першої секунди: перекидання триває 0,2 с, і лише так воно видне на справжній швидкості
	var frames: Array[Image] = []
	var stamps: Array[int] = []
	while Time.get_ticks_msec() - t0 < 1000:
		await RenderingServer.frame_post_draw
		frames.append(get_viewport().get_texture().get_image())
		stamps.append(Time.get_ticks_msec() - t0)
	# між перекиданням і тим, як пил улігся: тіло має лишатися там, де скінчилось перекидання
	var later: Dictionary = {}
	for ms: int in [1500, 2000, 2500, 3000]:
		while Time.get_ticks_msec() - t0 < ms:
			await RenderingServer.frame_post_draw
		later[ms] = get_viewport().get_texture().get_image()
	# пил улігся: кадр через 3,5 с після пострілу
	while Time.get_ticks_msec() - t0 < 3500:
		await RenderingServer.frame_post_draw
	var settled: Image = get_viewport().get_texture().get_image()
	for ms: int in later:
		(later[ms] as Image).save_png("%s/%s_fall_t%02d.png" % [out, tag, ms / 100])
	for i in frames.size():
		frames[i].save_png("%s/%s_fall_%03d.png" % [out, tag, i])
	print("UNIT fall frame times ms %s" % [stamps])
	settled.save_png("%s/%s_fall_35.png" % [out, tag])
	print("UNIT fall at %s: hp %d -> %d, figures %d -> %d" % [c, hp0, squad.hp, Casualties.figures(hp0, squad.max_hp()), Casualties.figures(squad.hp, squad.max_hp())])
	get_tree().quit()


## Пара для порівняння на поточному зумі: `<base>_nofade` (крони не гаснуть) і `<base>_noforest` (лісу нема);
## потім усе як було.
func _ab_pair(screen: BattleScreen, shots: Dictionary, base: String) -> void:
	var bv: BoardView = screen._board_view
	var keep: Array[Vector2i] = bv._forest._reveal.duplicate()
	bv.set_reveal_cells([] as Array[Vector2i], true)
	for f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	shots[base + "_nofade.png"] = get_viewport().get_texture().get_image()
	bv._forest.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	shots[base + "_noforest.png"] = get_viewport().get_texture().get_image()
	bv._forest.visible = true
	bv.set_reveal_cells(keep, true)
	for f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## Шостий аргумент forest_deep: штурмове відділення (значок дронів) на клітинці лісу, довкола якої на дві
## клітинки ліс (якщо такої нема — на одну). Кадри _deep_z6, _deep_z8, _deep_z20 і на зумах 6 і 8 пари для порівняння:
## _nofade (крона не гасне) і _noforest (лісу нема).
func _forest_deep(screen: BattleScreen, map: MapData, out: String, tag: String) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := Vector2i(m.width / 2, m.height / 2)
	var deep := Vector2i(-1, -1)
	# ліс на дві клітинки довкола, а якщо такого нема — хоч на одну
	for ring in [2, 1]:
		for y in range(ring, m.height - ring):
			for x in range(ring, m.width - ring):
				var ok: bool = true
				for dy in range(-ring, ring + 1):
					for dx in range(-ring, ring + 1):
						if m.tiles[(y + dy) * m.width + x + dx] != Terrain.Kind.FOREST:
							ok = false
				var p := Vector2i(x, y)
				if ok and (deep.x < 0 or (p - c).length_squared() < (deep - c).length_squared()):
					deep = p
		if deep.x >= 0:
			break
	if deep.x < 0:
		push_error("unit_shot: на карті нема клітинки глибоко в лісі")
		get_tree().quit()
		return
	m.spawns = [{"type_id": 1, "owner": 0, "pos": deep, "facing": 2}]
	screen.setup(m, 2, 1)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(deep)
	var shots: Dictionary = {}
	for z: float in [IsoCameraRig.MIN_ZOOM, 8.0, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots["%s/%s_deep_z%d.png" % [out, tag, int(z)]] = get_viewport().get_texture().get_image()
	for z: float in [IsoCameraRig.MIN_ZOOM, 8.0]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await _ab_pair(screen, shots, "%s/%s_deep_z%d" % [out, tag, int(z)])
	for path: String in shots:
		(shots[path] as Image).save_png(path)
	print("UNIT forest_deep at %s" % deep)
	get_tree().quit()
