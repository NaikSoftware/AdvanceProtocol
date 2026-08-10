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

func test_seen_never_shrinks_even_when_the_scout_dies() -> void:
	# §3.5: seen — храповик, і саме тому правила читають його, а не visible.
	# Розвідник, що загинув, однаково лишив власникові все, що встиг побачити:
	# після його смерті visible гасне цілком, а жоден біт seen не має впасти.
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(2, 2), 0)   # піхота, огляд 5
	v.recompute(_board(), [u], 0)
	var before: PackedByteArray = v.seen.duplicate()
	assert_true(before.count(1) > 0, "передумова: щось таки розвідано")

	u.hp = 0
	v.recompute(_board(), [u], 0)

	assert_eq(v.visible.count(1), 0, "мертвий розвідник більше нічого не світить")
	for i in before.size():
		if before[i] == 1:
			assert_eq(v.seen[i], 1, "біт seen №%d згас — розвідка не має відкочуватись" % i)
	assert_true(v.is_seen(Vector2i(2, 2)), "і власний тайл загиблого лишається розвіданим")

func test_newly_revealed_tiles_are_reported_once() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	var first: Array[Vector2i] = v.recompute(_board(), [u], 0)
	assert_true(first.size() > 0)
	var second: Array[Vector2i] = v.recompute(_board(), [u], 0)
	assert_eq(second.size(), 0, "той самий огляд другого разу нічого не відкриває")

func test_is_seen_and_is_visible_reject_out_of_bounds_coordinates() -> void:
	# §3.5: is_seen() — гейт усіх правил, які питають «чи бачить це гравець», і
	# сторожа _in_bounds() довго була декоративною: жодне правило is_seen() не
	# читало. Тепер читає, і дістатись до неї легко — Objectives.add()
	# (core/objectives.gd) не перевіряє позицію цілі, тож рукописна мапа з ціллю
	# на від'ємній чи за-межевій координаті доводить Objectives.refresh_seen() до
	# is_seen() з координатою поза сіткою щоходу.
	#
	# Масиви заповнені суцільно одиницями навмисне: _index() рахує позицію
	# лінійно (y*width+x), тож координата, зіпсована лише по одній осі, здатна
	# арифметично влучити у ЧУЖИЙ, цілком дійсний індекс іншого тайла. Без
	# перевірки меж це прочитало б справжню одиницю і мовчки повернуло true —
	# рівно ту поведінку й ловить цей тест. Точкове заповнення такої гарантії не
	# дало б: зіпсована арифметика могла б так само влучити в нуль і тест
	# лишився б зеленим і без guard'а.
	var v: Vision = Vision.create(10, 10)
	v.seen.fill(1)
	v.visible.fill(1)

	# x < 0, y лишається в межах: (-1,1) → 1*10-1 = 9 — дійсний індекс чужого тайла.
	assert_false(v.is_seen(Vector2i(-1, 1)), "is_seen(): x < 0")
	assert_false(v.is_visible(Vector2i(-1, 1)), "is_visible(): x < 0")
	# x >= width, y лишається в межах: (10,0) → 0*10+10 = 10 — так само дійсний.
	assert_false(v.is_seen(Vector2i(10, 0)), "is_seen(): x >= width")
	assert_false(v.is_visible(Vector2i(10, 0)), "is_visible(): x >= width")
	# y < 0: лінійний індекс не дає влучити в дійсну клітинку без переповнення
	# й по x, тож ця пара зачіпає обидві умови одразу — саме тому вони й
	# гейтяться однією сполучною, а не двома окремими перевірками.
	assert_false(v.is_seen(Vector2i(10, -1)), "is_seen(): y < 0")
	assert_false(v.is_visible(Vector2i(10, -1)), "is_visible(): y < 0")
	# y >= height: та сама причина, дзеркально.
	assert_false(v.is_seen(Vector2i(-1, 10)), "is_seen(): y >= height")
	assert_false(v.is_visible(Vector2i(-1, 10)), "is_visible(): y >= height")
