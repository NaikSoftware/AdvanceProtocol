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
	assert_eq(layer.get_child_count(), 2, "моделі й кільця")
	# Інший спостерігач: своя міна P0 для P1 — нерозкрита ворожа, отже зникає.
	layer.rebuild(state, 1)
	assert_eq(layer.marker_count(), 0)
	assert_eq(layer.get_child_count(), 0)


## Бюджет викликів (§8): скільки б не було мін, шар малює їх одним MultiMesh на вигляд плюс один
## на кільця всіх власників.
func test_many_mines_are_one_multimesh_per_style_plus_rings() -> void:
	for i in 10:
		Mines.place(state, Vector2i(i % 8, i / 8), 0)
	Mines.place(state, Vector2i(5, 5), 1)
	state.mines[10].known_to[0] = true
	layer.rebuild(state, 0)
	assert_eq(layer.marker_count(), 11)
	var mmis: Array[Node] = layer.find_children("*", "MultiMeshInstance3D", false, false)
	assert_eq(mmis.size(), 3)
	var total: int = 0
	for m: MultiMeshInstance3D in mmis:
		total += m.multimesh.instance_count
		assert_eq(m.layers, 1 << (MineLayer.MARKER_LAYER - 1), "шар 3, не шар світу")
	assert_eq(total, 22, "11 моделей і 11 кілець")


## Чия міна — кільце кольору HP-смуги власника, а не колір моделі; свою й знайдену ворожу
## відрізняє ще й форма: закопана врівень проти відкопаної.
func test_rings_carry_the_owners_hp_colour() -> void:
	Mines.place(state, Vector2i(1, 1), 0)
	Mines.place(state, Vector2i(2, 2), 1)
	state.mines[1].known_to[0] = true
	layer.rebuild(state, 0)
	assert_eq(layer.marker_at(Vector2i(1, 1)).get_meta("ring_color"), UnitView.hp_fill_color(0))
	assert_eq(layer.marker_at(Vector2i(2, 2)).get_meta("ring_color"), UnitView.hp_fill_color(1))
	assert_ne(UnitView.hp_fill_color(0), UnitView.hp_fill_color(1))
	assert_eq((layer.get_node("Rings") as MultiMeshInstance3D).multimesh.instance_count, 2)


func test_enemy_mine_lies_exposed_and_own_is_flush() -> void:
	var own: AABB = MineLayer.mesh_of(MineLayer.Style.OWN).get_aabb()
	var enemy: AABB = MineLayer.mesh_of(MineLayer.Style.ENEMY_REVEALED).get_aabb()
	assert_eq(own.position.y, 0.0, "міна стоїть на землі")
	assert_gt(enemy.size.y, own.size.y)
	assert_gt(own.size.x, enemy.size.x * 0.8, "своя лежить у ширшій плямі розритого ґрунту")


func test_marker_sits_below_zone_contours() -> void:
	assert_lt(MineLayer.MARKER_Y, BoardView._CONTOUR_Y)


## §3.11: для не власника, що міну не знайшов, тайл з міною і без неї однаковий — шар не лишає
## нічого: ні вузла, ні MultiMesh, ні плями ґрунту (пляма живе лише в моделі власника).
func test_unrevealed_mine_leaves_no_trace_for_a_non_owner() -> void:
	layer.rebuild(state, 1)
	var without: Array = _tree_signature(layer)
	Mines.place(state, Vector2i(3, 3), 0)
	layer.rebuild(state, 1)
	assert_eq(_tree_signature(layer), without)
	assert_eq(without, [])
	# Знайдена ним — з'являється, і лише тоді.
	state.mines[0].known_to[1] = true
	layer.rebuild(state, 1)
	assert_ne(_tree_signature(layer), without)


func _tree_signature(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "", true, false):
		out.append([c.get_class(), c.name])
	return out
