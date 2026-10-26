extends GutTest
## Протоптані стежки: знос у масці землі, а не вузли чи декалі. Вигляд не знає про сітку: шум
## зносу лежить у координатах самої стежки (вздовж, поперек), тож ніякої світової текстури.

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
const BoardViewScene := preload("res://game/battle/board_view.tscn")


func _walk(a: Vector2, b: Vector2, half: float = 0.0375, seed_value: int = 5) -> Dictionary:
	var pts: PackedVector2Array = Footpaths.meander(a, b, 0.0, 1.2, seed_value)
	var hw := PackedFloat32Array()
	hw.resize(pts.size())
	hw.fill(half)
	return {"kind": &"yard", "pts": pts, "half": hw, "seed": seed_value}


func _px(img: Image, p: Vector2, ch: int = 0) -> int:
	var c: Color = img.get_pixel(int((p.x + 0.5) * Footpaths.PX_PER_TILE), int((p.y + 0.5) * Footpaths.PX_PER_TILE))
	return int(round((c.r if ch == 0 else c.g) * 255.0))


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


## Поперечний профіль: середнє по довжині спадає від осі без плато й без крутого краю.
func test_wear_profile_is_a_peak_not_a_plateau() -> void:
	var img: Image = Footpaths.bake([_walk(Vector2(2, 5), Vector2(11, 5))], PackedVector3Array(), Vector2i(14, 10))
	var px: int = Footpaths.PX_PER_TILE
	var mid: int = int(5.5 * px)
	var prof: Array[float] = []
	for dy in range(0, 7):
		var sum := 0.0
		var n := 0
		for x in range(int(3.5 * px), int(10.0 * px)):
			sum += img.get_pixel(x, mid + dy).r * 255.0
			sum += img.get_pixel(x, mid - dy - 1).r * 255.0
			n += 2
		prof.append(sum / n)
	gut.p("профіль від осі (0..255): %s" % [prof])
	assert_gt(prof[0], 60.0, "посередині знос помітний")
	for k in range(1, 7):
		assert_lt(prof[k], prof[k - 1] + 0.5, "профіль не росте від осі (k=%d)" % k)
	assert_lt(prof[1], prof[0] * 0.85, "нема плато біля осі")
	assert_lt(prof[0] - prof[1], prof[0] * 0.7, "нема крутого краю: різниця сусідніх пікселів")
	assert_lt(prof[6], 6.0, "за ~0.5 м від осі знос зник")


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
	assert_gt(_px(img, Vector2(4, 4), 1), 60)
	assert_eq(_px(img, Vector2(4, 4), 0), 0, "пляма — окремий канал")
	assert_eq(_px(img, Vector2(4.4, 4), 1), 0)


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


func _yard_walks(props: PropLayer) -> Dictionary:
	var yard: Dictionary = {}
	for w: Dictionary in props.footpaths:
		if w["kind"] == &"yard":
			yard[int(w["home"])] = w
	return yard


func test_every_house_has_a_continuous_path_from_door_to_road(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	var yard: Dictionary = _yard_walks(props)
	for i in homes.size():
		assert_true(yard.has(i), "%s: у хати %d нема стежки" % [p, i])
		if not yard.has(i):
			continue
		var pts: PackedVector2Array = yard[i]["pts"]
		var door: Vector2 = yard[i]["door"]
		assert_lte(door.distance_to(Vector2(homes[i]["house"])), 0.75, "двері на хаті")
		assert_eq(pts[0], door)
		for k in range(1, pts.size()):
			assert_lte(pts[k].distance_to(pts[k - 1]), Footpaths.STEP * 1.2, "%s: розрив стежки %d" % [p, i])
		var last: Vector2 = pts[pts.size() - 1]
		assert_false(props._placer.on_road(last, 0.0), "%s: стежка хати %d заходить на полотно" % [p, i])
		assert_true(props._placer.on_road(last, 0.4), "%s: стежка хати %d не доходить до узбіччя" % [p, i])
		assert_eq((yard[i]["half"] as PackedFloat32Array).size(), pts.size())


## Стежка двору не різає ні свою хату (двері дивляться від воріт — обхід), ні чужі будівлі, ріллю й міст.
func test_yard_paths_go_round_buildings(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var yard: Dictionary = _yard_walks(props)
	for i in yard:
		var own: Rect2 = props._placer.doors[i][2]
		var pts: PackedVector2Array = yard[i]["pts"]
		for k in pts.size():
			var q: Vector2 = pts[k]
			if k > 3:
				assert_false(own.grow(-0.03).has_point(q), "%s: стежка %d різає свою хату в %s" % [p, i, q])
			for b: Array in props._placer.placed:
				if (b[0] as Rect2) != own:
					assert_false((b[0] as Rect2).grow(-0.03).has_point(q), "%s: стежка %d в чужій будівлі %s" % [p, i, q])
			for r: Rect2 in props.field_edges:
				assert_false(r.has_point(q), "%s: стежка %d на ріллі" % [p, i])
			var c := Vector2i(roundi(q.x), roundi(q.y))
			assert_false([Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED].has(props._placer.kind(c)), "%s: стежка %d на мосту" % [p, i])


func test_one_or_two_water_paths_that_stay_on_dry_ground(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var water: Array = props.footpaths.filter(func(w: Dictionary) -> bool: return w["kind"] == &"water")
	assert_between(water.size(), 1, 2, "%s: стежок до води" % p)
	var bs: Vector2i = view._board_size
	for w: Dictionary in water:
		var pts: PackedVector2Array = w["pts"]
		assert_between(Footpaths.length(pts), 4.0, 13.0, "%s: довжина стежки до води" % p)
		assert_gte(Footpaths.turns(pts), 1, "%s: вигинів на стежці до води" % p)
		assert_false(props._placer.on_road(pts[0], 0.0), "не заходить на полотно")
		assert_true(props._placer.on_road(pts[0], 0.4), "починається на узбіччі")
		for k in pts.size():
			assert_true(pts[k].x >= -0.3 and pts[k].y >= -0.3 and pts[k].x <= bs.x - 0.7 and pts[k].y <= bs.y - 0.7, "%s: стежка поза дошкою %s" % [p, pts[k]])
			assert_gte(view._height.at(pts[k].x, pts[k].y), TerrainHeight.WATER_LEVEL, "%s: стежка у воді в %s" % [p, pts[k]])
			if k > 0:
				assert_lte(pts[k].distance_to(pts[k - 1]), Footpaths.STEP * 1.2)
		var end: Vector2 = pts[pts.size() - 1]
		var wet := false
		for o: Vector2 in [Vector2(0.2, 0), Vector2(-0.2, 0), Vector2(0, 0.2), Vector2(0, -0.2)]:
			wet = wet or view._height.at(end.x + o.x, end.y + o.y) < TerrainHeight.WATER_LEVEL
		assert_true(wet, "%s: стежка закінчується біля берега" % p)


## Стежки до води обходять ріллю й грядки без винятків; коридор від ґанку до хвіртки ~1.2 м.
func test_water_paths_go_round_fields_and_gardens(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	for w: Dictionary in props.footpaths:
		if w["kind"] != &"water":
			continue
		for q: Vector2 in w["pts"]:
			for r: Rect2 in props.field_edges:
				assert_false(r.has_point(q), "%s: стежка до води на ріллі %s" % [p, q])
			for gp: Dictionary in props._garden_plots:
				assert_false((gp["rect"] as Rect2).has_point(q), "%s: стежка до води на грядці %s" % [p, q])


func test_yard_corridor_is_wide_at_porch_and_gate(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	for w: Dictionary in _yard_walks(props).values():
		var hw: PackedFloat32Array = w["half"]
		assert_gte(hw[0], 0.075 * 1.9, "%s: пляма біля ґанку ×2.5" % p)
		var mx := 0.0
		for v in hw:
			mx = maxf(mx, v)
		assert_gte(mx, 0.075 * 2.0)


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


## Жодна точка зносу з вагою понад 0.05 не лежить на полотні дороги; знос не обрізається краєм дошки;
## кожна стежка двору помітна (навіть коротка).
func test_baked_mask_is_clean(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var size: Vector2i = view._board_size
	var img: Image = Footpaths.bake(props.footpaths, props.trodden, size)
	var data: PackedByteArray = img.get_data()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lit := 0
	var bad := 0
	var worst := Vector2.ZERO
	for idx in range(0, data.size(), 2):
		if data[idx] > 13 or data[idx + 1] > 13:
			lit += 1
			var pi: int = idx / 2
			var q := Vector2(float(pi % w) + 0.5, float(pi / w) + 0.5) / float(Footpaths.PX_PER_TILE) - Vector2(0.5, 0.5)
			if props._placer.on_road(q, 0.0):
				bad += 1
				worst = q
	assert_gt(lit, 500, "%s: стежки є в масці" % p)
	assert_eq(bad, 0, "%s: знос на полотні дороги, останній %s" % [p, worst])
	var cut := 0
	for x in w:
		for y in [0, 1, h - 2, h - 1]:
			cut += 1 if img.get_pixel(x, y).r > 0.05 or img.get_pixel(x, y).g > 0.05 else 0
	for y in h:
		for x in [0, 1, w - 2, w - 1]:
			cut += 1 if img.get_pixel(x, y).r > 0.05 or img.get_pixel(x, y).g > 0.05 else 0
	assert_eq(cut, 0, "%s: маска обрізана краєм дошки" % p)
	for wk: Dictionary in _yard_walks(props).values():
		var best := 0
		for q: Vector2 in wk["pts"]:
			best = maxi(best, _px(img, q))
		assert_gte(best, 100, "%s: стежка хати %d непомітна" % [p, wk["home"]])


## Захист від полотна: точка, що вже лежить на дорозі, виштовхується за її край.
func test_verge_point_never_lands_on_the_road(p = use_parameters(MAPS)) -> void:
	var placer = _cached(p).props()._placer
	if not placer.road_indexed:
		placer._index_roads()
	var n := 0
	for segs: Array in placer.road_index.values():
		for seg: Array in segs:
			var mid: Vector2 = ((seg[0] as Vector2) + (seg[1] as Vector2)) * 0.5
			var v: Vector2 = placer._verge_point(mid)
			assert_false(placer.on_road(v, 0.0), "%s: узбіччя на полотні %s" % [p, v])
			n += 1
			if n > 40:
				return


## Відрізків не видно: справжня склеєна крива «двір → хвіртка → дорога» зі згинами, розбита вдвічі
## густіше, дає ті самі пікселі.
func test_wear_does_not_show_segments(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var longest: Dictionary = {}
	for w: Dictionary in props.footpaths:
		if longest.is_empty() or Footpaths.length(w["pts"]) > Footpaths.length(longest["pts"]):
			longest = w
	var pts: PackedVector2Array = longest["pts"]
	var hw: PackedFloat32Array = longest["half"]
	var fine := PackedVector2Array()
	var hf := PackedFloat32Array()
	for k in pts.size() - 1:
		fine.append(pts[k])
		hf.append(hw[k])
		fine.append((pts[k] + pts[k + 1]) * 0.5)
		hf.append((hw[k] + hw[k + 1]) * 0.5)
	fine.append(pts[pts.size() - 1])
	hf.append(hw[hw.size() - 1])
	var size: Vector2i = _cached(p)._board_size
	var a: Image = Footpaths.bake([{"pts": pts, "half": hw, "seed": 4}], PackedVector3Array(), size)
	var b: Image = Footpaths.bake([{"pts": fine, "half": hf, "seed": 4}], PackedVector3Array(), size)
	var lit := 0
	var bad := 0
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	for idx in range(0, da.size(), 2):
		lit += 1 if da[idx] > 0 else 0
		bad += 1 if absi(da[idx] - db[idx]) > 8 else 0
	assert_gt(lit, 100)
	assert_lte(bad, lit / 50, "%s: %d з %d пікселів розійшлися" % [p, bad, lit])
