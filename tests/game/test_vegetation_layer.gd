extends GutTest

## Розставлення рослинності (VegetationLayer) на справжніх картах: береги, луки, двори — за правилами
## шару й правилами поля (§8: вода ≥ 0,3 від центру клітинки суходолу).

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
var _views: Dictionary = {}


func _view(name: String) -> BoardView:
	if not _views.has(name):
		var m: MapData = load("res://maps/%s.tres" % name) as MapData
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


func _board(name: String) -> Board:
	return (load("res://maps/%s.tres" % name) as MapData).to_board()


func test_every_map_has_bank_meadow_and_yard_plants(p = use_parameters(MAPS)) -> void:
	var veg: VegetationLayer = _view(p).vegetation()
	var by: Dictionary = {}
	for pl: Dictionary in veg.placements:
		by[pl["group"]] = int(by.get(pl["group"], 0)) + 1
	assert_gt(int(by.get("bank", 0)), 10, "%s: берегової рослинності %s" % [p, by])
	assert_gt(int(by.get("meadow", 0)), 0, "%s: на луках нічого (%s)" % [p, by])
	if not VillageLayout.for_map(StringName(p)).get("homes", []).is_empty():
		assert_gt(int(by.get("yard", 0)), 0, "%s: у дворах нічого (%s)" % [p, by])


func test_reeds_stand_in_shallow_water_off_land(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(p)
	var board: Board = _board(p)
	var h: TerrainHeight = view.get("_height")
	var bad: Array = []
	for pl: Dictionary in view.vegetation().placements:
		if pl["kind"] != "reed":
			continue
		var q := Vector2(pl["pos"].x, pl["pos"].z)
		var g: float = h.at(q.x, q.y)
		if g > TerrainHeight.WATER_LEVEL + 0.001 or g < TerrainHeight.WATER_LEVEL - VegetationLayer.SHALLOW - 0.001:
			bad.append([pl["node"], q, "not shallow"])
		if VegetationLayer._land_dist(board, q) < VegetationLayer.LAND_CLEAR:
			bad.append([pl["node"], q, "too close to land centre"])
		if VegetationLayer._near_kind(board, pl["cell"], VegetationLayer.NO_BRIDGE, [Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]):
			bad.append([pl["node"], q, "near bridge"])
	assert_eq(bad, [], "%s: очерет не на мілині" % p)


func test_land_plants_keep_off_roads_water_fields_fences_and_roofs(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(p)
	var board: Board = _board(p)
	var h: TerrainHeight = view.get("_height")
	var veg: VegetationLayer = view.vegetation()
	var obst: Dictionary = VegetationLayer.obstacles(view.props())
	var bad: Array = []
	for pl: Dictionary in veg.placements:
		if pl["kind"] == "reed":
			continue
		var q := Vector2(pl["pos"].x, pl["pos"].z)
		var c := Vector2i(roundi(q.x), roundi(q.y))
		var k: int = board.kind_at(c)
		if k in [Terrain.Kind.ROAD, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED, Terrain.Kind.WATER]:
			bad.append([pl["node"], q, "cell %d" % k])
		if view.props().on_road(q, VegetationLayer.ROAD_PAD):
			bad.append([pl["node"], q, "road shoulder"])
		if h.at(q.x, q.y) < TerrainHeight.WATER_LEVEL + VegetationLayer.DRY:
			bad.append([pl["node"], q, "water"])
		for r: Rect2 in veg.fields:
			if r.has_point(q):
				bad.append([pl["node"], q, "ploughed"])
		for r: Rect2 in obst["roofs"]:
			if VegetationLayer._rect_dist(r, q) < VegetationLayer.crown_of(pl["node"]):
				bad.append([pl["node"], q, "crown on roof"])
		for r: Rect2 in obst["small"]:
			if VegetationLayer._rect_dist(r, q) < VegetationLayer.FENCE_CLEAR:
				bad.append([pl["node"], q, "on fence"])
		if pl["group"] == "bank" and not VegetationLayer.near_water(h, q, VegetationLayer.SHORE_REACH):
			bad.append([pl["node"], q, "bank bush far from water"])
	assert_eq(bad, [], "%s: рослини не на своїх місцях" % p)


func test_placement_is_deterministic_per_seed() -> void:
	var view: BoardView = _view("river")
	var board: Board = _board("river")
	var homes: Array = VillageLayout.for_map(&"river").get("homes", [])
	var a: Array[Dictionary] = VegetationLayer.plan(board, view.get("_height"), view.vegetation().fields, 7, view.props(), homes)
	var b: Array[Dictionary] = VegetationLayer.plan(board, view.get("_height"), view.vegetation().fields, 7, view.props(), homes)
	var c: Array[Dictionary] = VegetationLayer.plan(board, view.get("_height"), view.vegetation().fields, 8, view.props(), homes)
	assert_eq(a, b, "те саме зерно — те саме розставлення")
	assert_ne(a, c, "інше зерно — інше розставлення")
	assert_ne(VegetationLayer.point_seed(7, Vector2i(1, 2), 1), VegetationLayer.point_seed(7, Vector2i(2, 1), 1), "зерно точки залежить від клітинки")
	assert_ne(VegetationLayer.point_seed(7, Vector2i(1, 2), 1), VegetationLayer.point_seed(7, Vector2i(1, 2), 2), "зерно точки залежить від солі")


func test_plants_over_a_unit_fade_and_crushed_ones_fall() -> void:
	var veg: VegetationLayer = _view("river").vegetation()
	var target: Dictionary = {}
	for pl: Dictionary in veg.placements:
		if pl["kind"] == "tree":
			target = pl
			break
	assert_false(target.is_empty(), "на Річці нема дерева")
	if target.is_empty():
		return
	var cell: Vector2i = target["cell"]
	veg.set_reveal_cells([cell])
	var faded: bool = false
	for ch in veg.get_children():
		faded = faded or String(ch.name).ends_with("_faded")
	assert_true(faded, "дерево над юнітом мусить стати напівпрозорим")
	veg.set_reveal_cells([])
	veg.set_crushed([cell])
	var fallen: bool = false
	for ch in veg.get_children():
		fallen = fallen or String(ch.name).ends_with("_fallen")
	assert_true(fallen, "розчавлене дерево мусить показати повалений двійник")
	veg.set_crushed([])
