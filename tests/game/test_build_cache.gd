extends GutTest
## Дисковий кеш побудови дошки: ті самі вхідні дані дають ті самі байти, що й обчислення без кешу.

const TAG: String = "test_build_cache"


const TEST_DIR: String = "user://build_cache_test"
var _saved_dir: String = ""


## Свій каталог кешу, чистий на кожен тест: тести не читають справжній і не залежать від попередніх запусків.
func before_each() -> void:
	_saved_dir = BuildCache.dir
	BuildCache.dir = TEST_DIR
	_clear()


func after_each() -> void:
	_clear()
	BuildCache.dir = _saved_dir


func _clear() -> void:
	for name in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute("%s/%s" % [TEST_DIR, name])


func _files(prefix: String) -> int:
	var n := 0
	for name in DirAccess.get_files_at(TEST_DIR):
		if name.begins_with(prefix) and name.ends_with(".bin"):
			n += 1
	return n


func test_key_follows_the_inputs() -> void:
	var a: String = BuildCache.key([1, "x", PackedByteArray([1, 2])], [])
	assert_eq(a, BuildCache.key([1, "x", PackedByteArray([1, 2])], []))
	assert_ne(a, BuildCache.key([2, "x", PackedByteArray([1, 2])], []))
	assert_ne(a, BuildCache.key([1, "x", PackedByteArray([1, 3])], []))
	assert_ne(a, BuildCache.key([1, "x", PackedByteArray([1, 2])], ["res://game/battle/footpaths.gd"]))


func test_miss_is_null_and_hit_returns_the_stored_value() -> void:
	var k: String = BuildCache.key(["roundtrip"], [])
	assert_null(BuildCache.fetch(TAG, k))
	var value: Dictionary = {"cells": [Vector2i(1, 2)], "h": PackedFloat32Array([0.5, 1.25]), "n": 0.1}
	BuildCache.store(TAG, k, value)
	assert_eq(BuildCache.fetch(TAG, k), value)


func test_old_files_of_a_tag_are_pruned() -> void:
	for i in BuildCache.KEEP_PER_TAG + 3:
		BuildCache.store(TAG, BuildCache.key([i], []), i)
	var left := 0
	for name in DirAccess.get_files_at(TEST_DIR):
		if name.begins_with(TAG):
			left += 1
	assert_eq(left, BuildCache.KEEP_PER_TAG)


func test_footpaths_from_cache_match_a_fresh_bake_with_dry() -> void:
	var pts: PackedVector2Array = Footpaths.meander(Vector2(2, 5), Vector2(11, 5), 0.1, 1.2, 5)
	var hw := PackedFloat32Array()
	hw.resize(pts.size())
	hw.fill(0.0375)
	var walks: Array = [{"kind": &"yard", "pts": pts, "half": hw, "seed": 5}]
	var patches := PackedVector3Array([Vector3(6, 5, 0.3)])
	var dry := func(p: Vector2) -> bool: return p.x < 7.0
	var size := Vector2i(14, 10)
	var fresh: Image = Footpaths.bake(walks, patches, size, dry)
	var first: Image = Footpaths.bake(walks, patches, size, dry, true)
	var second: Image = Footpaths.bake(walks, patches, size, dry, true)
	assert_eq(first.get_data(), fresh.get_data())
	assert_eq(second.get_data(), fresh.get_data())
	assert_eq(_files("footpaths_"), 1, "перший виклик записав кеш, другий узяв з нього")


func test_height_from_cache_equals_a_fresh_bake() -> void:
	var m: MapData = load("res://maps/crossroads.tres")
	var board: Board = m.to_board()
	var seed_value: int = m.name_key.hash()
	var fresh := TerrainHeight.bake(board, 0, seed_value, m.surface)
	var first := TerrainHeight.bake(board, 0, seed_value, m.surface, 0, true)
	var second := TerrainHeight.bake(board, 0, seed_value, m.surface, 0, true)
	assert_eq(var_to_bytes(first._to_cache()), var_to_bytes(fresh._to_cache()))
	assert_eq(var_to_bytes(second._to_cache()), var_to_bytes(fresh._to_cache()))
	assert_eq(second.at(10.3, 7.7), fresh.at(10.3, 7.7))
	assert_not_null(second.roads, "дорога в зліпку")
	assert_eq(second.roads.d_grid(), fresh.roads.d_grid())
	assert_eq(_files("height_"), 1, "кеш записано один раз")
	assert_not_null(BuildCache.fetch("height", TerrainHeight._cache_key(board, 0, seed_value, m.surface, 0)), "другий виклик — справжнє влучання")


func test_height_from_cache_keeps_the_river_course() -> void:
	var m: MapData = load("res://maps/river.tres")
	var board: Board = m.to_board()
	var seed_value: int = m.name_key.hash()
	var fresh := TerrainHeight.bake(board, 0, seed_value, m.surface)
	TerrainHeight.bake(board, 0, seed_value, m.surface, 0, true)
	var second := TerrainHeight.bake(board, 0, seed_value, m.surface, 0, true)
	assert_not_null(second.course, "вісь річки в зліпку")
	assert_eq(second.course.lines, fresh.course.lines)
	assert_eq(second.course.axis_lines, fresh.course.axis_lines)
	assert_eq(second.course._warp_x.get_noise_2d(1.5, 2.5), fresh.course._warp_x.get_noise_2d(1.5, 2.5))
	assert_eq(var_to_bytes(second._to_cache()), var_to_bytes(fresh._to_cache()))


func test_height_cache_with_a_ring_equals_a_fresh_bake() -> void:
	var m: MapData = load("res://maps/river.tres")
	var ring: int = Surroundings.ring_of(m)
	assert_gt(ring, 0)
	var world: Board = Surroundings.world_board(m.to_board(), m)
	var surface: PackedByteArray = Surroundings.world_surface(m)
	var seed_value: int = m.name_key.hash()
	var fresh := TerrainHeight.bake(world, 0, seed_value, surface, ring)
	TerrainHeight.bake(world, 0, seed_value, surface, ring, true)
	var second := TerrainHeight.bake(world, 0, seed_value, surface, ring, true)
	assert_eq(_files("height_"), 1)
	assert_eq(var_to_bytes(second._to_cache()), var_to_bytes(fresh._to_cache()))
	assert_eq(second.mesh_quads(), fresh.mesh_quads())
	assert_eq(second.min_height(), fresh.min_height())


## Кожен вхідний параметр бере участь у ключі: випало б одне — інша карта віддала б чужі висоти.
func test_height_key_depends_on_every_input() -> void:
	var m: MapData = load("res://maps/crossroads.tres")
	var board: Board = m.to_board()
	var surface: PackedByteArray = m.surface.duplicate()
	if surface.is_empty():
		surface.resize(board.width * board.height)
	var base: String = TerrainHeight._cache_key(board, 0, 5, surface, 0)
	assert_ne(base, "")
	assert_eq(base, TerrainHeight._cache_key(board, 0, 5, surface, 0))
	var other_surface: PackedByteArray = surface.duplicate()
	other_surface[0] = 1 - other_surface[0]
	assert_ne(base, TerrainHeight._cache_key(board, 0, 5, other_surface, 0), "surface")
	var other_board: Board = Board.create(board.width, board.height, Terrain.GroundState.DRY)
	other_board.tiles = board.tiles.duplicate()
	other_board.tiles[0] = Terrain.Kind.WATER if board.tiles[0] != Terrain.Kind.WATER else Terrain.Kind.FIELD
	assert_ne(base, TerrainHeight._cache_key(other_board, 0, 5, surface, 0), "tiles")
	assert_ne(base, TerrainHeight._cache_key(board, 0, 6, surface, 0), "seed")
	assert_ne(base, TerrainHeight._cache_key(board, 0, 5, surface, 1), "ring")
	assert_ne(base, TerrainHeight._cache_key(board, 1, 5, surface, 0), "margin")


func test_forest_ring_plan_is_cached_and_equal() -> void:
	var board: Board = Board.create(12, 10, Terrain.GroundState.DRY)
	for y in range(2, 8):
		for x in range(2, 10):
			board.tiles[y * board.width + x] = Terrain.Kind.FOREST
	var plans: Array = []
	for i in 2:
		var f := ForestLayer.new()
		add_child_autofree(f)
		f.build(board, PackedByteArray(), 0, Vector2i(board.width, board.height), &"summer", 7)
		plans.append(f.board_plan)
	assert_eq(_files("forest_ring_"), 1, "план кільця записано раз і взято з кешу")
	assert_gt((plans[0] as Array).size(), 0)
	assert_eq(var_to_bytes(plans[0]), var_to_bytes(plans[1]))


## Без коду скриптів (експорт) ключа нема, і кеш нічого не читає й не пише.
func test_missing_script_source_disables_the_cache() -> void:
	assert_eq(BuildCache.key([1], ["res://no_such_script.gd"]), "")
	BuildCache.store(TAG, "", 1)
	assert_eq(_files(TAG), 0)
	assert_null(BuildCache.fetch(TAG, ""))


func test_stray_tmp_files_are_removed_on_store() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open("%s/%s_dead.bin.1.tmp" % [TEST_DIR, TAG], FileAccess.WRITE)
	f.store_8(1)
	f.close()
	BuildCache.store(TAG, BuildCache.key(["a"], []), 1)
	assert_false(FileAccess.file_exists("%s/%s_dead.bin.1.tmp" % [TEST_DIR, TAG]))
	assert_eq(_files(TAG), 1)


func _object_vars(obj: Object) -> Array:
	var out: Array = []
	for p: Dictionary in obj.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(p["type"]) == TYPE_OBJECT:
			out.append(p["name"])
	out.sort()
	return out


## dump_vars мовчки відкидає об'єкти: новий член-об'єкт у цих класах мусить потрапити сюди — і або
## в зліпок (TerrainHeight._to_cache), або в явний список пропущеного.
func test_dump_vars_skips_exactly_the_known_object_members() -> void:
	assert_eq(_object_vars(TerrainHeight.new()), ["_gradient_texture", "_texture", "course", "roads"])
	assert_eq(_object_vars(RoadCourse.new()), [])
	assert_eq(_object_vars(RiverCourse.new()), ["_warp_x", "_warp_x2", "_warp_z", "_warp_z2"])
