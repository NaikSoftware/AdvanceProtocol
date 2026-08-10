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

func test_vision_is_a_diamond_not_a_circle() -> void:
	# §3.1: цей тест перевернуто навмисне — раніше він стверджував протилежне.
	# Зламалася не реалізація, а передумова: огляд більше не коло. Ромб — це
	# лічильник кроків по 4-напрямковій сітці, тож огляд має ту саму форму, що й рух.
	var v: Vision = Vision.create(12, 12)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)   # огляд 5
	v.recompute(_board(), [inf], 0)
	assert_false(v.is_visible(Vector2i(9, 9)), "|3|+|3| = 6 > 5 — поза ромбом, хоч dist_sq 18 <= 25")
	assert_true(v.is_visible(Vector2i(8, 9)), "|2|+|3| = 5 — рівно на межі ромба")

func test_a_tile_inside_the_range_circle_can_lie_outside_the_vision_diamond() -> void:
	# §3.1: розбіжність двох форм на діагоналі — не похибка, а правило.
	# (9, 10) від (6, 6) — це dist_sq 25 <= 25 (усередині кола дальності 5)
	# і 3 + 4 = 7 > 5 (поза ромбом огляду 5).
	assert_true(Rules.in_radius(Vector2i(6, 6), Vector2i(9, 10), 5), "передумова: у колі дальності 5")
	assert_false(Rules.in_vision_diamond(Vector2i(6, 6), Vector2i(9, 10), 5), "передумова: поза ромбом огляду 5")
	var v: Vision = Vision.create(12, 12)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	v.recompute(_board(), [inf], 0)
	assert_false(v.is_visible(Vector2i(9, 10)),
		"§3.1: ціль буває в межах пострілу і водночас невидимою — обвідна вогню це перетин двох форм")

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
