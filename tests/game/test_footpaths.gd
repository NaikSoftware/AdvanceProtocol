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


func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Тон стежки — від яскравості трави під нею, а не сталий колір: у дощ трава темнішає ×0.66, і
## стала «гола земля» лягала світлою піщаною плямою (~1.4 яскравості трави).
const GRASS_WET := Color(0.08, 0.075, 0.055)


func test_tone_leaves_grass_without_wear() -> void:
	assert_eq(Footpaths.tone(GRASS_WET, Vector2.ZERO, 1.0), GRASS_WET)


func test_tone_wet_trodden_earth_is_darker_than_grass() -> void:
	var core: Color = Footpaths.tone(GRASS_WET, Vector2(1.0, 0.0), 0.7)
	var l: float = _lum(GRASS_WET)
	# wet_p 0.7 (MUD): k = lerp(1.15, 0.85, 0.7) = 0.94.
	assert_almost_eq(_lum(core), l * 0.94, 1e-6, "середина стежки в багні")
	assert_almost_eq(_lum(Footpaths.tone(GRASS_WET, Vector2(1.0, 0.0), 1.0)), l * 0.85, 1e-6, "середина в дощ")
	assert_true(core.r > core.g and core.g > core.b, "бура земля, не рожева й не сіра: %s" % core)
	assert_almost_eq(core.b / core.g, 0.5492, 1e-3, "синього мало — не рожевий пісок")


func test_tone_dry_trodden_earth_is_only_slightly_lighter() -> void:
	var grass := Color(0.16, 0.15, 0.09)
	assert_almost_eq(_lum(Footpaths.tone(grass, Vector2(1.0, 0.0), 0.0)), _lum(grass) * 1.15, 1e-6)


func test_tone_trodden_patch_follows_grass() -> void:
	var l: float = _lum(GRASS_WET)
	# Пляма: вага 0.8 × G, k — 0.78 у дощ, 1.0 сухо: lum = l × (1 − 0.8 + 0.8 × 0.78).
	assert_almost_eq(_lum(Footpaths.tone(GRASS_WET, Vector2(0.0, 1.0), 1.0)), l * (0.2 + 0.8 * 0.78), 1e-6)
	assert_almost_eq(_lum(Footpaths.tone(GRASS_WET, Vector2(0.0, 1.0), 0.0)), l * (0.2 + 0.8 * 1.0), 1e-6)


func test_tone_trampled_verge_keeps_grass_brightness_near() -> void:
	var l: float = _lum(GRASS_WET)
	# Смуга прим'ятої трави (pm.r 0.3): band_t = 1, вага 0.8, k = 0.93 у дощ, ядра ще нема.
	assert_almost_eq(_lum(Footpaths.tone(GRASS_WET, Vector2(0.3, 0.0), 1.0)), l * (0.2 + 0.8 * 0.93), 1e-6)


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
				assert_false(own.has_point(q), "%s: стежка %d різає свою хату в %s" % [p, i, q])
			for b: Array in props._placer.placed:
				if (b[0] as Rect2) != own:
					assert_false((b[0] as Rect2).has_point(q), "%s: стежка %d в чужій будівлі %s" % [p, i, q])
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
		assert_between(Footpaths.length(pts), 2.0, 14.0, "%s: довжина стежки до води" % p)
		# Причина: починається від хвіртки двору або від узбіччя дороги.
		var from_gate := false
		for gi: int in props._placer.gates:
			var g: Vector2 = props._placer.gates[gi][0] + (props._placer.gates[gi][1] as Vector2) * 0.15
			from_gate = from_gate or g.distance_to(pts[0]) < 0.05
		assert_true(from_gate or props._placer.on_road(pts[0], 0.4), "%s: стежка до води без початку" % p)
		var landing := false
		for lw: Dictionary in props.footpaths:
			landing = landing or (lw["kind"] == &"landing" and (lw["door"] as Vector2).distance_to(pts[pts.size() - 1]) < 0.05)
		assert_true(landing, "%s: на березі нема витоптаного майданчика" % p)
		for k in pts.size():
			assert_true(pts[k].x >= -0.3 and pts[k].y >= -0.3 and pts[k].x <= bs.x - 0.7 and pts[k].y <= bs.y - 0.7, "%s: стежка поза дошкою %s" % [p, pts[k]])
			assert_gte(view._height.at(pts[k].x, pts[k].y), TerrainHeight.WATER_LEVEL, "%s: стежка у воді в %s" % [p, pts[k]])
			if k > 0:
				assert_lte(pts[k].distance_to(pts[k - 1]), Footpaths.STEP * 1.2)
		var end: Vector2 = pts[pts.size() - 1]
		var wet := false
		for o: Vector2 in [Vector2(0.25, 0), Vector2(-0.25, 0), Vector2(0, 0.25), Vector2(0, -0.25)]:
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
		assert_gte(hw[0], Footpaths.HALF * 1.8, "%s: пляма біля ґанку ×2.5" % p)
		var mx := 0.0
		for v in hw:
			mx = maxf(mx, v)
		assert_gte(mx, Footpaths.HALF * 1.8)


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
	var img: Image = Footpaths.bake(props.footpaths, props.trodden, size, view._dry_grid())
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
	var placer: PropLayer._Placer = _cached(p).props()._placer
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
		if w["kind"] != &"yard":
			continue
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
		bad += 1 if absi(da[idx] - db[idx]) > 4 else 0
	assert_gt(lit, 100)
	assert_lte(bad, lit / 200, "%s: %d з %d пікселів розійшлися" % [p, bad, lit])


func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1: float = (b - a).cross(c - a)
	var d2: float = (b - a).cross(d - a)
	var d3: float = (d - c).cross(a - c)
	var d4: float = (d - c).cross(b - c)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


## Жодна стежка не перетинає секцій парканів (двір проходить лише крізь хвіртку).
func test_paths_do_not_cross_fence_sections(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var fences: Array = []
	for inst: Dictionary in props._instances:
		var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		if k == PropLayer.Kind.GARDEN_FENCE or k == PropLayer.Kind.FIELD_FENCE:
			var xf: Transform3D = inst["transform"]
			var aabb: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
			var a3: Vector3 = xf * Vector3(aabb.position.x, 0, 0)
			var b3: Vector3 = xf * Vector3(aabb.end.x, 0, 0)
			fences.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z)])
	assert_gt(fences.size(), 10, "%s: паркани знайдено" % p)
	for w: Dictionary in props.footpaths:
		var pts: PackedVector2Array = w["pts"]
		for k in range(1, pts.size()):
			for f: Array in fences:
				assert_false(_crosses(pts[k - 1], pts[k], f[0], f[1]), "%s: %s-стежка %d перетинає паркан в %s" % [p, w["kind"], w["home"], pts[k]])


func _rect_dist(r: Rect2, q: Vector2) -> float:
	return Vector2(maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0), maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0)).length()


## Обіцяний запас: 0.2 від будівель і парканів, 0.1 від ріллі й грядок (біля початку, де хвіртка, паркан не міряємо).
func test_water_paths_keep_their_margins(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	for w: Dictionary in props.footpaths:
		if w["kind"] != &"water":
			continue
		var pts: PackedVector2Array = w["pts"]
		for k in range(2, pts.size()):
			var q: Vector2 = pts[k]
			for b: Array in props._placer.placed:
				assert_gte(_rect_dist(b[0], q), 0.2 - 0.02, "%s: ближче 0.2 до будівлі в %s" % [p, q])
			for r: Rect2 in props.field_edges:
				assert_gte(_rect_dist(r, q), 0.1 - 0.02, "%s: ближче 0.1 до ріллі в %s" % [p, q])
			for gp: Dictionary in props._garden_plots:
				assert_gte(_rect_dist(gp["rect"], q), 0.1 - 0.02, "%s: ближче 0.1 до грядки в %s" % [p, q])
			if q.distance_to(pts[0]) > 0.7:
				assert_gte(props._placer.fence_dist(q), 0.2 - 0.02, "%s: ближче 0.2 до паркану в %s" % [p, q])


## Маска без фільтра: знос на полотні дороги лише від широких плям біля воріт, не від самих стежок.
func test_raw_geometry_barely_touches_the_road(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var walks: Array = props.footpaths.filter(func(w: Dictionary) -> bool: return w["kind"] == &"water")
	var img: Image = Footpaths.bake(walks, PackedVector3Array(), view._board_size)
	var data: PackedByteArray = img.get_data()
	var w: int = img.get_width()
	var bad := 0
	for idx in range(0, data.size(), 2):
		if data[idx] > 13:
			var q := Vector2(float((idx / 2) % w) + 0.5, float((idx / 2) / w) + 0.5) / float(Footpaths.PX_PER_TILE) - Vector2(0.5, 0.5)
			if props._placer.on_road(q, 0.0):
				bad += 1
	# Стежка до води, що перетинає дорогу, дозволена; поза нею шлях її не торкається.
	assert_lt(bad, 4000, "%s: знос води на дорозі" % p)


## Без рельєфу _dry_grid усе одно відсікає дорогу (воду відсікати нічим).
func test_dry_grid_without_height_still_cuts_the_road(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var kept: TerrainHeight = view._height
	view._height = null
	var cut: Callable = view._dry_grid()
	view._height = kept
	assert_true(cut.is_valid())
	var road := Vector2.INF
	for segs: Array in view.props()._placer.road_index.values():
		road = segs[0][0]
		break
	assert_false(cut.call(road), "%s: дорога не відсікається" % p)
