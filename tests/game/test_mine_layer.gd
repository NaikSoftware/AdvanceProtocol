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


## Бюджет викликів (§8): скільки б не було мін, шар малює їх по одному MultiMesh на вигляд.
func test_many_mines_are_one_multimesh_per_style() -> void:
	for i in 10:
		Mines.place(state, Vector2i(i % 8, i / 8), 0)
	Mines.place(state, Vector2i(5, 5), 1)
	state.mines[10].known_to[0] = true
	layer.rebuild(state, 0)
	assert_eq(layer.marker_count(), 11)
	var mmis: Array[Node] = layer.find_children("*", "MultiMeshInstance3D", false, false)
	assert_eq(mmis.size(), 2)
	var total: int = 0
	for m: MultiMeshInstance3D in mmis:
		total += m.multimesh.instance_count
		assert_eq(m.layers, 1 << (MineLayer.MARKER_LAYER - 1), "шар 3, не шар світу")
	assert_eq(total, 11)


## Свою й розкриту ворожу відрізняє форма, а не лише колір: у ворожої є огорожа з кілків вище за міну.
func test_enemy_marker_is_taller_and_wider_than_own() -> void:
	var own: Mesh = MineLayer.mesh_of(MineLayer.Style.OWN)
	var enemy: Mesh = MineLayer.mesh_of(MineLayer.Style.ENEMY_REVEALED)
	assert_gt(enemy.get_aabb().size.y, own.get_aabb().size.y * 2.0)
	assert_eq(own.get_aabb().position.y, 0.0, "міна стоїть на землі")
	assert_lt(MineLayer.MARKER_Y + enemy.get_aabb().size.y, 0.5)


func test_marker_sits_below_zone_contours() -> void:
	assert_lt(MineLayer.MARKER_Y, BoardView._CONTOUR_Y)
