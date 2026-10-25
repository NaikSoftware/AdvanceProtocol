extends GutTest
## Пропси поля бою (PropLayer): розстановка — чиста функція дошки, будівлі лише в групах BUILDING,
## дрібні пропси не в центрі клітинки, міст міняється з підривом, дах розчиняється над юнітом,
## розчавлене видно лише на розвіданому глядачем (§3.5).

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")
## Сторож від геометрії, що вийшла з-під контролю, а не бюджет (бюджет міряє tools/battle_budget).
const TRIS_GUARD: int = 150000
const ARMOURED_CAR: int = 2
const RIFLE: int = 0


func _view(map: MapData, board: Board = null) -> BoardView:
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	if map != null:
		view.ring_map = map
		view.surface = map.surface
		view.relief_seed = map.name_key.hash()
	view.build(board if board != null else map.to_board())
	return view


func _map(name: String) -> MapData:
	return load("res://maps/%s.tres" % name) as MapData


func _kind(model: StringName) -> int:
	return int(PropLayer.spec_of(model)["kind"])


func _is_small(model: StringName) -> bool:
	var k: int = _kind(model)
	return k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN and k != PropLayer.Kind.BRIDGE


func _snapshot(view: BoardView) -> Array:
	var out: Array = []
	for inst in view.props().all_instances():
		out.append([inst["model"], inst["transform"], inst["cells"]])
	return out


func test_same_board_gives_identical_props(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var first: Array = _snapshot(_view(m))
	assert_gt(first.size(), 0, "%s: пропси є" % p)
	assert_eq_deep(_snapshot(_view(m)), first)


## Слід будівлі (з метаданих GLB, повернутий) лежить цілком на клітинках BUILDING (руїна — RUBBLE)
## однієї карти разом із кільцем, а сама модель не виходить за слід далі за допуск ассета.
func test_structures_lie_wholly_inside_building_cells(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var view: BoardView = _view(m)
	var ring: int = Surroundings.ring_of(m)
	var world: Board = Surroundings.world_board(m.to_board(), m)
	var checked: int = 0
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN:
			continue
		var want: int = Terrain.Kind.BUILDING if k == PropLayer.Kind.STRUCTURE else Terrain.Kind.RUBBLE
		var info: Dictionary = PropLayer.model(inst["model"])
		var t: Transform3D = inst["transform"]
		var fp: Vector2i = info["footprint"]
		var x_axis: Vector3 = t.basis.x
		var size_r: Vector2i = fp if absf(x_axis.x) > 0.5 else Vector2i(fp.y, fp.x)
		var lo := Vector2(t.origin.x, t.origin.z) - Vector2(size_r - Vector2i.ONE) * 0.5
		for dy in size_r.y:
			for dx in size_r.x:
				var c := Vector2i(roundi(lo.x) + dx, roundi(lo.y) + dy)
				assert_eq(world.kind_at(c + Vector2i(ring, ring)), want, "%s: %s на %s" % [p, inst["model"], c])
		var box: AABB = t * (info["aabb"] as AABB)
		var rect := Rect2(lo - Vector2(0.5, 0.5), Vector2(size_r)).grow(0.1)
		assert_true(rect.encloses(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)),
				"%s: %s виходить за слід" % [p, inst["model"]])
		checked += 1
	assert_gt(checked, 0, "%s: будівлі є" % p)


## Дрібний пропс — лише на прохідній клітинці дошки і поза квадратом юніта в її центрі.
func test_nothing_small_on_a_unit_centre(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _view(m)
	var checked: int = 0
	for inst in view.props().all_instances():
		if not _is_small(inst["model"]):
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		assert_true(board.in_bounds(c), "%s: дрібний пропс поза дошкою" % p)
		var kind: int = board.kind_at(c)
		assert_true(kind in [Terrain.Kind.FIELD, Terrain.Kind.ROAD, Terrain.Kind.HILL],
				"%s: %s на непрохідному виді %d" % [p, inst["model"], kind])
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r: float = PropLayer.KEEP_OUT
		var hits: bool = box.position.x - c.x < r and box.end.x - c.x > -r and box.position.z - c.y < r and box.end.z - c.y > -r
		assert_false(hits, "%s: %s на %s заходить у центр" % [p, inst["model"], c])
		checked += 1
	assert_gt(checked, 0, "%s: дрібні пропси є" % p)


func test_bridge_swaps_when_demolished_and_back_when_repaired() -> void:
	var m: MapData = _map("river")
	var board: Board = m.to_board()
	var view: BoardView = _view(m, board)
	var cell := Vector2i(13, 10)
	assert_eq(view.props().instances_on(cell)[0]["model"], &"bridge_river_centre")
	assert_eq(view.props().instances_on(Vector2i(4, 10))[0]["model"], &"bridge_river_west")
	assert_eq(view.props().instances_on(Vector2i(21, 10))[0]["model"], &"bridge_river_east")
	board.set_kind(cell, Terrain.Kind.BRIDGE_DESTROYED)
	view.rebuild_tiles(board)
	assert_eq(view.props().instances_on(cell)[0]["model"], &"bridge_river_centre_broken")
	assert_eq(view.props().instances_on(Vector2i(4, 10))[0]["model"], &"bridge_river_west", "інша переправа ціла")
	board.set_kind(cell, Terrain.Kind.BRIDGE)
	view.rebuild_tiles(board)
	assert_eq(view.props().instances_on(cell)[0]["model"], &"bridge_river_centre")


## Настил збігається з дорогою: модель стоїть на deck_y мінус висота її настилу.
func test_bridge_deck_meets_the_road() -> void:
	var view: BoardView = _view(_map("river"))
	var inst: Dictionary = view.props().instances_on(Vector2i(13, 10))[0]
	var t: Transform3D = inst["transform"]
	assert_almost_eq(t.origin.y + 0.30, TerrainHeight.active.deck_y(Vector2i(13, 10)), 1e-4)
	assert_almost_eq(t.origin.x, 13.0, 1e-4)
	assert_almost_eq(t.origin.z, 10.0, 1e-4, "центр переправи 9–11")


## Переправа вздовж X: вісь моделі (локальна Z) повертається на світову X.
func test_bridge_follows_the_road_axis() -> void:
	var board := Board.create(6, 5, Terrain.GroundState.DRY)
	for x in 6:
		for y in [1, 2, 3]:
			board.set_kind(Vector2i(x, y), Terrain.Kind.WATER)
	board.set_kind(Vector2i(1, 2), Terrain.Kind.ROAD)
	board.set_kind(Vector2i(2, 2), Terrain.Kind.BRIDGE)
	board.set_kind(Vector2i(3, 2), Terrain.Kind.BRIDGE)
	board.set_kind(Vector2i(4, 2), Terrain.Kind.ROAD)
	var view: BoardView = _view(null, board)
	var on: Array[Dictionary] = view.props().instances_on(Vector2i(2, 2))
	assert_eq(on.size(), 1, "переправа в 2 клітинки має модель")
	if on.is_empty():
		return
	var z: Vector3 = (on[0]["transform"] as Transform3D).basis.z
	assert_almost_eq(absf(z.x), 1.0, 1e-4, "дорога йде по X")
	assert_eq_deep(view.props().instances_on(Vector2i(3, 2))[0]["model"], on[0]["model"])


func _house_board() -> Board:
	var board := Board.create(8, 8, Terrain.GroundState.DRY)
	for c: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]:
		board.set_kind(c, Terrain.Kind.BUILDING)
	return board


func _faded(view: BoardView, cell: Vector2i) -> bool:
	for inst in view.props().instances_on(cell):
		if inst["faded"]:
			return true
	return false


## Юніт на c розчиняє будівлі на c і на клітинках між ним і камерою (+x, +z); будинок за юнітом
## (з боку −x, −z) лишається суцільним.
func test_reveal_fades_the_cell_and_its_camera_side_neighbours_only() -> void:
	var view: BoardView = _view(null, _house_board())
	assert_false(view.props().instances_on(Vector2i(2, 2)).is_empty(), "передумова: будинок на групі 2×2")
	view.set_reveal_cells([Vector2i(1, 1)] as Array[Vector2i])
	assert_true(_faded(view, Vector2i(2, 2)), "будинок між юнітом і камерою")
	view.set_reveal_cells([Vector2i(4, 4)] as Array[Vector2i])
	assert_false(_faded(view, Vector2i(2, 2)), "будинок за юнітом не розчиняється")
	view.set_reveal_cells([Vector2i(3, 3)] as Array[Vector2i])
	assert_true(_faded(view, Vector2i(2, 2)), "юніт на клітинці будинку")


func test_reveal_replaces_the_previous_set() -> void:
	var view: BoardView = _view(null, _house_board())
	view.set_reveal_cells([Vector2i(2, 2)] as Array[Vector2i])
	assert_true(_faded(view, Vector2i(2, 2)))
	view.set_reveal_cells([] as Array[Vector2i])
	assert_false(_faded(view, Vector2i(2, 2)), "набір замінено, не доповнено")


## Розчинення й набір переживають перебудову мосту.
func test_reveal_survives_a_rebuild() -> void:
	var board := _house_board()
	var view: BoardView = _view(null, board)
	view.set_reveal_cells([Vector2i(2, 2)] as Array[Vector2i])
	view.rebuild_tiles(board)
	assert_true(_faded(view, Vector2i(2, 2)))


## Розчавлене — лише дрібні пропси, і лише на поданих клітинках; будинок не чавиться.
func test_crush_flattens_small_props_on_the_given_cells_only() -> void:
	var view: BoardView = _view(null, _house_board())
	var fence_cell := Vector2i(2, 1)
	var on: Array[Dictionary] = _fences_on(view, fence_cell)
	assert_eq(on.size(), 1, "огорожа під будинком")
	if on.is_empty():
		return
	assert_false(on[0]["crushed"])
	var before: Transform3D = on[0]["transform"]
	view.set_crushed_cells([fence_cell, Vector2i(2, 2)] as Array[Vector2i])
	var after: Dictionary = _fences_on(view, fence_cell)[0]
	assert_true(after["crushed"])
	assert_ne(after["transform"], before, "повалена огорожа лежить інакше")
	for inst in view.props().instances_on(Vector2i(2, 2)):
		assert_false(inst["crushed"], "будинок не чавиться")
	assert_false(_fences_on(view, Vector2i(2, 4))[0]["crushed"], "огорожа поруч ціла")


func _fences_on(view: BoardView, cell: Vector2i) -> Array[Dictionary]:
	return view.props().instances_on(cell).filter(
			func(i: Dictionary) -> bool: return _kind(i["model"]) == PropLayer.Kind.GARDEN_FENCE)


## Повалена опора забирає дроти своїх прольотів.
func test_crushed_pole_drops_its_wires() -> void:
	var view: BoardView = _view(_map("river"))
	var p: PropLayer = view.props()
	var spans: int = p.wire_spans()
	assert_gt(spans, 0, "на River є лінія")
	var pole_cell := Vector2i(-1, -1)
	for inst in p.all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.POLE:
			pole_cell = (inst["cells"] as Array)[0]
			break
	view.set_crushed_cells([pole_cell] as Array[Vector2i])
	assert_lt(p.wire_spans(), spans)


## Половини мають власний набір: та сама роль — інша модель (не віддзеркалена копія).
func test_halves_use_different_models() -> void:
	var view: BoardView = _view(_map("river"))
	var by_half: Array[Dictionary] = [{}, {}]
	var mid := Vector2(12.5, 10.5)
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.GARDEN_FENCE and k != PropLayer.Kind.HAY:
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		by_half[0 if c.y < mid.y else 1][inst["model"]] = true
	assert_false(by_half[0].is_empty() or by_half[1].is_empty(), "передумова: пропси на обох половинах")
	assert_ne(by_half[0].keys(), by_half[1].keys(), "половини різні")


## Лісові клітинки чекають на дерева: шар знає їх, але нічого на них не ставить.
func test_forest_cells_are_known_and_left_empty() -> void:
	var view: BoardView = _view(_map("river"))
	var forest: Array[Vector2i] = view.props().forest_cells
	assert_gt(forest.size(), 0)
	for c in forest:
		assert_true(view.props().instances_on(c).is_empty(), "у лісі %s поки нічого" % c)


## Міст кільця моделі не має: у нього нема й настилу, а правила його не бачать.
func test_ring_bridges_carry_no_prop() -> void:
	var view: BoardView = _view(_map("river"))
	var bridges: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.BRIDGE:
			bridges += 1
			for c: Vector2i in inst["cells"]:
				assert_true(c.x >= 0 and c.y >= 0 and c.x < 26 and c.y < 22, "міст %s поза дошкою" % c)
	assert_eq(bridges, 3, "три переправи дошки")


func test_props_have_no_runaway_geometry(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(_map(p))
	assert_lte(view.props().triangle_count(), TRIS_GUARD, p)


func test_one_multimesh_per_model(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(_map(p))
	var models: Dictionary = {}
	for inst in view.props().all_instances():
		models[inst["model"]] = true
	var mmis: Array[Node] = view.props().find_children("*", "MultiMeshInstance3D", false, false)
	assert_eq(mmis.size(), models.size(), p)
	for n in mmis:
		assert_true(models.has(StringName(n.name)), "%s: вузол %s" % [p, n.name])
		assert_eq((n as MultiMeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "§8: тіні лише юнітам")
		assert_eq((n as MultiMeshInstance3D).layers, 1, "світ: зонд відбиттів їх бачить")


## Будівлі кільця тонуть в імлі разом із землею: матеріал розчинення несе параметри кільця.
func test_ring_structures_take_the_haze() -> void:
	var view: BoardView = _view(_map("crossroads"))
	var mmi: MultiMeshInstance3D = view.props().get_node("house_h1")
	var mat: ShaderMaterial = mmi.material_override
	assert_true(mat.get_shader_parameter("surround"))


## Нова модель руїни стає в слот за префіксом імені.
func test_ruin_prefix_rule_takes_new_models() -> void:
	assert_eq(int(PropLayer.spec_of(&"ruin_half_h9")["kind"]), PropLayer.Kind.RUIN)
	assert_gt(int(PropLayer.spec_of(&"ruin_half_h9")["weight"]), int(PropLayer.spec_of(&"ruin_h1")["weight"]),
			"напівзруйнована — звичайна, повна руїна — рідкісна")


# --- екран бою: хто чавить і хто це бачить --------------------------------------------------

func _yard_map() -> MapData:
	var m := MapData.new()
	m.width = 14
	m.height = 6
	m.ground_state = Terrain.GroundState.DRY
	var tiles := PackedInt32Array()
	tiles.resize(m.width * m.height)
	tiles.fill(Terrain.Kind.FIELD)
	for x in range(2, 6):
		tiles[x] = Terrain.Kind.BUILDING
		tiles[4 * m.width + x] = Terrain.Kind.BUILDING
	m.tiles = tiles
	m.spawns = [
		{"type_id": ARMOURED_CAR, "owner": 0, "pos": Vector2i(1, 1), "facing": 2},
		{"type_id": RIFLE, "owner": 0, "pos": Vector2i(1, 3), "facing": 2},
		{"type_id": RIFLE, "owner": 1, "pos": Vector2i(13, 5), "facing": 6},
	] as Array[Dictionary]
	return m


func _move(service: Node, screen: BattleScreen, type_id: int, to: Vector2i) -> void:
	var unit: Unit = null
	for u: Unit in service.state.units_of(0):
		if u.type_id == type_id:
			unit = u
	assert_eq(service.submit(MoveCommand.create(unit.id, to)), "")
	await wait_until(func() -> bool: return unit.pos == to and not screen._event_player.is_playing(), 5.0)
	await wait_physics_frames(3)


func _crushed_on(screen: BattleScreen, cell: Vector2i) -> bool:
	var view: BoardView = screen.get_node("%BoardView")
	for inst in view.props().instances_on(cell):
		if inst["crushed"]:
			return true
	return false


func test_vehicle_crushes_infantry_does_not_and_the_enemy_never_sees_it_unscouted() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_yard_map(), 2, 1, service)
	var view: BoardView = screen.get_node("%BoardView")
	assert_false(view.props().instances_on(Vector2i(3, 1)).is_empty(), "передумова: огорожа під двором")
	assert_false(view.props().instances_on(Vector2i(3, 3)).is_empty(), "передумова: огорожа під другим двором")

	await _move(service, screen, ARMOURED_CAR, Vector2i(4, 1))
	await _move(service, screen, RIFLE, Vector2i(4, 3))
	assert_true(_crushed_on(screen, Vector2i(3, 1)), "техніка розчавила огорожу")
	assert_false(_crushed_on(screen, Vector2i(3, 3)), "піхота пройшла повз")
	assert_true(_faded(view, Vector2i(4, 4)), "дім між стрільцями й камерою розчинився")
	assert_false(_faded(view, Vector2i(4, 0)), "дім за машиною — ні")

	assert_false(service.state.vision[1].is_seen(Vector2i(3, 1)), "передумова: гравець 1 там не бував")
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	await wait_physics_frames(3)
	(screen.get_node("%HandoverGate").get_node("%ConfirmButton") as Button).pressed.emit()
	assert_false(_crushed_on(screen, Vector2i(3, 1)), "§3.5: уламки на нерозвіданому не видають танк")
	assert_false(_faded(view, Vector2i(4, 4)), "§3.5: прозорий дах не видає невидимих стрільців")


## Тінь сонця кидають лише будівлі й руїни і лише з увімкненим перемикачем.
func test_structure_shadows_only_when_switched_on() -> void:
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.structure_shadows = true
	view.build(_house_board())
	for n: MultiMeshInstance3D in view.props().find_children("*", "MultiMeshInstance3D", false, false):
		var k: int = _kind(StringName(n.name))
		var want: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k == PropLayer.Kind.STRUCTURE \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		assert_eq(n.cast_shadow, want, n.name)


## Сонячна карта вмикає тіні будівель, похмура River — ні.
func test_sunny_map_switches_structure_shadows_on(p = use_parameters([["crossroads", true], ["river", false]])) -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_map(p[0]), 2, 1, service)
	assert_eq((screen.get_node("%BoardView") as BoardView).structure_shadows, p[1], p[0])
