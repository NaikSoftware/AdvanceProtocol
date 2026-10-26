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
	var view: BoardView = _view(m)
	var checked: int = 0
	for inst in view.props().all_instances():
		# Двірське вбрання стоїть на клітинці BUILDING, як і будинок; правило — для прохідних клітинок.
		if not _is_small(inst["model"]) or inst.get("yard", false):
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
	var view: BoardView = _cached(p)
	assert_lte(view.props().triangle_count(), TRIS_GUARD, p)


func test_one_multimesh_per_model(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var models: Dictionary = {}
	for inst in view.props().all_instances():
		models[inst["model"]] = true
	var mmis: Array[Node] = view.props().find_children("*", "MultiMeshInstance3D", false, false).filter(
			func(n: Node) -> bool: return n.name != &"ContactShadows" and n.name != &"GardenBeds")
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
	var view: BoardView = _view(_map("crossroads"))
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
	var view: BoardView = _view(_map("ridge"))
	var stones: int = 0
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		stones += 1 if k in [PropLayer.Kind.BOULDER, PropLayer.Kind.BLOCK, PropLayer.Kind.RUIN] else 0
	var blobs: MultiMeshInstance3D = view.props().get_node("ContactShadows")
	assert_eq(blobs.multimesh.instance_count, stones)
	# Дзеркальний базис перевертає обхід трикутників, і cull_back викидає пляму зовсім.
	for i in blobs.multimesh.instance_count:
		assert_gt(blobs.multimesh.get_instance_transform(i).basis.determinant(), 0.0, "пляма %d дзеркальна" % i)


## Будівлі моделі, над якою ніхто не стоїть, малюються шейдером без discard.
func test_unfaded_structures_use_the_solid_material() -> void:
	var view: BoardView = _view(null, _house_board())
	var p: PropLayer = view.props()
	var node: MultiMeshInstance3D = null
	for n: MultiMeshInstance3D in p.find_children("*", "MultiMeshInstance3D", false, false):
		if n.name != &"ContactShadows" and _kind(StringName(n.name)) == PropLayer.Kind.STRUCTURE:
			node = n
	assert_not_null(node)
	assert_false(((node.material_override as ShaderMaterial).shader.code).contains("discard"))
	view.set_reveal_cells([Vector2i(2, 2)] as Array[Vector2i])
	p._flush()
	assert_true(((node.material_override as ShaderMaterial).shader.code).contains("discard"))


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
		var k: int = _kind(StringName(n.name))
		# Тінь кидають лише будинки дошки; руїни — плямою дотику, кільце й дрібнота — без тіні.
		var casts: bool = k == PropLayer.Kind.STRUCTURE and not String(n.name).ends_with("_ring")
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


## Огорожа двору стоїть лише довкола групи, де є будівля: порожній обгороджений двір читається
## уламком огорожі серед поля.
func test_only_built_yards_are_fenced(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _view(m)
	# Забудована — клітинка BUILDING із будинком, двірським вбранням чи городом.
	var built: Dictionary = {}
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
		var has_built := false
		for d in Board.DIRS_4:
			has_built = has_built or built.has(c + d)
		assert_true(has_built, "%s: огорожа на %s не при будинку" % [p, c])
		fences += 1
	assert_gt(fences, 0, "%s: передумова — двори обгороджені" % p)


## Огорожа двору — щонайменше 0.3 клітинки від даху будь-якої будівлі, вежа — 0.5 від будівель.
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
		for b in houses + towers:
			assert_false(b.grow(0.3 - 1e-4).intersects(f), "%s: огорожа %s ближче 0.3 клітинки до будівлі %s" % [p, f, b])
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
	var view: BoardView = _view(m)
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
const RIVER_BUILDINGS_FINGERPRINT: int = 2262903032


func test_river_buildings_match_the_golden_fingerprint() -> void:
	var view: BoardView = _view(_map("river"))
	var parts: PackedStringArray = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var c: Vector2i = (inst["cells"] as Array)[0]
			parts.append("%s@%d,%d" % [inst["model"], c.x, c.y])
	parts.sort()
	assert_eq(";".join(parts).hash(), RIVER_BUILDINGS_FINGERPRINT, ";".join(parts))



## §8: кожна клітинка BUILDING дошки видимо забудована — будинком або двором (повітка, дрова,
## причіп, тюк), а не голою травою.
func test_every_building_cell_reads_built_up(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _view(m)
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if board.kind_at(c) == Terrain.Kind.BUILDING:
				assert_false(view.props().instances_on(c).is_empty(), "%s: порожня клітинка BUILDING %s" % [p, c])



## Секція огорожі двору не коротша за MIN_FENCE: обрубок читається уламком.
func test_no_fence_stubs(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	for inst in view.props().all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.GARDEN_FENCE:
			assert_gte(_length(inst), PropLayer.MIN_FENCE - 1e-3, "%s: обрубок огорожі на %s" % [p, inst["cells"]])


## На мокрій карті мости беруть темнішу й блискучішу копію сітки; суха — імпортовану.
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
		if wet:
			assert_almost_eq(got.albedo_color.r, src.albedo_color.r * PropLayer.WET_DARK, 1e-3)
			assert_lte(got.roughness, PropLayer.WET_ROUGHNESS + 1e-4)
		else:
			assert_eq(got, src, "суха карта — імпортований матеріал")


## Руїна з глухим фронтоном стоїть пошкодженим фасадом (−Z) до камери (+x чи +z).
func test_blank_gable_ruins_face_away_from_the_camera(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	for inst in view.props().all_instances():
		if PropLayer.CAMERA_FRONT.has(inst["model"]):
			var front: Vector3 = -(inst["transform"] as Transform3D).basis.z
			assert_gt(front.x + front.z, 0.5, "%s: %s фасадом від камери" % [p, inst["model"]])


## Дахи будинків мають різні відтінки, руїни й двірське вбрання — без відтінку.
func test_roofs_get_varied_tints() -> void:
	var view: BoardView = _view(_map("crossroads"))
	var p: PropLayer = view.props()
	var tints: Dictionary = {}
	for inst in p.all_instances():
		if _kind(inst["model"]) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false):
			tints[p._roof_tint(inst)] = true
		elif _kind(inst["model"]) == PropLayer.Kind.RUIN:
			assert_eq(p._roof_tint(inst), Color(1, 1, 1))
	assert_gte(tints.size(), 3, "щонайменше три відтінки дахів")


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
	var view: BoardView = _view(_map("ridge"))
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
	var view: BoardView = _view(m)
	var houses: int = 0
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		var c: Vector2i = (inst["cells"] as Array)[0]
		if int(s["kind"]) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false) \
				and not bool(s.get("tower", false)) and board.in_bounds(c):
			houses += 1
	assert_gte(houses, 4)
