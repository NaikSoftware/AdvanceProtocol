extends GutTest
## Task 4.12: структурна перевірка кожної карти з maps/. Карта — контент, не код,
## тож помилку в ній (спавн у воді, недосяжний ворог, ціль поза дошкою) ловить
## лише цей тест, а не компілятор.

const MatchServiceScript := preload("res://game/autoload/match_service.gd")
const MAPS_DIR: String = "res://maps"
## Найдальший постріл ростеру — артилерія й дрон штурмового відділення, обидва 5.
const MAX_REACH: int = 5
const LOCALES: Array[String] = ["uk", "en"]


static func _map_paths() -> Array:
	var out: Array = []
	for file in DirAccess.get_files_at(MAPS_DIR):
		var f: String = file.trim_suffix(".remap")
		if f.ends_with(".tres"):
			out.append("%s/%s" % [MAPS_DIR, f])
	out.sort()
	return out


func _count(m: MapData, kinds: Array) -> int:
	var n: int = 0
	for k in m.tiles:
		if kinds.has(k):
			n += 1
	return n


func _passable(board: Board, p: Vector2i) -> bool:
	return board.in_bounds(p) and board.penalty_at(p) < Terrain.IMPASSABLE


## Множина тайлів, досяжних від start по прохідній місцевості (4 напрямки, §3.1).
func _reachable(board: Board, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var q: Vector2i = p + d
			if not seen.has(q) and _passable(board, q):
				seen[q] = true
				queue.append(q)
	return seen


func test_map_is_well_formed(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	assert_not_null(m, path)
	if m == null:
		return
	assert_eq(m.tiles.size(), m.width * m.height, path)
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		assert_ne(tr(m.name_key), m.name_key, "%s: немає перекладу %s (%s)" % [path, m.name_key, locale])
	TranslationServer.set_locale("en")

	var board: Board = m.to_board()
	var taken: Dictionary = {}
	var first_of: Dictionary = {}
	for s: Dictionary in m.spawns:
		var pos: Vector2i = s["pos"]
		var f: int = int(s["facing"])
		assert_true(f >= 0 and f <= 7, "%s: facing %d у %s" % [path, f, pos])
		assert_false(taken.has(pos), "%s: два спавни на %s" % [path, pos])
		taken[pos] = true
		var u := Unit.create(0, int(s["type_id"]), int(s["owner"]), pos, f)
		assert_true(board.in_bounds(pos) and Rules.entry_cost_at(u, board, pos) < Terrain.IMPASSABLE,
			"%s: спавн %s на непрохідному тайлі" % [path, pos])
		if not first_of.has(u.owner):
			first_of[u.owner] = pos
	# Ніхто не стартує під чужим пострілом: інакше перший хід вирішує розстановка.
	for a: Dictionary in m.spawns:
		for b: Dictionary in m.spawns:
			if int(a["owner"]) < int(b["owner"]):
				var d: Vector2i = (b["pos"] as Vector2i) - (a["pos"] as Vector2i)
				assert_gt(d.x * d.x + d.y * d.y, MAX_REACH * MAX_REACH,
					"%s: %s і %s стартують на дистанції пострілу" % [path, a["pos"], b["pos"]])

	assert_lte(m.objectives.size(), 15, path)
	for o: Vector2i in m.objectives:
		assert_true(_passable(board, o), "%s: ціль %s поза дошкою чи на непрохідному" % [path, o])
	assert_between(m.hold_target, 0, m.objectives.size(), path)

	assert_true(MatchSetup.map_supports(m, 2), path)
	assert_true(MatchSetup.map_supports(m, 3), path)

	for owner in first_of:
		var reach: Dictionary = _reachable(board, first_of[owner])
		for other: Dictionary in m.spawns:
			if int(other["owner"]) == owner:
				continue
			var near: bool = false
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if reach.has((other["pos"] as Vector2i) + d):
					near = true
			assert_true(near, "%s: від %s не дістатися до %s" % [path, first_of[owner], other["pos"]])

	for players in [2, 3]:
		var svc: Node = MatchServiceScript.new()
		add_child_autofree(svc)
		svc.start_match(m.to_board(), players, 1)
		assert_true(m.populate(svc.state), path)
		svc.begin()
		for pl in players:
			var units: Array[Unit] = svc.state.units_of(pl)
			assert_false(units.is_empty(), "%s: у гравця %d немає юнітів (%d гравців)" % [path, pl, players])
			var classes: Dictionary = {}
			for u in units:
				classes[UnitTypes.get_type(u.type_id)["unit_class"]] = true
			assert_true(classes.has(UnitTypes.UnitClass.ENGINEER), "%s: гравець %d без інженера" % [path, pl])
			assert_true(classes.has(UnitTypes.UnitClass.ARTILLERY), "%s: гравець %d без артилерії" % [path, pl])
		assert_eq(svc.state.units_of(players).size(), 0, "%s: зайвий гравець не має юнітів" % path)


func test_five_maps_with_required_kinds() -> void:
	var paths: Array = _map_paths()
	assert_eq(paths.size(), 5, str(paths))
	var by_name: Dictionary = {}
	for path: String in paths:
		by_name[path.get_file().get_basename()] = load(path) as MapData
	for name in ["skirmish_bridge", "urban", "open", "forest", "mountain"]:
		assert_true(by_name.has(name), "немає карти %s" % name)
	if by_name.size() != 5 or not by_name.has("skirmish_bridge") or not by_name.has("urban") \
			or not by_name.has("open") or not by_name.has("forest") or not by_name.has("mountain"):
		return
	var K := Terrain.Kind
	assert_gt(_count(by_name["skirmish_bridge"], [K.BRIDGE]), 0, "bridge: є міст")
	assert_gt(_count(by_name["urban"], [K.BUILDING]), 0, "urban: є забудова")
	var forest: MapData = by_name["forest"]
	assert_gte(_count(forest, [K.FOREST]) * 4, forest.tiles.size(), "forest: ліс >= 25 %")
	var mountain: MapData = by_name["mountain"]
	assert_gte(_count(mountain, [K.HILL]) * 4, mountain.tiles.size(), "mountain: пагорби >= 25 %")
	var open: MapData = by_name["open"]
	assert_gte(_count(open, [K.FIELD, K.ROAD]) * 5, open.tiles.size() * 4, "open: поле/дорога >= 80 %")
	assert_eq(open.hold_target, 0, "open: без умови за цілі")
