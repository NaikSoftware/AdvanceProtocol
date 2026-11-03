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
	assert_gt(int(by.get("bank", 0)) + int(by.get("pond", 0)), 10, "%s: берегової рослинності %s" % [p, by])
	assert_gt(int(by.get("meadow", 0)), 0, "%s: на луках нічого (%s)" % [p, by])
	# Садиби Перехрестя й Хребта затиснуті між дорогами й дахами: дерево там може не влізти ніде.
	if p == "river":
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
		if pl["pos"].y < TerrainHeight.WATER_LEVEL - VegetationLayer.REED_DIP - 1e-4:
			bad.append([pl["node"], q, "base too deep under water"])
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
		if VegetationLayer.near_road(view.props(), q, VegetationLayer.crown_of(pl["node"])):
			bad.append([pl["node"], q, "road shoulder"])
		if h.at(q.x, q.y) < TerrainHeight.WATER_LEVEL + VegetationLayer.DRY:
			bad.append([pl["node"], q, "water"])
		for r: Rect2 in veg.fields:
			if r.has_point(q):
				bad.append([pl["node"], q, "ploughed"])
		# Кущ садиби може рости попід стіною (YARD_BUSH_WALL радіуса крони від даху).
		var wall: float = VegetationLayer.YARD_BUSH_WALL if pl["group"] == "yard" and pl["kind"] == "bush" else 1.0
		for r: Rect2 in obst["roofs"]:
			if VegetationLayer._rect_dist(r, q) < VegetationLayer.crown_of(pl["node"]) * wall - 0.001:
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
	var fallen: bool = veg.drawn_nodes().any(func(n: StringName) -> bool: return String(n).ends_with("_fallen"))
	assert_true(fallen, "розчавлене дерево мусить показати повалений двійник")
	veg.set_crushed([])


## Ставок: очерет плямами на 25–40 % довжини урізу (з розмахом куртин), 3–5 плям, не далі 1 м від урізу.
func test_pond_reeds_patchy_and_hug_the_shore(p = use_parameters(["crossroads", "ridge"])) -> void:
	var view: BoardView = _view(p)
	var board: Board = _board(p)
	var h: TerrainHeight = view.get("_height")
	var ponds: Array = VegetationLayer.ponds(board)
	assert_gt(ponds.size(), 0, "%s: ставків немає" % p)
	for pond: Array[Vector2i] in ponds:
		var ring: PackedVector2Array = VegetationLayer.shore_ring(h, VegetationLayer.pond_centre(pond))
		var reeds: Array = view.vegetation().placements.filter(func(pl: Dictionary) -> bool:
			return pl["group"] == "pond" and pond.has(pl["cell"]))
		var far: Array = []
		for pl: Dictionary in reeds:
			var q := Vector2(pl["pos"].x, pl["pos"].z)
			if not VegetationLayer.near_dry(h, q, VegetationLayer.POND_REACH + 0.01):
				far.append(q)
		var hit: Array[bool] = []
		var total: float = 0.0
		var covered: float = 0.0
		for k in ring.size():
			var a: Vector2 = ring[k]
			var b: Vector2 = ring[(k + 1) % ring.size()]
			var m: Vector2 = (a + b) / 2.0
			var on: bool = reeds.any(func(pl: Dictionary) -> bool:
				return m.distance_to(Vector2(pl["pos"].x, pl["pos"].z)) < VegetationLayer.crown_of(pl["node"]) * float(pl["scale"]))
			hit.append(on)
			total += a.distance_to(b)
			covered += a.distance_to(b) if on else 0.0
		var runs: int = 0
		for k in hit.size():
			runs += 1 if hit[k] and not hit[(k + hit.size() - 1) % hit.size()] else 0
		gut.p("%s %s: уріз %.1f, під очеретом %.0f %%, плям %d" % [p, pond[0], total, covered / total * 100.0, runs])
		assert_eq(far, [], "%s: очерет далі 1 м від берега" % p)
		# Ставки Хребта на краю карти: частина урізу за дошкою чи біля дороги, де очерету не буває, —
		# там лише верхня межа.
		assert_between(covered / total, 0.25 if p == "crossroads" else 0.0, 0.4, "%s %s: частка урізу під очеретом" % [p, pond[0]])
		assert_between(runs, 3 if p == "crossroads" else 1, 5, "%s %s: плям очерету" % [p, pond[0]])


## Рослина (дерево чи кущ) — у 60–75 % садиб кожної карти, де садиби є.
func test_most_yards_have_a_plant(p = use_parameters(MAPS)) -> void:
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	if homes.is_empty():
		pass_test("%s: садиб немає" % p)
		return
	var green: int = 0
	for h: Dictionary in homes:
		var cells: Array = h.get("cells", [h["house"]])
		if _view(p).vegetation().placements.any(func(pl: Dictionary) -> bool:
				return pl["group"] == "yard" and cells.has(pl["cell"])):
			green += 1
	gut.p("%s: рослина у %d садибах з %d" % [p, green, homes.size()])
	# На карті з кількома садибами частку округлено до цілих садиб.
	assert_between(green, floori(0.6 * homes.size()), ceili(0.75 * homes.size()), "%s: садиб з рослиною" % p)


## Рослини садиби — лише всередині паркану (клітинки садиби з макета).
func test_yard_plants_stay_inside_the_fence(p = use_parameters(["river", "crossroads"])) -> void:
	var homes: Array = VillageLayout.for_map(StringName(p)).get("homes", [])
	var bad: Array = []
	for pl: Dictionary in _view(p).vegetation().placements:
		if pl["group"] != "yard":
			continue
		if not homes.any(func(h: Dictionary) -> bool: return (h.get("cells", [h["house"]]) as Array).has(pl["cell"])):
			bad.append([pl["node"], pl["cell"]])
	assert_eq(bad, [], "%s: рослина садиби за парканом" % p)


## Жодна крона (кущ двору, лука, берег, узлісся) не нависає над парканом: стовбур далі радіуса крони
## плюс FENCE_CROWN_PAD від кожної секції — з камери крона над секцією читається рослиною крізь паркан.
func test_no_crown_over_a_fence(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(p)
	var fences: Array = VegetationLayer.obstacles(view.props())["fences"]
	var bad: Array = []
	var checked: int = 0
	for pl: Dictionary in view.vegetation().placements:
		if pl["kind"] == "reed":
			continue
		var q := Vector2(pl["pos"].x, pl["pos"].z)
		var need: float = VegetationLayer.crown_of(pl["node"]) + VegetationLayer.FENCE_CROWN_PAD
		checked += 1
		for r: Rect2 in fences:
			if VegetationLayer._rect_dist(r, q) < need - 0.001:
				bad.append([pl["group"], pl["node"], q, snappedf(VegetationLayer._rect_dist(r, q), 0.01)])
				break
	for e: Dictionary in view.forest().board_plan:
		var q: Vector2 = e["pos"]
		checked += 1
		for r: Rect2 in fences:
			if VegetationLayer._rect_dist(r, q) < float(e["r"]) + VegetationLayer.FENCE_CROWN_PAD - 0.001:
				bad.append(["forest", e["node"], q, snappedf(VegetationLayer._rect_dist(r, q), 0.01)])
				break
	assert_eq(bad, [], "%s: крона над парканом" % p)
	assert_gt(checked, 0, "%s: передумова — рослини є" % p)


## На луках кожної карти є хоча б одне дерево (груша, дуб, верба).
func test_meadows_have_a_tree(p = use_parameters(MAPS)) -> void:
	var trees: int = 0
	for pl: Dictionary in _view(p).vegetation().placements:
		trees += 1 if pl["group"] == "meadow" and pl["kind"] == "tree" else 0
	assert_gt(trees, 0, "%s: на луках немає дерев" % p)


## Ліс має свій шар: рослина не стоїть на клітинці FOREST поверх нього.
func test_no_plant_on_forest_cells(p = use_parameters(MAPS)) -> void:
	var board: Board = _board(p)
	var bad: Array = []
	for pl: Dictionary in _view(p).vegetation().placements:
		var c := Vector2i(roundi(pl["pos"].x), roundi(pl["pos"].z))
		if board.in_bounds(c) and board.kind_at(c) == Terrain.Kind.FOREST:
			bad.append([pl["node"], c])
	assert_eq(bad, [], "%s: рослина на клітинці лісу" % p)


## Юніт під деревом поруч із лісом: розчиняються і рослина, і ліс — обидва шари з одного set_reveal_cells.
func test_unit_reveal_fades_plants_and_forest_together() -> void:
	var view: BoardView = _view("river")
	var board: Board = _board("river")
	var cell := Vector2i(-1, -1)
	for pl: Dictionary in view.vegetation().placements:
		var c := Vector2i(roundi(pl["pos"].x), roundi(pl["pos"].z))
		if pl["kind"] == "tree" and VegetationLayer._near_kind(board, c, 1, [Terrain.Kind.FOREST]):
			cell = c
			break
	if cell.x < 0:
		pass_test("на Річці немає дерева біля лісу")
		return
	var forest_cell := Vector2i(-1, -1)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if board.in_bounds(cell + Vector2i(dx, dy)) and board.kind_at(cell + Vector2i(dx, dy)) == Terrain.Kind.FOREST:
				forest_cell = cell + Vector2i(dx, dy)
	gut.p("дерево %s, ліс %s" % [cell, forest_cell])
	var cells: Array[Vector2i] = [cell, forest_cell]
	view.set_reveal_cells(cells, true)
	var veg_faded: bool = view.vegetation().get_children().any(func(n: Node) -> bool: return String(n.name).ends_with("_faded"))
	var forest_faded: bool = view.forest().get_children().any(func(n: Node) -> bool: return String(n.name).begins_with("Fade_"))
	var empty: Array[Vector2i] = []
	view.set_reveal_cells(empty, true)
	assert_true(veg_faded, "рослина над юнітом розчинена")
	assert_true(forest_faded, "ліс над юнітом розчинений")


## Крона (з розкидом масштабу й запасом 0,15) не росте під дротами ЛЕП, стовбур — не ближче 0,3 до опори
## (траси й опори — з PropLayer).
func test_no_crown_under_power_lines(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(p)
	var obst: Dictionary = VegetationLayer.obstacles(view.props())
	assert_gt((obst["wires"] as Array).size(), 0, "%s: дротів немає" % p)
	var bad: Array = []
	for pl: Dictionary in view.vegetation().placements:
		if pl["kind"] == "reed":
			continue
		var q := Vector2(pl["pos"].x, pl["pos"].z)
		if VegetationLayer._power_dist(obst, q) < maxf(VegetationLayer.crown_of(pl["node"]) * 1.1 + 0.15, 0.3) - 0.001:
			bad.append([pl["node"], q])
	assert_eq(bad, [], "%s: крона під ЛЕП" % p)


## Бюджет кадру (§8): рослини — по мешу на атлас бібліотеки (берег, луки, двори), а не MultiMesh на
## вузол: у кожної моделі ще й поверхня плями затінення, тож це подвоєні виклики. Тінь сонця
## рослини не кидають: вона — пляма на землі.
func test_plants_are_one_mesh_per_atlas(p = use_parameters(MAPS)) -> void:
	var veg: VegetationLayer = _view(p).vegetation()
	var drawn: Array[Node] = veg.get_children().filter(func(n: Node) -> bool: return not String(n.name).ends_with("_faded"))
	assert_between(drawn.size(), 1, 3, "%s: по мешу на атлас" % p)
	for n: Node in drawn:
		assert_true(n is MeshInstance3D, "%s: %s — не MultiMesh" % [p, n.name])
		assert_eq((n as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: %s кидає тінь" % [p, n.name])
		assert_lte((n as MeshInstance3D).mesh.get_surface_count(), 2, "рослина й пляма")
	var shown: int = 0
	for i in veg.placements.size():
		shown += 1 if veg.plant_visible(i) else 0
	assert_eq(shown, veg.placements.size(), "%s: усі рослини в мешах і цілі" % p)


## Розчинення працює і зі злитим мешем: рослина над юнітом гасне в таблиці батча (її малює
## напівпрозорий двійник `_faded`), а коли юніт іде — вертається.
func test_fade_hides_the_plant_inside_the_merged_mesh() -> void:
	var veg: VegetationLayer = _view("river").vegetation()
	var idx: int = -1
	for i in veg.placements.size():
		if veg.placements[i]["kind"] == "tree":
			idx = i
			break
	assert_gt(idx, -1, "на Річці є дерево")
	veg.set_reveal_cells([veg.placements[idx]["cell"]])
	assert_false(veg.plant_visible(idx), "у злитому мейші дерево над юнітом зникло")
	assert_true(veg.get_children().any(func(n: Node) -> bool: return String(n.name).ends_with("_faded")), "а замість нього — напівпрозоре")
	veg.set_reveal_cells([])
	assert_true(veg.plant_visible(idx), "юніт пішов — дерево знову ціле")



## Крона не накриває паркан чи ворота на екрані: у плані стовбур далі радіуса крони, але камера дивиться під кутом,
## і крона на висоті над стовбуром лягає на паркан за ним. Диск крони (центр на VegetationLayer.CROWN_H_K радіусів над ґрунтом)
## не ближче за радіус до силуету секції чи воріт на екрані.
func test_no_crown_over_a_fence_on_screen(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(p)
	var props: PropLayer = view.props()
	var obst: Dictionary = VegetationLayer.obstacles(props)
	var hulls: Array = obst["fence_hulls"]
	var bad: Array = []
	var checked: int = 0
	for pl: Dictionary in view.vegetation().placements:
		if pl["kind"] == "reed":
			continue
		var q := Vector2(pl["pos"].x, pl["pos"].z)
		var crown: float = VegetationLayer.crown_of(pl["node"])
		checked += 1
		var gap: float = PropLayer.hull_gap(q, VegetationLayer.CROWN_H_K * crown * VegetationLayer.SCALE_MAX, hulls)
		# Кущ і туя двору — тіло від землі (так колона туї на паркані не лишалась непоміченою, бо диск крони далеко вгорі).
		if pl["group"] == "yard" and pl["kind"] == "bush":
			gap = VegetationLayer.fence_screen_gap(obst, q, crown, true)
		var pad: float = VegetationLayer.YARD_BUSH_FENCE_PAD if pl["group"] == "yard" and pl["kind"] == "bush" else 0.0
		if gap < crown * VegetationLayer.SCALE_MAX + pad - 0.001:
			bad.append([pl["group"], pl["node"], q, snappedf(gap, 0.01)])
	assert_eq(bad, [], "%s: крона над парканом чи воротами на екрані" % p)
	assert_gt(checked, 0, "%s: передумова — рослини є" % p)


## Рослина двору не росте на грядках: стовбур поза ділянкою городу, а диск крони на екрані (центр на CROWN_H_K радіусів
## над стовбуром) нависає над ділянкою не глибше за 1 - PLOT_GAP_SHARE радіуса — інакше з камери дерево стоїть
## посеред рядів, хоч у плані стовбур і збоку.
func test_yard_plants_stay_off_garden_plots(p = use_parameters(MAPS)) -> void:
	var view: BoardView = _view(p)
	var plots: Array[Rect2] = []
	var hulls: Array = []
	for t: Transform3D in view.props().garden_beds():
		var box: AABB = t * AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 0.1, 1))
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		plots.append(r)
		var pts := PackedVector2Array()
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			pts.append(PropLayer.screen_pt(c, 0.0))
		hulls.append(Geometry2D.convex_hull(pts))
	assert_gt(plots.size(), 0, "%s: передумова — городи є" % p)
	var bad: Array = []
	var checked: int = 0
	for pl: Dictionary in view.vegetation().placements:
		if pl["group"] != "yard":
			continue
		checked += 1
		var q := Vector2(pl["pos"].x, pl["pos"].z)
		var crown: float = VegetationLayer.crown_of(pl["node"])
		var gap: float = PropLayer.hull_gap(q, VegetationLayer.CROWN_H_K * crown * VegetationLayer.SCALE_MAX, hulls)
		for r: Rect2 in plots:
			if r.has_point(q) or gap < VegetationLayer.PLOT_GAP_SHARE * crown * VegetationLayer.SCALE_MAX - 0.001:
				bad.append([pl["node"], q, snappedf(gap, 0.01)])
				break
	assert_eq(bad, [], "%s: рослина двору на грядках" % p)
	assert_gt(checked, 0, "%s: передумова — рослини двору є" % p)


## Пляма затінення очерету: на сонячній карті вона — його тінь (cast), на похмурій лише темнить воду; решта рослин — завжди.
func test_reed_shade_only_on_sunny_maps() -> void:
	assert_true(VegetationLayer.has_shade(&"bank_reed_01", true))
	assert_true(VegetationLayer.has_shade(&"bank_cattail_02", true))
	assert_false(VegetationLayer.has_shade(&"bank_reed_01", false))
	assert_false(VegetationLayer.has_shade(&"bank_cattail_02", false))
	assert_true(VegetationLayer.has_shade(&"bank_bush_01", false))


func test_reed_mask_dark_under_reeds_only() -> void:
	var view: BoardView = _view("river")
	var board: Board = _board("river")
	var img: Image = VegetationLayer.reed_mask(view.vegetation().placements, Vector2i(board.width, board.height))
	var px: int = VegetationLayer.REED_MASK_PX
	assert_eq(img.get_size(), Vector2i(board.width, board.height) * px)
	var reeds: int = 0
	for pl: Dictionary in view.vegetation().placements:
		var at := Vector2i(floori((pl["pos"].x + 0.5) * px), floori((pl["pos"].z + 0.5) * px))
		if pl["kind"] == "reed":
			reeds += 1
			assert_gt(img.get_pixelv(at).r, 0.5, "під куртиною %s маска світла" % pl["node"])
		elif pl["kind"] == "tree":
			# Дерево на суші далі від води, ніж розмах куртини.
			assert_eq(img.get_pixelv(at).r, 0.0, "під деревом %s маски нема" % pl["node"])
	assert_gt(reeds, 0)
	var mat := (view.get("_water") as WaterSurface).material_override as ShaderMaterial
	assert_true(mat.get_shader_parameter("use_reeds"), "вода бере маску очерету")
