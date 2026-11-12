extends Node
## Знімає модель юніта на справжньому екрані бою: дві моделі й коробка-заступник поруч для
## масштабу, на найближчому й найдальшому зумі, і два кадри з інтервалом 0,5 с, поки один танк
## їде на тайл уперед (гусениці й колеса мають крутитися). Кадри тримаються в пам'яті й пишуться
## в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/unit_shot.tscn -- <out_dir> <map> <type_id> [tag]
## Шостий аргумент pair=<type_b>:<facing> ставить type_id і type_b на сусідні тайли носом до носа
## (facing 0 — уздовж осі, 1 — по діагоналі) і знімає лише два зуми: чи не залазить ствол у сусіда.
## Шостий аргумент lineup ставить чотири танки справжніми юнітами трьох гравців (смуги HP у кольорі
## власника) і знімає один кадр на найближчому зумі; type_id тоді ігнорується.
## Сьомий аргумент set=N у звичайному режимі бере моделі набору N.
## Шостий аргумент gate [set=N] (запускає tools/unit_contrast_gate.py) знімає модель типу type_id на найдальшому зумі на різних ґрунтах і біля
## лісу, кожне місце двома кадрами — з моделлю (_m) і без (_e): різниця кадрів дає маску моделі для ΔE.
## Шостий аргумент sets ставить ті самі чотири танки для кожного з трьох гравців: рядки — набори
## (власники 0, 1, 2), стовпці — ролі (важкий, середній, винищувач, легкий); один кадр, type_id ігнорується.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 60
## Скільки триває проїзд на один тайл і коли знімати два кадри руху.
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
	if a.size() > 5 and a[5] == "sets":
		await _sets(screen, map, out, tag, a.size() > 6 and a[6] == "forest", a.size() > 6 and a[6] == "sel")
		return
	if a.size() > 5 and a[5] == "gate":
		var gset: int = int(a[6].substr(4)) if a.size() > 6 and a[6].begins_with("set=") else 0
		await _gate(screen, map, out, tag, type_id, gset)
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
	_place(UnitSilhouettes.build_merged(type_id, -1, set_id), cell, 0)
	_place(UnitSilhouettes.build_merged(type_id, -1, set_id), cell + Vector2i(1, 0), 3)
	_place(UnitSilhouettes.build(type_id), cell + Vector2i(-1, 0), 0)
	var mover: Node3D = UnitSilhouettes.build_merged(type_id, -1, set_id)
	_place(mover, cell + Vector2i(0, 2), 0)
	print("UNIT placed at %s" % cell)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell + Vector2i(0, 1))
	var shots: Array = []
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(["%s/%s_z%d.png" % [out, tag, int(z)], get_viewport().get_texture().get_image()])
	rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
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
func _field_near_centre(map: MapData, near_forest: bool = false) -> Vector2i:
	var c := Vector2i(map.width / 2, map.height / 2)
	var best := c
	var best_d: int = 1 << 30
	for y in range(1, map.height - 3):
		for x in range(1, map.width - 1):
			var ok: bool = true
			for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1)]:
				if map.tiles[(y + d.y) * map.width + x + d.x] != Terrain.Kind.FIELD:
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


## Рядок на набір, стовпець на роль: так видно, що ролі читаються однаково в кожному наборі.
func _sets(screen: BattleScreen, map: MapData, out: String, tag: String, near_forest: bool = false, select: bool = false) -> void:
	var m: MapData = map.duplicate(true)
	m.take_over_path(map.resource_path)
	var c := _field_near_centre(m, near_forest)
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


## Місця для виміру контрасту: по одній клітинці кожного виду поверхні поля (усі дев'ять сусідів того
## самого виду) і одна клітинка поля біля лісу. Модель дивиться на північ; камера однакова в обох кадрах.
func _gate(screen: BattleScreen, map: MapData, out: String, tag: String, type_id: int, set_id: int) -> void:
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
			# fallback when a surface has no uniform 3x3 anywhere: the cell's own surface, neighbours any field
			var all_field: bool = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if map.tiles[(y + dy) * map.width + x + dx] != Terrain.Kind.FIELD:
						all_field = false
			if all_field:
				if not relaxed.has(sv):
					relaxed[sv] = []
				relaxed[sv].append(p)
			# a field cell k = 1..3 cells from a forest in direction d (field in between and behind): k = 1 can sit under the
			# crown, k = 2..3 on the cast shadow strip; the report keeps the places whose ground is darkened but open
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
	for sv in [0, 1]:
		if not picks.has(sv) and relaxed.has(sv):
			picks[sv] = relaxed[sv]
	for sv in picks:
		var list: Array = picks[sv]
		list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
		var chosen: Array[Vector2i] = []
		for cand: Vector2i in list:
			var far: bool = true
			for o in chosen:
				if (o - cand).length_squared() < 36:
					far = false
			if far and chosen.size() < 3:
				chosen.append(cand)
		for i in chosen.size():
			cells.append(["field%d%s" % [sv, "abc"[i]], chosen[i]])
	var names: Dictionary = {Vector2i(1, 0): "forestE", Vector2i(-1, 0): "forestW", Vector2i(0, 1): "forestS", Vector2i(0, -1): "forestN"}
	for key: Vector3i in sides:
		cells.append(["%s%d" % [names[Vector2i(key.x, key.y)], key.z], sides[key]])
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	# Хмарні тіні рухаються з часом: без заморозки кадри пари «з моделлю / без» різняться, а числа не повторюються.
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_strength", 0.0)
	rig.zoom_by(IsoCameraRig.MAX_ZOOM / rig.zoom_level)
	for f in SETTLE_FRAMES * 3:
		await get_tree().process_frame
	print("UNIT gate zoom %.2f" % rig.zoom_level)
	for cl: Array in cells:
		var cell: Vector2i = cl[1]
		var m: Node3D = UnitSilhouettes.build_merged(type_id, -1, set_id)
		_place(m, cell, 0)
		rig.center_on(cell)
		for f in SETTLE_FRAMES * 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var with_m: Image = get_viewport().get_texture().get_image()
		m.queue_free()
		for f in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var empty: Image = get_viewport().get_texture().get_image()
		with_m.save_png("%s/%s_%s_m.png" % [out, tag, cl[0]])
		empty.save_png("%s/%s_%s_e.png" % [out, tag, cl[0]])
		print("UNIT gate %s cell %s" % [cl[0], cell])
	get_tree().quit()

