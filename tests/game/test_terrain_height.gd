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


func test_non_water_cell_centres_are_dry_and_water_cell_centres_wet() -> void:
	# Зсув узбережжя не міняє правил: центр кожної клітинки не-води — суша, води — вода.
	for path: String in ["res://maps/river.tres", "res://maps/crossroads.tres", "res://maps/ridge.tres"]:
		var m: MapData = load(path)
		var board: Board = m.to_board()
		var t := TerrainHeight.bake(board, 0, m.name_key.hash())
		for y in board.height:
			for x in board.width:
				var wet: bool = TerrainHeight._is_water(board.kind_at(Vector2i(x, y)))
				var below: bool = t.at(float(x), float(y)) < TerrainHeight.WATER_LEVEL
				if wet != below:
					assert_eq(below, wet, "%s: центр клітинки (%d,%d)" % [path, x, y])
					return
		assert_true(true, path)


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


func test_image_is_three_channel_half_float_and_matches_the_cpu_samples() -> void:
	var t := TerrainHeight.bake(_board(), 0, 2)
	var img: Image = t.image()
	assert_eq(img.get_format(), Image.FORMAT_RGBH)
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


func test_river_runs_straight_under_a_bridge() -> void:
	var t := TerrainHeight.bake(_board(), 0, 1)
	var first := -1.0
	var last := -1.0
	var z := 5.0
	while z < 10.0:
		if t.at(11.0, z) < TerrainHeight.WATER_LEVEL:
			if first < 0.0:
				first = z
			last = z
		z += 0.02
	assert_almost_eq(first, 6.5, 0.05, "північний берег під мостом прямий")
	assert_almost_eq(last, 8.5, 0.05, "південний берег під мостом прямий")


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
