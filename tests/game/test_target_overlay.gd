extends GutTest
## Task 8: контур довільного набору тайлів (цілі верби інженера, далі — дрон).
## Ребра — та сама логіка, що ZoneOverlay._edges.

const BoardViewScene := preload("res://game/battle/board_view.tscn")

var board_view: BoardView
var overlay: TargetOverlay


func before_each() -> void:
	board_view = BoardViewScene.instantiate()
	add_child_autofree(board_view)
	board_view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	overlay = TargetOverlay.new(board_view)


func test_show_tiles_draws_outer_edges_on_targets_layer() -> void:
	var tiles: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2)]
	overlay.show_tiles(tiles)
	var segs: Array = board_view.contour_segments(BoardView.LAYER_TARGETS)
	assert_eq(segs, ZoneOverlay._edges(tiles, TargetOverlay.COLOR))
	assert_eq(segs.size(), 6, "два сусідні тайли — 8 ребер мінус 2 спільні")
	assert_eq(board_view.contour_segments(BoardView.LAYER_ZONES), [], "зони не зачеплено")


func test_clear_and_empty_tiles_remove_contour() -> void:
	overlay.show_tiles([Vector2i(1, 1)] as Array[Vector2i])
	overlay.show_tiles([] as Array[Vector2i])
	assert_eq(board_view.contour_segments(BoardView.LAYER_TARGETS), [])
	overlay.show_tiles([Vector2i(1, 1)] as Array[Vector2i])
	overlay.clear()
	assert_eq(board_view.contour_segments(BoardView.LAYER_TARGETS), [])
