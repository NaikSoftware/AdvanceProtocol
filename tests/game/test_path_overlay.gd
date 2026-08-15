extends GutTest
## Підсвітка шляху (продовження Task 2.7/2.9): «клікнув юніта, клікнув
## клітинку — до підтвердження видно маршрут». PathOverlay нічого не рахує —
## малює РІВНО те, що прийшло в preview["path"] від InputController
## (Pathing.path_to() зі свіжих Pathing.Zones, R5: пораховані проти
## known_occupied_map(), не occupied_map()). Файл тут нічого не перевіряє
## про саме планування маршруту — те вже покрито
## tests/game/test_input_controller.gd (R5-тест); тут — лише що ОТРИМАНЕ
## малюється, а не переобчислюється.
##
## Живе в тій самій системі, що й ZoneOverlay: BoardView.draw_contour(), той
## самий приз структурних тестів без єдиного знімка екрана — колір інстансу
## мультимешу не читається назад під headless (R4/R16).

const BoardViewScene := preload("res://game/battle/board_view.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")

var board_view: Node3D
var overlay: PathOverlay


func before_each() -> void:
	board_view = BoardViewScene.instantiate()
	add_child_autofree(board_view)
	board_view.build(Board.create(20, 20, Terrain.GroundState.DRY))
	overlay = PathOverlay.new(board_view)


func _segments(layer: int) -> Array:
	return board_view.contour_segments(layer)


func _move_preview(path: Array[Vector2i]) -> Dictionary:
	return {
		"type": InputController.ActionType.MOVE,
		"unit_id": 1,
		"target": path[-1] if not path.is_empty() else Vector2i.ZERO,
		"path": path,
		"ap_left": 10,
	}


func _shot_preview() -> Dictionary:
	return {
		"type": InputController.ActionType.SHOT,
		"unit_id": 1,
		"target_id": 2,
		"sector": 0,
		"min": 10,
		"max": 20,
	}


# --- Малювання/зняття на голих словниках прев'ю ----------------------------

func test_show_preview_draws_full_outline_for_every_path_tile() -> void:
	var path: Array[Vector2i] = [Vector2i(6, 5), Vector2i(7, 5)]
	overlay.show_preview(_move_preview(path))

	var segments: Array = _segments(board_view.LAYER_PATH)
	assert_eq(segments.size(), 8, "два тайли шляху × чотири боки кожен")
	for seg in segments:
		assert_true(path.has(seg["cell"]), "%s: сегмент мусить належати клітинці шляху" % seg["cell"])
		assert_eq(seg["color"], PathOverlay.COLOR_PATH)


func test_show_preview_never_touches_the_tile_fill_layer() -> void:
	overlay.show_preview(_move_preview([Vector2i(6, 5)]))
	assert_eq(board_view._layer_highlights[board_view.LAYER_PATH].size(), 0,
		"шлях — контур, не заливка: _layer_highlights мусить лишитись порожнім")


func test_show_preview_ignores_shot_type_and_clears_any_previous_path() -> void:
	overlay.show_preview(_move_preview([Vector2i(6, 5)]))
	assert_true(_segments(board_view.LAYER_PATH).size() > 0, "передумова: шлях намальований")

	overlay.show_preview(_shot_preview())

	assert_eq(_segments(board_view.LAYER_PATH).size(), 0, "прев'ю пострілу не малює шлях і знімає старий")


func test_show_preview_with_empty_dict_clears_the_path() -> void:
	overlay.show_preview(_move_preview([Vector2i(6, 5)]))
	assert_true(_segments(board_view.LAYER_PATH).size() > 0, "передумова: шлях намальований")

	overlay.show_preview({})

	assert_eq(_segments(board_view.LAYER_PATH).size(), 0, "порожнє прев'ю — сигнал pending_cleared — знімає шлях")


func test_clear_empties_the_path_layer() -> void:
	overlay.show_preview(_move_preview([Vector2i(6, 5), Vector2i(7, 5)]))
	overlay.clear()
	assert_eq(_segments(board_view.LAYER_PATH).size(), 0)


func test_show_preview_called_twice_replaces_not_accumulates() -> void:
	overlay.show_preview(_move_preview([Vector2i(6, 5)]))
	overlay.show_preview(_move_preview([Vector2i(7, 5), Vector2i(8, 5)]))

	var cells: Array = []
	for seg in _segments(board_view.LAYER_PATH):
		if not cells.has(seg["cell"]):
			cells.append(seg["cell"])
	assert_false(cells.has(Vector2i(6, 5)), "старий шлях мусить зникнути")
	assert_true(cells.has(Vector2i(7, 5)) and cells.has(Vector2i(8, 5)), "новий шлях мусить бути намальований")


func test_show_preview_with_empty_path_array_draws_nothing() -> void:
	overlay.show_preview(_move_preview([] as Array[Vector2i]))
	assert_eq(_segments(board_view.LAYER_PATH).size(), 0)


## Колір шляху мусить різнитись і від золотої, і від червоної зони — інакше
## шлях (усередині зони, поверх її контуру) читався б як ще одна зона.
func test_path_color_differs_from_both_zone_colors() -> void:
	assert_ne(PathOverlay.COLOR_PATH, ZoneOverlay.COLOR_MOVE_AND_FIRE)
	assert_ne(PathOverlay.COLOR_PATH, ZoneOverlay.COLOR_MOVE_ONLY)


# --- Наскрізний тест: шлях будується з того, що гравець ЗНАЄ, не з правди ---
#
# Той самий сценарій, що й test_input_controller.gd
# (test_zone_uses_known_occupancy_not_true_occupancy): броньований автомобіль
# (vision-ромб 3) і ворог на Манхеттені 4 — за межею ромба, тож ніколи не
# бачений і відсутній у known_occupied_map(). InputController планує зони й
# шлях рівно проти НЕЇ (R5, input_controller.gd) — тап по клітинці ворога
## реєструється як звичайна ціль руху (Targeting тут ні до чого — тап по
## незнаній клітинці не резолвиться в юніта взагалі), і намальований шлях
## веде РІВНО туди, прямою лінією, а не в обхід — саме тому, що PathOverlay
## малює дане, а не перевіряє істину.
func test_drawn_path_reflects_the_known_board_not_the_true_one() -> void:
	var service := MatchServiceScript.new()
	add_child_autofree(service)
	service.start_match(Board.create(20, 20, Terrain.GroundState.DRY), 2, 1)
	var mover: Unit = service.state.add_unit(2, 0, Vector2i(5, 5), 0)  # armoured car, vision 3
	var hidden_enemy: Unit = service.state.add_unit(5, 1, Vector2i(5, 9), 0)  # Манхеттен 4, поза ромбом
	service.begin()
	service.take_events()

	assert_false(service.state.vision[0].is_seen(hidden_enemy.pos), "передумова: клітинка ворога нерозвідана")
	# Передумова другого роду: ІСТИННА карта зайнятості справді знає про
	# ворога тут — інакше тест нічого не доводить про розбіжність known/true.
	assert_true(service.state.occupied_map().has(hidden_enemy.pos), "передумова: ворог насправді там стоїть")
	assert_false(service.state.known_occupied_map(0).has(hidden_enemy.pos), "передумова: known про нього не знає")

	var zone_overlay := ZoneOverlay.new(board_view)
	var controller := InputController.new(service, zone_overlay)
	controller.action_preview.connect(overlay.show_preview)

	controller.tap_cell(mover.pos)
	controller.tap_cell(hidden_enemy.pos)  # тап по клітинці, де насправді стоїть невидимий ворог

	var drawn_cells: Array = []
	for seg in _segments(board_view.LAYER_PATH):
		if not drawn_cells.has(seg["cell"]):
			drawn_cells.append(seg["cell"])
	# Пряма лінія (5,6)->(5,7)->(5,8)->(5,9): known-карта не бачить перешкоди
	# на жодному з цих тайлів, тож known-шлях іде НАПРЯМУ, без жодного обходу.
	var expected: Array[Vector2i] = [Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9)]
	for cell in expected:
		assert_true(drawn_cells.has(cell), "%s: known-шлях мусить пройти прямою лінією через цей тайл" % cell)
	assert_eq(drawn_cells.size(), expected.size(), "жодного зайвого тайла — прямий шлях, не обхідний")
	assert_true(drawn_cells.has(hidden_enemy.pos),
		"шлях мусить включати клітинку невидимого ворога — рахований проти known, не true (R5)")
