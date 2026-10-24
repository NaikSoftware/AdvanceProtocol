extends GutTest
## Task 2.10: MapData — дані карти, які битва бере на старті. `to_board()`
## переносить тайли й стан ґрунту без жодного власного рішення; `populate()`
## додає юнітів в уже створений BattleState (§6 — карта не
## створює BattleState сама, лише наповнює той, що вже існує).

func _map(width: int = 4, height: int = 3) -> MapData:
	var m := MapData.new()
	m.width = width
	m.height = height
	m.ground_state = Terrain.GroundState.MUD
	var tiles := PackedInt32Array()
	tiles.resize(width * height)
	tiles.fill(Terrain.Kind.FIELD)
	m.tiles = tiles
	return m


func test_to_board_carries_width_height_and_ground_state() -> void:
	var m: MapData = _map(5, 4)

	var board: Board = m.to_board()

	assert_eq(board.width, 5)
	assert_eq(board.height, 4)
	assert_eq(board.ground_state, Terrain.GroundState.MUD)


func test_to_board_carries_tile_kinds_at_the_right_cells() -> void:
	var m: MapData = _map(4, 3)
	# індекс — те саме y*width+x, що й Board._index(), (2,1) -> 1*4+2 = 6
	m.tiles[6] = Terrain.Kind.WATER

	var board: Board = m.to_board()

	assert_eq(board.kind_at(Vector2i(2, 1)), Terrain.Kind.WATER)
	assert_eq(board.kind_at(Vector2i(0, 0)), Terrain.Kind.FIELD, "решта тайлів лишається дефолтом карти")


func test_populate_adds_units_from_spawns_at_declared_positions() -> void:
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 2},
		{"type_id": 11, "owner": 1, "pos": Vector2i(3, 2), "facing": 6},
	] as Array[Dictionary]
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)

	m.populate(state)

	assert_eq(state.units.size(), 2)
	var units: Array[Unit] = state.alive_units()
	var by_owner: Dictionary = {}
	for u in units:
		by_owner[u.owner] = u
	assert_eq(by_owner[0].type_id, 5)
	assert_eq(by_owner[0].pos, Vector2i(1, 1))
	assert_eq(by_owner[0].facing, 2)
	assert_eq(by_owner[1].type_id, 11)
	assert_eq(by_owner[1].pos, Vector2i(3, 2))


func test_populate_rejects_a_map_with_a_spawn_facing_out_of_range() -> void:
	# Так само, як BattleSerializer: зіпсована карта не відкривається частково —
	# жоден юніт не додається, і facing 8 не доходить до Rules.armour_sector().
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 2},
		{"type_id": 11, "owner": 1, "pos": Vector2i(3, 2), "facing": 8},
	] as Array[Dictionary]
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)

	assert_false(m.populate(state), "карта з facing 8 відкидається")
	assert_eq(state.units.size(), 0, "і нічого з неї не додано")


func test_populate_reports_success_for_a_valid_map() -> void:
	var m: MapData = _map()
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 7}] as Array[Dictionary]
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)
	assert_true(m.populate(state))
	assert_eq(state.units.size(), 1)


func test_populate_is_additive_not_a_reset_of_existing_state() -> void:
	# populate() наповнює вже створений BattleState (§6: карта не творить сам стан),
	# тож юніт, доданий до виклику populate(), мусить лишитися після нього.
	var m: MapData = _map()
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0}] as Array[Dictionary]
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)
	state.add_unit(9, 1, Vector2i(2, 2), 0)

	m.populate(state)

	assert_eq(state.units.size(), 2, "юніт, доданий до populate(), не мусить зникнути")


# --- Фаза 5a: поставна карта «Річка» ---------------------------------------

func test_river_map_loads_and_populates_a_sane_match() -> void:
	var m: MapData = load("res://maps/river.tres") as MapData
	assert_not_null(m, "res://maps/river.tres мусить завантажуватись як MapData")
	assert_eq(m.width, 26)
	assert_eq(m.height, 22)
	assert_eq(m.spawns.size(), 12, "по 6 юнітів на кожного з 2 гравців")

	var board: Board = m.to_board()
	# Річка блокує брід поза мостом, а сам міст — прохідний.
	assert_false(board.penalty_at(Vector2i(8, 10)) < Terrain.IMPASSABLE, "річка непрохідна поза мостом")
	assert_true(board.penalty_at(Vector2i(13, 10)) < Terrain.IMPASSABLE, "міст мусить лишатися прохідним")
	assert_true(board.penalty_at(Vector2i(13, 11)) < Terrain.IMPASSABLE, "міст мусить лишатися прохідним")

	var state: BattleState = BattleState.create(board, 2, 1)
	m.populate(state)

	assert_eq(state.units_of(0).size(), 6)
	assert_eq(state.units_of(1).size(), 6)
	for u in state.alive_units():
		assert_true(board.in_bounds(u.pos), "жоден спавн не мусить лежати поза дошкою")
		assert_true(board.penalty_at(u.pos) < Terrain.IMPASSABLE, "жоден спавн не мусить стояти на непрохідному тайлі")


# --- Task 4.12: карта на 3 гравці, зіграна вдвох -----------------------------

func test_populate_skips_spawns_beyond_player_count() -> void:
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(0, 0), "facing": 2},
		{"type_id": 5, "owner": 1, "pos": Vector2i(3, 0), "facing": 6},
		{"type_id": 5, "owner": 2, "pos": Vector2i(1, 2), "facing": 0},
	] as Array[Dictionary]
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)

	assert_true(m.populate(state))

	assert_eq(state.units.size(), 2, "спавн гравця 3 у матчі на двох пропускається")
	for u in state.alive_units():
		assert_lt(u.owner, 2, "жодного юніта з owner >= player_count")



# --- Косметичний підтип: стара карта без нього — усюди підтип 0 ----------------

func test_old_map_without_surface_loads_with_default_subtype_everywhere() -> void:
	var m: MapData = load("res://tests/fixtures/three_player_map.tres") as MapData
	assert_not_null(m)
	assert_eq(m.surface.size(), 0, "фікстура записана до появи surface")
	for y in m.height:
		for x in m.width:
			assert_eq(m.surface_at(Vector2i(x, y)), 0)


func test_to_board_does_not_carry_surface() -> void:
	# Board — усе, що бачать правила; підтипу там бути не може.
	var m: MapData = _map(2, 1)
	m.surface = PackedByteArray([1, 2])
	assert_false("surface" in m.to_board(), "Board не має поля surface")


func test_surface_at_is_zero_outside_the_map_and_never_wraps_rows() -> void:
	var m: MapData = _map(2, 2)
	m.surface = PackedByteArray([0, 0, 1, 2])
	assert_eq(m.surface_at(Vector2i(1, 1)), 2)
	assert_eq(m.surface_at(Vector2i(2, 0)), 0, "x == width не переходить на рядок 1")
	assert_eq(m.surface_at(Vector2i(-1, 1)), 0, "x < 0 не переходить на рядок 0")
	assert_eq(m.surface_at(Vector2i(0, 2)), 0)
	assert_eq(m.surface_at(Vector2i(0, -1)), 0)


func test_surface_variants_per_kind() -> void:
	assert_eq(MapData.surface_variants(Terrain.Kind.ROAD), MapData.RoadSurface.size())
	assert_eq(MapData.surface_variants(Terrain.Kind.FIELD), MapData.FieldSurface.size())
	assert_eq(MapData.surface_variants(Terrain.Kind.FOREST), MapData.ForestSurface.size())
	assert_eq(MapData.surface_variants(Terrain.Kind.WATER), 1, "лише типовий вигляд")


# --- Зовнішнє кільце (рішення власника 2026-10-22): лише пейзаж за краєм дошки ----

## Дошка 2×1 з кільцем 1: розширена сітка 4×3, внутрішній блок — заглушка 255.
func _ringed() -> MapData:
	var m: MapData = _map(2, 1)
	m.tiles = PackedInt32Array([Terrain.Kind.ROAD, Terrain.Kind.HILL])
	m.outer_margin = 1
	var w := Terrain.Kind.WATER
	var t := Terrain.Kind.FOREST
	m.outer_tiles = PackedByteArray([
		t, t, t, w,
		t, 255, 255, w,
		w, w, w, w,
	])
	return m


func test_outer_kind_at_reads_the_board_inside_and_the_ring_outside() -> void:
	var m: MapData = _ringed()
	assert_eq(m.outer_kind_at(Vector2i(0, 0)), Terrain.Kind.ROAD, "усередині — вид самої дошки, не заглушка")
	assert_eq(m.outer_kind_at(Vector2i(1, 0)), Terrain.Kind.HILL)
	assert_eq(m.outer_kind_at(Vector2i(-1, -1)), Terrain.Kind.FOREST, "кут кільця")
	assert_eq(m.outer_kind_at(Vector2i(2, -1)), Terrain.Kind.WATER)
	assert_eq(m.outer_kind_at(Vector2i(-1, 0)), Terrain.Kind.FOREST, "сусід дошки зліва")
	assert_eq(m.outer_kind_at(Vector2i(2, 0)), Terrain.Kind.WATER, "сусід дошки справа")
	assert_eq(m.outer_kind_at(Vector2i(0, 1)), Terrain.Kind.WATER, "сусід дошки знизу")


func test_outer_kind_at_clamps_beyond_the_ring_to_its_nearest_edge() -> void:
	var m: MapData = _ringed()
	assert_eq(m.outer_kind_at(Vector2i(-9, -9)), Terrain.Kind.FOREST)
	assert_eq(m.outer_kind_at(Vector2i(9, -1)), Terrain.Kind.WATER)
	assert_eq(m.outer_kind_at(Vector2i(0, 9)), Terrain.Kind.WATER)


func test_outer_kind_at_without_a_ring_clamps_to_the_board_edge() -> void:
	var m: MapData = _map(2, 1)
	m.tiles = PackedInt32Array([Terrain.Kind.ROAD, Terrain.Kind.HILL])
	assert_eq(m.outer_margin, 0)
	assert_eq(m.outer_kind_at(Vector2i(-5, 3)), Terrain.Kind.ROAD)
	assert_eq(m.outer_kind_at(Vector2i(7, -2)), Terrain.Kind.HILL)


func test_old_map_without_ring_loads_with_margin_zero() -> void:
	var m: MapData = load("res://tests/fixtures/three_player_map.tres") as MapData
	assert_not_null(m)
	assert_eq(m.outer_margin, 0)
	assert_eq(m.outer_tiles.size(), 0)
	assert_eq(m.outer_surface.size(), 0)


func test_to_board_does_not_carry_the_outer_ring() -> void:
	# Кільце — пейзаж: Board (усе, що бачать правила) його не має й розміру не змінює.
	var m: MapData = _ringed()
	var board: Board = m.to_board()
	assert_eq([board.width, board.height], [2, 1])
	assert_false(board.in_bounds(Vector2i(-1, 0)), "у кільце не ступити")
	for field in ["outer_margin", "outer_tiles", "outer_surface"]:
		assert_false(field in board, "Board не має поля %s" % field)
