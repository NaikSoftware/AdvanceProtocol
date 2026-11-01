extends GutTest
## Просіка ЛЕП у лісі: на справжніх картах жодна крона дерева не стоїть ближче за півширину просіки
## (1 тайл — літерал, не стала шару) до прольоту, а клітинка лісу під прольотом лишається лісом.

var _views: Dictionary = {}


func _view(map: String) -> BoardView:
	if not _views.has(map):
		var m: MapData = load("res://maps/%s.tres" % map) as MapData
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		view.build(m.to_board())
		_views[map] = view
	return _views[map]


func after_all() -> void:
	for v: BoardView in _views.values():
		v.free()
	_views.clear()


func _is_crown(f: ForestLayer, e: Dictionary) -> bool:
	var node: String = e["node"]
	if e["ground"] or not f._lib.has(node) or not node.get_slice("_", 0) in ForestLayer.TREES:
		return false
	return float(f._lib[node]["h"]) * e["xf"].basis.get_scale().y >= ForestLayer.UNDER_TOP


func test_no_crown_over_spans(p = use_parameters(["river", "ridge", "crossroads"])) -> void:
	var view: BoardView = _view(p)
	var f: ForestLayer = view.forest()
	var spans: Array = view.props().span_lines()
	var board: Board = (load("res://maps/%s.tres" % p) as MapData).to_board()
	# Клітинки лісу, чий центр лежить не далі за 1,5 тайла від прольоту: туди просіка заходить.
	var crossed: Dictionary = {}
	for w: Array in spans:
		for y in board.height:
			for x in board.width:
				var c := Vector2i(x, y)
				if board.kind_at(c) == Terrain.Kind.FOREST and Vector2(c).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(c), w[0], w[1])) < 1.5:
					crossed[c] = true
	if p != "crossroads":
		assert_gt(crossed.size(), 0, "%s: проліт перетинає ліс" % p)
	var bad: int = 0
	for e: Dictionary in f.board_plan:
		if not _is_crown(f, e):
			continue
		for w: Array in spans:
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(e["pos"], w[0], w[1])
			if q.distance_to(e["pos"]) < 1.0:
				bad += 1
				break
	assert_eq(bad, 0, "%s: крон у просіці" % p)
	for c: Vector2i in crossed:
		var left: int = 0
		for e: Dictionary in f.board_plan:
			if not e["ground"] and Vector2i(roundi(e["pos"].x), roundi(e["pos"].y)) == c:
				left += 1
		assert_gt(left, 0, "%s: клітинка лісу %s під прольотом спорожніла" % [p, c])
