extends GutTest
## Дисковий кеш побудови дошки: ті самі вхідні дані дають ті самі байти, що й обчислення без кешу.

const TAG: String = "test_build_cache"


func after_each() -> void:
	for name in DirAccess.get_files_at(BuildCache.DIR):
		if name.begins_with(TAG):
			DirAccess.remove_absolute("%s/%s" % [BuildCache.DIR, name])


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
	for name in DirAccess.get_files_at(BuildCache.DIR):
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
	var k: String = BuildCache.key([walks, patches, size], ["res://game/battle/footpaths.gd"])
	DirAccess.remove_absolute("%s/footpaths_%s.bin" % [BuildCache.DIR, k])


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
	var k: String = BuildCache.key([board.width, board.height, board.tiles, 0, seed_value, m.surface, 0, TerrainHeight.undulation_scale], TerrainHeight.CACHE_SCRIPTS)
	DirAccess.remove_absolute("%s/height_%s.bin" % [BuildCache.DIR, k])
