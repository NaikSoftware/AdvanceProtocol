extends GutTest
## TagPlacement (spec §2): чиста геометрія, без вузлів. Точні значення, а не нерівності, там, де
## їх дає формула.

const SCREEN := Rect2(0, 0, 985, 442)
const TAG := Vector2(209.0, 30.0)


func _scene(extra: Dictionary = {}) -> Dictionary:
	var s: Dictionary = {
		"tag_size": TAG, "unit": Rect2(480, 200, 40, 50), "core": Rect2(480, 220, 40, 30),
		"others": [] as Array[Rect2], "chrome": [] as Array[Rect2],
		"polys": [] as Array[PackedVector2Array], "fire": PackedVector2Array(),
		"marks": [] as Array[PackedVector2Array], "screen": SCREEN,
	}
	s.merge(extra, true)
	return s


func test_free_board_puts_the_tag_beside_the_unit_without_a_leader() -> void:
	var p := TagPlacement.new(_scene())
	var pick: Dictionary = p.best()
	assert_true(pick["found"])
	assert_false(pick["leader"], "місця вдосталь — лідер не потрібен")
	var r: Rect2 = pick["rect"]
	assert_false(r.intersects(Rect2(480, 200, 40, 50)), "тег не лягає на свого юніта")
	assert_eq(TagPlacement._dist(r, Rect2(480, 200, 40, 50)), 8.0, "найближчий законний — рівно 8 dp від коробки")


func test_tag_stays_off_every_other_unit_and_chrome() -> void:
	var others: Array[Rect2] = [Rect2(380, 190, 40, 50), Rect2(580, 190, 40, 50)]
	var chrome: Array[Rect2] = [Rect2(24, 12, 160, 36)]
	var p := TagPlacement.new(_scene({"others": others, "chrome": chrome}))
	var pick: Dictionary = p.best()
	assert_true(pick["found"])
	for o: Rect2 in others:
		assert_false((pick["rect"] as Rect2).intersects(o.grow(8.0)), "сусід %s обійдено з запасом 8 dp" % o)
	assert_false((pick["rect"] as Rect2).intersects(chrome[0].grow(8.0)))


func test_contour_under_the_tag_costs_exactly_the_mark_fraction() -> void:
	# Горизонталь довжиною 100 dp усередині тега 209 × 30: 100 × 2 dp / 6270 dp².
	var r := Rect2(100, 100, 209, 30)
	var line := PackedVector2Array([Vector2(110, 115), Vector2(210, 115)])
	var marks: Array[PackedVector2Array] = [line]
	var unit := Rect2(300, 200, 40, 50)
	var with := TagPlacement.new(_scene({"unit": unit, "core": unit, "marks": marks}))
	var without := TagPlacement.new(_scene({"unit": unit, "core": unit}))
	assert_almost_eq(with.score(r) - without.score(r), TagPlacement.MARK_WEIGHT * 200.0 / (209.0 * 30.0) + TagPlacement.TOUCH_COST, 0.001,
		"ціна — вага × площа лінії / площа тега плюс ціна дотику")


func test_a_contour_pushes_the_tag_to_the_clear_side() -> void:
	var clear := TagPlacement.new(_scene()).best()["rect"] as Rect2
	var marks: Array[PackedVector2Array] = []
	# Контур по всьому ряду, куди тег став би без нього.
	for y in range(int(clear.position.y), int(clear.end.y) + 1, 4):
		marks.append(PackedVector2Array([Vector2(clear.position.x - 20.0, y), Vector2(clear.end.x + 20.0, y)]))
	var moved := TagPlacement.new(_scene({"marks": marks})).best()
	assert_true(moved["found"])
	assert_ne(moved["rect"], clear, "тег уникає контуру там, де є чистий варіант")


func test_move_path_cells_are_hard_obstacles_for_the_tag_and_its_leader() -> void:
	var cell := PackedVector2Array([Vector2(300, 150), Vector2(400, 150), Vector2(400, 250), Vector2(300, 250)])
	var p := TagPlacement.new(_scene({"polys": [cell] as Array[PackedVector2Array]}))
	var pick: Dictionary = p.best()
	assert_true(pick["found"])
	var grown: Rect2 = Rect2(300, 150, 100, 100).grow(TagPlacement.POLY_GROW)
	assert_false((pick["rect"] as Rect2).intersects(grown), "полігон клітинки + 4 dp — тверда перешкода")
	# Тег, який лежав би на клітинці, відхиляється.
	assert_false(p.is_legal(Rect2(250, 190, 209, 30)))


func test_tag_keeps_four_dp_from_a_cell_apex_the_raster_cannot_see() -> void:
	# Ромб (ізометрична клітинка): гострий верх тонший за крок растру, тож растр його пропускає.
	var cell := PackedVector2Array([Vector2(400, 190), Vector2(430, 205), Vector2(400, 220), Vector2(370, 205)])
	var p := TagPlacement.new(_scene({"polys": [cell] as Array[PackedVector2Array]}))
	assert_false(p.is_legal(Rect2(240, 158, 209, 30)), "2 dp над верхівкою — у запасі 4 dp")
	assert_true(p.is_legal(Rect2(240, 158, 209, 30), 2), "послаблення 2 полігони не враховує")


func test_line_of_fire_is_blocked() -> void:
	var fire := PackedVector2Array([Vector2(500, 225), Vector2(900, 225)])
	var p := TagPlacement.new(_scene({"fire": fire}))
	assert_false(p.is_legal(Rect2(540, 215, 209, 30)), "на лінії вогню тега нема")
	assert_true(p.is_legal(Rect2(540, 285, 209, 30)), "поза лінією — законне")


func test_hysteresis_keeps_a_legal_spot() -> void:
	var first := TagPlacement.new(_scene())
	var pick: Rect2 = first.best()["rect"]
	# Ті самі обставини, десь додалася далека перешкода: попередній ще законний.
	var again := TagPlacement.new(_scene({"others": [Rect2(100, 100, 40, 40)] as Array[Rect2]}))
	assert_true(again.is_legal(pick))


func test_no_legal_spot_reports_not_found() -> void:
	var wall: Array[Rect2] = [Rect2(-200, -200, 1500, 900)]
	# Усе довкола юніта — чужа коробка: місця для тега нема.
	var p := TagPlacement.new(_scene({"others": wall, "unit": Rect2(480, 200, 40, 50)}))
	assert_false(p.best()["found"])


func test_leader_runs_from_the_tag_edge_to_the_bar_and_model_box() -> void:
	var p := TagPlacement.new(_scene())
	var r := Rect2(560, 120, 209, 30)
	var ends: PackedVector2Array = p.leader_points(r)
	assert_eq(ends[0], Vector2(560, 150), "від найближчої до юніта точки краю тега")
	assert_eq(ends[1], Vector2(520, 220), "до найближчої точки коробки смуги й моделі")


func test_hold_card_takes_the_corner_away_from_the_finger() -> void:
	var card := Vector2(226.0, 161.0)
	var held := Rect2(100, 100, 40, 50)
	var rect: Rect2 = HudDocking.choose_card(Vector2(985, 442), card, held, [] as Array[Rect2], Vector2(120, 125))
	assert_eq(rect, Rect2(735, 64, 226, 161), "палець у лівій чверті — картка праворуч")
	var left: Rect2 = HudDocking.choose_card(Vector2(985, 442), card, Rect2(800, 100, 40, 50), [] as Array[Rect2], Vector2(820, 125))
	assert_eq(left, Rect2(24, 58, 226, 161), "палець праворуч — картка ліворуч")


func test_ring_of_cells_lets_the_leader_cross_them_before_the_tag_is_hidden() -> void:
	# Чотири клітинки щільно довкола юніта без щілини: лідер, що не перетинає жодної, неможливий, але тег
	# не зникає — AP інженера потрібен саме тут. Усі кінці лежать ближче 7,5 dp до клітинки (півдіагональ
	# квадрата плюс запас 4 dp), проте чистих від неї на 2 dp квадрата вистачає: рівень 1 приймає такий кінець.
	var cells: Array[Rect2] = [Rect2(440, 170, 120, 43.5), Rect2(440, 256.5, 120, 43.5), Rect2(440, 213.5, 33.5, 43), Rect2(526.5, 213.5, 33.5, 43)]
	var ring: Array[PackedVector2Array] = []
	for c: Rect2 in cells:
		ring.append(PackedVector2Array([c.position, Vector2(c.end.x, c.position.y), c.end, Vector2(c.position.x, c.end.y)]))
	var p := TagPlacement.new(_scene({"polys": ring}))
	var pick: Dictionary = p.best()
	assert_true(pick["found"])
	assert_eq(p.relax_used, 1, "рівень 1: лише лідер перетинає клітинки")
	assert_true(pick["leader"], "тег далі за 12 dp від юніта має лідера")
	for c: Rect2 in cells:
		assert_false((pick["rect"] as Rect2).intersects(c.grow(TagPlacement.POLY_GROW)), "тег поза клітинкою %s" % c)
	var ends: PackedVector2Array = p.leader_points(pick["rect"])
	var square := Rect2(ends[1] - Vector2(2.5, 2.5), Vector2(5.0, 5.0))
	for c: Rect2 in cells:
		assert_false(square.intersects(c.grow(2.0)), "кінець лідера не в клітинці %s і не на її краю" % c)
	assert_false(p.is_legal(pick["rect"]), "суворі правила цього місця не дають")


## Ті самі клітинки інженера, стиснуті довкола юніта (менший зум); напис HP лишається того ж розміру.
func _shrunk_engineer_scene(k: float) -> Dictionary:
	var s: Dictionary = _engineer_scene()
	var c: Vector2 = (s["unit"] as Rect2).get_center()
	var sc := func(v: Vector2) -> Vector2: return c + (v - c) * k
	var polys: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in s["polys"]:
		var q := PackedVector2Array()
		for v in poly:
			q.append(sc.call(v))
		polys.append(q)
	s["polys"] = polys
	var core_poly := PackedVector2Array()
	for v in s["core_poly"]:
		core_poly.append(sc.call(v))
	s["core_poly"] = core_poly
	for key: String in ["unit", "core"]:
		var r: Rect2 = s[key]
		s[key] = Rect2(sc.call(r.position), r.size * k)
	var label: Rect2 = s["label"]
	s["label"] = Rect2(sc.call(label.position), label.size)
	return s


func test_shrunk_engineer_cells_never_put_the_tag_on_them() -> void:
	for k: float in [0.6, 0.7, 0.8]:
		var scene: Dictionary = _shrunk_engineer_scene(k)
		var p := TagPlacement.new(scene)
		var pick: Dictionary = p.best()
		assert_true(pick["found"], "k=%s" % k)
		assert_lte(p.relax_used, 1, "k=%s: кінець, чистий на 2 dp, є — рівень 2 не потрібен" % k)
		for cell: PackedVector2Array in scene["polys"]:
			var box := PackedVector2Array([(pick["rect"] as Rect2).position, Vector2((pick["rect"] as Rect2).end.x, (pick["rect"] as Rect2).position.y),
				(pick["rect"] as Rect2).end, Vector2((pick["rect"] as Rect2).position.x, (pick["rect"] as Rect2).end.y)])
			assert_true(Geometry2D.intersect_polygons(box, cell).is_empty(), "k=%s: тег поза клітинкою" % k)


## Клітинки справжнього інженера (знято з кадра): чотири ромби довкола моделі, що сходяться в кутах.
## Щілина лишається над написом HP, між двома верхніми ромбами, — лідер входить у неї зверху.
func _engineer_scene() -> Dictionary:
	var cells: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(322.1627, 145.50818), Vector2(345.87024, 162.00468), Vector2(315.14536, 179.9884), Vector2(291.74048, 162.00468)]),
		PackedVector2Array([Vector2(258.53354, 179.83173), Vector2(281.48285, 199.51202), Vector2(244.51149, 221.143), Vector2(222.22429, 199.51201)]),
		PackedVector2Array([Vector2(270.26288, 145.47229), Vector2(291.73328, 161.96832), Vector2(258.5657, 179.95166), Vector2(237.59991, 161.96834)]),
		PackedVector2Array([Vector2(315.12955, 179.89021), Vector2(340.7483, 199.57097), Vector2(306.71823, 221.20224), Vector2(281.4966, 199.57097)]),
	]
	var chrome: Array[Rect2] = [Rect2(24, 12, 151, 36), Rect2(728, 8, 48, 48), Rect2(24, 300, 161, 48), Rect2(491, 296, 285, 52)]
	return _scene({
		"tag_size": Vector2(234.0, 30.0), "screen": Rect2(0, 0, 800, 360), "polys": cells, "chrome": chrome,
		"unit": Rect2(263.382, 157.3435, 40.4502, 34.91266), "core": Rect2(263.382, 157.9101, 40.4502, 34.34608),
		"label": Rect2(269.8468, 157.3435, 25.33765, 4.785034),
		"core_poly": PackedVector2Array([Vector2(263.382, 160.46288), Vector2(282.0581, 157.91008), Vector2(303.02417, 160.46288),
			Vector2(303.83218, 183.7564), Vector2(289.7757, 192.25616), Vector2(269.99643, 175.88872), Vector2(263.382, 165.41815)]),
	})


func test_engineer_leader_stays_out_of_every_target_cell_when_a_gap_exists() -> void:
	var scene: Dictionary = _engineer_scene()
	var p := TagPlacement.new(scene)
	var pick: Dictionary = p.best()
	assert_true(pick["found"])
	assert_eq(p.relax_used, 0, "щілина над написом дає законне місце без пом'якшень")
	assert_true(pick["leader"])
	var ends: PackedVector2Array = p.leader_points(pick["rect"])
	for cell: PackedVector2Array in scene["polys"]:
		assert_true(Geometry2D.intersect_polyline_with_polygon(ends, cell).is_empty(), "лінія лідера поза клітинкою")
		assert_false(Geometry2D.is_point_in_polygon(ends[1], cell), "кінець лідера поза клітинкою")
		for g in Geometry2D.offset_polygon(cell, 2.0, Geometry2D.JOIN_MITER):
			assert_false(Geometry2D.is_point_in_polygon(ends[1], g), "кінець лідера не ближче 2 dp до клітинки")


func test_leader_never_exceeds_the_cap() -> void:
	var p := TagPlacement.new(_scene())
	var near := Rect2(480.0 - TAG.x - 40.0, 220.0, TAG.x, TAG.y)
	assert_true(p.is_legal(near))
	assert_true(p.needs_leader(near))
	var ends: PackedVector2Array = p.leader_points(near)
	assert_true(ends[0].distance_to(ends[1]) <= TagPlacement.MAX_LEAD)
	assert_false(p.is_legal(Rect2(480.0 - TAG.x - 100.0, 220.0, TAG.x, TAG.y)), "далі за 60 dp тег не стає")


func test_leader_ends_on_the_silhouette_polygon_not_the_box_corner() -> void:
	# Силует — трикутник: кут охопної коробки порожній, лідер мусить лягти на скіс.
	var tri := PackedVector2Array([Vector2(480, 250), Vector2(520, 250), Vector2(520, 220)])
	var p := TagPlacement.new(_scene({"core_poly": tri}))
	var left: PackedVector2Array = p.leader_points(Rect2(200, 120, 209, 30))
	assert_eq(left[0], Vector2(409, 150))
	assert_almost_eq(left[1], Vector2(482.56, 248.08), Vector2(0.01, 0.01), "основа перпендикуляра на скіс силуету, а не кут коробки (480, 220)")


func test_hold_card_tie_takes_the_corner_farther_from_the_press_and_avoids_ring_arcs() -> void:
	var card := Vector2(226.0, 161.0)
	var screen := Vector2(985, 442)
	var held := Rect2(600, 300, 40, 50)
	var none: Array[PackedVector2Array] = []
	var tie: Rect2 = HudDocking.choose_card(screen, card, held, [] as Array[Rect2], Vector2(620, 325), none)
	assert_eq(tie, Rect2(24, 58, 226, 161), "обидва кутки чисті: дальший від пальця — лівий")
	# Дуга кільця проходить крізь лівий верхній куток: тепер ціна кутка вища, і картка йде праворуч.
	var arc: Array[PackedVector2Array] = [PackedVector2Array([Vector2(24, 120), Vector2(250, 120)])]
	var moved: Rect2 = HudDocking.choose_card(screen, card, held, [] as Array[Rect2], Vector2(620, 325), arc)
	assert_eq(moved, Rect2(735, 64, 226, 161))


func test_leader_end_square_stays_off_the_hp_label() -> void:
	# Напис лежить на верхньому краї смуги, тег зверху: найближча точка була б просто під цифрами.
	var label := Rect2(482, 214, 36, 9)
	var p := TagPlacement.new(_scene({"label": label}))
	for r: Rect2 in [Rect2(471, 120, 209, 30), Rect2(300, 120, 209, 30), Rect2(560, 150, 209, 30)]:
		var ends: PackedVector2Array = p.leader_points(r)
		var square := Rect2(ends[1] - Vector2(2.5, 2.5), Vector2(5.0, 5.0))
		assert_false(square.intersects(label.grow(2.0)), "квадрат кінця поза написом HP: %s" % [ends])


func test_contour_corner_is_found_only_where_the_line_turns() -> void:
	var marks: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]),
		PackedVector2Array([Vector2(10, 0), Vector2(10, 10)]),
		PackedVector2Array([Vector2(10, 10), Vector2(10, 20)]),
	]
	assert_eq(TagPlacement._find_corners(marks), PackedVector2Array([Vector2(10, 0)]), "прямий стик (10,10) — не кут")


func test_a_contour_corner_under_the_tag_loses_to_a_clean_spot_beside_the_unit() -> void:
	# Зона огортає юніта знизу й справа: кут контуру якраз під нижнім місцем, ліворуч чисто.
	var unit := Rect2(480, 200, 40, 50)
	var marks: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(440, 270), Vector2(560, 270)]),
		PackedVector2Array([Vector2(560, 270), Vector2(560, 200)]),
	]
	var p := TagPlacement.new(_scene({"unit": unit, "core": unit, "marks": marks}))
	var below := Rect2(350, 258, 209, 30)
	var clean := Rect2(263, 210, 209, 30)
	assert_true(p.score(below) - p.score(clean) >= TagPlacement.CORNER_COST, "кут під тегом коштує щонайменше ціну кута")
	var pick: Dictionary = p.best()
	assert_eq(p.mark_cover(pick["rect"]), 0.0, "обране місце без контурів")


func test_leader_cost_is_exact_and_steep_past_forty_dp() -> void:
	var unit := Rect2(480, 200, 40, 50)
	var p := TagPlacement.new(_scene({"unit": unit, "core": unit}))
	var r := Rect2(400, 120, 209, 30)
	var ends: PackedVector2Array = p.leader_points(r)
	var len: float = ends[0].distance_to(ends[1])
	var d: float = TagPlacement._dist(r, unit)
	var expected: float = TagPlacement.DISTANCE_WEIGHT * d + TagPlacement.LEADER_COST \
		+ TagPlacement.LONG_LEAD_PER_DP * maxf(0.0, len - TagPlacement.LONG_LEAD_FROM)
	assert_eq(len, 50.0)
	assert_almost_eq(p.score(r), expected, 0.001)
	var near := Rect2(400, 150, 209, 30)
	assert_true(p.score(near) < p.score(r), "ближчий закуток дешевший за дальній")


func test_leader_is_needed_past_twelve_dp_from_the_model_not_from_the_label() -> void:
	# Напис над смугою розширює «unit», але лідер міряється від моделі зі смугою (core).
	var p := TagPlacement.new(_scene())
	assert_false(p.needs_leader(Rect2(263, 220, 209, 30)), "8 dp збоку від моделі — без лідера")
	assert_true(p.needs_leader(Rect2(480 + 40 + 13.5, 220, 209, 30)), "13,5 dp від моделі — лідер")
	assert_true(p.needs_leader(Rect2(480, 250 + 13.5, 209, 30)), "13,5 dp під моделлю — лідер")
	assert_false(p.needs_leader(Rect2(480, 250 + 12.0, 209, 30)), "рівно 12 dp — ще без лідера")
	assert_true(p.needs_leader(Rect2(480, 200 - 8.0 - 30.0, 209, 30)), "над написом: від моделі далі 12 dp — лідер")


func test_leader_end_square_stays_two_dp_off_the_drone_icon() -> void:
	var icon := Rect2(522, 224, 10, 10)
	var p := TagPlacement.new(_scene({"icon": icon}))
	for r: Rect2 in [Rect2(560, 150, 209, 30), Rect2(560, 230, 209, 30), Rect2(560, 300, 209, 30), Rect2(300, 120, 209, 30)]:
		var ends: PackedVector2Array = p.leader_points(r)
		var square := Rect2(ends[1] - Vector2(2.5, 2.5), Vector2(5.0, 5.0))
		assert_false(square.intersects(icon.grow(2.0)), "квадрат кінця ≥ 2 dp від значка: %s" % [ends])


func test_a_leadered_tag_hugging_another_unit_pays_the_crowded_cost() -> void:
	# Тег на 30 dp від свого юніта й на 11 dp від чужого: читається підписом чужого.
	var unit := Rect2(300, 300, 40, 50)
	var r := Rect2(340, 240, 209, 30)
	var with := TagPlacement.new(_scene({"unit": unit, "core": unit, "others": [Rect2(560, 210, 60, 30)] as Array[Rect2]}))
	var far := TagPlacement.new(_scene({"unit": unit, "core": unit, "others": [Rect2(900, 400, 20, 20)] as Array[Rect2]}))
	assert_eq(TagPlacement._dist(r, unit), 30.0)
	assert_eq(TagPlacement._dist(r, Rect2(560, 210, 60, 30)), 11.0)
	# Два крауди (< 12 dp; ближче за d + 8), тісний чужий, основа й 19 dp різниці відстаней.
	assert_eq(with.score(r) - far.score(r), 2.0 * TagPlacement.CROWD_COST + TagPlacement.NEAR_OTHER_CROWDED_COST \
		+ TagPlacement.NEAR_OTHER_COST + TagPlacement.NEAR_OTHER_PER_DP * 19.0)
