extends GutTest
## Протоптані стежки: знос у масці землі, а не вузли чи декалі. Вигляд не знає про сітку: шум
## зносу лежить у координатах самої стежки (вздовж, поперек), тож ніякої світової текстури.

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
const BoardViewScene := preload("res://game/battle/board_view.tscn")


func _walk(a: Vector2, b: Vector2, half: float = 0.085, seed_value: int = 5) -> Dictionary:
	var pts: PackedVector2Array = Footpaths.meander(a, b, 0.05, 1.2, seed_value)
	var hw := PackedFloat32Array()
	hw.resize(pts.size())
	hw.fill(half)
	return {"kind": &"yard", "pts": pts, "half": hw, "seed": seed_value}


func _px(img: Image, p: Vector2) -> int:
	return int(round(img.get_pixel(int((p.x + 0.5) * Footpaths.PX_PER_TILE), int((p.y + 0.5) * Footpaths.PX_PER_TILE)).r * 255.0))


func test_meander_keeps_ends_and_is_deterministic() -> void:
	var a := Vector2(2, 3)
	var b := Vector2(6.5, 4)
	var m1: PackedVector2Array = Footpaths.meander(a, b, 0.1, 1.2, 9)
	var m2: PackedVector2Array = Footpaths.meander(a, b, 0.1, 1.2, 9)
	assert_eq(m1, m2)
	assert_eq(m1[0], a)
	assert_eq(m1[m1.size() - 1], b)
	var worst := 0.0
	var line: Vector2 = (b - a).normalized()
	for k in m1.size():
		if k > 0:
			assert_lte(m1[k].distance_to(m1[k - 1]), Footpaths.STEP * 1.2)
		worst = maxf(worst, absf(line.cross(m1[k] - a)))
	assert_gt(worst, 0.02, "стежка має звиватися")
	assert_lte(worst, 0.1 + 1e-4, "звивистість не більша за амплітуду")


func test_wear_fades_softly_across_the_path() -> void:
	var img: Image = Footpaths.bake([_walk(Vector2(2, 5), Vector2(9, 5))], PackedVector3Array(), Vector2i(12, 10))
	var x: int = int(6.0 * Footpaths.PX_PER_TILE)
	var mid: int = int(5.5 * Footpaths.PX_PER_TILE)
	var soft := 0
	var prev: int = 0
	for dy in range(-16, 17):
		var v: int = int(round(img.get_pixel(x, mid + dy).r * 255.0))
		if v > 20 and v < 235:
			soft += 1
		assert_lte(absi(v - prev), 110, "різкої межі нема (dy=%d)" % dy)
		prev = v
	assert_gte(soft, 6, "край розчиняється на кілька пікселів, а не ступінню")
	assert_gt(_px(img, Vector2(6.0, 5.0)), 100, "посередині стежки знос помітний")
	assert_eq(_px(img, Vector2(6.0, 5.6)), 0, "поза стежкою землі не торкнуто")


func test_wear_does_not_depend_on_world_position() -> void:
	var w1: Dictionary = _walk(Vector2(2, 3), Vector2(8, 3))
	var w2: Dictionary = _walk(Vector2(5, 6), Vector2(11, 6))
	var i1: Image = Footpaths.bake([w1], PackedVector3Array(), Vector2i(14, 10))
	var i2: Image = Footpaths.bake([w2], PackedVector3Array(), Vector2i(14, 10))
	var px: int = Footpaths.PX_PER_TILE
	var bad := 0
	var lit := 0
	for y in range(2 * px, 4 * px):
		for x in range(1 * px, 9 * px):
			var v1: int = int(i1.get_pixel(x, y).r * 255.0)
			var v2: int = int(i2.get_pixel(x + 3 * px, y + 3 * px).r * 255.0)
			lit += 1 if v1 > 0 else 0
			# Зсув на цілі клітинки не міняє пікселів; ±1 — лише похибка округлення float.
			bad += 1 if absi(v1 - v2) > 1 else 0
	assert_gt(lit, 1000)
	assert_eq(bad, 0, "та сама стежка в іншому місці дає ті самі пікселі")


func test_bake_is_deterministic() -> void:
	var walks: Array = [_walk(Vector2(2, 3), Vector2(8, 4))]
	var patches := PackedVector3Array([Vector3(4, 7, 0.25)])
	assert_eq(Footpaths.bake(walks, patches, Vector2i(12, 10)).get_data(), Footpaths.bake(walks, patches, Vector2i(12, 10)).get_data())


func test_trodden_patch_is_soft_and_centred() -> void:
	var img: Image = Footpaths.bake([], PackedVector3Array([Vector3(4, 4, 0.25)]), Vector2i(10, 10))
	assert_gt(_px(img, Vector2(4, 4)), 100)
	assert_eq(_px(img, Vector2(4.4, 4)), 0)


func test_water_cuts_the_wear() -> void:
	var dry := func(p: Vector2) -> bool: return p.x < 5.0
	var img: Image = Footpaths.bake([_walk(Vector2(2, 5), Vector2(9, 5))], PackedVector3Array(), Vector2i(12, 10), dry)
	assert_gt(_px(img, Vector2(4.0, 5.0)), 0)
	assert_eq(_px(img, Vector2(6.0, 5.0)), 0)


var _views: Dictionary = {}


func _cached(name: String) -> BoardView:
	if not _views.has(name):
		var m: MapData = load("res://maps/%s.tres" % name)
		var view: BoardView = BoardViewScene.instantiate()
		add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		view.build(m.to_board())
		_views[name] = view
	return _views[name]


func after_all() -> void:
	for v: BoardView in _views.values():
		v.free()
	_views.clear()


func test_every_house_has_a_continuous_path_from_door_to_road(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	var yard: Dictionary = {}
	for w: Dictionary in props.footpaths:
		if w["kind"] == &"yard":
			yard[int(w["home"])] = w
	for i in homes.size():
		assert_true(yard.has(i), "%s: у хати %d нема стежки" % [p, i])
		if not yard.has(i):
			continue
		var pts: PackedVector2Array = yard[i]["pts"]
		var door: Vector2 = yard[i]["door"]
		assert_lte(door.distance_to(Vector2(homes[i]["house"])), 0.75, "двері на хаті")
		assert_eq(pts[0], door)
		for k in range(1, pts.size()):
			assert_lte(pts[k].distance_to(pts[k - 1]), Footpaths.STEP * 1.5, "%s: розрив стежки %d" % [p, i])
		var last: Vector2 = pts[pts.size() - 1]
		assert_false(props._placer.on_road(last, 0.0), "%s: стежка хати %d заходить на полотно" % [p, i])
		assert_true(props._placer.on_road(last, 0.4), "%s: стежка хати %d не доходить до узбіччя" % [p, i])
		assert_eq((yard[i]["half"] as PackedFloat32Array).size(), pts.size())


func test_one_or_two_water_paths_that_stay_on_dry_ground(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var water: Array = props.footpaths.filter(func(w: Dictionary) -> bool: return w["kind"] == &"water")
	assert_between(water.size(), 1, 2, "%s: стежок до води" % p)
	for w: Dictionary in water:
		var pts: PackedVector2Array = w["pts"]
		assert_false(props._placer.on_road(pts[0], 0.0), "не заходить на полотно")
		assert_true(props._placer.on_road(pts[0], 0.4), "починається на узбіччі")
		for k in pts.size():
			assert_gte(view._height.at(pts[k].x, pts[k].y), TerrainHeight.WATER_LEVEL, "%s: стежка у воді в %s" % [p, pts[k]])
			if k > 0:
				assert_lte(pts[k].distance_to(pts[k - 1]), Footpaths.STEP * 1.5)
		var end: Vector2 = pts[pts.size() - 1]
		var wet := false
		for o: Vector2 in [Vector2(0.2, 0), Vector2(-0.2, 0), Vector2(0, 0.2), Vector2(0, -0.2)]:
			wet = wet or view._height.at(end.x + o.x, end.y + o.y) < TerrainHeight.WATER_LEVEL
		assert_true(wet, "%s: стежка закінчується біля берега" % p)


func test_paths_keep_off_buildings(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	for w: Dictionary in props.footpaths:
		if w["kind"] != &"water":
			continue
		for pt: Vector2 in w["pts"]:
			for b: Array in props._placer.placed:
				assert_false((b[0] as Rect2).has_point(pt), "%s: стежка до води через будівлю" % p)


func test_ground_gets_the_path_mask(p = use_parameters(MAPS)) -> void:
	var mat: ShaderMaterial = _cached(p)._ground.material_override
	assert_true(mat.get_shader_parameter("has_paths"))
	assert_not_null(mat.get_shader_parameter("path_map"))


func test_footpaths_are_deterministic(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var first: Array = view.props().footpaths.duplicate(true)
	var m: MapData = load("res://maps/%s.tres" % p)
	view.build(m.to_board())
	assert_eq(view.props().footpaths, first)


## Жодна точка зносу з вагою понад 0.05 не лежить на полотні дороги: стежка розчиняється на узбіччі.
func test_wear_stays_off_the_road_surface(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var size: Vector2i = view._board_size
	var img: Image = Footpaths.bake(props.footpaths, props.trodden, size)
	var data: PackedByteArray = img.get_data()
	var w: int = img.get_width()
	var lit := 0
	var bad := 0
	var worst := Vector2.ZERO
	for idx in data.size():
		if data[idx] > 13:
			lit += 1
			var q := Vector2(float(idx % w) + 0.5, float(idx / w) + 0.5) / float(Footpaths.PX_PER_TILE) - Vector2(0.5, 0.5)
			if props._placer.on_road(q, 0.0):
				bad += 1
				worst = q
	assert_gt(lit, 2000, "%s: стежки є в масці" % p)
	assert_eq(bad, 0, "%s: знос на полотні дороги, останній %s" % [p, worst])


## Відрізки не видно: та сама крива, розбита вдвічі густіше, дає ті самі пікселі.
func test_wear_does_not_show_segments() -> void:
	var ctrl := PackedVector2Array([Vector2(2, 3), Vector2(4, 3), Vector2(5.5, 4.5), Vector2(5.5, 7)])
	var pts: PackedVector2Array = Footpaths.smooth(Footpaths.meander(ctrl[0], ctrl[1], 0.1, 1.0, 3))
	var fine := PackedVector2Array()
	for k in pts.size() - 1:
		fine.append(pts[k])
		fine.append((pts[k] + pts[k + 1]) * 0.5)
	fine.append(pts[pts.size() - 1])
	var hw := PackedFloat32Array()
	hw.resize(pts.size()); hw.fill(0.04)
	var hf := PackedFloat32Array()
	hf.resize(fine.size()); hf.fill(0.04)
	var a: Image = Footpaths.bake([{"pts": pts, "half": hw, "seed": 4}], PackedVector3Array(), Vector2i(8, 9))
	var b: Image = Footpaths.bake([{"pts": fine, "half": hf, "seed": 4}], PackedVector3Array(), Vector2i(8, 9))
	var lit := 0
	var bad := 0
	for y in a.get_height():
		for x in a.get_width():
			var v: int = int(a.get_pixel(x, y).r * 255.0)
			lit += 1 if v > 0 else 0
			bad += 1 if absi(v - int(b.get_pixel(x, y).r * 255.0)) > 2 else 0
	assert_gt(lit, 500)
	assert_lte(bad, lit / 100, "%d з %d пікселів розійшлися" % [bad, lit])
