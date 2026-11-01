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


func test_neighbouring_sheds_differ(p = use_parameters(MAPS)) -> void:
	var is_shed := func(i: Dictionary) -> bool: return i.get("yard", false) and _kind(i) == PropLayer.Kind.STRUCTURE
	assert_eq(_twins(_props(p), is_shed, SMALL_GAP), [], "%s: однакові повітки поруч" % p)


func test_neighbouring_trailers_differ(p = use_parameters(MAPS)) -> void:
	var is_trailer := func(i: Dictionary) -> bool: return _kind(i) == PropLayer.Kind.TRAILER
	assert_eq(_twins(_props(p), is_trailer, SMALL_GAP), [], "%s: однакові причепи поруч" % p)


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
