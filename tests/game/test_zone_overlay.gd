extends GutTest
## Task 2.5, ruling R16: жива сцена battle_screen.tscn зʼявляється лише в
## Task 2.10, тож перевірка тут — headless, той самий прийом, що й
## tests/game/test_board_view.gd (ruling R4): підсвітка перевіряється через
## власний стан BoardView (_contour_segments), бо колір інстансу мультимешу
## не читається назад під headless-запуском.
##
## R15 → PO-скарга «контурно, не заливкою»: ZoneOverlay малює РЕБРА зони
## (BoardView.draw_contour), а не тайли (BoardView.highlight_tiles). Головний
## доказ — _layer_highlights для LAYER_ZONES лишається порожнім завжди
## (test_show_for_never_touches_the_tile_fill_layer нижче): це і відрізняє
## контур від fill структурно, без єдиного знімка екрана.

const BoardViewScene := preload("res://game/battle/board_view.tscn")

var board_view: Node3D
var overlay: ZoneOverlay


func before_each() -> void:
	board_view = BoardViewScene.instantiate()
	add_child_autofree(board_view)
	board_view.build(Board.create(20, 20, Terrain.GroundState.DRY))
	overlay = ZoneOverlay.new(board_view)


func _unit(pos: Vector2i) -> Unit:
	return Unit.create(1, 5, 0, pos, 0)


func _zones(origin: Vector2i, move_and_fire: Array[Vector2i], move_only: Array[Vector2i]) -> Pathing.Zones:
	var z := Pathing.Zones.new()
	z.origin = origin
	z.move_and_fire = move_and_fire
	z.move_only = move_only
	return z


func _segments(layer: int) -> Array:
	return board_view.contour_segments(layer)


## cell -> Array[Vector2i] напрямків, для яких намальована риска — зручно для
## тестів, яким байдужий сам напрямок, лише факт «цей тайл на контурі».
func _dirs_by_cell(layer: int) -> Dictionary:
	var out: Dictionary = {}
	for seg in _segments(layer):
		var cell: Vector2i = seg["cell"]
		if not out.has(cell):
			out[cell] = [] as Array[Vector2i]
		out[cell].append(seg["dir"])
	return out


func test_show_for_paints_only_zones_layer() -> void:
	var origin := Vector2i(10, 10)
	var mf: Array[Vector2i] = [Vector2i(10, 10)]
	var mo: Array[Vector2i] = [Vector2i(11, 10)]
	overlay.show_for(_unit(origin), _zones(origin, mf, mo))

	var by_cell: Dictionary = _dirs_by_cell(board_view.LAYER_ZONES)
	assert_true(by_cell.has(Vector2i(10, 10)), "золота зона мусить бути намальована")
	assert_true(by_cell.has(Vector2i(11, 10)), "червона зона мусить бути намальована")
	assert_eq(_segments(board_view.LAYER_TARGETS).size(), 0, "show_for не мусить чіпати шар цілей")
	assert_eq(_segments(board_view.LAYER_SELECTION).size(), 0, "show_for не мусить чіпати шар вибору")
	assert_eq(_segments(board_view.LAYER_PATH).size(), 0, "show_for не мусить чіпати шар шляху")


## Головний доказ Task 1: контур ЗОН ніколи не є заливкою тайла. Якби
## show_for() досі викликав highlight_tiles(), цей запис зʼявився б тут.
func test_show_for_never_touches_the_tile_fill_layer() -> void:
	var origin := Vector2i(10, 10)
	var block: Array[Vector2i] = []
	for x in range(9, 12):
		for y in range(9, 12):
			block.append(Vector2i(x, y))
	overlay.show_for(_unit(origin), _zones(origin, block, []))

	assert_eq(board_view._layer_highlights[board_view.LAYER_ZONES].size(), 0,
		"зона руху — контур, не заливка: _layer_highlights мусить лишитись порожнім")


func test_show_for_uses_correct_colors_per_zone() -> void:
	var origin := Vector2i(10, 10)
	var mf: Array[Vector2i] = [Vector2i(10, 10)]
	var mo: Array[Vector2i] = [Vector2i(11, 10)]
	overlay.show_for(_unit(origin), _zones(origin, mf, mo))

	for seg in _segments(board_view.LAYER_ZONES):
		if seg["cell"] == Vector2i(10, 10):
			assert_eq(seg["color"], ZoneOverlay.COLOR_MOVE_AND_FIRE)
		elif seg["cell"] == Vector2i(11, 10):
			assert_eq(seg["color"], ZoneOverlay.COLOR_MOVE_ONLY)


## Тест доводить саме контур, а не «намальовано хоч щось»: суцільний 3x3
## блок у одній зоні має внутрішню клітинку без жодного сусіда ззовні — вона
## не мусить отримати жодної риски, тоді як усі вісім країв мусять отримати
## бодай одну. Рівно 12 риск разом: чотири кутові тайли мають по 2 ребра
## назовні, чотири серединні — по 1 (§3.2, DIRS_4 — лише ортогональні сусіди).
func test_contour_omits_interior_tile_of_a_solid_block() -> void:
	var origin := Vector2i(5, 5)
	var block: Array[Vector2i] = []
	for x in range(4, 7):
		for y in range(4, 7):
			block.append(Vector2i(x, y))
	var mo: Array[Vector2i] = block.duplicate()
	overlay.show_for(_unit(origin), _zones(origin, [], mo))

	var by_cell: Dictionary = _dirs_by_cell(board_view.LAYER_ZONES)
	assert_false(by_cell.has(Vector2i(5, 5)), "центр суцільного блоку — не контур, всі сусіди в тій самій зоні")
	for cell in block:
		if cell != Vector2i(5, 5):
			assert_true(by_cell.has(cell), "%s: край блоку мусить мати хоч одну риску" % cell)
	assert_eq(_segments(board_view.LAYER_ZONES).size(), 12, "рівно 12 риск на периметрі 3x3 блоку, без центру")


## Золота зона (внутрішній 3x3) і червона зона (кільце навколо неї) торкаються
## по межі — на дотичному ребрі мусить лишитись РІВНО ДВІ риски (по одній з
## кожного боку), а не одна змішана й не жодної.
func test_nested_zones_touch_without_swallowing_each_other() -> void:
	var origin := Vector2i(10, 10)
	var gold: Array[Vector2i] = []
	for x in range(9, 12):
		for y in range(9, 12):
			gold.append(Vector2i(x, y))
	var red: Array[Vector2i] = []
	for x in range(8, 13):
		for y in range(8, 13):
			var p := Vector2i(x, y)
			if not gold.has(p):
				red.append(p)
	overlay.show_for(_unit(origin), _zones(origin, gold, red))

	var gold_edge := {"cell": Vector2i(11, 10), "dir": Vector2i(1, 0)}
	var red_edge := {"cell": Vector2i(12, 10), "dir": Vector2i(-1, 0)}
	var found_gold := false
	var found_red := false
	for seg in _segments(board_view.LAYER_ZONES):
		if seg["cell"] == gold_edge["cell"] and seg["dir"] == gold_edge["dir"]:
			assert_eq(seg["color"], ZoneOverlay.COLOR_MOVE_AND_FIRE, "золота риска на дотичному ребрі лишається золотою")
			found_gold = true
		if seg["cell"] == red_edge["cell"] and seg["dir"] == red_edge["dir"]:
			assert_eq(seg["color"], ZoneOverlay.COLOR_MOVE_ONLY, "червона риска на дотичному ребрі лишається червоною")
			found_red = true
	assert_true(found_gold, "золота сторона дотичного ребра мусить мати власну риску")
	assert_true(found_red, "червона сторона дотичного ребра мусить мати власну риску")

	var by_cell: Dictionary = _dirs_by_cell(board_view.LAYER_ZONES)
	assert_false(by_cell.has(origin), "центр золотого блоку — суцільна внутрішність, не контур")


func test_clear_removes_overlay_and_leaves_other_layers_alone() -> void:
	var target_cell := Vector2i(3, 3)
	var selection_cell := Vector2i(4, 4)
	board_view.highlight_tiles([target_cell] as Array[Vector2i], Color.RED, board_view.LAYER_TARGETS)
	board_view.highlight_tiles([selection_cell] as Array[Vector2i], Color.WHITE, board_view.LAYER_SELECTION)

	var origin := Vector2i(10, 10)
	var mf: Array[Vector2i] = [Vector2i(10, 10)]
	overlay.show_for(_unit(origin), _zones(origin, mf, []))
	assert_true(_segments(board_view.LAYER_ZONES).size() > 0, "передумова: зона намальована")

	overlay.clear()
	assert_eq(_segments(board_view.LAYER_ZONES).size(), 0, "clear() мусить прибрати весь контур зон")
	assert_true(board_view._layer_highlights[board_view.LAYER_TARGETS].has(target_cell), "clear() не мусить чіпати шар цілей")
	assert_true(board_view._layer_highlights[board_view.LAYER_SELECTION].has(selection_cell), "clear() не мусить чіпати шар вибору")


## §3.2: «перемальовується після кожної дії» — другий show_for підряд
## замінює попередній контур, а не додає до нього.
func test_show_for_called_twice_replaces_not_accumulates() -> void:
	var origin_a := Vector2i(2, 2)
	var origin_b := Vector2i(15, 15)
	overlay.show_for(_unit(origin_a), _zones(origin_a, [origin_a], []))
	assert_true(_dirs_by_cell(board_view.LAYER_ZONES).has(origin_a))

	overlay.show_for(_unit(origin_b), _zones(origin_b, [origin_b], []))
	var by_cell: Dictionary = _dirs_by_cell(board_view.LAYER_ZONES)
	assert_false(by_cell.has(origin_a), "стара зона мусить зникнути, а не лишитись поруч із новою")
	assert_true(by_cell.has(origin_b), "нова зона мусить бути намальована")


func test_show_for_handles_single_tile_zone() -> void:
	var origin := Vector2i(5, 5)
	overlay.show_for(_unit(origin), _zones(origin, [origin], []))
	var segments: Array = _segments(board_view.LAYER_ZONES)
	assert_eq(segments.size(), 4, "один тайл — усі чотири боки на контурі")
	for seg in segments:
		assert_eq(seg["cell"], origin)
		assert_eq(seg["color"], ZoneOverlay.COLOR_MOVE_AND_FIRE)


func test_show_for_handles_empty_zones_without_crashing() -> void:
	var origin := Vector2i(5, 5)
	overlay.show_for(_unit(origin), _zones(origin, [], []))
	assert_eq(_segments(board_view.LAYER_ZONES).size(), 0, "порожні зони — порожній контур, без падіння")
