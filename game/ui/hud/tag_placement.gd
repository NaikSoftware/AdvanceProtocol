class_name TagPlacement
extends RefCounted
## Де стати тегу вибраного юніта (docs/ui/hud.md#unit-tag-placement). Чисті прямокутники,
## відрізки й полігони в екранних dp: жодного вузла й жодного правила гри. Усе, що тег має
## обійти, приходить уже спроєктованим із видимих UnitView (фог, §3.5), тож тут немає шляху до
## невидимого юніта.
##
## Тверді перешкоди: чужі юніти (з їхніми позначками), хром HUD — кожне +8 dp; лінія вогню;
## полігони (клітинки цілей верби, призначення й шлях руху) +5 dp — для тега й для лідера.
## М'яка ціна: контури зон і дуги кілець під тегом (вага 1500), лідер, тіснота до чужих юнітів.
##
## shortcut: сітка позначок і полігонів — растр із кроком 4 dp (довжина контуру × 2 dp, а не
## точна геометрія перетину), бо точний перетин на тисячі кандидатів не вкладається в кадр;
## шукати точніше, якщо тег помітно сідає на 1–2 dp повз ребро контуру.
## shortcut: best() вибирає рівно те, що й повний перебір 4-dp сітки, але відсікає кандидатів за нижньою
## межею ціни; на десктопі це ~9 ms для танка на River. Інженер із клітинками верби коштує до ~55 ms: рівень 0
## там доводиться доводити порожнім, а кожна нова точка t рахує лідера (_leader_from) з перебором кінців.
## Пошук іде на виборі й на спокої камери, коли збережене місце накриває позначки, а не на кожному кадрі
## руху — тоді тег лише їде з юнітом. Прискорювати _leader_from далі, коли інженер стане помітним.

const LEAD_AT: float = 12.0
const MAX_LEAD: float = 60.0
const MIN_GAP: float = 8.0
const OBSTACLE_GROW: float = 8.0
const POLY_GROW: float = 5.0
const FIRE_GROW: float = 10.0
const LEADER_CLEAR: float = 4.0
const LABEL_CLEAR: float = 2.0
const CHROME_AIR: float = 16.0
const CORNER_COST: float = 1200.0
const CORNER_AIR: float = 4.0
## Будь-який дотик до контуру дорожчий за кілька десятків dp відстані: частка площі сама по собі
## ледь важить, а сегмент контуру під тегом ховає межу зони. Дорожчий за найдовший законний лідер
## (LONG_LEAD_PER_DP × (MAX_LEAD − LONG_LEAD_FROM) = 240): інакше довгий лідер програє накриттю контуру.
const TOUCH_COST: float = 300.0
## Лідер довший за 40 dp росте круто: чистий закуток поруч кращий за дальній.
const LONG_LEAD_FROM: float = 40.0
const LONG_LEAD_PER_DP: float = 12.0
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
## Тег, що і впритул до чужого юніта (< CROWD_AIR), і ближче до нього, ніж до свого, читається його підписом:
## дорожчий за будь-яке накриття контурів і кутів, тож лишається лише тоді, коли інакше місця нема.
const NEAR_OTHER_CROWDED_COST: float = 6000.0
const CROWD_AIR: float = 12.0
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
## Значок дрона: так само не місце для кінця лідера (запас END_CLEAR від квадрата).
var _icon: Rect2 = Rect2()
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
## Ті самі полігони точно (без растру): лінія лідера — на 5 dp плюс пів-ширини лінії від клітинки, квадрат кінця — на
## півдіагоналі квадрата й ще END_CLEAR (2 dp) запасу. Растр із кроком 4 dp для лінії завгрубий: він закривав щілини між клітинками.
var _cells_raw: Array[PackedVector2Array] = []
## Полігони + POLY_GROW точно: растр із кроком 4 dp пропускає гострий кут клітинки, і тег міг сісти на нього.
var _cells_grown: Array[PackedVector2Array] = []
var _cells_line: Array[PackedVector2Array] = []
## Охопні коробки _cells_grown і _cells_line: точний перетин полігонів дорогий, а переважна більшість кандидатів далеко.
var _grown_boxes: Array[Rect2] = []
var _line_boxes: Array[Rect2] = []
var _cells_end: Array[PackedVector2Array] = []
## Лідер залежить лише від точки t на краю тега, а різних t на сітці кандидатів у рази менше, ніж прямокутників.
var _leaders: Dictionary = {}
## Кінці лідера й їхня ціна, що не залежить від t (кінець у клітинці, запас від клітинок): рахуються раз.
var _ends: PackedVector2Array = PackedVector2Array()
var _ends_static: PackedFloat32Array = PackedFloat32Array()
var _ends_floor: PackedFloat32Array = PackedFloat32Array()
var _mark_sat: PackedFloat32Array = PackedFloat32Array()
const _NEVER: int = 1 << 30
var _leader_levels: Dictionary = {}
## Кандидати сцени й те, що best() про них уже знає: рівень і ціна від рівня пошуку не залежать, тож
## наступний рівень послаблення не рахує їх удруге.
var _cands: Array[Rect2] = []
var _lows: PackedFloat64Array = PackedFloat64Array()
var _lows_unled: PackedFloat64Array = PackedFloat64Array()
var _rect_levels: PackedInt32Array = PackedInt32Array()
var _levels: PackedInt32Array = PackedInt32Array()
var _scores: PackedFloat64Array = PackedFloat64Array()
var _end_box: Rect2 = Rect2()
## (нижня межа ціни × 64, заокруглена донизу) << _INDEX_BITS | номер кандидата, за зростанням.
var _order: PackedInt64Array = PackedInt64Array()
var _prepared: bool = false
const _INDEX_BITS: int = 24


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
	var icon: Rect2 = scene.get("icon", Rect2())
	_icon = icon.grow(LABEL_CLEAR) if icon.size != Vector2.ZERO else Rect2()
	_others.assign(scene.get("others", []))
	_fire = scene.get("fire", PackedVector2Array())
	_safe = Rect2(scene["screen"]).grow_individual(-24.0, -8.0, -24.0, -8.0)
	for o: Rect2 in _others:
		_blocked.append(o.grow(OBSTACLE_GROW))
	for c: Rect2 in scene.get("chrome", []):
		_blocked.append(c.grow(OBSTACLE_GROW))
		_chrome.append(c)
	# Растр питають лише про прямокутники в безпечній зоні (законний тег лежить у ній): коробка юніта, що
	# в перспективі розлетілась за кадр, інакше дала б растр на тисячі dp.
	var window: Rect2 = _unit.grow_individual(_tag.x + 64.0, _tag.y + 64.0, _tag.x + 64.0, _tag.y + 64.0).intersection(_safe)
	_origin = (window.position / CELL).floor() * CELL
	_gw = int(ceil(window.size.x / CELL)) + 1
	_gh = int(ceil(window.size.y / CELL)) + 1
	for poly: PackedVector2Array in scene.get("polys", []):
		_cells_raw.append(poly)
		_cells_grown.append_array(Geometry2D.offset_polygon(poly, POLY_GROW, Geometry2D.JOIN_MITER))
		_cells_line.append_array(Geometry2D.offset_polygon(poly, POLY_GROW + LINE_WIDTH / 2.0, Geometry2D.JOIN_MITER))
		_cells_end.append_array(Geometry2D.offset_polygon(poly, sqrt(2.0) * END_HALF + END_CLEAR, Geometry2D.JOIN_MITER))
	for g in _cells_grown:
		_grown_boxes.append(_bounds(g))
	for g in _cells_line:
		_line_boxes.append(_bounds(g))
	_rasterise_polys(scene.get("polys", []))
	_rasterise_marks(scene.get("marks", []))


## relax: 0 — усі правила; 1 — лідер може перетнути клітинки дії (тег їх не накриває): верба інженера
## оточує модель чотирма клітинками, що сходяться в кутах, і лідер інакше не виходить нікуди;
## 2 — полігони не заважають зовсім. Чужі юніти, хром, лінія вогню й межі екрана — тверді завжди.
func is_legal(r: Rect2, relax: int = 0) -> bool:
	return _level(r) <= relax


## Найнижчий рівень послаблення, на якому r законне; _NEVER — не законне на жодному.
func _level(r: Rect2) -> int:
	var level: int = _rect_level(r)
	if level == _NEVER or not needs_leader(r):
		return level
	return maxi(level, _leader_level(leader_points(r)))


## Усе, крім лідера: лідер коштує найдорожче, тож його не рахують, коли прямокутник уже не проходить.
func _rect_level(r: Rect2) -> int:
	var d: float = _dist(r, _unit)
	var dc: float = _dist(r, _core)
	if d < MIN_GAP or dc > MAX_LEAD:
		return _NEVER
	if not _safe.encloses(r):
		return _NEVER
	for b: Rect2 in _blocked:
		if r.intersects(b):
			return _NEVER
	if _fire.size() == 2 and _segment_hits(_fire[0], _fire[1], r.grow(FIRE_GROW)):
		return _NEVER
	if dc <= _lead_at:
		# Тег без лідера мусить читатися як цього юніта: на 8 dp ближче за будь-якого іншого.
		for o: Rect2 in _others:
			if _dist(r, o) < d + 8.0:
				return _NEVER
	return 2 if _sat_sum_i(_hard_sat, r) > 0 or _hits_grown(r) else 0


## Законність лідера залежить лише від його кінців, а ті — від точки t: рахується раз на t, а не на кожен
## прямокутник сітки.
func _leader_level(ends: PackedVector2Array) -> int:
	if _leader_levels.has(ends[0]):
		return _leader_levels[ends[0]]
	var level: int = _NEVER
	if ends[0].distance_to(ends[1]) <= MAX_LEAD and _leader_clear(ends[0], ends[1]):
		# Кінець лідера не лежить у клітинці й не торкається її ніколи; лінія не перетинає її на рівні 0.
		level = 2 if _in_any(ends[1], _cells_end) else (1 if _crosses_cells(ends[0], ends[1]) else 0)
	_leader_levels[ends[0]] = level
	return level


func _leader_clear(a: Vector2, b: Vector2) -> bool:
	for i in _SAMPLES + 1:
		var p: Vector2 = a.lerp(b, float(i) / _SAMPLES)
		for o: Rect2 in _others:
			if o.grow(LEADER_CLEAR).has_point(p):
				return false
		# Лінія не проходить крізь власну смугу HP і модель: вона лише торкається їх краєм.
		if i < _SAMPLES - 1 and _core_poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, _core_poly):
			return false
	return true


func _hits_grown(r: Rect2) -> bool:
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for i in _cells_grown.size():
		if _grown_boxes[i].intersects(r) and not Geometry2D.intersect_polygons(box, _cells_grown[i]).is_empty():
			return true
	return false


static func _bounds(g: PackedVector2Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in g:
		lo = lo.min(v)
		hi = hi.max(v)
	return Rect2(lo, hi - lo)


## Відстань міряється до моделі зі смугою (куди дістає лідер), а не до напису й значка: інакше тег
## на 13 dp від моделі лишався б без лідера й читався б відірваним.
func needs_leader(r: Rect2) -> bool:
	return _dist(r, _core) > _lead_at


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
		_ends_floor.resize(_ends.size())
		for i in _ends.size():
			_ends_static[i] = _static_cost(_ends[i])
			_ends_floor[i] = END_IN_CELL_COST if _ends_static[i] >= END_IN_CELL_COST - CLEARANCE_WEIGHT * CLEARANCE_CAP else 0.0
	# Ціна кінця = відстань + штрафи, а штрафи — це напис, кінець у клітинці й перетин (не менше 200 dp). Нижня межа без
	# перетину й напису — відстань плюс «кінець у клітинці»: вона ближча до ціни, ніж межа зі статичною частиною (та сягає
	# −200 dp), тож перетини лінії з клітинками рахуються лише для кількох найближчих кінців. Старий порядок
	# (відстань + статична частина, потім номер) лишається за розв'язання нічиїх: виграє перший у ньому.
	var n: int = _ends.size()
	var lows := PackedFloat64Array()
	var olds := PackedFloat64Array()
	var keys := PackedInt64Array()
	lows.resize(n)
	olds.resize(n)
	keys.resize(n)
	for i in n:
		var d: float = t.distance_to(_ends[i])
		lows[i] = d + _ends_floor[i]
		olds[i] = d + _ends_static[i]
		keys[i] = (int(floor(lows[i] * 64.0)) << _INDEX_BITS) | i
	keys.sort()
	var best_cost: float = INF
	var best_old: float = INF
	var best_i: int = n
	for key: int in keys:
		if float(key >> _INDEX_BITS) / 64.0 > best_cost:
			break
		var i: int = key & ((1 << _INDEX_BITS) - 1)
		if lows[i] > best_cost:
			continue
		var q: Vector2 = _ends[i]
		var cost: float = t.distance_to(q) + _end_cost(t, q, _ends_static[i])
		if cost < best_cost or (cost == best_cost and (olds[i] < best_old or (olds[i] == best_old and i < best_i))):
			best_cost = cost
			best_old = olds[i]
			best_i = i
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
	var square := Rect2(u - Vector2(END_HALF, END_HALF), Vector2(END_HALF, END_HALF) * 2.0)
	if _label.size != Vector2.ZERO:
		cost += _avoid_cost(t, u, square, _label)
	if _icon.size != Vector2.ZERO:
		cost += _avoid_cost(t, u, square, _icon)
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


## Квадрат кінця на написі чи значку — 1000, лінія крізь нього — 500.
func _avoid_cost(t: Vector2, u: Vector2, square: Rect2, avoid: Rect2) -> float:
	if avoid.intersects(square):
		return 1000.0
	return 500.0 if _segment_hits(t, u, avoid) else 0.0


func _in_any(p: Vector2, polys: Array[PackedVector2Array]) -> bool:
	for g in polys:
		if Geometry2D.is_point_in_polygon(p, g):
			return true
	return false


func _crosses_cells(a: Vector2, b: Vector2) -> bool:
	var line := PackedVector2Array([a, b])
	var seg: Rect2 = Rect2(a, Vector2.ZERO).expand(b).grow(0.01)
	for i in _cells_line.size():
		if not _line_boxes[i].intersects(seg):
			continue
		var g: PackedVector2Array = _cells_line[i]
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


## Частка прямокутника під контурами зон і дугами кілець (0..1): за нею гістерезис відрізняє збережене
## місце, що накриває позначки, від чистого. Растр покриває лише безпечну зону навколо юніта: і ця частка, і score()
## правдиві лише для прямокутника, що може бути законним, — у безпечній зоні й не далі MAX_LEAD від юніта.
## Поза цим растр обрізає край, і значення відрізняється.
func mark_cover(r: Rect2) -> float:
	return minf(1.0, _sat_sum_f(_mark_sat, r) / maxf(1.0, r.size.x * r.size.y))


func score(r: Rect2) -> float:
	var lead_len: float = 0.0
	if needs_leader(r):
		var ends: PackedVector2Array = leader_points(r)
		lead_len = ends[0].distance_to(ends[1])
	return _score(r, lead_len)


## Ціна з даною довжиною лідера: вона входить лише в один доданок, що росте з нею, тож коротша довжина
## дає нижню межу тієї самої ціни.
func _score(r: Rect2, lead_len: float) -> float:
	var d: float = _dist(r, _unit)
	var lead: bool = needs_leader(r)
	var s: float = _base_cost(mark_cover(r), d, lead)
	if lead:
		s += LONG_LEAD_PER_DP * maxf(0.0, lead_len - LONG_LEAD_FROM)
	# Відстані до чужих — раз: їх питають три доданки нижче.
	var ods := PackedFloat64Array()
	for o: Rect2 in _others:
		ods.append(_dist(r, o))
	for od: float in ods:
		if od < 12.0:
			s += CROWD_COST
			break
	# Тег впритул до хрому читається другим рядом чипа, а не тегом юніта на дошці.
	for c: Rect2 in _chrome:
		if _dist(r, c) < CHROME_AIR:
			s += CROWD_COST
			break
	# Кут контуру під тегом ховає, де зона повертає.
	var grown: Rect2 = r.grow(CORNER_AIR)
	for v in _corners:
		if grown.has_point(v):
			s += CORNER_COST
	if lead:
		for od: float in ods:
			if od < d + 8.0:
				s += CROWD_COST
				break
	# Тег ближче до чужого юніта, ніж до свого, читається як його підпис.
	var worst: float = 0.0
	for od: float in ods:
		worst = maxf(worst, d - od)
		if od < CROWD_AIR and od < d:
			s += NEAR_OTHER_CROWDED_COST
			break
	if worst > 0.0:
		s += NEAR_OTHER_COST + NEAR_OTHER_PER_DP * worst
	return s


## Перші доданки score(): дешеві, а решта ціни лише додає до них, тож це й нижня межа ціни для відсіву.
func _base_cost(cover: float, d: float, lead: bool) -> float:
	return MARK_WEIGHT * cover + (TOUCH_COST if cover > 0.0 else 0.0) + DISTANCE_WEIGHT * d + (LEADER_COST if lead else 0.0)


## Найкращий законний прямокутник або found=false (місця нема навіть без полігонів — тег ховається).
## Спершу всі правила, потім лідер крізь клітинки, потім тег без огляду на клітинки: видимий тег
## важливіший за чисті контури.
func best(relax: int = 0) -> Dictionary:
	if not _prepared:
		_prepare()
	var pick: Dictionary = {}
	# Без полігонів рівні послаблення нічого не міняють: один прохід замість трьох однакових.
	for level in range(relax, relax + 1 if _cells_raw.is_empty() else 3):
		relax_used = level
		pick = _best(level)
		if pick["found"]:
			break
	return pick


## Кандидати за зростанням нижньої межі ціни: щойно межа перевищила найкращу знайдену ціну, решта не
## виграє, і дорогі перевірки законності й ціни бачать десятки кандидатів, а не тисячі.
func _prepare() -> void:
	_prepared = true
	_build()
	var n: int = _cands.size()
	_lows_unled.resize(n)
	_lows_unled.fill(-1.0)
	_scores.resize(n)
	_scores.fill(-1.0)
	_levels.resize(n)
	_levels.fill(-1)
	_order.resize(n)
	for i in n:
		_order[i] = (int(floor(_lows[i] * 64.0)) << _INDEX_BITS) | i
	_order.sort()
	# Кінець лідера лежить на контурі силуету (чи коробці смуги й моделі) або в ряду над написом HP.
	_end_box = _bounds(_ring())
	if _label.size != Vector2.ZERO:
		_end_box = _end_box.expand(Vector2(_label.position.x, _label.position.y - END_HALF - 1.0)).expand(Vector2(_label.end.x, _label.position.y - END_HALF - 1.0))


## Те саме, що перебір усіх кандидатів у їхньому порядку зі строгим «<»: за рівної ціни виграє менший номер.
## Кожен кандидат проходить дедалі дорожчі сходинки — прямокутник, межа ціни без лідера, лідер, ціна —
## і випадає на першій, що вже його відкидає.
func _best(relax: int) -> Dictionary:
	var best_i: int = -1
	var best_score: float = INF
	for key: int in _order:
		if float(key >> _INDEX_BITS) / 64.0 > best_score:
			break
		var i: int = key & ((1 << _INDEX_BITS) - 1)
		if _loses(_lows[i], i, best_score, best_i):
			continue
		var r: Rect2 = _cands[i]
		if _rect_levels[i] < 0:
			_rect_levels[i] = _rect_level(r)
		if _rect_levels[i] > relax:
			continue
		if best_i >= 0:
			if _lows_unled[i] < 0.0:
				# Лідер не коротший за відстань від тега до коробки його кінців; 0,01 dp — запас на
				# заокруглення float32 у самій довжині.
				_lows_unled[i] = _score(r, maxf(0.0, _dist(r, _end_box) - 0.01))
			if _loses(_lows_unled[i], i, best_score, best_i):
				continue
		if _levels[i] < 0:
			_levels[i] = _rect_levels[i] if not needs_leader(r) else maxi(_rect_levels[i], _leader_level(leader_points(r)))
		if _levels[i] > relax:
			continue
		if _scores[i] < 0.0:
			_scores[i] = score(r)
		if _scores[i] < best_score or (_scores[i] == best_score and i < best_i):
			best_score = _scores[i]
			best_i = i
	var found: bool = best_i >= 0
	var best_rect: Rect2 = _cands[best_i] if found else Rect2()
	return {"found": found, "rect": best_rect, "leader": found and needs_leader(best_rect)}


## Кандидат i з нижньою межею ціни low уже не виграє: ціна не менша за межу, а за рівної виграє менший номер.
static func _loses(low: float, i: int, best_score: float, best_i: int) -> bool:
	return low > best_score or (low == best_score and i > best_i)


## Кандидати, що можуть бути законними, у порядку повного перебору, і нижня межа ціни кожного. Відкинуто
## те, що is_legal() не пропустив би на жодному рівні: ближче MIN_GAP, далі MAX_LEAD, поза безпечною зоною,
## на чужому юніті чи хромі. Для сітки ці умови розпадаються на стовпчик і рядок, тож рахуються раз на
## стовпчик і раз на рядок, а не на кожен із тисяч вузлів.
func _build() -> void:
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
				var r := Rect2(p, _tag)
				var d: float = _dist(r, _unit)
				var dc: float = _dist(r, _core)
				if d >= MIN_GAP and dc <= MAX_LEAD and _safe.encloses(r) and not _on_blocked(r):
					_add(r, d, dc > _lead_at)
	# З лідером: будь-яка точка 4-dp сітки навколо юніта; межі — ті самі вузли x0 + 4k, обрізані до безпечної
	# зони із запасом у вузол (точний відсів — у таблицях нижче).
	var x0: int = roundi(u.position.x - w - MAX_LEAD)
	var y0: int = roundi(u.position.y - h - MAX_LEAD)
	var xs: int = x0 + 4 * maxi(0, floori((_safe.position.x - x0) / 4.0))
	var ys: int = y0 + 4 * maxi(0, floori((_safe.position.y - y0) / 4.0))
	var x1: int = mini(roundi(u.end.x + MAX_LEAD + 1.0), ceili(_safe.end.x - w) + 4)
	var y1: int = mini(roundi(u.end.y + MAX_LEAD + 1.0), ceili(_safe.end.y - h) + 4)
	var cols: Dictionary = _axis_table(range(xs, x1, 4), 0, w)
	var rows: Dictionary = _axis_table(range(ys, y1, 4), 1, h)
	var col_at: PackedInt32Array = cols["at"]
	var row_at: PackedInt32Array = rows["at"]
	var col_mask: PackedInt64Array = cols["mask"]
	var row_mask: PackedInt64Array = rows["mask"]
	var col_core: PackedFloat64Array = cols["core"]
	var row_core: PackedFloat64Array = rows["core"]
	var col_unit: PackedFloat64Array = cols["unit"]
	var row_unit: PackedFloat64Array = rows["unit"]
	# Вузол сітки вже пройшов усе, що _rect_level() перевіряє, окрім лінії вогню й полігонів; без них він законний.
	var known: int = 0 if _blocked.size() <= 62 and _fire.size() != 2 and _cells_raw.is_empty() else -1
	for ci in col_at.size():
		for ri in row_at.size():
			if col_mask[ci] & row_mask[ri] != 0:
				continue
			# Той самий вираз, що в _dist(): значення збігаються до біта.
			var dc: float = sqrt(col_core[ci] * col_core[ci] + row_core[ri] * row_core[ri])
			# Усередині 13 dp — це вже «збоку».
			if dc <= _lead_at or dc > MAX_LEAD:
				continue
			var d: float = sqrt(col_unit[ci] * col_unit[ci] + row_unit[ri] * row_unit[ri])
			if d >= MIN_GAP:
				_add(Rect2(col_at[ci], row_at[ri], w, h), d, true, known)


## Для кожного вузла осі (axis 0 — x, 1 — y) з розміром тега extent: чи лежить він у безпечній зоні, відстані
## по цій осі до юніта й до core (як у _dist()) і маска чужих коробок і хрому, які він перекриває по цій
## осі (як у Rect2.intersects()). Вузли поза безпечною зоною не потрапляють у таблицю.
func _axis_table(at: Array, axis: int, extent: float) -> Dictionary:
	var nodes := PackedInt32Array()
	var unit_gap := PackedFloat64Array()
	var core_gap := PackedFloat64Array()
	var masks := PackedInt64Array()
	# Маска на 62 коробки; більше їх на екрані не буває, а як буде — відсіє _rect_level().
	var masked: bool = _blocked.size() <= 62
	for v: int in at:
		var r := Rect2(v, v, extent, extent)
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if lo < _safe.position[axis] or hi > _safe.end[axis]:
			continue
		nodes.append(v)
		unit_gap.append(maxf(maxf(_unit.position[axis] - hi, lo - _unit.end[axis]), 0.0))
		core_gap.append(maxf(maxf(_core.position[axis] - hi, lo - _core.end[axis]), 0.0))
		var mask: int = 0
		if masked:
			for k in _blocked.size():
				if not (lo >= _blocked[k].end[axis] or hi <= _blocked[k].position[axis]):
					mask |= 1 << k
		masks.append(mask)
	return {"at": nodes, "unit": unit_gap, "core": core_gap, "mask": masks}


func _on_blocked(r: Rect2) -> bool:
	for b: Rect2 in _blocked:
		if r.intersects(b):
			return true
	return false


## rect_level: уже відомий рівень _rect_level() або -1 — порахувати, коли знадобиться.
func _add(r: Rect2, d: float, lead: bool, rect_level: int = -1) -> void:
	_cands.append(r)
	_lows.append(_base_cost(mark_cover(r), d, lead))
	_rect_levels.append(rect_level)


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
	var grid_box := Rect2(_origin, Vector2(_gw, _gh) * CELL)
	for line: PackedVector2Array in marks:
		for i in range(line.size() - 1):
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			# Відрізок повз растр не лишає в ньому жодної точки; ребра за кадром бувають довжиною в тисячі dp.
			if not Rect2(a, Vector2.ZERO).expand(b).intersects(grid_box, true):
				continue
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
	# Чотири півплощини, розгорнуті без масивів: цей виклик іде на кожен кінець лідера.
	var p: float = -d.x
	var q: float = a.x - r.position.x
	for k in 4:
		if k == 1:
			p = d.x
			q = r.end.x - a.x
		elif k == 2:
			p = -d.y
			q = a.y - r.position.y
		elif k == 3:
			p = d.y
			q = r.end.y - a.y
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
