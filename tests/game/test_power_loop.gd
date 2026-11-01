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


func _is_crown(f: ForestLayer, e: Dictionary) -> bool:
	var node: String = e["node"]
	if e["ground"] or not f._lib.has(node) or not node.get_slice("_", 0) in ForestLayer.TREES:
		return false
	return float(f._lib[node]["h"]) * e["xf"].basis.get_scale().y >= ForestLayer.UNDER_TOP


## Жодна крона (дошки й кільця, радіус — який побачить гравець) не підходить до проліту ближче за CROWN_MARGIN.
func test_no_tree_crown_under_a_power_line(p = use_parameters(MAPS)) -> void:
	var view: BoardView = null
	_props(p)
	view = _views[p]
	var spans: Array = view.props().span_lines()
	var f: ForestLayer = view.forest()
	var crowns: Array[Dictionary] = []
	for e: Dictionary in f.board_plan:
		if _is_crown(f, e):
			crowns.append(e)
	crowns.append_array(f._ring_crowns)
	assert_gt(crowns.size(), 0, "%s: передумова — крони є" % p)
	var fwd: Vector2 = ForestLayer._view_fwd()
	for e: Dictionary in crowns:
		var at: Vector2 = e["pos"]
		var top: float = float(e["top"]) if e.has("top") else float(f._lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y
		var sh: Vector2 = ForestLayer.crown_shift(top)
		# Крона на екрані лежить уздовж зсуву: кожна її точка далі за CROWN_MARGIN від проліту (на екрані — від дроту).
		for k in 9:
			var q: Vector2 = at + fwd * lerpf(sh.x, sh.y, k / 8.0)
			for w: Array in spans:
				var gap: float = q.distance_to(Geometry2D.get_closest_point_to_segment(q, w[0], w[1])) - float(e["r"])
				assert_gte(gap, ForestLayer.CROWN_MARGIN - 1e-4, "%s: крона %s (r=%.2f, h=%.2f) за %.2f від проліту %s" % [p, at, e["r"], top, gap, w])


## Підлісок вищий за 0.4 тайла (кущі, молоді дерева) теж не лежить на дроті на екрані: низький кущ лишається, решта — ні.
func test_no_tall_undergrowth_under_a_power_line(p = use_parameters(MAPS)) -> void:
	_props(p)
	var view: BoardView = _views[p]
	var spans: Array = view.props().span_lines()
	var f: ForestLayer = view.forest()
	var fwd: Vector2 = ForestLayer._view_fwd()
	var seen: int = 0
	for e: Dictionary in f.board_plan:
		if e["ground"] or not f._lib.has(e["node"]) or str(e["node"]).begins_with("Hedge"):
			continue
		var top: float = float(f._lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y
		if top <= 0.4:
			continue
		seen += 1
		var sh: Vector2 = ForestLayer.crown_shift(top)
		for k in 9:
			var q: Vector2 = (e["pos"] as Vector2) + fwd * lerpf(sh.x, sh.y, k / 8.0)
			for w: Array in spans:
				var gap: float = q.distance_to(Geometry2D.get_closest_point_to_segment(q, w[0], w[1])) - float(e["r"])
				assert_gte(gap, ForestLayer.CROWN_MARGIN - 1e-4, "%s: %s (h=%.2f) %s за %.2f від проліту %s" % [p, e["node"], top, e["pos"], gap, w])
	assert_gt(seen, 0, "%s: передумова — високий підлісок є" % p)
