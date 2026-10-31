extends GutTest
## Просіка ЛЕП у лісі: на справжніх картах жодна крона дерева не накриває дріт (запас 0,15 тайла —
## літерал, не допоміжна функція шару), а клітинка лісу під дротом лишається лісом.

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


func test_no_crown_over_wires(p = use_parameters(["river", "ridge"])) -> void:
	var view: BoardView = _view(p)
	var f: ForestLayer = view.forest()
	var wires: Array = view.props().wire_lines()
	var board: Board = (load("res://maps/%s.tres" % p) as MapData).to_board()
	var crossed: Dictionary = {}
	for w: Array in wires:
		for i in 41:
			var s: Vector2 = (w[0] as Vector2).lerp(w[1], i / 40.0)
			var c := Vector2i(roundi(s.x), roundi(s.y))
			if board.in_bounds(c) and board.kind_at(c) == Terrain.Kind.FOREST:
				crossed[c] = true
	assert_gt(crossed.size(), 0, "%s: дріт перетинає ліс" % p)
	var bad: int = 0
	for e: Dictionary in f.board_plan:
		if not _is_crown(f, e):
			continue
		for w: Array in wires:
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(e["pos"], w[0], w[1])
			if q.distance_to(e["pos"]) < float(e["r"]) + 0.15:
				bad += 1
				break
	assert_eq(bad, 0, "%s: крон над дротами" % p)
	for c: Vector2i in crossed:
		var left: int = 0
		for e: Dictionary in f.board_plan:
			if not e["ground"] and Vector2i(roundi(e["pos"].x), roundi(e["pos"].y)) == c:
				left += 1
		assert_gt(left, 0, "%s: клітинка лісу %s під дротом спорожніла" % [p, c])
