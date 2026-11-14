class_name TagPlacement
extends RefCounted
## Де стати тегу вибраного юніта (spec §2, «Unit tag placement rule»). Чисті прямокутники,
## відрізки й полігони в екранних dp: жодного вузла й жодного правила гри. Усе, що тег має
## обійти, приходить уже спроєктованим із видимих UnitView (фог, §3.5), тож тут немає шляху до
## невидимого юніта.
##
## Тверді перешкоди: чужі юніти (з їхніми позначками), хром HUD — кожне +8 dp; лінія вогню;
## полігони (клітинки цілей верби, призначення й шлях руху) +4 dp — для тега й для лідера.
## М'яка ціна: контури зон і дуги кілець під тегом (вага 1500), лідер, тіснота до чужих юнітів.
##
## shortcut: сітка позначок і полігонів — растр із кроком 4 dp (довжина контуру × 2 dp, а не
## точна геометрія перетину), бо точний перетин на тисячі кандидатів не вкладається в кадр;
## шукати точніше, якщо тег помітно сідає на 1–2 dp повз ребро контуру.

const LEAD_AT: float = 12.0
const MAX_LEAD: float = 60.0
const MIN_GAP: float = 8.0
const OBSTACLE_GROW: float = 8.0
const POLY_GROW: float = 4.0
const FIRE_GROW: float = 10.0
const LEADER_CLEAR: float = 4.0
const LABEL_CLEAR: float = 2.0
const CHROME_AIR: float = 16.0
const CORNER_COST: float = 400.0
const END_HALF: float = 2.5
const _STEP: float = 3.0
const MARK_WEIGHT: float = 1500.0
const DISTANCE_WEIGHT: float = 0.15
const LEADER_COST: float = 6.0
const CROWD_COST: float = 25.0
## Тег ближче до чужого юніта, ніж до свого: основа плюс вага за кожен dp, на який чужий ближче. Місце,
## де чужий лише трохи ближче, програє місцю без нього, але перемагає те, де тег читається підписом ворога.
const NEAR_OTHER_COST: float = 200.0
const NEAR_OTHER_PER_DP: float = 60.0
const CELL: float = 4.0
const LINE_WIDTH: float = 2.0
const _SAMPLES: int = 12
const END_CLEAR: float = 2.0
## Лінія лідера, що перетинає клітинку, дорожча за будь-яку чисту; кінець у клітинці — ще дорожчий.
const CROSS_COST: float = 400.0
const END_IN_CELL_COST: float = 2000.0
const CLEARANCE_CAP: float = 20.0
const CLEARANCE_WEIGHT: float = 10.0

var _lead_at: float = LEAD_AT
var _gaps: Array[float] = [8.0, 12.0]
## Який рівень послаблення дав останній best(): гістерезис мусить перевіряти збережений прямокутник тим самим.
var relax_used: int = 0
var _tag: Vector2
var _unit: Rect2
var _core: Rect2
var _core_poly: PackedVector2Array
var _label: Rect2 = Rect2()
var _chrome: Array[Rect2] = []
var _corners: PackedVector2Array = PackedVector2Array()
var _others: Array[Rect2]
var _blocked: Array[Rect2] = []
var _fire: PackedVector2Array
var _safe: Rect2
var _origin: Vector2
var _gw: int = 0
var _gh: int = 0
var _hard: PackedByteArray = PackedByteArray()
var _hard_sat: PackedInt32Array = PackedInt32Array()
## Ті самі полігони точно (без растру): лінія лідера — на 4 dp плюс пів-ширини лінії від клітинки, квадрат кінця — на
## півдіагоналі квадрата й ще 2 dp запасу. Растр із кроком 4 dp для лінії завгрубий: він закривав щілини між клітинками.
var _cells_raw: Array[PackedVector2Array] = []
## Полігони + 4 dp точно: растр із кроком 4 dp пропускає гострий кут клітинки, і тег міг сісти на нього.
var _cells_grown: Array[PackedVector2Array] = []
var _cells_line: Array[PackedVector2Array] = []
var _cells_end: Array[PackedVector2Array] = []
## Лідер залежить лише від точки t на краю тега, а різних t на сітці кандидатів у рази менше, ніж прямокутників.
var _leaders: Dictionary = {}
## Кінці лідера й їхня ціна, що не залежить від t (кінець у клітинці, запас від клітинок): рахуються раз.
var _ends: PackedVector2Array = PackedVector2Array()
var _ends_static: PackedFloat32Array = PackedFloat32Array()
var _mark_sat: PackedFloat32Array = PackedFloat32Array()


## scene: tag_size Vector2, unit Rect2 (модель ∪ смуга ∪ напис ∪ значок), core Rect2 (смуга + модель:
## куди дістає лідер), others Array[Rect2], chrome Array[Rect2], polys Array[PackedVector2Array],
## fire PackedVector2Array (0 або 2 точки), marks Array[PackedVector2Array] (ламані), screen Rect2.
func _init(scene: Dictionary) -> void:
	_tag = scene["tag_size"]
	_unit = scene["unit"]
	_core = scene.get("core", _unit)
	_core_poly = scene.get("core_poly", PackedVector2Array())
	# Напис HP рушій малює поверх верхнього краю смуги: кінець лідера мусить його обійти.
	_label = scene.get("label", Rect2()).grow(LABEL_CLEAR) if scene.get("label", Rect2()).size != Vector2.ZERO else Rect2()
	_others.assign(scene.get("others", []))
	_fire = scene.get("fire", PackedVector2Array())
	_safe = Rect2(scene["screen"]).grow_individual(-24.0, -8.0, -24.0, -8.0)
	for o: Rect2 in _others:
		_blocked.append(o.grow(OBSTACLE_GROW))
	for c: Rect2 in scene.get("chrome", []):
		_blocked.append(c.grow(OBSTACLE_GROW))
		_chrome.append(c)
	var window: Rect2 = _unit.grow_individual(_tag.x + 64.0, _tag.y + 64.0, _tag.x + 64.0, _tag.y + 64.0)
	_origin = (window.position / CELL).floor() * CELL
	_gw = int(ceil(window.size.x / CELL)) + 1
	_gh = int(ceil(window.size.y / CELL)) + 1
	for poly: PackedVector2Array in scene.get("polys", []):
		_cells_raw.append(poly)
		_cells_grown.append_array(Geometry2D.offset_polygon(poly, POLY_GROW, Geometry2D.JOIN_MITER))
		_cells_line.append_array(Geometry2D.offset_polygon(poly, POLY_GROW + LINE_WIDTH / 2.0, Geometry2D.JOIN_MITER))
		_cells_end.append_array(Geometry2D.offset_polygon(poly, sqrt(2.0) * END_HALF + END_CLEAR, Geometry2D.JOIN_MITER))
	_rasterise_polys(scene.get("polys", []))
	_rasterise_marks(scene.get("marks", []))


## relax: 0 — усі правила; 1 — лідер може перетнути клітинки дії (тег їх не накриває): верба інженера
## оточує модель чотирма клітинками, що сходяться в кутах, і лідер інакше не виходить нікуди;
## 2 — полігони не заважають зовсім. Чужі юніти, хром, лінія вогню й межі екрана — тверді завжди.
func is_legal(r: Rect2, relax: int = 0) -> bool:
	var d: float = _dist(r, _unit)
	if d < MIN_GAP or _dist(r, _core) > MAX_LEAD:
		return false
	if not _safe.encloses(r):
		return false
	for b: Rect2 in _blocked:
		if r.intersects(b):
			return false
	if _fire.size() == 2 and _segment_hits(_fire[0], _fire[1], r.grow(FIRE_GROW)):
		return false
	if relax < 2 and (_sat_sum_i(_hard_sat, r) > 0 or _hits_grown(r)):
		return false
	if d > _lead_at:
		var ends: PackedVector2Array = leader_points(r)
		if ends[0].distance_to(ends[1]) > MAX_LEAD:
			return false
		for i in _SAMPLES + 1:
			var p: Vector2 = ends[0].lerp(ends[1], float(i) / _SAMPLES)
			for o: Rect2 in _others:
				if o.grow(LEADER_CLEAR).has_point(p):
					return false
			# Лінія не проходить крізь власну смугу HP і модель: вона лише торкається їх краєм.
			if i < _SAMPLES - 1 and _core_poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, _core_poly):
				return false
		# Кінець лідера не лежить у клітинці й не торкається її ніколи; лінія не перетинає її на рівні 0.
		if relax < 2 and _in_any(ends[1], _cells_end):
			return false
		if relax < 1 and _crosses_cells(ends[0], ends[1]):
			return false
	else:
		# Тег без лідера мусить читатися як цього юніта: на 8 dp ближче за будь-якого іншого.
		for o: Rect2 in _others:
			if _dist(r, o) < d + 8.0:
				return false
	return true


func _hits_grown(r: Rect2) -> bool:
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for g in _cells_grown:
		if not Geometry2D.intersect_polygons(box, g).is_empty():
			return true
	return false


func needs_leader(r: Rect2) -> bool:
	return _dist(r, _unit) > _lead_at


## [від краю тега, до смуги+моделі юніта] — лідер: найдешевша точка контуру силуету (відстань + штрафи) або
## точка просто над написом HP. Штрафи: квадрат кінця на написі HP, лінія крізь напис, лінія крізь клітинку
## дії, кінець у клітинці. Найближча точка береться першою — вона чиста майже завжди.
func leader_points(r: Rect2) -> PackedVector2Array:
	var c: Vector2 = _core.get_center()
	var t := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	if not _leaders.has(t):
		_leaders[t] = _leader_from(t)
	return _leaders[t]


func _leader_from(t: Vector2) -> PackedVector2Array:
	var u := Vector2(clampf(t.x, _core.position.x, _core.end.x), clampf(t.y, _core.position.y, _core.end.y))
	var ring: PackedVector2Array = _ring()
	if _core_poly.size() >= 3:
		var best: float = INF
		for i in ring.size():
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(t, ring[i], ring[(i + 1) % ring.size()])
			if t.distance_squared_to(q) < best:
				best = t.distance_squared_to(q)
				u = q
	if _end_cost(t, u) == 0.0:
		return PackedVector2Array([t, u])
	if _ends.is_empty():
		_ends = _end_candidates(ring)
		_ends_static.resize(_ends.size())
		for i in _ends.size():
			_ends_static[i] = _static_cost(_ends[i])
	var best_cost: float = INF
	for i in _ends.size():
		var q: Vector2 = _ends[i]
		var d: float = t.distance_to(q)
		# Ціна не менша за відстань і статичну частину: далі шукати нема сенсу.
		if d + _ends_static[i] >= best_cost:
			continue
		var cost: float = d + _end_cost(t, q, _ends_static[i])
		if cost < best_cost:
			best_cost = cost
			u = q
	return PackedVector2Array([t, u])


func _ring() -> PackedVector2Array:
	if _core_poly.size() >= 3:
		return _core_poly
	return PackedVector2Array([_core.position, Vector2(_core.end.x, _core.position.y), _core.end, Vector2(_core.position.x, _core.end.y)])


## Точки контуру з кроком _STEP і ряд точок над написом HP: напис лежить на верхньому краї смуги,
## а клітинки верби закривають весь контур, окрім щілини саме над ним.
func _end_candidates(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var n: int = maxi(1, int(ceil(a.distance_to(b) / _STEP)))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	if _label.size != Vector2.ZERO:
		var y: float = _label.position.y - END_HALF - 1.0
		var x: float = _label.position.x
		while x <= _label.end.x:
			out.append(Vector2(x, y))
			x += _STEP
	return out


## Частина штрафу, що від тега не залежить: кінець у клітинці — найтяжчий — й відсутність запасу від клітинок.
func _static_cost(u: Vector2) -> float:
	if _cells_raw.is_empty():
		return 0.0
	return (END_IN_CELL_COST if _in_any(u, _cells_end) else 0.0) - CLEARANCE_WEIGHT * minf(_clearance(u), CLEARANCE_CAP)


## Штраф кінця лідера: квадрат на написі HP — найтяжчий, лінія крізь напис, клітинка дії — легші.
## static_cost < INF — уже пораховану статичну частину (кінці з кешу); INF — порахувати тут.
func _end_cost(t: Vector2, u: Vector2, static_cost: float = INF) -> float:
	var cost: float = 0.0
	if _label.size != Vector2.ZERO:
		if _label.intersects(Rect2(u - Vector2(END_HALF, END_HALF), Vector2(END_HALF, END_HALF) * 2.0)):
			cost += 1000.0
		elif _segment_hits(t, u, _label):
			cost += 500.0
	if _cells_raw.is_empty():
		return cost
	var st: float = _static_cost(u) if static_cost == INF else static_cost
	var in_cell: bool = st >= END_IN_CELL_COST - CLEARANCE_WEIGHT * CLEARANCE_CAP
	if in_cell:
		cost += END_IN_CELL_COST
	if _crosses_cells(t, u):
		# Лінія все одно крізь клітинку: хай кінець стоїть там, де від клітинок найдалі.
		cost += CROSS_COST + (st - (END_IN_CELL_COST if in_cell else 0.0))
	return cost


func _in_any(p: Vector2, polys: Array[PackedVector2Array]) -> bool:
	for g in polys:
		if Geometry2D.is_point_in_polygon(p, g):
			return true
	return false


func _crosses_cells(a: Vector2, b: Vector2) -> bool:
	var line := PackedVector2Array([a, b])
	for g in _cells_line:
		if Geometry2D.is_point_in_polygon(a, g) or Geometry2D.is_point_in_polygon(b, g) \
				or not Geometry2D.intersect_polyline_with_polygon(line, g).is_empty():
			return true
	return false


func _clearance(p: Vector2) -> float:
	var best: float = INF
	for g in _cells_raw:
		for i in g.size():
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, g[i], g[(i + 1) % g.size()])))
	return best


func score(r: Rect2) -> float:
	var d: float = _dist(r, _unit)
	var s: float = MARK_WEIGHT * minf(1.0, _sat_sum_f(_mark_sat, r) / maxf(1.0, r.size.x * r.size.y)) \
		+ DISTANCE_WEIGHT * d + (LEADER_COST if d > _lead_at else 0.0)
	for o: Rect2 in _others:
		if _dist(r, o) < 12.0:
			s += CROWD_COST
			break
	# Тег впритул до хрому читається другим рядом чипа, а не тегом юніта на дошці.
	for c: Rect2 in _chrome:
		if _dist(r, c) < CHROME_AIR:
			s += CROWD_COST
			break
	# Кут контуру під тегом ховає, де зона повертає.
	var grown: Rect2 = r.grow(2.0)
	for v in _corners:
		if grown.has_point(v):
			s += CORNER_COST
	if d > _lead_at:
		for o: Rect2 in _others:
			if _dist(r, o) < d + 8.0:
				s += CROWD_COST
				break
	# Тег ближче до чужого юніта, ніж до свого, читається як його підпис.
	var worst: float = 0.0
	for o: Rect2 in _others:
		worst = maxf(worst, d - _dist(r, o))
	if worst > 0.0:
		s += NEAR_OTHER_COST + NEAR_OTHER_PER_DP * worst
	return s


## Найкращий законний прямокутник або found=false (місця нема навіть без полігонів — тег ховається).
## Спершу всі правила, потім лідер крізь клітинки, потім тег без огляду на клітинки: AP юніта на
## екрані важливіший за чистоту контурів.
func best(relax: int = 0) -> Dictionary:
	var pick: Dictionary = {}
	for level in range(relax, 3):
		relax_used = level
		pick = _best(level)
		if pick["found"]:
			break
	return pick


func _best(relax: int) -> Dictionary:
	var best_rect := Rect2()
	var best_score: float = INF
	for r: Rect2 in _candidates():
		if not is_legal(r, relax):
			continue
		var s: float = score(r)
		if s < best_score:
			best_score = s
			best_rect = r
	return {"found": best_score < INF, "rect": best_rect, "leader": best_score < INF and needs_leader(best_rect)}


func _candidates() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var w: float = _tag.x
	var h: float = _tag.y
	var u: Rect2 = _unit
	# Збоку, без лідера: кожна сторона на 8 і 12 dp, ковзання в 11 кроків, плюс чотири кути.
	for gap: float in _gaps:
		for i in 11:
			var f: float = i / 10.0
			var cy: float = u.position.y + u.size.y * f
			var cx: float = u.position.x + u.size.x * f
			for p: Vector2 in [Vector2(u.position.x - gap - w, cy - h / 2.0), Vector2(u.end.x + gap, cy - h / 2.0),
					Vector2(cx - w / 2.0, u.position.y - gap - h), Vector2(cx - w / 2.0, u.end.y + gap),
					Vector2(u.position.x - w + 12.0, u.position.y - gap - h), Vector2(u.end.x - 12.0, u.position.y - gap - h),
					Vector2(u.position.x - w + 12.0, u.end.y + gap), Vector2(u.end.x - 12.0, u.end.y + gap)]:
				out.append(Rect2(p, _tag))
	# З лідером: будь-яка точка 4-dp сітки навколо юніта.
	var x0: int = roundi(u.position.x - w - MAX_LEAD)
	var x1: int = roundi(u.end.x + MAX_LEAD + 1.0)
	var y0: int = roundi(u.position.y - h - MAX_LEAD)
	var y1: int = roundi(u.end.y + MAX_LEAD + 1.0)
	for x in range(x0, x1, 4):
		for y in range(y0, y1, 4):
			var r := Rect2(x, y, w, h)
			# Дешевий відсів ще до повних перевірок: усередині 13 dp — це вже «збоку».
			if _dist(r, u) > _lead_at:
				out.append(r)
	return out


# --- Растр -----------------------------------------------------------------------

func _rasterise_polys(polys: Array) -> void:
	_hard.resize(_gw * _gh)
	_hard.fill(0)
	for poly: PackedVector2Array in polys:
		var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(poly, POLY_GROW, Geometry2D.JOIN_MITER)
		for g in grown:
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for v in g:
				lo = lo.min(v)
				hi = hi.max(v)
			var cx0: int = maxi(0, int(floor((lo.x - _origin.x) / CELL)))
			var cx1: int = mini(_gw - 1, int(floor((hi.x - _origin.x) / CELL)))
			var cy0: int = maxi(0, int(floor((lo.y - _origin.y) / CELL)))
			var cy1: int = mini(_gh - 1, int(floor((hi.y - _origin.y) / CELL)))
			for cy in range(cy0, cy1 + 1):
				for cx in range(cx0, cx1 + 1):
					if Geometry2D.is_point_in_polygon(_origin + Vector2(cx + 0.5, cy + 0.5) * CELL, g):
						_hard[cy * _gw + cx] = 1
	_hard_sat = _build_sat_i()


func _rasterise_marks(marks: Array) -> void:
	var grid := PackedFloat32Array()
	grid.resize(_gw * _gh)
	for line: PackedVector2Array in marks:
		for i in range(line.size() - 1):
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var steps: int = maxi(1, int(ceil(a.distance_to(b) / 2.0)))
			for s in steps:
				var p: Vector2 = a.lerp(b, (s + 0.5) / steps)
				var cx: int = int(floor((p.x - _origin.x) / CELL))
				var cy: int = int(floor((p.y - _origin.y) / CELL))
				if cx >= 0 and cx < _gw and cy >= 0 and cy < _gh:
					# Шматок довжиною ≈ 2 dp × ширина лінії.
					grid[cy * _gw + cx] += 2.0 * LINE_WIDTH
	_corners = _find_corners(marks)
	_mark_sat = PackedFloat32Array()
	_mark_sat.resize((_gw + 1) * (_gh + 1))
	for y in _gh:
		var run: float = 0.0
		for x in _gw:
			run += grid[y * _gw + x]
			_mark_sat[(y + 1) * (_gw + 1) + x + 1] = _mark_sat[y * (_gw + 1) + x + 1] + run


## Вершини контурів, де лінія повертає: у спільній точці двох відрізків напрямки не співнапрямлені.
## Ребра зони йдуть по клітинках, тож кожен відрізок — одне ребро, а не вся сторона.
static func _find_corners(marks: Array) -> PackedVector2Array:
	var seen: Dictionary = {}
	var out := PackedVector2Array()
	for line: PackedVector2Array in marks:
		for i in range(line.size() - 1):
			var d: Vector2 = (line[i + 1] - line[i]).normalized()
			for p: Vector2 in [line[i], line[i + 1]]:
				var key := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
				if seen.has(key):
					if absf((seen[key] as Vector2).cross(d)) > 0.3:
						out.append(p)
				else:
					seen[key] = d
	return out


func _build_sat_i() -> PackedInt32Array:
	var sat := PackedInt32Array()
	sat.resize((_gw + 1) * (_gh + 1))
	for y in _gh:
		var run: int = 0
		for x in _gw:
			run += _hard[y * _gw + x]
			sat[(y + 1) * (_gw + 1) + x + 1] = sat[y * (_gw + 1) + x + 1] + run
	return sat


func _cells(r: Rect2) -> Vector4i:
	return Vector4i(
		clampi(int(floor((r.position.x - _origin.x) / CELL)), 0, _gw),
		clampi(int(floor((r.position.y - _origin.y) / CELL)), 0, _gh),
		clampi(int(ceil((r.end.x - _origin.x) / CELL)), 0, _gw),
		clampi(int(ceil((r.end.y - _origin.y) / CELL)), 0, _gh))


func _sat_sum_i(sat: PackedInt32Array, r: Rect2) -> int:
	var c: Vector4i = _cells(r)
	var s: int = _gw + 1
	return sat[c.w * s + c.z] - sat[c.y * s + c.z] - sat[c.w * s + c.x] + sat[c.y * s + c.x]


func _sat_sum_f(sat: PackedFloat32Array, r: Rect2) -> float:
	var c: Vector4i = _cells(r)
	var s: int = _gw + 1
	return sat[c.w * s + c.z] - sat[c.y * s + c.z] - sat[c.w * s + c.x] + sat[c.y * s + c.x]


# --- Геометрія -------------------------------------------------------------------

static func _dist(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0)
	var dy: float = maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)


## Відрізок перетинає (чи лежить у) прямокутнику — Ліанг–Барськи.
static func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	for k in 4:
		var p: float = [-d.x, d.x, -d.y, d.y][k]
		var q: float = [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y][k]
		if p == 0.0:
			if q < 0.0:
				return false
		else:
			var t: float = q / p
			if p < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true
