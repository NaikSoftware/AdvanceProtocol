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


## Увесь рослинний план дошки (дерева, кущі, живопліт) і крони кільця лежать на екрані поза дротом: тіло рослини й дріт
## на висоті опори проєктуються вздовж погляду, і зазор між ними не менший за CROWN_MARGIN. Покривний підлісок
## (cover) іде за тим самим правилом, лишень у клітинці, де чистого місця нема зовсім, бере найкраще.
func test_no_foliage_under_a_power_line_on_screen(p = use_parameters(MAPS)) -> void:
	_props(p)
	var view: BoardView = _views[p]
	var spans: Array = view.props().span_lines()
	var f: ForestLayer = view.forest()
	var seen: int = 0
	var tight: int = 0
	var items: Array[Dictionary] = []
	for e: Dictionary in f.board_plan:
		var species: String = str(e["node"]).get_slice("_", 0)
		if e["ground"] or not f._lib.has(e["node"]) or not (species in ForestLayer.TREES or species in ["Shrub", "Hedge"]):
			continue
		items.append({"pos": e["pos"], "r": e["r"], "top": float(f._lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y, "node": e["node"], "cover": e.get("cover", false)})
	for e: Dictionary in f._ring_crowns:
		items.append({"pos": e["pos"], "r": e["r"], "top": e["top"], "node": "ring", "cover": false})
	for it: Dictionary in items:
		seen += 1
		var gap: float = ForestLayer.screen_gap(it["pos"], it["top"], it["r"], spans)
		if it["cover"] and gap < ForestLayer.CROWN_MARGIN - 1e-4:
			tight += 1
			continue
		assert_gte(gap, ForestLayer.CROWN_MARGIN - 1e-4, "%s: %s (h=%.2f) %s на екрані за %.2f від дроту" % [p, it["node"], it["top"], it["pos"], gap])
	assert_gt(seen, 0, "%s: передумова — рослини є" % p)
	gut.p("%s: рослин %d, тісних покривних %d" % [p, seen, tight])


## Група дерев Ріки біля (17, 1) стоїть за дротом (13.9, 3.51)–(20.51, 3.51) на 2.5 тайла вглиб, але на екрані дріт
## на висоті опори лягає їй на крони: камера гри зсуває точку на PROJ_K тайлів вглиб на кожен тайл висоти. Такого
## дерева в плані немає, а штучне — лягає на дріт.
func test_tree_behind_the_wire_lies_on_it_on_screen() -> void:
	var wire: Array = [[Vector2(13.9, 3.51), Vector2(20.51, 3.51)]]
	assert_lt(ForestLayer.screen_gap(Vector2(17.0, 1.0), 1.4, 0.5, wire), ForestLayer.CROWN_MARGIN, "крона 1.4 тайла за дротом на екрані лежить на ньому")
	assert_gt(ForestLayer.screen_gap(Vector2(17.0, 5.5), 1.4, 0.5, wire), ForestLayer.CROWN_MARGIN, "а перед дротом (ближче до камери) — ні")
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
