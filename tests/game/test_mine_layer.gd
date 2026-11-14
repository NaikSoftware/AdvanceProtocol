extends GutTest
## Task 4.5: шар мін малює рівно те, що знає спостерігач (§3.5, §3.11) —
## свої міни завжди, ворожі лише розкриті, нерозкриті — жодного вузла.

var layer: MineLayer
var state: BattleState


func before_each() -> void:
	TerrainHeight.active = null
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


## Бюджет викликів (§8): скільки б не було мін, шар малює їх одним MultiMesh на вигляд плюс
## одна сітка кілець усіх власників.
func test_many_mines_are_one_multimesh_per_style_plus_one_ring_mesh() -> void:
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
	var rings: MeshInstance3D = layer.get_node("Rings")
	assert_eq(rings.layers, 1 << (MineLayer.MARKER_LAYER - 1))
	assert_eq(rings.mesh.surface_get_array_len(0), 11 * 64)


## Чия міна — кільце кольору HP-смуги власника, а не колір моделі. Колір читається з масиву
## вершин сітки (під dummy-рендерером кольори MultiMesh не читаються назад), і кільце sRGB.
func test_rings_carry_the_owners_hp_colour_in_srgb() -> void:
	Mines.place(state, Vector2i(1, 1), 0)
	Mines.place(state, Vector2i(2, 2), 1)
	state.mines[1].known_to[0] = true
	layer.rebuild(state, 0)
	var rings: MeshInstance3D = layer.get_node("Rings")
	var colors: PackedColorArray = rings.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	# Кольори сітки стискаються до 8 біт на канал.
	for pair in [[colors[0], UnitView.hp_fill_color(0)], [colors[64], UnitView.hp_fill_color(1)]]:
		for ch in 3:
			assert_almost_eq(pair[0][ch], pair[1][ch], 0.01)
	assert_ne(UnitView.hp_fill_color(0), UnitView.hp_fill_color(1))
	assert_true((rings.material_override as StandardMaterial3D).vertex_color_is_srgb)


## Закопана врівень проти відкопаної: відкопана вища; ґрунтова пляма виходить за контактний пояс
## міни, тож закопану видно саме як міну в розритому ґрунті.
func test_enemy_mine_lies_exposed_and_own_is_flush() -> void:
	var own: AABB = MineLayer.mesh_of(MineLayer.Style.OWN).get_aabb()
	var enemy: AABB = MineLayer.mesh_of(MineLayer.Style.ENEMY_REVEALED).get_aabb()
	assert_gt(enemy.size.y, own.size.y)
	var contact_diameter: float = 2.0 * 0.15 * 1.15 * MineLayer.MINE_FACTOR / 8.0
	assert_gt(own.size.x, contact_diameter * 1.3, "пляма ґрунту ширша за міну")
	assert_gt(enemy.size.x, contact_diameter * 1.3)


## Модель вибирає покриття, яким дошку малює ґрунт: асфальт дороги — тверда (MultiMesh 2), ґрунтівка
## й звичайна земля — ґрунт (MultiMesh 0). Перевіряється, у якому саме MultiMesh лежить клітинка.
func test_the_model_follows_the_drawn_surface_not_the_tile_kind() -> void:
	state.board.set_kind(Vector2i(3, 3), Terrain.Kind.ROAD)
	state.board.set_kind(Vector2i(5, 3), Terrain.Kind.ROAD)
	var surf := PackedByteArray()
	surf.resize(8 * 8)
	surf[3 * 8 + 5] = MapData.RoadSurface.DIRT
	layer.surface = surf
	for p: Vector2i in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]:
		Mines.place(state, p, 0)
	layer.rebuild(state, 0)
	assert_true(layer.get_node("Mines_2").has_node("Mine_3_3"), "асфальт: тверда модель")
	assert_true(layer.get_node("Mines_0").has_node("Mine_4_3"), "поле: ґрунт")
	assert_true(layer.get_node("Mines_0").has_node("Mine_5_3"), "ґрунтівка: ґрунт")
	assert_false(layer.get_node("Mines_2").has_node("Mine_5_3"))
	assert_ne(MineLayer.mesh_of(MineLayer.Style.OWN, true), MineLayer.mesh_of(MineLayer.Style.OWN, false))


## На настилі моста, як і на асфальті, закопати нема куди.
func test_a_mine_on_a_bridge_deck_uses_the_hard_model() -> void:
	state.board.set_kind(Vector2i(2, 2), Terrain.Kind.BRIDGE)
	Mines.place(state, Vector2i(2, 2), 0)
	layer.rebuild(state, 0)
	assert_true(layer.get_node("Mines_2").has_node("Mine_2_2"))


## Збільшення міни живе у двох місцях (mine.py і MINE_FACTOR); тест звіряє їх по справжній моделі:
## верх корпусу відкопаної міни — 0,3 м × MINE_FACTOR × BODY_TAPER (верх конуса корпусу в mine.py
## вужчий за основу в 0,97 раза).
const BODY_TAPER: float = 0.97


func test_the_model_matches_the_mine_factor() -> void:
	var mesh: Mesh = MineLayer.mesh_of(MineLayer.Style.ENEMY_REVEALED)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# Корпус сягає найвище, ґрунт, грудки й валик — нижче половини висоти моделі: поріг береться з неї.
	var cutoff: float = mesh.get_aabb().size.y * 0.5
	var reach: float = 0.0
	for v: Vector3 in verts:
		if v.y > cutoff:
			reach = maxf(reach, Vector2(v.x, v.z).length())
	var expected: float = 0.3 * MineLayer.MINE_FACTOR * BODY_TAPER
	assert_almost_eq(reach * 2.0 * 8.0, expected, expected * 0.03)


## На мосту міна стоїть на настилі, а не на руслі під ним (так само, як юніт і контури).
func test_a_mine_on_a_bridge_sits_on_the_deck() -> void:
	var view: BoardView = preload("res://game/battle/board_view.tscn").instantiate()
	add_child_autofree(view)
	view.build((load("res://maps/river.tres") as MapData).to_board())
	var th: TerrainHeight = TerrainHeight.active
	var cell: Vector2i = th.bridge_groups()[0]["cells"][0]
	var bed: float = th.at(float(cell.x), float(cell.y))
	assert_gt(th.deck_y(cell), bed + 0.1, "передумова: настил над руслом")
	var st: BattleState = BattleState.create((load("res://maps/river.tres") as MapData).to_board(), 2, 7)
	Mines.place(st, cell, 0)
	layer.rebuild(st, 0)
	assert_almost_eq(layer.marker_at(cell).position.y, th.deck_y(cell) + MineLayer.MARKER_Y, 1e-4)


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
