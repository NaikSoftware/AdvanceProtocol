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
## Запасний поріг «без лідера»: коли довкола юніта нема місця ні для чого суворішого (верба інженера: чотири
## клітинки охоплюють модель, лідер з жодного боку їх не оминає), тег стає збоку далі, але без лідера.
const LEAD_AT_WIDE: float = 32.0
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
const NEAR_OTHER_COST: float = 2000.0
const CELL: float = 4.0
const LINE_WIDTH: float = 2.0
const _SAMPLES: int = 12

var _lead_at: float = LEAD_AT
var _gaps: Array[float] = [8.0, 12.0]
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
	_rasterise_polys(scene.get("polys", []))
	_rasterise_marks(scene.get("marks", []))


## relax: 0 — усі правила; 2 — полігони не заважають зовсім (лише для тестів і діагностики). Лідер
## ніколи не перетинає клітинок дії і не кінчається в них: квадрат кінця читався б як мітка на клітинці.
## Чужі юніти, хром, лінія вогню й межі екрана — тверді завжди.
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
	if relax < 2 and _sat_sum_i(_hard_sat, r) > 0:
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
			if relax < 2 and _hard_at(p):
				return false
			# Лінія не проходить крізь власну смугу HP і модель: вона лише торкається їх краєм.
			if i < _SAMPLES - 1 and _core_poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, _core_poly):
				return false
	else:
		# Тег без лідера мусить читатися як цього юніта: на 8 dp ближче за будь-якого іншого.
		for o: Rect2 in _others:
			if _dist(r, o) < d + 8.0:
				return false
	return true


func needs_leader(r: Rect2) -> bool:
	return _dist(r, _unit) > _lead_at


## [від краю тега, до смуги+моделі юніта] — лідер: найближча точка силуету, але квадрат кінця 5×5
## не лягає на напис HP (і не на клітинку дії, якщо є вибір), а лінія не січе напис.
func leader_points(r: Rect2) -> PackedVector2Array:
	var c: Vector2 = _core.get_center()
	var t := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	var u := Vector2(clampf(t.x, _core.position.x, _core.end.x), clampf(t.y, _core.position.y, _core.end.y))
	var ring: PackedVector2Array = _core_poly if _core_poly.size() >= 3 else PackedVector2Array(
		[_core.position, Vector2(_core.end.x, _core.position.y), _core.end, Vector2(_core.position.x, _core.end.y)])
	if _core_poly.size() >= 3:
		var best: float = INF
		for i in ring.size():
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(t, ring[i], ring[(i + 1) % ring.size()])
			if t.distance_squared_to(q) < best:
				best = t.distance_squared_to(q)
				u = q
	if _end_cost(t, u) == 0.0:
		return PackedVector2Array([t, u])
	# Найближча точка погана: перебір точок контуру з кроком _STEP за ціною «відстань + штрафи».
	var best_cost: float = INF
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var n: int = maxi(1, int(ceil(a.distance_to(b) / _STEP)))
		for k in n:
			var q: Vector2 = a.lerp(b, float(k) / n)
			var cost: float = t.distance_to(q) + _end_cost(t, q)
			if cost < best_cost:
				best_cost = cost
				u = q
	return PackedVector2Array([t, u])


## Штраф кінця лідера: квадрат на написі HP — найтяжчий, лінія крізь напис, клітинка дії — легші.
func _end_cost(t: Vector2, u: Vector2) -> float:
	var cost: float = 0.0
	if _label.size != Vector2.ZERO:
		if _label.intersects(Rect2(u - Vector2(END_HALF, END_HALF), Vector2(END_HALF, END_HALF) * 2.0)):
			cost += 1000.0
		elif _segment_hits(t, u, _label):
			cost += 500.0
	if _hard_at(u):
		cost += 400.0
	return cost


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
	for o: Rect2 in _others:
		if _dist(r, o) < d:
			s += NEAR_OTHER_COST
			break
	return s


## Найкращий законний прямокутник або Rect2() із found=false (місця нема — тег ховається).
func best(relax: int = 0) -> Dictionary:
	var pick: Dictionary = _best(relax)
	if not pick["found"] and _lead_at == LEAD_AT:
		_lead_at = LEAD_AT_WIDE
		_gaps = [8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0]
		pick = _best(relax)
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


func _hard_at(p: Vector2) -> bool:
	var cx: int = int(floor((p.x - _origin.x) / CELL))
	var cy: int = int(floor((p.y - _origin.y) / CELL))
	return cx >= 0 and cx < _gw and cy >= 0 and cy < _gh and _hard[cy * _gw + cx] != 0


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
