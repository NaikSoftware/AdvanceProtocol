extends GutTest
## Task 4.5: шар мін малює рівно те, що знає спостерігач (§3.5, §3.11) —
## свої міни завжди, ворожі лише розкриті, нерозкриті — жодного вузла.

var layer: MineLayer
var state: BattleState


func before_each() -> void:
	layer = MineLayer.new()
	add_child_autofree(layer)
	state = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 2, 7)


func test_own_mines_always_drawn() -> void:
	Mines.place(state, Vector2i(3, 1), 0)
	Mines.place(state, Vector2i(5, 5), 0)
	layer.rebuild(state, 0)
	assert_eq(layer.marker_count(), 2)
	var m: Node3D = layer.marker_at(Vector2i(3, 1))
	assert_not_null(m)
	assert_eq(m.get_meta("style"), MineLayer.Style.OWN)
	assert_eq(m.position, IsoCameraRig.cell_to_world(Vector2i(3, 1)) + Vector3(0.0, MineLayer.MARKER_Y, 0.0))
	assert_null(layer.marker_at(Vector2i(4, 4)))


func test_revealed_enemy_mine_has_enemy_style() -> void:
	Mines.place(state, Vector2i(2, 2), 1)
	state.mines[0].known_to[0] = true
	layer.rebuild(state, 0)
	assert_eq(layer.marker_count(), 1)
	assert_eq(layer.marker_at(Vector2i(2, 2)).get_meta("style"), MineLayer.Style.ENEMY_REVEALED)


func test_unrevealed_enemy_mine_has_no_node() -> void:
	Mines.place(state, Vector2i(2, 2), 1)
	layer.rebuild(state, 0)
	assert_eq(layer.marker_count(), 0)
	assert_eq(layer.get_child_count(), 0)
	assert_null(layer.marker_at(Vector2i(2, 2)))


func test_rebuild_replaces_not_accumulates() -> void:
	Mines.place(state, Vector2i(1, 1), 0)
	layer.rebuild(state, 0)
	layer.rebuild(state, 0)
	assert_eq(layer.marker_count(), 1)
	assert_eq(layer.get_child_count(), 1)
	# Інший спостерігач: своя міна P0 для P1 — нерозкрита ворожа, отже зникає.
	layer.rebuild(state, 1)
	assert_eq(layer.marker_count(), 0)
	assert_eq(layer.get_child_count(), 0)
