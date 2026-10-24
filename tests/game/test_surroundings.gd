extends GutTest
## Світ довкола дошки (Surroundings): відстань від дошки, імла й затемнення, світ із кільцем,
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


## Меш кільця на кожній поставній карті — зі справжніми клітинками води й берега густоти дошки —
## не більший за `Surroundings.RING_TRIS_MAX`.
func test_ring_mesh_bands_stay_within_the_triangle_budget() -> void:
	var size := Vector2i(26, 22)
	assert_eq(Surroundings.quads_for(Vector2i(0, 0), size, 7), 7)
	assert_eq(Surroundings.quads_for(Vector2i(-1, 5), size, 7), 7, "перша клітинка за краєм — як дошка")
	assert_eq(Surroundings.quads_for(Vector2i(-2, 5), size, 7), 2)
	assert_eq(Surroundings.quads_for(Vector2i(31, 5), size, 7), 2)
	assert_eq(Surroundings.quads_for(Vector2i(-7, -7), size, 7), 1)
	for path: String in _MAPS:
		var w: Array = _world(path)
		var b: Board = w[1]
		var t: TerrainHeight = w[3]
		var mg: int = Surroundings.ring_of(w[0])
		var board_tris: int = b.width * b.height * t.samples * t.samples * 2
		var mesh: ArrayMesh = Surroundings.ground_mesh(Vector2i(b.width, b.height), mg, t.samples,
				t.bank_cells())
		var tris: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_lte(tris - board_tris, Surroundings.RING_TRIS_MAX,
				"%s: кільце %d трикутників" % [path, tris - board_tris])


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


## Грубий квад кільця над руслом закривав би воду прямими ребрами: клітинка з водою чи схилом
## берега має густоту дошки, а суха клітинка далеко від води — своєї смуги.
func test_ring_cells_with_water_or_bank_get_the_board_density() -> void:
	var w: Array = _world("res://maps/river.tres")
	var b: Board = w[1]
	var t: TerrainHeight = w[3]
	var size := Vector2i(b.width, b.height)
	var fine: Dictionary = t.bank_cells()
	var ring := 0
	for c: Vector2i in fine:
		if b.in_bounds(c):
			continue
		ring += 1
		assert_eq(Surroundings.quads_for(c, size, t.samples, fine), t.samples, "клітинка %s" % c)
	assert_gt(ring, 0, "річка тече крізь кільце")
	var mg: int = Surroundings.ring_of(w[0])
	for cy in range(-mg, b.height + mg):
		for cx in range(-mg, b.width + mg):
			var wet := false
			for j in 8:
				for i in 8:
					wet = wet or t.at(cx - 0.5 + i / 7.0, cy - 0.5 + j / 7.0) < TerrainHeight.WATER_LEVEL
			if wet and not fine.has(Vector2i(cx, cy)):
				fail_test("клітинка з водою %s без густоти дошки" % Vector2i(cx, cy))
				return
	assert_eq(Surroundings.quads_for(Vector2i(-11, -11), size, t.samples, fine), Surroundings.FAR_QUADS)


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
					# Чверть зі 121 відліку, як і без кільця (test_terrain_height.gd).
					assert_gte(wet, 31, "%s: клітинка води %s — %d зі 121 відліку" % [path, c, wet])
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


## Річка не має видимого кінця: кінець осі річки законний, лише коли він під суцільною імлою,
## або впадає в іншу вісь (лежить у межах її півширини), або за ним на клітинку вздовж течії вже
## нема води карти — там водойму закінчив автор. Одна умова і для дошки, і для кільця.
func test_no_river_course_ends_in_view() -> void:
	var checked := 0
	for path: String in _MAPS:
		var w: Array = _world(path)
		var m: MapData = w[0]
		var wb: Board = w[2]
		var c: RiverCourse = (w[3] as TerrainHeight).course
		if c == null:
			continue
		var mg: int = Surroundings.ring_of(m)
		var size := Vector2i(m.width, m.height)
		for li in c.axis_lines:
			var pts: PackedVector2Array = c.lines[li]
			if pts.size() < 2:
				continue
			for side in 2:
				var e: Vector2 = pts[0] if side == 0 else pts[pts.size() - 1]
				var out: Vector2 = (e - (pts[1] if side == 0 else pts[pts.size() - 2])).normalized()
				var d: float = Surroundings.board_distance(e - Vector2(mg, mg), size)
				var beyond := Vector2i((e + out).round())
				var authored: bool = not wb.in_bounds(beyond) \
						or not TerrainHeight._is_water(wb.kind_at(beyond))
				checked += 1
				assert_true(d >= Surroundings.HAZE_CLOSED or _joins_another_axis(c, li, e) or authored,
						"%s: вісь %d кінчається в кадрі в %s (%.1f клітинки від дошки)"
						% [path, li, e - Vector2(mg, mg), d])
	assert_gt(checked, 0, "кінці осей є")


## Точка лежить у руслі іншої осі: ближче до її ламаної, ніж півширина в цьому місці.
func _joins_another_axis(c: RiverCourse, li: int, e: Vector2) -> bool:
	for lj in c.axis_lines:
		if lj == li:
			continue
		var q: PackedVector2Array = c.lines[lj]
		var hw: PackedFloat32Array = c.halfs[lj]
		for si in q.size() - 1:
			var ab: Vector2 = q[si + 1] - q[si]
			var t: float = clampf((e - q[si]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			if e.distance_to(q[si] + ab * t) <= lerpf(hw[si], hw[si + 1], t):
				return true
	return false


## Річка тече суцільно: кожна область води, через яку йде вісь річки й яка торкається дошки, сягає
## суцільної імли, а відірваних шматків води з віссю річки в кадрі нема. Вода тут — відліки
## запеченої висоти під рівнем води, що лишаються водою й після звуження на 2 відліки в кожен бік:
## перешийок, тонший за ~0.6 клітинки, на екрані — суша, і річка через нього не тече. Ставки й
## озера осі річки не мають і тут не перевіряються.
func test_river_water_is_connected_from_the_board_into_closed_haze() -> void:
	var checked := 0
	for path: String in _MAPS:
		var w: Array = _world(path)
		var m: MapData = w[0]
		var t: TerrainHeight = w[3]
		if t.course == null:
			continue
		var cols: int = t.cols
		var rows: int = t.rows
		var s: float = float(t.samples)
		var size := Vector2i(m.width, m.height)
		var wet := PackedByteArray()
		wet.resize(cols * rows)
		for k in cols * rows:
			var x0: int = k % cols
			var y0: int = k / cols
			var all_wet := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var q: int = clampi(y0 + dy, 0, rows - 1) * cols + clampi(x0 + dx, 0, cols - 1)
					all_wet = all_wet and t._h[q] < TerrainHeight.WATER_LEVEL
			wet[k] = 1 if all_wet else 0
		var axis := PackedByteArray()
		axis.resize(cols * rows)
		for li in t.course.axis_lines:
			for q: Vector2 in t.course.lines[li]:
				var i: int = roundi((q.x + 0.5) * s)
				var j: int = roundi((q.y + 0.5) * s)
				if i >= 0 and j >= 0 and i < cols and j < rows:
					axis[j * cols + i] = 1
		var seen := PackedByteArray()
		seen.resize(cols * rows)
		for start in cols * rows:
			if seen[start] == 1 or wet[start] == 0:
				continue
			var has_axis := false
			var near := 1e9
			var far := 0.0
			var stack: Array[int] = [start]
			seen[start] = 1
			while not stack.is_empty():
				var k: int = stack.pop_back()
				var x: int = k % cols
				var y: int = k / cols
				has_axis = has_axis or axis[k] == 1
				var d: float = Surroundings.board_distance(
						Vector2(-0.5 - t.margin + x / s, -0.5 - t.margin + y / s), size)
				near = minf(near, d)
				far = maxf(far, d)
				for o: Vector2i in Board.DIRS_4:
					var nx: int = x + o.x
					var ny: int = y + o.y
					var nk: int = ny * cols + nx
					if nx >= 0 and ny >= 0 and nx < cols and ny < rows and seen[nk] == 0 \
							and wet[nk] == 1:
						seen[nk] = 1
						stack.append(nk)
			if not has_axis or near >= Surroundings.HAZE_CLOSED:
				continue
			checked += 1
			assert_true(near <= 0.0, "%s: шматок річки відірваний від дошки, %.1f–%.1f клітинки від неї"
					% [path, near, far])
			assert_gte(far, Surroundings.HAZE_CLOSED,
					"%s: річка з дошки кінчається за %.1f клітинки, до суцільної імли" % [path, far])
	assert_gt(checked, 0, "річки є")


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
			# Вісь курсу — у координатах світу (`TerrainHeight.bake` з `ring`), відлік (i, j) — у
			# `-0.5 + i / s`.
			for li in t.course.axis_lines:
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


## Ставок Ridge (вода в рядах 0–1 і 20–21) замкнений: заходить у кільце, але закривається берегом
## за кілька клітинок від дошки й під заслін не виходить.
func test_ridge_ponds_close_inside_the_ring() -> void:
	var w: Array = _world("res://maps/ridge.tres")
	var m: MapData = w[0]
	var t: TerrainHeight = w[3]
	var size := Vector2i(m.width, m.height)
	for cell: Vector2i in [Vector2i(15, 0), Vector2i(10, 21)]:
		var s: int = t.samples
		var start: int = (cell.y + t.margin) * s * t.cols + s / 2 * t.cols + (cell.x + t.margin) * s + s / 2
		assert_lt(t._h[start], TerrainHeight.WATER_LEVEL, "вода в клітинці %s" % cell)
		var seen: Dictionary = {start: true}
		var stack: Array[int] = [start]
		var farthest := 0.0
		var at_edge := false
		while not stack.is_empty() and not at_edge:
			var k: int = stack.pop_back()
			var x: int = k % t.cols
			var y: int = k / t.cols
			at_edge = x == 0 or y == 0 or x == t.cols - 1 or y == t.rows - 1
			var p := Vector2(-0.5 - t.margin + float(x) / s, -0.5 - t.margin + float(y) / s)
			farthest = maxf(farthest, Surroundings.board_distance(p, size))
			for o: Vector2i in Board.DIRS_4:
				var q: int = (y + o.y) * t.cols + x + o.x
				if not seen.has(q) and t._h[q] < TerrainHeight.WATER_LEVEL:
					seen[q] = true
					stack.append(q)
		assert_false(at_edge, "ставок біля %s дійшов до краю світу" % cell)
		assert_lt(farthest, 3.0, "ставок біля %s закривається за %.1f клітинки від дошки" % [cell, farthest])


## Шум рельєфу прив'язаний до дошки, а річка на дошці береться з осі самої дошки
## (`TerrainHeight._keep_board_course`): у глибині дошки кільце майже нічого не міняє — на
## всіх трьох картах різниця не більша за 0.21 м (дороги, що тривають у кільці, лягають сплайном
## трохи інакше). Поріг 0.75 м ловить річку, що з кільцем змінила ширину по всій дошці.
func test_board_relief_inside_stays_the_same_with_the_ring() -> void:
	for path: String in _MAPS:
		var w: Array = _world(path)
		var m: MapData = w[0]
		var plain := TerrainHeight.bake(m.to_board(), 0, m.name_key.hash(), m.surface)
		var t: TerrainHeight = w[3]
		var worst := 0.0
		for z in range(4, m.height - 4):
			for x in range(4, m.width - 4):
				worst = maxf(worst, absf(plain.at(x, z) - t.at(x, z)))
		assert_lt(worst, 0.75 * M, "%s: найбільша різниця висоти в глибині дошки %.2f м" % [path, worst / M])


## Імла пливе за глобальним `fog_time`, що росте кроком 0.1 с (10 кадрів на секунду на дошці
## без руху), а не за `TIME`; годинник один на `BoardView` і переживає перебудову.
func test_fog_clock_advances_fog_time_by_a_tenth_of_a_second() -> void:
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	var m: MapData = load("res://maps/crossroads.tres")
	view.ring_map = m
	view.build(m.to_board())
	var clock: Timer = view.get_node("FogClock")
	assert_eq(clock.wait_time, BoardView.FOG_TICK)
	assert_almost_eq(BoardView.FOG_TICK, 0.1, 1e-6)
	var before: float = BoardView.fog_time
	clock.timeout.emit()
	assert_almost_eq(BoardView.fog_time, before + 0.1, 1e-5)
	view.build(m.to_board())
	assert_same(view.get_node("FogClock"), clock, "перебудова дошки годинник не скидає")


## Без кільця імли нема, і годинник після перебудови стоїть: інакше він будив би кадр 10 разів
## на секунду даремно.
func test_fog_clock_pauses_when_the_board_is_rebuilt_without_a_ring() -> void:
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	var m: MapData = load("res://maps/crossroads.tres")
	view.ring_map = m
	view.build(m.to_board())
	var clock: Timer = view.get_node("FogClock")
	assert_false(clock.paused)
	view.ring_map = null
	view.build(m.to_board())
	assert_true(clock.paused, "без кільця годинник стоїть")


## Підірваний міст кільця теж лишає руїни: вони йдуть тим самим мультимешем, але не в перелік
## клітинок руїн дошки, який читають правила й тести дошки.
func test_destroyed_ring_bridge_draws_ruins_outside_the_board_list() -> void:
	var m: MapData = (load("res://maps/river.tres") as MapData).duplicate()
	var tiles: PackedByteArray = m.outer_tiles.duplicate()
	var hit := -1
	for i in tiles.size():
		if tiles[i] == Terrain.Kind.BRIDGE:
			hit = i
			break
	assert_gt(hit, -1, "у кільці River є міст")
	tiles[hit] = Terrain.Kind.BRIDGE_DESTROYED
	m.outer_tiles = tiles
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.ring_map = m
	view.build(m.to_board())
	var ruin: MultiMeshInstance3D = view.get_node_or_null("PlaceholderBridgeRuin")
	assert_not_null(ruin, "руїни кільця намальовані")
	if ruin != null:
		# Дві плити, дві опори й третя плита, що впала: її кидає хеш цієї клітинки.
		assert_eq(ruin.multimesh.instance_count, 5)
	assert_eq(view._placeholder_bridge_ruin_cells.size(), 0, "на дошці руїн нема")


## Множник улоговини в центрі крайньої клітинки — smoothstep(0, 1.5, 0.5) = 7/27, кутової —
## (7/27)²; на самому краю 0, за `_EDGE_HILL_IN` від краю — 1.
func test_edge_hill_dip_has_exact_values_at_cell_centres() -> void:
	var edge: float = 7.0 / 27.0
	assert_almost_eq(TerrainHeight._edge_hill_dip(-0.5, -5.0), edge, 1e-6, "крайня клітинка")
	assert_almost_eq(TerrainHeight._edge_hill_dip(-5.0, -0.5), edge, 1e-6, "крайня клітинка")
	assert_almost_eq(TerrainHeight._edge_hill_dip(-0.5, -0.5), edge * edge, 1e-6, "кутова клітинка")
	assert_eq(TerrainHeight._edge_hill_dip(0.0, -5.0), 0.0, "на краю")
	assert_eq(TerrainHeight._edge_hill_dip(-1.5, -5.0), 1.0, "за 1.5 клітинки від краю")


## Пагорб, що перетинає край дошки, сходить на краю до 0 улоговиною, але клітинка HILL лишається
## пагорбом. Центр крайньої клітинки піднято щонайменше на 7/27 від `_HILL_KEEP` найменшої
## висоти пагорба (0.56 м) і, на Ridge, на 0.65 м: найнижча крайня клітинка (23, 0) має 0.68 м.
## Решта клітинок тримає `_HILL_KEEP` повністю. Кутових клітинок пагорба на Ridge нема.
func test_ring_world_keeps_every_board_hill_cell_raised() -> void:
	var w: Array = _world("res://maps/ridge.tres")
	var m: MapData = w[0]
	var b: Board = w[1]
	var world: Board = w[2]
	var t: TerrainHeight = w[3]
	var flat := Board.create(world.width, world.height, world.ground_state)
	for i in world.tiles.size():
		var k: int = world.tiles[i]
		flat.tiles[i] = Terrain.Kind.FIELD if k == Terrain.Kind.HILL else k
	var f := TerrainHeight.bake(flat, 0, m.name_key.hash(), Surroundings.world_surface(m),
			Surroundings.ring_of(m))
	var floor_h: float = TerrainHeight._HILL_KEEP * TerrainHeight._HILL_MIN
	# Допуск 8 мм: центр клітинки лежить між відліками, і білінійна інтерполяція зрізає вершину.
	var tol: float = 0.008 * M
	var edge_cells := 0
	for z in b.height:
		for x in b.width:
			if b.kind_at(Vector2i(x, z)) != Terrain.Kind.HILL:
				continue
			var rise: float = t.at(float(x), float(z)) - f.at(float(x), float(z))
			var on_edge: bool = x == 0 or z == 0 or x == b.width - 1 or z == b.height - 1
			assert_false(on_edge and (x == 0 or x == b.width - 1) and (z == 0 or z == b.height - 1),
					"(%d, %d): кутова клітинка пагорба" % [x, z])
			if on_edge:
				edge_cells += 1
				assert_gt(rise, 7.0 / 27.0 * floor_h - tol, "(%d, %d): %.2f м" % [x, z, rise / M])
				assert_gt(rise, 0.65 * M, "(%d, %d): %.2f м" % [x, z, rise / M])
			else:
				assert_gt(rise, floor_h - tol, "(%d, %d): %.2f м" % [x, z, rise / M])
	assert_gt(edge_cells, 0, "на Ridge пагорб перетинає край")


## Настил — лише на мостах дошки: плита впоперек русла кільця під напівзакритою імлою
## обриває річку прямою, і за нею вода читається окремим шматком.
func test_ring_bridge_lays_no_deck_across_the_river() -> void:
	var m: MapData = load("res://maps/river.tres")
	var b: Board = m.to_board()
	var on_board := 0
	for k: int in b.tiles:
		on_board += 1 if k == Terrain.Kind.BRIDGE else 0
	assert_true(m.outer_tiles.has(Terrain.Kind.BRIDGE), "у кільці River є міст")
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.ring_map = m
	view.build(b)
	var deck: MultiMeshInstance3D = view.get_node("PlaceholderBridgeDeck")
	assert_eq(deck.multimesh.instance_count, on_board, "настил — лише на клітинках дошки")


## Коліно русла завширшки в клітинку: розмиття тут не додає води зовсім, а замикання заповнює
## внутрішній кут суші, не чіпаючи вузлів води й не підходячи до зовнішнього кута й далекої суші.
func test_ring_closing_fills_the_inner_land_corner_of_a_narrow_bend() -> void:
	var n := 20
	var step := 0.25
	var dc := PackedFloat32Array()
	dc.resize(n * n)
	for j in n:
		for i in n:
			var wet: bool = (j >= 8 and j <= 11 and i >= 8) or (i >= 8 and i <= 11 and j >= 8)
			dc[j * n + i] = -0.3 if wet else 1.0
	var c: PackedFloat32Array = TerrainHeight.new()._closing(dc, n, n, step, 0.8)
	for k in dc.size():
		if dc[k] < 0.0:
			assert_eq(c[k], dc[k], "вузол води лишається своїм")
	assert_lt(c[12 * n + 12], 0.0, "внутрішній кут суші заповнено")
	assert_gt(c[7 * n + 7], 0.0, "зовнішній кут коліна сухий")
	assert_gt(c[0], 0.0, "далека суша суха")


## За краєм поля замикання бачить сушу: берег між водою й краєм світу, вужчий за 2r, не
## заливається до самого краю.
func test_ring_closing_leaves_the_shore_at_the_field_edge_dry() -> void:
	var n := 20
	var dc := PackedFloat32Array()
	dc.resize(n * n)
	for j in n:
		for i in n:
			dc[j * n + i] = -0.3 if j >= 3 and j <= 6 else 1.0
	var c: PackedFloat32Array = TerrainHeight.new()._closing(dc, n, n, 0.25, 0.8)
	for i in n:
		assert_gt(c[i], 0.0, "вузол (%d, 0) на краю поля сухий" % i)
		assert_gt(c[n + i], 0.0, "вузол (%d, 1) біля краю поля сухий" % i)


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
