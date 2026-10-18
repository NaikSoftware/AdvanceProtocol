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

	assert_true(MatchSetup.map_supports(m, 2), path)

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

	for players in [2]:
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


func test_exactly_the_three_new_maps() -> void:
	assert_eq(_map_paths(), ["res://maps/crossroads.tres", "res://maps/ridge.tres", "res://maps/river.tres"])


## Симетрія на 180° — гарантія чесності: кожен гравець має дзеркально ту саму позицію.
func test_map_is_180_degree_symmetric(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	var odd: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			if m.tiles[y * m.width + x] != m.tiles[(m.height - 1 - y) * m.width + (m.width - 1 - x)]:
				odd.append(Vector2i(x, y))
	assert_eq(odd.size(), 0, "%s: тайли без дзеркальної пари %s" % [path, odd.slice(0, 8)])
	var by_owner: Dictionary = {0: 0, 1: 0}
	for s: Dictionary in m.spawns:
		by_owner[int(s["owner"])] = by_owner.get(int(s["owner"]), 0) + 1
		if int(s["owner"]) != 0:
			continue
		var pos: Vector2i = s["pos"]
		var twin := {"type_id": int(s["type_id"]), "owner": 1,
			"pos": Vector2i(m.width - 1 - pos.x, m.height - 1 - pos.y), "facing": (int(s["facing"]) + 4) % 8}
		assert_true(m.spawns.has(twin), "%s: спавн %s без дзеркального двійника" % [path, s])
	assert_eq(by_owner[0], by_owner[1], path)


func test_map_has_the_six_unit_set_per_side(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	var ids: Dictionary = {}
	for s: Dictionary in m.spawns:
		var o: int = int(s["owner"])
		if not ids.has(o):
			ids[o] = []
		ids[o].append(int(s["type_id"]))
	var owners: Array = ids.keys()
	owners.sort()
	assert_eq(owners, [0, 1], path)
	for o in ids:
		ids[o].sort()
		assert_eq(ids[o], [0, 1, 2, 5, 9, 11], "%s: гравець %d" % [path, o])


## Ціна найдешевшого шляху (4 напрямки) за справжньою формулою входу. Тайл,
## дорожчий за повний запас AP, юніт не здатен увійти ніколи — він для нього стіна.
func _path_cost(unit: Unit, board: Board, from: Vector2i, to: Vector2i) -> int:
	var dist: Dictionary = {from: 0}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var best: int = 0
		for i in frontier.size():
			if dist[frontier[i]] < dist[frontier[best]]:
				best = i
		var cur: Vector2i = frontier[best]
		frontier.remove_at(best)
		if cur == to:
			return dist[cur]
		for n in board.neighbours4(cur):
			var c: int = Rules.entry_cost_at(unit, board, n)
			if c > unit.max_ap():
				continue
			if not dist.has(n) or dist[cur] + c < dist[n]:
				if not dist.has(n):
					frontier.append(n)
				dist[n] = dist[cur] + c
	return Terrain.IMPASSABLE


## Темп — головна обіцянка нових карт: розвідка сходиться на 2–3 хід, основні сили на 3–4.
## Міряємо від бази до бази під власним станом ґрунту карти, щоб правка тайлів не розбалансувала її тихо.
func test_map_pace(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	var board: Board = m.to_board()
	var bounds: Dictionary = {2: [4.0, 6.0], 5: [6.0, 8.0]}
	for type_id: int in bounds:
		var ends: Dictionary = {}
		for s: Dictionary in m.spawns:
			if int(s["type_id"]) == type_id:
				ends[int(s["owner"])] = s["pos"]
		assert_eq(ends.size(), 2, "%s: тип %d" % [path, type_id])
		if ends.size() != 2:
			continue
		var u := Unit.create(0, type_id, 0, ends[0], 0)
		var cost: int = _path_cost(u, board, ends[0], ends[1])
		assert_lt(cost, Terrain.IMPASSABLE, "%s: тип %d не доїде до ворожої бази" % [path, type_id])
		var turns: float = float(cost) / u.max_ap()
		assert_between(turns, bounds[type_id][0], bounds[type_id][1], "%s: тип %d — %.2f ходу" % [path, type_id, turns])


func test_river_has_three_crossings_and_a_town() -> void:
	var m: MapData = load("res://maps/river.tres") as MapData
	assert_not_null(m)
	if m == null:
		return
	assert_gte(_count(m, [Terrain.Kind.BRIDGE]), 6, "три переправи по два ряди мосту")
	assert_gte(_count(m, [Terrain.Kind.BUILDING]), 8, "містечко")


func test_crossroads_town_block_and_ridge_forest() -> void:
	var c: MapData = load("res://maps/crossroads.tres") as MapData
	var r: MapData = load("res://maps/ridge.tres") as MapData
	assert_not_null(c)
	assert_not_null(r)
	if c == null or r == null:
		return
	assert_gte(_count(c, [Terrain.Kind.BUILDING]), 20, "crossroads: суцільний квартал")
	assert_gte(_count(r, [Terrain.Kind.FOREST, Terrain.Kind.HILL]), 60, "ridge: лісистий хребет")
