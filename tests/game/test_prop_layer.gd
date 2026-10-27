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


## Карта -> побудований BoardView для тестів, що лише читають розстановку: побудова з рельєфом —
## кілька секунд, а таких тестів десятки.
var _views: Dictionary = {}


func _cached(name: String) -> BoardView:
	if not _views.has(name):
		var m: MapData = _map(name)
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		view.build(m.to_board())
		_views[name] = view
	return _views[name]


func after_all() -> void:
	for v: BoardView in _views.values():
		v.free()
	_views.clear()


func _map(name: String) -> MapData:
	return load("res://maps/%s.tres" % name) as MapData


## Вид моделі; −1 — не модель шару (город, вузол плям дотику чи грядок).
func _kind(model: StringName) -> int:
	return int(PropLayer.spec_of(model).get("kind", -1))


func _is_small(model: StringName) -> bool:
	var k: int = _kind(model)
	return k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN and k != PropLayer.Kind.BRIDGE


func _snapshot(view: BoardView) -> Array:
	var out: Array = []
	for inst in view.props().all_instances():
		out.append([inst["model"], inst["transform"], inst["cells"]])
	# Мережа теж чиста функція дошки: прольоти, відводи й підстанції.
	var props: PropLayer = view.props()
	out.append([props._spans, props._drops, props._transformers.keys()])
	return out


func test_same_board_gives_identical_props(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var first: Array = _snapshot(_cached(p))
	assert_gt(first.size(), 0, "%s: пропси є" % p)
	assert_eq_deep(_snapshot(_view(m)), first)


## Слід будівлі (з метаданих GLB, повернутий) лежить цілком на клітинках BUILDING (руїна — RUBBLE)
## однієї карти разом із кільцем, а сама модель не виходить за слід далі за допуск ассета.
func test_structures_lie_wholly_inside_building_cells(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var view: BoardView = _cached(p)
	var ring: int = Surroundings.ring_of(m)
	var world: Board = Surroundings.world_board(m.to_board(), m)
	var checked: int = 0
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN:
			continue
		if (PropLayer.RING_LANDMARKS.get(StringName(p), {}) as Dictionary).get("model", &"") == inst["model"]:
			continue                                                   # орієнтир кільця стоїть на вільному полі за краєм: це декорація без правил
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


## Між будь-якими двома будівлями (зі звісом даху) — щонайменше STRUCTURE_GAP (1 м); окремість на
## екрані стереже інший тест. Двірське вбрання (зменшена повітка) — не будівля.
func test_structures_keep_their_gap(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var rects: Array = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN:
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		if inst.get("yard", false):
			continue
		# Кожна межа розширена на пів проміжку: перетин означає вужчий прохід.
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(PropLayer.STRUCTURE_GAP * 0.5 - 1e-4)
		var ruin: bool = k == PropLayer.Kind.RUIN
		for o: Array in rects:
			# Руїни прив'язані кожна до своєї клітинки RUBBLE; правило стереже будинки.
			if ruin and o[1]:
				continue
			assert_false(r.intersects(o[0]), "%s: %s ближче за проміжок до сусіда" % [p, inst["model"]])
		rects.append([r, ruin])


## Дрібний пропс — лише на прохідній клітинці дошки і поза квадратом юніта в її центрі.
func test_nothing_small_on_a_unit_centre(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _cached(p)
	var checked: int = 0
	for inst in view.props().all_instances():
		# Двірське вбрання стоїть на клітинці BUILDING, як і будинок; правило — для прохідних клітинок.
		# Опори ЛЕП ідуть і за дошку, і між хатами, тож для них своє правило (test_poles_keep_off_...).
		if not _is_small(inst["model"]) or inst.get("yard", false) or _kind(inst["model"]) == PropLayer.Kind.POLE:
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		assert_true(board.in_bounds(c), "%s: дрібний пропс поза дошкою" % p)
		var kind: int = board.kind_at(c)
		# Огорожа двору може стояти й на порожній клітинці BUILDING за межею ділянки.
		var allowed: Array = [Terrain.Kind.FIELD, Terrain.Kind.ROAD, Terrain.Kind.HILL]
		if _kind(inst["model"]) == PropLayer.Kind.GARDEN_FENCE:
			allowed.append(Terrain.Kind.BUILDING)
		assert_true(kind in allowed, "%s: %s на виді %d" % [p, inst["model"], kind])
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
	assert_eq(view.props().instances_on(cell)[0]["model"], &"bridge_river_centre_broken#1", "підірвана клітинка — руїна")
	assert_eq(view.props().instances_on(Vector2i(13, 9))[0]["model"], &"bridge_river_centre#0",
			"сусідня клітинка тієї ж переправи лишається цілою: її не треба відновлювати")
	assert_eq(view.props().instances_on(Vector2i(13, 11))[0]["model"], &"bridge_river_centre#2")
	assert_eq(view.props().instances_on(Vector2i(4, 10))[0]["model"], &"bridge_river_west", "інша переправа ціла")
	for c: Vector2i in [Vector2i(13, 9), Vector2i(13, 10), Vector2i(13, 11)]:
		assert_eq(view.props().instances_on(c).size(), 1, "%s: рівно один шматок" % c)
	board.set_kind(cell, Terrain.Kind.BRIDGE)
	view.rebuild_tiles(board)
	assert_eq(view.props().instances_on(cell)[0]["model"], &"bridge_river_centre")


## Настил збігається з дорогою: модель стоїть на deck_y мінус висота її настилу.
## Шматок мосту обрізано рівно по межі своєї клітинки.
func test_bridge_segments_stay_inside_their_cell() -> void:
	for name: String in ["bridge_river_centre#0", "bridge_river_centre#1", "bridge_river_centre_broken#2", "bridge_river_west#1"]:
		var info: Dictionary = PropLayer.model(StringName(name))
		var box: AABB = info["aabb"]
		var k: int = int(name.get_slice("#", 1))
		var length: float = 3.0 if name.begins_with("bridge_river_centre") else 2.0
		assert_gt(int(info["tris"]), 0, name)
		assert_gte(box.position.z, -length * 0.5 + k - 1e-4, name)
		assert_lte(box.end.z, -length * 0.5 + k + 1.0 + 1e-4, name)


func test_bridge_deck_meets_the_road() -> void:
	var view: BoardView = _cached("river")
	var inst: Dictionary = view.props().instances_on(Vector2i(13, 10))[0]
	var t: Transform3D = inst["transform"]
	assert_almost_eq(t.origin.y + 0.30, view._height.deck_y(Vector2i(13, 10)), 1e-4)
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


## Одна клітинка BUILDING: ділянка двору однозначна — рівно ця клітинка.
func _yard_board() -> Board:
	var board := Board.create(8, 8, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(3, 3), Terrain.Kind.BUILDING)
	return board


const _YARD_SIDES: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 4), Vector2i(2, 3), Vector2i(4, 3)]


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
## Клітинка групи з будинком, з найменшими координатами (будинок може не вкрити всю групу).
func _house_cell(view: BoardView) -> Vector2i:
	for c: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]:
		if not view.props().instances_on(c).filter(
				func(i: Dictionary) -> bool: return _kind(i["model"]) == PropLayer.Kind.STRUCTURE).is_empty():
			return c
	return Vector2i(-1, -1)


func test_reveal_fades_the_cell_and_its_camera_side_neighbours_only() -> void:
	var view: BoardView = _view(null, _house_board())
	var h: Vector2i = _house_cell(view)
	assert_ne(h, Vector2i(-1, -1), "передумова: будинок на групі 2×2")
	view.set_reveal_cells([h - Vector2i(1, 1)] as Array[Vector2i])
	assert_true(_faded(view, h), "будинок між юнітом і камерою")
	view.set_reveal_cells([Vector2i(5, 5)] as Array[Vector2i])
	assert_false(_faded(view, h), "будинок за юнітом не розчиняється")
	view.set_reveal_cells([h] as Array[Vector2i])
	assert_true(_faded(view, h), "юніт на клітинці будинку")


func test_reveal_replaces_the_previous_set() -> void:
	var view: BoardView = _view(null, _house_board())
	var h: Vector2i = _house_cell(view)
	view.set_reveal_cells([h] as Array[Vector2i])
	assert_true(_faded(view, h))
	view.set_reveal_cells([] as Array[Vector2i])
	assert_false(_faded(view, h), "набір замінено, не доповнено")


## Розчинення й набір переживають перебудову мосту.
func test_reveal_survives_a_rebuild() -> void:
	var board := _house_board()
	var view: BoardView = _view(null, board)
	var h: Vector2i = _house_cell(view)
	view.set_reveal_cells([h] as Array[Vector2i])
	view.rebuild_tiles(board)
	assert_true(_faded(view, h))


## Розчавлене — лише дрібні пропси, і лише на поданих клітинках; будинок не чавиться.
func test_crush_flattens_small_props_on_the_given_cells_only() -> void:
	var view: BoardView = _view(null, _yard_board())
	var fenced: Array[Vector2i] = []
	for c: Vector2i in _YARD_SIDES:
		if not _fences_on(view, c).is_empty():
			fenced.append(c)
	assert_gte(fenced.size(), 3, "двір обгороджено, хвіртка — одна")
	var fence_cell: Vector2i = fenced[0]
	var other: Vector2i = fenced[1]
	var on: Array[Dictionary] = _fences_on(view, fence_cell)
	assert_eq(on.size(), 1, "огорожа під будинком")
	if on.is_empty():
		return
	assert_false(on[0]["crushed"])
	var before: Transform3D = on[0]["transform"]
	view.set_crushed_cells([fence_cell, Vector2i(3, 3)] as Array[Vector2i])
	var after: Dictionary = _fences_on(view, fence_cell)[0]
	assert_true(after["crushed"])
	assert_ne(after["transform"], before, "повалена огорожа лежить інакше")
	for inst in view.props().instances_on(Vector2i(3, 3)):
		assert_false(inst["crushed"], "будинок не чавиться")
	assert_false(_fences_on(view, other)[0]["crushed"], "огорожа поруч ціла")


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
	var view: BoardView = _cached("river")
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
	var view: BoardView = _cached("river")
	var forest: Array[Vector2i] = view.props().forest_cells
	assert_gt(forest.size(), 0)
	for c in forest:
		assert_true(view.props().instances_on(c).is_empty(), "у лісі %s поки нічого" % c)


## Міст кільця моделі не має: у нього нема й настилу, а правила його не бачать.
func test_ring_bridges_carry_no_prop() -> void:
	var view: BoardView = _cached("river")
	var bridges: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.BRIDGE:
			bridges += 1
			for c: Vector2i in inst["cells"]:
				assert_true(c.x >= 0 and c.y >= 0 and c.x < 26 and c.y < 22, "міст %s поза дошкою" % c)
	assert_eq(bridges, 3, "три переправи дошки")


func test_props_have_no_runaway_geometry(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	assert_lte(view.props().triangle_count(), TRIS_GUARD, p)


func test_one_multimesh_per_model(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var models: Dictionary = {}
	for inst in view.props().all_instances():
		models[inst["model"]] = true
	var mmis: Array[Node] = view.props().find_children("*", "MultiMeshInstance3D", false, false).filter(
			func(n: Node) -> bool: return not n.name in [&"ContactShadows", &"GardenBeds", &"HouseGrime", &"RubbleFloors", &"RubbleDebris", &"YardPaths", &"Transformers", &"GatePosts", &"SmallBoxes"] and not String(n.name).ends_with("_fade"))
	# Модель — вузол дошки й, для будівель кільця, ще «модель_ring» (кільце відсікається окремо).
	var keys: Dictionary = {}
	for n in mmis:
		var m := StringName(String(n.name).trim_suffix("_ring"))
		assert_true(models.has(m), "%s: вузол %s" % [p, n.name])
		keys[m] = true
	assert_eq(keys.size(), models.size(), p)
	for n in mmis:
		assert_eq((n as MultiMeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "§8: тіні лише юнітам")
		assert_eq((n as MultiMeshInstance3D).layers, 1, "світ: зонд відбиттів їх бачить")


## Будівлі кільця тонуть в імлі разом із землею: матеріал розчинення несе параметри кільця.
func test_ring_structures_take_the_haze() -> void:
	var view: BoardView = _cached("crossroads")
	var mmi: MultiMeshInstance3D = null
	for n: MultiMeshInstance3D in view.props().find_children("*", "MultiMeshInstance3D", false, false):
		if n.name != &"ContactShadows" and _kind(StringName(n.name)) == PropLayer.Kind.STRUCTURE:
			mmi = n
	var mat: ShaderMaterial = mmi.material_override
	assert_true(mat.get_shader_parameter("surround"))


func _length(inst: Dictionary) -> float:
	var b: Basis = (inst["transform"] as Transform3D).basis
	return b.x.length()


## Огорожа двору — замкнений контур довкола ділянки з однією хвірткою ~3.6 м: секція стоїть на кожному
## ребрі, і рівно одна з них коротша на хвіртку.
func test_yard_fence_closes_the_yard_with_one_gate() -> void:
	var view: BoardView = _view(null, _yard_board())
	assert_false(view.props().instances_on(Vector2i(3, 3)).is_empty(), "передумова: будинок на клітинці")
	var fenced: int = 0
	var total: float = 0.0
	for c: Vector2i in _YARD_SIDES:
		var on: Array[Dictionary] = _fences_on(view, c)
		fenced += 1 if not on.is_empty() else 0
		for i in on:
			total += _length(i)
	assert_eq(fenced, 4, "кожне ребро обгороджене")
	# Повний контур ділянки 1×1 з опуклими кутами — 4 × (1 + 2·YARD_OUT); хвіртка забирає GATE.
	var full: float = 4.0 * (1.0 + 2.0 * PropLayer.YARD_OUT)
	assert_almost_eq(total, full - PropLayer.GATE, 0.02, "одна хвіртка на весь контур")
	var models: Dictionary = {}
	for inst in view.props().all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.GARDEN_FENCE:
			models[inst["model"]] = true
	assert_eq(models.size(), 1, "один тип огорожі на двір")


## Хвіртка — у бік дороги, коли дорога поруч.
func test_yard_gate_faces_the_road() -> void:
	var board := _yard_board()
	board.set_kind(Vector2i(3, 4), Terrain.Kind.ROAD)
	var view: BoardView = _view(null, board)
	# Бік до дороги лишається відкритим (паркан ніколи не стає на покриття, і там хвіртка); решта
	# трьох боків обгороджена цілком.
	assert_true(_fences_on(view, Vector2i(3, 4)).is_empty(), "на дорозі паркана нема")
	var total: float = 0.0
	for c: Vector2i in [Vector2i(3, 2), Vector2i(2, 3), Vector2i(4, 3)]:
		for i in _fences_on(view, c):
			total += _length(i)
	assert_almost_eq(total, 3.0 * (1.0 + 2.0 * PropLayer.YARD_OUT), 0.02, "хвіртка — на дорогу, решта обгороджена")


## Під брилами, блоками й руїнами — пляма дотику, одним вузлом.
func test_boulders_get_contact_blobs() -> void:
	var view: BoardView = _cached("ridge")
	var stones: int = 0
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		stones += 1 if k in [PropLayer.Kind.BOULDER, PropLayer.Kind.BLOCK, PropLayer.Kind.RUIN] else 0
	var blobs: MultiMeshInstance3D = view.props().get_node("ContactShadows")
	assert_eq(blobs.multimesh.instance_count, stones)
	# Дзеркальний базис перевертає обхід трикутників, і cull_back викидає пляму зовсім.
	for i in blobs.multimesh.instance_count:
		assert_gt(blobs.multimesh.get_instance_transform(i).basis.determinant(), 0.0, "пляма %d дзеркальна" % i)


## Перелік моделей — через ResourceLoader, тож працює й в експортованій збірці.
func test_model_discovery_is_export_safe() -> void:
	var src: String = (load("res://game/battle/prop_layer.gd") as Script).source_code
	assert_false(src.contains("DirAccess"), "DirAccess не бачить .glb в експорті")
	assert_true(PropLayer.models_of(PropLayer.Kind.RUIN).size() >= 2)


## Нова модель руїни стає в слот за префіксом імені.
func test_ruin_prefix_rule_takes_new_models() -> void:
	assert_eq(int(PropLayer.spec_of(&"ruin_half_h9")["kind"]), PropLayer.Kind.RUIN)
	assert_gt(int(PropLayer.spec_of(&"ruin_half_h9")["weight"]), int(PropLayer.spec_of(&"ruin_h1")["weight"]),
			"напівзруйнована — звичайна, повна руїна — рідкісна")


# --- екран бою: хто чавить і хто це бачить --------------------------------------------------

func _yard_map() -> MapData:
	var m := MapData.new()
	m.width = 14
	m.height = 8
	m.ground_state = Terrain.GroundState.DRY
	var tiles := PackedInt32Array()
	tiles.resize(m.width * m.height)
	tiles.fill(Terrain.Kind.FIELD)
	# Двори на одну клітинку: будинок стоїть рівно там, а секція огорожі — на клітинці перед ним
	# (хвіртка лише вкорочує її), на шляху машини (3,2) і стрільців (4,4).
	tiles[1 * m.width + 3] = Terrain.Kind.BUILDING
	tiles[5 * m.width + 4] = Terrain.Kind.BUILDING
	m.tiles = tiles
	m.spawns = [
		{"type_id": ARMOURED_CAR, "owner": 0, "pos": Vector2i(1, 2), "facing": 2},
		{"type_id": RIFLE, "owner": 0, "pos": Vector2i(1, 4), "facing": 2},
		{"type_id": RIFLE, "owner": 1, "pos": Vector2i(13, 7), "facing": 6},
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


func _structure_cell(view: BoardView, cells: Array[Vector2i]) -> Vector2i:
	for c in cells:
		if not view.props().instances_on(c).filter(
				func(i: Dictionary) -> bool: return _kind(i["model"]) == PropLayer.Kind.STRUCTURE).is_empty():
			return c
	return Vector2i(-1, -1)


func _fenced_of(view: BoardView, cells: Array[Vector2i]) -> Vector2i:
	for c in cells:
		if not _fences_on(view, c).is_empty():
			return c
	return Vector2i(-1, -1)


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
	var car_cell := Vector2i(3, 2)
	var rifle_cell := Vector2i(4, 4)
	assert_false(_fences_on(view, car_cell).is_empty(), "передумова: огорожа під двором")
	assert_false(_fences_on(view, rifle_cell).is_empty(), "передумова: огорожа під другим двором")

	await _move(service, screen, ARMOURED_CAR, Vector2i(4, 2))
	await _move(service, screen, RIFLE, Vector2i(4, 4))
	assert_true(_crushed_on(screen, car_cell), "техніка розчавила огорожу")
	assert_false(_crushed_on(screen, rifle_cell), "піхота пройшла повз")
	# Стрільці на (4,4): будинок (4,5) стоїть між ними й камерою; будинок (3,1) — за машиною.
	var south := Vector2i(4, 5)
	var north := Vector2i(3, 1)
	assert_ne(_structure_cell(view, [south]), Vector2i(-1, -1), "передумова: будинок між стрільцями й камерою")
	assert_true(_faded(view, south), "дім між стрільцями й камерою розчинився")
	assert_false(_faded(view, north), "дім за машиною — ні")

	assert_false(service.state.vision[1].is_seen(car_cell), "передумова: гравець 1 там не бував")
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	await wait_physics_frames(3)
	(screen.get_node("%HandoverGate").get_node("%ConfirmButton") as Button).pressed.emit()
	assert_false(_crushed_on(screen, car_cell), "§3.5: уламки на нерозвіданому не видають танк")
	assert_false(_faded(view, south), "§3.5: прозорий дах не видає невидимих стрільців")


## Тінь сонця кидають пропси (крім мостів і каміння) і лише з увімкненим перемикачем.
func test_structure_shadows_only_when_switched_on() -> void:
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.structure_shadows = true
	view.build(_house_board())
	for n: MultiMeshInstance3D in view.props().find_children("*", "MultiMeshInstance3D", false, false):
		# Вузол «_fade» (напівпрозорі екземпляри) кидає тінь, як і суцільний вузол своєї моделі.
		var base: String = String(n.name).trim_suffix("_fade")
		var k: int = _kind(StringName(base))
		# Тінь кидають лише будинки дошки; руїни — плямою дотику, кільце й дрібнота — без тіні.
		var casts: bool = k == PropLayer.Kind.STRUCTURE and not base.ends_with("_ring")
		var want: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		assert_eq(n.cast_shadow, want, n.name)


## Сонячна карта вмикає тіні будівель, похмура River — ні.
func test_sunny_map_switches_structure_shadows_on(p = use_parameters([["crossroads", true], ["ridge", true], ["river", false]])) -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_map(p[0]), 2, 1, service)
	assert_eq((screen.get_node("%BoardView") as BoardView).structure_shadows, p[1], p[0])


## Огорожа двору стоїть лише довкола садиби (на карті з макетом — на клітинці її двору) чи групи,
## де є будівля: порожній обгороджений двір читається уламком огорожі серед поля.
func test_only_built_yards_are_fenced(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _cached(p)
	# Забудована — клітинка BUILDING із будинком, двірським вбранням чи городом, або двір садиби.
	var built: Dictionary = _layout_yards(p, false)
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if board.kind_at(c) == Terrain.Kind.BUILDING and not view.props().instances_on(c).is_empty():
				built[c] = true
	var fences: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		var has_built: bool = built.has(c)
		for d in Board.DIRS_4:
			has_built = has_built or built.has(c + d)
		assert_true(has_built, "%s: огорожа на %s не при будинку" % [p, c])
		fences += 1
	assert_gt(fences, 0, "%s: передумова — двори обгороджені" % p)


## Огорожа двору доходить до стіни, але не заходить під обрис будівлі (зі звісом даху) і тримається
## 0.3 клітинки від вежі; вежа — 0.5 від будівель.
func test_fences_and_towers_keep_clear(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var towers: Array[Rect2] = []
	var houses: Array[Rect2] = []
	var fences: Array[Rect2] = []
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if bool(s.get("tower", false)):
			towers.append(r)
		elif int(s["kind"]) == PropLayer.Kind.STRUCTURE or int(s["kind"]) == PropLayer.Kind.RUIN:
			houses.append(r)
		elif int(s["kind"]) == PropLayer.Kind.GARDEN_FENCE:
			fences.append(r)
	assert_gt(fences.size(), 0, "%s: передумова — огорожі є" % p)
	for f in fences:
		for b in houses:
			assert_false(b.grow(-0.01).intersects(f), "%s: огорожа %s заходить у будівлю %s" % [p, f, b])
		for b in towers:
			assert_false(b.grow(0.3 - 1e-4).intersects(f), "%s: огорожа %s ближче 0.3 клітинки до вежі %s" % [p, f, b])
	for t in towers:
		for b in houses:
			assert_false(t.grow(0.5 - 1e-4).intersects(b), "%s: вежа ближче 0.5 клітинки до будівлі" % p)



## З камери гри будівлі не накладаються на екрані й не торкаються (≥ 0.3 клітинки землі між
## силуетами, і по діагоналі теж — так злиплися руїна й хата на південному заході Crossroads), хіба
## що одна далеко за іншою вглиб: ближча
## будівля інакше ховає звіс дальшої, і дві читаються однією, хоч згори між ними й 2 м.
func test_buildings_never_overlap_on_screen(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var proj: Array = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if (k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN) or inst.get("yard", false):
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var scr: Array = PropLayer._Placer._screen_of(Rect2(box.position.x, box.position.z, box.size.x, box.size.z), box.size.y)
		scr.append(k == PropLayer.Kind.RUIN)
		for o: Array in proj:
			# Руїни прив'язані кожна до своєї клітинки RUBBLE; правило стереже будинки.
			if scr[2] and o[2]:
				continue
			# Між силуетами — щонайменше SCREEN_GROUND землі (кути, що торкаються, теж злипаються).
			# Між хатою й руїною — менший запас: руїна низька, силует не злипається.
			var margin: float = PropLayer.SCREEN_GROUND_RUIN if (scr[2] or o[2]) else PropLayer.SCREEN_GROUND
			var overlap: bool = (scr[0] as Rect2).grow(margin - 1e-4).intersects(o[0])
			assert_false(overlap and PropLayer._Placer._depth_gap(scr[1], o[1]) < PropLayer.SCREEN_DEPTH_SEP,
					"%s: %s накладається на сусіда на екрані" % [p, inst["model"]])
		proj.append(scr)


## Одна вежа на карту, і жодна будівля не стоїть поруч із нею.
func test_one_tower_per_map_in_its_own_lot(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var towers: Array[Vector2i] = []
	var others: Dictionary = {}
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if (k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN) or inst.get("yard", false):
			continue
		for c: Vector2i in inst["cells"]:
			if bool(PropLayer.spec_of(inst["model"]).get("tower", false)):
				towers.append(c)
			else:
				others[c] = true
	assert_lte(towers.size(), 1, p)
	for t in towers:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				assert_false(others.has(t + Vector2i(dx, dy)), "%s: будівля поруч із вежею" % p)


## Однакові моделі не стоять у сусідніх клітинках, і двоповерхових — не більше половини.
func test_villages_are_varied(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var at: Dictionary = {}
	var houses: int = 0
	var tall: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.STRUCTURE or inst.get("yard", false):
			continue
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		if not bool(s.get("tower", false)):
			houses += 1
			tall += 1 if int(s.get("storeys", 1)) >= 2 else 0
		for c: Vector2i in inst["cells"]:
			at[c] = [inst["model"], inst]
	for c: Vector2i in at:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if at.has(n) and at[n][1] != at[c][1]:
					assert_ne(at[n][0], at[c][0], "%s: дві %s поруч" % [p, at[c][0]])
	assert_lte(tall * 2, houses, "%s: двоповерхових більше половини" % p)


## Кожна клітинка RUBBLE дошки показує руїну; неприйнята модель не стає нікуди.
func test_every_rubble_cell_shows_a_ruin(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _cached(p)
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if board.kind_at(c) != Terrain.Kind.RUBBLE:
				continue
			var ruins: Array = view.props().instances_on(c).filter(
					func(i: Dictionary) -> bool: return _kind(i["model"]) == PropLayer.Kind.RUIN)
			assert_eq(ruins.size(), 1, "%s: руїна на %s" % [p, c])
	for inst in view.props().all_instances():
		assert_false(PropLayer.RETIRED.has(inst["model"]), "%s: неприйнята %s" % [p, inst["model"]])


## Відбиток будівель River: розстановка та сама в кожному процесі, а не лише в межах одного
## (сортування StringName за вказівником міняло вибір моделей між запусками). Число міняють лише
## разом зі свідомою зміною таблиці моделей чи правил розстановки.
const RIVER_BUILDINGS_FINGERPRINT: int = 1817935571


func test_river_buildings_match_the_golden_fingerprint() -> void:
	var view: BoardView = _cached("river")
	var parts: PackedStringArray = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var c: Vector2i = (inst["cells"] as Array)[0]
			parts.append("%s@%d,%d" % [inst["model"], c.x, c.y])
	parts.sort()
	assert_eq(";".join(parts).hash(), RIVER_BUILDINGS_FINGERPRINT, ";".join(parts))


## §8: кожна клітинка BUILDING дошки видимо забудована — будівлею, двором садиби з макету (за
## парканом) чи луком між садибами з макету, а не голою травою серед поля; і навпаки, кожна клітинка
## макета — справді BUILDING: макет не малює садибу там, де правила бачать поле.
func test_every_building_cell_reads_built_up(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _cached(p)
	var yards: Dictionary = _layout_yards(p, true)
	var checked: int = 0
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if board.kind_at(c) == Terrain.Kind.BUILDING:
				assert_true(yards.has(c) or not view.props().instances_on(c).is_empty(), "%s: порожня клітинка BUILDING %s" % [p, c])
				checked += 1
	assert_gt(checked, 0, "%s: передумова — клітинки BUILDING є" % p)
	for c: Vector2i in yards:
		assert_eq(board.kind_at(c), Terrain.Kind.BUILDING, "%s: клітинка макета %s — не BUILDING" % [p, c])


## Клітинки дворів садиб із макету карти (і, за with_orchards, луків між садибами).
func _layout_yards(map_key: String, with_orchards: bool) -> Dictionary:
	var out: Dictionary = {}
	var lay: Dictionary = VillageLayout.for_map(StringName(map_key))
	for home: Dictionary in lay.get("homes", []):
		for c: Vector2i in home["cells"]:
			out[c] = true
	if with_orchards:
		for c: Vector2i in lay.get("orchards", []):
			out[c] = true
	return out


## Кільце паркану садиби замкнене: кожен кінець секції сходиться з кінцем іншої або впирається в
## стіну будівлі; вільних кінців рівно по два на садибу — стовпи одних воріт, не ширших за GATE.
## Сиріт-панелей нема: панель без пари на обох кінцях дала б два зайві вільні кінці.
func test_fence_rings_are_closed(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var walls: Array[Rect2] = []
	var ends: Array[Vector2] = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		var t: Transform3D = inst["transform"]
		var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = t * box
			walls.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
		elif k == PropLayer.Kind.GARDEN_FENCE:
			for x: float in [box.position.x, box.end.x]:
				var e: Vector3 = t * Vector3(x, 0.0, 0.0)
				ends.append(Vector2(e.x, e.z))
	var loose: Array[Vector2] = []
	for i in ends.size():
		var joined := false
		for j in ends.size():
			joined = joined or (j != i and ends[j].distance_to(ends[i]) < 0.03)
		for w in walls:
			joined = joined or w.grow(0.05).has_point(ends[i])
		if not joined:
			loose.append(ends[i])
	var homes: int = (VillageLayout.for_map(StringName(p)).get("homes", []) as Array).size()
	assert_eq(loose.size(), 2 * homes, "%s: вільні кінці паркану %s" % [p, loose])
	for e in loose:
		var pair: bool = loose.any(func(o: Vector2) -> bool: return o != e and o.distance_to(e) <= PropLayer.GATE + 0.03)
		assert_true(pair, "%s: кінець паркану %s без пари воріт — кільце розірване" % [p, e])


## Міст — матова копія сітки (ассет мав «мокрі» поверхні з шорсткістю 0.15, міст блищав склом); на
## мокрій карті ще й темніша.
func test_wet_map_darkens_bridges() -> void:
	var m: MapData = _map("river")
	for wet: bool in [false, true]:
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child_autofree(view)
		view.ring_map = m
		view.wet = wet
		view.build(m.to_board())
		var node: MultiMeshInstance3D = view.props().get_node("bridge_river_centre")
		var src := (PropLayer.model(&"bridge_river_centre")["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D
		var got := node.multimesh.mesh.surface_get_material(0) as BaseMaterial3D
		# Міст матовий на будь-якій карті (не скло); на мокрій ще й темніший.
		if wet:
			assert_almost_eq(got.albedo_color.r, src.albedo_color.r * PropLayer.WET_DARK, 1e-3)
			assert_gte(got.roughness, PropLayer.WET_ROUGHNESS - 1e-4)
		else:
			assert_almost_eq(got.albedo_color.r, src.albedo_color.r, 1e-3)
			assert_gte(got.roughness, PropLayer.BRIDGE_ROUGH - 1e-4)


## Руїна з глухим фронтоном стоїть пошкодженим фасадом (−Z) до камери (+x чи +z). Карта, де такої
## руїни нема (на Річці вона не випадає), перевіряти нічого: тест це й каже.
func test_blank_gable_ruins_face_away_from_the_camera(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var n: int = 0
	for inst in view.props().all_instances():
		if PropLayer.CAMERA_FRONT.has(inst["model"]):
			var front: Vector3 = -(inst["transform"] as Transform3D).basis.z
			assert_gt(front.x + front.z, 0.5, "%s: %s фасадом від камери" % [p, inst["model"]])
			n += 1
	if n == 0:
		pass_test("%s: руїн із глухим фронтоном на карті нема" % p)


## Дахи будинків мають різні відтінки, руїни й двірське вбрання — без відтінку.
func test_roofs_are_untinted(p = use_parameters(MAPS)) -> void:
	# Колір даху дає лише текстура моделі: множник відтінку зсував дахи в оливу й вохру.
	var props: PropLayer = _cached(p).props()
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			assert_eq(props._roof_tint(inst), Color(1, 1, 1), "%s: %s" % [p, inst["model"]])


func test_roof_variety_comes_from_house_textures() -> void:
	var atlases: Dictionary = {}
	for m: StringName in PropLayer.MODELS:
		if String(m).begins_with("house_h") and int(PropLayer.spec_of(m)["kind"]) == PropLayer.Kind.STRUCTURE:
			var mat := (PropLayer.model(m)["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D
			if mat != null and mat.albedo_texture != null:
				atlases[mat.albedo_texture.resource_path] = true
	assert_gte(atlases.size(), 3, "щонайменше три хати зі своїм атласом (і своїм дахом)")


## Паркан і дрібний пропс не лягають на дорожнє покриття (осі й ширина дороги, не вид клітинки).
func test_nothing_small_lies_on_the_road_surface(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var checked: int = 0
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k in [PropLayer.Kind.STRUCTURE, PropLayer.Kind.RUIN, PropLayer.Kind.BRIDGE, PropLayer.Kind.POLE]:
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		for v: Vector2 in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.end.z),
				Vector2(box.position.x, box.end.z), Vector2(box.end.x, box.position.z),
				Vector2(box.get_center().x, box.get_center().z)]:
			assert_false(props.on_road(v), "%s: %s на %s лежить на дорозі" % [p, inst["model"], inst["cells"]])
		checked += 1
	assert_gt(checked, 0, p)


## Не більше двох однакових дрібних пропсів ближче за клітинку: ряд копій читається складом.
func test_no_rows_of_identical_small_props(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var items: Array = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k in [PropLayer.Kind.HAY, PropLayer.Kind.TRAILER, PropLayer.Kind.BLOCK] or inst.get("yard", false):
			var o: Vector3 = (inst["transform"] as Transform3D).origin
			items.append([inst["model"], Vector2(o.x, o.z)])
	for a: Array in items:
		var near: int = 0
		for b: Array in items:
			if b != a and b[0] == a[0] and (a[1] as Vector2).distance_to(b[1]) < 1.0:
				near += 1
		assert_lte(near, 1, "%s: %s біля %s — ряд однакових" % [p, a[0], a[1]])


## Сарай і причіп стоять лише при хаті: хата в межах HOUSE_NEAR клітинок.
func test_sheds_and_trailers_stand_by_a_house(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var houses: Array[Vector2i] = []
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		if int(s["kind"]) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false) and not bool(s.get("tower", false)):
			houses.append_array(inst["cells"])
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		var is_shed: bool = k == PropLayer.Kind.STRUCTURE and inst.get("yard", false)
		if not is_shed and k != PropLayer.Kind.TRAILER:
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		var ok := false
		for hc in houses:
			ok = ok or (absi(hc.x - c.x) <= PropLayer.HOUSE_NEAR and absi(hc.y - c.y) <= PropLayer.HOUSE_NEAR)
		assert_true(ok, "%s: %s на %s без хати поруч" % [p, inst["model"], c])


## На кожному хуторі Ridge — щонайменше один цілий будинок, не самі руїни.
func test_ridge_hamlets_keep_an_intact_house() -> void:
	var view: BoardView = _cached("ridge")
	for group: Array in [[Vector2i(13, 4), Vector2i(13, 5), Vector2i(14, 5)], [Vector2i(11, 16), Vector2i(12, 16), Vector2i(12, 17)]]:
		var houses: int = 0
		for c: Vector2i in group:
			for inst in view.props().instances_on(c):
				if _kind(inst["model"]) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false):
					houses += 1
		assert_gt(houses, 0, "хутір %s без цілого будинку" % [group])


## Перехрестя читається селом: 4–6 хат на дошці (не вежа, не двірське вбрання, не руїни).
func test_crossroads_reads_as_a_village() -> void:
	var m: MapData = _map("crossroads")
	var board: Board = m.to_board()
	var view: BoardView = _cached("crossroads")
	var houses: int = 0
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		var c: Vector2i = (inst["cells"] as Array)[0]
		if int(s["kind"]) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false) \
				and not bool(s.get("tower", false)) and board.in_bounds(c):
			houses += 1
	assert_gte(houses, 4)


func _box_of(inst: Dictionary) -> AABB:
	return (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)


## Будівля стоїть на рівному майданчику: ґрунт під її справжнім слідом (сітка 9×9) гуляє не більше
## ніж на 0.15 м, жоден кут не закопаний глибше 0.1 м і не висить. Усі будівлі, руїни й сараї — на
## дошці й у кільці.
func test_buildings_sit_on_the_relief(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	# Рельєф саме цієї карти: TerrainHeight.active — рельєф останньої побудованої дошки.
	var th: TerrainHeight = view._height
	var checked := 0
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN and inst["model"] != PropLayer.YARD_SHED:
			continue
		checked += 1
		var box: AABB = _box_of(inst)
		var lo: float = INF
		var hi: float = -INF
		for j in 9:
			for i in 9:
				var g: float = th.at(box.position.x + box.size.x * i / 8.0, box.position.z + box.size.z * j / 8.0)
				lo = minf(lo, g)
				hi = maxf(hi, g)
		var what: String = "%s: %s на %s" % [p, inst["model"], inst["cells"]]
		assert_lte((hi - lo) / TerrainHeight.M, 0.15, "%s — ґрунт під слідом гуляє на %.2f м" % [what, (hi - lo) / TerrainHeight.M])
		assert_lte((hi - box.position.y) / TerrainHeight.M, 0.1, "%s — закопана на %.2f м" % [what, (hi - box.position.y) / TerrainHeight.M])
		assert_lte(box.position.y, lo + 0.005, "%s висить" % what)
	assert_gt(checked, 5, "%s: є будівлі" % p)


## Секція паркану лежить на рельєфі обома кінцями й серединою (нахил за схилом, не висить).
func test_fences_follow_the_relief(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var th: TerrainHeight = view._height
	for inst in view.props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var t: Transform3D = inst["transform"]
		var half: float = (PropLayer.model(inst["model"])["aabb"] as AABB).size.x * 0.5
		for sgn: float in [-1.0, 1.0]:
			var end: Vector3 = t * Vector3(sgn * half, 0.0, 0.0)
			assert_almost_eq(end.y, th.at(end.x, end.z), 0.03, "%s: паркан на %s висить" % [p, inst["cells"]])
		# Середина секції — не вище й не нижче ґрунту більш ніж на 5 см (край майданчика будівлі).
		var mid: Vector3 = t.origin
		assert_almost_eq(mid.y, th.at(mid.x, mid.z), PropLayer.FENCE_SAG + 0.001,
				"%s: середина паркану (%.2f; %.2f) відходить від ґрунту на %.2f м" % [p, mid.x, mid.z, (mid.y - th.at(mid.x, mid.z)) / TerrainHeight.M])


## Будівлі, паркани й стовпи не ближче WATER_CLEAR до води й болота: на березі вони висіли б над руслом.
func test_nothing_hangs_over_the_bank(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _cached(p)
	var wet: Array[Rect2] = []
	for y in board.height:
		for x in board.width:
			var kd: int = board.kind_at(Vector2i(x, y))
			if kd == Terrain.Kind.WATER or kd == Terrain.Kind.MARSH:
				wet.append(Rect2(x - 0.5, y - 0.5, 1.0, 1.0).grow(PropLayer.WATER_CLEAR - 1e-3))
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k not in [PropLayer.Kind.STRUCTURE, PropLayer.Kind.GARDEN_FENCE, PropLayer.Kind.POLE]:
			continue
		var box: AABB = _box_of(inst)
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		for w in wet:
			assert_false(r.intersects(w), "%s: %s на %s над водою" % [p, inst["model"], inst["cells"]])


## Кінці мосту сходяться з дорогою на березі.
func test_bridge_ends_meet_the_bank() -> void:
	var view: BoardView = _cached("river")
	var h: TerrainHeight = view._height
	for g in h.bridge_groups():
		var cells: Array = g["cells"]
		var axis: Vector2 = g["axis"]
		var a := Vector2i(axis)
		for c: Vector2i in cells:
			for d: Vector2i in [a, -a]:
				var n: Vector2i = c + d
				if cells.has(n) or n.x < 0 or n.y < 0 or n.x >= 26 or n.y >= 22:
					continue
				# Настил на кінці — на висоті дороги на березі (центр клітинки дороги).
				assert_almost_eq(h.deck_y(c), h.at(float(n.x), float(n.y)), 0.05, "кінець мосту %s до %s" % [c, n])


## Масштаб у метрах (клітинка — 8 м): стовп 0.4 кВ — 8.6–9.0 м, 10 кВ — 10–11 м; одноповерхова хата
## разом із димарем — до 8 м, двоповерхова — 8.5–11 м.
func test_poles_and_houses_have_real_heights(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		var metres: float = _box_of(inst).size.y * 8.0
		if int(s.get("kind", -1)) == PropLayer.Kind.POLE:
			var r: Vector2 = Vector2(8.6, 9.0) if s.get("line") == &"04kv" else Vector2(10.0, 11.0)
			assert_between(metres, r.x, r.y, "%s: %s %.1f м" % [p, inst["model"], metres])
		elif inst["model"] in PropLayer.HOUSE_FORMS and not inst.get("yard", false):
			var r: Vector2 = Vector2(8.5, 11.0) if int(s.get("storeys", 1)) >= 2 else Vector2(5.0, 8.0)
			assert_between(metres, r.x, r.y, "%s: %s %.1f м" % [p, inst["model"], metres])


## Хати макету дивляться фасадом (−Z моделі) туди, куди каже садиба.
func test_layout_houses_face_their_road(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	for home: Dictionary in VillageLayout.for_map(StringName(p))["homes"]:
		var hc: Vector2i = home["house"]
		var house: Array = view.props().instances_on(hc).filter(
				func(i: Dictionary) -> bool: return _kind(i["model"]) == PropLayer.Kind.STRUCTURE and not i.get("yard", false))
		assert_eq(house.size(), 1, "хата на %s" % hc)
		if house.is_empty():
			continue
		var front: Vector3 = -(house[0]["transform"] as Transform3D).basis.z.normalized()
		var face: Vector2i = home["face"]
		assert_almost_eq(Vector2(front.x, front.z).dot(Vector2(face)), 1.0, 0.01, "хата на %s фасадом не до дороги" % hc)


## Для диму: верх димаря кожної хати дошки (вузол chimney_top) і центри руїн дошки.
func test_chimney_tops_and_ruin_centres() -> void:
	var view: BoardView = _cached("crossroads")
	var props: PropLayer = view.props()
	var houses: Array = props.all_instances().filter(func(i: Dictionary) -> bool:
		return i["model"] in PropLayer.HOUSE_FORMS and not i.get("yard", false) \
				and Rect2i(0, 0, 26, 22).has_point((i["cells"] as Array)[0]))
	var tops: Array[Vector3] = props.chimney_tops()
	assert_eq(tops.size(), houses.size(), "на кожній хаті дошки рівно один димар")
	for t in tops:
		var near := false
		for hs: Dictionary in houses:
			var box: AABB = _box_of(hs).grow(0.05)
			near = near or box.has_point(t)
		assert_true(near, "димар %s не над хатою" % t)
	var ruins: Array[Vector3] = props.ruin_centres()
	assert_eq(ruins.size(), 6, "шість руїн на дошці Перехрестя")
	for r in ruins:
		assert_almost_eq(r.y, view._height.at(r.x, r.z), 0.1)


## Руїна тліє з пролому на рівні даху — над землею, усередині обрису руїни, — а не біля
## уцілілого димаря.
func test_ruin_smoke_rises_from_the_breach_at_roof_level() -> void:
	for name in MAPS:
		var props: PropLayer = _cached(name).props()
		var m: MapData = _map(name)
		var pts: Array[Vector3] = props.ruin_smoke_points()
		var centres: Array[Vector3] = props.ruin_centres()
		var boxes: Array[AABB] = []
		for inst in props.all_instances():
			if int(PropLayer.spec_of(inst["model"])["kind"]) == PropLayer.Kind.RUIN \
					and Rect2i(0, 0, m.width, m.height).has_point((inst["cells"] as Array)[0]):
				boxes.append((inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB))
		assert_eq(pts.size(), centres.size(), name)
		assert_eq(pts.size(), boxes.size(), name)
		for i in pts.size():
			var p: Vector3 = pts[i]
			assert_gt(p.y, centres[i].y + 0.1, "%s: над землею, на рівні даху" % name)
			assert_true(p.x > -0.5 and p.z > -0.5 and p.x < m.width - 0.5 and p.z < m.height - 0.5, "%s: на дошці" % name)
			assert_true(p.x >= boxes[i].position.x and p.x <= boxes[i].end.x and p.z >= boxes[i].position.z and p.z <= boxes[i].end.z,
					"%s: усередині обрису руїни" % name)


## Пояс бруду довкола кожної хати дошки — одним вузлом.
func test_houses_get_a_grime_band() -> void:
	var view: BoardView = _cached("river")
	var node: MultiMeshInstance3D = view.props().get_node("HouseGrime")
	var houses: int = 0
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		if int(s.get("kind", -1)) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false) \
				and Rect2i(0, 0, 26, 22).has_point((inst["cells"] as Array)[0]):
			houses += 1
	assert_eq(node.multimesh.instance_count, houses)



## Під кожною руїною дошки — підлога з уламків, не трава.
func test_ruins_stand_on_rubble_floors() -> void:
	var view: BoardView = _cached("crossroads")
	var node: MultiMeshInstance3D = view.props().get_node("RubbleFloors")
	assert_eq(node.multimesh.instance_count, view.props().ruin_centres().size())



## Шейдер будівлі бере з матеріалу GLB усе, що там є: альбедо, нормалі з їхньою силою, карту
## шорсткості з каналом, метал, AO, а спекуляр — не більший за мінеральний. Одне число шорсткості на
## весь дім давало вигляд пластику.
func test_house_shader_takes_every_map_of_the_glb_material() -> void:
	var view: BoardView = _cached("crossroads")
	var m: StringName = &""
	for f: StringName in PropLayer.HOUSE_FORMS:                               # будь-яка хата, що стоїть на дошці
		if view.props().has_node(String(f)):
			m = f
			break
	assert_ne(m, &"", "на дошці немає жодної хати")
	var node: MultiMeshInstance3D = view.props().get_node(String(m))
	var mat: ShaderMaterial = node.material_override
	var src := (PropLayer.model(m)["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D
	assert_eq(mat.get_shader_parameter("albedo_tex"), src.albedo_texture)
	assert_eq(mat.get_shader_parameter("normal_tex"), src.normal_texture)
	assert_almost_eq(float(mat.get_shader_parameter("normal_scale")), src.normal_scale if src.normal_enabled else 1.0, 1e-4)
	assert_eq(bool(mat.get_shader_parameter("use_roughness_tex")), src.roughness_texture != null)
	if src.roughness_texture != null:
		assert_eq(mat.get_shader_parameter("roughness_tex"), src.roughness_texture)
		assert_eq(mat.get_shader_parameter("roughness_channel"), PropLayer._channel(src.roughness_texture_channel))
	assert_eq(bool(mat.get_shader_parameter("use_ao_tex")), src.ao_enabled and src.ao_texture != null)
	assert_lte(float(mat.get_shader_parameter("specular")), PropLayer.MINERAL_SPECULAR + 1e-4)


## Обриси будівель дошки (хати, руїни, сараї дворів — разом зі звісом даху) тримаються одна від
## одної на ≥ BUILDING_GAP: впритул дві будівлі з камери гри читаються однією, що входить в іншу.
func test_buildings_keep_a_quarter_cell_apart(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var board: Board = _map(p).to_board()
	var rects: Array = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if (k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN) or not board.in_bounds((inst["cells"] as Array)[0]):
			continue
		var box: AABB = _box_of(inst)
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		for o: Array in rects:
			assert_false(r.grow(PropLayer.BUILDING_GAP - 1e-3).intersects(o[0]),
					"%s: %s на %s ближче %.2f клітинки до %s на %s" % [p, inst["model"], inst["cells"], PropLayer.BUILDING_GAP, o[1], o[2]])
		rects.append([r, inst["model"], inst["cells"]])


## Город — у дворі своєї садиби (усі кути на її клітинках) і не заходить під жодну будівлю.
func test_gardens_stay_inside_the_yard(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	var houses: Array[Rect2] = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = _box_of(inst)
			houses.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	var plots: Array[Dictionary] = view.props()._garden_plots
	assert_gt(plots.size(), 0, "%s: передумова — городи є" % p)
	for gp in plots:
		var r: Rect2 = gp["rect"]
		var cells: Array = homes[int(gp["home"])]["cells"]
		for v: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			assert_true(cells.has(Vector2i(roundi(v.x), roundi(v.y))), "%s: город %s виходить за двір" % [p, r])
		for hr in houses:
			assert_false(hr.intersects(r), "%s: город %s заходить під будівлю %s" % [p, r, hr])


## Тюк — щойно за краєм ріллі: не на полі й не далі 0.3 клітинки від його краю (не посеред луку).
func test_hay_sits_just_outside_a_field(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var fields: Array[Rect2] = view.props().field_edges
	var bales: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.HAY:
			continue
		var o: Vector3 = (inst["transform"] as Transform3D).origin
		var q := Vector2(o.x, o.z)
		var near: float = INF
		for r in fields:
			assert_false(r.has_point(q), "%s: тюк %s на полі" % [p, q])
			near = minf(near, q.distance_to(q.clamp(r.position, r.end)))
		assert_lte(near, 0.3 + 1e-3, "%s: тюк %s далі 0.3 від краю поля" % [p, q])
		bales += 1
	assert_gt(bales, 0, "%s: передумова — тюки є" % p)


## Дріт не йде над дахом: жоден проліт лінії й жоден відвід (крім своєї хати на кінці) не перетинає
## обрис будівлі; проліт — не довший за SPAN (~36 м), відвід без проміжного стовпа — не довший за
## DROP_DIRECT.
func test_wires_never_cross_a_roof(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var roofs: Array[Rect2] = []
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = _box_of(inst)
			roofs.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	var segs: Array = []
	for s: Array in props._spans:
		var a: Vector3 = (props._instances[s[0]]["transform"] as Transform3D).origin
		var b: Vector3 = (props._instances[s[1]]["transform"] as Transform3D).origin
		segs.append([Vector2(a.x, a.z), Vector2(b.x, b.z), false])
		assert_lte(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)), PropLayer.SPAN[&"10kv"] + 1e-3, "%s: проліт" % p)
	for d: Array in props._drops:
		var a: Vector3 = (props._instances[d[0]]["transform"] as Transform3D).origin
		var t: Vector3 = d[1]
		segs.append([Vector2(a.x, a.z), Vector2(t.x, t.z), true])
		assert_lte(Vector2(a.x, a.z).distance_to(Vector2(t.x, t.z)), PropLayer.DROP_DIRECT, "%s: відвід до %s задовгий" % [p, t])
	assert_gt(segs.size(), 0, "%s: передумова — дроти є" % p)
	for sg: Array in segs:
		for r in roofs:
			# Відвід закінчується на стіні своєї хати: її обрис кінець і містить.
			if sg[2] and r.grow(0.02).has_point(sg[1]):
				continue
			var hit: bool = r.has_point(sg[0]) or r.has_point(sg[1])
			for e: Array in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
					[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
				hit = hit or Geometry2D.segment_intersects_segment(sg[0], sg[1], e[0], e[1]) != null
			assert_false(hit, "%s: дріт %s → %s над дахом %s" % [p, sg[0], sg[1], r])


## Стовп стоїть прямо: вісь Y моделі відхиляється від вертикалі не більше ніж на 3°. Нахил, видний
## на краях кадру, — перспектива камери, не модель.
func test_poles_stand_upright(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var n: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.POLE:
			continue
		var up: Vector3 = (inst["transform"] as Transform3D).basis.y.normalized()
		assert_lte(rad_to_deg(up.angle_to(Vector3.UP)), 3.0, "%s: стовп %s нахилений" % [p, inst["cells"]])
		n += 1
	assert_gt(n, 0, "%s: передумова — стовпи є" % p)


## Розчиняється лише будівля, вища за FADE_MIN_H, що на екрані перекриває юніта: купа уламків по
## коліно лишається суцільною, хата перед юнітом — розчиняється.
func test_only_tall_buildings_over_the_unit_dissolve() -> void:
	var view: BoardView = _view(_map("crossroads"))
	var props: PropLayer = view.props()
	var tall: Dictionary = {}
	var low: Dictionary = {}
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN:
			continue
		var h: float = _box_of(inst).size.y
		if h >= PropLayer.FADE_MIN_H and tall.is_empty() and not inst.get("yard", false):
			tall = inst
		elif h < PropLayer.FADE_MIN_H and low.is_empty():
			low = inst
	assert_false(tall.is_empty(), "передумова — висока будівля")
	# Юніт за будівлею з боку від камери (камера на +x, +z): будівля — його REVEAL_OFFSETS (1, 1).
	var behind: Vector2i = (tall["cells"] as Array)[0] - Vector2i.ONE
	var cells: Array[Vector2i] = [behind]
	props.set_reveal_cells(cells)
	assert_true(props._is_faded(tall), "висока будівля перед юнітом розчиняється")
	if not low.is_empty():
		var at: Array[Vector2i] = [(low["cells"] as Array)[0] - Vector2i.ONE]
		props.set_reveal_cells(at)
		assert_false(props._is_faded(low), "низька руїна не розчиняється")


## Будівля над юнітом — звичайна альфа з проходом глибини, не растр: матеріал вузла «_fade» —
## альфа-варіант без discard; за FADE_TIME дім переходить туди з альфою FADE_ALPHA, а в суцільному
## вузлі схований; знято юніта — повертається.
func test_dissolve_is_alpha_blend_not_dither() -> void:
	var src: String = (load("res://game/battle/shaders/prop_fade.gdshader") as Shader).code
	assert_false(src.contains("discard"), "у шейдері будівель нема растрового розчинення")
	var view: BoardView = _view(null, _house_board())
	var props: PropLayer = view.props()
	var h: Vector2i = _house_cell(view)
	view.set_reveal_cells([h] as Array[Vector2i])
	var idx: int = -1
	for i in props._instances.size():
		if props._is_faded(props._instances[i]):
			idx = i
	assert_gte(idx, 0, "передумова: будинок над юнітом")
	var key: StringName = props._instances[idx]["model"]
	var fmi: MultiMeshInstance3D = props._fade_nodes[key]
	var depth := fmi.material_override as ShaderMaterial
	assert_true(depth.shader.code.contains("#define FADE_DEPTH") and src.contains("depth_draw_always"), "перший прохід — лише глибина")
	var colour := depth.next_pass as ShaderMaterial
	assert_true(colour != null and colour.shader.code.contains("#define FADE_ALPHA"), "другий прохід — колір з альфою")
	assert_false(fmi.visible, "до переходу вузол розчинення схований")
	props._flush()
	props._process(PropLayer.FADE_TIME * 2.0)
	# Дані екземплярів MultiMesh безголовий рендер не зберігає: перевіряємо рівень і вузол.
	assert_almost_eq(float(props._fade_level[idx]), 1.0, 1e-4, "перехід завершився за FADE_TIME")
	assert_true(fmi.visible, "дім у вузлі розчинення")
	view.set_reveal_cells([] as Array[Vector2i])
	props._flush()
	props._process(PropLayer.FADE_TIME * 2.0)
	assert_false(fmi.visible, "юніта нема — дім знову суцільний")


## Гейт передачі (§3.5): намальований стан дахів одразу, без жодного тіку _process — рівень
## розчинення вже на цілі, вузол «_fade» показано чи сховано. Інакше дах, прозорий для попереднього
## гравця, ще кілька кадрів доповертався б до непрозорості й показував його юнітів.
func test_instant_reveal_draws_the_final_state_without_ticks() -> void:
	var view: BoardView = _view(null, _house_board())
	var props: PropLayer = view.props()
	var h: Vector2i = _house_cell(view)
	view.set_reveal_cells([h] as Array[Vector2i], true)
	var idx: int = -1
	for i in props._instances.size():
		if props._is_faded(props._instances[i]):
			idx = i
	assert_gte(idx, 0, "передумова: будинок над юнітом")
	var fmi: MultiMeshInstance3D = props._fade_nodes[props._instances[idx]["model"]]
	assert_almost_eq(float(props._fade_level[idx]), 1.0, 1e-6, "розчинено одразу")
	assert_true(fmi.visible)
	view.set_reveal_cells([] as Array[Vector2i], true)
	assert_almost_eq(float(props._fade_level[idx]), 0.0, 1e-6, "суцільний одразу")
	assert_false(fmi.visible, "вузол розчинення схований до зняття гейта")
	assert_false(props.is_processing(), "переходу нема")


## Мокра карта: дах шорсткіший за мокрий не буває — під вологою шорсткість даху знижується (метал до
## 0.35, черепиця й шифер до 0.45), а на сухій карті (wetness 0) гілка мокрості не діє.
func test_wet_roofs_get_lower_roughness() -> void:
	var src: String = (load("res://game/battle/shaders/prop_fade.gdshader") as Shader).code
	var consts: Dictionary = {}
	for line in src.split("\n"):
		var parts: PackedStringArray = line.strip_edges().trim_suffix(";").split(" ")
		if parts.size() == 5 and parts[0] == "const" and parts[1] == "float":
			consts[parts[2]] = float(parts[4])
	assert_between(float(consts["WET_ROOF_ROUGHNESS_METAL"]), 0.3, 0.45)
	assert_between(float(consts["WET_ROOF_ROUGHNESS"]), 0.35, 0.45)
	# Дах на сухій карті має шорсткість ассета (~0.8–0.9); мокрий — нижча.
	assert_lt(float(consts["WET_ROOF_ROUGHNESS"]), 0.8)
	assert_true(src.contains("if (wet > 0.0)"), "суха карта — без змін")
	# Роль даху — з нормалі, металевість — з каналу metallic ORM-карти, вологість — з погоди.
	assert_true(src.contains("smoothstep(0.0, WET_FULL, weather_wetness)"), "вологість — з weather_wetness")
	assert_true(src.contains("metal *= dot(texture(metallic_tex, UV), metallic_channel)"), "метал — з ORM")
	assert_true(src.contains("float sheet = smoothstep(0.3, 0.6, metal)"), "листовий метал — за металевістю")


## Дрібні пропси (тюки, причепи, двірські речі) не заходять у слід юніта (UNIT_HALF) у центрі жодної
## клітинки, де юніт може стояти; стовп — ще на UNIT_POLE_CLEAR далі від сліду.
func test_small_props_keep_out_of_unit_footprints(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var board: Board = _map(p).to_board()
	var n: int = 0
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		var margin: float = 0.0
		var r: Rect2
		if k == PropLayer.Kind.POLE:
			var o: Vector3 = (inst["transform"] as Transform3D).origin
			r = Rect2(Vector2(o.x, o.z) - Vector2(0.03, 0.03), Vector2(0.06, 0.06))
			margin = PropLayer.UNIT_POLE_CLEAR
		elif k == PropLayer.Kind.HAY or k == PropLayer.Kind.TRAILER or k == PropLayer.Kind.YARD:
			var b: AABB = _box_of(inst)
			r = Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		else:
			continue
		var cc := Vector2i(roundi(r.get_center().x), roundi(r.get_center().y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = cc + Vector2i(dx, dy)
				if not board.in_bounds(c) or board.kind_at(c) == Terrain.Kind.WATER:
					continue
				var half: float = PropLayer.UNIT_HALF + margin - 1e-3
				assert_false(r.intersects(Rect2(Vector2(c) - Vector2(half, half), Vector2(half, half) * 2.0)),
						"%s: %s заходить у слід юніта на %s" % [p, inst["model"], c])
		n += 1
	assert_gt(n, 0, "%s: передумова — дрібні пропси є" % p)


## Щоглова підстанція — лише на опорі 10 кВ, від якої йде відвід до хати чи гілка 0.4 кВ.
func test_transformers_only_where_needed(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var feeds: Dictionary = {}
	for d: Array in props._drops:
		feeds[d[0]] = true
	for sp: Array in props._spans:
		for e in 2:
			var other: int = sp[1 - e]
			if PropLayer.spec_of(props._instances[other]["model"]).get("line", &"") == &"04kv":
				feeds[sp[e]] = true
	for i: int in props._transformers:
		assert_eq(PropLayer.spec_of(props._instances[i]["model"]).get("line", &""), &"10kv", "%s: підстанція не на 10 кВ" % p)
		assert_true(feeds.has(i), "%s: підстанція на опорі без відводу й гілки" % p)
	assert_gt(props._transformers.size(), 0, "%s: передумова — підстанція є" % p)


## Повалена опора — без шафи підстанції.
func test_crushed_pole_drops_its_transformer() -> void:
	var view: BoardView = _view(_map("crossroads"))
	var props: PropLayer = view.props()
	assert_gt(props.transformers_shown().size(), 0, "передумова")
	var i: int = props._transformers.keys()[0]
	var cells: Array[Vector2i] = [(props._instances[i]["cells"] as Array)[0]]
	props.set_crushed(cells)
	props._flush()
	assert_eq(props.transformers_shown().size(), props._transformers.size() - 1)


## Ворота є в кожному дворі: два стовпи на садибу.
func test_every_yard_has_one_gate(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var homes: int = (VillageLayout.for_map(StringName(p)).get("homes", []) as Array).size()
	assert_eq(props._gate_posts.size(), 2 * homes, "%s: стовпи воріт" % p)


## Обрис двору — прямокутник або L (щонайбільше шість кутів): сходинки клітинок видають сітку.
func test_yards_are_at_most_l_shaped(p = use_parameters(MAPS)) -> void:
	for home: Dictionary in VillageLayout.for_map(StringName(p)).get("homes", []):
		var cells: Array = home["cells"]
		var corners: int = 0
		var pts: Dictionary = {}
		for c: Vector2i in cells:
			for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				pts[c + o] = true
		for v: Vector2i in pts:
			# Кут сітки — вершина многокутника, якщо довкола нього 1 чи 3 клітинки двору (або 2 навскіс).
			var a: bool = cells.has(v + Vector2i(-1, -1))
			var b: bool = cells.has(v + Vector2i(0, -1))
			var c2: bool = cells.has(v + Vector2i(-1, 0))
			var d: bool = cells.has(v)
			var cnt: int = int(a) + int(b) + int(c2) + int(d)
			if cnt == 1 or cnt == 3 or (cnt == 2 and a == d):
				corners += 1
		assert_lte(corners, 6, "%s: двір хати %s — сходинки" % [p, home["house"]])


# --- мережа ЛЕП ----------------------------------------------------------------------------

func _pole_ids(props: PropLayer) -> Array[int]:
	var out: Array[int] = []
	for i in props._instances.size():
		if _kind(props._instances[i]["model"]) == PropLayer.Kind.POLE:
			out.append(i)
	return out


func _pole_at(props: PropLayer, i: int) -> Vector2:
	var o: Vector3 = (props._instances[i]["transform"] as Transform3D).origin
	return Vector2(o.x, o.z)


func _is_04(props: PropLayer, i: int) -> bool:
	return PropLayer.spec_of(props._instances[i]["model"]).get("line", &"") == &"04kv"


func _neighbours(props: PropLayer) -> Dictionary:
	var adj: Dictionary = {}
	for i in _pole_ids(props):
		adj[i] = []
	for sp: Array in props._spans:
		(adj[sp[0]] as Array).append(sp[1])
		(adj[sp[1]] as Array).append(sp[0])
	return adj


## Відстань від точки до зовнішнього краю світу (дошка разом із кільцем).
func _edge_gap(view: BoardView, m: MapData, p: Vector2) -> float:
	var r: float = float(view._ring)
	return minf(minf(p.x + r + 0.5, m.width + r - 0.5 - p.x), minf(p.y + r + 0.5, m.height + r - 0.5 - p.y))


func _rect_of(inst: Dictionary) -> Rect2:
	var b: AABB = _box_of(inst)
	return Rect2(b.position.x, b.position.z, b.size.x, b.size.z)


## Відстань від точки до обрису прямокутника (0 — всередині).
func _rect_gap(p: Vector2, r: Rect2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x), maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)).length()


## Цілі хати карти: індекс екземпляра, обрис, чи лежить хата на дошці і чи живить її мережа
## (PropLayer.powered_homes).
func _homes(props: PropLayer, m: MapData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var centres: Array[Vector2] = []
	var on_board: Array[bool] = []
	var board := Rect2i(0, 0, m.width, m.height)
	for i in props._instances.size():
		var inst: Dictionary = props._instances[i]
		if PropLayer.is_home(inst):
			var r: Rect2 = _rect_of(inst)
			out.append({"i": i, "rect": r, "board": board.has_point((inst["cells"] as Array)[0])})
			centres.append(r.get_center())
			on_board.append(out.back()["board"])
	var powered: Array[bool] = PropLayer.powered_homes(centres, on_board)
	for k in out.size():
		out[k]["powered"] = powered[k]
	return out


func _powered_homes(props: PropLayer, m: MapData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in _homes(props, m):
		if h["powered"]:
			out.append(h)
	return out


func _drops_to(props: PropLayer, rect: Rect2) -> Array:
	var out: Array = []
	for d: Array in props._drops:
		var t := Vector2((d[1] as Vector3).x, (d[1] as Vector3).z)
		if rect.grow(0.02).has_point(t):
			out.append(d)
	return out


## Кут при опорі b між прольотами до a і c, градуси.
func _angle_at(props: PropLayer, b: int, a: int, c: int) -> float:
	return rad_to_deg((_pole_at(props, a) - _pole_at(props, b)).angle_to(_pole_at(props, c) - _pole_at(props, b)))


## Мережа: кожна зв'язна частина виходить на зовнішній край кільця (магістраль 10 кВ) і не має одиноких опор; кінці, що не на
## краю, — підстанція (10 кВ) чи опора з відводом (0.4 кВ). Магістралей на краю — щонайменше дві.
func test_power_network_is_connected_and_leaves_the_world(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var m: MapData = _map(p)
	var adj: Dictionary = _neighbours(props)
	var ids: Array[int] = _pole_ids(props)
	assert_gt(ids.size(), 0, "%s: передумова — опори є" % p)
	var seen: Dictionary = {}
	for start in ids:
		if seen.has(start):
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = true
		while not stack.is_empty():
			var u: int = stack.pop_back()
			comp.append(u)
			for n: int in adj[u]:
				if not seen.has(n):
					seen[n] = true
					stack.append(n)
		assert_gt(comp.size(), 1, "%s: одинока опора %s" % [p, _pole_at(props, start)])
		var reaches_edge: bool = comp.any(func(i: int) -> bool: return _edge_gap(view, m, _pole_at(props, i)) <= 0.5)
		assert_true(reaches_edge, "%s: частина мережі з опорою %s не виходить на край" % [p, _pole_at(props, start)])
	var fed: Dictionary = {}
	for d: Array in props._drops:
		fed[d[0]] = true
	var edge_ends: int = 0
	for i in ids:
		if (adj[i] as Array).size() != 1:
			continue
		var gap: float = _edge_gap(view, m, _pole_at(props, i))
		if _is_04(props, i):
			assert_true(fed.has(i), "%s: гілка 0.4 кВ обривається на %s без відводу" % [p, _pole_at(props, i)])
		elif gap <= 0.5:
			edge_ends += 1
		else:
			assert_true(props._transformers.has(i), "%s: 10 кВ обривається не на ТП: %s (до краю %.2f)" % [p, _pole_at(props, i), gap])
	assert_gte(edge_ends, 2, "%s: кінців магістралі на краю кільця %d" % [p, edge_ends])


## Прольоти: 10 кВ — до 9 клітинок (72 м), 0.4 кВ — до 5 (40 м); опори не скупчені: будь-які дві не ближче за 1.4.
func test_spans_keep_their_length(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	assert_gt(props._spans.size(), 0, "%s: передумова — прольоти є" % p)
	var long10: int = 0
	for sp: Array in props._spans:
		var len_: float = _pole_at(props, sp[0]).distance_to(_pole_at(props, sp[1]))
		var limit: float = float(PropLayer.SPAN[&"04kv"] if _is_04(props, sp[0]) or _is_04(props, sp[1]) else PropLayer.SPAN[&"10kv"])
		assert_lte(len_, limit + 1e-3, "%s: проліт %s завдовжки %.2f" % [p, _pole_at(props, sp[0]), len_])
		if not _is_04(props, sp[0]) and not _is_04(props, sp[1]) and len_ >= 6.0:
			long10 += 1
	assert_gt(long10, 0, "%s: у магістралі нема прольотів 6–9 клітинок" % p)
	var ids: Array[int] = _pole_ids(props)
	for x in ids.size():
		for y in range(x + 1, ids.size()):
			assert_gte(_pole_at(props, ids[x]).distance_to(_pole_at(props, ids[y])), 1.4, "%s: опори %s скупчені" % [p, _pole_at(props, ids[x])])


## Магістраль 10 кВ не повертає назад: кут між прольотами — не гостріший за 60°.
func test_trunk_does_not_fold_back(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var adj: Dictionary = _neighbours(props)
	for i: int in adj:
		if _is_04(props, i):
			continue
		var nb: Array = adj[i].filter(func(n: int) -> bool: return not _is_04(props, n))
		for a in nb.size():
			for b in range(a + 1, nb.size()):
				assert_gte(absf(_angle_at(props, i, nb[a], nb[b])), 59.0, "%s: магістраль повертає назад на %s" % [p, _pole_at(props, i)])


## Підстанція на поселення рівно одна: кожна хата живиться від мережі з однією підстанцією, а хати одного поселення
## (ланцюг не довший за SETTLEMENT_R) — від тієї самої. Підстанція стоїть на лінії 10 кВ.
func test_each_settlement_has_exactly_one_transformer(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var m: MapData = _map(p)
	var homes: Array[Dictionary] = _powered_homes(props, m)
	assert_gt(homes.size(), 0, "%s: передумова — хати є" % p)
	var tp_of: Dictionary = {}
	for h in homes:
		var drops: Array = _drops_to(props, h["rect"])
		if drops.is_empty():
			continue
		var tps: Array[int] = _transformers_of(props, drops[0][0])
		assert_eq(tps.size(), 1, "%s: хата %s живиться від %d підстанцій" % [p, (h["rect"] as Rect2).get_center(), tps.size()])
		tp_of[h["i"]] = tps[0] if not tps.is_empty() else -1
	for a in homes:
		for b in homes:
			var ca: Vector2 = (a["rect"] as Rect2).get_center()
			var cb: Vector2 = (b["rect"] as Rect2).get_center()
			if ca.distance_to(cb) <= PropLayer.SETTLEMENT_R and tp_of.has(a["i"]) and tp_of.has(b["i"]):
				assert_eq(tp_of[a["i"]], tp_of[b["i"]], "%s: хати %s і %s одного поселення — різні підстанції" % [p, ca, cb])
	for i: int in props._transformers:
		assert_false(_is_04(props, i), "%s: підстанція не на лінії 10 кВ" % p)


## Дві підстанції не стоять ближче TP_GAP (6 клітинок) одна до одної.
func test_transformers_keep_apart(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var tps: Array = props._transformers.keys()
	for a in tps.size():
		for b in range(a + 1, tps.size()):
			assert_gte(_pole_at(props, tps[a]).distance_to(_pole_at(props, tps[b])), PowerGrid.TP_GAP, "%s: ТП %s і %s ближче за %.1f" % [p, _pole_at(props, tps[a]), _pole_at(props, tps[b]), PowerGrid.TP_GAP])


## Мережа 0.4 кВ, до якої підключено опору: підстанції, що до неї доходять прольотами (за підстанцію далі не йдемо).
func _transformers_of(props: PropLayer, start: int) -> Array[int]:
	var adj: Dictionary = _neighbours(props)
	var found: Array[int] = []
	var seen: Dictionary = {start: true}
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		if props._transformers.has(u):
			if not found.has(u):
				found.append(u)
			continue
		for n: int in adj[u]:
			if not seen.has(n) and (_is_04(props, n) or props._transformers.has(n)):
				seen[n] = true
				stack.append(n)
	return found


## До кожної цілої хати мережі — один відвід від найближчої опори, від якої він можливий: не довший за DROP_DIRECT (25 м),
## на стіні з боку опори на висоті 2.8–3 м, відрізок не заходить у обрис даху власної хати й не ближче DROP_GAP до чужих.
## Руїни, сараї й пошкоджені хати відводу не мають. Хати, до яких не дотягнулись (PropLayer._unfed), названі й справді
## без відводу.
func test_every_home_has_one_short_drop_to_its_wall(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var m: MapData = _map(p)
	var powered: Array[Dictionary] = _powered_homes(props, m)
	var all_homes: Array[Dictionary] = _homes(props, m)
	var rects: Array[Rect2] = []
	for h in all_homes:
		rects.append(h["rect"])
	var eligible: Array[int] = []
	for i in _pole_ids(props):
		if _is_04(props, i) or props._transformers.has(i):
			eligible.append(i)
	assert_gt(powered.size(), 0, "%s: передумова — хати є" % p)
	assert_eq(props._unfed.size(), 0, "%s: хати без відводу: %s" % [p, props._unfed])
	assert_eq(powered.size(), _homes(props, m).size(), "%s: не кожну цілу хату живить мережа" % p)
	for h in powered:
		var drops: Array = _drops_to(props, h["rect"])
		var centre: Vector2 = (h["rect"] as Rect2).get_center()
		assert_eq(drops.size(), 1, "%s: відводів до хати %s — %d" % [p, centre, drops.size()])
		if drops.is_empty():
			continue
		var d: Array = drops[0]
		var src: int = d[0]
		assert_true(eligible.has(src), "%s: відвід від опори 10 кВ без підстанції" % p)
		var target: Vector3 = d[1]
		var lip := Vector2(target.x, target.z)
		var from: Vector2 = _pole_at(props, src)
		assert_lte(from.distance_to(lip), PropLayer.DROP_DIRECT + 1e-3, "%s: відвід до %s завдовжки %.2f" % [p, centre, from.distance_to(lip)])
		var above: float = (target.y - view._height.at(target.x, target.z)) * 8.0
		assert_between(above, 2.8, 3.0, "%s: кріплення відводу до %s на %.2f м" % [p, centre, above])
		# Відрізок не заходить у дах власної хати (кріплення — на самому обрисі) й не лягає на чужі хати.
		for j in 20:
			var q: Vector2 = from.lerp(lip, float(j) / 20.0)
			assert_false((h["rect"] as Rect2).grow(-0.005).has_point(q), "%s: відвід до %s проходить крізь дах" % [p, centre])
			for r in rects:
				if not r.is_equal_approx(h["rect"]):
					assert_gte(_rect_gap(q, r), PropLayer.DROP_GAP - 0.02, "%s: відвід до %s ближче за %.2f до чужої хати" % [p, centre, PropLayer.DROP_GAP])
		assert_gte(from.distance_to(lip), PropLayer.DROP_MIN - 1e-3, "%s: відвід до %s коротший за DROP_MIN" % [p, centre])
		# Дріт від траверси до кромки не заходить під поверхню даху.
		var inst: Dictionary = props._instances[h["i"]]
		var info: Dictionary = PropLayer.model(inst["model"])
		var xf: Transform3D = (inst["transform"] as Transform3D) * (info["local"] as Transform3D)
		var tm: TriangleMesh = PropLayer.triangles_of(inst["model"])
		var inv: Transform3D = xf.affine_inverse()
		for pr: Array in PropLayer.drop_wire_pairs(props._instances[src], target):
			var pts: PackedVector3Array = PropLayer.wire_points(pr[0], pr[1], 40)
			for j in 37:
				var hit: Dictionary = tm.intersect_segment(inv * Vector3(pts[j].x, 50.0, pts[j].z), inv * Vector3(pts[j].x, -50.0, pts[j].z))
				if hit.is_empty():
					continue
				assert_gte(pts[j].y, (xf * (hit["position"] as Vector3)).y - 0.005, "%s: відвід до %s проходить крізь дах (%.0f%%)" % [p, centre, 100.0 * j / 40.0])
		# Найближча опора, від якої відвід можливий: ближчі його не допускають.
		for i in eligible:
			if _pole_at(props, i).distance_to(centre) < from.distance_to(centre) - 1e-3:
				assert_false(props._placer._drop_target(h["i"], i).is_finite(), "%s: до хати %s ближча опора %s допускає відвід" % [p, centre, _pole_at(props, i)])
	for u: Vector2 in props._unfed:
		for h in all_homes:
			if (h["rect"] as Rect2).get_center().distance_to(u) < 0.05:
				assert_eq(_drops_to(props, h["rect"]).size(), 0, "%s: хата %s названа без відводу, а відвід є" % [p, u])
	# Сараї, руїни й пошкоджені хати відводу не мають.
	for inst in props._instances:
		var k: int = _kind(inst["model"])
		if (k == PropLayer.Kind.RUIN or k == PropLayer.Kind.STRUCTURE) and not PropLayer.is_home(inst):
			assert_eq(_drops_to(props, _rect_of(inst)).size(), 0, "%s: відвід до сараю чи руїни %s" % [p, inst["cells"]])


## Кабелі: між двома опорами 10 кВ — три голі дроти, фаза до фази, без перехресть у плані; решта (0.4 кВ, ТП, відводи) —
## один кабель СІП.
func test_span_wires_do_not_cross(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	assert_gt(props._spans.size(), 0, "%s: передумова — прольоти є" % p)
	for sp: Array in props._spans:
		var pairs: Array = PropLayer.span_wire_pairs(props._instances[sp[0]], props._instances[sp[1]])
		var both10: bool = not _is_04(props, sp[0]) and not _is_04(props, sp[1])
		assert_eq(pairs.size(), 3 if both10 else 1, "%s: проліт %s: дротів %d" % [p, _pole_at(props, sp[0]), pairs.size()])
		for a in pairs.size():
			for b in range(a + 1, pairs.size()):
				var x: Variant = Geometry2D.segment_intersects_segment(
						Vector2(pairs[a][0].x, pairs[a][0].z), Vector2(pairs[a][1].x, pairs[a][1].z),
						Vector2(pairs[b][0].x, pairs[b][0].z), Vector2(pairs[b][1].x, pairs[b][1].z))
				assert_null(x, "%s: дроти %d і %d прольоту %s перехрещені" % [p, a, b, _pole_at(props, sp[0])])


## Найнижча точка дроту — не нижче 6 м над ґрунтом, дорогою й водою (поверхнею води, не дном).
func test_wires_hang_six_metres_above_ground_and_water(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var lowest: float = INF
	for sp: Array in props._spans:
		for pr: Array in PropLayer.span_wire_pairs(props._instances[sp[0]], props._instances[sp[1]]):
			for q: Vector3 in PropLayer.wire_points(pr[0], pr[1], 40):
				var floor_y: float = maxf(view._height.at(q.x, q.z), TerrainHeight.WATER_LEVEL)
				lowest = minf(lowest, (q.y - floor_y) * 8.0)
	assert_gte(lowest, 6.0, "%s: найнижчий дріт %.2f м над землею чи водою" % [p, lowest])


## Стовп стоїть на ґрунті: основа не відхиляється від рельєфу більше ніж на 2 см (0.0025 клітинки).
func test_poles_stand_on_the_ground(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	for i in _pole_ids(props):
		var o: Vector3 = (props._instances[i]["transform"] as Transform3D).origin
		assert_lte(absf(o.y - view._height.at(o.x, o.z)) * 8.0, 0.02, "%s: стовп %s висить чи вгрузає" % [p, _pole_at(props, i)])


## Нічого на асфальті (≥ POLE_ROAD_CLEAR_M від його краю за полем дороги, яке малює шейдер), у воді, ближче POLE_WET_CLEAR
## до води, в лісі, на мосту, у центрі клітинки; стовп — не в обрисі будівлі, паркану, дрібної речі чи грядок (від будівлі — не
## ближче POLE_BUILDING_CLEAR); проліт не лягає на будівлю. Кільце теж.
func test_poles_keep_off_road_water_bridges_and_buildings(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var m: MapData = _map(p)
	var world: Board = Surroundings.world_board(m.to_board(), m)
	var ring: int = view._ring
	var buildings: Array[Rect2] = []
	var homes: Array[Rect2] = []
	var bridges: Array[Rect2] = []
	var smalls: Array[Rect2] = []
	for inst in props._instances:
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			buildings.append(_rect_of(inst))
			if PropLayer.is_home(inst):
				homes.append(_rect_of(inst))
		elif k == PropLayer.Kind.BRIDGE:
			bridges.append(_rect_of(inst))
		elif k != PropLayer.Kind.POLE:
			smalls.append(_rect_of(inst))
	var bad_kinds: Array = [Terrain.Kind.WATER, Terrain.Kind.MARSH, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED,
			Terrain.Kind.FOREST]
	for i in _pole_ids(props):
		var at: Vector2 = _pole_at(props, i)
		assert_gte(props.road_edge_m(at), 2.39, "%s: стовп %s за %.2f м від краю асфальту" % [p, at, props.road_edge_m(at)])
		var c := Vector2i(roundi(at.x), roundi(at.y))
		var kind_here: int = world.kind_at(c + Vector2i(ring, ring))
		assert_false(kind_here in bad_kinds, "%s: стовп %s на клітинці %d" % [p, at, kind_here])
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if not world.in_bounds(n + Vector2i(ring, ring)):
					continue
				var kn: int = world.kind_at(n + Vector2i(ring, ring))
				if kn == Terrain.Kind.WATER or kn == Terrain.Kind.MARSH:
					var nearest := Vector2(clampf(at.x, n.x - 0.5, n.x + 0.5), clampf(at.y, n.y - 0.5, n.y + 0.5))
					assert_gte(at.distance_to(nearest), PropLayer.POLE_WET_CLEAR - 1e-3, "%s: стовп %s за %.2f від води" % [p, at, at.distance_to(nearest)])
		# Стовп у клітинці двору — лише біля межі двору з боку вулиці.
		if kind_here == Terrain.Kind.BUILDING or kind_here == Terrain.Kind.RUBBLE:
			var near_street: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var kn2: int = world.kind_at(c + d + Vector2i(ring, ring))
				if kn2 != Terrain.Kind.BUILDING and kn2 != Terrain.Kind.RUBBLE:
					near_street = near_street or 0.5 - (at - Vector2(c)).dot(Vector2(d)) <= PropLayer.YARD_EDGE + 1e-3
			assert_true(near_street, "%s: стовп %s посеред двору" % [p, at])
		assert_gte(maxf(absf(at.x - c.x), absf(at.y - c.y)), 0.45, "%s: стовп %s у центрі клітинки" % [p, at])
		for r in buildings:
			assert_gte(_rect_gap(at, r), PropLayer.POLE_BUILDING_CLEAR - 0.01, "%s: стовп %s ближче за %.2f до будівлі %s" % [p, at, PropLayer.POLE_BUILDING_CLEAR, r])
		for r in homes:
			assert_gte(_rect_gap(at, r), PropLayer.POLE_HOME_CLEAR - 0.01, "%s: стовп %s ближче за %.2f до цілої хати %s" % [p, at, PropLayer.POLE_HOME_CLEAR, r])
		for r in bridges:
			assert_false(r.grow(PropLayer.POLE_BRIDGE_CLEAR).has_point(at), "%s: стовп %s на мосту %s" % [p, at, r])
		for r in smalls:
			assert_false(r.has_point(at), "%s: стовп %s в обрисі паркану чи дрібної речі %s" % [p, at, r])
		for gp: Dictionary in props._garden_plots:
			assert_false((gp["rect"] as Rect2).has_point(at), "%s: стовп %s на грядках %s" % [p, at, gp["rect"]])
	for sp: Array in props._spans:
		var a: Vector2 = _pole_at(props, sp[0])
		var b: Vector2 = _pole_at(props, sp[1])
		for r in buildings:
			for j in 41:
				assert_false(r.grow(PropLayer.POLE_BUILDING_CLEAR - 0.01).has_point(a.lerp(b, float(j) / 40.0)), "%s: проліт %s—%s над будівлею %s" % [p, a, b, r])


## Відтяжки: кутова й кінцева опора їх мають, пряма — ні; анкер стоїть на ґрунті (висота TerrainHeight), не ближче
## POLE_ROAD_CLEAR_M до асфальту й не в сліду юніта. Шафа ТП — КТП 2–3 м заввишки на землі, уся її площа поза асфальтом і
## будівлями, між стовпом і гранню шафи 0.6–1 м, стовп не проходить крізь неї.
func test_guys_and_cabinets_stand_clear(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var m: MapData = _map(p)
	var adj: Dictionary = _neighbours(props)
	var guys: Dictionary = {}
	for g: Array in props._guy_lines():
		guys[g[0]] = g[2]
	var board := Rect2i(0, 0, m.width, m.height)
	for i: int in adj:
		var nb: Array = adj[i]
		var straight: bool = nb.size() == 2 and absf(_angle_at(props, i, nb[0], nb[1])) >= 170.0
		var corner: bool = nb.size() == 1 or (nb.size() == 2 and absf(_angle_at(props, i, nb[0], nb[1])) <= 140.0)
		if straight:
			assert_false(guys.has(i), "%s: пряма опора %s має відтяжку" % [p, _pole_at(props, i)])
		if corner:
			assert_true(guys.has(i), "%s: кутова чи кінцева опора %s без відтяжки" % [p, _pole_at(props, i)])
	for i: int in guys:
		var a: Vector3 = guys[i]
		assert_almost_eq(a.y, view._height.at(a.x, a.z), 0.001, "%s: анкер відтяжки %s не на ґрунті" % [p, Vector2(a.x, a.z)])
		assert_gte(props.road_edge_m(Vector2(a.x, a.z)), PropLayer.POLE_ROAD_CLEAR_M - 0.01, "%s: анкер відтяжки %s на асфальті" % [p, Vector2(a.x, a.z)])
		var c := Vector2i(roundi(a.x), roundi(a.z))
		if board.has_point(c):
			assert_gte(maxf(absf(a.x - c.x), absf(a.z - c.y)), PropLayer.UNIT_HALF + 0.01, "%s: анкер %s у сліду юніта" % [p, Vector2(a.x, a.z)])
	assert_between(PropLayer.TRANSFORMER_SIZE.y * 8.0, 2.0, 3.0, "шафа ТП заввишки")
	var buildings: Array[Rect2] = []
	for inst in props._instances:
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			buildings.append(_rect_of(inst))
	for i: int in props._transformers:
		var pole: Dictionary = props._instances[i]
		var at: Vector3 = props._cabinet_at(pole)
		var basis: Basis = (pole["transform"] as Transform3D).basis
		var side := Vector2(basis.x.x, basis.x.z).normalized()
		var along := Vector2(basis.z.x, basis.z.z).normalized()
		var c2 := Vector2(at.x, at.z)
		var rel: Vector2 = _pole_at(props, i) - c2
		var gap := Vector2(absf(rel.dot(side)) - PropLayer.TRANSFORMER_SIZE.x * 0.5, absf(rel.dot(along)) - PropLayer.TRANSFORMER_SIZE.z * 0.5)
		var face_m: float = maxf(gap.x, gap.y) * 8.0
		assert_between(face_m, PropLayer.POLE_RADIUS * 8.0 + PropLayer.CABINET_GAP_M - 0.01, 1.05, "%s: між стовпом і шафою ТП %s — %.2f м" % [p, c2, face_m])
		var hx: Vector2 = side * PropLayer.TRANSFORMER_SIZE.x * 0.5
		var hz: Vector2 = along * PropLayer.TRANSFORMER_SIZE.z * 0.5
		for q: Vector2 in [c2 + hx + hz, c2 + hx - hz, c2 - hx + hz, c2 - hx - hz, c2]:
			assert_gte(props.road_edge_m(q), PropLayer.POLE_ROAD_CLEAR_M - 0.01, "%s: шафа ТП %s на асфальті" % [p, c2])
			for r in buildings:
				assert_false(r.has_point(q), "%s: шафа ТП %s у будівлі" % [p, c2])


## Мережа 0.4 кВ кожної підстанції — дерево (без кілець): ребер на одне менше за опор; прольоти в плані не перетинаються.
func test_low_voltage_network_is_a_tree_without_crossings(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var adj: Dictionary = _neighbours(props)
	for tp: int in props._transformers:
		var seen: Dictionary = {tp: true}
		var stack: Array[int] = [tp]
		while not stack.is_empty():
			var u: int = stack.pop_back()
			for n: int in adj[u]:
				if _is_04(props, n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		var count: int = 0
		for sp: Array in props._spans:
			if seen.has(sp[0]) and seen.has(sp[1]) and (sp[0] == tp or sp[1] == tp or (_is_04(props, sp[0]) and _is_04(props, sp[1]))):
				count += 1
		assert_eq(count, seen.size() - 1, "%s: мережа 0.4 кВ підстанції %s — не дерево (%d ребер на %d опор)" % [p, _pole_at(props, tp), count, seen.size()])
	for i in props._spans.size():
		var a: Vector2 = _pole_at(props, props._spans[i][0])
		var b: Vector2 = _pole_at(props, props._spans[i][1])
		for j in range(i + 1, props._spans.size()):
			if props._spans[i].any(func(e: int) -> bool: return props._spans[j].has(e)):
				continue
			var x: Variant = Geometry2D.segment_intersects_segment(a, b, _pole_at(props, props._spans[j][0]), _pole_at(props, props._spans[j][1]))
			assert_null(x, "%s: прольоти %s—%s і %s перетинаються в плані" % [p, a, b, _pole_at(props, props._spans[j][0])])


## Плитка грядок лежить на ґрунті: кожен кут і внутрішні точки (сітка 5×5) — на висоті землі плюс
## підйом плитки (0.004) з допуском 3 см, тож рельєф не ріже город на клапті.
func test_garden_beds_lie_on_the_ground(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var th: TerrainHeight = view._height
	var beds: Array[Transform3D] = view.props().garden_beds()
	assert_gt(beds.size(), 0, "%s: є городи" % p)
	for i in beds.size():
		var t: Transform3D = beds[i]
		for j in 5:
			for k in 5:
				var v: Vector3 = t * Vector3(-0.5 + j * 0.25, 0.0, -0.5 + k * 0.25)
				assert_almost_eq(v.y - th.at(v.x, v.z), 0.004, 0.03 * TerrainHeight.M,
						"%s: город %d у (%.2f; %.2f) відходить від ґрунту на %.2f м" % [p, i, v.x, v.z, (v.y - 0.004 - th.at(v.x, v.z)) / TerrainHeight.M])


## Орієнтир кільця Хребта (зруйнована панельна п'ятиповерхівка) стоїть цілком за краєм дошки, на вільному полі, фасадом із язиком до камери.
func test_ridge_ring_landmark_stands_in_the_ring_facing_the_camera() -> void:
	var m: MapData = _map("ridge")
	var found: Array[Dictionary] = []
	for inst in _view(m).props().all_instances():
		if inst["model"] == &"h5_panel_block_damaged":
			found.append(inst)
	assert_eq(found.size(), 1, "рівно один орієнтир")
	if found.is_empty():
		return
	var t: Transform3D = found[0]["transform"]
	var front: Vector3 = t.basis * Vector3(0, 0, -1)                    # −Z моделі — фасад, з якого лежить язик
	assert_gt(front.x + front.z, 0.5, "фасад дивиться до камери (+x чи +z)")
	for c: Vector2i in found[0]["cells"]:
		assert_true(c.x < 0 or c.y < 0 or c.x >= m.width or c.y >= m.height, "клітинка %s за краєм дошки" % c)

## Село не «з одного магазину»: хати садиб ближче HOUSE_APART клітинок — різних форм, а в кожному селі
## (хати, зв'язані відстанню до HOUSE_APART клітинок) з трьох і більше хат — щонайменше три форми.
func test_village_houses_vary(p = use_parameters(MAPS)) -> void:
	var houses: Array = []
	for inst in _cached(p).props().all_instances():
		if String(inst["model"]).begins_with("house_") and not inst.get("yard", false):
			houses.append([(inst["cells"] as Array)[0], inst["model"]])
	assert_gt(houses.size(), 0, "%s: хат немає" % p)
	var seen: Dictionary = {}
	for a in houses.size():
		for b in range(a + 1, houses.size()):
			var d: Vector2i = (houses[a][0] as Vector2i) - (houses[b][0] as Vector2i)
			if maxi(absi(d.x), absi(d.y)) <= PropLayer.HOUSE_APART:
				assert_ne(houses[a][1], houses[b][1], "%s: однакові сусіди %s і %s" % [p, houses[a][0], houses[b][0]])
	for a in houses.size():
		if seen.has(a):
			continue
		var village: Array = [a]
		seen[a] = true
		var k: int = 0
		while k < village.size():
			for b in houses.size():
				var d: Vector2i = (houses[village[k]][0] as Vector2i) - (houses[b][0] as Vector2i)
				if not seen.has(b) and maxi(absi(d.x), absi(d.y)) <= PropLayer.HOUSE_APART:
					seen[b] = true
					village.append(b)
			k += 1
		var forms: Dictionary = {}
		for v in village:
			forms[houses[v][1]] = true
		if village.size() >= 3:
			assert_gte(forms.size(), 3, "%s: село біля %s — лише %d форми на %d хат" % [p, houses[a][0], forms.size(), village.size()])


## Орієнтир кільця Хребта не стоїть під лісом і ЛЕП: ні опора, ні трасa дроту, ні клітинка FOREST з запасом в одну клітинку не лежать на його сліду.
func test_ridge_ring_landmark_keeps_clear_of_forest_and_power_line() -> void:
	var m: MapData = _map("ridge")
	var view: BoardView = _view(m)
	var ring: int = Surroundings.ring_of(m)
	var world: Board = Surroundings.world_board(m.to_board(), m)
	var land: Dictionary = {}
	for inst in view.props().all_instances():
		if inst["model"] == &"h5_panel_block_damaged":
			land = inst
	assert_false(land.is_empty(), "орієнтир є")
	if land.is_empty():
		return
	var box: AABB = (land["transform"] as Transform3D) * ((PropLayer.model(land["model"]) as Dictionary)["aabb"] as AABB)
	var rect := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.3)
	for inst in view.props().all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.POLE:
			var o: Vector3 = (inst["transform"] as Transform3D).origin
			assert_false(rect.has_point(Vector2(o.x, o.z)), "опора на орієнтирі: %s" % o)
	for c: Vector2i in land["cells"]:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var w: Vector2i = c + Vector2i(dx, dy) + Vector2i(ring, ring)
				if world.in_bounds(w):
					assert_ne(world.kind_at(w), Terrain.Kind.FOREST, "ліс біля орієнтира на %s" % w)


## Бюджет кадру (§8): стовпи воріт, уламки руїн і шафи підстанцій — однакові коробки, тож один
## MultiMesh, а не три виклики малювання.
func test_small_boxes_share_one_multimesh(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	for gone: StringName in [&"GatePosts", &"RubbleDebris", &"Transformers"]:
		assert_null(props.get_node_or_null(NodePath(gone)), "%s: %s злито" % [p, gone])
	var boxes: MultiMeshInstance3D = props.get_node_or_null("SmallBoxes")
	assert_not_null(boxes, "%s: спільний вузол є" % p)
	assert_eq(boxes.multimesh.instance_count, props._small_base.size(), "%s: екземплярів стільки, скільки коробок" % p)
	assert_gte(props._small_base.size(), props._gate_posts.size() + props._transformers.size(), p)
	assert_eq(boxes.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Дрібні пропси з зумом не зникають: на найбільшому віддаленні сіно, брили й коробки видно.
func test_small_props_stay_visible_at_max_zoom() -> void:
	var props: PropLayer = _cached("crossroads").props()
	var small: Array[Node] = props.find_children("*", "MultiMeshInstance3D", false, false).filter(func(n: Node) -> bool:
		return n.name == &"SmallBoxes" or int(PropLayer.spec_of(StringName(n.name)).get("kind", -1)) in [PropLayer.Kind.HAY, PropLayer.Kind.BOULDER])
	assert_gt(small.size(), 2, "передумова: на карті є дрібні вузли")
	for n: Node in small:
		assert_true((n as Node3D).visible, "%s: видно на будь-якому зумі" % n.name)
