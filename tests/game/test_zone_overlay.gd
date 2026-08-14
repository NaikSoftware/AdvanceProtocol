extends GutTest
## Task 2.5, ruling R16: жива сцена battle_screen.tscn зʼявляється лише в
## Task 2.10, тож перевірка тут — headless, той самий прийом, що й
## tests/game/test_board_view.gd (ruling R4): підсвітка перевіряється через
## власний стан BoardView (_layer_highlights), бо колір інстансу мультимешу
## не читається назад під headless-запуском.

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


func _painted(layer: int) -> Dictionary:
	return board_view._layer_highlights[layer]


func test_show_for_paints_only_zones_layer() -> void:
	var origin := Vector2i(10, 10)
	var mf: Array[Vector2i] = [Vector2i(10, 10)]
	var mo: Array[Vector2i] = [Vector2i(11, 10)]
	overlay.show_for(_unit(origin), _zones(origin, mf, mo))

	assert_true(_painted(board_view.LAYER_ZONES).has(Vector2i(10, 10)), "золота зона мусить бути намальована")
	assert_true(_painted(board_view.LAYER_ZONES).has(Vector2i(11, 10)), "червона зона мусить бути намальована")
	assert_eq(_painted(board_view.LAYER_TARGETS).size(), 0, "show_for не мусить чіпати шар цілей")
	assert_eq(_painted(board_view.LAYER_SELECTION).size(), 0, "show_for не мусить чіпати шар вибору")


func test_show_for_uses_correct_colors_per_zone() -> void:
	var origin := Vector2i(10, 10)
	var mf: Array[Vector2i] = [Vector2i(10, 10)]
	var mo: Array[Vector2i] = [Vector2i(11, 10)]
	overlay.show_for(_unit(origin), _zones(origin, mf, mo))

	assert_eq(_painted(board_view.LAYER_ZONES)[Vector2i(10, 10)], ZoneOverlay.COLOR_MOVE_AND_FIRE)
	assert_eq(_painted(board_view.LAYER_ZONES)[Vector2i(11, 10)], ZoneOverlay.COLOR_MOVE_ONLY)


## Тест доводить саме контур, а не «намальовано хоч щось»: суцільний 3x3
## блок у одній зоні має внутрішню клітинку без жодного сусіда ззовні — вона
## не має потрапити на дошку, тоді як усі вісім країв мусять.
func test_contour_omits_interior_tile_of_a_solid_block() -> void:
	var origin := Vector2i(5, 5)
	var block: Array[Vector2i] = []
	for x in range(4, 7):
		for y in range(4, 7):
			block.append(Vector2i(x, y))
	var mo: Array[Vector2i] = block.duplicate()
	overlay.show_for(_unit(origin), _zones(origin, [], mo))

	var painted: Dictionary = _painted(board_view.LAYER_ZONES)
	assert_false(painted.has(Vector2i(5, 5)), "центр суцільного блоку — не контур, всі сусіди в тій самій зоні")
	for cell in block:
		if cell != Vector2i(5, 5):
			assert_true(painted.has(cell), "%s: край блоку мусить бути в контурі" % cell)
	assert_eq(painted.size(), 8, "рівно вісім країв 3x3 блоку, без центру")


## Золота зона (внутрішній 3x3) і червона зона (кільце навколо неї) торкаються
## по межі — дотична золота клітинка не має бути «проковтнута» червоною і
## навпаки.
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

	var painted: Dictionary = _painted(board_view.LAYER_ZONES)
	# (11,10) золотий правий край внутрішнього блоку, (12,10) — сусідній
	# червоний тайл кільця відразу зовні — точка дотику двох контурів.
	assert_eq(painted[Vector2i(11, 10)], ZoneOverlay.COLOR_MOVE_AND_FIRE, "золота межа лишається золотою біля червоної")
	assert_eq(painted[Vector2i(12, 10)], ZoneOverlay.COLOR_MOVE_ONLY, "червона межа лишається червоною біля золотої")
	assert_false(painted.has(origin), "центр золотого блоку — суцільна внутрішність, не контур")


func test_clear_removes_overlay_and_leaves_other_layers_alone() -> void:
	var target_cell := Vector2i(3, 3)
	var selection_cell := Vector2i(4, 4)
	board_view.highlight_tiles([target_cell] as Array[Vector2i], Color.RED, board_view.LAYER_TARGETS)
	board_view.highlight_tiles([selection_cell] as Array[Vector2i], Color.WHITE, board_view.LAYER_SELECTION)

	var origin := Vector2i(10, 10)
	var mf: Array[Vector2i] = [Vector2i(10, 10)]
	overlay.show_for(_unit(origin), _zones(origin, mf, []))
	assert_true(_painted(board_view.LAYER_ZONES).size() > 0, "передумова: зона намальована")

	overlay.clear()
	assert_eq(_painted(board_view.LAYER_ZONES).size(), 0, "clear() мусить прибрати весь шар зон")
	assert_true(_painted(board_view.LAYER_TARGETS).has(target_cell), "clear() не мусить чіпати шар цілей")
	assert_true(_painted(board_view.LAYER_SELECTION).has(selection_cell), "clear() не мусить чіпати шар вибору")


## §3.2: «перемальовується після кожної дії» — другий show_for підряд
## замінює попередню зону, а не додає до неї.
func test_show_for_called_twice_replaces_not_accumulates() -> void:
	var origin_a := Vector2i(2, 2)
	var origin_b := Vector2i(15, 15)
	overlay.show_for(_unit(origin_a), _zones(origin_a, [origin_a], []))
	assert_true(_painted(board_view.LAYER_ZONES).has(origin_a))

	overlay.show_for(_unit(origin_b), _zones(origin_b, [origin_b], []))
	var painted: Dictionary = _painted(board_view.LAYER_ZONES)
	assert_false(painted.has(origin_a), "стара зона мусить зникнути, а не лишитись поруч із новою")
	assert_true(painted.has(origin_b), "нова зона мусить бути намальована")
	assert_eq(painted.size(), 1, "жодного накопичення між викликами")


func test_show_for_handles_single_tile_zone() -> void:
	var origin := Vector2i(5, 5)
	overlay.show_for(_unit(origin), _zones(origin, [origin], []))
	var painted: Dictionary = _painted(board_view.LAYER_ZONES)
	assert_eq(painted.size(), 1, "один тайл — весь він і є контур")
	assert_eq(painted[origin], ZoneOverlay.COLOR_MOVE_AND_FIRE)


func test_show_for_handles_empty_zones_without_crashing() -> void:
	var origin := Vector2i(5, 5)
	overlay.show_for(_unit(origin), _zones(origin, [], []))
	assert_eq(_painted(board_view.LAYER_ZONES).size(), 0, "порожні зони — порожній контур, без падіння")
