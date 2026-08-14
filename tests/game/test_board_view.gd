extends GutTest
## Task 2.3, ruling R4: жива сцена battle_screen.tscn зʼявляється лише в Task
## 2.10, тож перевірка тут — headless, не «увімкнути гру й подивитись».
##
## Підсвітка перевіряється через власний стан BoardView (_layer_highlights,
## _resolve_color), а не через читання кольору назад з MultiMesh: під
## headless-запуском (`--headless`, дамі-рендерер) RenderingServer не зберігає
## буфер інстансів мультимешу — set_instance_color/set_instance_transform не
## кидають помилку, але get_instance_color/get_instance_transform одразу
## після них повертають дефолт (чорний/нульовий), навіть після кадру. Це
## перевірено окремо поза GUT. Структурні перевірки (кількість інстансів)
## лишаються — instance_count це звичайна властивість ресурсу, а не буфер RS.

const BoardViewScene := preload("res://game/battle/board_view.tscn")

var view: Node3D


func before_each() -> void:
	view = BoardViewScene.instantiate()
	add_child_autofree(view)


## Дошка з двома видами — ROAD і FIELD — щоб перевірити «один draw call на
## вид», а не просто «один draw call на дошку».
func _two_kind_board() -> Board:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	for x in board.width:
		board.set_kind(Vector2i(x, 1), Terrain.Kind.ROAD)
	return board


func _multimesh_children() -> Array:
	var out: Array = []
	for child in view.get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
	return out


func test_build_makes_one_multimesh_per_kind_present_and_covers_every_tile() -> void:
	var board := _two_kind_board()
	view.build(board)
	var mmis := _multimesh_children()
	assert_eq(mmis.size(), 2, "дошка має рівно два види: ROAD і FIELD")
	var total: int = 0
	for mmi in mmis:
		total += mmi.multimesh.instance_count
	assert_eq(total, board.width * board.height, "кількість інстансів разом мусить дорівнювати кількості тайлів")


func test_build_with_single_kind_makes_one_instance() -> void:
	var board := Board.create(3, 3, Terrain.GroundState.DRY)
	view.build(board)
	var mmis := _multimesh_children()
	assert_eq(mmis.size(), 1, "суцільне поле — один вид, один draw call")
	assert_eq(mmis[0].multimesh.instance_count, 9)


func test_build_handles_empty_board() -> void:
	var board := Board.create(0, 0, Terrain.GroundState.DRY)
	view.build(board)
	assert_eq(_multimesh_children().size(), 0, "порожня дошка — жодного виду, жодного інстансу")


func test_build_is_idempotent() -> void:
	var board := _two_kind_board()
	view.build(board)
	view.build(board)
	var mmis := _multimesh_children()
	assert_eq(mmis.size(), 2, "повторний build не мусить плодити нові MultiMeshInstance3D")
	var total: int = 0
	for mmi in mmis:
		total += mmi.multimesh.instance_count
	assert_eq(total, board.width * board.height, "повторний build не мусить подвоювати інстанси")


func test_highlight_layers_are_independent() -> void:
	var board := _two_kind_board()
	view.build(board)
	var zone_cell := Vector2i(0, 0)
	var target_cell := Vector2i(1, 0)
	view.highlight_tiles([zone_cell] as Array[Vector2i], Color.YELLOW, view.LAYER_ZONES)
	view.highlight_tiles([target_cell] as Array[Vector2i], Color.RED, view.LAYER_TARGETS)

	assert_eq(view._layer_highlights[view.LAYER_ZONES][zone_cell], Color.YELLOW)
	assert_eq(view._layer_highlights[view.LAYER_TARGETS][target_cell], Color.RED)
	assert_false(view._layer_highlights[view.LAYER_TARGETS].has(zone_cell), "ціль не мусить зʼявитись у шарі зон")
	assert_false(view._layer_highlights[view.LAYER_ZONES].has(target_cell), "зона не мусить зʼявитись у шарі цілей")

	# Додавання ще одного тайла в шар зон не мусить чіпати вже виставлений
	# шар цілей — саме заради цього шари незалежні.
	view.highlight_tiles([Vector2i(2, 0)] as Array[Vector2i], Color.YELLOW, view.LAYER_ZONES)
	assert_eq(view._layer_highlights[view.LAYER_TARGETS][target_cell], Color.RED, "зони не гасять підсвітку цілі")


func test_selection_layer_wins_over_zones_on_the_same_tile() -> void:
	var board := _two_kind_board()
	var cell := Vector2i(0, 0)
	var kind: int = board.kind_at(cell)
	view.build(board)

	view.highlight_tiles([cell] as Array[Vector2i], Color.YELLOW, view.LAYER_ZONES)
	assert_eq(view._resolve_color(cell, kind), Color.YELLOW)

	view.highlight_tiles([cell] as Array[Vector2i], Color.RED, view.LAYER_SELECTION)
	assert_eq(view._resolve_color(cell, kind), Color.RED, "SELECTION має пріоритет над ZONES — зони не гасять вибір")


func test_clear_highlights_clears_only_that_layer() -> void:
	var board := _two_kind_board()
	var cell := Vector2i(0, 0)
	var kind: int = board.kind_at(cell)
	view.build(board)
	var base_color: Color = view._resolve_color(cell, kind)

	view.highlight_tiles([cell] as Array[Vector2i], Color.YELLOW, view.LAYER_ZONES)
	view.highlight_tiles([cell] as Array[Vector2i], Color.RED, view.LAYER_SELECTION)

	view.clear_highlights(view.LAYER_SELECTION)
	assert_false(view._layer_highlights[view.LAYER_SELECTION].has(cell), "SELECTION мусить бути порожнім")
	assert_true(view._layer_highlights[view.LAYER_ZONES].has(cell), "ZONES не мали зникнути разом із SELECTION")
	assert_eq(view._resolve_color(cell, kind), Color.YELLOW, "після зняття SELECTION видимий колір — ZONES")

	view.clear_highlights(view.LAYER_ZONES)
	assert_false(view._layer_highlights[view.LAYER_ZONES].has(cell))
	assert_eq(view._resolve_color(cell, kind), base_color, "після зняття обох шарів — знову базовий колір тайлу")


func test_highlight_tiles_ignores_cells_outside_the_board() -> void:
	var board := _two_kind_board()
	view.build(board)
	var outside := Vector2i(99, 99)
	# Не мусить впасти — і не мусить лишити слід у жодному шарі, бо такої
	# клітинки на дошці немає.
	view.highlight_tiles([outside] as Array[Vector2i], Color.RED, view.LAYER_SELECTION)
	assert_false(view._layer_highlights[view.LAYER_SELECTION].has(outside))


## §3.5: туман ховає юнітів і міни, ніколи не карту. BoardView не має і не
## може мати уявлення про клітинкову видимість — інакше місцевість перестане
## бути публічною.
func test_no_apply_fog_and_no_vision_reference() -> void:
	assert_false(view.has_method("apply_fog"), "BoardView не ховає місцевість — apply_fog їй не потрібен")
	var source: String = FileAccess.get_file_as_string("res://game/battle/board_view.gd")
	assert_false(source.contains("Vision"), "BoardView не має споживати Vision узагалі")
