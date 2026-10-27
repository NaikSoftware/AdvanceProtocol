class_name PowerGrid
extends RefCounted
## Мережа ЛЕП, яку гра будує сама й однаково щоразу (без пошуку й без збережених точок):
## - 10 кВ іде за намірами routes макета вздовж головних доріг (вісь спрощена), стовпи через ≤ MAX_10KV клітинок;
## - у кожного поселення (хати, зв'язані кроком SETTLEMENT_R) — одна ТП на стовпі 10 кВ біля в'їзду; ТП ближче
##   за TP_GAP одна до одної — спільна;
## - 0.4 кВ — один ствол уздовж кожної вулиці села на смузі між асфальтом і хатами (з боку дворів; де вона
##   заставлена — з протилежного боку, крім кільцевої дороги), опори через ≤ MAX_04KV клітинок і на поворотах;
##   мережа — дерево (Прима від ТП) по сусідах уздовж вулиці, без перетинів; відрізана вулиця
##   сполучається з деревом прольотом чи ланкою опор не довшою за BRIDGE_MAX;
## - головна вулиця села лишається з лінією від ТП до кожної її опори навпроти хати (STREET_END); решта гілок — лише
##   до хат із відводом;
## - відвід — лише коли опора вулиці дістає до хати коротким прольотом (PropLayer drop_ok: через вулицю лише
##   впоперек, не чужим двором, не над грядками); опор заради далекої хати не ставимо. З досяжних хат села кожна
##   SKIP_ONE_IN-а лишається без відводу.
## Розстановка поступається там, де стовпу не місце (pole_spot_ok): місце шукається поряд на межах клітинок, а
## не знайшлось — стовпа нема, і це видно в тесті.
## Результат: lines — ламані з опор (kind, points), transformers — точки підстанцій, fed і skipped — хати з відводом
## і без нього, хоч опора й дістала б.

const STREET_R: float = 7.0
const SIDE_PROBE: float = 0.8
const VERGE: float = 0.9
const STATION_GAP: float = 4.5
const MAX_04KV: float = 5.0
const MAX_10KV: float = 9.0
const TRUNK_GAP: float = 7.5
const BEND_ANGLE: float = 0.9
const BEND_WINDOW: int = 5
## Синус 25° — найбільший відхил переходу через дорогу від прямого кута (як PropLayer.DROP_CROSS_COS).
const SQUARE_SIN: float = 0.423
## Межі пошуку, щоб будова карти не дорожчала від вулиць без виходу: скільки разів пробуємо сполучити відрізану
## станцію з деревом, скільки спроб на все село (BRIDGE_BUDGET), скільки кандидатів ТП перевіряємо на зв'язок із
## вулицею (TP_PROBES) і наскільки опора переходу через дорогу може відійти від місця прямо навпроти (HOP_R, клітинки).
const BRIDGE_TRIES: int = 3
const TP_PROBES: int = 40
const HOP_R: float = 1.2
const BRIDGE_BUDGET: int = 40
## Найбільше прольотів на опорі 0.4 кВ (відводи не лічаться); на ТП — два прольоти 10 кВ і до MAX_SPANS − 1 прольотів 0.4 кВ.
const MAX_SPANS: int = 3
## Кінцева опора головної вулиці стоїть не далі за стільки (клітинки) від хати.
const STREET_END: float = 3.0
## Кожна така за ліком досяжна хата села (за хешем) лишається без відводу.
const SKIP_ONE_IN: int = 3
## Найдовший проліт, яким відокремлена частина вулиць сполучається з деревом, клітинки.
const BRIDGE_MAX: float = 12.0
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
## ТП-кандидат -> чи сполучається з вулицею села (_tp_reaches), у межах одного села.
var _reach_cache: Dictionary = {}
var _spot_cache: Dictionary = {}
var _size := Vector2i.ZERO
var lines: Array[Dictionary] = []
var transformers: Array[Vector2] = []
## Центри хат із відводом і хат, до яких опора дістала б, але відводу навмисно нема (SKIP_ONE_IN).
var fed: Array[Vector2] = []
var skipped: Array[Vector2] = []
## Найбільше спроб мосту в одному селі й на одну станцію за весь план (тест стереже межі пошуку).
var peak_attempts: int = 0
var peak_tries: int = 0


func plan(placer: PropLayer._Placer) -> void:
	_p = placer
	_ring = placer.ring
	_size = placer.size
	var homes: Array[Dictionary] = _homes()
	var trunk: Array = _trunk()
	for line: Array in trunk:
		lines.append({"kind": &"10kv", "points": line})
	for line: Array in trunk:
		_avoid.append_array(line)
	for village: Array in _villages(homes):
		_village(village, trunk)


# --- хати й села ---------------------------------------------------------------------------

func _homes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inst: Dictionary in _p.layer._instances:
		if not PropLayer.is_home(inst):
			continue
		var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		out.append({"rect": r, "centre": r.get_center()})
	return out


## Хеш хати за центром: який її бік у черзі на відвід (однаково щоразу).
static func _home_hash(c: Vector2) -> int:
	return hash(Vector2i(roundi(c.x * 4.0), roundi(c.y * 4.0)))


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
	# Місце, придатне на нижчому ярусі, придатне й на вищих: accept для нього рахується раз, а не тричі.
	var accepted: Dictionary = {}
	for tier in 3:
		for q in cands:
			if not _spot_ok(q, tier) or _near_avoid(q):
				continue
			if not accepted.has(q):
				accepted[q] = accept.is_null() or accept.call(q)
			if accepted[q]:
				return q
	return Vector2.INF


## PropLayer pole_spot_ok з кешем: перешкоди за час планування не змінюються, а ті самі місця на межах клітинок
## перебираються сотні разів (переходи через дорогу, ТП).
func _spot_ok(q: Vector2, tier: int) -> bool:
	var key := Vector3(q.x, q.y, tier)
	if not _spot_cache.has(key):
		_spot_cache[key] = _p.pole_spot_ok(q, tier)
	return _spot_cache[key]


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
		# Хата без вулиці поряд (хутір): ТП на найближчому стовпі 10 кВ, відвід — від неї, якщо дістає.
		var nearest := Vector2.INF
		for line: Array in trunk:
			for pt: Vector2 in line:
				if not nearest.is_finite() or pt.distance_to(homes[0]["centre"]) < nearest.distance_to(homes[0]["centre"]):
					nearest = pt
		if not nearest.is_finite():
			return
		stations.append(nearest)
	# ТП: стовп 10 кВ магістралі (наявний чи вставлений у проліт), найближчий до станції, що найближча до магістралі;
	# біля стовпа має знайтись місце під шафу, а від нього — проліт до вулиці (_tp_reaches).
	var tp := Vector2.INF
	var best: float = INF
	_reach_cache.clear()
	for i in stations.size():
		for line: Array in trunk:
			for k in line.size():
				var d: float = stations[i].distance_to(line[k])
				if d < best and _cabinet_fits(line[k], _pole_dir(line, k)) and _tp_reaches(line[k], stations, trunk):
					best = d
					tp = line[k]
				if k > 0:
					var proj: Vector2 = Geometry2D.get_closest_point_to_segment(stations[i], line[k - 1], line[k])
					var dp: float = stations[i].distance_to(proj)
					if dp < best - 0.5 and proj.distance_to(line[k - 1]) >= 2.0 and proj.distance_to(line[k]) >= 2.0:
						var s: Vector2 = _snap(proj, 0.6)
						if s.is_finite() and s.distance_to(line[k - 1]) >= 2.0 and s.distance_to(line[k]) >= 2.0 \
								and _cabinet_fits(s, ((s - line[k - 1]).normalized() + (line[k] - s).normalized()).normalized()) \
								and _tp_reaches(s, stations, trunk):
							best = dp
							tp = s
	if not tp.is_finite():
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
				edges.append_array(_chain_edges(stations, i, j, trunk_segs, dead))
	var from_tp: int = 0
	var near_tp: Array = range(stations.size())
	near_tp.sort_custom(func(x: int, y: int) -> bool: return stations[root].distance_to(stations[x]) < stations[root].distance_to(stations[y]))
	var hops: int = 0
	for i: int in near_tp:
		var d: float = stations[root].distance_to(stations[i])
		if i == root or dead.has(i):
			continue
		if d <= MAX_04KV and _span_clear(stations[root], stations[i], trunk_segs):
			edges.append([mini(root, i), maxi(root, i), d * 1.6])
			from_tp += 1
		elif d <= MAX_04KV * 2.0 and from_tp == 0 and hops < 3:
			# ТП за дорогою від вулиці: перехід до однієї з трьох найближчих станцій, поки прямого прольоту нема.
			hops += 1
			var hop: Array = _square_hop(stations, root, i, trunk_segs)
			edges.append_array(hop)
			from_tp += int(not hop.is_empty())
	# ТП далі за проліт від вулиці: пряма ланка опор 0.4 кВ до найближчої станції, якщо вона не зачіпає будівель.
	if from_tp == 0:
		var near_i: int = -1
		for i in stations.size():
			if i != root and not dead.has(i) and (near_i < 0 or stations[i].distance_to(tp) < stations[near_i].distance_to(tp)):
				near_i = i
		if near_i >= 0 and stations[near_i].distance_to(tp) <= BRIDGE_CHAIN_MAX:
			edges.append_array(_chain_edges(stations, root, near_i, trunk_segs, dead))
	edges.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2] or (a[2] == b[2] and (a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))))
	# Дерево Прима від ТП. Частина вулиць, відрізана від дерева, сполучається з ним одним коротким прольотом.
	var parent: Dictionary = {root: -1}
	var tree_edges: Array = []
	var bridged: Dictionary = dead.duplicate()
	# Опора 0.4 кВ несе щонайбільше MAX_SPANS прольотів: розвилка на чотири дроти — павутиння. ТП — два прольоти 10 кВ
	# (лічаться за один) і щонайбільше MAX_SPANS − 1 прольотів 0.4 кВ, разом із тими, що вже йдуть від спільної ТП.
	var degree: Dictionary = {root: 1 + _spans_04_at(tp)}
	var attempts: int = 0
	var tries: Dictionary = {}
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
				if _crosses(stations[from], stations[to], tree_edges) or int(degree.get(from, 0)) >= MAX_SPANS:
					continue
				degree[from] = int(degree.get(from, 0)) + 1
				degree[to] = 1
				parent[to] = from
				tree_edges.append([stations[from], stations[to]])
				grown = true
				break
		var link: Array = _nearest_gap(stations, parent, bridged)
		if link.is_empty() or attempts >= BRIDGE_BUDGET:
			break
		attempts += 1
		bridged[Vector2i(link[0], link[1])] = true
		# Станцію, до якої вже BRIDGE_TRIES разів не дотягнулись, більше не пробуємо: кожна спроба — це пошук місць
		# для опор, а будова карти не повинна дорожчати від кожної вулиці без виходу.
		tries[link[1]] = int(tries.get(link[1], 0)) + 1
		peak_attempts = maxi(peak_attempts, attempts)
		peak_tries = maxi(peak_tries, tries[link[1]])
		if int(tries[link[1]]) >= BRIDGE_TRIES:
			bridged[link[1]] = true
		if stations[link[0]].distance_to(stations[link[1]]) <= MAX_04KV and _span_clear(stations[link[0]], stations[link[1]], trunk_segs):
			edges.append([link[0], link[1], 1.0])
		else:
			# Відрізана вулиця за дорогою — опора навпроти й проліт прямо впоперек; далі за проліт — ланка проміжних
			# опор, інакше її хати лишились би без світла.
			var base: int = stations.size()
			var hop: Array = _square_hop(stations, link[0], link[1], trunk_segs)
			edges.append_array(hop if not hop.is_empty() else _chain_edges(stations, link[0], link[1], trunk_segs, dead))
			# Проміжні опори переходу чи ланки — не нові цілі мосту: інакше невдалі спроби множили б станції.
			for k in range(base, stations.size()):
				bridged[k] = true
	# Відводи: хата — до найближчої станції дерева, звідки відвід можливий; такої нема — хата без відводу. З досяжних
	# хат села кожна SKIP_ONE_IN-а (за хешем центру, найменші хеші) лишається без відводу: сусідні хати не всі під
	# дротами, а село з однією-двома досяжними хатами не лишається без жодного відводу.
	var reach: Array = []
	for h: Dictionary in homes:
		var pick: int = _pick_station(h["rect"], stations, parent)
		if pick >= 0:
			reach.append([h, pick])
	var by_hash: Array = reach.duplicate()
	by_hash.sort_custom(func(a: Array, b: Array) -> bool: return _home_hash(a[0]["centre"]) < _home_hash(b[0]["centre"]))
	var chosen: Array = by_hash.slice(reach.size() / SKIP_ONE_IN)
	var needed: Dictionary = {}
	for r: Array in reach:
		(fed if chosen.has(r) else skipped).append(r[0]["centre"])
	for r: Array in chosen:
		var u: int = r[1]
		while u >= 0 and not needed.has(u):
			needed[u] = true
			u = parent[u]
	# Головна вулиця села (найбільше опор у дереві) лишається з лінією 0.4 кВ уздовж хат, навіть де відводів
	# нема: село з електрикою, а не хати з окремими дротами.
	var main: Array = []
	for run: Array in runs:
		var on_tree: Array = run.filter(func(i: int) -> bool: return parent.has(i) and not dead.has(i))
		if on_tree.size() > main.size():
			main = on_tree
	# Лінія тягнеться вулицею від ТП до кожної її опори навпроти хати, а не далі: кінець лінії — біля хати.
	main = main.filter(func(i: int) -> bool:
		return homes.any(func(h: Dictionary) -> bool: return stations[i].distance_to(h["centre"]) <= STREET_END))
	for i: int in main:
		var u: int = i
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


## Ланцюжок станцій від i до j з проміжними опорами (кожен проліт ≤ MAX_04KV, вільний від будівель і магістралі), у
## порядку від i до j; порожній, якщо не вийшло.
func _chain_ids(stations: Array[Vector2], i: int, j: int, trunk_segs: Array, dead: Dictionary) -> Array[int]:
	var base: int = stations.size()
	var ids: Array[int] = [i]
	for q in _between(stations[i], stations[j], MAX_04KV, STATION_GAP):
		# Станція, що вже стоїть ближче 1.4, — та сама опора: ланки ділять її, а не ставлять другу впритул; задалека від
		# попередньої — ланки нема.
		var at: int = -1
		for si in stations.size():
			if si != j and not dead.has(si) and stations[si].distance_to(q) < 1.4:
				at = si
				break
		var to: Vector2 = q if at < 0 else stations[at]
		if stations[ids.back()].distance_to(to) > MAX_04KV or not _span_clear(stations[ids.back()], to, trunk_segs):
			stations.resize(base)
			return []
		if at < 0:
			stations.append(q)
			at = stations.size() - 1
		if at != ids.back():
			ids.append(at)
	if stations[ids.back()].distance_to(stations[j]) > MAX_04KV or not _span_clear(stations[ids.back()], stations[j], trunk_segs):
		stations.resize(base)
		return []
	ids.append(j)
	return ids


func _chain_edges(stations: Array[Vector2], i: int, j: int, trunk_segs: Array, dead: Dictionary) -> Array:
	var ids: Array[int] = _chain_ids(stations, i, j, trunk_segs, dead)
	var out: Array = []
	for k in range(1, ids.size()):
		out.append([mini(ids[k - 1], ids[k]), maxi(ids[k - 1], ids[k]), 1.0])
	return out


## Скільки прольотів 0.4 кВ уже виходить з опори в точці p (спільна ТП двох сіл).
func _spans_04_at(p: Vector2) -> int:
	var n: int = 0
	for line: Dictionary in lines:
		if line["kind"] != &"04kv":
			continue
		var pts: Array = line["points"]
		for k in pts.size():
			if pts[k] == p:
				n += int(k > 0) + int(k < pts.size() - 1)
	return n


## Чи сполучається ТП у точці p з якоюсь станцією вулиці: прямим прольотом чи переходом через дорогу (_square_hop).
## Проба на копії станцій — нічого не додає.
func _tp_reaches(p: Vector2, stations: Array[Vector2], trunk: Array) -> bool:
	if _reach_cache.has(p):
		return _reach_cache[p]
	# Кандидатів ТП у селі — десятки (кожен стовп магістралі й проєкції станцій); далі за TP_PROBES найближчих вони вже
	# не виграють, а кожна проба — пошук переходу через дорогу.
	if _reach_cache.size() >= TP_PROBES:
		return false
	_reach_cache[p] = false
	var segs: Array = []
	for line: Array in trunk:
		for k in range(1, line.size()):
			if Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k]).distance_to(p) > 0.6:
				segs.append([line[k - 1], line[k]])
	var probe: Array[Vector2] = stations.duplicate()
	probe.append(p)
	var pi: int = probe.size() - 1
	var order: Array = range(stations.size())
	order.sort_custom(func(x: int, y: int) -> bool: return p.distance_to(stations[x]) < p.distance_to(stations[y]))
	# Переходи пробуються лише до трьох найближчих станцій: далі ТП однаково не ставлять.
	for n in order.size():
		var i: int = order[n]
		var d: float = p.distance_to(stations[i])
		if d < 1.4 or (d <= MAX_04KV and _span_clear(p, stations[i], segs)) \
				or (n < 3 and d <= MAX_04KV * 2.0 and not _square_hop(probe, pi, i, segs).is_empty()):
			_reach_cache[p] = true
			return true
	return false


## Перехід через дорогу між станціями i і j, які розділяє вісь дороги: нова опора навпроти i з того боку (чи навпроти
## j з цього), проліт через дорогу прямо впоперек (PropLayer wire_ok), інший — уздовж узбіччя не довше за MAX_04KV. Ребра [i, q], [q, j]; порожній — не вийшло.
func _square_hop(stations: Array[Vector2], i: int, j: int, trunk_segs: Array) -> Array:
	var a: Vector2 = stations[i]
	var b: Vector2 = stations[j]
	var rc: Variant = _p.height.roads if _p.height != null else null
	if rc == null:
		return []
	for pts: PackedVector2Array in rc.lines:
		for k in range(1, pts.size()):
			var p0: Vector2 = pts[k - 1] - Vector2(_ring, _ring)
			var p1: Vector2 = pts[k] - Vector2(_ring, _ring)
			if p0 == p1 or Geometry2D.segment_intersects_segment(a, b, p0, p1) == null:
				continue
			var n: Vector2 = (p1 - p0).normalized().orthogonal()
			if n.dot(b - a) < 0.0:
				n = -n
			# Опора навпроти a з того боку, а коли там двір — навпроти b з цього боку.
			var t: Vector2 = (p1 - p0).normalized()
			# Нова опора c не впритул до наявної станції (як і решта опор — не ближче 1.4), проліт u–v через дорогу прямо.
			var square := func(u: Vector2, v: Vector2, c: Vector2) -> bool:
				return absf((v - u).normalized().dot(t)) <= SQUARE_SIN and stations.all(func(o: Vector2) -> bool: return o.distance_to(c) >= 1.4)
			var q: Vector2 = _snap(a + n * 2.0 * absf((a - p0).dot(n)), HOP_R, func(c: Vector2) -> bool:
				return c.distance_to(b) <= MAX_04KV and a.distance_to(c) <= MAX_04KV and c.distance_to(b) >= 1.4 and square.call(a, c, c) \
						and _span_clear(a, c, trunk_segs) and _span_clear(c, b, trunk_segs))
			if not q.is_finite():
				q = _snap(b - n * 2.0 * absf((b - p0).dot(n)), HOP_R, func(c: Vector2) -> bool:
					return c.distance_to(a) <= MAX_04KV and c.distance_to(b) <= MAX_04KV and c.distance_to(a) >= 1.4 and square.call(c, b, c) \
							and _span_clear(a, c, trunk_segs) and _span_clear(c, b, trunk_segs))
			if not q.is_finite():
				return []
			stations.append(q)
			var qi: int = stations.size() - 1
			return [[mini(i, qi), maxi(i, qi), 1.0], [mini(qi, j), maxi(qi, j), 1.0]]
	return []


## Проліт a–b не лягає на будівлю, не перетинає магістраль і як дріт можливий (PropLayer wire_ok: не крізь двори, не
## над грядками й будівлями з боку камери, через вулицю лише впоперек).
func _span_clear(a: Vector2, b: Vector2, trunk_segs: Array) -> bool:
	if _p.span_hits_building(a, b) or not _p.wire_ok(a, b, PropLayer.SPAN_CROSS):
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


## Найближча пара (станція дерева, станція поза деревом) не далі за BRIDGE_MAX; порожній — таких нема. Пара, між
## якою міст уже пробувався, вдруге не береться, а станція — пробується й від інших станцій дерева.
func _nearest_gap(stations: Array[Vector2], parent: Dictionary, bridged: Dictionary) -> Array:
	var best: float = BRIDGE_MAX
	var pick: Array = []
	for a: int in parent:
		for b in stations.size():
			if parent.has(b) or bridged.has(b) or bridged.has(Vector2i(a, b)):
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
