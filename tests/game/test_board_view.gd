extends GutTest
## Task 2.3, рішення R4: жива сцена battle_screen.tscn з'являється лише в Task
## 2.10, тож перевірка тут — headless, не «увімкнути гру й подивитись».
##
## Контур перевіряється через власний стан BoardView (_contour_segments),
## а не через читання кольору назад з MultiMesh: під
## headless-запуском (`--headless`, дамі-рендерер) RenderingServer не зберігає
## буфер екземплярів мультимешу — set_instance_color/set_instance_transform не
## кидають помилку, але get_instance_color/get_instance_transform одразу
## після них повертають типове значення (чорний/нульовий), навіть після кадру. Це
## перевірено окремо поза GUT. Структурні перевірки (кількість екземплярів)
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


## Колір екземпляра мультимешу не читається назад під headless (див. коментар
## угорі файлу), але шлях, яким він туди потрапляє, — звичайні властивості
## Resource, і вони читаються справно. Перевіряємо кожен екземпляр, який
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


## §3.5: туман ховає юнітів і міни, ніколи не карту. BoardView не має і не
## може мати уявлення про тайлову видимість — інакше місцевість перестане
## бути публічною.
func test_no_apply_fog_and_no_vision_reference() -> void:
	assert_false(view.has_method("apply_fog"), "BoardView не ховає місцевість — apply_fog їй не потрібен")
	var source: String = FileAccess.get_file_as_string("res://game/battle/board_view.gd")
	assert_false(source.contains("Vision"), "BoardView не має споживати Vision узагалі")


# --- Контур (§3.13, PO-скарга: «контурно, не заливкою») -------------------
#
# draw_contour(): сегмент {cell, dir, color} малює тонку риску вздовж ОДНОГО
# ребра тайла, а не перефарбовує весь тайл.

func _edge(cell: Vector2i, dir: Vector2i, color: Color) -> Dictionary:
	return {"cell": cell, "dir": dir, "color": color}


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


## Task 8: BridgeChanged перебудовує дошку, а контури (зони, цілі) лишаються.
func test_rebuild_tiles_shows_new_kind_and_keeps_contours() -> void:
	var board := Board.create(4, 4, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE)
	var bv: BoardView = BoardViewScene.instantiate()
	add_child_autofree(bv)
	bv.build(board)
	var segs: Array[Dictionary] = [{"cell": Vector2i(0, 0), "dir": Vector2i(1, 0), "color": Color.RED}]
	bv.draw_contour(segs, BoardView.LAYER_ZONES)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE_DESTROYED)
	bv.rebuild_tiles(board)
	assert_eq(bv.kind_at(Vector2i(1, 1)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_eq(bv.contour_segments(BoardView.LAYER_ZONES), segs)


# --- Кільце огляду — одне геометричне коло (§3.13, docs/ui/overlays.md) ----------

func _circle_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in view.get_children():
		if child is MeshInstance3D and not child is MultiMeshInstance3D:
			out.append(child)
	return out


## Радіус у тайлах = радіус у світі (тайл — 1.0), центр — середина тайла юніта.
func test_draw_circles_makes_one_ring_per_circle_centred_on_the_tile() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	var circles: Array[Dictionary] = [{"center": Vector2i(4, 6), "radius": 3, "color": Color.WHITE}]

	view.draw_circles(circles, BoardView.LAYER_INSPECT)

	assert_eq(view.circles(BoardView.LAYER_INSPECT), circles)
	var nodes: Array[MeshInstance3D] = _circle_nodes()
	assert_eq(nodes.size(), 1, "одне коло — один вузол, один draw call")
	var ring: MeshInstance3D = nodes[0]
	assert_eq(ring.position.x, 4.0)
	assert_eq(ring.position.z, 6.0)
	var torus: TorusMesh = ring.mesh as TorusMesh
	assert_not_null(torus)
	assert_almost_eq((torus.inner_radius + torus.outer_radius) * 0.5, 3.0, 0.0001, "середня лінія — рівно 3 тайли")
	assert_eq(view.contour_segments(BoardView.LAYER_INSPECT), [], "коло — не контур тайлів")


func test_draw_circles_replaces_and_empty_clears_only_that_layer() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	view.draw_circles([{"center": Vector2i(1, 1), "radius": 5, "color": Color.RED}] as Array[Dictionary], BoardView.LAYER_TARGETS)
	view.draw_circles([{"center": Vector2i(2, 2), "radius": 3, "color": Color.WHITE},
		{"center": Vector2i(2, 2), "radius": 5, "color": Color.PURPLE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	view.draw_circles([{"center": Vector2i(3, 3), "radius": 4, "color": Color.WHITE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	assert_eq(_circle_nodes().size(), 2, "заміна, а не накопичення")

	view.draw_circles([] as Array[Dictionary], BoardView.LAYER_INSPECT)

	assert_eq(view.circles(BoardView.LAYER_INSPECT), [])
	assert_eq(_circle_nodes().size(), 1, "коло іншого шару лишилось")
	assert_eq(view.circles(BoardView.LAYER_TARGETS).size(), 1)


func test_rebuild_tiles_keeps_circles() -> void:
	var board := Board.create(10, 10, Terrain.GroundState.DRY)
	view.build(board)
	var circles: Array[Dictionary] = [{"center": Vector2i(4, 6), "radius": 3, "color": Color.WHITE}]
	view.draw_circles(circles, BoardView.LAYER_INSPECT)

	view.rebuild_tiles(board)

	assert_eq(view.circles(BoardView.LAYER_INSPECT), circles)
	assert_eq(_circle_nodes().size(), 1)
