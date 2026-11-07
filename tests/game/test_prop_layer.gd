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
## Опора 0.4 кВ не далі за стільки клітинок від хати поселення — це його лінія; кінець гілки 0.4 кВ без відводу —
## не далі за STREET_END від хати.
const STREET_R: float = 7.0
const STREET_END: float = 3.0
## Найближче, як стовп ЛЕП може стояти до секції паркану двору, клітинки (2.4 м).
const FENCE_POLE_CLEAR: float = 0.3
## Скільки воріт карти може стояти з послабленим правилом стіни чи екрана (test_gates_do_not_run_alongside_walls).
const RELAXED_GATES: Dictionary = {"crossroads": 1}


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


## Мокра «Річка» з поверхнею й зерном рельєфу: один вид на мокрі міст і тюки, що лише читають матеріали.
func _wet_river() -> BoardView:
	if not _views.has("river#wet"):
		var m: MapData = _map("river")
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		view.wet = true
		view.build(m.to_board())
		_views["river#wet"] = view
	return _views["river#wet"]


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
	var board: Board = _map("river").to_board()
	# Спільний вигляд Річки перебудовується двічі: зруйнувати й полагодити міст.
	# Наприкінці він має бути таким самим, як до тесту, бо на ньому йдуть інші тести Річки.
	var view: BoardView = _cached("river")
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
	var step: Array[Vector2i] = _hit_step(view.props(), (view.props()._instances[_fence_index(view, fence_cell)]["transform"] as Transform3D).origin,
			_fence_index(view, fence_cell))
	assert_eq(step.size(), 2, "передумова: смуга корпусу зачіпає секцію")
	var edge := Vector4i(step[0].x, step[0].y, step[1].x, step[1].y)
	view.set_crushed_cells([fence_cell, Vector2i(3, 3)] as Array[Vector2i], false, [edge])
	var after: Dictionary = _fences_on(view, fence_cell)[0]
	assert_true(after["crushed"])
	assert_ne(after["transform"], before, "повалена огорожа лежить інакше")
	for inst in view.props().instances_on(Vector2i(3, 3)):
		assert_false(inst["crushed"], "будинок не чавиться")
	# Секції далі за тайл від смуги кроку лишаються цілими.
	var strip_a := Vector2(step[0])
	var strip_b := Vector2(step[1])
	for i in view.props()._instances.size():
		var inst: Dictionary = view.props()._instances[i]
		if inst["band"]:
			var o := Vector2((inst["transform"] as Transform3D).origin.x, (inst["transform"] as Transform3D).origin.z)
			if o.distance_to(Geometry2D.get_closest_point_to_segment(o, strip_a, strip_b)) > 1.5:
				assert_false(view.props()._is_crushed(inst), "далека секція ціла")
	assert_lt(view.props()._broken.size(), view.props().all_instances().filter(func(i: Dictionary) -> bool: return i["band"]).size(),
			"решта парканів стоїть")


## Крок техніки (from, to), смуга якого зачіпає екземпляр inst: to — клітинка під екземпляром, from — сусідня.
func _hit_step(props: PropLayer, origin: Vector3, inst: int = -1, gate: int = -1) -> Array[Vector2i]:
	var base := Vector2i(roundi(origin.x), roundi(origin.z))
	for off: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var to: Vector2i = base + off
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var hits: Dictionary = props.band_hits(to + d, to)
			if (inst >= 0 and (hits["inst"] as Array).has(inst)) or (gate >= 0 and (hits["gates"] as Array).has(gate)):
				return [to + d, to]
	return []


func _fence_index(view: BoardView, cell: Vector2i) -> int:
	for i in view.props()._instances.size():
		var inst: Dictionary = view.props()._instances[i]
		if inst["band"] and (inst["cells"] as Array).has(cell):
			return i
	return -1


## Валить опору кроком, смуга корпусу якого її зачіпає; повертає [from, to].
func _topple_pole(props: PropLayer, idx: int) -> Array[Vector2i]:
	var step: Array[Vector2i] = _hit_step(props, (props._instances[idx]["transform"] as Transform3D).origin, idx)
	assert_eq(step.size(), 2, "передумова: смуга корпусу зачіпає опору")
	props.topple_cell(step[1], step[0])
	return step


func _fences_on(view: BoardView, cell: Vector2i) -> Array[Dictionary]:
	return view.props().instances_on(cell).filter(
			func(i: Dictionary) -> bool: return _kind(i["model"]) == PropLayer.Kind.GARDEN_FENCE)


## Повалена опора забирає дроти своїх прольотів.
func test_crushed_pole_drops_its_wires() -> void:
	var view: BoardView = _cached("river")
	var p: PropLayer = view.props()
	var spans: int = p.wire_spans()
	assert_gt(spans, 0, "на River є лінія")
	var wi: int = _wired_pole(p)
	var pole_cell: Vector2i = (p._instances[wi]["cells"] as Array)[0]
	var pstep: Array[Vector2i] = _hit_step(p, (p._instances[wi]["transform"] as Transform3D).origin, wi)
	view.set_crushed_cells([pole_cell] as Array[Vector2i], false, [Vector4i(pstep[0].x, pstep[0].y, pstep[1].x, pstep[1].y)])
	assert_lt(p.wire_spans(), spans)
	# Вид спільний з іншими тестами: повалене повертаємо.
	view.set_crushed_cells([] as Array[Vector2i])


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


## Один вузол MultiMesh на модель (на «batch» моделей), без тіні.
func test_one_multimesh_per_model(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	# Вузол — модель, а моделі одного «batch» (види паркану двору) — один спільний вузол.
	var models: Dictionary = {}
	for inst in view.props().all_instances():
		models[StringName(PropLayer.spec_of(inst["model"]).get("batch", inst["model"]))] = true
	var mmis: Array[Node] = view.props().find_children("*", "MultiMeshInstance3D", false, false).filter(
			func(n: Node) -> bool: return not n.name in [&"ContactShadows", &"GardenBeds", &"HouseGrime", &"RubbleFloors", &"RubbleDebris", &"YardPaths", &"Transformers", &"GatePosts", &"SmallBoxes", &"GateMesh"] and not String(n.name).ends_with("_fade"))
	# Модель — вузол дошки й, для будівель кільця, ще «модель_ring» (кільце відсікається окремо).
	var keys: Dictionary = {}
	for n in mmis:
		var m := StringName(String(n.name).trim_suffix("_ring").trim_suffix("_alpha"))
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


## Стовпи, дроти й шафи ЛЕП тонуть в імлі кільця, як будинки поруч: кожен їхній матеріал несе ті самі
## параметри кільця (`Surroundings.apply`), інакше лінія в кільці малюється темною поверх імли.
func test_power_line_takes_the_haze(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var props: PropLayer = _cached(p).props()
	var board := Vector2(m.width, m.height)
	var mats: Array = []
	for n: Node in props.get_children():
		if n is MultiMeshInstance3D and _kind(StringName(n.name)) == PropLayer.Kind.POLE:
			var mesh: Mesh = (n as MultiMeshInstance3D).multimesh.mesh
			for s in mesh.get_surface_count():
				mats.append([String(n.name), mesh.surface_get_material(s)])
	assert_gt(mats.size(), 0, "%s: стовпи є" % p)
	assert_not_null(props._wires, "%s: дроти є" % p)
	mats.append(["Wires", props._wires.material_override])
	if props._transformer_node != null:
		mats.append(["Transformers", (props._transformer_node.multimesh.mesh as PrimitiveMesh).material])
	for e: Array in mats:
		var mat := e[1] as ShaderMaterial
		assert_not_null(mat, "%s: %s — матеріал з імлою кільця" % [p, e[0]])
		if mat != null:
			assert_true(mat.get_shader_parameter("surround"), "%s: %s" % [p, e[0]])
			assert_eq(mat.get_shader_parameter("board_size"), board, "%s: %s" % [p, e[0]])


## Пляма дотику лягає й під руїни кільця (Хребет): без імли вона чорніє поверх пелени, у якій тонуть самі руїни.
func test_contact_shadows_take_the_haze(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var props: PropLayer = _cached(p).props()
	assert_not_null(props._contacts, "%s: плями дотику є" % p)
	var mat := (props._contacts.multimesh.mesh as PrimitiveMesh).material as ShaderMaterial
	assert_true(mat.get_shader_parameter("surround"), p)
	assert_eq(mat.get_shader_parameter("board_size"), Vector2(m.width, m.height), p)


## Огорожі, тюки, брили, бетонні блоки й причепи стоять лише на дошці: їхні матеріали імли кільця не знають.
## Карта, що поставить такий пропс у кільце, мусить спершу дати йому імлу, як стовпам.
func test_small_props_stay_off_the_ring(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var small: Array = [PropLayer.Kind.FIELD_FENCE, PropLayer.Kind.GARDEN_FENCE, PropLayer.Kind.HAY,
			PropLayer.Kind.BOULDER, PropLayer.Kind.BLOCK, PropLayer.Kind.TRAILER]
	for inst in _cached(p).props().all_instances():
		if _kind(inst["model"]) in small:
			var o: Vector3 = (inst["transform"] as Transform3D).origin
			assert_true(o.x >= -0.5 and o.z >= -0.5 and o.x <= m.width - 0.5 and o.z <= m.height - 0.5,
					"%s: %s у кільці (%.1f, %.1f)" % [p, inst["model"], o.x, o.z])


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


## Огорожа двору стоїть лише довкола садиби (на карті з макетом — на клітинці її двору) чи групи,
## де є будівля: порожній обгороджений двір читається уламком огорожі серед поля.
func test_only_built_yards_are_fenced(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var board: Board = m.to_board()
	var view: BoardView = _cached(p)
	# Забудована — клітинка BUILDING із будинком, двірським вбранням чи городом, або двір садиби.
	var built: Dictionary = _layout_yards(p, false)
	# Клітинки fenced паркан садиби обгороджує разом із її двором: вони теж при будинку.
	for home: Dictionary in VillageLayout.for_map(StringName(p)).get("homes", []):
		for c: Vector2i in home.get("fenced", []):
			built[c] = true
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


## Слід стін моделі: контрольні числа двох хат (кінець по +x у координатах моделі, тайли), щоб помилка в обчисленні сліду не
## проходила сама собою (інші тести міряють від нього ж).
func test_wall_footprint_of_known_houses() -> void:
	for pair: Array in [[&"house_h8", 0.32], [&"house_h4", 0.52]]:
		var info: Variant = PropLayer.model(pair[0])
		if info == null:
			continue
		var foot: AABB = (info as Dictionary)["foot"]
		var full: AABB = (info as Dictionary)["aabb"]
		assert_almost_eq(foot.end.x, float(pair[1]), 0.01, "%s: слід стін по +x" % pair[0])
		assert_lte(foot.end.x, full.end.x + 1e-4, "%s: слід у межах обрису" % pair[0])


## Слід стін хат (model()["foot"]) збігається з розмірами стін у конвеєрі Blender (PropLayer.WALL_SIZES, ±0,02) і покриває
## щонайменше 85 % обрису по кожній осі; виняток — із причиною (ґанок із дашком, веранда, димар виступають за стіну).
const FOOT_EXCEPTIONS: Dictionary = {
	&"house_h2": "ґанок з дашком виступає за стіну по z",
	&"house_h3": "ґанок з дашком виступає за стіну по z",
	&"house_h4": "ґанок з дашком виступає за стіну по z",
	&"house_h7": "ґанок з дашком виступає за стіну по z",
	&"house_h8": "ґанок з дашком й приставний димар виступають за стіну",
}


func test_wall_footprints_match_the_builders() -> void:
	for name: StringName in PropLayer.WALL_SIZES:
		var info: Variant = PropLayer.model(name)
		if info == null:
			continue
		var foot: AABB = (info as Dictionary)["foot"]
		var full: AABB = (info as Dictionary)["aabb"]
		var want: Vector2 = PropLayer.WALL_SIZES[name]
		assert_almost_eq(foot.size.x, want.x, 0.02, "%s: слід по x відповідає розміру стін з Blender" % name)
		assert_almost_eq(foot.size.z, want.y, 0.02, "%s: слід по z відповідає розміру стін з Blender" % name)
		var share: Vector2 = Vector2(foot.size.x / full.size.x, foot.size.z / full.size.z)
		if not FOOT_EXCEPTIONS.has(name):
			assert_gte(minf(share.x, share.y), 0.85, "%s: слід покриває мало обрису (%s)" % [name, share])
	# Модель поза списком (сарай, комора) — слід дорівнює обрису.
	var barn: Variant = PropLayer.model(&"f2_livestock_barn")
	if barn != null:
		assert_eq((barn as Dictionary)["foot"], (barn as Dictionary)["aabb"], "поза списком — обрис")


## Ланки Г-подібних обходів до сліду стін (detour_legs) підпорядковані тим самим правилам, що й секції: не на дорозі, не в сліді
## будівлі, не на опорі й не на стовпі воріт, не перетинають інших секцій.
func test_detour_legs_obey_fence_rules(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var legs: Array = props._placer.detour_legs
	var foots: Array[Rect2] = []
	var poles: Array[Rect2] = []
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			foots.append(PropLayer.wall_rect(inst))
		elif k == PropLayer.Kind.POLE:
			var b: AABB = _box_of(inst)
			poles.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	var posts: Array[Vector2] = []
	for g: Dictionary in props._gates:
		posts.append_array([g["a"], g["mid"], g["b"]])
	for leg: Array in legs:
		for t in 6:
			var q: Vector2 = (leg[0] as Vector2).lerp(leg[1], float(t) / 5.0)
			assert_gte(props.road_edge_m(q), PropLayer.FENCE_ROAD_INSET * 8.0, "%s: ланка обходу %s на асфальті" % [p, q])
			for f: Rect2 in foots:
				assert_false(f.grow(-0.005).has_point(q), "%s: ланка обходу %s у сліді стін" % [p, q])
			for r: Rect2 in poles:
				assert_false(r.grow(0.02).has_point(q), "%s: ланка обходу %s на опорі" % [p, q])
			for g: Vector2 in posts:
				assert_gt(g.distance_to(q), 0.03, "%s: ланка обходу %s на стовпі воріт" % [p, q])
	gut.p("%s: ланок обходу %d" % [p, legs.size()])


## Огорожа двору доходить до стіни, але не заходить у слід її стін (без звісу даху й димаря) і тримається
## 0.3 клітинки від вежі; вежа — 0.5 від будівель.
func test_fences_and_towers_keep_clear(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var towers: Array[Rect2] = []
	var houses: Array[Rect2] = []
	var house_boxes: Array[Rect2] = []
	var fences: Array[Rect2] = []
	for inst in view.props().all_instances():
		var s: Dictionary = PropLayer.spec_of(inst["model"])
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if bool(s.get("tower", false)):
			towers.append(r)
		elif int(s["kind"]) == PropLayer.Kind.STRUCTURE or int(s["kind"]) == PropLayer.Kind.RUIN:
			# Слід стін без звісу даху й димаря: паркан доходить до стіни, але не заходить у неї.
			houses.append(PropLayer.wall_rect(inst))
			house_boxes.append(r)
		elif int(s["kind"]) == PropLayer.Kind.GARDEN_FENCE:
			fences.append(r)
	assert_gt(fences.size(), 0, "%s: передумова — огорожі є" % p)
	for f in fences:
		for b in houses:
			assert_false(b.grow(-0.01).intersects(f), "%s: огорожа %s заходить у будівлю %s" % [p, f, b])
		for b in towers:
			assert_false(b.grow(0.3 - 1e-4).intersects(f), "%s: огорожа %s ближче 0.3 клітинки до вежі %s" % [p, f, b])
	for t in towers:
		for b in house_boxes:
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
const RIVER_BUILDINGS_FINGERPRINT: int = 705048882


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
			joined = joined or w.grow(0.03).has_point(ends[i])
		if not joined:
			loose.append(ends[i])
	var homes: int = (VillageLayout.for_map(StringName(p)).get("homes", []) as Array).size()
	assert_eq(loose.size(), 2 * homes, "%s: вільні кінці паркану %s" % [p, loose])
	for e in loose:
		var pair: bool = loose.any(func(o: Vector2) -> bool: return o != e and o.distance_to(e) <= PropLayer.GATE + 0.03)
		assert_true(pair, "%s: кінець паркану %s без пари воріт — кільце розірване" % [p, e])


## Кожен ланцюг секцій паркану (з'єднаних кінцями) кінчається лише на грані будівлі (з вистрілом даху, ≤ 0.03), на
## кінці іншого ланцюга чи на стовпі воріт; ланцюг коротший за MIN_FENCE (0.5 клітинки, 4 м) — уламок, крім
## того, що тримає стовп воріт (вузька сторона двору); секції на дорозі нема.
func test_fence_runs_end_on_walls_or_gate_posts(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var walls: Array[Rect2] = []
	var secs: Array = []
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = _box_of(inst)
			walls.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
		elif k == PropLayer.Kind.GARDEN_FENCE or k == PropLayer.Kind.FIELD_FENCE:
			var xf: Transform3D = inst["transform"]
			var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
			var a3: Vector3 = xf * Vector3(box.position.x, 0.0, 0.0)
			var b3: Vector3 = xf * Vector3(box.end.x, 0.0, 0.0)
			secs.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), k == PropLayer.Kind.GARDEN_FENCE])
			for t in 5:
				var q: Vector2 = Vector2(a3.x, a3.z).lerp(Vector2(b3.x, b3.z), float(t) / 4.0)
				assert_false(props.on_road(q), "%s: секція паркану на дорозі в %s" % [p, q])
	var posts: Array[Vector2] = []
	for g: Dictionary in props._gates:
		posts.append_array([g["a"], g["mid"], g["b"]])
	# Ланцюги садибних секцій: союз за збіг кінців.
	var garden: Array = secs.filter(func(s: Array) -> bool: return s[2])
	var parent: Array[int] = []
	for i in garden.size():
		parent.append(i)
	var root := func(i: int) -> int:
		while parent[i] != i:
			i = parent[i]
		return i
	for i in garden.size():
		for j in range(i + 1, garden.size()):
			for ea: Vector2 in [garden[i][0], garden[i][1]]:
				for eb: Vector2 in [garden[j][0], garden[j][1]]:
					if ea.distance_to(eb) < 0.03:
						parent[root.call(i)] = root.call(j)
	var size_of: Dictionary = {}
	var gated: Dictionary = {}
	for i in garden.size():
		var ri: int = root.call(i)
		size_of[ri] = float(size_of.get(ri, 0.0)) + (garden[i][0] as Vector2).distance_to(garden[i][1])
		for q in posts:
			if q.distance_to(garden[i][0]) < 0.04 or q.distance_to(garden[i][1]) < 0.04:
				gated[ri] = true
	# Секція між двома стінами (просвіт між хатою й руїною вужчий за ворота): обидва вільні кінці ланцюга стоять на стінах.
	var spans: Dictionary = {}
	for r: int in size_of:
		var free_ends: Array[Vector2] = []
		for i in garden.size():
			if root.call(i) != r:
				continue
			for e: Vector2 in [garden[i][0], garden[i][1]]:
				var shared := false
				for j in garden.size():
					shared = shared or (j != i and root.call(j) == r and (e.distance_to(garden[j][0]) < 0.005 or e.distance_to(garden[j][1]) < 0.005))
				if not shared:
					free_ends.append(e)
		var on_walls := not free_ends.is_empty()
		for e: Vector2 in free_ends:
			var hit := false
			for w in walls:
				hit = hit or w.grow(0.05).has_point(e)
			on_walls = on_walls and hit
		if on_walls:
			spans[r] = true
	for r: int in size_of:
		assert_true(float(size_of[r]) >= PropLayer.MIN_FENCE - 1e-3 or gated.has(r) or spans.has(r), "%s: уламок паркану завдовжки %.2f біля %s" % [p, size_of[r], garden[r][0]])
	for i in garden.size():
		for e: Vector2 in [garden[i][0], garden[i][1]]:
			var ok := false
			for j in garden.size():
				for eb: Vector2 in [garden[j][0], garden[j][1]]:
					ok = ok or (j != i and eb.distance_to(e) < 0.03)
			for w in walls:
				ok = ok or w.grow(0.03).has_point(e)
			for q in posts:
				ok = ok or q.distance_to(e) < 0.04
			assert_true(ok, "%s: кінець паркану %s висить у повітрі" % [p, e])


## Міст — матова копія сітки (ассет мав «мокрі» поверхні з шорсткістю 0.15, міст блищав склом); на
## мокрій карті ще й темніша.
func test_wet_map_darkens_bridges() -> void:
	for wet: bool in [false, true]:
		var view: BoardView = _wet_river() if wet else _cached("river")
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


## Покриття настилу на мокрій карті йде за дорогою: ґрунтове (панельний і понтонний мости, також
## зруйновані) — тоном ґрунтівки DIRT_DECK_WET і матове, як ґрунтова дорога в шейдері землі (з 0.55
## воно відбивало небо холодною сірою плитою); асфальт центрального — ASPHALT_DECK_WET. Обидва кінці
## настилу переходять до тону дороги свого в'їзду (DECK_END_TINT): один тон на весь настил не
## збігався з обома в'їздами, і на стику лишалась сходинка яскравості.
func test_wet_map_keeps_decks_in_the_road_tone() -> void:
	var expect: Dictionary = {
		&"bridge_river_west": ["bridge_asphalt1", "bridge_deckplate"],
		&"bridge_river_west_broken": ["bridge_asphalt1", "bridge_deckplate"],
		&"bridge_river_east": ["bridge_deckplate"],
		&"bridge_river_east_broken": ["bridge_deckplate"],
		&"bridge_river_centre": ["bridge_asphalt"],
		&"bridge_river_centre_broken": ["bridge_asphalt"],
	}
	for m: StringName in expect:
		var src: Mesh = PropLayer.model(m)["mesh"]
		var mesh: Mesh = PropLayer._bridge_mesh(m, src, true)
		var tint: Array = PropLayer.DECK_END_TINT[StringName(String(m).trim_suffix("_broken"))]
		var found: Array = []
		for i in mesh.get_surface_count():
			var name: String = src.surface_get_material(i).resource_name
			if name not in expect[m]:
				continue
			found.append(name)
			var got := mesh.surface_get_material(i) as ShaderMaterial
			assert_not_null(got, "%s: %s без переходу до дороги" % [m, name])
			if got == null:
				continue
			var k: Color = Color(PropLayer.ASPHALT_DECK_WET, PropLayer.ASPHALT_DECK_WET, PropLayer.ASPHALT_DECK_WET) \
					if name == "bridge_asphalt" else PropLayer.DIRT_DECK_WET
			var a: Color = (src.surface_get_material(i) as BaseMaterial3D).albedo_color * k
			var alb: Color = got.get_shader_parameter("albedo")
			assert_almost_eq(alb.r, a.r, 1e-3, "%s: %s" % [m, name])
			assert_almost_eq(alb.b, a.b, 1e-3, "%s: %s" % [m, name])
			assert_eq(got.get_shader_parameter("end_lo"), Vector3(tint[0].r, tint[0].g, tint[0].b), "%s: %s кінець -Z" % [m, name])
			assert_eq(got.get_shader_parameter("end_hi"), Vector3(tint[1].r, tint[1].g, tint[1].b), "%s: %s кінець +Z" % [m, name])
			# Перехід згасає до бортів: півширина покриття — з його ж вершин.
			assert_between(float(got.get_shader_parameter("edge_x")), 0.15, 0.5, "%s: %s півширина покриття" % [m, name])
			if name != "bridge_asphalt":
				assert_gte(float(got.get_shader_parameter("roughness")), PropLayer.DIRT_DECK_ROUGH - 1e-4, "%s: %s блищить" % [m, name])
		found.sort()
		var want: Array = (expect[m] as Array).duplicate()
		want.sort()
		assert_eq(found, want, "%s: покриття настилу" % m)


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


## Колір даху з палітри мають лише хати: руїни, сараї й ферми лишаються з текстури моделі.
func test_only_houses_get_a_roof_colour(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	for inst in props.all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var house: bool = String(inst["model"]).begins_with("house_") and not inst.get("yard", false)
			assert_eq(props._roof_tint(inst) != Color(0, 0, 0), house, "%s: %s" % [p, inst["model"]])


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


## Блок біля мосту не впирається в підніжжя опори: від його габариту до стовпа щонайменше 0.3 клітинки.
func test_blocks_keep_clear_of_poles(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var poles: Array[Vector2] = []
	var blocks: Array[Rect2] = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		var xf: Transform3D = inst["transform"]
		if k == PropLayer.Kind.POLE:
			poles.append(Vector2(xf.origin.x, xf.origin.z))
		elif k == PropLayer.Kind.BLOCK:
			var b: AABB = xf * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
			blocks.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	for r: Rect2 in blocks:
		for q: Vector2 in poles:
			assert_false(r.grow(PropLayer.BLOCK_POLE_GAP).has_point(q), "%s: блок %s ближче за %.1f до опори %s" % [p, r, PropLayer.BLOCK_POLE_GAP, q])


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
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN and not PropLayer.YARD_SHEDS.has(inst["model"]):
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


## В'їзд на міст — насип: від центру клітинки дороги до опори ґрунт лише піднімається (ні ями
## перед мостом, ні горба), а від краю клітинки мосту на 0.1 клітинки (там кінці настилів усіх трьох
## моделей; SEAT_REACH далі — лише до відліку меша) лежить урівень із покриттям
## настилу (deck_y + SEAT_TOP), тож дорога заходить на настил без сходинки.
func test_bridge_approach_rises_to_the_deck_without_a_dip() -> void:
	var view: BoardView = _cached("river")
	var h: TerrainHeight = view._height
	var ends := 0
	for g in h.bridge_groups():
		var cells: Array = g["cells"]
		var a := Vector2i(g["axis"])
		for c: Vector2i in cells:
			for d: Vector2i in [a, -a]:
				var n: Vector2i = c + d
				if cells.has(n) or n.x < 0 or n.y < 0 or n.x >= 26 or n.y >= 22:
					continue
				ends += 1
				var seat: float = h.deck_y(c) + TerrainHeight.SEAT_TOP
				for off: float in [-0.3, 0.0, 0.3]:
					var side := Vector2(-d.y, d.x) * off
					var top := -INF
					for k in 57:
						var t: float = float(k) / 56.0 * 0.6
						var p: Vector2 = Vector2(n) - Vector2(d) * t + side
						var y: float = h.at(p.x, p.y)
						assert_gt(y, top - 0.002, "%s->%s бік %.1f: яма перед мостом на %.2f клітинки, %.2f м нижче" % [n, c, off, t, (top - y) / TerrainHeight.M])
						top = maxf(top, y)
						if t >= 0.5:
							assert_almost_eq(y, seat, 0.004, "%s->%s бік %.1f: на %.2f клітинки ґрунт на %.2f м від настилу" % [n, c, off, t, (y - seat) / TerrainHeight.M])
	assert_eq(ends, 6, "відкритих кінців переправ на дошці")


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


## Хати макету дивляться фасадом — стіною з дверима — туди, куди каже садиба: −Z моделі, а в house_h5,
## де двері на тильній стіні, +Z.
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
		if house[0]["model"] == &"house_h5":
			front = -front
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


## Дим із димаря — лише з цілої хати. На картах пошкоджених моделей нема, тож підставляємо в розстановку
## копію цілої хати з моделлю house_h1_hit: її маркер не дає точки, а в house_h1 — дає.
func test_no_chimney_smoke_over_damaged_houses_or_ruins() -> void:
	for m in [&"house_h1_hit", &"f3_hangar_damaged", &"h5_panel_block_damaged"]:
		assert_true(bool(PropLayer.spec_of(m).get("damaged", false)), "%s не позначена damaged" % m)
	assert_gt(((PropLayer.model(&"house_h1_hit") as Dictionary)["chimneys"] as Array).size(), 0, "у пошкодженої хати є маркер, який треба ігнорувати")
	var props: PropLayer = _cached("crossroads").props()
	var src: Dictionary = {}
	for inst in props.all_instances():
		if int(PropLayer.spec_of(inst["model"])["kind"]) == PropLayer.Kind.STRUCTURE and not inst.get("yard", false) \
				and Rect2i(0, 0, 26, 22).has_point((inst["cells"] as Array)[0]) and not (PropLayer.model(inst["model"]) as Dictionary)["chimneys"].is_empty():
			src = inst
			break
	assert_false(src.is_empty())
	var base: int = props.chimney_tops().size()
	var copy: Dictionary = src.duplicate()
	copy["model"] = &"house_h1_hit"
	props.all_instances().append(copy)
	assert_eq(props.chimney_tops().size(), base, "дим над house_h1_hit")
	copy["model"] = &"house_h1"
	assert_eq(props.chimney_tops().size(), base + 1, "ціла house_h1 дає точку")
	props.all_instances().erase(copy)
	assert_eq(props.chimney_tops().size(), base)


## Руїна тліє з уламків усередині обрису: точка не вище 0,1 клітинки над геометрією руїни в тому
## самому місці (не в повітрі).
func test_ruin_smoke_rises_from_the_rubble_surface() -> void:
	for name in MAPS:
		var props: PropLayer = _cached(name).props()
		var m: MapData = _map(name)
		var pts: Array[Vector3] = props.ruin_smoke_points()
		var centres: Array[Vector3] = props.ruin_centres()
		var boxes: Array[AABB] = []
		var insts: Array[Dictionary] = []
		for inst in props.all_instances():
			if int(PropLayer.spec_of(inst["model"])["kind"]) == PropLayer.Kind.RUIN \
					and Rect2i(0, 0, m.width, m.height).has_point((inst["cells"] as Array)[0]):
				insts.append(inst)
				boxes.append((inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB))
		assert_eq(pts.size(), centres.size(), name)
		assert_eq(pts.size(), boxes.size(), name)
		for i in pts.size():
			var p: Vector3 = pts[i]
			var tm: TriangleMesh = PropLayer.triangles_of(insts[i]["model"])
			var inv: Transform3D = (props._final_transform(insts[i]) * (PropLayer.model(insts[i]["model"]) as Dictionary)["local"]).affine_inverse()
			var hit: Dictionary = tm.intersect_ray(inv * (p + Vector3(0, 50, 0)), (inv.basis * Vector3.DOWN).normalized())
			assert_false(hit.is_empty(), "%s: під точкою диму є геометрія руїни" % name)
			if not hit.is_empty():
				var world_y: float = (props._final_transform(insts[i]) * (PropLayer.model(insts[i]["model"]) as Dictionary)["local"] * (hit["position"] as Vector3)).y
				assert_true(p.y - world_y >= 0.0 and p.y - world_y <= 0.1, "%s: дим %.2f над геометрією руїни" % [name, p.y - world_y])
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
	var view: BoardView = _cached("crossroads")
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
	# Вид спільний з іншими тестами: розчинення знімаємо.
	props.set_reveal_cells([] as Array[Vector2i])


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
	var view: BoardView = _cached("crossroads")
	var props: PropLayer = view.props()
	assert_gt(props.transformers_shown().size(), 0, "передумова")
	var i: int = props._transformers.keys()[0]
	var cells: Array[Vector2i] = [(props._instances[i]["cells"] as Array)[0]]
	var tstep: Array[Vector2i] = _hit_step(props, (props._instances[i]["transform"] as Transform3D).origin, i)
	props.set_crushed(cells, false, [Vector4i(tstep[0].x, tstep[0].y, tstep[1].x, tstep[1].y)])
	props._flush()
	assert_eq(props.transformers_shown().size(), props._transformers.size() - 1)
	# Вид спільний з іншими тестами: повалене повертаємо.
	props.set_crushed([] as Array[Vector2i])
	props._flush()


## Ворота є в кожному дворі: одні ворота з хвірткою поруч.
func test_every_yard_has_one_gate(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var homes: int = (VillageLayout.for_map(StringName(p)).get("homes", []) as Array).size()
	assert_eq(props._gates.size(), homes, "%s: ворота" % p)
	assert_eq(props._placer.gates.size(), homes, "%s: ворота з точкою стежки" % p)


## Ворота мають форму з переліку, полотно 3–4 м завширшки й 1,8–2 м заввишки (клітинка — 8 м), а
## хвіртка — окремий отвір поруч, вужчий за півтора метра.
func test_gates_have_human_size_and_a_wicket_beside(p = use_parameters(MAPS)) -> void:
	for g: Dictionary in _cached(p).props()._gates:
		assert_true(PropLayer.GATE_KINDS.has(g["kind"]), "%s: форма воріт %s" % [p, g["kind"]])
		var leaf: float = (g["a"] as Vector2).distance_to(g["mid"]) * 8.0
		assert_between(leaf - PropLayer.GATE_POST_SIZE.x * 8.0, 3.0, 4.0, "%s: ширина полотна, м" % p)
		assert_between(float(g["height"]) * 8.0, 1.8, 2.0, "%s: висота полотна, м" % p)
		var wicket: float = (g["mid"] as Vector2).distance_to(g["b"]) * 8.0
		assert_between(wicket - PropLayer.GATE_POST_SIZE.x * 8.0, 0.8, 1.5, "%s: ширина хвіртки, м" % p)
		assert_almost_eq((g["a"] as Vector2).distance_to(g["b"]), PropLayer.GATE, 1e-4, "%s: отвір воріт" % p)


## Ворота дивляться на дорогу, коли вільний відрізок огорожі з запасом від стін на неї дивиться: промінь від хвіртки
## назовні впирається в покриття не далі, ніж за GATE_SIGHT клітинок. Двір, де такого відрізка нема (фасад стоїть
## за 1 м від узбіччя, і паркан вздовж нього заборонений), — «сліпий» (gate_blind): ворота там на бічному відрізку,
## але двір без воріт не лишається ніколи.
func test_gates_face_the_road(p = use_parameters(MAPS)) -> void:
	var placer: RefCounted = _cached(p).props()._placer
	var homes: int = (VillageLayout.for_map(StringName(p)).get("homes", []) as Array).size()
	assert_eq(placer.gates.size(), homes, "%s: двір без воріт" % p)
	for i: int in placer.gates:
		var at: Vector2 = placer.gates[i][0]
		var out: Vector2 = placer.gates[i][1]
		var sees: bool = placer.road_ahead_of(at, out) <= PropLayer.GATE_SIGHT
		assert_true(sees or placer.gate_blind.has(i), "%s: ворота %s не до дороги і двір не «сліпий»" % [p, at])


## Хати «Річки», двори яких стоять на краю своїх клітинок (кільце впритул до стін): (12,6) біля мосту й (5,7) на
## березі. Решту дворів ці перевірки не чіпають.
const PLAIN_YARDS: Array[Vector2i] = [Vector2i(12, 6), Vector2i(5, 7)]


func _home_index(p: String, house: Vector2i) -> int:
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	for i in homes.size():
		if homes[i]["house"] == house:
			return i
	return -1


## Двір — простий прямокутник довкола хати: кільце з чотирьох сторін (без кишені чи сходинки), і за кожною стіною хати
## стоїть паркан чи ворота, або стіна врівень зі стороною кільця — паркан не впирається в стіну посередині.
func test_plain_yard_encloses_the_house() -> void:
	var props: PropLayer = _cached("river").props()
	var placer: RefCounted = props._placer
	var segs: Array = _yard_segments(props)
	for g: Dictionary in props._gates:
		segs.append([g["a"], g["b"]])
	for house: Vector2i in PLAIN_YARDS:
		var i: int = _home_index("river", house)
		var sides: Array = placer.ring_sides[i]
		assert_eq(sides.size(), 4, "двір хати %s — не прямокутник" % house)
		var hr: Rect2 = placer.doors[i][2]
		# Кишеня: сторона кільця вздовж стіни хати ближче FENCE_WALL, але не врівень з нею — таку сторону стіна розрізає,
		# і від неї лишаються вухо повз ріг хати й гачок до стіни. Сторона або врівень зі стіною, або далі FENCE_WALL.
		for sd: Dictionary in sides:
			var d: Vector2i = sd["d"]
			var ax: int = 0 if d.x != 0 else 1
			var a: Vector2 = sd["a"]
			var b: Vector2 = sd["b"]
			if minf(a[1 - ax], b[1 - ax]) >= hr.end[1 - ax] or maxf(a[1 - ax], b[1 - ax]) <= hr.position[1 - ax]:
				continue
			var wall: float = hr.end[ax] if d[ax] > 0 else hr.position[ax]
			var gap: float = (a[ax] - wall) * float(d[ax])
			assert_true(absf(gap) <= 0.03 or gap >= PropLayer.FENCE_WALL,
					"хата %s: сторона %s за %.2f від стіни — кишеня" % [house, d, gap])
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var from: Vector2 = hr.get_center()
			# Промінь — до краю кільця з запасом: далі вже паркан сусіда.
			var ext := Rect2(sides[0]["a"], Vector2.ZERO)
			for sd: Dictionary in sides:
				ext = ext.expand(sd["a"]).expand(sd["b"])
			var ax: int = 0 if d.x != 0.0 else 1
			var reach: float = ext.end[ax] - from[ax] if d[ax] > 0.0 else from[ax] - ext.position[ax]
			var hit := false
			for sg: Array in segs:
				var x: Variant = Geometry2D.segment_intersects_segment(from, from + d * (reach + 0.05), sg[0], sg[1])
				hit = hit or (x != null and not hr.has_point(x))
			# Стіна на межі двору — лише врівень зі стороною кільця (хата на розі двору при вулиці): паркан тоді продовжує
			# її площину від рогу, а не впирається в неї посередині.
			var wall: float = hr.end[ax] if d[ax] > 0.0 else hr.position[ax]
			for sd: Dictionary in sides:
				hit = hit or (Vector2(sd["d"] as Vector2i) == d and absf((sd["a"] as Vector2)[ax] - wall) <= 0.03)
			assert_true(hit, "хата %s: за стіною %s паркану нема — хата на межі двору" % [house, d])


## Ворота цих дворів — на боці фасаду, до дороги, з якої до хати підходять: промінь назовні впирається в покриття.
func test_plain_yard_gate_faces_the_road() -> void:
	var placer: RefCounted = _cached("river").props()._placer
	for house: Vector2i in PLAIN_YARDS:
		var i: int = _home_index("river", house)
		var face := Vector2(VillageLayout.for_map(&"river")["homes"][i]["face"])
		var out: Vector2 = placer.gates[i][1]
		assert_eq(out, face, "хата %s: ворота дивляться не на дорогу" % house)
		assert_lte(placer.road_ahead_of(placer.gates[i][0], out), PropLayer.GATE_SIGHT, "хата %s: дороги перед воротами нема" % house)


## Ворота не лізуть на фасад: увесь отвір (від стовпа до стовпа) далі свого запасу (GATE_CLEAR 0.35 клітинки,
## а коли з ним воріт нема ніде — наступний з GATE_CLEARS, не менший за 0.25) від кожної будівлі, руїни й сараю. Не залежить від того, котра стіна хати фасад: міряється від усього обрису.
func test_gates_keep_clear_of_buildings(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var rects: Array[Rect2] = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = _box_of(inst)
			rects.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	assert_gt(view.props()._gates.size(), 0, p)
	for g: Dictionary in view.props()._gates:
		for t in 21:
			var q: Vector2 = (g["a"] as Vector2).lerp(g["b"], float(t) / 20.0)
			for r in rects:
				assert_false(r.grow(float(g["clear"]) - 1e-3).has_point(q), "%s: ворота %s ближче %.2f до будівлі %s" % [p, q, g["clear"], r])
		assert_gte(float(g["clear"]), PropLayer.GATE_CLEARS[1], "%s: ворота зі запасом менше %.2f" % [p, PropLayer.GATE_CLEARS[1]])


## Отвір воріт не йде вздовж стіни ближче GATE_ALONG навіть тоді, коли двір узяв менший запас з GATE_CLEARS: менший
## запас — лише для стіни, що стоїть торцем до воріт. Ворота паралельно стіні за два-три метри від неї на екрані
## виходять з-під звису даху чи затуляють перший поверх і читаються прибудовою до хати. Виняток — двір, де інакше
## воріт нема ніде (along = false), як «сліпий» двір у test_gates_face_the_road. Воріт із будь-яким послабленням (ні
## along, ні screen з test_gates_are_not_hidden_behind_buildings) — рівно RELAXED_GATES на карту: тісні двори
## Перехрестя (хата між дорогами з трьох боків) іншого місця не мають, а решта карт — жодного. Число точне, щоб
## новий послаблений двір не пройшов непомітно.
func test_gates_do_not_run_alongside_walls(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var rects: Array[Rect2] = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = _box_of(inst)
			rects.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	var gates: Array = view.props()._gates
	assert_gt(gates.size(), 0, p)
	assert_eq(gates.filter(func(g: Dictionary) -> bool: return not (g["along"] and g["screen"])).size(), RELAXED_GATES.get(p, 0),
			"%s: воріт з послабленим правилом" % p)
	for g: Dictionary in gates:
		var a: Vector2 = g["a"]
		var b: Vector2 = g["b"]
		if not g["along"]:
			continue
		var ax: int = 0 if absf(b.x - a.x) > absf(b.y - a.y) else 1
		for r in rects:
			if minf(a[ax], b[ax]) >= r.end[ax] or maxf(a[ax], b[ax]) <= r.position[ax]:
				continue
			var gap: float = maxf(r.position[1 - ax] - a[1 - ax], a[1 - ax] - r.end[1 - ax])
			assert_gte(gap, PropLayer.GATE_ALONG - 1e-3, "%s: ворота %s–%s уздовж стіни %s" % [p, a, b, r])


## Ворота не стоять на екрані за ближчою до камери будівлею: верх полотна далі GATE_SCREEN_GAP від її силуету
## (обрис зі звисом і дахом, піднятий на висоту моделі, разом із шапками димарів) під найнижчим нахилом рига. Ворота,
## що визирають з-за гребеня даху чи димаря, читаються частиною хати, хоч у плані до неї й три метри.
## Виняток — двір, де інакше воріт нема (screen = false).
func test_gates_are_not_hidden_behind_buildings(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var shapes: Array = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k != PropLayer.Kind.STRUCTURE and k != PropLayer.Kind.RUIN:
			continue
		var b: AABB = _box_of(inst)
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		var pts := PackedVector2Array()
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			for y: float in [0.0, b.size.y]:
				pts.append(_on_screen(c, y))
		var xf: Transform3D = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary).get("local", Transform3D()) as Transform3D)
		for ch: Vector3 in (PropLayer.model(inst["model"]) as Dictionary).get("chimneys", []):
			var w: Vector3 = xf * ch
			pts.append(_on_screen(Vector2(w.x, w.z), w.y - b.position.y))
		shapes.append([r, Geometry2D.convex_hull(pts)])
	var checked: int = 0
	for g: Dictionary in view.props()._gates:
		if not g["screen"]:
			continue
		checked += 1
		for sh: Array in shapes:
			var hull: PackedVector2Array = sh[1]
			for t in 11:
				var q: Vector2 = (g["a"] as Vector2).lerp(g["b"], t / 10.0)
				var s: Vector2 = _on_screen(q, float(g["height"]))
				var gap: float = INF if not Geometry2D.is_point_in_polygon(s, hull) else 0.0
				for k in hull.size() - 1:
					gap = minf(gap, Geometry2D.get_closest_point_to_segment(s, hull[k], hull[k + 1]).distance_to(s))
				assert_gte(gap, PropLayer.GATE_SCREEN_GAP, "%s: ворота %s за будівлею %s на екрані" % [p, q, sh[0]])
	assert_gt(checked, 0, "%s: передумова — ворота не лише з послабленим правилом" % p)


## Проєкція правила екрана, перевірена рукою (рискання 45°, нахил 38°, sin = 0.615661, cos = 0.788011). Камера
## дивиться з +x, +z: глибина точки — −(x + z)/√2, вертикаль екрана — глибина·sin + висота·cos, горизонталь — (x − z)/√2.
## Будівля — куб 1×1×1 у (0, 0); ворота заввишки 0.23:
## - за нею, у (−0.3, −0.3): глибина 0.424264, верх на екрані (0, 0.442443) — усередині силуету, відстань 0;
## - перед нею, у (1.5, 1.5): глибина −2.121320, верх (0, −1.124779); найнижча вершина силуету — ріг (1, 1) біля землі,
##   (0, −0.870677), тож відстань 0.254102.
## Хибний знак напряму погляду чи переставлені sin і cos дають інші числа.
func test_gate_screen_projection_by_hand() -> void:
	assert_eq(IsoCameraRig.YAW_DEGREES, 45.0, "передумова — рискання рига")
	assert_eq(IsoCameraRig.PITCH_NEAR_DEG, 38.0, "передумова — найнижчий нахил рига")
	var pts := PackedVector2Array()
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		for y: float in [0.0, 1.0]:
			pts.append(PropLayer._Placer._screen_pt(c, y))
	var hull: PackedVector2Array = Geometry2D.convex_hull(pts)
	for impl: Callable in [PropLayer._Placer._screen_pt, _on_screen]:
		var behind: Vector2 = impl.call(Vector2(-0.3, -0.3), 0.23)
		assert_almost_eq(behind.x, 0.0, 1e-5)
		assert_almost_eq(behind.y, 0.442443, 1e-5)
		var front: Vector2 = impl.call(Vector2(1.5, 1.5), 0.23)
		assert_almost_eq(front.x, 0.0, 1e-5)
		assert_almost_eq(front.y, -1.124779, 1e-5)
		var corner: Vector2 = impl.call(Vector2(1, 1), 0.0)
		assert_almost_eq(corner.y, -0.870677, 1e-5)
	assert_eq(PropLayer._Placer._hull_gap(Vector2(-0.3, -0.3), 0.23, [hull]), 0.0)
	assert_almost_eq(PropLayer._Placer._hull_gap(Vector2(1.5, 1.5), 0.23, [hull]), 0.254102, 1e-5)


## Купка коротких ходів, без якої повис би довгий хід, лишається, навіть коли цей довгий хід складено з шматків коротших
## за SHORT_RUN: рахується довжина прямого ходу, а не шматка. Стіна ліворуч (x ≤ 0); довгий хід — чотири шматки по 0.2
## від неї до (0.8, 0); у його кінці — коротка поперечна купка (0.8, −0.1)–(0.8, 0.1), чиї кінці тримають дві малі стіни.
## Купка ні воріт, ні довгого ходу кінцями не тримає (кінець довгого ходу — у її середині), але без неї він повис би.
## Друга, відірвана купка (3, 0)–(3, 0.2) між двома стінами — уламок і викидається.
func test_short_cluster_holding_a_long_run_of_short_pieces_stays() -> void:
	var walls: Array = [Rect2(-0.5, -0.5, 0.5, 1.0), Rect2(0.7, 0.1, 0.2, 0.2), Rect2(0.7, -0.3, 0.2, 0.2),
			Rect2(2.9, -0.2, 0.2, 0.2), Rect2(2.9, 0.2, 0.2, 0.2)]
	var long_run: Array = [[Vector2(0, 0), Vector2(0.2, 0)], [Vector2(0.2, 0), Vector2(0.4, 0)],
			[Vector2(0.4, 0), Vector2(0.6, 0)], [Vector2(0.6, 0), Vector2(0.8, 0)]]
	var cluster: Array = [[Vector2(0.8, -0.1), Vector2(0.8, 0)], [Vector2(0.8, 0), Vector2(0.8, 0.1)]]
	var stray: Array = [[Vector2(3, 0), Vector2(3, 0.2)]]
	var got: Array = PropLayer._Placer._drop_short_runs(long_run + cluster + stray, [], [], [], walls)
	for pc: Array in long_run + cluster:
		assert_true(got.has(pc), "шматок %s викинуто" % [pc])
	assert_false(got.has(stray[0]), "відірвана купка лишилась")


## Напрям погляду камери в плані (IsoCameraRig.YAW_DEGREES): від камери вглиб.
func _cam_fwd() -> Vector2:
	return -Vector2(sin(deg_to_rad(IsoCameraRig.YAW_DEGREES)), cos(deg_to_rad(IsoCameraRig.YAW_DEGREES)))


## Точка плану на висоті y — на екрані камери під найнижчим нахилом рига (IsoCameraRig.PITCH_NEAR_DEG), у клітинках.
func _on_screen(c: Vector2, y: float) -> Vector2:
	var pitch: float = deg_to_rad(IsoCameraRig.PITCH_NEAR_DEG)
	var fwd: Vector2 = _cam_fwd()
	return Vector2(c.dot(Vector2(-fwd.y, fwd.x)), c.dot(fwd) * sin(pitch) + y * cos(pitch))


## Паркан двору не заходить на асфальт: жодна точка секції (від стовпа до стовпа) не ближче FENCE_ROAD_INSET до краю
## дороги так, як її малює шейдер землі (road_edge_m: поле RoadCourse з заокругленими кутами розвилок, а не осі з
## півшириною, як on_road), тож і на заокругленнях розвилок між панеллю й асфальтом лишається узбіччя.
func test_yard_fences_keep_off_the_asphalt(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var checked: int = 0
	for sg: Array in _yard_segments(props):
		checked += 1
		for t in 11:
			var q: Vector2 = (sg[0] as Vector2).lerp(sg[1], float(t) / 10.0)
			assert_gte(props.road_edge_m(q), PropLayer.FENCE_ROAD_INSET * 8.0, "%s: паркан %s–%s на асфальті в %s" % [p, sg[0], sg[1], q])
	assert_gt(checked, 0, p)


## Прямі ходи паркану двору, коротші за SHORT_RUN (~2 м), стоять лише купкою, яка тримає ворота (кінець котрогось
## ходу на стовпі воріт) чи довгий хід (кінець на ході не коротшому за SHORT_RUN), як бічна стійка воріт чи сполучник зі
## стіною. Купка коротких шматків довкола рогу хати, що замикаються самі на себе через стіну, — уламок у нікуди.
func test_short_fence_runs_hold_a_gate_or_a_long_run(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var posts: Array[Vector2] = []
	for g: Dictionary in props._gates:
		posts.append_array([g["a"], g["mid"], g["b"]])
	var clusters: Array = PropLayer._Placer._short_clusters(PropLayer._Placer._collinear_runs(_yard_segments(props)), posts)
	for cl: Array in clusters:
		var ends: Array = []
		for run: Dictionary in cl[0]:
			ends.append_array(run["ends"])
		assert_true(cl[1], "%s: купка коротких ходів паркану з кінцями %s ні до чого не веде" % [p, ends])
	gut.p("%s: купок коротких ходів %d" % [p, clusters.size()])


## Секції парканів дворів як відрізки по осі моделі.
func _yard_segments(props: PropLayer) -> Array:
	var out: Array = []
	for inst in props.all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var xf: Transform3D = inst["transform"]
		var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
		var a3: Vector3 = xf * Vector3(box.position.x, 0.0, 0.0)
		var b3: Vector3 = xf * Vector3(box.end.x, 0.0, 0.0)
		out.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z)])
	return out


## Паркан не йде вздовж стіни ближче FENCE_WALL: проєкція його ходу на стіну (з відступом 0.03 від рогів — крок
## розрізання) не лежить у межах стіни, коли між ними менше 0.25. Секція впирається в стіну кінцем, але не
## лежить паралельно в двох метрах від фасаду, затуляючи вікна.
func test_fences_keep_off_walls(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var rects: Array[Rect2] = []
	for inst in view.props().all_instances():
		var k: int = _kind(inst["model"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			var b: AABB = _box_of(inst)
			rects.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	var checked: int = 0
	for inst in view.props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var xf: Transform3D = inst["transform"]
		var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
		var a3: Vector3 = xf * Vector3(box.position.x, 0.0, 0.0)
		var b3: Vector3 = xf * Vector3(box.end.x, 0.0, 0.0)
		var a := Vector2(a3.x, a3.z)
		var along_x: bool = absf(b3.x - a3.x) >= absf(b3.z - a3.z)
		for t in 11:
			var q: Vector2 = a.lerp(Vector2(b3.x, b3.z), float(t) / 10.0)
			for r in rects:
				var pos: float = q.x if along_x else q.y
				var lo: float = r.position.x if along_x else r.position.y
				var hi: float = r.end.x if along_x else r.end.y
				var gap: float = maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0) if along_x else maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0)
				assert_false(pos > lo + 0.03 and pos < hi - 0.03 and gap > 0.03 and gap < PropLayer.FENCE_WALL - 0.01,
						"%s: паркан біля %s вздовж стіни %s на %.2f" % [p, q, r, gap])
		checked += 1
	assert_gt(checked, 0, p)


## Паркан садиби не заходить у клітинки чужого двору (дві огорожі не схрещуються хрестом).
func test_fence_never_enters_another_yard(p = use_parameters(MAPS)) -> void:
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	var owner_of: Dictionary = {}
	for i in homes.size():
		for c: Vector2i in homes[i]["cells"]:
			owner_of[c] = i
	var checked: int = 0
	for inst in _cached(p).props().all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var mine: int = int(owner_of.get((inst["cells"] as Array)[0], -1))
		var xf: Transform3D = inst["transform"]
		var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
		for t in 11:
			var w: Vector3 = xf * Vector3(lerpf(box.position.x, box.end.x, float(t) / 10.0), 0.0, 0.0)
			var c := Vector2i(roundi(w.x), roundi(w.z))
			var o: int = int(owner_of.get(c, -1))
			var inside: bool = absf(w.x - c.x) < 0.5 - 0.02 and absf(w.z - c.y) < 0.5 - 0.02
			assert_false(o >= 0 and o != mine and inside, "%s: паркан двору %d у дворі %d на %s" % [p, mine, o, Vector2(w.x, w.z)])
		checked += 1
	assert_gt(checked, 0, p)


## Сусідні садиби (хата в межах HOUSE_APART клітинок) не мають однакових воріт, паркану, сараю чи
## причепа; парканів, причепів і воріт є з чого вибирати (сараїв — одна модель: друга коштує виклик малювання).
func test_neighbouring_yards_do_not_repeat_forms(p = use_parameters(MAPS)) -> void:
	var placer: RefCounted = _cached(p).props()._placer
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	assert_gte(PropLayer.FENCE_FORMS.size(), 3)
	assert_gte(PropLayer.models_of(PropLayer.Kind.TRAILER).size(), 2)
	assert_eq(placer.forms.size(), homes.size(), "%s: форми записані на кожну садибу" % p)
	var pairs: int = 0
	for i in homes.size():
		for j in range(i + 1, homes.size()):
			var d: Vector2i = (homes[i]["house"] as Vector2i) - (homes[j]["house"] as Vector2i)
			if maxi(absi(d.x), absi(d.y)) > PropLayer.HOUSE_APART:
				continue
			pairs += 1
			for key: StringName in [&"fence", &"trailer", &"gate"]:
				var a: Variant = (placer.forms[i] as Dictionary).get(key)
				var b: Variant = (placer.forms[j] as Dictionary).get(key)
				if a != null and b != null:
					assert_ne(a, b, "%s: садиби %d і %d мають однаковий %s" % [p, i, j, key])
					if key == &"fence":
						assert_ne(String(a).get_slice("|", 1), String(b).get_slice("|", 1), "%s: сусіди %d і %d одної висоти паркану" % [p, i, j])
	# На Хребті дві садиби далеко одна від одної: сусідів нема, перевіряти нічого.
	assert_true(pairs > 0 or p == "ridge", "%s: передумова — є сусіди" % p)
	# Записане справді стоїть на дошці.
	var present: Dictionary = {}
	for inst in _cached(p).props().all_instances():
		present[inst["model"]] = true
	for i: int in placer.forms:
		for key: StringName in [&"fence", &"shed", &"trailer"]:
			if (placer.forms[i] as Dictionary).has(key):
				assert_true(present.has(StringName(String(placer.forms[i][key]).get_slice("|", 0))), "%s: %s садиби %d нема на дошці" % [p, key, i])


## Порядок видів паркану двору один на всіх: GLB (extras fence_kinds/fence_tops із tools/blender/infra/yard_fences.py)
## задає номер виду, і з ним сходяться картки сітки (вид k — смуга k атласу, floor(UV.y·n) = k, верх картки —
## fence_tops[k]), матеріал (kinds = n), моделі «infra_fence_yard_вид» у MODELS і FENCE_FORMS, а кожен екземпляр вузла
## несе в INSTANCE_CUSTOM.r номер виду своєї моделі.
func test_yard_fence_kinds_agree_across_mesh_specs_and_instances(p = use_parameters(MAPS)) -> void:
	var info: Dictionary = PropLayer.model(&"infra_fence_yard_picket")
	var kinds: Array = info["fence_kinds"]
	var tops: Array = info["fence_tops"]
	var n: int = kinds.size()
	assert_eq(n, 5, "видів паркану двору")
	assert_eq(tops.size(), n)
	for k in n:
		var m := StringName("infra_fence_yard_" + String(kinds[k]))
		assert_true(PropLayer.MODELS.has(m), "%s нема в MODELS" % m)
		assert_eq(PropLayer.fence_kind_of(m), k, String(m))
		assert_true(PropLayer.FENCE_FORMS.any(func(f: StringName) -> bool: return String(f).get_slice("|", 0) == String(m)), "%s нема у FENCE_FORMS" % m)
	var mesh: Mesh = info["mesh"]
	assert_eq(((mesh.surface_get_material(0) as ShaderMaterial).get_shader_parameter("kinds") as int), n, "kinds матеріалу")
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	assert_eq((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, 2 * n, "по картці (два трикутники) на вид")
	var count: Array[int] = []
	var top: Array[float] = []
	for k in n:
		count.append(0)
		top.append(-INF)
	for i in verts.size():
		var k: int = floori(uvs[i].y * n)
		assert_between(k, 0, n - 1, "вершина %s поза атласом" % verts[i])
		count[k] += 1
		top[k] = maxf(top[k], verts[i].y)
	for k in n:
		assert_eq(count[k], 4, "картка виду %s" % kinds[k])
		assert_almost_eq(top[k], float(tops[k]), 1e-3, "верх картки виду %s" % kinds[k])
	var props: PropLayer = _cached(p).props()
	# Два вузли «batch»: непрозорий (суцільні планки) і «_alpha» (рабиця); на карті може бути один із них.
	var total := 0
	for key: StringName in [&"infra_fence_yard", &"infra_fence_yard_alpha"]:
		if not props._slots.has(key):
			continue
		var node: MultiMeshInstance3D = props.get_node(NodePath(key))
		assert_true(node.multimesh.use_custom_data, p)
		var slots: Array = props._slots[key]
		assert_gt(slots.size(), 0, p)
		total += slots.size()
		# Записане в INSTANCE_CUSTOM — з дзеркала: без рендера (headless) MultiMesh його не віддає.
		var written: Array = props._custom_written[key]
		assert_eq(written.size(), slots.size(), p)
		for k in slots.size():
			var m: StringName = props._instances[slots[k]]["model"]
			assert_eq(written[k], PropLayer.fence_kind_of(m), "%s: слот %d (%s)" % [p, k, m])
			assert_eq(key == &"infra_fence_yard_alpha", PropLayer.FENCE_ALPHA_FORMS.has(m), "%s: вид %s не в своєму проході" % [p, m])
	assert_gt(total, 0, p)


## Кожен двір обгороджений одним видом паркану (усі його секції — одна модель із FENCE_FORMS), а в селі кожної карти
## з трьома й більше дворами трапляються щонайменше три види: паркани села не однакові. Ворота — роду свого паркану.
func test_each_yard_has_one_fence_kind_and_villages_mix_kinds(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	var yard_of: Dictionary = {}
	for i in homes.size():
		for c: Vector2i in homes[i]["cells"]:
			yard_of[c] = i
	var kinds_of: Dictionary = {}
	for inst in props.all_instances():
		if _kind(inst["model"]) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var c: Vector2i = (inst["cells"] as Array)[0]
		if not yard_of.has(c):
			continue
		var i: int = yard_of[c]
		if not kinds_of.has(i):
			kinds_of[i] = {}
		kinds_of[i][inst["model"]] = true
	var used: Dictionary = {}
	for i: int in kinds_of:
		assert_eq((kinds_of[i] as Dictionary).size(), 1, "%s: двір %d має види %s" % [p, i, (kinds_of[i] as Dictionary).keys()])
		var m: StringName = (kinds_of[i] as Dictionary).keys()[0]
		assert_true(PropLayer.FENCE_FORMS.any(func(f: StringName) -> bool: return String(f).get_slice("|", 0) == String(m)),
				"%s: паркан двору %d — %s, не з FENCE_FORMS" % [p, i, m])
		used[m] = true
		var form: Variant = (props._placer.forms[i] as Dictionary).get(&"gate")
		if form != null and PropLayer.spec_of(m).has("gate"):
			assert_eq(form, PropLayer.spec_of(m)["gate"], "%s: ворота двору %d не того роду, що паркан %s" % [p, i, m])
	assert_gt(kinds_of.size(), 0, "%s: передумова — двори обгороджені" % p)
	if homes.size() >= 3:
		assert_gte(used.size(), 3, "%s: видів паркану в селі лише %s" % [p, used.keys()])


## Кожна коробка воріт (стовпи, полотно, хвіртка, планки) — на висоті воріт: центр не вище GATE_H + 0.05 над ґрунтом.
## Планка, що висить над воротами, на екрані зсувається вглиб і читається рискою посеред двору.
func test_gate_boxes_stay_within_gate_height(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	# Рельєф саме цієї карти: TerrainHeight.ground_y читає рельєф останньої побудованої дошки.
	var th: TerrainHeight = _cached(p)._height
	var checked: int = 0
	for xf: Transform3D in props._small_base:
		var c := Vector2(xf.origin.x, xf.origin.z)
		for g: Dictionary in props._gates:
			if Geometry2D.get_closest_point_to_segment(c, g["a"], g["b"]).distance_to(c) > 0.03:
				continue
			checked += 1
			var up: float = xf.origin.y - th.at(c.x, c.y)
			assert_lte(up, PropLayer.GATE_H + 0.05, "%s: коробка воріт %s на висоті %.3f" % [p, c, up])
			break
	assert_gt(checked, 0, "%s: передумова — коробки воріт є" % p)


## Усі форми воріт трапляються в селах трьох карт.
func test_every_gate_form_is_used_on_some_map() -> void:
	var seen: Dictionary = {}
	for p in MAPS:
		for g: Dictionary in _cached(p).props()._gates:
			seen[g["kind"]] = true
	for k: StringName in PropLayer.GATE_KINDS:
		assert_true(seen.has(k), "форма воріт %s не вжита" % k)


## Відстань від точки до найближчої клітинки води чи болота (клітинки дошки, чверть-квадрат навколо).
func _water_gap(world: Board, ring: int, q: Vector2) -> float:
	var best: float = INF
	var c := Vector2i(roundi(q.x), roundi(q.y))
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n: Vector2i = c + Vector2i(dx, dy)
			var w: Vector2i = n + Vector2i(ring, ring)
			if not world.in_bounds(w):
				continue
			var kd: int = world.kind_at(w)
			if kd != Terrain.Kind.WATER and kd != Terrain.Kind.MARSH:
				continue
			var nearest := Vector2(clampf(q.x, n.x - 0.5, n.x + 0.5), clampf(q.y, n.y - 0.5, n.y + 0.5))
			best = minf(best, q.distance_to(nearest))
	return best


## Нічого дрібного — тюка, причепа, сараю, воріт — ближче WATER_CLEAR (0,4 клітинки) до води чи болота.
func test_nothing_small_stands_near_water(p = use_parameters(MAPS)) -> void:
	var m: MapData = _map(p)
	var world: Board = Surroundings.world_board(m.to_board(), m)
	var ring: int = Surroundings.ring_of(m)
	var props: PropLayer = _cached(p).props()
	var checked: int = 0
	for inst in props.all_instances():
		var is_shed: bool = PropLayer.YARD_SHEDS.has(inst["model"]) and inst.get("yard", false)
		if _kind(inst["model"]) not in [PropLayer.Kind.HAY, PropLayer.Kind.TRAILER] and not is_shed:
			continue
		var o: Vector3 = (inst["transform"] as Transform3D).origin
		assert_gte(_water_gap(world, ring, Vector2(o.x, o.z)), PropLayer.WATER_CLEAR - 1e-3, "%s: %s на %s біля води" % [p, inst["model"], inst["cells"]])
		checked += 1
	for g: Dictionary in props._gates:
		for k: String in ["a", "mid", "b"]:
			assert_gte(_water_gap(world, ring, g[k]), PropLayer.WATER_CLEAR - 1e-3, "%s: ворота біля води" % p)
		checked += 1
	assert_gt(checked, 0, p)


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


## Цілі хати карти: індекс екземпляра, обрис, чи лежить хата на дошці.
func _homes(props: PropLayer, m: MapData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var board := Rect2i(0, 0, m.width, m.height)
	for i in props._instances.size():
		var inst: Dictionary = props._instances[i]
		if PropLayer.is_home(inst):
			out.append({"i": i, "rect": _rect_of(inst), "board": board.has_point((inst["cells"] as Array)[0])})
	return out


## Поселення: ланцюги точок із кроком до SETTLEMENT_R.
func _settlements(pts: Array[Vector2]) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for i in pts.size():
		if seen.has(i):
			continue
		var group: Array[Vector2] = []
		var stack: Array[int] = [i]
		seen[i] = true
		while not stack.is_empty():
			var u: int = stack.pop_back()
			group.append(pts[u])
			for j in pts.size():
				if not seen.has(j) and pts[u].distance_to(pts[j]) <= PropLayer.SETTLEMENT_R:
					seen[j] = true
					stack.append(j)
		out.append(group)
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
## краю, — підстанція (10 кВ) чи опора 0.4 кВ з відводом або не далі STREET_END від хати. Магістралей на краю — щонайменше дві.
func test_power_network_is_connected_and_leaves_the_world(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var m: MapData = _map(p)
	var homes: Array[Dictionary] = _homes(props, m)
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
			# Кінець вулиці: опора з відводом або навпроти хати (головна вулиця тягнеться на всю довжину села).
			var at: Vector2 = _pole_at(props, i)
			assert_true(fed.has(i) or homes.any(func(h: Dictionary) -> bool: return (h["rect"] as Rect2).get_center().distance_to(at) <= STREET_END),
					"%s: гілка 0.4 кВ обривається на %s без відводу й далеко від хат" % [p, at])
		elif gap <= 0.5:
			edge_ends += 1
		else:
			assert_true(props._transformers.has(i), "%s: 10 кВ обривається не на ТП: %s (до краю %.2f)" % [p, _pole_at(props, i), gap])
	assert_gte(edge_ends, 2, "%s: кінців магістралі на краю кільця %d" % [p, edge_ends])


## Прольоти: 10 кВ — до 9 клітинок (72 м), 0.4 кВ — до 5 (40 м); опори не скупчені: будь-які дві не ближче за 1.4.
func test_spans_keep_their_length(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	assert_gt(props._spans.size(), 0, "%s: передумова — прольоти є" % p)
	assert_eq([float(PropLayer.SPAN[&"04kv"]), float(PropLayer.SPAN[&"10kv"])], [PowerGrid.MAX_04KV, PowerGrid.MAX_10KV], "межі прольотів у розстановці й у мережі — ті самі")
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


## Лінії 0.4 і 10 кВ — прямі відрізки вздовж осей карти з поворотами під прямим кутом: кожен проліт між опорами
## лежить уздовж x чи z (допуск 0.02 клітинки). Під іншим кутом іде лише відвід до хати.
func test_spans_run_along_the_map_axes(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	assert_gt(props._spans.size(), 0, "%s: передумова — прольоти є" % p)
	for sp: Array in props._spans:
		var d: Vector2 = _pole_at(props, sp[1]) - _pole_at(props, sp[0])
		assert_lte(minf(absf(d.x), absf(d.y)), 1e-3, "%s: проліт %s → %s навскіс" % [p, _pole_at(props, sp[0]), _pole_at(props, sp[1])])


## Траса 10 кВ, як її намалює редактор карт — навпростець крізь село, річку, ліс і навскіс, — однаково лягає
## лише законними прольотами: уздовж осі, не довше за MAX_10KV, не на будівлі. Де законного прольоту нема, траси
## там нема, а не проліт навскіс чи крізь хату.
func test_editor_routes_give_only_legal_trunk_spans() -> void:
	var placer = _cached("river").props()._placer
	var keep: Dictionary = placer.layout
	placer.layout = {"routes": [
		{"kind": &"10kv", "axis": [Vector2(-13, 5), Vector2(38, 5)], "side": 1.0},
		{"kind": &"10kv", "axis": [Vector2(11, -13), Vector2(11, 34)], "side": -1.0},
		{"kind": &"10kv", "axis": [Vector2(-13, -13), Vector2(38, 34)], "side": 1.0},
		# Праворуч від ходу: ліворуч уздовж x = 13 — двір хати (12,6) впритул до асфальту.
		{"kind": &"10kv", "axis": [Vector2(-13, 15), Vector2(13, 15), Vector2(13, 6), Vector2(38, 6)], "side": -1.0},
	]}
	var grid := PowerGrid.new()
	grid.plan(placer)
	placer.layout = keep
	var spans: int = 0
	for line: Dictionary in grid.lines:
		if line["kind"] != &"10kv":
			continue
		var pts: Array = line["points"]
		for k in range(1, pts.size()):
			var a: Vector2 = pts[k - 1]
			var b: Vector2 = pts[k]
			spans += 1
			assert_lte(minf(absf(a.x - b.x), absf(a.y - b.y)), 1e-3, "проліт %s → %s навскіс" % [a, b])
			assert_lte(a.distance_to(b), PowerGrid.MAX_10KV + 1e-3, "проліт %s → %s задовгий" % [a, b])
			assert_false(placer.span_hits_building(a, b), "проліт %s → %s на будівлі" % [a, b])
	assert_gt(spans, 0, "передумова — траси лягли хоч частково")


## Стовп не стоїть на паркані двору: до будь-якої секції паркану — не ближче за FENCE_POLE_CLEAR клітинки.
func test_poles_keep_off_yard_fences(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var segs: Array = props._placer._fence_segments()
	assert_gt(segs.size(), 0, "%s: передумова — паркани є" % p)
	for i in _pole_ids(props):
		var at: Vector2 = _pole_at(props, i)
		for sg: Array in segs:
			var d: float = Geometry2D.get_closest_point_to_segment(at, sg[0], sg[1]).distance_to(at)
			assert_gte(d, FENCE_POLE_CLEAR, "%s: стовп %s за %.2f від паркану %s" % [p, at, d, sg])


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
	var homes: Array[Dictionary] = _homes(props, m)
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


## До хати — щонайбільше один відвід, від найближчої опори, від якої він можливий: не довший за DROP_DIRECT (16 м),
## на стіні з боку опори на висоті 2.8–3 м, відрізок не заходить у обрис даху власної хати й не ближче DROP_GAP до чужих.
## Хата, яку мережа навмисно лишає без світла (PropLayer._skipped), відводу не має. Руїни, сараї й пошкоджені хати
## відводу не мають. Хати без відводу (PropLayer._unfed) названі й справді без відводу.
func test_homes_have_at_most_one_short_drop_to_their_wall(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _cached(p)
	var props: PropLayer = view.props()
	var m: MapData = _map(p)
	var all_homes: Array[Dictionary] = _homes(props, m)
	var rects: Array[Rect2] = []
	for h in all_homes:
		rects.append(h["rect"])
	var eligible: Array[int] = []
	for i in _pole_ids(props):
		if _is_04(props, i) or props._transformers.has(i):
			eligible.append(i)
	assert_gt(all_homes.size(), 0, "%s: передумова — хати є" % p)
	assert_gt(props._drops.size(), 0, "%s: передумова — відводи є" % p)
	for u: Vector2 in props._skipped:
		for h in all_homes:
			if (h["rect"] as Rect2).get_center().distance_to(u) < 0.05:
				assert_eq(_drops_to(props, h["rect"]).size(), 0, "%s: хата %s без світла, а відвід є" % [p, u])
	for h in all_homes:
		var drops: Array = _drops_to(props, h["rect"])
		var centre: Vector2 = (h["rect"] as Rect2).get_center()
		assert_lte(drops.size(), 1, "%s: відводів до хати %s — %d" % [p, centre, drops.size()])
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


## Відвід короткий: не довший за DROP_DIRECT (16 м), не над грядками, не крізь чужий двір, кінець — не біля димаря. Через вулицю — лише прямо впоперек: кут до нормалі вулиці не більший за 25° і проліт не довший за DROP_CROSS
## (14 м). Довгий навскісний відвід через вулицю чи поле — павутиння, а не село.
func test_drops_are_short_and_cross_streets_square(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var placer = props._placer
	assert_eq([PropLayer.DROP_DIRECT, PropLayer.DROP_CROSS, PropLayer.DROP_CROSS_COS], [2.0, 1.75, 0.906])
	assert_gt(props._drops.size(), 0, "%s: передумова — відводи є" % p)
	var crossing: int = 0
	for d: Array in props._drops:
		var from: Vector2 = _pole_at(props, d[0])
		var lip := Vector2((d[1] as Vector3).x, (d[1] as Vector3).z)
		var len_: float = from.distance_to(lip)
		assert_lte(len_, PropLayer.DROP_DIRECT + 1e-3, "%s: відвід до %s задовгий" % [p, lip])
		for ch3: Vector3 in placer._chimneys:
			assert_gte(Vector2(ch3.x, ch3.z).distance_to(lip), PropLayer.DROP_CHIMNEY_CLEAR, "%s: відвід до %s закінчується біля димаря" % [p, lip])
		for r: Rect2 in placer._garden_rects:
			assert_false(PropLayer._Placer._seg_hits_rect(from, lip, r), "%s: відвід до %s над грядкою" % [p, lip])
		var house: Rect2
		for h in _homes(props, _map(p)):
			if (h["rect"] as Rect2).grow(0.02).has_point(lip):
				house = h["rect"]
		var own: Variant = placer.yard_owner.get(Vector2i(roundi(house.get_center().x), roundi(house.get_center().y)))
		var crossed: bool = false
		for j in range(0, 41):
			var q: Vector2 = from.lerp(lip, float(j) / 40.0)
			if placer.road_edge_m(q) < 0.0 and not crossed:
				crossed = true
				crossing += 1
				assert_lte(len_, PropLayer.DROP_CROSS + 1e-3, "%s: відвід через вулицю до %s завдовжки %.2f" % [p, lip, len_])
				var sin_a: float = absf((lip - from).normalized().dot(placer.street_dir(q, from, lip)))
				assert_lte(rad_to_deg(asin(sin_a)), 25.0 + 0.1, "%s: відвід до %s іде через вулицю навскіс" % [p, lip])
			var c := Vector2i(roundi(q.x), roundi(q.y))
			if placer.yard_owner.has(c) and minf(0.5 - absf(q.x - c.x), 0.5 - absf(q.y - c.y)) > PropLayer.YARD_EPS:
				assert_eq(placer.yard_owner[c], own, "%s: відвід до %s іде чужим двором %s" % [p, lip, c])
	gut.p("%s: відводів через вулицю %d" % [p, crossing])


## Відвід не кріпиться до стіни з власним димарем хати (на щиті чи зовнішнім): димар у обрисі хати ближче
## DROP_CHIMNEY_WALL до лінії стіни й помітно ближче, ніж до протилежної, — на екрані відвід тоді кінчається на шапці
## димаря. Точка на розі лежить на двох стінах — перевіряються обидві. Правило мусить спрацьовувати хоч на одній карті:
## стіни з димарем у хат є, інакше тест нічого б не стеріг.
func test_drops_avoid_chimney_walls() -> void:
	var excluded: int = 0
	for p in MAPS:
		var props: PropLayer = _cached(p).props()
		var placer = props._placer
		var homes: Array[Dictionary] = _homes(props, _map(p))
		for h in homes:
			for n: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				excluded += int(_chimney_wall(placer, h["rect"], n))
		for d: Array in props._drops:
			var lip := Vector2((d[1] as Vector3).x, (d[1] as Vector3).z)
			var house := Rect2()
			for h in homes:
				if (h["rect"] as Rect2).grow(0.02).has_point(lip):
					house = h["rect"]
			assert_true(house.has_area(), "%s: хату відводу до %s не знайдено" % [p, lip])
			if not house.has_area():
				continue
			for n: Vector2 in PropLayer.wall_normals(house, lip):
				assert_false(_chimney_wall(placer, house, n), "%s: відвід до %s на стіні %s з димарем" % [p, lip, n])
	assert_gt(excluded, 0, "правило стіни з димарем жодного разу не спрацювало")


## Незалежно від коду розстановки: чи стоїть власний димар хати rect біля її стіни з нормаллю n.
func _chimney_wall(placer, rect: Rect2, n: Vector2) -> bool:
	var wall: float = (rect.get_center() + rect.size * 0.5 * n).dot(n)
	var depth: float = absf(rect.size.dot(n))
	for ch3: Vector3 in placer._chimneys:
		var q := Vector2(ch3.x, ch3.z)
		if not rect.grow(0.02).has_point(q):
			continue
		var off: float = absf(wall - q.dot(n))
		if off < PropLayer.DROP_CHIMNEY_WALL and off < absf(depth - off) - 0.1:
			return true
	return false


## Відводи має частина хат: на карті з десятьма й більше хатами — 40–70 % (село з електрикою, але не павутиння). На
## Хребті досяжні хати стоять поселеннями з однієї-двох, тож жодну не лишено без відводу навмисно.
func test_drop_share_per_map(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var homes: int = _homes(props, _map(p)).size()
	assert_gt(props._drops.size(), 0, "%s: передумова — відводи є" % p)
	if homes >= 10:
		assert_between(float(props._drops.size()) / homes, 0.4, 0.7, "%s: відводів %d з %d хат" % [p, props._drops.size(), homes])
	if p == "ridge":
		assert_eq(props._skipped.size(), 0, "ridge: досяжні хати в поселеннях з однієї-двох")


# --- окремі правила дроту й місця опори, на рукотворних випадках (не через план мережі) ---------------------------

func _river_placer():
	return _cached("river").props()._placer


## Дріт крізь клітинку лісу неможливий: лінія з-під крон читається лінією нізвідки.
func test_wire_rule_forest() -> void:
	var placer = _river_placer()
	var forest := Vector2i(-1, -1)
	for y in 24:
		for x in 24:
			if forest.x < 0 and placer.kind(Vector2i(x, y)) == Terrain.Kind.FOREST:
				forest = Vector2i(x, y)
	assert_true(forest.x >= 0, "передумова — ліс є")
	var c := Vector2(forest)
	assert_false(placer.wire_ok(c - Vector2(0.4, 0.0), c + Vector2(0.4, 0.0), PropLayer.SPAN_CROSS))


## Проліт уздовж дороги над асфальтом (не перетинає вісь) неможливий довше за ROAD_CLIP.
func test_wire_rule_along_asphalt() -> void:
	var placer = _river_placer()
	var pts: PackedVector2Array = placer.height.roads.lines[0]
	var ring := Vector2(placer.ring, placer.ring)
	var k: int = pts.size() / 2
	var a: Vector2 = pts[k] - ring
	var dir: Vector2 = (pts[k + 4] - pts[k]).normalized()
	var off: Vector2 = dir.orthogonal() * 0.05
	assert_lt(placer.road_edge_m(a + off), 0.0, "передумова — точка на асфальті")
	assert_false(placer.wire_ok(a + off, a + off + dir * 1.5, PropLayer.SPAN_CROSS))


## Проліт перед будівлею з боку камери (+x, +z), що на екрані лягає на дах, неможливий.
func test_wire_rule_projection_over_building() -> void:
	var placer = _river_placer()
	var r: Rect2 = Rect2()
	for b: Rect2 in placer._bld_rects:
		if b.size.x > 0.5 and b.size.y > 0.5 and b.position.x > 2.0 and b.position.y > 2.0:
			r = b
			break
	assert_true(r.has_area(), "передумова — будівля є")
	var y: float = r.end.y + 0.35
	var a := Vector2(r.position.x, y) + Vector2(0.35, 0.0)
	var b := Vector2(r.end.x, y) + Vector2(0.35, 0.0)
	assert_false(placer._seen_clear(a, b, Rect2()), "проліт перед дахом з боку камери")


## Відвід, що йде майже вздовж напряму погляду камери, неможливий: на екрані — вертикальна риска.
func test_wire_rule_drop_along_view() -> void:
	var placer = _river_placer()
	var r: Rect2 = Rect2()
	for b: Rect2 in placer._home_rects:
		r = b
		break
	assert_true(r.has_area(), "передумова — хата є")
	var lip: Vector2 = r.end
	assert_false(placer.wire_ok(lip + Vector2.ONE.normalized() * 1.0, lip, PropLayer.DROP_CROSS, r))


## Стовп поруч із тюком сіна (ближче POLE_HAY_CLEAR) не стоїть: жодне місце в цій смузі довкола будь-якого тюка не
## придатне. Без правила частина таких місць придатна (поле біля тюка).
func test_pole_spot_rule_hay() -> void:
	var props: PropLayer = _cached("river").props()
	var placer = props._placer
	var n: int = 0
	for r: Rect2 in placer._hay_rects:
		for k in 24:
			var q: Vector2 = r.get_center() + Vector2.from_angle(TAU * k / 24.0) * (maxf(r.size.x, r.size.y) * 0.5 + PropLayer.POLE_HAY_CLEAR * 0.6)
			if r.grow(PropLayer.POLE_HAY_CLEAR).has_point(q):
				n += 1
				assert_false(placer.pole_spot_ok(q, 2), "опора впритул до тюка %s" % q)
	assert_gt(n, 0, "передумова — тюки є")


## Стовп у прорізі воріт (ближче POLE_GATE_CLEAR до відрізка між стовпами воріт) не стоїть: жодне місце там не придатне.
## Поки обрис паркану (in_yard) не має прорізу на місці воріт, ці місця відкидає ще й відступ від паркану
## (POLE_FENCE_CLEAR), тож near_gate у pole_spot_ok затінено і без нього тест не впаде; він стереже ворота на той час,
## коли паркан отримає проріз.
func test_pole_spot_rule_gate(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var placer = props._placer
	assert_gt(placer.gate_segments.size(), 0, "передумова — ворота є")
	for g: Array in placer.gate_segments:
		var a: Vector2 = g[0]
		var b: Vector2 = g[1]
		var nrm: Vector2 = (b - a).normalized().orthogonal()
		for t in 5:
			for o: float in [-0.15, -0.08, 0.0, 0.08, 0.15]:
				var q: Vector2 = a.lerp(b, t / 4.0) + nrm * o
				assert_true(placer.near_gate(q))
				assert_false(placer.pole_spot_ok(q, 2), "опора у воротах %s" % q)


## Кожне поселення з двох і більше хат має свою мережу 0.4 кВ із підстанцією: опори 0.4 кВ не далі за STREET_R від його
## хат є, і мережа, до якої вони належать, доходить до ТП (стовпа 10 кВ із підстанцією). Без ТП не було б і відводів —
## тож поселення без відводів тут не пропускаються.
func test_every_settlement_has_a_transformer(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var centres: Array[Vector2] = []
	for h in _homes(props, _map(p)):
		centres.append((h["rect"] as Rect2).get_center())
	var poles04: Array[int] = []
	for i in _pole_ids(props):
		if _is_04(props, i):
			poles04.append(i)
	var checked: int = 0
	for group: Array in _settlements(centres):
		if group.size() < 2:
			continue
		checked += 1
		var own: Array[int] = poles04.filter(func(i: int) -> bool:
			return group.any(func(c: Vector2) -> bool: return _pole_at(props, i).distance_to(c) <= STREET_R))
		assert_gt(own.size(), 0, "%s: поселення %s без опор 0.4 кВ" % [p, group])
		assert_true(own.any(func(i: int) -> bool: return _transformers_of(props, i).size() == 1),
				"%s: мережа 0.4 кВ поселення %s не доходить до підстанції" % [p, group])
	assert_gt(checked, 0, "%s: передумова — поселення з двох і більше хат є" % p)
	# Кожна хата з відводом живиться від мережі з підстанцією (не від обірваної гілки).
	for d: Array in props._drops:
		assert_eq(_transformers_of(props, d[0]).size(), 1, "%s: відвід від %s без підстанції" % [p, _pole_at(props, d[0])])


## Пошук мосту між відрізаною станцією й деревом обмежений: не більше BRIDGE_TRIES спроб на станцію й BRIDGE_BUDGET на
## село — будова карти не дорожчає від вулиць без виходу.
func test_power_grid_search_is_capped(p = use_parameters(MAPS)) -> void:
	var grid := PowerGrid.new()
	grid.plan(_cached(p).props()._placer)
	assert_lte(grid.peak_tries, PowerGrid.BRIDGE_TRIES, p)
	assert_lte(grid.peak_attempts, PowerGrid.BRIDGE_BUDGET, p)


## Стовп не стоїть у дворі садиби (PropLayer in_yard: обрис паркану) і ближче POLE_GATE_CLEAR до прорізу воріт, а
## проліт 0.4 кВ не йде над грядкою, крізь двір, над будівлею з боку камери, а через дорогу — лише прямо впоперек.
## На опорі 0.4 кВ щонайбільше три прольоти, на ТП (і спільній) — щонайбільше два прольоти 0.4 кВ. Будь-який проліт
## 0.4 кВ — не довший за PowerGrid.MAX_04KV.
func test_poles_and_spans_keep_out_of_yards(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var placer = props._placer
	assert_gt(placer.gate_segments.size(), 0, "%s: передумова — ворота є" % p)
	for i in _pole_ids(props):
		var at: Vector2 = _pole_at(props, i)
		assert_false(placer.in_yard(at), "%s: опора %s у дворі" % [p, at])
		for g: Array in placer.gate_segments:
			assert_gte(Geometry2D.get_closest_point_to_segment(at, g[0], g[1]).distance_to(at),
					PropLayer.POLE_GATE_CLEAR, "%s: опора %s у воротах" % [p, at])
	var adj: Dictionary = _neighbours(props)
	var checked: int = 0
	for sp: Array in props._spans:
		if not (_is_04(props, sp[0]) or _is_04(props, sp[1])):
			continue
		checked += 1
		assert_lte(_pole_at(props, sp[0]).distance_to(_pole_at(props, sp[1])), PowerGrid.MAX_04KV + 1e-3,
				"%s: проліт %s–%s довший за MAX_04KV" % [p, _pole_at(props, sp[0]), _pole_at(props, sp[1])])
		assert_true(placer.wire_ok(_pole_at(props, sp[0]), _pole_at(props, sp[1]), PropLayer.SPAN_CROSS),
				"%s: проліт %s–%s над грядкою, двором чи будівлею або навскіс через дорогу" % [p, _pole_at(props, sp[0]), _pole_at(props, sp[1])])
	for i: int in adj:
		var n04: int = (adj[i] as Array).filter(func(n: int) -> bool: return _is_04(props, n)).size()
		if _is_04(props, i):
			assert_lte((adj[i] as Array).size(), PowerGrid.MAX_SPANS, "%s: на опорі %s прольотів %d" % [p, _pole_at(props, i), (adj[i] as Array).size()])
		elif props._transformers.has(i):
			assert_lte(n04, PowerGrid.MAX_SPANS - 1, "%s: на ТП %s прольотів 0.4 кВ %d" % [p, _pole_at(props, i), n04])
	assert_gt(checked, 0, "%s: передумова — прольоти 0.4 кВ є" % p)


## Сусідні хати не всі під дротами: у кожному поселенні з трьома й більше хатами, до яких опора дістає, щонайменше одна
## лишена без відводу (PropLayer._skipped), і відводу в неї справді нема (вона серед PropLayer._unfed).
func test_some_reachable_homes_are_left_without_a_drop(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var reach: Array[Vector2] = props._skipped.duplicate()
	for d: Array in props._drops:
		for h in _homes(props, _map(p)):
			if (h["rect"] as Rect2).grow(0.02).has_point(Vector2((d[1] as Vector3).x, (d[1] as Vector3).z)):
				reach.append((h["rect"] as Rect2).get_center())
	for group: Array in _settlements(reach):
		if group.size() >= 3:
			assert_true(group.any(func(c: Vector2) -> bool: return props._skipped.has(c)), "%s: у поселенні %s відвід до кожної досяжної хати" % [p, group])
	for u: Vector2 in props._skipped:
		assert_true(props._unfed.any(func(c: Vector2) -> bool: return c.distance_to(u) < 0.05), "%s: хата %s лишена без світла, а відвід є" % [p, u])


## Кожне поселення з двох і більше хат має свою вулицю з лінією 0.4 кВ: опора 0.4 кВ не далі за STREET_R від його хати.
func test_every_settlement_has_a_street_line(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var centres: Array[Vector2] = []
	for h in _homes(props, _map(p)):
		centres.append((h["rect"] as Rect2).get_center())
	var poles04: Array[Vector2] = []
	for i in _pole_ids(props):
		if _is_04(props, i):
			poles04.append(_pole_at(props, i))
	for group: Array in _settlements(centres):
		if group.size() < 2:
			continue
		assert_true(group.any(func(c: Vector2) -> bool: return poles04.any(func(q: Vector2) -> bool: return q.distance_to(c) <= STREET_R)),
				"%s: поселення %s без лінії 0.4 кВ" % [p, group])


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


## Панельний блок — міська будівля: ні на дошці, ні в кільці жодної сільської карти його нема.
func test_no_panel_block_on_any_map(p = use_parameters(MAPS)) -> void:
	for inst in _cached(p).props().all_instances():
		assert_false(String(inst["model"]).begins_with("h5_panel_block"), "%s: панельний блок %s" % [p, inst["model"]])


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


## Бюджет кадру (§8): стовпи воріт і уламки руїн — однакові дерев'яні коробки, тож один MultiMesh.
func test_small_boxes_share_one_multimesh(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	for gone: StringName in [&"GatePosts", &"RubbleDebris"]:
		assert_null(props.get_node_or_null(NodePath(gone)), "%s: %s злито" % [p, gone])
	var boxes: MultiMeshInstance3D = props.get_node_or_null("SmallBoxes")
	assert_not_null(boxes, "%s: спільний вузол є" % p)
	assert_eq(boxes.multimesh.instance_count, props._small_base.size(), "%s: екземплярів стільки, скільки коробок" % p)
	assert_gte(props._small_base.size(), 3 * props._gates.size(), p)
	assert_eq(boxes.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Дрібні пропси з зумом не зникають: на найбільшому віддаленні сіно, брили й коробки видно.
func test_small_props_stay_drawn_at_max_zoom() -> void:
	var view: BoardView = _cached("crossroads")
	view.set_forest_zoom(IsoCameraRig.MAX_ZOOM)
	var props: PropLayer = view.props()
	var small: Array[Node] = props.find_children("*", "MultiMeshInstance3D", false, false).filter(func(n: Node) -> bool:
		return n.name == &"SmallBoxes" or int(PropLayer.spec_of(StringName(n.name)).get("kind", -1)) in [PropLayer.Kind.HAY, PropLayer.Kind.BOULDER])
	assert_gt(small.size(), 1, "передумова: на карті є дрібні вузли")
	for n: Node in small:
		assert_true((n as Node3D).visible, "%s: видно на будь-якому зумі" % n.name)


## Тюки на мокрій карті темніші за суху: у дощ не світяться жовто-зеленою плямою на траві.
func test_hay_is_dimmed_on_a_wet_map() -> void:
	var node: MultiMeshInstance3D = null
	var view: BoardView = _wet_river()
	for n in view.props().get_children():
		if String(n.name).begins_with("infra_hay"):
			node = n
			break
	assert_not_null(node, "тюки на River")
	var src := (PropLayer.model(StringName(node.name))["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D
	var got := node.multimesh.mesh.surface_get_material(0) as BaseMaterial3D
	for ch in 3:
		assert_almost_eq(got.albedo_color[ch], src.albedo_color[ch] * PropLayer.HAY_WET[ch], 1e-4)


## Стулка й хвіртка воріт одного тону: найбільша коробка кожної частини має однаковий колір (сталь і профнастил).
func test_wicket_has_the_leaf_colour(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _cached(p).props()
	var checked: int = 0
	for g: Dictionary in props._gates:
		if g["kind"] != &"metal" and g["kind"] != &"sheet":
			continue
		var u: Vector2 = ((g["b"] as Vector2) - (g["a"] as Vector2)).normalized()
		var best: Array = [0.0, Color.BLACK, 0.0, Color.BLACK]
		for k in props._small_base.size():
			var xf: Transform3D = props._small_base[k]
			var q := Vector2(xf.origin.x, xf.origin.z)
			var s: float = (q - (g["a"] as Vector2)).dot(u)
			if absf(((q - (g["a"] as Vector2)) - u * s).length()) > 0.02 or s < 0.0 or s > (g["a"] as Vector2).distance_to(g["b"]):
				continue
			var area: float = xf.basis.x.length() * xf.basis.y.length()
			# Стовпи (0.245 і вище) поза діапазоном висот полотна; береться найбільша площа лицьової грані.
			var idx: int = 0 if s < (g["a"] as Vector2).distance_to(g["mid"]) else 2
			if xf.basis.y.length() < 0.19 or xf.basis.y.length() > 0.23 or area <= best[idx]:
				continue
			best[idx] = area
			best[idx + 1] = props._small_colors[k]
		if best[0] > 0.0 and best[2] > 0.0:
			assert_eq(best[1], best[3], "%s: хвіртка іншого тону, ніж полотно (%s)" % [p, g["kind"]])
			checked += 1
	assert_gt(checked, 0, p)


## Суцільний паркан у справжньому непрозорому проході: шейдер не пише ALPHA і не вмикає alpha_to_coverage, інакше рушій
## кладе його в чергу прозорих без запису глибини, і дим чи вода сортувались би з ним за пріоритетом, а не за глибиною.
func test_solid_fence_shader_is_truly_opaque() -> void:
	var code: String = PropLayer._thin_opaque().code
	assert_false(code.contains("\tALPHA = "), "запис ALPHA")
	assert_false(code.contains(", alpha_to_coverage"), "alpha_to_coverage у render_mode")
	assert_true(code.contains("discard"), "просвіти вирізає discard")


# --- падіння опор і парканів ---------------------------------------------------------------

class FallLog:
	var hits: Array = []
	var lands: Array = []

	func on_hit(at: Vector3, top: Vector3, debris: int, live: bool, pole: bool, span: Vector3) -> void:
		hits.append([at, top, debris, live, pole, span])

	func on_land(a: Vector3, b: Vector3, debris: int, live: bool, pole: bool) -> void:
		lands.append([a, b, debris, live, pole])


func _fall_log(props: PropLayer) -> FallLog:
	var fx := FallLog.new()
	props.topple_hit.connect(fx.on_hit)
	props.topple_landed.connect(fx.on_land)
	return fx


## Крутить падіння кроками 50 мс, поки щось ламається (чи поки not until.call()); повертає секунди. Реального часу не чекає.
func _run_falls(props: PropLayer, until: Callable = Callable()) -> float:
	var t: float = 0.0
	while props.falling_count() > 0 and t < 6.0 and not (until.is_valid() and until.call()):
		props._tick_falls(0.05)
		t += 0.05
	return t


func _hidden(props: PropLayer, idx: int) -> bool:
	return (props._final_transform(props._instances[idx]) as Transform3D).basis.get_scale().is_zero_approx()


## Опора з дротом: індекс екземпляра й клітинка.
func _wired_pole(props: PropLayer) -> int:
	for s: Array in props._spans:
		return s[0]
	return -1


func _synthetic_scene(n: int) -> Node3D:
	var root := Node3D.new()
	# Перші дві складові ділять сітку: вони йдуть одним вузлом.
	var shared := BoxMesh.new()
	for k in n:
		var mi := MeshInstance3D.new()
		mi.name = "piece_%02d" % k
		mi.mesh = shared if k < 2 else BoxMesh.new()
		mi.transform = Transform3D(Basis(), Vector3(0.0, 0.1 + 0.3 * float(k), 0.0))
		root.add_child(mi)
	var other := MeshInstance3D.new()
	other.name = "extra"
	root.add_child(other)
	return root


func test_pieces_come_from_piece_nodes_sorted_by_name() -> void:
	var pieces: Array = PropLayer.pieces_of_scene(_synthetic_scene(3))
	assert_eq(pieces.size(), 3, "extra — не складова")
	assert_eq(pieces[2]["name"], "piece_02")
	assert_eq((pieces[1]["xf"] as Transform3D).origin, Vector3(0.0, 0.4, 0.0))
	var whole: Array = PropLayer.broken_pieces(&"infra_pole_wood")
	assert_gte(whole.size(), 1, "без файлу — хоч одна складова з усієї сітки")


func test_pole_snaps_falls_along_travel_breaks_into_pieces_and_vanishes_with_its_wires() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	assert_gte(idx, 0, "на River є лінія")
	var m: StringName = props._instances[idx]["model"]
	PropLayer._pieces_cache[m] = PropLayer.pieces_of_scene(_synthetic_scene(3))
	props._piece_geo.erase(m)
	var cell: Vector2i = (props._instances[idx]["cells"] as Array)[0]
	var spans: int = props.wire_spans()
	var fx := _fall_log(props)
	var travel_step: Array[Vector2i] = _topple_pole(props, idx)
	assert_true(props.is_falling(idx))
	assert_eq(fx.hits.size(), 1, "удар — одна мить")
	assert_true(fx.hits[0][3], "опора з дротом — під напругою")
	assert_eq(fx.lands.size(), 0)
	assert_true(_hidden(props, idx), "ціла модель замінена складовими")
	var b: Dictionary = props._instances[idx]["burst"]
	assert_eq((b["pieces"] as Array).size(), 3)
	assert_eq(((b["root"] as Node).get_child_count()), props._piece_groups(m).size(), "один вузол на матеріал, не на складову")
	assert_true(fx.hits[0][4], "опора")
	var attach_before: Vector3 = PropLayer._attach_point(props._live(props._instances[idx]))
	assert_not_null(props._wires_live.mesh, "дроти падаючої опори — у живому мешу")
	var stumps: Array = (b["pieces"] as Array).filter(func(p: Dictionary) -> bool: return p["stump"])
	assert_eq(stumps.size(), 1, "один пеньок")
	assert_almost_eq((stumps[0]["w0"] as Transform3D).origin.y, (props._instances[idx]["transform"] as Transform3D).origin.y + 0.1, 0.0001, "пеньок — найнижча")
	assert_eq(props.wire_spans(), spans, "дроти тягнуться за падаючим валом")
	var f: Dictionary = props._instances[idx]["fall"]
	assert_gt((f["dir"] as Vector3).dot(Vector3(travel_step[1].x - travel_step[0].x, 0.0, travel_step[1].y - travel_step[0].y)), 0.74, "падає за напрямом руху в межах 40°")
	assert_eq(f["phi"], PropLayer.TOPPLE_PHI0, "стартує з малого кута")
	props._tick_falls(0.05)
	assert_gt(float(f["phi"]), PropLayer.TOPPLE_PHI0)
	for i in 4:
		props._tick_falls(0.1)
	var spent: float = 0.05 + 0.4  # секунди, прокручені до заміру часу падіння нижче
	assert_ne(PropLayer._attach_point(props._live(props._instances[idx])), attach_before, "кінець дроту на опорі йде за нею")
	var t: float = _run_falls(props, func() -> bool: return fx.lands.size() > 0)
	assert_between(t + spent, 1.2, 1.8, "10 м опора падає 1,2–1,8 с")
	assert_true(fx.lands[0][4], "опора")
	assert_eq(fx.lands.size(), 1)
	assert_lt(props.wire_spans(), spans, "дроти зникли в мить удару об землю")
	assert_true(props.is_falling(idx), "уламки ще лежать")
	var stump_pos: Vector3 = stumps[0]["pos"]
	var shaft: Dictionary = (b["pieces"] as Array).filter(func(p: Dictionary) -> bool: return not p["stump"])[0]
	var at_land: Vector3 = shaft["pos"]
	_run_falls(props)
	assert_ne(shaft["pos"], at_land, "складові покотилися далі")
	assert_eq(stumps[0]["pos"], stump_pos, "пеньок на місці")
	assert_false(props.is_falling(idx))
	assert_null(props.find_child("Break", false, false), "вузли уламків прибрано")
	assert_true(_hidden(props, idx))
	var a: Vector3 = fx.lands[0][0]
	var e: Vector3 = fx.lands[0][1]
	var h: float = ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.y
	assert_almost_eq(Vector2(a.x, a.z).distance_to(Vector2(e.x, e.z)), h, 0.001, "накрила відрізок завдовжки з опору")
	PropLayer._pieces_cache.erase(m)
	props._piece_geo.erase(m)
	props.set_crushed([] as Array[Vector2i], true)
	assert_eq(props.wire_spans(), spans, "вид спільний з іншими тестами: повернуто")


func test_fence_bursts_forward_into_pieces_then_vanishes() -> void:
	var view: BoardView = _view(null, _yard_board())
	var props: PropLayer = view.props()
	var cell: Vector2i = _fenced_of(view, _YARD_SIDES)
	assert_ne(cell, Vector2i(-1, -1), "передумова: огорожа під двором")
	var idx: int = -1
	for i in props._instances.size():
		if (props._instances[i]["cells"] as Array).has(cell) and props._instances[i]["topples"]:
			idx = i
	assert_gte(idx, 0)
	var m: StringName = props._instances[idx]["model"]
	PropLayer._pieces_cache[m] = PropLayer.pieces_of_scene(_synthetic_scene(3))
	props._piece_geo.erase(m)
	var fx := _fall_log(props)
	var step: Array[Vector2i] = _hit_step(props, (props._instances[idx]["transform"] as Transform3D).origin, idx)
	assert_eq(step.size(), 2, "передумова: смуга корпусу зачіпає секцію")
	var travel: Vector2i = step[1] - step[0]
	props.topple_cell(step[1], step[0])
	var b: Dictionary = props._instances[idx]["burst"]
	assert_eq((b["pieces"] as Array).size(), 3)
	assert_false(fx.hits[0][3], "паркан без напруги")
	assert_false(fx.hits[0][4], "не опора")
	assert_true(_hidden(props, idx))
	var t: float = _run_falls(props, func() -> bool: return fx.lands.size() > 0)
	assert_between(t, 0.1, 1.2, "перша складова торкається землі")
	var drift: float = 0.0
	for p: Dictionary in b["pieces"]:
		drift += ((p["pos"] as Vector3) - (p["w0"] as Transform3D).origin).dot(Vector3(travel.x, 0.0, travel.y))
	assert_gt(drift, 0.0, "складові летять за напрямом руху")
	_run_falls(props)
	assert_gte(fx.lands.size(), 1, "кожна поламана секція приземлилась")
	assert_false(props.is_falling(idx))
	assert_null(props.find_child("Break", false, false))
	assert_true(_hidden(props, idx))
	PropLayer._pieces_cache.erase(m)
	props._piece_geo.erase(m)


func test_instant_crush_hides_without_a_fall() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	var cell: Vector2i = (props._instances[idx]["cells"] as Array)[0]
	var fx := _fall_log(props)
	var step: Array[Vector2i] = _hit_step(props, (props._instances[idx]["transform"] as Transform3D).origin, idx)
	props.set_crushed([cell] as Array[Vector2i], true, [Vector4i(step[0].x, step[0].y, step[1].x, step[1].y)])
	assert_eq(props.falling_count(), 0)
	assert_true(_hidden(props, idx))
	assert_eq(fx.hits.size() + fx.lands.size(), 0, "без жодної миті")
	props.set_crushed([] as Array[Vector2i], true)


func test_set_crushed_mid_fall_neither_restarts_nor_cancels() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	var cell: Vector2i = (props._instances[idx]["cells"] as Array)[0]
	var fx := _fall_log(props)
	_topple_pole(props, idx)
	props._tick_falls(0.2)
	var phi: float = props._instances[idx]["fall"]["phi"]
	props.set_crushed([] as Array[Vector2i])
	assert_true(props._broken.has(idx), "падіння лишається поламаним, хоч набір ребер його не мав")
	assert_true(props.is_falling(idx), "не скасовано")
	assert_eq(props._instances[idx]["fall"]["phi"], phi, "не почато знову")
	assert_eq(fx.hits.size(), 1)
	_run_falls(props)
	assert_true(_hidden(props, idx))
	props.set_crushed([] as Array[Vector2i], true)


func test_instant_rebuild_finishes_a_running_fall_for_the_next_viewer() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	var cell: Vector2i = (props._instances[idx]["cells"] as Array)[0]
	var spans: int = props.wire_spans()
	_topple_pole(props, idx)
	props._tick_falls(0.2)
	assert_not_null(props._wires_live.mesh)
	props.set_crushed([] as Array[Vector2i], true)
	props._flush()
	assert_null(props._wires_live.mesh, "живих дротів нема")
	assert_eq(props.falling_count(), 0, "гейт обриває падіння")
	assert_null(props.find_child("Break", false, false), "уламків нема")
	assert_false(_hidden(props, idx), "новий глядач цієї клітинки не розвідав: опора стоїть")
	assert_eq(props.wire_spans(), spans)


func test_gate_falls_and_vanishes() -> void:
	var props: PropLayer = _cached("crossroads").props()
	var gi: int = -1
	for i in props._gates.size():
		var g: Dictionary = props._gates[i]
		if g.has("small") and (g["small"] as Vector2i).y > (g["small"] as Vector2i).x:
			gi = i
			break
	assert_gte(gi, 0, "на Crossroads є ворота")
	var g: Dictionary = props._gates[gi]
	var mid: Vector2 = g["mid"]
	var gstep: Array[Vector2i] = _hit_step(props, Vector3(mid.x, 0.0, mid.y), -1, gi)
	assert_eq(gstep.size(), 2, "передумова: смуга корпусу зачіпає ворота")
	props.topple_cell(gstep[1], gstep[0])
	assert_true(g.has("burst"))
	_run_falls(props)
	assert_false(g.has("burst"))
	assert_true(props._gate_down(gi))
	assert_true(bool(g["hidden"]))
	props.set_crushed([] as Array[Vector2i], true)
	props._flush()
	assert_false(bool(g["hidden"]), "повернуто")


func test_step_hook_topples_for_vehicles_only_and_only_on_seen_ground() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_yard_map(), 2, 1, service)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var fx := _fall_log(props)
	await _move(service, screen, RIFLE, Vector2i(4, 4))
	assert_eq(fx.hits.size(), 0, "піхота нічого не валить")
	await _move(service, screen, ARMOURED_CAR, Vector2i(4, 2))
	assert_gt(fx.hits.size(), 0, "броньована машина валить огорожу на шляху")
	await wait_until(func() -> bool: return props.falling_count() == 0, 5.0)
	# Той самий виклик: на розвіданій клітинці валить, на нерозвіданій — ні.
	var state: BattleState = service.state
	var step: Array[Vector2i] = []
	for i in props._instances.size():
		var inst: Dictionary = props._instances[i]
		if inst["band"] and not props._is_crushed(inst):
			step = _hit_step(props, (inst["transform"] as Transform3D).origin, i)
			if not step.is_empty():
				break
	assert_eq(step.size(), 2, "передумова: лишився цілий паркан на шляху корпусу")
	var moved := Events.UnitMoved.new(0, [step[1]] as Array[Vector2i], 0)
	screen._vehicle_moves[moved] = true
	var vision: Vision = state.vision[state.active_player]
	var saved: PackedByteArray = vision.seen.duplicate()
	vision.seen.fill(0)
	var before: int = fx.hits.size()
	screen._on_cell_entered(moved, step[0], step[1])
	assert_eq(fx.hits.size(), before, "§3.5: на нерозвіданому падіння не показується")
	assert_eq(props.falling_count(), 0)
	vision.seen.fill(1)
	screen._on_cell_entered(moved, step[0], step[1])
	assert_gt(fx.hits.size(), before, "на розвіданому — падає")
	var other := Events.UnitMoved.new(1, [step[1]] as Array[Vector2i], 0)
	var after: int = fx.hits.size()
	screen._on_cell_entered(other, step[0], step[1])
	assert_eq(fx.hits.size(), after, "не рух техніки з пакета — не валить")
	vision.seen = saved


## Відтяжка падаючої опори тримається, поки вал не ляже, і зникає разом з ним.
func test_guy_of_a_falling_pole_goes_at_landing() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = -1
	for g: Array in props._guys():
		idx = g[0]
		break
	assert_gte(idx, 0, "на River є відтяжка")
	var cell: Vector2i = (props._instances[idx]["cells"] as Array)[0]
	var fx := _fall_log(props)
	_topple_pole(props, idx)
	var has_guy := func() -> bool:
		return props._guys().any(func(g: Array) -> bool: return g[0] == idx)
	assert_true(has_guy.call(), "відтяжка на місці під час падіння")
	_run_falls(props, func() -> bool: return fx.lands.size() > 0)
	assert_false(has_guy.call(), "зникла при ударі об землю")
	props.set_crushed([] as Array[Vector2i], true)
	props._flush()
	assert_true(has_guy.call(), "повернуто")


func test_every_yard_kind_breaks_from_its_own_file() -> void:
	for k: String in ["picket", "sheet", "chainlink", "brickbars", "slat"]:
		var pieces: Array = PropLayer.broken_pieces(StringName("infra_fence_yard_" + k))
		assert_gt(pieces.size(), 1, "%s: розколота, не вся сітка" % k)
		assert_gte(PropLayer.fence_kind_of(StringName("infra_fence_yard_" + k)), 0, "%s: вид паркану двору" % k)
		for src: Dictionary in pieces:
			assert_not_null((src["mesh"] as Mesh).surface_get_material(0), "%s: шматок має власний матеріал" % k)


## Падіння, що ще йдуть під час передачі ходу, не лишають ні мить ефектів, ні уламків, ні нових мить потім.
func test_handover_gate_cancels_running_falls_and_fx() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_yard_map(), 2, 1, service)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var fx := _fall_log(props)
	await _move(service, screen, ARMOURED_CAR, Vector2i(4, 2))
	assert_gt(fx.hits.size(), 0, "передумова: машина щось валить")
	assert_gt(props.falling_count(), 0, "передумова: падіння ще йде")
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	await wait_physics_frames(3)
	assert_eq(props.falling_count(), 0, "падіння обірвано разом із передачею ходу")
	var lands: int = fx.lands.size()
	props._tick_falls(5.0)
	await wait_physics_frames(2)
	assert_eq(fx.lands.size(), lands, "після гейта нових мить не народжується")
	assert_eq(get_tree().get_nodes_in_group(BattleFx.GROUP).size(), 0, "мить попереднього гравця немає")
	(screen.get_node("%HandoverGate").get_node("%ConfirmButton") as Button).pressed.emit()
	assert_eq(get_tree().get_nodes_in_group(BattleFx.GROUP).size(), 0)
	assert_null(props.find_child("Break", false, false))


## Справжні зламані моделі: земляні валики єврозабору не летять, цегляний цоколь не летить далеко,
## а пеньок опори — частина з тегом stump.
func test_real_pieces_follow_their_part_tags() -> void:
	var props: PropLayer = _cached("river").props()
	var root := Node3D.new()
	add_child_autofree(root)
	var euro: Array = props._burst_pieces(root, &"infra_fence_euro", Transform3D())
	var b := {"pieces": euro, "cell": Vector2i(2, 3)}
	props._throw(b, Vector3.RIGHT)
	var berms: Array = euro.filter(func(p: Dictionary) -> bool: return p["part"] == "berm")
	var thrown: Array = euro.filter(func(p: Dictionary) -> bool: return p["part"] != "berm")
	assert_gt(berms.size(), 0, "у єврозабору є земляні валики")
	assert_gt(thrown.size(), 0)
	for p: Dictionary in berms:
		assert_true(p["stump"], "валик лишається на місці")
		assert_eq(p["vel"], Vector3.ZERO)
	for p: Dictionary in thrown:
		assert_gt((p["vel"] as Vector3).x, -0.01, "решта летить за напрямом")
	var bricks: Array = props._burst_pieces(root, &"infra_fence_yard_brickbars", Transform3D())
	b["pieces"] = bricks
	props._throw(b, Vector3.RIGHT)
	for p: Dictionary in bricks:
		if p["part"] == "plinth":
			assert_true(p["stump"], "цоколь лишається на місці")
	var pole: Array = props._burst_pieces(root, &"infra_pole_wood", Transform3D())
	assert_eq(pole.filter(func(p: Dictionary) -> bool: return p["part"] == "stump").size(), 1, "один пеньок")


## Справжні складові опори після удару об землю розходяться: сегменти лежать не стосом, а поодинці.
func test_real_pole_segments_separate_after_landing() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	var cell: Vector2i = (props._instances[idx]["cells"] as Array)[0]
	var fx := _fall_log(props)
	_topple_pole(props, idx)
	var b: Dictionary = props._instances[idx]["burst"]
	var segs: Array = (b["pieces"] as Array).filter(func(p: Dictionary) -> bool: return p["part"] == "segment")
	assert_gt(segs.size(), 1, "у опори кілька сегментів")
	var rest: Array[Vector3] = []
	for p: Dictionary in segs:
		rest.append((p["w0"] as Transform3D).origin)
	_run_falls(props, func() -> bool: return fx.lands.size() > 0)
	for i in 30:
		props._tick_falls(0.05)
	var spread: float = 0.0
	for i in segs.size():
		for j in range(i + 1, segs.size()):
			spread = maxf(spread, ((segs[i]["pos"] as Vector3).distance_to(segs[j]["pos"] as Vector3)) - rest[i].distance_to(rest[j]))
	assert_gte(spread, 0.2, "сегменти розійшлись щонайменше на 0,2 тайла")
	props.set_crushed([] as Array[Vector2i], true)


## Тонкі картки паркану лягають із нахилом 5–15°: не рівно й не на ребрі.
func test_real_fence_cards_settle_tilted() -> void:
	var props: PropLayer = _cached("river").props()
	var root := Node3D.new()
	add_child_autofree(root)
	var pieces: Array = props._burst_pieces(root, &"infra_fence_yard_sheet", Transform3D(Basis(), Vector3(5.0, 0.0, 5.0)))
	var b := {"pieces": pieces, "cell": Vector2i(2, 3)}
	props._throw(b, Vector3.RIGHT)
	for i in 600:
		for p: Dictionary in pieces:
			if not p["stump"]:
				props._step_piece(p, PropLayer.TOPPLE_DT)
	var cards := 0
	for p: Dictionary in pieces:
		if p["thin"] == Vector3.ZERO or p["stump"]:
			continue
		cards += 1
		var n: Vector3 = ((p["rot"] as Basis) * ((p["w0"] as Transform3D).basis * (p["thin"] as Vector3))).normalized()
		var tilt: float = rad_to_deg(acos(clampf(absf(n.dot(Vector3.UP)), 0.0, 1.0)))
		assert_between(tilt, 4.5, 15.5, "картка лежить із нахилом 5–15°")
	assert_gt(cards, 0, "у профлисту є тонкі картки")


## Крок техніки ламає лише секції в смузі, яку змів корпус; решта двору стоїть.
func test_a_step_breaks_only_the_fences_in_the_swept_band() -> void:
	var view: BoardView = _view(null, _yard_board())
	var props: PropLayer = view.props()
	var total: int = props._instances.filter(func(i: Dictionary) -> bool: return i["band"]).size()
	var step: Array[Vector2i] = []
	for i in props._instances.size():
		if props._instances[i]["band"]:
			step = _hit_step(props, (props._instances[i]["transform"] as Transform3D).origin, i)
			if not step.is_empty():
				break
	assert_eq(step.size(), 2)
	props.topple_cell(step[1], step[0])
	var hits: Array = props.band_hits(step[0], step[1])["inst"]
	assert_gt(hits.size(), 0)
	assert_eq(props._broken.size(), hits.size(), "зламано рівно смугу")
	assert_lt(props._broken.size(), total, "решта парканів стоїть")
	props.cancel_falls()


## Поламаний смугою паркан лишається схованим після будь-якого переписування вузлів (дах розчиняється, перебудова).
func test_band_broken_fence_stays_hidden_after_a_node_rewrite() -> void:
	var view: BoardView = _view(null, _yard_board())
	var props: PropLayer = view.props()
	var idx: int = -1
	var step: Array[Vector2i] = []
	for i in props._instances.size():
		if props._instances[i]["band"] and int(PropLayer.spec_of(props._instances[i]["model"])["kind"]) != PropLayer.Kind.POLE:
			step = _hit_step(props, (props._instances[i]["transform"] as Transform3D).origin, i)
			if not step.is_empty():
				idx = i
				break
	assert_gte(idx, 0)
	props.topple_cell(step[1], step[0])
	_run_falls(props)
	assert_true(_hidden(props, idx))
	props._apply()
	props._write_nodes()
	assert_true(_hidden(props, idx), "переписування вузлів не повертає секцію")
	var edge := Vector4i(step[0].x, step[0].y, step[1].x, step[1].y)
	props.set_crushed([] as Array[Vector2i], true, [edge])
	props._apply()
	assert_true(_hidden(props, idx), "правда з ребер ховає секцію після перебудови чи гейта")
	props.set_crushed([] as Array[Vector2i], true)
	props._apply()
	assert_false(_hidden(props, idx), "без ребер (нерозвіданий глядач) секція стоїть")


func test_strip_has_flat_ends_and_the_start_is_cut_off() -> void:
	var a := Vector2(0.35, 0.0)
	var tip := Vector2(1.35, 0.0)
	assert_true(PropLayer._in_strip(Vector2(1.0, 0.2), a, tip, 0.255))
	assert_false(PropLayer._in_strip(Vector2(1.5, 0.0), a, tip, 0.255), "опора за носом не зачіпається")
	assert_false(PropLayer._in_strip(Vector2(0.1, 0.0), a, tip, 0.255), "початок смуги відрізано: клітинку from перебрано раніше")
	assert_false(PropLayer._in_strip(Vector2(0.9, 0.3), a, tip, 0.255), "збоку — поза смугою")
	assert_true(PropLayer._in_strip(Vector2(0.9, 0.45), a, tip, PropLayer.POLE_BAND_HALF), "опора збоку в межах півтайла")


## Опора падає в межах 40° від напряму руху і не лягає на стоячі паркани, якщо є чистий напрям.
func test_pole_fall_direction_stays_within_forty_degrees() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	var t: Transform3D = props._instances[idx]["transform"]
	var h: float = ((PropLayer.model(props._instances[idx]["model"]) as Dictionary)["aabb"] as AABB).size.y
	for ang in [0.0, 90.0, 180.0, 270.0]:
		var want := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(ang))
		var pick: Array = props._clear_direction(idx, t.origin, want, h)
		assert_gte((pick[0] as Vector3).dot(want), cos(deg_to_rad(40.0)) - 0.001, "напрям у межах 40° від руху")
		if (pick[1] as Array).is_empty():
			var hit: Dictionary = props._shaft_conflicts(idx, t.origin, pick[0], h)
			assert_false(hit["blocked"])


## Вал опори не лягає на корпус машини, що зупинилась (і на будь-який відомий юніт); без списку — як було.
func test_pole_shaft_avoids_known_unit_hulls() -> void:
	var props: PropLayer = _cached("river").props()
	var idx: int = _wired_pole(props)
	var t: Transform3D = props._instances[idx]["transform"]
	var h: float = ((PropLayer.model(props._instances[idx]["model"]) as Dictionary)["aabb"] as AABB).size.y
	var a := Vector2(t.origin.x, t.origin.z)
	# Машина стоїть за напрямом руху від основи, на шляху вала.
	var hull := Vector2i(roundi(a.x + 1.0), roundi(a.y))
	var want := Vector3(float(hull.x) - a.x, 0.0, float(hull.y) - a.y).normalized()
	var open: Array = props._clear_direction(idx, t.origin, want, h)
	props._avoid = [hull]
	var pick: Array = props._clear_direction(idx, t.origin, want, h)
	props._avoid = []
	var shaft := func(d: Vector3) -> float:
		var best := INF
		for k in 9:
			best = minf(best, (a + Vector2(d.x, d.z) * h * float(k) / 8.0).distance_to(Vector2(hull)))
		return best
	assert_lt(shaft.call(want), PropLayer.UNIT_HULL_R, "передумова: без корпуса вал лягав би на нього")
	assert_gt(shaft.call(pick[0]), PropLayer.UNIT_HULL_R, "вал не проходить крізь корпус")
	assert_ne(pick[0], want, "корпус на шляху міняє напрям падіння")


## Напрям падіння знає лише про юнітів, яких глядач вправі знати.
func test_fall_direction_is_steered_only_by_known_units() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_yard_map(), 2, 1, service)
	var known: Array = screen._known_unit_cells()
	assert_true(known.has(Vector2i(1, 2)), "свої юніти відомі")
	assert_false(known.has(Vector2i(13, 7)), "прихований ворог не береться до уваги")


## §8: вибух ламаного — один вузол на матеріал, а не на складову; найгірший крок на River лишається в бюджеті.
func test_burst_nodes_follow_materials_not_pieces() -> void:
	var props: PropLayer = _cached("river").props()
	var root := Node3D.new()
	add_child_autofree(root)
	for m: StringName in [&"infra_fence_euro", &"infra_fence_yard_picket", &"infra_pole_wood", &"infra_fence_sheet_green"]:
		var pieces: Array = props._burst_pieces(root, m, Transform3D())
		var mats: Array = []
		for src: Dictionary in PropLayer.broken_pieces(m):
			for si in (src["mesh"] as Mesh).get_surface_count():
				var mat: Material = (src["mesh"] as Mesh).surface_get_material(si)
				if not mats.has(mat):
					mats.append(mat)
		var groups: Array = root.get_meta("groups")
		assert_gt(pieces.size(), 1, "%s: розколото" % m)
		assert_lte(groups.size(), mats.size(), "%s: вузлів не більше, ніж матеріалів" % m)
		for c in root.get_children():
			c.free()


func test_worst_river_step_stays_within_the_node_budget() -> void:
	var view: BoardView = _cached("river")
	var props: PropLayer = view.props()
	props.topple_cell(Vector2i(6, 4), Vector2i(6, 5))
	var nodes: int = 0
	for b: Dictionary in props._falls:
		if b["root"] != null:
			nodes += (b["root"] as Node).get_child_count()
	assert_gt(props._falls.size(), 0, "крок щось ламає")
	assert_lte(nodes, 2 * props._falls.size() + 4, "вузлів уламків — по матеріалу на вибух")
	assert_lt(nodes, 30, "найгірший крок River далеко від бюджету викликів малювання")
	props.cancel_falls()
	props.set_crushed([] as Array[Vector2i], true)


## §3.5: злам показується лише коли власна клітинка пропса розвідана — навіть якщо from і сусідні клітинки ні.
func test_break_is_shown_only_where_the_props_own_cell_is_seen() -> void:
	var view: BoardView = _view(null, _yard_board())
	var props: PropLayer = view.props()
	var idx: int = -1
	var step: Array[Vector2i] = []
	for i in props._instances.size():
		if props._instances[i]["band"] and int(PropLayer.spec_of(props._instances[i]["model"])["kind"]) != PropLayer.Kind.POLE:
			step = _hit_step(props, (props._instances[i]["transform"] as Transform3D).origin, i)
			if not step.is_empty():
				idx = i
				break
	assert_gte(idx, 0)
	var home: Vector2i = PropLayer._home_of(props._instances[idx])
	var edge := Vector4i(step[0].x, step[0].y, step[1].x, step[1].y)
	var none := func(_c: Vector2i) -> bool: return false
	var only_to := func(c: Vector2i) -> bool: return c == step[1] and c != home
	var only_home := func(c: Vector2i) -> bool: return c == home
	props.set_crushed([] as Array[Vector2i], true, [edge], none)
	assert_false(props._is_crushed(props._instances[idx]), "нічого не розвідано — не ламається")
	props.set_crushed([] as Array[Vector2i], true, [edge], only_to)
	assert_false(props._is_crushed(props._instances[idx]), "розвідано лише клітинку to, а власна клітинка ні")
	props.set_crushed([] as Array[Vector2i], true, [edge], only_home)
	assert_true(props._is_crushed(props._instances[idx]), "власна клітинка розвідана — зламано")
	# Те саме для живої анімації.
	props.set_crushed([] as Array[Vector2i], true)
	props.topple_cell(step[1], step[0], [], none)
	assert_eq(props.falling_count(), 0, "нерозвіданого падіння не показано")
	props.topple_cell(step[1], step[0], [], only_home)
	assert_gt(props.falling_count(), 0)
	props.cancel_falls()
	props.set_crushed([] as Array[Vector2i], true)


## Вторинний злам (вал опори ліг на паркан) переживає перебудову, гейт і перебудову дошки (build).
func test_secondary_breaks_survive_rebuilds() -> void:
	var view: BoardView = _view(null, _yard_board())
	var props: PropLayer = view.props()
	var fence: int = -1
	for i in props._instances.size():
		if props._instances[i]["band"] and int(PropLayer.spec_of(props._instances[i]["model"])["kind"]) != PropLayer.Kind.POLE:
			fence = i
			break
	var origin: Vector3 = (props._instances[fence]["transform"] as Transform3D).origin
	var marks: Array[Vector3] = [origin]
	props.set_crushed([] as Array[Vector2i], true, [] as Array[Vector4i], Callable(), marks)
	assert_true(props._is_crushed(props._instances[fence]), "позначений паркан зламано")
	props.set_crushed([] as Array[Vector2i], false, [] as Array[Vector4i], Callable(), marks)
	assert_true(props._is_crushed(props._instances[fence]), "після нової команди теж")
	view.rebuild_tiles(_yard_board())
	assert_true(props._is_crushed(props._instances[fence]), "перебудова дошки повертає зламане одразу")
	props.set_crushed([] as Array[Vector2i], true)
