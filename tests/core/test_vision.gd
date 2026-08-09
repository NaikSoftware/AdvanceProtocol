extends GutTest

func _board() -> Board:
	return Board.create(12, 12, Terrain.GroundState.DRY)

func test_unit_sees_its_own_radius() -> void:
	var v: Vision = Vision.create(12, 12)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)   # vision 5
	v.recompute(_board(), [inf], 0)
	assert_true(v.is_visible(Vector2i(6, 6)))
	assert_true(v.is_visible(Vector2i(6, 1)), "рівно 5 тайлів — усередині")
	assert_false(v.is_visible(Vector2i(6, 0)), "6 тайлів — уже ні")

func test_vision_is_euclidean_not_diamond() -> void:
	var v: Vision = Vision.create(12, 12)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	v.recompute(_board(), [inf], 0)
	assert_true(v.is_visible(Vector2i(9, 9)), "dist_sq 18 <= 25 — коло, не ромб")

func test_only_own_units_contribute() -> void:
	var v: Vision = Vision.create(12, 12)
	var mine: Unit = Unit.create(1, 0, 0, Vector2i(1, 1), 0)
	var theirs: Unit = Unit.create(2, 0, 1, Vector2i(10, 10), 0)
	v.recompute(_board(), [mine, theirs], 0)
	assert_false(v.is_visible(Vector2i(10, 10)), "чужий юніт не світить тобі карту")

func test_dead_units_see_nothing() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	u.hp = 0
	v.recompute(_board(), [u], 0)
	assert_false(v.is_visible(Vector2i(6, 6)))

func test_seen_is_sticky_but_visible_is_not() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(2, 2), 0)
	v.recompute(_board(), [u], 0)
	assert_true(v.is_visible(Vector2i(2, 2)))
	u.pos = Vector2i(10, 10)
	v.recompute(_board(), [u], 0)
	assert_false(v.is_visible(Vector2i(2, 2)), "visible перебудовується з нуля")
	assert_true(v.is_seen(Vector2i(2, 2)), "seen памʼятає назавжди")

func test_newly_revealed_tiles_are_reported_once() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	var first: Array[Vector2i] = v.recompute(_board(), [u], 0)
	assert_true(first.size() > 0)
	var second: Array[Vector2i] = v.recompute(_board(), [u], 0)
	assert_eq(second.size(), 0, "той самий огляд другого разу нічого не відкриває")
