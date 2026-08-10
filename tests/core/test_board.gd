extends GutTest

func _board() -> Board:
	return Board.create(8, 6, Terrain.GroundState.DRY)

func test_bounds() -> void:
	var b: Board = _board()
	assert_true(b.in_bounds(Vector2i(0, 0)))
	assert_true(b.in_bounds(Vector2i(7, 5)))
	assert_false(b.in_bounds(Vector2i(8, 0)))
	assert_false(b.in_bounds(Vector2i(-1, 2)))

func test_default_fill_is_field() -> void:
	assert_eq(_board().kind_at(Vector2i(4, 4)), Terrain.Kind.FIELD)

func test_set_and_read_kind() -> void:
	var b: Board = _board()
	b.set_kind(Vector2i(2, 2), Terrain.Kind.FOREST)
	assert_eq(b.kind_at(Vector2i(2, 2)), Terrain.Kind.FOREST)
	assert_eq(b.penalty_at(Vector2i(2, 2)), Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.DRY))

func test_out_of_bounds_is_impassable() -> void:
	assert_false(_board().is_passable(Vector2i(-1, 0)))

func test_movement_is_four_directional() -> void:
	assert_eq(Board.DIRS_4.size(), 4, "§3.1: рух лише ортогональний")
	for d in Board.DIRS_4:
		assert_eq(absi(d.x) + absi(d.y), 1, "жодних діагоналей у русі")

func test_facing_is_eight_directional() -> void:
	assert_eq(Board.DIRS_8.size(), 8, "§3.1: поворот — 8 напрямків")

func test_facing_towards_matches_dirs8() -> void:
	var origin := Vector2i(4, 4)
	for i in Board.DIRS_8.size():
		var target: Vector2i = origin + Board.DIRS_8[i] * 3
		assert_eq(Board.facing_towards(origin, target), i, "напрямок %d має бути стабільним" % i)

func test_neighbours_are_clipped_to_board() -> void:
	assert_eq(_board().neighbours4(Vector2i(0, 0)).size(), 2)
	assert_eq(_board().neighbours4(Vector2i(3, 3)).size(), 4)

func test_out_of_bounds_does_not_alias_to_real_tiles() -> void:
	# Verify out-of-bounds coordinates are impassable, not aliasing onto real tiles
	var b: Board = _board()
	# Set a known kind at (0, 1) and at the last tile (7, 5)
	b.set_kind(Vector2i(0, 1), Terrain.Kind.FOREST)
	b.set_kind(Vector2i(7, 5), Terrain.Kind.WATER)
	# Out-of-bounds coordinates must be rejected outright, not folded into the
	# flat tile index (y * width + x), where they could silently alias onto a
	# real tile's data (e.g. (8, 0) would land on the same index as (0, 1)).
	assert_false(b.is_passable(Vector2i(-1, 0)), "negative x should be impassable")
	assert_false(b.is_passable(Vector2i(8, 0)), "x >= width should be impassable")
	assert_false(b.is_passable(Vector2i(0, -1)), "negative y should be impassable")
	assert_false(b.is_passable(Vector2i(0, 6)), "y >= height should be impassable")
	# Verify the real tiles were not corrupted
	assert_eq(b.kind_at(Vector2i(0, 1)), Terrain.Kind.FOREST)
	assert_eq(b.kind_at(Vector2i(7, 5)), Terrain.Kind.WATER)
