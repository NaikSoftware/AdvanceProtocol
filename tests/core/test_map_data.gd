extends GutTest
## Task 2.10: MapData — дані карти, які битва бере на старті. `to_board()`
## переносить тайли й стан ґрунту без жодного власного рішення; `populate()`
## додає юнітів і цілі в уже створений BattleState (§3.10, §6 — карта не
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


func test_populate_adds_neutral_objectives_and_sets_hold_target() -> void:
	var m: MapData = _map()
	m.objectives = [Vector2i(0, 0), Vector2i(3, 2)] as Array[Vector2i]
	m.hold_target = 2
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)

	m.populate(state)

	assert_eq(state.objectives.size(), 2)
	for o in state.objectives:
		assert_eq(o.owner, -1, "§3.10: цілі карти стартують нейтральними — володіння вирішує гра, не карта")
	assert_eq(state.objective_hold_target, 2)


func test_populate_is_additive_not_a_reset_of_existing_state() -> void:
	# populate() наповнює вже створений BattleState (§6: карта не творить сам стан),
	# тож юніт, доданий до виклику populate(), мусить лишитися після нього.
	var m: MapData = _map()
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0}] as Array[Dictionary]
	var state: BattleState = BattleState.create(m.to_board(), 2, 1)
	state.add_unit(9, 1, Vector2i(2, 2), 0)

	m.populate(state)

	assert_eq(state.units.size(), 2, "юніт, доданий до populate(), не мусить зникнути")


# --- Task 2.10, Крок 3: ручна карта skirmish_bridge ------------------------

func test_skirmish_bridge_map_loads_and_populates_a_sane_match() -> void:
	var m: MapData = load("res://maps/skirmish_bridge.tres") as MapData
	assert_not_null(m, "res://maps/skirmish_bridge.tres мусить завантажуватись як MapData")
	assert_eq(m.width, 16)
	assert_eq(m.height, 12)
	assert_eq(m.spawns.size(), 6, "по 3 юніти на кожного з 2 гравців")

	var board: Board = m.to_board()
	# Річка блокує брід поза мостом, а сам міст — прохідний.
	assert_false(board.is_passable(Vector2i(8, 0)), "річка непрохідна поза мостом")
	assert_true(board.is_passable(Vector2i(8, 5)), "міст мусить лишатися прохідним")
	assert_true(board.is_passable(Vector2i(8, 6)), "міст мусить лишатися прохідним")

	var state: BattleState = BattleState.create(board, 2, 1)
	m.populate(state)

	assert_eq(state.units_of(0).size(), 3)
	assert_eq(state.units_of(1).size(), 3)
	for u in state.alive_units():
		assert_true(board.in_bounds(u.pos), "жоден спавн не мусить лежати поза дошкою")
		assert_true(board.is_passable(u.pos), "жоден спавн не мусить стояти на непрохідному тайлі")
