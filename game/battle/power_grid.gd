class_name PowerGrid
extends RefCounted
## Мережа ЛЕП, яку гра будує сама й однаково щоразу (без пошуку й без збережених точок):
## - 10 кВ іде за намірами routes макета вздовж головних доріг (вісь спрощена), стовпи через ≤ MAX_10KV клітинок;
## - у кожного поселення (хати, зв'язані кроком SETTLEMENT_R) — одна ТП на стовпі 10 кВ біля в'їзду; ТП ближче
##   за TP_GAP одна до одної — спільна;
## - 0.4 кВ — один ствол уздовж кожної вулиці села на смузі між асфальтом і хатами (з боку дворів; де вона
##   заставлена — з протилежного боку, крім кільцевої дороги), опори через ≤ MAX_04KV клітинок і на поворотах;
##   мережа — дерево (Прима від ТП) лише по сусідах уздовж вулиці, без перетинів і без зрізів крізь квартали;
## - до кожної цілої хати — один відвід від найближчої опори вулиці (PropLayer drop_ok); коли жодна не дістає,
##   на землі поблизу ставиться ще одна опора, з'єднана коротким прольотом із деревом.
## Розстановка поступається там, де стовпу не місце (pole_spot_ok): місце шукається поряд на межах клітинок, а
## не знайшлось — стовпа нема, і це видно в тесті.
## Результат: lines — ламані з опор (kind, points), transformers — точки підстанцій, unfed — хати без відводу.

const STREET_R: float = 7.0
const SIDE_PROBE: float = 0.8
const VERGE: float = 0.9
const STATION_GAP: float = 4.5
const MAX_04KV: float = 5.0
const MAX_10KV: float = 9.0
const TRUNK_GAP: float = 7.5
const BEND_ANGLE: float = 0.9
const BEND_WINDOW: int = 5
## Найдовший проліт, яким відокремлена частина вулиць сполучається з деревом, клітинки.
const BRIDGE_MAX: float = 5.0
## Дві ТП ближче за стільки клітинок — одна: друге село підключається до наявної.
const TP_GAP: float = 6.0
## Найдовша ланка вздовж вулиці, яку ще добудовують проміжними опорами, клітинки.
const BRIDGE_CHAIN_MAX: float = 12.0
## Допуск спрощення осі дороги для 10 кВ, клітинки, і найкоротший проліт між вершинами траси.
const SIMPLIFY_TOL: float = 1.0
const MIN_VERTEX_GAP: float = 6.0

var _p: PropLayer._Placer
## Опори, ближче за 1.4 до яких нових не ставимо: стовпи магістралі й уже побудованих сіл.
var _avoid: Array[Vector2] = []
var _ring: int = 0
var _size := Vector2i.ZERO
var lines: Array[Dictionary] = []
var transformers: Array[Vector2] = []
## Центри хат, до яких дотягнутись не вдалось (тест їх називає).
var unfed: Array[Vector2] = []


func plan(placer: PropLayer._Placer) -> void:
	_p = placer
	_ring = placer.ring
	_size = placer.size
	var homes: Array[Dictionary] = _powered_homes()
	var trunk: Array = _trunk()
	for line: Array in trunk:
		lines.append({"kind": &"10kv", "points": line})
	for line: Array in trunk:
		_avoid.append_array(line)
	for village: Array in _villages(homes):
		_village(village, trunk)


# --- хати й села ---------------------------------------------------------------------------

func _powered_homes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var centres: Array[Vector2] = []
	var on_board: Array[bool] = []
	var items: Array[Dictionary] = []
	for inst: Dictionary in _p.layer._instances:
		if not PropLayer.is_home(inst):
			continue
		var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		items.append({"rect": r, "centre": r.get_center()})
		centres.append(r.get_center())
		on_board.append(_p.on_board((inst["cells"] as Array)[0]))
	var powered: Array[bool] = PropLayer.powered_homes(centres, on_board)
	for i in items.size():
		if powered[i]:
			out.append(items[i])
	return out


## Села: ланцюги хат із кроком до SETTLEMENT_R, у порядку першої хати (однаково щоразу).
func _villages(homes: Array[Dictionary]) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for i in homes.size():
		if seen.has(i):
			continue
		var group: Array[Dictionary] = []
		var stack: Array[int] = [i]
		seen[i] = true
		while not stack.is_empty():
			var u: int = stack.pop_back()
			group.append(homes[u])
			for j in homes.size():
				if not seen.has(j) and (homes[u]["centre"] as Vector2).distance_to(homes[j]["centre"]) <= PropLayer.SETTLEMENT_R:
					seen[j] = true
					stack.append(j)
		out.append(group)
	return out


# --- місце стовпа --------------------------------------------------------------------------

## Найближче до target придатне місце на межі клітинок (k ± 0.01) у радіусі radius; INF — нема.
func _snap(target: Vector2, radius: float, accept: Callable = Callable()) -> Vector2:
	var cands: Array[Vector2] = []
	var c := Vector2i(roundi(target.x), roundi(target.y))
	var reach: int = ceili(radius) + 1
	for axis in 2:
		for k in range((c.x if axis == 0 else c.y) - reach, (c.x if axis == 0 else c.y) + reach + 1):
			for o: float in [0.49, 0.51]:
				var fixed: float = k + o
				var da: float = absf(fixed - (target.x if axis == 0 else target.y))
				if da > radius:
					continue
				var lim: float = sqrt(radius * radius - da * da)
				var free0: float = target.y if axis == 0 else target.x
				var t: float = free0 - lim
				while t <= free0 + lim + 1e-6:
					var tt: float = snappedf(t, 0.01)
					cands.append(Vector2(fixed, tt) if axis == 0 else Vector2(tt, fixed))
					t += 0.1
	cands.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da: float = a.distance_squared_to(target)
		var db: float = b.distance_squared_to(target)
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	# Порядок місць: поле, узбіччя дороги, двір уздовж паркану (PropLayer pole_spot_ok).
	for tier in 3:
		for q in cands:
			if _p.pole_spot_ok(q, tier) and not _near_avoid(q) and (accept.is_null() or accept.call(q)):
				return q
	return Vector2.INF


func _near_avoid(q: Vector2) -> bool:
	for a in _avoid:
		if a.distance_to(q) < 1.4:
			return true
	return false


func _snap_wide(target: Vector2, radius: float) -> Vector2:
	var q: Vector2 = _snap(target, radius)
	return q if q.is_finite() else _snap(target, radius * 1.6)


func _clamp_world(q: Vector2) -> Vector2:
	var lo: float = -_ring - 0.49
	return Vector2(clampf(q.x, lo, _size.x + _ring - 1 + 0.49), clampf(q.y, lo, _size.y + _ring - 1 + 0.49))


## Ламана на відстані d від осі дороги: ліворуч (side > 0) чи праворуч за ходом, у кутах — міттер.
static func offset_poly(pts: Array, side: float, d: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n: int = pts.size()
	var norms: Array[Vector2] = []
	for k in range(1, n):
		var dir: Vector2 = ((pts[k] as Vector2) - (pts[k - 1] as Vector2)).normalized()
		norms.append(Vector2(side * dir.y, -side * dir.x))
	for k in n:
		if k == 0:
			out.append((pts[0] as Vector2) + norms[0] * d)
		elif k == n - 1:
			out.append((pts[k] as Vector2) + norms[n - 2] * d)
		else:
			var a: Vector2 = norms[k - 1]
			var b: Vector2 = norms[k]
			out.append((pts[k] as Vector2) + (a + b) / (1.0 + a.dot(b)) * d)
	return out


# --- 10 кВ ---------------------------------------------------------------------------------

## Стовпи 10 кВ за намірами routes: вздовж осі дороги з боку side, кути й кінці на краю світу — вершини, між
## ними рівномірно не рідше за TRUNK_GAP; відгалуження (from ≥ 0) починається з найближчого стовпа раніших трас.
func _trunk() -> Array:
	var out: Array = []
	for route: Dictionary in _p.layout.get("routes", []):
		var axis: Array = _simplify(route["axis"])
		var spur: bool = int(route.get("from", -1)) >= 0
		var off: Array[Vector2] = offset_poly(axis, float(route.get("side", 1.0)), VERGE)
		var verts: Array[Vector2] = []
		for k in off.size():
			var q: Vector2 = off[k]
			if k == off.size() - 1 or (k == 0 and not spur):
				q = _clamp_world(q)
			if k == 0 and spur:
				var near := Vector2.INF
				for line: Array in out:
					for pt: Vector2 in line:
						if not near.is_finite() or pt.distance_to(q) < near.distance_to(q):
							near = pt
				verts.append(near if near.is_finite() else q)
				continue
			var s: Vector2 = _snap_wide(q, 1.0)
			if s.is_finite():
				verts.append(s)
		var pts: Array[Vector2] = []
		for k in verts.size():
			if k > 0:
				pts.append_array(_between(verts[k - 1], verts[k], MAX_10KV, TRUNK_GAP))
			pts.append(verts[k])
		_clear_buildings(pts)
		if pts.size() >= 2:
			out.append(pts)
	return out


## Проліт, що лягає на будівлю чи довший за MAX_10KV, ділиться опорою збоку: з обох боків проліт вільний і не довший за MAX_10KV.
func _clear_buildings(pts: Array[Vector2]) -> void:
	var k: int = 1
	var guard: int = 0
	while k < pts.size() and guard < 40:
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		if not _p.span_hits_building(a, b) and a.distance_to(b) <= MAX_10KV:
			k += 1
			continue
		guard += 1
		var s: Vector2 = _detour(a, b)
		if s.is_finite():
			pts.insert(k, s)
		else:
			k += 1


func _detour(a: Vector2, b: Vector2) -> Vector2:
	var n: Vector2 = (b - a).normalized().orthogonal()
	for off: float in [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
		for t: float in [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]:
			var s: Vector2 = _snap(a.lerp(b, t) + n * off, 0.5)
			if s.is_finite() and s.distance_to(a) >= 1.6 and s.distance_to(b) >= 1.6 \
					and s.distance_to(a) <= MAX_10KV and s.distance_to(b) <= MAX_10KV \
					and not _p.span_hits_building(a, s) and not _p.span_hits_building(s, b):
				return s
	return Vector2.INF


## Вісь дороги для 10 кВ без дрібних вигинів: Дуглас–Пекер з допуском SIMPLIFY_TOL, потім вершини не ближче за
## MIN_VERTEX_GAP одна до одної (кінці лишаються): траса не смикається на кожному повороті звивистої дороги.
func _simplify(axis: Array) -> Array:
	var keep: Array[bool] = []
	keep.resize(axis.size())
	keep.fill(false)
	keep[0] = true
	keep[axis.size() - 1] = true
	var stack: Array = [[0, axis.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var far: int = -1
		var far_d: float = SIMPLIFY_TOL
		for k in range(seg[0] + 1, seg[1]):
			var d: float = (axis[k] as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(axis[k], axis[seg[0]], axis[seg[1]]))
			if d > far_d:
				far_d = d
				far = k
		if far >= 0:
			keep[far] = true
			stack.append([seg[0], far])
			stack.append([far, seg[1]])
	var out: Array = []
	for k in axis.size():
		if not keep[k]:
			continue
		if k == axis.size() - 1 and not out.is_empty() and (out.back() as Vector2).distance_to(axis[k]) < MIN_VERTEX_GAP and out.size() > 1:
			out.pop_back()
		if out.is_empty() or k == axis.size() - 1 or (out.back() as Vector2).distance_to(axis[k]) >= MIN_VERTEX_GAP:
			out.append(axis[k])
	return out


## Проміжні стовпи між a і b (не включаючи кінців): рівномірно, кожен проліт ≤ max_span.
func _between(a: Vector2, b: Vector2, max_span: float, gap: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var len_: float = a.distance_to(b)
	if len_ <= max_span:
		return out
	var n: int = ceili(len_ / gap)
	for i in range(1, n):
		var s: Vector2 = _snap_wide(a.lerp(b, float(i) / n), 1.0)
		if s.is_finite():
			out.append(s)
	return out


# --- село ----------------------------------------------------------------------------------

func _village(homes: Array, trunk: Array) -> void:
	var stations: Array[Vector2] = []
	var runs: Array = []
	_streets(homes, stations, runs)
	if stations.is_empty():
		# Хата без вулиці поряд (хутір): ТП на найближчому стовпі 10 кВ, відвід — опорою-запаскою біля хати.
		var nearest := Vector2.INF
		for line: Array in trunk:
			for pt: Vector2 in line:
				if not nearest.is_finite() or pt.distance_to(homes[0]["centre"]) < nearest.distance_to(homes[0]["centre"]):
					nearest = pt
		if not nearest.is_finite():
			for h: Dictionary in homes:
				unfed.append(h["centre"])
			return
		stations.append(nearest)
	# ТП: стовп 10 кВ магістралі (наявний чи вставлений у проліт), найближчий до станції, що найближча до магістралі;
	# біля стовпа має знайтись місце під шафу.
	var tp := Vector2.INF
	var best: float = INF
	for i in stations.size():
		for line: Array in trunk:
			for k in line.size():
				var d: float = stations[i].distance_to(line[k])
				if d < best and _cabinet_fits(line[k], _pole_dir(line, k)):
					best = d
					tp = line[k]
				if k > 0:
					var proj: Vector2 = Geometry2D.get_closest_point_to_segment(stations[i], line[k - 1], line[k])
					var dp: float = stations[i].distance_to(proj)
					if dp < best - 0.5 and proj.distance_to(line[k - 1]) >= 2.0 and proj.distance_to(line[k]) >= 2.0:
						var s: Vector2 = _snap(proj, 0.6)
						if s.is_finite() and s.distance_to(line[k - 1]) >= 2.0 and s.distance_to(line[k]) >= 2.0 \
								and _cabinet_fits(s, ((s - line[k - 1]).normalized() + (line[k] - s).normalized()).normalized()):
							best = dp
							tp = s
	if not tp.is_finite():
		for h: Dictionary in homes:
			unfed.append(h["centre"])
		return
	# Одна ТП на поселення: близька наявна ТП — спільна.
	var shared: bool = false
	for t: Vector2 in transformers:
		if t.distance_to(tp) < TP_GAP:
			tp = t
			shared = true
			break
	var inserted: bool = false
	if not shared:
		inserted = _insert_pole(trunk, tp)
		_avoid.append(tp)
	# ТП — корінь дерева: станція упритул до неї і є ТП; інакше ТП — нова станція.
	var root: int = -1
	for i in stations.size():
		if stations[i].distance_to(tp) < 1.4 and (root < 0 or stations[i].distance_to(tp) < stations[root].distance_to(tp)):
			root = i
	if root >= 0:
		stations[root] = tp
	else:
		stations.append(tp)
		root = stations.size() - 1
	var dead: Dictionary = {}
	for i in stations.size():
		if i != root and stations[i].distance_to(tp) < 1.4:
			dead[i] = true
	var trunk_segs: Array = []
	for line: Array in trunk:
		for k in range(1, line.size()):
			trunk_segs.append([line[k - 1], line[k]])
	# Ребра-кандидати: лише сусіди вздовж вулиці й проліти від ТП; жодних зрізів через квартали.
	var edges: Array = []
	for run: Array in runs:
		for k in range(1, run.size()):
			var i: int = run[k - 1]
			var j: int = run[k]
			var d: float = stations[i].distance_to(stations[j])
			if i == j or dead.has(i) or dead.has(j):
				continue
			if d <= MAX_04KV:
				if _span_clear(stations[i], stations[j], trunk_segs):
					edges.append([mini(i, j), maxi(i, j), d])
			elif d <= BRIDGE_CHAIN_MAX:
				# Станцію між ними не вдалось поставити (двір, вода): опора посередині тієї ж вулиці.
				edges.append_array(_chain_edges(stations, i, j, trunk_segs))
	var from_tp: int = 0
	for i in stations.size():
		var d: float = stations[root].distance_to(stations[i])
		if i != root and not dead.has(i) and d <= MAX_04KV and _span_clear(stations[root], stations[i], trunk_segs):
			edges.append([mini(root, i), maxi(root, i), d * 1.6])
			from_tp += 1
	# ТП далі за проліт від вулиці: пряма ланка опор 0.4 кВ до найближчої станції, якщо вона не зачіпає будівель.
	if from_tp == 0:
		var near_i: int = -1
		for i in stations.size():
			if i != root and not dead.has(i) and (near_i < 0 or stations[i].distance_to(tp) < stations[near_i].distance_to(tp)):
				near_i = i
		if near_i >= 0 and stations[near_i].distance_to(tp) <= BRIDGE_CHAIN_MAX:
			edges.append_array(_chain_edges(stations, root, near_i, trunk_segs))
	edges.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2] or (a[2] == b[2] and (a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))))
	# Дерево Прима від ТП. Частина вулиць, відрізана від дерева, сполучається з ним одним коротким прольотом.
	var parent: Dictionary = {root: -1}
	var tree_edges: Array = []
	var bridged: Dictionary = dead.duplicate()
	while true:
		var grown: bool = true
		while grown:
			grown = false
			for e: Array in edges:
				var a: int = e[0]
				var b: int = e[1]
				if parent.has(a) == parent.has(b):
					continue
				var from: int = a if parent.has(a) else b
				var to: int = b if parent.has(a) else a
				if _crosses(stations[from], stations[to], tree_edges):
					continue
				parent[to] = from
				tree_edges.append([stations[from], stations[to]])
				grown = true
				break
		var link: Array = _nearest_gap(stations, parent, bridged)
		if link.is_empty():
			break
		bridged[link[1]] = true
		if _span_clear(stations[link[0]], stations[link[1]], trunk_segs):
			edges.append([link[0], link[1], 1.0])
	# Відводи: кожна хата — до найближчої станції дерева, звідки відвід можливий; коли такої нема — нова опора
	# на землі поблизу, з'єднана коротким прольотом із деревом.
	var needed: Dictionary = {}
	for h: Dictionary in homes:
		var pick: int = _pick_station(h["rect"], stations, parent)
		if pick < 0:
			pick = _add_station_for(h["rect"], stations, parent, tree_edges, trunk_segs)
		if pick < 0:
			unfed.append(h["centre"])
			continue
		var u: int = pick
		while u >= 0 and not needed.has(u):
			needed[u] = true
			u = parent[u]
	if needed.is_empty():
		# ТП, яка нікого не живить, не лишається ні в мережі, ні на лінії 10 кВ.
		if inserted:
			_remove_pole(trunk, tp)
			_avoid.erase(tp)
		return
	if not shared:
		transformers.append(tp)
	needed[root] = true
	for i: int in needed:
		_avoid.append(stations[i])
	# Ламані: від ТП гілками дерева (як lines).
	var kids: Dictionary = {}
	for i: int in needed:
		var par: int = parent[i]
		if par >= 0:
			if not kids.has(par):
				kids[par] = []
			(kids[par] as Array).append(i)
	var stack: Array = [[root, [] as Array[Vector2]]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var cur: int = item[0]
		var ch: Array[Vector2] = (item[1] as Array[Vector2]).duplicate()
		ch.append(stations[cur])
		while true:
			var ks: Array = kids.get(cur, [])
			ks.sort()
			if ks.is_empty():
				break
			for k in range(1, ks.size()):
				stack.append([ks[k], [stations[cur]] as Array[Vector2]])
			cur = ks[0]
			ch.append(stations[cur])
		if ch.size() >= 2:
			lines.append({"kind": &"04kv", "points": ch})


## Станція дерева, найближча до центру хати, від якої відвід можливий (-1 — жодна не дістає): так само обирає відвід
## розстановка (PropLayer _service_drops).
func _pick_station(rect: Rect2, stations: Array[Vector2], parent: Dictionary) -> int:
	var pick: int = -1
	var pick_d: float = INF
	for i: int in parent:
		if _p.drop_ok(rect, stations[i]):
			var d: float = stations[i].distance_to(rect.get_center())
			if d < pick_d - 1e-9 or (absf(d - pick_d) <= 1e-9 and i < pick):
				pick_d = d
				pick = i
	return pick


## Нова опора на землі біля хати, від якої можливий відвід і яка сполучається з деревом одним прольотом ≤ MAX_04KV
## (вільним від будівель, магістралі й гілок дерева). Повертає її індекс у stations, -1 — місця нема.
func _add_station_for(rect: Rect2, stations: Array[Vector2], parent: Dictionary, tree_edges: Array, trunk_segs: Array) -> int:
	var accept := func(q: Vector2) -> bool:
		# Опора-запаска стоїть на вулиці перед хатою (не далі 20 м від асфальту), а не в полі.
		if not _p.drop_ok(rect, q) or _p.road_edge_m(q) > 20.0:
			return false
		for s in stations:
			if s.distance_to(q) < 1.4:
				return false
		for i: int in parent:
			if stations[i].distance_to(q) <= MAX_04KV and _span_clear(stations[i], q, trunk_segs) and not _crosses(stations[i], q, tree_edges):
				return true
		return false
	var q: Vector2 = _snap(rect.get_center(), 3.4, accept)
	if not q.is_finite():
		# Дерево далі за проліт: опора на вулиці перед хатою й ланцюжок опор до найближчої досяжної станції дерева.
		var far := func(c: Vector2) -> bool:
			if not _p.drop_ok(rect, c) or _p.road_edge_m(c) > 20.0:
				return false
			for s in stations:
				if s.distance_to(c) < 1.4:
					return false
			var probe: Array[Vector2] = stations.duplicate()
			return not _chain_to_tree(probe, parent, c, trunk_segs, tree_edges).is_empty()
		q = _snap(rect.get_center(), 3.4, far)
		if not q.is_finite():
			return -1
		var ids: Array[int] = _chain_to_tree(stations, parent, q, trunk_segs, tree_edges)
		if ids.is_empty():
			return -1
		for k in range(1, ids.size()):
			parent[ids[k]] = ids[k - 1]
			tree_edges.append([stations[ids[k - 1]], stations[ids[k]]])
		return ids.back()
	var best: int = -1
	for i: int in parent:
		if stations[i].distance_to(q) <= MAX_04KV and _span_clear(stations[i], q, trunk_segs) and not _crosses(stations[i], q, tree_edges) \
				and (best < 0 or stations[i].distance_to(q) < stations[best].distance_to(q)):
			best = i
	stations.append(q)
	parent[stations.size() - 1] = best
	tree_edges.append([stations[best], q])
	return stations.size() - 1


## Ланцюжок опор від найближчої досяжної станції дерева до нової опори в точці c (станції додаються в stations; c —
## остання); порожній, якщо жодна станція в межах BRIDGE_CHAIN_MAX не сполучається вільним від будівель, магістралі й
## гілок дерева ланцюжком.
func _chain_to_tree(stations: Array[Vector2], parent: Dictionary, c: Vector2, trunk_segs: Array, tree_edges: Array) -> Array[int]:
	var order: Array[int] = []
	for i: int in parent:
		if stations[i].distance_to(c) <= BRIDGE_CHAIN_MAX:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return stations[a].distance_to(c) < stations[b].distance_to(c) or (stations[a].distance_to(c) == stations[b].distance_to(c) and a < b))
	stations.append(c)
	var qi: int = stations.size() - 1
	for i in order:
		var base: int = stations.size()
		var ids: Array[int] = _chain_ids(stations, i, qi, trunk_segs)
		var ok: bool = not ids.is_empty()
		for k in range(1, ids.size()):
			if _crosses(stations[ids[k - 1]], stations[ids[k]], tree_edges):
				ok = false
		if ok:
			return ids
		stations.resize(base)
	stations.resize(qi)
	return []


## Ланцюжок станцій від i до j з проміжними опорами (кожен проліт ≤ MAX_04KV, вільний від будівель і магістралі), у
## порядку від i до j; порожній, якщо не вийшло.
func _chain_ids(stations: Array[Vector2], i: int, j: int, trunk_segs: Array) -> Array[int]:
	var ids: Array[int] = [i]
	for q in _between(stations[i], stations[j], MAX_04KV, STATION_GAP):
		# Станція, що вже стоїть ближче 1.4, — та сама опора: ланки ділять її, а не ставлять другу в півклітинці.
		var at: int = -1
		for si in stations.size():
			if si != j and stations[si].distance_to(q) < 1.4:
				at = si
				break
		var to: Vector2 = q if at < 0 else stations[at]
		if not _span_clear(stations[ids.back()], to, trunk_segs):
			return []
		if at < 0:
			stations.append(q)
			at = stations.size() - 1
		if at != ids.back():
			ids.append(at)
	if stations[ids.back()].distance_to(stations[j]) > MAX_04KV or not _span_clear(stations[ids.back()], stations[j], trunk_segs):
		return []
	ids.append(j)
	return ids


func _chain_edges(stations: Array[Vector2], i: int, j: int, trunk_segs: Array) -> Array:
	var ids: Array[int] = _chain_ids(stations, i, j, trunk_segs)
	var out: Array = []
	for k in range(1, ids.size()):
		out.append([mini(ids[k - 1], ids[k]), maxi(ids[k - 1], ids[k]), 1.0])
	return out


## Проліт a–b не лягає на будівлю й не перетинає магістраль.
func _span_clear(a: Vector2, b: Vector2, trunk_segs: Array) -> bool:
	if _p.span_hits_building(a, b):
		return false
	for e: Array in trunk_segs:
		if _seg_crosses(a, b, e[0], e[1]):
			return false
	return true


## Чи знайдеться біля стовпа в точці p, повернутого вздовж t, місце під шафу ТП.
func _cabinet_fits(p: Vector2, t: Vector2) -> bool:
	return PropLayer.cabinet_centre(p, t, Vector2(t.y, -t.x), _p).is_finite()


## Напрям стовпа k ламаної — так само, як його обирає розстановка (бісектриса прольотів).
func _pole_dir(line: Array, k: int) -> Vector2:
	var t := Vector2.ZERO
	if k > 0:
		t += ((line[k] as Vector2) - (line[k - 1] as Vector2)).normalized()
	if k < line.size() - 1:
		t += ((line[k + 1] as Vector2) - (line[k] as Vector2)).normalized()
	if t.length() < 0.1:
		t = (line[k] as Vector2) - (line[maxi(k - 1, 0)] as Vector2)
	return t.normalized()


## Найближча пара (станція дерева, станція поза деревом) не далі за BRIDGE_MAX; порожній — таких нема. Станція,
## з якої міст уже пробувався, вдруге не береться.
func _nearest_gap(stations: Array[Vector2], parent: Dictionary, bridged: Dictionary) -> Array:
	var best: float = BRIDGE_MAX
	var pick: Array = []
	for a: int in parent:
		for b in stations.size():
			if parent.has(b) or bridged.has(b):
				continue
			var d: float = stations[a].distance_to(stations[b])
			if d < best:
				best = d
				pick = [a, b]
	return pick


## Вставити ТП у проліт магістралі, якщо її там ще нема; true — вставлено.
func _insert_pole(trunk: Array, pt: Vector2) -> bool:
	for line: Array in trunk:
		if line.has(pt):
			return false
	for line: Array in trunk:
		for k in range(1, line.size()):
			if Geometry2D.get_closest_point_to_segment(pt, line[k - 1], line[k]).distance_to(pt) <= 0.6:
				line.insert(k, pt)
				return true
	return false


func _remove_pole(trunk: Array, pt: Vector2) -> void:
	for line: Array in trunk:
		line.erase(pt)


static func _seg_crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if a == c or a == d or b == c or b == d:
		return false
	return Geometry2D.segment_intersects_segment(a, b, c, d) != null


func _crosses(a: Vector2, b: Vector2, tree: Array) -> bool:
	for e: Array in tree:
		if _seg_crosses(a, b, e[0], e[1]):
			return true
		# Станція не лежить під чужим прольотом.
		if e[0] != a and e[0] != b and Geometry2D.get_closest_point_to_segment(e[0], a, b).distance_to(e[0]) < 0.25:
			return true
		if e[1] != a and e[1] != b and Geometry2D.get_closest_point_to_segment(e[1], a, b).distance_to(e[1]) < 0.25:
			return true
	return false


## Вулиці села: дороги не далі за STREET_R від хати; уздовж кожної — станції з боку дворів (клітинки BUILDING чи
## RUBBLE), на межі клітинок біля краю асфальту. stations — позиції, runs — індекси станцій за порядком вулиці.
func _streets(homes: Array, stations: Array[Vector2], runs: Array) -> void:
	var rc: Variant = _p.height.roads if _p.height != null else null
	if rc == null:
		return
	for li in rc.lines.size():
		var pts: PackedVector2Array = rc.lines[li]
		var run: Array[Vector2] = []
		var normals: Array[Vector2] = []
		var run_side: float = 0.0
		var last_near: int = -1
		# Кільцева дорога: ствол лише з боку дворів, а не навколо кварталу по зовнішньому боці.
		var closed: bool = pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1.5
		for k in pts.size():
			var a: Vector2 = pts[k] - Vector2(_ring, _ring)
			var dir: Vector2 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var near: bool = false
			for h: Dictionary in homes:
				near = near or a.distance_to(h["centre"]) <= STREET_R
			var side: float = _side(a, nrm, homes, run_side) if near else 0.0
			if side != 0.0 and not run.is_empty() and side != run_side:
				_flush(run.slice(0, last_near + 1), normals, run_side, stations, runs, not closed)
				run = []
				normals = []
				last_near = -1
			if side != 0.0 and run.is_empty():
				run_side = side
			# Ділянка між двома дворами лишається на тому ж боці: ствол іде вздовж вулиці без розривів.
			if side != 0.0 or not run.is_empty():
				run.append(a)
				normals.append(nrm)
				if side != 0.0:
					last_near = run.size() - 1
		_flush(run.slice(0, last_near + 1), normals, run_side, stations, runs, not closed)


## З якого боку вулиці двори: +1 — вздовж нормалі, −1 — проти, 0 — з жодного. Коли двори з обох боків, лишається
## бік, яким ствол уже йде (prefer), а на новій вулиці — той, де ближчі хати: ствол не стрибає з боку на бік.
func _side(a: Vector2, nrm: Vector2, homes: Array, prefer: float) -> float:
	var ok: Array[bool] = [false, false]
	var near_d: Array[float] = [INF, INF]
	for s in 2:
		var q: Vector2 = a + nrm * SIDE_PROBE * (1.0 if s == 0 else -1.0)
		ok[s] = _p.kind(Vector2i(roundi(q.x), roundi(q.y))) in [Terrain.Kind.BUILDING, Terrain.Kind.RUBBLE]
		for h: Dictionary in homes:
			near_d[s] = minf(near_d[s], q.distance_to(h["centre"]))
	if not ok[0] and not ok[1]:
		return 0.0
	if ok[0] != ok[1]:
		return 1.0 if ok[0] else -1.0
	if prefer != 0.0:
		return prefer
	return 1.0 if near_d[0] <= near_d[1] else -1.0


func _flush(run: Array[Vector2], normals: Array[Vector2], side: float, stations: Array[Vector2], runs: Array, may_flip: bool) -> void:
	if run.size() < 6:
		return
	var cum: PackedFloat32Array = PackedFloat32Array([0.0])
	for k in range(1, run.size()):
		cum.append(cum[k - 1] + run[k].distance_to(run[k - 1]))
	if cum[run.size() - 1] < 1.0:
		return
	# Ключові точки: початок, кінець і повороти (найгостріший у вікні, не частіше ніж раз на 1.5 клітинки).
	var keys: Array[int] = [0]
	var k: int = BEND_WINDOW
	while k < run.size() - BEND_WINDOW:
		var a: Vector2 = run[k] - run[k - BEND_WINDOW]
		var b: Vector2 = run[k + BEND_WINDOW] - run[k]
		if a.length() > 0.01 and b.length() > 0.01 and absf(a.angle_to(b)) > BEND_ANGLE and cum[k] - cum[keys.back()] > 1.5:
			var best_k: int = k
			var best_a: float = absf(a.angle_to(b))
			var j: int = k + 1
			while j < run.size() - BEND_WINDOW and cum[j] - cum[k] < 1.0:
				var a2: Vector2 = run[j] - run[j - BEND_WINDOW]
				var b2: Vector2 = run[j + BEND_WINDOW] - run[j]
				if absf(a2.angle_to(b2)) > best_a:
					best_a = absf(a2.angle_to(b2))
					best_k = j
				j += 1
			keys.append(best_k)
			k = best_k + BEND_WINDOW
		else:
			k += 1
	if keys.back() != run.size() - 1:
		keys.append(run.size() - 1)
	var picks: Array[int] = [0]
	for i in range(1, keys.size()):
		var g0: int = keys[i - 1]
		var g1: int = keys[i]
		var gap: float = cum[g1] - cum[g0]
		var pieces: int = maxi(1, ceili(gap / STATION_GAP - 1e-6))
		for pi in range(1, pieces):
			var target_s: float = cum[g0] + gap * pi / pieces
			var m: int = g0
			while m < g1 and cum[m] < target_s:
				m += 1
			picks.append(m)
		picks.append(g1)
	# Бік дворів, а коли смуга між асфальтом і хатами заставлена (проліти лягають на будівлі) — протилежний бік
	# вулиці: відводи тоді перетинають вулицю.
	var spots: Array[Vector2] = _spots(run, normals, picks, side)
	if may_flip:
		var other: Array[Vector2] = _spots(run, normals, picks, -side)
		if _blocked(other) < _blocked(spots):
			spots = other
	var ids: Array[int] = []
	for s: Vector2 in spots:
		var at: int = stations.find(s)
		if at < 0:
			# Станція, що опинилась упритул до наявної (розвилка вулиць), — та сама опора.
			var nearest: int = -1
			for si in stations.size():
				if stations[si].distance_to(s) < 1.4 and (nearest < 0 or stations[si].distance_to(s) < stations[nearest].distance_to(s)):
					nearest = si
			if nearest >= 0:
				at = nearest
			else:
				stations.append(s)
				at = stations.size() - 1
		if ids.is_empty() or ids.back() != at:
			ids.append(at)
	if ids.size() >= 2:
		runs.append(ids)


## Місця станцій уздовж вулиці з боку side (пропуск там, де придатного місця нема).
func _spots(run: Array[Vector2], normals: Array[Vector2], picks: Array[int], side: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for idx in picks:
		var s: Vector2 = _snap_wide(run[idx] + normals[idx] * side * VERGE, 0.6)
		if s.is_finite() and (out.is_empty() or out.back().distance_to(s) >= 1.4):
			out.append(s)
	return out


## Скільки прольотів між сусідніми місцями лягають на будівлю або надто довгі, і скільки місць не знайшлось.
func _blocked(spots: Array[Vector2]) -> int:
	var bad: int = 0
	for k in range(1, spots.size()):
		if _p.span_hits_building(spots[k - 1], spots[k]) or spots[k - 1].distance_to(spots[k]) > BRIDGE_CHAIN_MAX:
			bad += 1
	return bad * 2 + (0 if spots.size() >= 2 else 4)
