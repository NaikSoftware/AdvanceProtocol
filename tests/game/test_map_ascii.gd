extends GutTest
## Task 5a.1: ASCII-формат карт → MapData. Карти пишуться текстом, тож помилку
## формату (рваний рядок, невідомий символ) конвертер має відсікти, а не мовчки з'їсти.


func test_parse_reads_size_tiles_ground_and_name() -> void:
	var m: MapData = MapAscii.parse("name_key=map_x\nground=MUD\ntiles:\n=.T\nw~B\nspawns:\n")
	assert_not_null(m)
	assert_eq(m.width, 3)
	assert_eq(m.height, 2)
	assert_eq(m.ground_state, Terrain.GroundState.MUD)
	assert_eq(m.name_key, "map_x")
	var want: Array[int] = [Terrain.Kind.ROAD, Terrain.Kind.FIELD, Terrain.Kind.FOREST,
		Terrain.Kind.WATER, Terrain.Kind.MARSH, Terrain.Kind.BUILDING]
	assert_eq(Array(m.tiles), want)


func test_parse_mirrors_player0_spawns_for_player1() -> void:
	var m: MapData = MapAscii.parse(
		"name_key=map_x # c\nground=DRY\ntiles:\n....\n....\n....\nspawns:\n# коментар\n2 0 2 0 # ряд\n")
	assert_not_null(m)
	assert_eq(m.spawns.size(), 2)
	assert_eq(m.spawns[0], {"type_id": 2, "owner": 0, "pos": Vector2i(0, 2), "facing": 0})
	assert_eq(m.spawns[1], {"type_id": 2, "owner": 1, "pos": Vector2i(3, 0), "facing": 4})


func test_parse_rejects_ragged_rows_and_unknown_chars() -> void:
	var head := "name_key=map_x\nground=DRY\ntiles:\n"
	assert_null(MapAscii.parse(head + "...\n..\nspawns:\n"))
	assert_null(MapAscii.parse(head + "...\n.Q.\nspawns:\n"))
	assert_push_error_count(2)



# --- Косметичний підтип тайла: лише вигляд, правила його не читають ---

const _HEAD: String = "name_key=map_x\nground=DRY\ntiles:\n=.T\n=.T\n"


func test_parse_surface_section_gives_per_cell_subtypes() -> void:
	var m: MapData = MapAscii.parse(_HEAD + "surface:\n1.2\n011\nspawns:\n")
	assert_not_null(m)
	if m == null:
		return
	var want: Array[int] = [Terrain.Kind.ROAD, Terrain.Kind.FIELD, Terrain.Kind.FOREST,
		Terrain.Kind.ROAD, Terrain.Kind.FIELD, Terrain.Kind.FOREST]
	assert_eq(Array(m.tiles), want, "підтип не змінює виду тайла")
	assert_eq(Array(m.surface), [1, 0, 2, 0, 1, 1], "'.' — нуль, решта — цифра")
	assert_eq(m.surface_at(Vector2i(0, 0)), MapData.RoadSurface.DIRT)
	assert_eq(m.surface_at(Vector2i(1, 1)), MapData.FieldSurface.PLOUGHED)
	assert_eq(m.surface_at(Vector2i(2, 1)), MapData.ForestSurface.PINE)


func test_parse_without_surface_section_leaves_it_empty() -> void:
	var m: MapData = MapAscii.parse(_HEAD + "spawns:\n")
	assert_not_null(m)
	assert_eq(m.surface.size(), 0)
	assert_eq(m.surface_at(Vector2i(0, 0)), 0)


func test_parse_rejects_surface_grid_of_wrong_size_or_bad_char() -> void:
	assert_null(MapAscii.parse(_HEAD + "surface:\n...\nspawns:\n"), "рядків менше, ніж у tiles")
	assert_null(MapAscii.parse(_HEAD + "surface:\n...\n..\nspawns:\n"), "рваний рядок")
	assert_null(MapAscii.parse(_HEAD + "surface:\n...\n.x.\nspawns:\n"), "не цифра")
	assert_push_error_count(3)


func test_parse_rejects_surface_on_a_kind_without_variants_or_out_of_its_range() -> void:
	# _HEAD: стовпці ROAD, FIELD, FOREST — варіантів 3, 2 і 3.
	assert_null(MapAscii.parse(_HEAD + "surface:\n3..\n...\nspawns:\n"), "ROAD 3 поза RoadSurface")
	assert_null(MapAscii.parse(_HEAD + "surface:\n.2.\n...\nspawns:\n"), "FIELD 2 поза FieldSurface — стерні нема")
	assert_null(MapAscii.parse(_HEAD + "surface:\n..3\n...\nspawns:\n"), "FOREST 3 поза ForestSurface")
	assert_null(MapAscii.parse("name_key=map_x\nground=DRY\ntiles:\nw\nsurface:\n1\nspawns:\n"),
		"у води варіантів немає")
	assert_push_error_count(4)
	assert_not_null(MapAscii.parse("name_key=map_x\nground=DRY\ntiles:\nw\nsurface:\n0\nspawns:\n"),
		"нуль дозволений на будь-якому виді")


func test_move_cost_ignores_surface() -> void:
	# Сторож: підтип косметичний — ціна входу на ґрунтовку, бруківку, ріллю чи бір
	# мусить дорівнювати ціні того самого виду з підтипом 0, за будь-якого ґрунту.
	for ground: String in Terrain.GroundState.keys():
		var m: MapData = MapAscii.parse(
			"name_key=map_x\nground=%s\ntiles:\n===..TT\nsurface:\n.12.1.1\nspawns:\n" % ground)
		assert_not_null(m)
		if m == null:
			return
		var board: Board = m.to_board()
		for type_id in UnitTypes.count():
			var u := Unit.create(0, type_id, 0, Vector2i(0, 0), 0)
			for pair: Array in [[0, 1], [0, 2], [3, 4], [5, 6]]:
				assert_eq(Rules.entry_cost_at(u, board, Vector2i(pair[1], 0)),
					Rules.entry_cost_at(u, board, Vector2i(pair[0], 0)),
					"тип %d, ґрунт %s, клітинки %s" % [type_id, ground, pair])


# --- Зовнішнє кільце: пейзаж за краєм, правила його не читають ---

## Дошка 2×1 (=.), кільце 1 → сітка 4×3; дошку пишуть один раз, у кільці на її місці '#'.
const _RING_HEAD: String = "name_key=map_x\nground=DRY\nouter_margin=1\ntiles:\n=.\n"
const _RING: String = "outer:\n=TTw\nT##w\nwwHw\n"


func test_parse_outer_ring_gives_kinds_around_the_board() -> void:
	var m: MapData = MapAscii.parse(_RING_HEAD + _RING + "spawns:\n")
	assert_not_null(m)
	if m == null:
		return
	assert_eq(m.outer_margin, 1)
	assert_eq(m.outer_tiles.size(), 12)
	assert_eq(m.outer_kind_at(Vector2i(-1, -1)), Terrain.Kind.ROAD)
	assert_eq(m.outer_kind_at(Vector2i(0, -1)), Terrain.Kind.FOREST)
	assert_eq(m.outer_kind_at(Vector2i(2, 0)), Terrain.Kind.WATER)
	assert_eq(m.outer_kind_at(Vector2i(1, 1)), Terrain.Kind.BRIDGE)
	assert_eq(m.outer_kind_at(Vector2i(0, 0)), Terrain.Kind.ROAD, "на місці '#' — сама дошка")
	assert_eq(m.outer_kind_at(Vector2i(1, 0)), Terrain.Kind.FIELD)
	assert_eq(m.outer_surface.size(), 0, "без outer_surface: підтип кільця не задано")


func test_parse_without_outer_ring_has_margin_zero() -> void:
	var m: MapData = MapAscii.parse(_HEAD + "spawns:\n")
	assert_not_null(m)
	assert_eq(m.outer_margin, 0)
	assert_eq(m.outer_tiles.size(), 0)


func test_parse_rejects_malformed_outer_ring() -> void:
	var head := "name_key=map_x\nground=DRY\nouter_margin=%s\ntiles:\n=.\n"
	var cases: Dictionary = {
		head % "1" + "spawns:\n": "відступ без сітки outer:",
		"name_key=map_x\nground=DRY\ntiles:\n=.\n" + _RING + "spawns:\n": "outer: без відступу",
		head % "x" + _RING + "spawns:\n": "відступ — не число",
		head % "-1" + _RING + "spawns:\n": "від'ємний відступ",
		head % "2" + _RING + "spawns:\n": "сітка не (w+2m)×(h+2m)",
		_RING_HEAD + "outer:\n=TTw\nT##w\nspawns:\n": "рядків замало",
		_RING_HEAD + "outer:\n=TTw\nT##w\nwwHww\nspawns:\n": "рваний рядок",
		_RING_HEAD + "outer:\n=TTw\nT#.w\nwwHw\nspawns:\n": "дошка в кільці не заглушена '#'",
		_RING_HEAD + "outer:\n=T#w\nT##w\nwwHw\nspawns:\n": "'#' поза місцем дошки",
		_RING_HEAD + "outer:\n=TQw\nT##w\nwwHw\nspawns:\n": "невідомий символ",
	}
	for text: String in cases:
		assert_null(MapAscii.parse(text), cases[text])
	assert_push_error_count(cases.size())


func test_parse_outer_surface_gives_ring_subtypes() -> void:
	# Кільце: (-1,-1) ROAD, (0,-1)/(1,-1)/(-1,0) FOREST.
	var m: MapData = MapAscii.parse(_RING_HEAD + _RING + "outer_surface:\n122.\n1##.\n....\nspawns:\n")
	assert_not_null(m)
	if m == null:
		return
	assert_eq(m.outer_surface.size(), 12)
	assert_eq(m.outer_surface[0], MapData.RoadSurface.DIRT)
	assert_eq(m.outer_surface[1], MapData.ForestSurface.DECIDUOUS)
	assert_eq(m.outer_surface[4], MapData.ForestSurface.PINE)
	assert_eq(m.outer_surface[3], 0)


func test_parse_rejects_malformed_outer_surface() -> void:
	var cases: Dictionary = {
		_RING_HEAD + "outer_surface:\n....\n.##.\n....\nspawns:\n": "outer_surface без outer:",
		_RING_HEAD + _RING + "outer_surface:\n....\n.##.\nspawns:\n": "рядків замало",
		_RING_HEAD + _RING + "outer_surface:\n....\n.##..\n....\nspawns:\n": "рваний рядок",
		_RING_HEAD + _RING + "outer_surface:\n....\n.#..\n....\nspawns:\n": "дошка не заглушена '#'",
		_RING_HEAD + _RING + "outer_surface:\n.#..\n.##.\n....\nspawns:\n": "'#' поза місцем дошки",
		_RING_HEAD + _RING + "outer_surface:\n..x.\n.##.\n....\nspawns:\n": "не цифра",
		_RING_HEAD + _RING + "outer_surface:\n...1\n.##.\n....\nspawns:\n": "у води варіантів немає",
		_RING_HEAD + _RING + "outer_surface:\n3...\n.##.\n....\nspawns:\n": "ROAD 3 поза RoadSurface",
	}
	for text: String in cases:
		assert_null(MapAscii.parse(text), cases[text])
	assert_push_error_count(cases.size())


func test_outer_ring_changes_neither_board_nor_move_cost() -> void:
	# Кільце — косметика. Та сама дошка з кільцем і без
	# дає ту саму Board, а ціна входу на крайову клітинку від кільця не залежить.
	var bare: MapData = MapAscii.parse("name_key=map_x\nground=MUD\ntiles:\n=.\nspawns:\n")
	var ringed: MapData = MapAscii.parse(_RING_HEAD.replace("DRY", "MUD") + _RING + "spawns:\n")
	assert_not_null(bare)
	assert_not_null(ringed)
	if bare == null or ringed == null:
		return
	var a: Board = bare.to_board()
	var b: Board = ringed.to_board()
	assert_eq([b.width, b.height, b.ground_state], [a.width, a.height, a.ground_state])
	assert_eq(Array(b.tiles), Array(a.tiles))
	assert_false(b.in_bounds(Vector2i(-1, 0)), "у кільце не ступити")
	for type_id in UnitTypes.count():
		var u := Unit.create(0, type_id, 0, Vector2i(0, 0), 0)
		for x in 2:
			assert_eq(Rules.entry_cost_at(u, b, Vector2i(x, 0)), Rules.entry_cost_at(u, a, Vector2i(x, 0)),
				"тип %d, клітинка %d" % [type_id, x])
