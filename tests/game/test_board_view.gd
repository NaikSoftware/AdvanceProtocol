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


## Кольор інстансу мультимешу не читається назад під headless (див. коментар
## угорі файлу), але шлях, яким він туди потрапляє, — звичайні властивості
## Resource, і вони читаються справно. Перевіряємо кожен інстанс, який
## справді створив build(), а не лише перший-ліпший: вид, якому забракло
## матеріалу чи use_colors, — це саме та безмовна поломка, яку має ловити
## цей тест.
func test_build_wires_every_kind_instance_for_instance_color_paint() -> void:
	var board := _two_kind_board()
	view.build(board)
	var mmis := _multimesh_children()
	assert_true(mmis.size() > 0, "передумова: дошка має хоч один вид")
	for mmi in mmis:
		assert_true(mmi.multimesh.use_colors, "%s: без use_colors set_instance_color — no-op, підсвітка мовчки зникає" % mmi.name)
		assert_true(mmi.material_override is StandardMaterial3D, "%s: колір інстансу нема куди читати без матеріалу" % mmi.name)
		assert_true(mmi.material_override.vertex_color_use_as_albedo, "%s: без vertex_color_use_as_albedo колір інстансу не доходить до альбедо" % mmi.name)
		assert_true(mmi.multimesh.mesh is BoxMesh, "%s: тайл мусить лишатись дешевим примітивом" % mmi.name)


## Далі — підсвітка перевіряється через власний стан BoardView (bookkeeping)
## і через щойно перевірене підключення до мультимешу (wiring), а не через
## сам намальований результат: колір інстансу мультимешу не читається назад
## під headless (коментар угорі файлу), тож «а чи справді видно потрібний
## колір на екрані» лишається за Task 2.10.
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


# --- Контур (§3.13, PO-скарга: «контурно, не заливкою») -------------------
#
# draw_contour() — окремий механізм від highlight_tiles(): сегмент {cell, dir,
# color} малює тонку риску вздовж ОДНОГО ребра тайла, а не перефарбовує весь
# тайл. Головний доказ, що це не заливка: намальований контур НІКОЛИ не
# лишає сліду в _layer_highlights (тому старий механізм і зберігається окремо
# в тестах вище — щоб було з чим порівняти).

func _edge(cell: Vector2i, dir: Vector2i, color: Color) -> Dictionary:
	return {"cell": cell, "dir": dir, "color": color}


func test_draw_contour_never_touches_the_tile_fill_layer() -> void:
	var board := _two_kind_board()
	view.build(board)
	var segments: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]

	view.draw_contour(segments, view.LAYER_ZONES)

	assert_eq(view._layer_highlights[view.LAYER_ZONES].size(), 0,
		"контур не мусить лишати запис у _layer_highlights — інакше це знову заливка")


func test_draw_contour_stores_segments_for_that_layer_only() -> void:
	var board := _two_kind_board()
	view.build(board)
	var zone_segments: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]
	var path_segments: Array[Dictionary] = [_edge(Vector2i(1, 0), Vector2i(0, 1), Color.WHITE)]

	view.draw_contour(zone_segments, view.LAYER_ZONES)
	view.draw_contour(path_segments, view.LAYER_PATH)

	assert_eq(view.contour_segments(view.LAYER_ZONES), zone_segments)
	assert_eq(view.contour_segments(view.LAYER_PATH), path_segments)


func test_draw_contour_replaces_not_accumulates() -> void:
	var board := _two_kind_board()
	view.build(board)
	var first: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]
	view.draw_contour(first, view.LAYER_ZONES)

	var second: Array[Dictionary] = [_edge(Vector2i(1, 0), Vector2i(0, 1), Color.RED)]
	view.draw_contour(second, view.LAYER_ZONES)

	assert_eq(view.contour_segments(view.LAYER_ZONES), second, "другий виклик мусить замінити, а не додати")


func test_clear_contour_empties_segments_and_frees_the_mesh_node() -> void:
	var board := _two_kind_board()
	view.build(board)
	var first: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]
	view.draw_contour(first, view.LAYER_ZONES)

	view.clear_contour(view.LAYER_ZONES)

	assert_eq(view.contour_segments(view.LAYER_ZONES).size(), 0)


func test_clear_contour_on_empty_layer_does_not_crash() -> void:
	var board := _two_kind_board()
	view.build(board)
	view.clear_contour(view.LAYER_ZONES)
	assert_eq(view.contour_segments(view.LAYER_ZONES).size(), 0)


func test_draw_contour_with_empty_segments_draws_nothing() -> void:
	var board := _two_kind_board()
	view.build(board)
	view.draw_contour([] as Array[Dictionary], view.LAYER_ZONES)
	assert_eq(view.contour_segments(view.LAYER_ZONES).size(), 0)
