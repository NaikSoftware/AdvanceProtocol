extends GutTest
## Task 4.12: структурна перевірка кожної карти з maps/. Карта — контент, не код,
## тож помилку в ній (спавн у воді, недосяжний ворог, ціль поза дошкою) ловить
## лише цей тест, а не компілятор.

const MatchServiceScript := preload("res://game/autoload/match_service.gd")
const MAPS_DIR: String = "res://maps"
## Найдальший постріл ростеру — артилерія й дрон штурмового відділення, обидва 5.
const MAX_REACH: int = 5
const LOCALES: Array[String] = ["uk", "en"]
## Карти з симетрією на 180°. Решту рівняє не форма, а test_map_sides_are_balanced.
const SYMMETRIC_MAPS: Array[String] = ["res://maps/crossroads.tres", "res://maps/ridge.tres"]
const PACE_TOL: float = 0.05
const COUNT_TOL: float = 0.15


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
func test_map_is_180_degree_symmetric(p = use_parameters(SYMMETRIC_MAPS)) -> void:
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
func _path_cost(unit: Unit, board: Board, from: Vector2i, to: Array[Vector2i]) -> int:
	var dist: Dictionary = {from: 0}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var best: int = 0
		for i in frontier.size():
			if dist[frontier[i]] < dist[frontier[best]]:
				best = i
		var cur: Vector2i = frontier[best]
		frontier.remove_at(best)
		if to.has(cur):
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
## Міряємо під власним станом ґрунту карти: від бази до бази — межі темпу, від бази до середини —
## рівність сторін, щоб правка тайлів не розбалансувала карту тихо.
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
		var mid: Array[Vector2i] = _middle(board, ends[0], ends[1])
		var to_mid: Array[float] = []
		for o in 2:
			var u := Unit.create(0, type_id, o, ends[o], 0)
			var cost: int = _path_cost(u, board, ends[o], [ends[1 - o]] as Array[Vector2i])
			assert_lt(cost, Terrain.IMPASSABLE, "%s: тип %d гравця %d не доїде до ворожої бази" % [path, type_id, o])
			var turns: float = float(cost) / u.max_ap()
			assert_between(turns, bounds[type_id][0], bounds[type_id][1],
				"%s: тип %d гравця %d — %.2f ходу" % [path, type_id, o, turns])
			to_mid.append(float(_path_cost(u, board, ends[o], mid)) / u.max_ap())
		# Шлях від бази до бази однаковий для обох гравців з точністю до ціни входу на самі бази,
		# тож рівність сторін міряє темп кожного від своєї бази до середини дошки.
		assert_almost_eq(to_mid[0], to_mid[1], PACE_TOL * maxf(to_mid[0], to_mid[1]),
			"%s: тип %d — до середини %.2f і %.2f ходу" % [path, type_id, to_mid[0], to_mid[1]])


## Середні ряди (або стовпці) дошки між базами: нейтральна смуга, до якої біжать обидва.
func _middle(board: Board, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var rows: bool = absi(a.y - b.y) >= absi(a.x - b.x)
	var n: int = board.height if rows else board.width
	var out: Array[Vector2i] = []
	for k in range((n - 1) / 2, n / 2 + 1):
		for i in (board.width if rows else board.height):
			out.append(Vector2i(i, k) if rows else Vector2i(k, i))
	return out


## Одна 4-зв'язна група клітинок мосту — одна переправа.
func _bridges(board: Board) -> Array[Array]:
	var deck: Array = [Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	var out: Array[Array] = []
	var seen: Dictionary = {}
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if seen.has(c) or not deck.has(board.kind_at(c)):
				continue
			var group: Array[Vector2i] = []
			var queue: Array[Vector2i] = [c]
			seen[c] = true
			while not queue.is_empty():
				var q: Vector2i = queue.pop_back()
				group.append(q)
				for n in board.neighbours4(q):
					if not seen.has(n) and deck.has(board.kind_at(n)):
						seen[n] = true
						queue.append(n)
			out.append(group)
	return out


## Міст без дороги з одного берега нікуди не веде. Вісь переправи не записана в карті,
## тож годиться будь-яка вісь, де за обома торцями групи є ROAD.
func test_every_bridge_has_road_on_both_banks(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var board: Board = (load(path) as MapData).to_board()
	for group: Array[Vector2i] in _bridges(board):
		var ok: bool = false
		for axis: Vector2i in [Vector2i(0, 1), Vector2i(1, 0)]:
			var road_ahead: bool = false
			var road_behind: bool = false
			for c in group:
				var ahead: Vector2i = c + axis
				var behind: Vector2i = c - axis
				road_ahead = road_ahead or (board.in_bounds(ahead) and board.kind_at(ahead) == Terrain.Kind.ROAD)
				road_behind = road_behind or (board.in_bounds(behind) and board.kind_at(behind) == Terrain.Kind.ROAD)
			ok = ok or (road_ahead and road_behind)
		assert_true(ok, "%s: міст %s має дорогу лише з одного берега" % [path, group])


func _side_counts(m: MapData, kinds: Array, top: bool) -> int:
	var n: int = 0
	var rows: Array = range(0, m.height / 2) if top else range(m.height - m.height / 2, m.height)
	for y: int in rows:
		for x in m.width:
			if kinds.has(m.tiles[y * m.width + x]):
				n += 1
	return n


## Несиметрична карта чесна, лише якщо в гравців порівнянні переправи за темпом, а на половинах —
## порівнянна кількість повільних і закритих для техніки клітинок.
func test_map_sides_are_balanced(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	var board: Board = m.to_board()
	var bridges: Array[Array] = _bridges(board)
	for type_id: int in [2, 5]:
		var per_owner: Array = []
		for s: Dictionary in m.spawns:
			if int(s["type_id"]) != type_id:
				continue
			var u := Unit.create(0, type_id, int(s["owner"]), s["pos"], 0)
			var turns: Array[float] = []
			for group: Array[Vector2i] in bridges:
				turns.append(float(_path_cost(u, board, s["pos"], group)) / u.max_ap())
			turns.sort()
			per_owner.append(turns)
		assert_eq(per_owner.size(), 2, "%s: тип %d" % [path, type_id])
		if per_owner.size() != 2:
			continue
		for i in bridges.size():
			assert_almost_eq(per_owner[0][i], per_owner[1][i], PACE_TOL * per_owner[0][i],
				"%s: тип %d, %d-а за близькістю переправа — %.2f і %.2f ходу" % [path, type_id, i + 1,
					per_owner[0][i], per_owner[1][i]])
	var slow: Array = [Terrain.Kind.FOREST, Terrain.Kind.HILL]
	var closed: Array = [Terrain.Kind.WATER, Terrain.Kind.MARSH, Terrain.Kind.BUILDING]
	for kinds: Array in [slow, closed]:
		var top: int = _side_counts(m, kinds, true)
		var bottom: int = _side_counts(m, kinds, false)
		assert_almost_eq(float(top), float(bottom), COUNT_TOL * maxi(top, bottom),
			"%s: клітинок %s згори %d, знизу %d" % [path, kinds, top, bottom])


## Косметичний підтип: правил не торкається, але крива сітка — це крива картинка.
func test_map_surface_is_well_formed(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	assert_not_null(m, path)
	if m == null:
		return
	assert_true(m.surface.is_empty() or m.surface.size() == m.width * m.height,
		"%s: surface %d замість 0 або %d" % [path, m.surface.size(), m.width * m.height])
	if m.surface.size() != m.width * m.height:
		return
	var bad: Array[Vector2i] = []
	var odd: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			var i: int = y * m.width + x
			if m.surface[i] >= MapData.surface_variants(m.tiles[i]):
				bad.append(Vector2i(x, y))
			if SYMMETRIC_MAPS.has(path) and m.surface[i] != m.surface[(m.height - 1 - y) * m.width + (m.width - 1 - x)]:
				odd.append(Vector2i(x, y))
	assert_eq(bad.size(), 0, "%s: підтип поза варіантами виду %s" % [path, bad.slice(0, 8)])
	assert_eq(odd.size(), 0, "%s: підтип без дзеркальної пари %s" % [path, odd.slice(0, 8)])


# --- Зовнішнє кільце (рішення власника 2026-10-22): пейзаж за краєм, правила його не читають ---

## Найбільше віддалення не має показати край світу — 12 клітинок з кожного боку.
const OUTER_MARGIN: int = 12


func test_map_outer_ring_is_well_formed_and_symmetric(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	assert_eq(m.outer_margin, OUTER_MARGIN, path)
	var mg: int = m.outer_margin
	var ow: int = m.width + 2 * mg
	var oh: int = m.height + 2 * mg
	assert_eq(m.outer_tiles.size(), ow * oh, path)
	assert_true(m.outer_surface.is_empty() or m.outer_surface.size() == ow * oh, path)
	if m.outer_tiles.size() != ow * oh:
		return
	var bad: Array[Vector2i] = []
	var odd: Array[Vector2i] = []
	for y in range(-mg, m.height + mg):
		for x in range(-mg, m.width + mg):
			var i: int = (y + mg) * ow + x + mg
			var inside: bool = x >= 0 and x < m.width and y >= 0 and y < m.height
			var k: int = m.outer_tiles[i]
			var s: int = m.outer_surface[i] if not m.outer_surface.is_empty() else 0
			if inside != (k == MapData.OUTER_HOLE) or (not inside and (k >= Terrain.Kind.size()
					or s >= MapData.surface_variants(k))):
				bad.append(Vector2i(x, y))
			var j: int = oh * ow - 1 - i  # дзеркальна клітинка розширеної сітки
			# Симетрію дошки перевіряє test_map_is_180_degree_symmetric, і лише для SYMMETRIC_MAPS.
			if not inside and (m.outer_kind_at(Vector2i(x, y)) != m.outer_kind_at(Vector2i(m.width - 1 - x, m.height - 1 - y))
					or (not m.outer_surface.is_empty() and m.outer_surface[i] != m.outer_surface[j])):
				odd.append(Vector2i(x, y))
	assert_eq(bad.size(), 0, "%s: криві клітинки кільця %s" % [path, bad.slice(0, 8)])
	assert_eq(odd.size(), 0, "%s: кільце без дзеркальної пари %s" % [path, odd.slice(0, 8)])


## Річка й дорога не обриваються на краю дошки: клітинка кільця за краєм продовжує їх.
func test_map_edge_water_and_roads_continue_into_the_ring(p = use_parameters(_map_paths())) -> void:
	var path: String = p
	var m: MapData = load(path) as MapData
	# Без кільця outer_kind_at повертає сам край — перевірка пройшла б порожньо.
	assert_eq(m.outer_margin, OUTER_MARGIN, path)
	var wet: Array = [Terrain.Kind.WATER, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	var paved: Array = [Terrain.Kind.ROAD, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	var broken: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			var k: int = m.tiles[y * m.width + x]
			var need: Array = paved if k == Terrain.Kind.ROAD else (wet if k == Terrain.Kind.WATER else [])
			if need.is_empty():
				continue
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var q := Vector2i(x, y) + d
				var off: bool = q.x < 0 or q.x >= m.width or q.y < 0 or q.y >= m.height
				if off and not need.has(m.outer_kind_at(q)):
					broken.append(Vector2i(x, y))
	assert_eq(broken.size(), 0, "%s: обривається на краю дошки %s" % [path, broken.slice(0, 8)])


func test_river_flows_through_the_ring_to_its_outer_edge_on_both_ends() -> void:
	var m: MapData = load("res://maps/river.tres") as MapData
	assert_eq(m.outer_margin, OUTER_MARGIN, "без кільця перевірка пройшла б порожньо")
	var mg: int = m.outer_margin
	var wet: Array = [Terrain.Kind.WATER, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	# Старт — будь-яка клітинка річки на західному краю дошки: русло петляє, рядок не сталий.
	var start := Vector2i(-1, -1)
	for y in m.height:
		if m.outer_kind_at(Vector2i(0, y)) == Terrain.Kind.WATER:
			start = Vector2i(0, y)
			break
	assert_ne(start, Vector2i(-1, -1), "річка виходить на західний край дошки")
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var west: bool = false
	var east: bool = false
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		west = west or c.x == -mg
		east = east or c.x == m.width - 1 + mg
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var q: Vector2i = c + d
			if q.x < -mg or q.x >= m.width + mg or q.y < -mg or q.y >= m.height + mg:
				continue
			if not seen.has(q) and wet.has(m.outer_kind_at(q)):
				seen[q] = true
				queue.append(q)
	assert_true(west and east, "річка тече крізь кільце до зовнішнього краю з обох боків (захід %s, схід %s)"
		% [west, east])


func test_river_has_three_crossings_and_a_town() -> void:
	var m: MapData = load("res://maps/river.tres") as MapData
	assert_not_null(m)
	if m == null:
		return
	assert_gte(_count(m, [Terrain.Kind.BRIDGE]), 6, "три переправи")
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
