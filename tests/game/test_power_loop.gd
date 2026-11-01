extends GutTest
## ЛЕП без павутини: мережа опор — ліс без циклів (лінії не замикають кільце навколо поля), а дроти не лежать під кронами.

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
var _views: Dictionary = {}


func _props(name: String) -> PropLayer:
	if not _views.has(name):
		var m: MapData = load("res://maps/%s.tres" % name) as MapData
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		view.build(m.to_board())
		_views[name] = view
	return (_views[name] as BoardView).props()


func after_all() -> void:
	for v: BoardView in _views.values():
		v.free()
	_views.clear()


func _grid(p: String) -> PowerGrid:
	var g := PowerGrid.new()
	g.plan(_props(p)._placer)
	return g


## Кінець гілки 0.4 кВ не стоїть біля магістралі: така гілка лише дублює її й замикає навколо поля кільце.
func test_branch_ends_keep_off_the_trunk(p = use_parameters(MAPS)) -> void:
	var g: PowerGrid = _grid(p)
	var ends: Dictionary = {}
	var trunk: Array = []
	for line: Dictionary in g.lines:
		var pts: Array = line["points"]
		if line["kind"] == &"10kv":
			for k in range(1, pts.size()):
				trunk.append([pts[k - 1], pts[k]])
		else:
			for q: Vector2 in [pts.front(), pts.back()]:
				ends[q] = int(ends.get(q, 0)) + 1
	for line: Dictionary in g.lines:
		if line["kind"] != &"04kv":
			continue
		var pts: Array = line["points"]
		# Кінець лінії, якого більше ніщо не торкається, і не ТП.
		var q: Vector2 = pts.back()
		if int(ends[q]) > 1 or g.transformers.has(q) or trunk.any(func(e: Array) -> bool: return (e[0] == q or e[1] == q)):
			continue
		for e: Array in trunk:
			var d: float = Geometry2D.get_closest_point_to_segment(q, e[0], e[1]).distance_to(q)
			assert_gte(d, PowerGrid.LEAF_CLEAR, "%s: кінець гілки %s за %.2f від магістралі" % [p, q, d])


## Мережа опор — ліс: жодна лінія не замикає цикл.
func test_pole_graph_has_no_cycle(p = use_parameters(MAPS)) -> void:
	var par: Dictionary = {}
	var find := func(x: Vector2i) -> Vector2i:
		while par[x] != x:
			par[x] = par[par[x]]
			x = par[x]
		return x
	for s: Array in _props(p).span_lines():
		var a := Vector2i((s[0] as Vector2) * 10.0)
		var b := Vector2i((s[1] as Vector2) * 10.0)
		for v: Vector2i in [a, b]:
			if not par.has(v):
				par[v] = v
		var ra: Vector2i = find.call(a)
		var rb: Vector2i = find.call(b)
		assert_ne(ra, rb, "%s: проліт %s–%s замикає цикл" % [p, a, b])
		par[ra] = rb


## Крони дерев (вищих за LOW_KEEP) дошки й кільця лежать на екрані поза дротом: тіло крони й дріт на висоті опори
## проєктуються вздовж погляду, і зазор між ними не менший за CROWN_MARGIN. Низький підлісок під дротом лишається.
func test_no_tree_crown_under_a_power_line_on_screen(p = use_parameters(MAPS)) -> void:
	_props(p)
	var view: BoardView = _views[p]
	var spans: Array = view.props().span_lines()
	var f: ForestLayer = view.forest()
	var items: Array[Dictionary] = []
	for e: Dictionary in f.board_plan:
		var species: String = str(e["node"]).get_slice("_", 0)
		if e["ground"] or not f._lib.has(e["node"]) or not species in ForestLayer.TREES:
			continue
		var top: float = float(f._lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y
		if top > ForestLayer.LOW_KEEP:
			items.append({"pos": e["pos"], "r": e["r"], "top": top, "node": e["node"]})
	for e: Dictionary in f._ring_crowns:
		items.append({"pos": e["pos"], "r": e["r"], "top": e["top"], "node": e["node"]})
	assert_gt(items.size(), 0, "%s: передумова — крони є" % p)
	for it: Dictionary in items:
		var gap: float = ForestLayer.screen_gap(it["pos"], it["top"], it["r"], spans, it["node"])
		assert_gte(gap, ForestLayer.CROWN_MARGIN - 1e-4, "%s: %s (h=%.2f) %s на екрані за %.2f від дроту" % [p, it["node"], it["top"], it["pos"], gap])


## Підлісок під проводом лишається: просіка не знімає низьких кущів і живоплоту — вони тримають клітину лісом. Скільки
## рослин лишилось у лісовій клітині під прольотом (на екрані тут видно, що ліс не лисіє), тест лише друкує.
func test_low_undergrowth_stays_under_the_wires(p = use_parameters(MAPS)) -> void:
	_props(p)
	var view: BoardView = _views[p]
	var spans: Array = view.props().span_lines()
	var f: ForestLayer = view.forest()
	var low_under: int = 0
	var bare: Array[Vector2i] = []
	var count: Dictionary = {}
	for e: Dictionary in f.board_plan:
		if e["ground"] or not f._lib.has(e["node"]):
			continue
		var c := Vector2i(roundi(e["pos"].x), roundi(e["pos"].y))
		count[c] = int(count.get(c, 0)) + 1
		var top: float = float(f._lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y
		if top <= ForestLayer.LOW_KEEP and ForestLayer.screen_gap(e["pos"], top, e["r"], spans, e["node"]) < 0.0:
			low_under += 1
	for c: Vector2i in f._cells:
		if f._in_board(Vector2(c)) and int(count.get(c, 0)) < 3 and f._ground_gap(Vector2(c)) < 1.5:
			bare.append(c)
	gut.p("%s: низького підліску на дроті %d; лісових клітин під прольотом майже без рослин: %s" % [p, low_under, bare])
	if p == "river":
		gut.p("river, шелтербелт x=13: клітини (13,0) %d, (13,1) %d, (13,2) %d рослин" % [count.get(Vector2i(13, 0), 0), count.get(Vector2i(13, 1), 0), count.get(Vector2i(13, 2), 0)])
	if p != "crossroads":
		assert_gt(low_under, 0, "%s: низький підлісок під дротом лишається" % p)
	else:
		pass_test("crossroads: без підліску під дротом")


## Група дерев Ріки біля (17, 1) стоїть за дротом (13.9, 3.51)–(20.51, 3.51) на 2.5 тайла вглиб, але на екрані дріт
## на висоті опори лягає їй на крони: камера гри зсуває точку на PROJ_K тайлів вглиб на кожен тайл висоти. Такого
## дерева в плані немає, а штучне — лягає на дріт.
func test_tree_behind_the_wire_lies_on_it_on_screen() -> void:
	var wire: Array = [[Vector2(13.9, 3.51), Vector2(20.51, 3.51)]]
	assert_lt(ForestLayer.screen_gap(Vector2(17.0, 1.0), 1.4, 0.5, wire, "Spruce_B"), ForestLayer.CROWN_MARGIN, "крона 1.4 тайла за дротом на екрані лежить на ньому")
	assert_gt(ForestLayer.screen_gap(Vector2(17.0, 5.5), 1.4, 0.5, wire, "Spruce_B"), ForestLayer.CROWN_MARGIN, "а перед дротом (ближче до камери) — ні")
	_props("river")
	var f: ForestLayer = (_views["river"] as BoardView).forest()
	for e: Dictionary in f.board_plan:
		var h: float = float(f._lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y if f._lib.has(e["node"]) else 0.0
		# Ялини групи, крізь чиї крони на кадрі йшли три дроти.
		for at: Vector2 in [Vector2(16.8126, 1.02538), Vector2(17.00087, 1.391728), Vector2(17.43409, 1.265139)]:
			if h > 1.0 and (e["pos"] as Vector2).distance_to(at) < 0.05:
				fail_test("дерево %s %s за дротом лишилось" % [e["node"], e["pos"]])
				return
	pass_test("ok")


## Береза Ріки (16.71, 0.58) у пізню осінь стоїть без листя: це одне ціле дерево з однієї сітки (стовбур і крона — один
## екземпляр), просіка знімає рослину цілою, а не крону окремо від стовбура. Тож білий стовбур без крони на кадрі — голе
## дерево, а не недорубане.
func test_plants_are_culled_whole() -> void:
	_props("river")
	var f: ForestLayer = (_views["river"] as BoardView).forest()
	assert_eq(f._season, "late", "Ріка — пізня осінь: береза гола")
	for name: String in ["Birch_A", "Birch_B", "Birch_R", "Spruce_A", "Spruce_B", "Pine_A"]:
		assert_eq((f._mesh[name] as Mesh).get_surface_count(), 1, "%s: стовбур і крона — одна поверхня" % name)
	var kept: bool = false
	for e: Dictionary in f.board_plan:
		if e["node"] == "Birch_A" and (e["pos"] as Vector2).distance_to(Vector2(16.71053, 0.58127)) < 0.01:
			kept = true
	assert_true(kept, "береза (16.71, 0.58) лишилась цілою: на дроті її крони нема")

