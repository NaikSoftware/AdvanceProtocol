extends GutTest
## Світ довкола дошки (Surroundings): відстань від дошки, серпанок і затемнення, світ із кільцем,
## меш кільця смугами, а також інваріанти рельєфу дошки, коли він запікається разом із кільцем.

const M: float = TerrainHeight.M
const _MAPS: Array[String] = ["res://maps/river.tres", "res://maps/crossroads.tres", "res://maps/ridge.tres"]
const _ROADS := preload("res://tests/game/test_road_course.gd")

## Запікання світу — ~2 с на карту, тож одне на карту на весь файл.
static var _cache: Dictionary = {}


func _world(path: String) -> Array:
	if not _cache.has(path):
		var m: MapData = load(path)
		var b: Board = m.to_board()
		var w: Board = Surroundings.world_board(b, m)
		var t := TerrainHeight.bake(w, 0, m.name_key.hash(), Surroundings.world_surface(m), Surroundings.ring_of(m))
		_cache[path] = [m, b, w, t]
	return _cache[path]


func test_board_distance_is_zero_inside_and_euclidean_outside() -> void:
	var size := Vector2i(26, 22)
	assert_eq(Surroundings.board_distance(Vector2(12, 10), size), 0.0)
	assert_eq(Surroundings.board_distance(Vector2(-0.5, 3), size), 0.0, "край дошки — край клітинки")
	assert_almost_eq(Surroundings.board_distance(Vector2(-3.5, 3), size), 3.0, 1e-5)
	assert_almost_eq(Surroundings.board_distance(Vector2(28.5, 25.5), size), 5.0, 1e-5, "кут: 3-4-5")


func test_haze_is_clear_to_3_tiles_half_at_7_and_full_at_11() -> void:
	assert_eq(Surroundings.haze(3.0), 0.0)
	assert_almost_eq(Surroundings.haze(7.0), 0.5, 1e-5)
	assert_eq(Surroundings.haze(11.0), 1.0)
	assert_eq(Surroundings.haze(0.0), 0.0, "дошка без серпанку")


## Біля дошки тон землі не змінюється зовсім: затемнення йде лише разом із серпанком.
func test_grade_starts_only_with_the_haze_and_follows_its_curve() -> void:
	for d: float in [0.0, 0.5, 1.0, 2.0, 3.0]:
		assert_eq(Surroundings.grade(d), 0.0, "%.1f клітинки від дошки" % d)
	for d: float in [4.0, 7.0, 10.0, 11.0]:
		assert_eq(Surroundings.grade(d), Surroundings.haze(d))
	# Яскравість −20 %, насиченість −35 %: у межах брифу (−15…−25 % і −30…−45 %).
	assert_between(Surroundings.GRADE_LUMA, 0.75, 0.85)
	assert_between(Surroundings.GRADE_SAT, 0.55, 0.7)


func test_world_board_takes_live_board_kinds_and_the_authored_ring() -> void:
	var m: MapData = load("res://maps/river.tres")
	var b: Board = m.to_board()
	var bridge := Vector2i(-1, -1)
	for i in b.tiles.size():
		if b.tiles[i] == Terrain.Kind.BRIDGE:
			bridge = Vector2i(i % b.width, i / b.width)
			break
	b.set_kind(bridge, Terrain.Kind.BRIDGE_DESTROYED)
	var mg: int = Surroundings.ring_of(m)
	var w: Board = Surroundings.world_board(b, m)
	assert_eq(mg, 12)
	assert_eq(Vector2i(w.width, w.height), Vector2i(b.width + 24, b.height + 24))
	assert_eq(w.kind_at(bridge + Vector2i(mg, mg)), Terrain.Kind.BRIDGE_DESTROYED, "підірваний міст — з живої дошки")
	assert_eq(w.kind_at(Vector2i.ZERO), m.outer_kind_at(Vector2i(-mg, -mg)))
	assert_eq(w.kind_at(Vector2i(w.width - 1, w.height - 1)), m.outer_kind_at(Vector2i(b.width - 1 + mg, b.height - 1 + mg)))


func test_without_a_ring_the_world_is_the_board() -> void:
	var m := MapData.new()
	m.width = 3
	m.height = 2
	m.tiles = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var b: Board = m.to_board()
	assert_eq(Surroundings.ring_of(m), 0)
	assert_same(Surroundings.world_board(b, m), b)
	assert_eq(Surroundings.ring_of(null), 0)


func test_world_surface_carries_board_and_ring_subtypes() -> void:
	var m: MapData = load("res://maps/river.tres")
	var mg: int = Surroundings.ring_of(m)
	var s: PackedByteArray = Surroundings.world_surface(m)
	var ow: int = m.width + 2 * mg
	assert_eq(s.size(), ow * (m.height + 2 * mg))
	for i in s.size():
		var p := Vector2i(i % ow - mg, i / ow - mg)
		var want: int = m.surface_at(p) if p.x >= 0 and p.y >= 0 and p.x < m.width and p.y < m.height else m.outer_surface[i]
		if s[i] != want:
			fail_test("підтип %s: %d замість %d" % [p, s[i], want])
			return
	pass_test("усі підтипи на місці")


func test_ring_mesh_bands_stay_within_the_triangle_budget() -> void:
	var size := Vector2i(26, 22)
	assert_eq(Surroundings.quads_for(Vector2i(0, 0), size, 7), 7)
	assert_eq(Surroundings.quads_for(Vector2i(-1, 5), size, 7), 7, "перша клітинка за краєм — як дошка")
	assert_eq(Surroundings.quads_for(Vector2i(-2, 5), size, 7), 2)
	assert_eq(Surroundings.quads_for(Vector2i(31, 5), size, 7), 2)
	assert_eq(Surroundings.quads_for(Vector2i(-7, -7), size, 7), 1)
	var board_tris: int = size.x * size.y * 7 * 7 * 2
	var mesh: ArrayMesh = Surroundings.ground_mesh(size, 12, 7)
	var tris: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_lte(tris - board_tris, 20000, "кільце: %d трикутників" % (tris - board_tris))


## Т-з'єднання без щілини: вершина на ребрі з грубшою клітинкою лежить на відрізку між двома
## вершинами грубої клітинки, і ці кінці — справжні вершини меша.
func test_ring_mesh_snaps_every_t_junction_onto_the_coarse_edge() -> void:
	var mesh: ArrayMesh = Surroundings.ground_mesh(Vector2i(6, 5), 8, 3)
	var a: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var positions: Dictionary = {}
	for v in verts:
		positions[Vector2(snappedf(v.x, 1e-4), snappedf(v.z, 1e-4))] = true
	var snapped := 0
	for i in verts.size():
		if col[i].a < 0.5:
			continue
		snapped += 1
		var p := Vector2(verts[i].x, verts[i].z)
		var ab: Vector2 = uv2[i] - uv[i]
		var t: float = clampf((p - uv[i]).dot(ab) / ab.dot(ab), 0.0, 1.0)
		assert_almost_eq(p.distance_to(uv[i].lerp(uv2[i], t)), 0.0, 1e-4, "вершина %d на грубому ребрі" % i)
		for e: Vector2 in [uv[i], uv2[i]]:
			assert_true(positions.has(Vector2(snappedf(e.x, 1e-4), snappedf(e.y, 1e-4))), "кінець ребра %s — вершина меша" % e)
	assert_gt(snapped, 0, "стики смуг є")


## Ті самі інваріанти, що й у test_terrain_height.gd для дошки без кільця: правила бачать воду там,
## де її показує рельєф, а юніт у центрі клітинки суші стоїть на сухому.
func test_world_bake_keeps_water_and_land_invariants_on_the_board() -> void:
	for path: String in _MAPS:
		var w: Array = _world(path)
		var b: Board = w[1]
		var t: TerrainHeight = w[3]
		for y in b.height:
			for x in b.width:
				var c := Vector2i(x, y)
				if TerrainHeight._is_water(b.kind_at(c)):
					var wet := 0
					for j in 11:
						for i in 11:
							wet += 1 if t.at(x - 0.5 + i * 0.1, y - 0.5 + j * 0.1) < TerrainHeight.WATER_LEVEL else 0
					# 30 зі 121 відліку, на один менше за чверть: River (14,9) біля мосту, де берег не
					# розсувається, і (1,13), куди річка кільця вже не заходить. Один відлік сітки 11×11 — допуск.
					assert_gte(wet, 30, "%s: клітинка води %s — %d зі 121 відліку" % [path, c, wet])
				else:
					for r10 in 4:
						for k in 16:
							var ang: float = TAU * k / 16.0
							if t.at(x + 0.1 * r10 * cos(ang), y + 0.1 * r10 * sin(ang)) < TerrainHeight.WATER_LEVEL:
								fail_test("%s: вода за %.1f від центру суші %s" % [path, 0.1 * r10, c])
								return


func test_world_bake_puts_each_crossing_on_one_deck_above_the_water() -> void:
	for path: String in _MAPS:
		var t: TerrainHeight = _world(path)[3]
		for g in t.bridge_groups():
			var cells: Array = g["cells"]
			var deck: float = t.deck_y(cells[0])
			for c: Vector2i in cells:
				assert_eq(t.deck_y(c), deck, "%s: одна висота переправи %s" % [path, c])
			assert_gt(deck - TerrainHeight.WATER_LEVEL, 1.0 * M, "%s: настил ≥ 1 м над водою" % path)


func test_world_bake_covers_every_road_cell_of_board_and_ring() -> void:
	for path: String in _MAPS:
		var w: Array = _world(path)
		var wb: Board = w[2]
		var rc: RoadCourse = (w[3] as TerrainHeight).roads
		var img: Image = rc.rasterise()[0]
		for y in wb.height:
			for x in wb.width:
				var c := Vector2i(x, y)
				if wb.kind_at(c) != Terrain.Kind.ROAD:
					continue
				var d: float = _ROADS._dist_to_lines(rc, Vector2(c))
				var cov: float = _ROADS._coverage(rc, img, c)
				assert_true(d < 0.6 or cov >= 0.25, "%s: дорога %s — вісь за %.2f, покриття %.0f %%" % [path, c, d, cov * 100.0])


## Річка не закінчується ставком на краю дошки: вода доходить до зовнішнього краю кільця.
func test_river_runs_through_the_ring_to_its_outer_edge() -> void:
	var w: Array = _world("res://maps/river.tres")
	var m: MapData = w[0]
	var t: TerrainHeight = w[3]
	var mg: int = Surroundings.ring_of(m)
	for edge_x: float in [-mg - 0.4, m.width - 1 + mg + 0.4]:
		var wet := false
		for zi in (m.height + 2 * mg) * 10:
			wet = wet or t.at(edge_x, -mg - 0.5 + zi * 0.1) < TerrainHeight.WATER_LEVEL
		assert_true(wet, "вода на краю кільця x = %.1f" % edge_x)


## Річка не має видимого кінця поза дошкою: кожен вільний кінець осі (не ставка й не стик з
## іншою віссю) або під повним серпанком, або всередині води, що тягнеться ще клітинку за ним
## (відгалуження скелета в широкому руслі, без берега довкола кінця). Кінці на самій дошці
## задають клітинки води карти, тут вони не перевіряються.
func test_no_river_course_ends_in_view_outside_the_board() -> void:
	for path: String in _MAPS:
		var w: Array = _world(path)
		var m: MapData = w[0]
		var t: TerrainHeight = w[3]
		var c: RiverCourse = t.course
		if c == null:
			continue
		var mg := Vector2(Surroundings.ring_of(m), Surroundings.ring_of(m))
		var size := Vector2i(m.width, m.height)
		for li in c.lines.size():
			var pts: PackedVector2Array = c.lines[li]
			if c._pond_lines.has(li) or pts.size() < 2:
				continue
			for side in 2:
				var e: Vector2 = pts[0] if side == 0 else pts[pts.size() - 1]
				var out: Vector2 = (e - (pts[1] if side == 0 else pts[pts.size() - 2])).normalized()
				var joined := false
				for lj in c.lines.size():
					if lj != li:
						for q: Vector2 in c.lines[lj]:
							joined = joined or q.distance_to(e) < 0.6
				var p: Vector2 = e - mg
				var d: float = Surroundings.board_distance(p, size)
				if joined or d <= 0.0:
					continue
				var beyond: Vector2 = p + out
				var hidden: bool = d >= Surroundings.HAZE_FULL or t.at(beyond.x, beyond.y) < TerrainHeight.WATER_LEVEL
				assert_true(hidden, "%s: вісь %d кінчається в кадрі в %s (%.1f клітинки від дошки)" % [path, li, p, d])


## Озеро чи ставок — замкнена водойма з берегом довкола: за край світу (під заслін) виходить лише
## вода, крізь яку тече вісь річки.
func test_only_rivers_reach_the_outer_edge_of_the_world() -> void:
	for path: String in _MAPS:
		var t: TerrainHeight = _world(path)[3]
		var w: int = t.cols
		var h: int = t.rows
		var s: float = float(t.samples)
		var org: float = -0.5 - t.margin
		var wet := func(k: int) -> bool:
			return t._h[k] < TerrainHeight.WATER_LEVEL
		var river := PackedByteArray()
		river.resize(w * h)
		if t.course != null:
			# Вісь курсу — у координатах світу (TerrainHeight.bake з ring), відлік (i, j) — у -0.5 + i / s.
			for li in t.course.lines.size():
				if t.course._pond_lines.has(li):
					continue
				for q: Vector2 in t.course.lines[li]:
					var i: int = roundi((q.x + 0.5) * s)
					var j: int = roundi((q.y + 0.5) * s)
					if i >= 0 and j >= 0 and i < w and j < h:
						river[j * w + i] = 1
		var seen := PackedByteArray()
		seen.resize(w * h)
		for start in w * h:
			var x0: int = start % w
			var y0: int = start / w
			if seen[start] == 1 or not wet.call(start) or (x0 > 0 and y0 > 0 and x0 < w - 1 and y0 < h - 1):
				continue
			var has_river := false
			var stack: Array[int] = [start]
			seen[start] = 1
			while not stack.is_empty():
				var k: int = stack.pop_back()
				has_river = has_river or river[k] == 1
				for o: Vector2i in Board.DIRS_4:
					var x: int = k % w + o.x
					var y: int = k / w + o.y
					if x >= 0 and y >= 0 and x < w and y < h and seen[y * w + x] == 0 and wet.call(y * w + x):
						seen[y * w + x] = 1
						stack.append(y * w + x)
			assert_true(has_river, "%s: вода на краю світу біля (%.1f, %.1f) без осі річки" % [path, org + x0 / s, org + y0 / s])


func test_board_relief_inside_stays_the_same_with_the_ring() -> void:
	# Шум рельєфу прив'язаний до дошки; кільце міняє лише смугу біля краю (річка, дороги й
	# пагорби, що тепер тривають за ним).
	var w: Array = _world("res://maps/ridge.tres")
	var m: MapData = w[0]
	var plain := TerrainHeight.bake(m.to_board(), 0, m.name_key.hash(), m.surface)
	var t: TerrainHeight = w[3]
	var worst := 0.0
	for z in range(4, m.height - 4):
		for x in range(4, m.width - 4):
			worst = maxf(worst, absf(plain.at(x, z) - t.at(x, z)))
	assert_lt(worst, 0.75 * M, "найбільша різниця висоти в глибині дошки %.2f м" % (worst / M))


## Дотик по кільцю потрапляє в землю кільця, але дає клітинку поза дошкою, яку Board.in_bounds
## відкидає; що далі робить InputController.tap_cell — test_tap_outside_board_clears_selection.
func test_tap_on_the_ring_picks_a_cell_outside_the_board() -> void:
	var w: Array = _world("res://maps/crossroads.tres")
	var b: Board = w[1]
	var rig: IsoCameraRig = load("res://game/camera/iso_camera_rig.tscn").instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(b.width, b.height))
	TerrainHeight.active = w[3]
	rig.center_on(Vector2i(0, 0))
	var target := Vector3(-5.0, (w[3] as TerrainHeight).at(-5.0, -4.0), -4.0)
	var cell: Vector2i = rig.screen_point_to_cell(rig.unproject(target))
	TerrainHeight.active = null
	assert_eq(cell, Vector2i(-5, -4), "дотик лягає на землю кільця")
	assert_false(b.in_bounds(cell))
