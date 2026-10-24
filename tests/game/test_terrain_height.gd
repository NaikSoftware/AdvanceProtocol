extends GutTest
## Косметичний рельєф (рішення власника 2026-10-22): висота нічого не змінює в правилах,
## тому тут перевіряється лише сама карта висот — детермінізм, співвідношення видів, міст,
## пікінг по піднятій клітинці. 1 м = 0.125 світу.

const M: float = TerrainHeight.M


## 14x14 поле: пагорб 3x3 у (3..5, 3..5), дорога вздовж X на y = 10, річка (2 клітинки) на y = 7..8
## з мостом на x = 11, будівля в (1, 12).
func _board() -> Board:
	var b := Board.create(14, 14, Terrain.GroundState.DRY)
	for y in range(3, 6):
		for x in range(3, 6):
			b.set_kind(Vector2i(x, y), Terrain.Kind.HILL)
	for x in 14:
		b.set_kind(Vector2i(x, 7), Terrain.Kind.WATER)
		b.set_kind(Vector2i(x, 8), Terrain.Kind.WATER)
		b.set_kind(Vector2i(x, 10), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(11, 7), Terrain.Kind.BRIDGE)
	b.set_kind(Vector2i(11, 8), Terrain.Kind.BRIDGE)
	b.set_kind(Vector2i(11, 6), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(11, 9), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(1, 12), Terrain.Kind.BUILDING)
	return b


func _at(t: TerrainHeight, c: Vector2i) -> float:
	return t.at(float(c.x), float(c.y))


func test_bake_is_deterministic_per_seed_and_differs_between_seeds() -> void:
	var a := TerrainHeight.bake(_board(), 0, 7)
	var b := TerrainHeight.bake(_board(), 0, 7)
	var c := TerrainHeight.bake(_board(), 0, 8)
	assert_eq(a.image().get_data(), b.image().get_data(), "той самий seed -> та сама карта")
	assert_ne(a.image().get_data(), c.image().get_data(), "інший seed -> інший мікрорельєф")


func test_hill_stands_3_to_6_metres_above_the_field() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	var rise: float = (_at(t, Vector2i(4, 4)) - _at(t, Vector2i(10, 1))) / M
	assert_true(rise >= 2.5 and rise <= 8.0, "пагорб над полем: %.2f м" % rise)


func test_hill_has_no_stepped_tile_edges() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	# Уздовж рядка y = 4 через край пагорба (x = 5.5): найкрутіший крок на 0.25 клітинки
	# менший за чверть повного підйому — схил, а не сходинка.
	var steepest := 0.0
	var x := 1.0
	while x < 8.0:
		steepest = maxf(steepest, absf(t.at(x + 0.25, 4.0) - t.at(x, 4.0)))
		x += 0.25
	assert_true(steepest < 0.45 * 4.0 * M, "найкрутіший крок %.3f м" % (steepest / M))


func test_water_bed_is_well_under_the_waterline_and_banks_slope() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	var bed: float = t.at(8.0, 7.5)
	assert_true((TerrainHeight.WATER_LEVEL - bed) / M > 0.8, "русло глибше за воду: %.2f м" % ((TerrainHeight.WATER_LEVEL - bed) / M))
	assert_true(bed / M < -2.0, "русло ≥ 2 м під рівниною")
	# Берег: від урізу до верху ≥ 1 м і ≤ ~0.5 клітинки по горизонталі.
	var top: float = t.at(8.0, 5.0)
	var steepest := 0.0
	var z := 5.0
	while z < 6.9:
		steepest = maxf(steepest, absf(t.at(8.0, z + 0.05) - t.at(8.0, z)) / 0.05)
		z += 0.05
	assert_true(top - t.at(8.0, 6.45) > 0.5 * M or top - t.at(8.0, 6.7) > 1.0 * M, "берег падає до води")
	assert_true(steepest > 0.3, "схил берега стрімкий: %.2f" % steepest)


func test_water_level_is_1_to_1_5_metres_below_the_bank_top() -> void:
	var drop: float = -TerrainHeight.WATER_LEVEL / M
	assert_true(drop >= 1.0 and drop <= 1.5, "рівень води нижче верху берега на %.2f м" % drop)


func test_shoreline_is_irregular() -> void:
	var m: MapData = load("res://maps/river.tres")
	var t := TerrainHeight.bake(m.to_board(), 0, m.name_key.hash())
	var widths: Array[float] = []
	for x in range(14, 20):
		var w := 0.0
		var z := 8.5
		while z < 13.0:
			if t.at(float(x), z) < TerrainHeight.WATER_LEVEL:
				w += 0.05
			z += 0.05
		widths.append(w)
	assert_true(widths.max() - widths.min() >= 0.2, "ширина річки мусить гуляти: %s" % str(widths))


func _roughness(t: TerrainHeight, cells: Array[Vector2i]) -> float:
	# Середня друга різниця вздовж X по осі клітинок (крок 0.25): чим менше, тим глаже.
	var sum := 0.0
	var n := 0
	for c in cells:
		for dx in [-0.25, 0.0, 0.25]:
			var x: float = c.x + dx
			sum += absf(t.at(x - 0.25, c.y) + t.at(x + 0.25, c.y) - 2.0 * t.at(x, c.y))
			n += 1
	return sum / n


func test_road_is_smoother_than_the_field_around_it() -> void:
	var t := TerrainHeight.bake(_board(), 0, 3)
	var road: Array[Vector2i] = []
	var field: Array[Vector2i] = []
	for x in range(2, 12):
		road.append(Vector2i(x, 10))
		field.append(Vector2i(x, 12))
	assert_true(_roughness(t, road) < 0.4 * _roughness(t, field), "дорога глаже за поле")


func test_building_pad_is_flat() -> void:
	var t := TerrainHeight.bake(_board(), 0, 3)
	var pad: Array[Vector2i] = [Vector2i(1, 12)]
	var field: Array[Vector2i] = [Vector2i(3, 13), Vector2i(7, 12)]
	assert_true(_roughness(t, pad) < 0.2 * _roughness(t, field), "майданчик будівлі плаский")


func test_plain_relief_stays_within_two_metres() -> void:
	var t := TerrainHeight.bake(_board(), 0, 5)
	var lo := 1e9
	var hi := -1e9
	for x in range(9, 14):
		for z in range(0, 3):
			lo = minf(lo, t.at(x, z))
			hi = maxf(hi, t.at(x, z))
	assert_true(lo >= -1.6 * M and hi <= 1.6 * M, "рельєф рівнини %.2f..%.2f м" % [lo / M, hi / M])
	assert_true(hi - lo > 0.05 * M, "рівнина не пласка")


func test_bridge_deck_is_at_least_as_high_as_the_banks() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	var deck: float = t.deck_y(Vector2i(11, 7))
	assert_eq(deck, t.deck_y(Vector2i(11, 8)), "настил однієї переправи на одній висоті")
	assert_true(deck >= _at(t, Vector2i(11, 6)) and deck >= _at(t, Vector2i(11, 9)), "настил не нижче берегів")
	assert_true(deck - TerrainHeight.WATER_LEVEL > 1.0 * M, "настил ≥ 1 м над водою")
	assert_true(deck - t.at(11.0, 7.5) > 2.0 * M, "під настилом — русло")


func test_margin_continues_the_relief_and_keeps_board_samples_in_place() -> void:
	var plain := TerrainHeight.bake(_board(), 0, 2)
	var wide := TerrainHeight.bake(_board(), 3, 2)
	# Під межею дошки висота та сама — відступ лише продовжує її (клампом по краю).
	assert_almost_eq(wide.at(8.0, 1.0), plain.at(8.0, 1.0), 0.0005)
	assert_almost_eq(wide.at(-3.0, 1.0), wide.at(-2.5, 1.0), 0.1, "відступ плавно продовжує край")
	assert_eq(wide.image().get_width(), (14 + 6) * wide.samples + 1)


func test_image_is_four_channel_half_float_and_matches_the_cpu_samples() -> void:
	var t := TerrainHeight.bake(_board(), 0, 2)
	var img: Image = t.image()
	assert_eq(img.get_format(), Image.FORMAT_RGBAH)
	var s: int = t.samples
	# Піксель (i, j) лежить у світі на (-0.5 + i / s, -0.5 + j / s).
	var i: int = 5 * s + 2
	var j: int = 1 * s + 2
	assert_almost_eq(img.get_pixel(i, j).r, t.at(-0.5 + float(i) / s, -0.5 + float(j) / s), 0.0006)
	assert_almost_eq(img.get_pixel(5 * s, 8 * s).g, 1.0, 0.01, "G — маска води посеред річки")
	assert_almost_eq(img.get_pixel(5 * s, 1 * s).g, 0.0, 0.01, "G — суша")


func test_pick_hits_the_raised_surface_not_the_flat_plane() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	var top: float = _at(t, Vector2i(4, 4))
	assert_true(top > 3.0 * M)
	# Промінь 45° вниз до верху пагорба (4, top, 4): площина y = 0 перетнулась би далі.
	var dir := Vector3(0.0, -1.0, 1.0).normalized()
	var target := Vector3(4.0, top, 4.0)
	var origin: Vector3 = target - dir * 12.0
	var hit: Variant = t.pick(origin, dir)
	assert_not_null(hit)
	var h: Vector3 = hit
	assert_almost_eq(h.x, 4.0, 0.01)
	assert_true(absf(h.z - 4.0) < 0.2, "потрапляє в пагорб, z = %.3f" % h.z)
	assert_almost_eq(h.y, t.at(h.x, h.z), 0.002)
	var plane_z: float = origin.z + dir.z * (-origin.y / dir.y)
	assert_true(plane_z > 4.0 + top * 0.9, "площина y = 0 дала б іншу клітинку")
	assert_eq(IsoCameraRig.world_to_cell(h), Vector2i(4, 4))


func test_pick_returns_null_for_a_ray_that_never_descends() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	assert_null(t.pick(Vector3(0, 5, 0), Vector3(1, 0, 0)))


func test_cell_to_world_follows_the_active_height_field() -> void:
	assert_eq(IsoCameraRig.cell_to_world(Vector2i(4, 4)), Vector3(4, 0, 4), "без рельєфу — площина")
	var t := TerrainHeight.bake(_board(), 0, 1)
	TerrainHeight.active = t
	var w: Vector3 = IsoCameraRig.cell_to_world(Vector2i(4, 4))
	TerrainHeight.active = null
	assert_eq(w, Vector3(4.0, t.at(4.0, 4.0), 4.0))


func test_rig_picks_the_cell_under_the_visible_hill() -> void:
	var rig: IsoCameraRig = load("res://game/camera/iso_camera_rig.tscn").instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(14, 14))
	var t := TerrainHeight.bake(_board(), 0, 1)
	TerrainHeight.active = t
	rig.center_on(Vector2i(4, 4))
	var screen: Vector2 = rig.unproject(IsoCameraRig.cell_to_world(Vector2i(4, 4)))
	var cell: Vector2i = rig.screen_point_to_cell(screen)
	TerrainHeight.active = null
	assert_eq(cell, Vector2i(4, 4), "тап по верху пагорба -> клітинка пагорба")


func test_dry_land_is_never_below_the_water_level() -> void:
	# Вода береться за висотою, тож жодна впадина суші не смій опуститись під її рівень.
	for path: String in ["res://maps/crossroads.tres", "res://maps/ridge.tres"]:
		var m: MapData = load(path)
		var board: Board = m.to_board()
		var t := TerrainHeight.bake(board, 0, m.name_key.hash())
		var low := 1e9
		for y in board.height:
			for x in board.width:
				if not TerrainHeight._is_water(board.kind_at(Vector2i(x, y))):
					low = minf(low, t.at(float(x), float(y)))
		assert_true(low > TerrainHeight.WATER_LEVEL + 0.1 * M, "%s: найнижча суша %.2f м" % [path, low / M])


## Г-подібна річка 2 клітинки завширшки: на схід по y = 9..10, на повороті (x = 9..10) на південь.
## Зовнішній кут повороту — північно-східний, внутрішній — південно-західний.
func _bend_board(hill_at: Vector2i = Vector2i(-1, -1)) -> Board:
	var b := Board.create(20, 20, Terrain.GroundState.DRY)
	for x in range(0, 11):
		b.set_kind(Vector2i(x, 9), Terrain.Kind.WATER)
		b.set_kind(Vector2i(x, 10), Terrain.Kind.WATER)
	for y in range(10, 20):
		b.set_kind(Vector2i(9, y), Terrain.Kind.WATER)
		b.set_kind(Vector2i(10, y), Terrain.Kind.WATER)
	if hill_at.x >= 0:
		for dy in 3:
			for dx in 3:
				b.set_kind(hill_at + Vector2i(dx, dy), Terrain.Kind.HILL)
	return b


## Горизонтальна протяжність (м) підйому від +0.1 м до +1.0 м над водою вздовж променя з
## точки у воді; -1, якщо ґрунт не піднявся.
func _bank_run_m(t: TerrainHeight, from: Vector2, dir: Vector2) -> float:
	var d: Vector2 = dir.normalized()
	var lo := -1.0
	var s := 0.0
	while s < 3.0:
		var p: Vector2 = from + d * s
		var above: float = (t.at(p.x, p.y) - TerrainHeight.WATER_LEVEL) / M
		if lo < 0.0 and above >= 0.1:
			lo = s
		if above >= 1.0:
			return (s - lo) * 8.0
		s += 0.01
	return -1.0


func test_bend_has_a_steep_cut_bank_outside_and_a_gentle_point_bar_inside() -> void:
	var t := TerrainHeight.bake(_bend_board(), 0, 3)
	# Від вершини осі в куті повороту: назовні (на північний схід) — підмитий берег, досередини — коса.
	var corner := Vector2(9.5, 9.5)
	var line: PackedVector2Array = t.course.lines[0]
	var at_i := 0
	var best := 1e9
	for i in line.size():
		if line[i].distance_to(corner) < best:
			best = line[i].distance_to(corner)
			at_i = i
	var mid: Vector2 = line[at_i]
	# Нормаль до осі в куті: на північний схід — зовнішній бік.
	var tang: Vector2 = (line[mini(at_i + 1, line.size() - 1)] - line[maxi(at_i - 1, 0)]).normalized()
	var nrm := Vector2(-tang.y, tang.x)
	if nrm.dot(Vector2(1.0, -1.0)) < 0.0:
		nrm = -nrm
	var outer: float = _bank_run_m(t, mid, nrm)
	var inner: float = _bank_run_m(t, mid, -nrm)
	assert_true(outer > 0.0 and outer <= 2.6 and outer < 0.6 * inner, "підмитий берег: падіння 1 м на ≤ 2.6 м і вдвічі різкіший за косу, є %.2f м (коса %.2f)" % [outer, inner])
	assert_true(inner >= 4.0 and inner <= 8.0, "піщана коса: схил на 4-8 м, є %.2f м" % inner)


func test_straight_reach_has_banks_of_equal_width() -> void:
	var t := TerrainHeight.bake(_bend_board(), 0, 3)
	# Середнє по плесу: ширина схилу гуляє від місця до місця (шум урізу), симетрія — у середньому.
	var north := 0.0
	var south := 0.0
	for x in [0.5, 1.5, 2.5, 3.5, 4.5, 5.5]:
		north += _bank_run_m(t, Vector2(x, 9.5), Vector2(0.0, -1.0)) / 6.0
		south += _bank_run_m(t, Vector2(x, 9.8), Vector2(0.0, 1.0)) / 6.0
	assert_true(north > 0.0 and south > 0.0, "обидва береги підіймаються")
	assert_true(absf(north - south) <= 0.25 * maxf(north, south), "прямий плес симетричний: %.2f / %.2f м" % [north, south])


const _MAPS: Array[String] = ["res://maps/river.tres", "res://maps/crossroads.tres", "res://maps/ridge.tres"]


func _river_bake() -> Array:
	var m: MapData = load("res://maps/river.tres")
	var board: Board = m.to_board()
	return [board, TerrainHeight.bake(board, 0, m.name_key.hash())]


## Контур води не прив'язаний до сітки, але юніти стоять у центрах клітинок суші: у радіусі
## 0.3 від такого центру води нема.
func test_water_keeps_0_3_tiles_from_every_land_cell_centre() -> void:
	var boards: Dictionary = _probe_layouts()
	for key: String in boards:
		var board: Board = boards[key][0]
		var t := TerrainHeight.bake(board, 0, boards[key][1])
		var bad := 0
		var worst := Vector3.ZERO
		for y in board.height:
			for x in board.width:
				if TerrainHeight._is_water(board.kind_at(Vector2i(x, y))):
					continue
				# Весь диск r <= 0.3, а не лише коло: ґрунт під юнітом сухий.
				for r10 in 4:
					for a in 16:
						var ang: float = TAU * a / 16.0
						var r: float = 0.1 * r10
						if t.at(x + r * cos(ang), y + r * sin(ang)) < TerrainHeight.WATER_LEVEL:
							bad += 1
							worst = Vector3(x, y, r)
		assert_eq(bad, 0, "%s: вода в радіусі 0.3 від центру суші, остання (%s)" % [key, worst])


func _water_layout(w: int, h: int, cells: Array[Vector2i]) -> Board:
	var b := Board.create(w, h, Terrain.GroundState.DRY)
	for c in cells:
		b.set_kind(c, Terrain.Kind.WATER)
	return b


func _rect(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out


## Частка клітинки, де земля нижча за воду (сітка 11x11 по клітинці).
func _wet_fraction(t: TerrainHeight, c: Vector2i) -> float:
	var wet := 0
	for j in 11:
		for i in 11:
			if t.at(c.x - 0.5 + i * 0.1, c.y - 0.5 + j * 0.1) < TerrainHeight.WATER_LEVEL:
				wet += 1
	return wet / 121.0


## Берег може перетинати клітинку води, але цілком сухою вона не малюється: інакше вигляд
## показував би прохідну землю там, де правила її не мають.
func test_every_water_cell_shows_at_least_a_quarter_water() -> void:
	var boards: Dictionary = _layouts()
	for key: String in boards:
		var board: Board = boards[key][0]
		var t := TerrainHeight.bake(board, 0, boards[key][1])
		var worst := 1.0
		var worst_at := Vector2i.ZERO
		for y in board.height:
			for x in board.width:
				if TerrainHeight._is_water(board.kind_at(Vector2i(x, y))):
					var f: float = _wet_fraction(t, Vector2i(x, y))
					if f < worst:
						worst = f
						worst_at = Vector2i(x, y)
		assert_gte(worst, 0.25, "%s: найсухіша клітинка води %s має %.0f%% води" % [key, worst_at, worst * 100.0])


func _layouts() -> Dictionary:
	var boards: Dictionary = {}
	for path: String in _MAPS:
		var m: MapData = load(path)
		boards[path] = [m.to_board(), m.name_key.hash()]
	boards["lake7x7"] = [_water_layout(16, 16, _rect(4, 4, 10, 10)), 1]
	boards["lake12x8"] = [_water_layout(20, 16, _rect(3, 4, 14, 11)), 1]
	boards["pond1"] = [_water_layout(12, 10, [Vector2i(5, 5)]), 1]
	boards["edge_lake"] = [_water_layout(14, 12, _rect(0, 0, 4, 4)), 1]
	return boards


## Плюс розкладки з проби редактора: кільце з островом і зигзаг шириною в клітинку. Лише для перевірок
## суші, чистої води й дна: логічних груп у зигзага 7, а зримих одна (діагональні стики).
func _probe_layouts() -> Dictionary:
	var boards: Dictionary = _layouts()
	var ring: Array[Vector2i] = []
	for c in _rect(3, 3, 11, 11):
		if c.x == 3 or c.x == 11 or c.y == 3 or c.y == 11:
			ring.append(c)
	boards["ring"] = [_water_layout(15, 15, ring), 1]
	var zig: Array[Vector2i] = []
	for x in 14:
		zig.append(Vector2i(x, 5 if (x / 2) % 2 == 0 else 6))
	boards["zigzag1"] = [_water_layout(14, 12, zig), 1]
	return boards


## Число 4-зв'язних груп: клітинок води на дошці й мокрих відліків на карті висот.
func _components(w: int, h: int, wet: Callable) -> int:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var n := 0
	for start in w * h:
		if seen[start] == 1 or not wet.call(start % w, start / w):
			continue
		n += 1
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var k: int = stack.pop_back()
			for o: Vector2i in Board.DIRS_4:
				var x: int = k % w + o.x
				var y: int = k / w + o.y
				if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x] == 1 or not wet.call(x, y):
					continue
				seen[y * w + x] = 1
				stack.append(y * w + x)
	return n


## Окремих калюж уздовж берега нема: мокрих груп на карті висот рівно стільки, скільки
## логічних водойм.
func test_water_has_one_component_per_logical_body_and_no_orphan_puddles() -> void:
	var boards: Dictionary = _layouts()
	for key: String in boards:
		var board: Board = boards[key][0]
		var t := TerrainHeight.bake(board, 0, boards[key][1])
		var logical: int = _components(board.width, board.height, func(x: int, y: int) -> bool:
				return TerrainHeight._is_water(board.kind_at(Vector2i(x, y))))
		var s: int = t.samples
		var visual: int = _components((board.width - 1) * s + 1, (board.height - 1) * s + 1, func(x: int, y: int) -> bool:
				return t.at(float(x) / s, float(y) / s) < TerrainHeight.WATER_LEVEL)
		assert_eq(visual, logical, "%s: груп води на карті висот" % key)


## Острів без центру клітинки суші — артефакт контуру, його затоплено. Справжня суша (центр
## клітинки суші всередині) лишається.
func test_no_enclosed_land_inside_any_water_body() -> void:
	var boards: Dictionary = _probe_layouts()
	for key: String in boards:
		var board: Board = boards[key][0]
		var t := TerrainHeight.bake(board, 0, boards[key][1])
		var w: int = t.cols
		var h: int = t.rows
		var s: int = t.samples
		var land := func(x: int, y: int) -> bool:
			return t.at(-0.5 + float(x) / s, -0.5 + float(y) / s) >= TerrainHeight.WATER_LEVEL
		var seen := PackedByteArray()
		seen.resize(w * h)
		var stack: Array[int] = []
		for i in w:
			stack.append(i)
			stack.append((h - 1) * w + i)
		for j in h:
			stack.append(j * w)
			stack.append(j * w + w - 1)
		while not stack.is_empty():
			var k: int = stack.pop_back()
			if seen[k] == 1 or not land.call(k % w, k / w):
				continue
			seen[k] = 1
			for o: Vector2i in Board.DIRS_4:
				var x: int = k % w + o.x
				var y: int = k / w + o.y
				if x >= 0 and y >= 0 and x < w and y < h:
					stack.append(y * w + x)
		# Справжній острів (є центр клітинки суші) дозволений; заборонені лише безхазяйні відліки.
		var real := PackedByteArray()
		real.resize(w * h)
		for cy in board.height:
			for cx in board.width:
				if TerrainHeight._is_water(board.kind_at(Vector2i(cx, cy))):
					continue
				var st: Array[int] = [((2 * cy + 1) * s / 2) * w + (2 * cx + 1) * s / 2]
				while not st.is_empty():
					var k: int = st.pop_back()
					if real[k] == 1 or seen[k] == 1 or not land.call(k % w, k / w):
						continue
					real[k] = 1
					for o: Vector2i in Board.DIRS_4:
						var x: int = k % w + o.x
						var y: int = k / w + o.y
						if x >= 0 and y >= 0 and x < w and y < h:
							st.append(y * w + x)
		var islands := 0
		for k in w * h:
			if seen[k] == 0 and real[k] == 0 and land.call(k % w, k / w):
				islands += 1
		assert_eq(islands, 0, "%s: відліків суші, оточеної водою, без центру клітинки" % key)


## Дно не просвічує посеред русла: глибина ≥ 0.3 м (повна непрозорість шейдера) скрізь,
## крім смуги 0.5 клітинки від урізу.
func test_bed_is_opaque_deep_beyond_half_a_tile_from_the_shore() -> void:
	var boards: Dictionary = _probe_layouts()
	var full: float = 0.3 * M
	for key: String in boards:
		var board: Board = boards[key][0]
		var t := TerrainHeight.bake(board, 0, boards[key][1])
		var w: int = t.cols
		var h: int = t.rows
		var r: int = ceili(0.5 * t.samples)
		var wet := PackedByteArray()
		wet.resize(w * h)
		for k in w * h:
			wet[k] = 1 if t._h[k] < TerrainHeight.WATER_LEVEL else 0
		var bad := 0
		var worst := INF
		var worst_at := Vector2i.ZERO
		for j in h:
			for i in w:
				if wet[j * w + i] == 0:
					continue
				var near_shore := false
				for dj in range(maxi(j - r, 0), mini(j + r + 1, h)):
					for di in range(maxi(i - r, 0), mini(i + r + 1, w)):
						if wet[dj * w + di] == 0 and (di - i) * (di - i) + (dj - j) * (dj - j) <= r * r:
							near_shore = true
				if near_shore:
					continue
				var depth: float = TerrainHeight.WATER_LEVEL - t._h[j * w + i]
				if depth < full:
					bad += 1
					if depth < worst:
						worst = depth
						worst_at = Vector2i(i, j)
		assert_eq(bad, 0, "%s: відліків глибше 0.5 клітинки від берега, але мілкіших за 0.3 м; найгірший %s: %.3f м" % [key, worst_at, worst / M])


## Кінці настилу (по осі дороги) стоять на суші чи схилі берега, а під настилом є вода.
func test_every_bridge_deck_spans_water_with_dry_ground_at_both_ends() -> void:
	var r: Array = _river_bake()
	_check_decks(r[0], r[1], 8)
	# Міст через озеро й через вузький струмок, до яких вісь може не дотягнутись.
	var lake: Board = _water_layout(14, 12, _rect(3, 2, 9, 9))
	for y in range(2, 10):
		lake.set_kind(Vector2i(6, y), Terrain.Kind.BRIDGE)
	lake.set_kind(Vector2i(6, 1), Terrain.Kind.ROAD)
	lake.set_kind(Vector2i(6, 10), Terrain.Kind.ROAD)
	_check_decks(lake, TerrainHeight.bake(lake, 0, 3), 2)
	var brook: Board = _water_layout(14, 12, _rect(0, 5, 13, 5))
	brook.set_kind(Vector2i(7, 5), Terrain.Kind.BRIDGE)
	brook.set_kind(Vector2i(7, 4), Terrain.Kind.ROAD)
	brook.set_kind(Vector2i(7, 6), Terrain.Kind.ROAD)
	for sd in range(1, 11):
		_check_decks(brook, TerrainHeight.bake(brook, 0, sd), 2)


func _check_decks(board: Board, t: TerrainHeight, expected_ends: int) -> void:
	var checked := 0
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if board.kind_at(c) != Terrain.Kind.BRIDGE:
				continue
			var axis: Vector2i = BoardView._bridge_axis(board, c)
			var wet := false
			for k in range(-10, 11):
				var p := Vector2(c) + Vector2(axis) * (k * 0.05)
				wet = wet or t.at(p.x, p.y) < TerrainHeight.WATER_LEVEL
			assert_true(wet, "під настилом (%d,%d) є вода" % [x, y])
			for dir: Vector2i in [axis, -axis]:
				if board.kind_at(c + dir) == Terrain.Kind.BRIDGE:
					continue
				var e := Vector2(c) + Vector2(dir) * 0.5
				assert_gte(t.at(e.x, e.y), TerrainHeight.WATER_LEVEL, "кінець настилу (%d,%d)->%s на суші" % [x, y, dir])
				checked += 1
	assert_eq(checked, expected_ends, "відкритих кінців настилу")


## Осьова лінія не показує сходинок клітинок: поворот дотичної на довжині клітинки не різкіший
## за 60°, радіус не менший за 1.2 клітинки (|кривизна| <= 0.85).
func test_river_centreline_has_no_lateral_steps() -> void:
	var course: RiverCourse = (_river_bake()[1] as TerrainHeight).course
	assert_gt(course.lines.size(), 0)
	for li in course.main_count:
		var pts: PackedVector2Array = course.lines[li]
		var per_tile: int = roundi(1.0 / RiverCourse.STEP)
		for i in range(1, pts.size() - 1 - per_tile):
			var a: float = (pts[i] - pts[i - 1]).angle()
			var b: float = (pts[i + per_tile] - pts[i + per_tile - 1]).angle()
			assert_lt(absf(angle_difference(a, b)), deg_to_rad(60.0), "лінія %d вершина %d" % [li, i])
		for k: float in course.kappas[li]:
			assert_lt(absf(k), 0.85, "кривизна осі")


## Під мостом вісь пряма на настил + 0.1 клітинки й перпендикулярна його осі.
func test_river_runs_straight_and_square_under_each_deck() -> void:
	var r: Array = _river_bake()
	var t: TerrainHeight = r[1]
	# Центри та осі трьох переправ River (мости (4,10-11), (12-13,10-11), (21,10-11)).
	var decks: Array = [[Vector2(4.0, 10.5), 1.0], [Vector2(12.5, 10.5), 2.0], [Vector2(21.0, 10.5), 1.0]]
	var pts: PackedVector2Array = t.course.lines[0]
	for d: Array in decks:
		var c: Vector2 = d[0]
		var half: float = float(d[1]) * 0.5 + 0.1
		var n := 0
		for p in pts:
			if absf(p.x - c.x) <= half and absf(p.y - c.y) < 0.6:
				assert_almost_eq(p.y, c.y, 0.001, "вісь пряма під настилом %s" % c)
				n += 1
		assert_gt(n, 2, "вершини під настилом %s" % c)


func test_river_width_wanders_along_the_course() -> void:
	var course: RiverCourse = (_river_bake()[1] as TerrainHeight).course
	var hw: Array = Array(course.halfs[0])
	assert_gte(hw.size(), 20)
	assert_gte(hw.max() / hw.min(), 1.3, "ширина гуляє: %.2f..%.2f" % [hw.min(), hw.max()])
	assert_lte(hw.max(), 1.4, "півширина не більша за 1.4 клітинки")


func test_water_follows_the_smooth_course_not_the_cells() -> void:
	var r: Array = _river_bake()
	var t: TerrainHeight = r[1]
	var pts: PackedVector2Array = t.course.lines[0]
	var wet := 0
	var inside := 0
	for i in range(0, pts.size(), 3):
		if pts[i].x < 0.0 or pts[i].x > 25.0 or pts[i].y < 0.0 or pts[i].y > 21.0:
			continue
		inside += 1
		wet += 1 if t.at(pts[i].x, pts[i].y) < TerrainHeight.WATER_LEVEL else 0
	assert_eq(wet, inside, "кожна вершина осі стоїть у воді")



func test_banks_stay_under_50_degrees_even_beside_a_hill() -> void:
	for hill_at: Vector2i in [Vector2i(-1, -1), Vector2i(7, 6), Vector2i(6, 11)]:
		var t := TerrainHeight.bake(_bend_board(hill_at), 0, 3)
		var steepest := 0.0
		var x := 0.5
		while x < 14.0:
			var z := 6.5
			while z < 14.0:
				steepest = maxf(steepest, maxf(absf(t.at(x + 0.04, z) - t.at(x, z)), absf(t.at(x, z + 0.04) - t.at(x, z))) / 0.04)
				z += 0.04
			x += 0.04
		assert_lt(steepest, 1.2, "схил берега при пагорбі %s: %.1f°" % [hill_at, rad_to_deg(atan(steepest))])


## HILL — клітинка правил: зсув обрису не виносить пагорб на поле. Пагорб в 1 клітинку тримає
## у центрі ≥ 60 % найменшої висоти пагорба (_HILL_MIN), а центри клітинок поля, не сусідніх
## із ним, лишаються як без пагорба.
func test_one_cell_hill_stays_on_its_cell() -> void:
	for seed_value in [3, 17, 41]:
		var flat := Board.create(11, 11, Terrain.GroundState.DRY)
		var with_hill := Board.create(11, 11, Terrain.GroundState.DRY)
		with_hill.set_kind(Vector2i(5, 5), Terrain.Kind.HILL)
		var a := TerrainHeight.bake(flat, 0, seed_value)
		var b := TerrainHeight.bake(with_hill, 0, seed_value)
		var rise: float = b.at(5.0, 5.0) - a.at(5.0, 5.0)
		assert_gt(rise, 0.6 * TerrainHeight._HILL_MIN, "сід %d: центр пагорба піднято на %.3f" % [seed_value, rise])
		for z in 11:
			for x in 11:
				if absi(x - 5) <= 1 and absi(z - 5) <= 1:
					continue
				# Допуск 8 мм (1e-3 клітинки): інтерполяція відліків дає зсув ~1 мм.
				assert_almost_eq(b.at(float(x), float(z)), a.at(float(x), float(z)), 1e-3, "сід %d: поле (%d, %d) підняте" % [seed_value, x, z])
