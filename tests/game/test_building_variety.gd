extends GutTest
## Різноманітність сільської забудови: сусідні хати, повітки й причепи різні; тюки лише біля краю поля.

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
## Хати ближче за стільки клітинок (Чебишов) не повторюють модель.
const HOUSE_GAP: int = PropLayer.HOUSE_APART
## Повітки й причепи ближче за стільки клітинок не повторюють модель.
const SMALL_GAP: int = 3
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


func _centre(inst: Dictionary) -> Vector2i:
	var o: Vector3 = (inst["transform"] as Transform3D).origin
	return Vector2i(roundi(o.x), roundi(o.z))


## Пари екземплярів відібраного виду, що стоять ближче gap і мають одну модель.
func _twins(props: PropLayer, pick: Callable, gap: int) -> Array:
	var items: Array = []
	for inst in props.all_instances():
		if pick.call(inst):
			items.append([inst["model"], _centre(inst)])
	var out: Array = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			var d: Vector2i = (items[i][1] as Vector2i) - (items[j][1] as Vector2i)
			if items[i][0] == items[j][0] and maxi(absi(d.x), absi(d.y)) <= gap:
				out.append([items[i][0], items[i][1], items[j][1]])
	return out


func _is_house(inst: Dictionary) -> bool:
	return String(inst["model"]).begins_with("house_") and not inst.get("yard", false)


func _kind(inst: Dictionary) -> int:
	return int(PropLayer.spec_of(inst["model"]).get("kind", -1))


func test_neighbouring_houses_differ(p = use_parameters(MAPS)) -> void:
	assert_eq(_twins(_props(p), _is_house, HOUSE_GAP), [], "%s: однакові хати поруч" % p)


## Дві хати ближче ROOF_APART клітинок мають різний колір даху (різні моделі теж: двоповерхові з зеленим дахом читаються одним).
func test_neighbouring_houses_have_different_roofs(p = use_parameters(MAPS)) -> void:
	var houses: Array = []
	for inst in _props(p).all_instances():
		if _is_house(inst):
			houses.append([_centre(inst), PropLayer.roof_of(inst), inst["model"]])
	assert_gt(houses.size(), 3, "%s: передумова" % p)
	for i in houses.size():
		assert_gte(houses[i][1], 0, "%s: хата без кольору даху" % p)
		for j in range(i + 1, houses.size()):
			var d: Vector2i = (houses[i][0] as Vector2i) - (houses[j][0] as Vector2i)
			if maxi(absi(d.x), absi(d.y)) <= PropLayer.ROOF_APART:
				assert_ne(houses[i][1], houses[j][1], "%s: %s і %s з однаковим дахом поруч" % [p, houses[i], houses[j]])


## Палітра дахів — лише сільські кольори: не оливкові й не вохристі, усі помітно темні.
func test_roof_palette_is_rural_and_dark() -> void:
	assert_gte(PropLayer.ROOF_PALETTE.size(), 5)
	for c: Color in PropLayer.ROOF_PALETTE:
		assert_lte(c.get_luminance(), 0.4, "%s надто світлий" % c)
		var hue_deg: float = c.h * 360.0
		assert_false(hue_deg >= 40.0 and hue_deg <= 100.0 and c.s > 0.3, "%s — олива чи вохра" % c)


## Дах кожної хати не світліший за ROOF_WALL_MAX її стіни (яскравість стіни — за атласом моделі, з найтемнішим відтінком стіни).
func test_roofs_stay_darker_than_the_wall(p = use_parameters(MAPS)) -> void:
	var houses: int = 0
	for inst in _props(p).all_instances():
		if _is_house(inst):
			houses += 1
			var limit: float = PropLayer.wall_luma(inst["model"]) * PropLayer.WALL_TINT_MIN * PropLayer.ROOF_WALL_MAX
			var roof: float = PropLayer.ROOF_PALETTE[PropLayer.roof_of(inst)].get_luminance()
			assert_lte(roof, limit, "%s: дах %s хати %s світліший за %.3f" % [p, PropLayer.ROOF_PALETTE[PropLayer.roof_of(inst)], inst["model"], limit])
	assert_gt(houses, 3, "%s: передумова" % p)


## Кожна модель хати має хоч один колір палітри, що проходить за стіною (темні стіни кільця — лише найтемніший); пари «колір × модель» друкуються.
func test_every_house_model_has_a_roof_that_passes() -> void:
	var models: Array[StringName] = []
	for m: StringName in PropLayer.models_of(PropLayer.Kind.STRUCTURE):
		if String(m).begins_with("house_") and not bool(PropLayer.spec_of(m).get("damaged", false)):
			models.append(m)
	assert_gt(models.size(), 3)
	for m: StringName in models:
		var wall: float = PropLayer.wall_luma(m) * PropLayer.WALL_TINT_MIN * PropLayer.ROOF_WALL_MAX
		var ok: Array = []
		for k in PropLayer.ROOF_PALETTE.size():
			if PropLayer.ROOF_PALETTE[k].get_luminance() <= wall:
				ok.append(k)
		gut.p("%s: стіна %.3f, проходять кольори %s" % [m, PropLayer.wall_luma(m), ok])
		assert_gte(ok.size(), 1, "%s: жоден колір палітри не темніший за стіну %.3f" % [m, wall])


## Руїна не повторює сусідню й не стоїть поруч із цілим двійником.
func test_neighbouring_ruins_differ(p = use_parameters(MAPS)) -> void:
	# Кільце за краєм дошки — фон без правил, тож лише руїни дошки.
	var map: MapData = load("res://maps/%s.tres" % p) as MapData
	var is_ruin := func(i: Dictionary) -> bool:
		var c: Vector2i = _centre(i)
		return _kind(i) == PropLayer.Kind.RUIN and c.x >= 0 and c.y >= 0 and c.x < map.width and c.y < map.height
	assert_eq(_twins(_props(p), is_ruin, PropLayer.RUIN_APART), [], "%s: однакові руїни поруч" % p)
	var ruins: Array = []
	var houses: Array = []
	for inst in _props(p).all_instances():
		if is_ruin.call(inst):
			ruins.append([inst["model"], _centre(inst)])
		elif _is_house(inst):
			houses.append([inst["model"], _centre(inst)])
	for r: Array in ruins:
		for h: Array in houses:
			var d: Vector2i = (r[1] as Vector2i) - (h[1] as Vector2i)
			if PropLayer.RUIN_TWIN.get(r[0], &"") == h[0]:
				assert_gt(maxi(absi(d.x), absi(d.y)), PropLayer.RUIN_TWIN_NEAR, "%s: %s біля цілого двійника %s" % [p, r, h])


func test_neighbouring_sheds_differ(p = use_parameters(MAPS)) -> void:
	var is_shed := func(i: Dictionary) -> bool: return i.get("yard", false) and _kind(i) == PropLayer.Kind.STRUCTURE
	assert_eq(_twins(_props(p), is_shed, SMALL_GAP), [], "%s: однакові повітки поруч" % p)


## Лише знімок розстановки трьох карт (причепів на них зараз нема, тож тест порожній, доки вони з'являться); правило перевіряє синтетична дошка нижче.
func test_pin_trailers_on_the_maps_never_repeat_nearby(p = use_parameters(MAPS)) -> void:
	# Навмисно порожній, поки на картах нема причепів: перевірка живе в синтетичній дошці нижче.
	var is_trailer := func(i: Dictionary) -> bool: return _kind(i) == PropLayer.Kind.TRAILER
	assert_eq(_twins(_props(p), is_trailer, SMALL_GAP), [], "%s: однакові причепи поруч" % p)


## Дошка без макета: ряди дворів по дві клітинки. Повітки й причепи сусідніх дворів різні.
func test_legacy_yards_alternate_sheds_and_trailers() -> void:
	var board := Board.create(40, 12, Terrain.GroundState.DRY)
	for row in [3, 8]:
		for k in 10:
			board.set_kind(Vector2i(2 + k * 3, row), Terrain.Kind.BUILDING)
			board.set_kind(Vector2i(3 + k * 3, row), Terrain.Kind.BUILDING)
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.build(board)
	var is_shed := func(i: Dictionary) -> bool: return i.get("yard", false) and _kind(i) == PropLayer.Kind.STRUCTURE
	var is_trailer := func(i: Dictionary) -> bool: return _kind(i) == PropLayer.Kind.TRAILER
	var sheds: int = 0
	for inst in view.props().all_instances():
		sheds += 1 if is_shed.call(inst) else 0
	assert_gte(sheds, 3, "передумова: повітки на дошці")
	assert_eq(_twins(view.props(), is_shed, 3), [], "однакові повітки поруч")
	assert_eq(_twins(view.props(), is_trailer, 3), [], "однакові причепи поруч")


## Є з чого вибирати: більше однієї повітки й більше двох причепів у таблиці.
func test_more_than_one_shed_and_trailer_model() -> void:
	assert_gt(PropLayer.YARD_SHEDS.size(), 1)
	assert_gt(PropLayer.models_of(PropLayer.Kind.TRAILER).size(), 2)


## Без поля поруч тюків нема ніде: ні на лузі, ні в дворі.
func test_no_hay_without_a_field() -> void:
	var board := Board.create(24, 24, Terrain.GroundState.DRY)
	for c: Vector2i in [Vector2i(3, 3), Vector2i(10, 10), Vector2i(17, 5)]:
		board.set_kind(c, Terrain.Kind.BUILDING)
	var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.build(board)
	var bales: int = 0
	for inst in view.props().all_instances():
		bales += 1 if _kind(inst) == PropLayer.Kind.HAY else 0
	assert_eq(bales, 0, "тюки без поля")


## Двірська повітка не заходить на огорожу: від її обрису (зі звісом) до секції паркану лишається щілина.
func test_yard_sheds_keep_off_the_fence(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var segs: Array = []
	for inst in props.all_instances():
		if _kind(inst) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var xf: Transform3D = inst["transform"]
		var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
		var a: Vector3 = xf * Vector3(box.position.x, 0.0, 0.0)
		var b: Vector3 = xf * Vector3(box.end.x, 0.0, 0.0)
		segs.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
	var sheds: int = 0
	for inst in props.all_instances():
		if not (inst.get("yard", false) and _kind(inst) == PropLayer.Kind.STRUCTURE):
			continue
		sheds += 1
		var bx: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r := Rect2(bx.position.x, bx.position.z, bx.size.x, bx.size.z)
		for sg: Array in segs:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var hit: bool = r.has_point(a) or r.has_point(b)
			for k in 11:
				hit = hit or r.has_point(a.lerp(b, k / 10.0))
			assert_false(hit, "%s: %s на огорожі %s" % [p, inst["model"], sg])
	assert_gt(sheds, 0, "%s: передумова" % p)
