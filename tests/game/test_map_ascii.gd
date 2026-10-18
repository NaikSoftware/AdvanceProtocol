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
