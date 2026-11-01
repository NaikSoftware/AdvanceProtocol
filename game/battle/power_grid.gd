class_name PowerGrid
extends RefCounted
## Мережа ЛЕП, яку гра будує сама й однаково щоразу (без збережених точок):
## - кожна лінія — прямі відрізки вздовж осей карти (x чи z) з поворотами лише під прямим кутом і опорою на
##   кожному куті; за вигином дороги лінія не йде, на діагональній дорозі — сходинками. Під іншим кутом іде лише
##   відвід до хати;
## - 10 кВ іде за намірами routes макета вздовж головних доріг (_trunk, _lay), стовпи через ≤ MAX_10KV клітинок, від
##   краю світу до краю чи до ТП — посеред поля не обривається (_trim_dead_ends);
## - у кожного поселення (хати, зв'язані кроком SETTLEMENT_R) — одна ТП на стовпі 10 кВ, найближчому до хат, від якого
##   вдається провести лінію; ТП ближче за TP_GAP одна до одної — спільна;
## - 0.4 кВ — дерево від ТП (_grow): до кожної хати, до якої ще жодна опора не дістає відводом, — найкоротший шлях
##   сходинками узбіччям (_path) до місця, звідки відвід можливий (_drop_spots); опори через ≤ MAX_04KV, не ближче
##   POLE_GAP, щонайбільше MAX_SPANS прольотів на опорі, без перетинів. Лишаються гілки до хат із відводом, а в
##   поселенні з кількох хат, де всі відводи дістали прямо з ТП, — ще й перша гілка до опори навпроти хати: у
##   поселення своя лінія вулицею, кінець якої стоїть перед хатою;
## - відвід — лише коротким прольотом від опори поряд (PropLayer drop_ok: через вулицю лише впоперек, не чужим двором,
##   не над грядками); з досяжних хат села кожна SKIP_ONE_IN-а лишається без відводу.
## Стовп стоїть лише там, де йому місце (pole_spot_ok, CENTRE_CLEAR): пряма відходить від дороги цілою, а не
## зсуває окрему опору навскіс.
## Результат: lines — ламані з опор (kind, points), transformers — точки підстанцій, fed і skipped — хати з відводом
## і без нього, хоч опора й дістала б.

## Пряма лінії біля дороги — на стільки клітинок від її осі (узбіччя за краєм асфальту).
const VERGE: float = 0.9
## Найдовший проліт, клітинки: 0.4 кВ і 10 кВ; проміжні стовпи магістралі — через TRUNK_GAP.
const MAX_04KV: float = 5.0
const MAX_10KV: float = 9.0
const TRUNK_GAP: float = 7.5
## Межі пошуку, щоб будова карти не дорожчала від хат, до яких не дійти: скільки пошуків шляху на одну гілку
## (BRIDGE_TRIES), скільки гілок на все село (BRIDGE_BUDGET) і скільки кандидатів ТП пробуємо (TP_PROBES).
const BRIDGE_TRIES: int = 6
const TP_PROBES: int = 40
## Пошуків шляху від кандидата ТП до хат: невдалий кандидат не вартий повного перебору — є наступний.
const TP_TRIES: int = 2
const BRIDGE_BUDGET: int = 40
## Найбільше прольотів на опорі 0.4 кВ (відводи не лічаться); на ТП — два прольоти 10 кВ і до MAX_SPANS − 1 прольотів 0.4 кВ.
const MAX_SPANS: int = 3
## Кожна така за ліком досяжна хата села (за хешем) лишається без відводу.
const SKIP_ONE_IN: int = 3
## Гілка до хати починається з опори дерева не далі за стільки клітинок від хати.
const BRIDGE_MAX: float = 12.0
## Дві ТП ближче за стільки клітинок — одна: друге село підключається до наявної.
const TP_GAP: float = 6.0
## Найдовша пряма гілки між двома поворотами, клітинки (довша — з проміжними опорами).
const BRIDGE_CHAIN_MAX: float = 12.0
## Проліт лежить уздовж осі карти, коли поперечний зсув кінців не більший за стільки клітинок.
const AXIS_EPS: float = 0.02
## Наскільки пряма магістралі може відійти від наміченої (VERGE від осі дороги), клітинки: до дороги й за неї, на
## другий бік (SHIFT_IN), і від неї в поле (SHIFT_OUT) — обійти хату, бази гравців чи ліс.
const SHIFT_IN: float = 2.2
const SHIFT_OUT: float = 3.0
## Напрям дороги в точці — за точками осі на стільки кроків (0.2 клітинки) вперед і назад; прямий відрізок, коротший
## за MIN_PIECE клітинок, — лише вигин, а не сходинка: він приєднується до сусіднього.
const DIR_WINDOW: int = 5
const MIN_PIECE: float = 1.0
## Кінцева опора всередині світу може відійти вздовж лінії до стількох клітинок.
const END_WIDE: float = 3.0
## Скільки інших координат пробує попередня пряма, коли з наступною нема кута чи цілого відрізка.
const BACKTRACK: int = 12
## Шлях сходинками (_path): запас рамки навколо місць біля хати й найближчої опори, клітинки; ціна повороту й
## множник ціни дроту далі за клітинку від асфальту, у клітинках шляху; синус 25° —
## найбільший відхил переходу через дорогу від прямого кута (як PropLayer.DROP_CROSS_COS).
const ROUTE_MARGIN: float = 2.0
const TURN_COST: float = 2.0
const FIELD_COST: float = 1.5
const SQUARE_SIN: float = 0.423
## Скільки місць опори з відводом біля хати пробує дерево.
const DROP_SPOTS: int = 6
## Скільки найближчих до хати придатних місць зважує вибір місць із відводом.
const DROP_SCAN: int = 24
## Опора відступає від центру клітинки хоч за однією віссю щонайменше на стільки (клітинки) і на кільці теж: стоїть
## біля межі клітинок, а не посеред місця, де міг би стояти юніт (PropLayer clear_of_centre, сторож у тесті).
const CENTRE_CLEAR: float = 0.45
## Найменша відстань між двома опорами, клітинки: 1.4 за правилом і запас на округлення місця до 0.01.
const POLE_GAP: float = 1.41
## Кінець відгалуження 0.4 кВ не ближче за стільки до магістралі: інакше він лише дублює її біля хати, а лінії
## замикають навколо поля кільце, схоже на павутину.
const LEAF_CLEAR: float = 1.5

var _p: PropLayer._Placer
## Опори, ближче за 1.4 до яких нових не ставимо: стовпи магістралі й уже побудованих сіл.
var _avoid: Array[Vector2] = []
var _ring: int = 0
var _spot_cache: Dictionary = {}
## Місце -> чи стане там кут (_corner_ok); скидається, щойно змінюється _avoid.
var _corner_cache: Dictionary = {}
var _piece_cache: Dictionary = {}
## Середина відрізка шляху -> чи вона далі за клітинку від асфальту (FIELD_COST).
var _far_cache: Dictionary = {}
var _size := Vector2i.ZERO
var lines: Array[Dictionary] = []
var transformers: Array[Vector2] = []
## Центри хат із відводом і хат, до яких опора дістала б, але відводу навмисно нема (SKIP_ONE_IN).
var fed: Array[Vector2] = []
var skipped: Array[Vector2] = []
## Найбільше гілок, що пробувались в одному селі, і пошуків шляху на одну гілку за весь план (тест стереже межі пошуку).
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
	for village: Array in _villages(homes):
		_village(village, trunk)
	_trim_dead_ends(trunk)


## Магістраль не обривається посеред поля: кінець, що не на краю світу, не ТП і не стовп іншої траси (відгалуження),
## знімається аж до такого; траса, від якої нічого не лишилось, зникає зовсім.
func _trim_dead_ends(trunk: Array) -> void:
	var lo: float = -_ring - 0.5
	var hi := Vector2(_size.x + _ring - 0.5, _size.y + _ring - 0.5)
	var keep := func(line: Array, p: Vector2) -> bool:
		if transformers.has(p) or minf(minf(p.x - lo, hi.x - p.x), minf(p.y - lo, hi.y - p.y)) <= 0.5:
			return true
		return trunk.any(func(o: Array) -> bool: return o != line and o.has(p))
	for line: Array in trunk:
		while line.size() >= 2 and not keep.call(line, line.back()):
			_avoid.erase(line.pop_back())
			_corner_cache.clear()
		while line.size() >= 2 and not keep.call(line, line.front()):
			_avoid.erase(line.pop_front())
			_corner_cache.clear()
	for k in range(lines.size() - 1, -1, -1):
		if lines[k]["kind"] == &"10kv" and (lines[k]["points"] as Array).size() < 2:
			lines.remove_at(k)


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

## Чи лежить відрізок a–b уздовж осі карти.
static func aligned(a: Vector2, b: Vector2) -> bool:
	return minf(absf(a.x - b.x), absf(a.y - b.y)) <= AXIS_EPS


## Точка на прямій: уздовж x (h) на висоті fixed чи уздовж z на fixed, at — координата вздовж.
static func _pt(h: bool, fixed: float, at: float) -> Vector2:
	return Vector2(at, fixed) if h else Vector2(fixed, at)


## Найближче до p придатне місце на тій самій прямій уздовж осі (h — уздовж x) не далі за radius; INF — нема.
## Кандидати — крок 0.1 і межі клітинок (k ± 0.01): на дошці опора стоїть лише там, де не займає місця юніта.
func _along(p: Vector2, h: bool, radius: float, accept: Callable = Callable()) -> Vector2:
	var at: float = p.x if h else p.y
	var fixed: float = p.y if h else p.x
	var vals: Array[float] = []
	var t: float = -radius
	while t <= radius + 1e-6:
		vals.append(snappedf(at + t, 0.01))
		t += 0.1
	for k in range(floori(at - radius) - 1, ceili(at + radius) + 1):
		for o: float in [0.49, 0.51]:
			if absf(k + o - at) <= radius:
				vals.append(k + o)
	vals.sort_custom(func(x: float, y: float) -> bool: return absf(x - at) < absf(y - at) or (absf(x - at) == absf(y - at) and x < y))
	var cands: Array[Vector2] = []
	for v in vals:
		var q: Vector2 = _pt(h, fixed, v)
		if _clamp_world(q) == q:
			cands.append(q)
	return _first_ok(cands, accept)


## Перше придатне місце з кандидатів за порядком ярусів: поле, узбіччя дороги, двір уздовж паркану (PropLayer
## pole_spot_ok). Місце, придатне на нижчому ярусі, придатне й на вищих: accept для нього рахується раз, а не тричі.
func _first_ok(cands: Array[Vector2], accept: Callable) -> Vector2:
	var accepted: Dictionary = {}
	var near: Dictionary = {}
	for tier in 3:
		for q in cands:
			if not _spot_ok(q, tier):
				continue
			if not near.has(q):
				near[q] = _near_avoid(q)
			if near[q]:
				continue
			if not accepted.has(q):
				accepted[q] = accept.is_null() or accept.call(q)
			if accepted[q]:
				return q
	return Vector2.INF


## PropLayer pole_spot_ok з кешем: перешкоди за час планування не змінюються, а ті самі місця на межах клітинок
## перебираються сотні разів (кути, ТП).
## Опора й на кільці, де сліду юніта нема, не стоїть посеред клітинки (CENTRE_CLEAR).
func _spot_ok(q: Vector2, tier: int) -> bool:
	var key := Vector3(q.x, q.y, tier)
	if not _spot_cache.has(key):
		var edge: bool = maxf(absf(q.x - roundf(q.x)), absf(q.y - roundf(q.y))) >= CENTRE_CLEAR
		_spot_cache[key] = edge and _p.pole_spot_ok(q, tier)
	return _spot_cache[key]


func _near_avoid(q: Vector2) -> bool:
	for a in _avoid:
		if a.distance_to(q) < POLE_GAP:
			return true
	return false


func _clamp_world(q: Vector2) -> Vector2:
	var lo: float = -_ring - 0.49
	return Vector2(clampf(q.x, lo, _size.x + _ring - 1 + 0.49), clampf(q.y, lo, _size.y + _ring - 1 + 0.49))


# --- прямі вздовж осей ------------------------------------------------------------------------

## Прямі лінії вздовж дороги pts (точки осі за ходом): точки групуються за переважним напрямком дороги (x чи z),
## група коротша за MIN_PIECE — лише вигин — приєднується до сусідньої. Пряма групи — на медіані її поперечної
## координати, зсунута на d у бік nrm (нормалі точок, уже з боком лінії).
## Кожна: {h — уздовж x, c — координата прямої, away — знак «від дороги»}.
static func _lines(pts: Array, nrm: Array, d: float) -> Array:
	var n: int = pts.size()
	var groups: Array = []
	for k in n:
		var dir: Vector2 = (pts[mini(k + DIR_WINDOW, n - 1)] as Vector2) - (pts[maxi(k - DIR_WINDOW, 0)] as Vector2)
		var h: bool = absf(dir.x) >= absf(dir.y)
		if groups.is_empty() or groups.back()["h"] != h:
			groups.append({"h": h, "i0": k, "i1": k})
		else:
			groups.back()["i1"] = k
	var merged: Array = []
	for g: Dictionary in groups:
		var short: bool = (pts[g["i1"]] as Vector2).distance_to(pts[g["i0"]]) < MIN_PIECE
		if not merged.is_empty() and (short or merged.back()["h"] == g["h"]):
			merged.back()["i1"] = g["i1"]
		else:
			merged.append(g)
	# Короткий початок — вигин перед першою прямою, а не окрема пряма.
	if merged.size() > 1 and (pts[merged[0]["i1"]] as Vector2).distance_to(pts[merged[0]["i0"]]) < MIN_PIECE:
		merged[1]["i0"] = 0
		merged.pop_front()
	var out: Array = []
	for g: Dictionary in merged:
		var h: bool = g["h"]
		var across: Array[float] = []
		var side: float = 0.0
		for k in range(g["i0"], int(g["i1"]) + 1):
			across.append((pts[k] as Vector2).y if h else (pts[k] as Vector2).x)
			side += (nrm[k] as Vector2).y if h else (nrm[k] as Vector2).x
		across.sort()
		var away: float = 1.0 if side >= 0.0 else -1.0
		out.append({"h": h, "c": across[across.size() / 2] + away * d, "away": away})
	return out


## Можливі координати прямої: намічена, далі — зсуви до дороги й за неї (до SHIFT_IN) і від неї (до SHIFT_OUT)
## кроком 0.1 і межі клітинок, від найменшого зсуву.
static func _coords(line: Dictionary) -> Array[float]:
	var c: float = line["c"]
	var away: float = line["away"]
	var vals: Array[float] = []
	var t: float = -SHIFT_IN
	while t <= SHIFT_OUT + 1e-6:
		vals.append(snappedf(c + away * t, 0.01))
		t += 0.1
	for k in range(floori(c - maxf(SHIFT_IN, SHIFT_OUT)) - 1, ceili(c + maxf(SHIFT_IN, SHIFT_OUT)) + 1):
		for o: float in [0.49, 0.51]:
			var dt: float = (k + o - c) * away
			if dt >= -SHIFT_IN and dt <= SHIFT_OUT:
				vals.append(k + o)
	vals.sort_custom(func(x: float, y: float) -> bool:
		var dx: float = absf(x - c)
		var dy: float = absf(y - c)
		return dx < dy or (dx == dy and (x - c) * away > (y - c) * away))
	return vals


## Опори лінії з прямих lines від координати s0 уздовж першої до s1 уздовж останньої. Кут із попередньою прямою
## мусить бути придатний під опору — інакше лінія піде навскіс; з таких координат (_coords) пряма бере першу, на якій
## її відрізок стоїть цілий (_line_ok). Коли кута нема з жодною, попередня пряма пробує іншу координату (до
## BACKTRACK). Опора на кожному куті, між кутами — проміжні не далі за gap (проліт ≤ max_span і ok). start — опора, з
## якої лінія починається (відгалуження); r0, r1 — наскільки кінцеві опори можуть відійти вздовж лінії.
func _lay(lines: Array, s0: float, s1: float, gap: float, max_span: float, ok: Callable, r0: float, r1: float, start := Vector2.INF) -> Array[Vector2]:
	var n: int = lines.size()
	var coords: Array[float] = []
	# Координата прямої i: [перша, з якою стоїть цілий відрізок (_line_ok), чи INF; перша лише з придатним кутом, чи INF].
	var pick := func(i: int) -> Array[float]:
		var h: bool = lines[i]["h"]
		var a0: float = s0 if i == 0 else coords[i - 1]
		var a1: float = s1 if i == n - 1 else float(lines[i + 1]["c"])
		var first: float = INF
		for cand in _coords(lines[i]):
			# Сходинка, коротша за проліт між опорами, — або нема її зовсім (пряма продовжується), або вона не коротша
			# за POLE_GAP: два кути впритул не стоять.
			if i > 1 and cand != coords[i - 2] and absf(cand - coords[i - 2]) < POLE_GAP:
				continue
			if i > 0 and not _corner_ok(_pt(lines[i - 1]["h"], coords[i - 1], cand)):
				continue
			if i == 0 and not _end_pole(_pt(h, cand, s0), h, r0).is_finite():
				continue
			if not is_finite(first):
				first = cand
			if _line_ok(h, cand, a0, a1, r0 if i == 0 else 1.0, r1 if i == n - 1 else 1.0, gap, max_span, ok):
				return [cand, cand] as Array[float]
		return [INF, first] as Array[float]
	for i in n:
		if i == 0 and start.is_finite():
			coords.append(start.y if lines[0]["h"] else start.x)
			continue
		var got: Array[float] = pick.call(i)
		coords.append(got[0])
		# Цілого відрізка нема (ліс, вода, хата на прямій): попередня пряма пробує інші координати (до BACKTRACK); не
		# вийшло — лишається перша координата з придатним кутом.
		if not is_finite(coords[i]) and i > 0 and not (i == 1 and start.is_finite()):
			var keep: float = coords[i - 1]
			var tried: int = 0
			for alt in _coords(lines[i - 1]):
				if alt == keep or (i > 1 and not _corner_ok(_pt(lines[i - 2]["h"], coords[i - 2], alt))) \
						or (i > 2 and alt != coords[i - 3] and absf(alt - coords[i - 3]) < POLE_GAP):
					continue
				tried += 1
				if tried > BACKTRACK:
					break
				coords[i - 1] = alt
				coords[i] = (pick.call(i) as Array[float])[0]
				if is_finite(coords[i]):
					break
			if not is_finite(coords[i]):
				coords[i - 1] = keep
		if not is_finite(coords[i]):
			coords[i] = got[1]
		if not is_finite(coords[i]):
			coords[i] = lines[i]["c"]
	var out: Array[Vector2] = []
	for i in n:
		var h: bool = lines[i]["h"]
		var v: float = coords[i]
		var p0 := Vector2.INF
		if i == 0:
			p0 = start if start.is_finite() else _end_pole(_pt(h, v, s0), h, r0)
		else:
			p0 = _pt(lines[i - 1]["h"], coords[i - 1], v)
			if not _corner_ok(p0):
				p0 = _along(_pt(h, v, coords[i - 1]), h, 1.0)
		if not p0.is_finite():
			continue
		if out.is_empty() or out.back() != p0:
			out.append(p0)
		# Сходинки нема: наступна пряма продовжує попередню з того самого кута.
		if i < n - 1 and _pt(h, v, coords[i + 1]) == p0:
			continue
		var p1 := Vector2.INF
		var from: Vector2 = p0
		var apart := func(q: Vector2) -> bool: return q.distance_to(from) >= POLE_GAP
		if i == n - 1:
			p1 = _end_pole(_pt(h, v, s1), h, r1, apart)
		else:
			p1 = _pt(h, v, coords[i + 1])
			if not _corner_ok(p1) or not apart.call(p1):
				p1 = _along(_pt(h, v, coords[i + 1]), h, 1.0, apart)
		if not p1.is_finite():
			continue
		# Де законного прольоту нема (ліс, вода), проміжних опор нема; такий відрізок прибирає _legal_runs.
		var mid: Variant = _fill(p0, p1, gap, max_span, ok)
		if mid != null:
			out.append_array(mid)
		out.append(p1)
	return out


## Ламана опор, розрізана на шматки з самих лише законних прольотів (уздовж осі, ok): незаконний проліт — розрив.
## Лишаються шматки, що виходять на край світу чи починаються з опори start (відгалуження від іншої траси): шматок
## посеред поля був би лінією нізвідки.
func _legal_runs(pts: Array[Vector2], ok: Callable, start: Vector2) -> Array:
	var runs: Array = []
	var cur: Array[Vector2] = []
	for k in pts.size():
		if not cur.is_empty() and not (aligned(cur.back(), pts[k]) and ok.call(cur.back(), pts[k])):
			runs.append(cur)
			cur = []
		cur.append(pts[k])
	runs.append(cur)
	var lo: float = -_ring - 0.5
	var hi := Vector2(_size.x + _ring - 0.5, _size.y + _ring - 0.5)
	var at_edge := func(p: Vector2) -> bool:
		return minf(minf(p.x - lo, hi.x - p.x), minf(p.y - lo, hi.y - p.y)) <= 0.5
	return runs.filter(func(r: Array) -> bool:
		return r.size() >= 2 and (at_edge.call(r.front()) or at_edge.call(r.back()) or r.front() == start))


## Кут двох прямих придатний під опору.
func _corner_ok(c: Vector2) -> bool:
	if not _corner_cache.has(c):
		_corner_cache[c] = _spot_ok(c, 2) and not _near_avoid(c)
	return _corner_cache[c]


## Чи стоїть на прямій (h, v) відрізок від a0 до a1 цілий: кінцеві опори біля a0 і a1 (не далі за ra, rb) і проміжні між
## ними (_fill).
func _line_ok(h: bool, v: float, a0: float, a1: float, ra: float, rb: float, gap: float, max_span: float, ok: Callable) -> bool:
	var e0: Vector2 = _end_pole(_pt(h, v, a0), h, ra)
	if not e0.is_finite():
		return false
	var e1: Vector2 = _end_pole(_pt(h, v, a1), h, rb, func(q: Vector2) -> bool: return q.distance_to(e0) >= POLE_GAP)
	return e1.is_finite() and _fill(e0, e1, gap, max_span, ok) != null


## Кінцева опора на прямій біля p: у межах r, а кінець усередині світу (r ≥ 1) — і далі, до END_WIDE (вода, асфальт
## біля самого кінця дороги).
func _end_pole(p: Vector2, h: bool, r: float, accept: Callable = Callable()) -> Vector2:
	var q: Vector2 = _along(p, h, r, accept)
	if not q.is_finite() and r >= 1.0:
		q = _along(p, h, END_WIDE, accept)
	return q


## Сусідні опори магістралі не на одній прямій (кута між прямими не знайшлось) — сполучаються кутом (a.x, b.y) чи
## (b.x, a.y), де він придатний.
func _square_up(pts: Array[Vector2], ok: Callable) -> void:
	var k: int = 1
	while k < pts.size():
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		if not aligned(a, b):
			for c: Vector2 in [Vector2(a.x, b.y), Vector2(b.x, a.y)]:
				if c.distance_to(a) >= POLE_GAP and c.distance_to(b) >= POLE_GAP and _corner_ok(c) and ok.call(a, c) and ok.call(c, b):
					pts.insert(k, c)
					break
		k += 1


## Проміжні опори на прямій a–b (уздовж осі), кожен проліт ≤ max_span, не ближче POLE_GAP і ok; null — не вийшло.
func _fill(a: Vector2, b: Vector2, gap: float, max_span: float, ok: Callable) -> Variant:
	var out: Array[Vector2] = []
	var len_: float = a.distance_to(b)
	var h: bool = absf(b.y - a.y) <= AXIS_EPS
	if len_ > max_span:
		var n: int = ceili(len_ / gap)
		for i in range(1, n):
			var prev: Vector2 = out.back() if not out.is_empty() else a
			var q: Vector2 = _along(a.lerp(b, float(i) / n), h, 1.0, func(c: Vector2) -> bool:
				return c.distance_to(prev) >= POLE_GAP and c.distance_to(prev) <= max_span and c.distance_to(b) >= POLE_GAP and ok.call(prev, c))
			if not q.is_finite():
				return null
			out.append(q)
	var last: Vector2 = out.back() if not out.is_empty() else a
	if last.distance_to(b) > max_span or not ok.call(last, b):
		return null
	return out


# --- 10 кВ ---------------------------------------------------------------------------------

## Стовпи 10 кВ за намірами routes: прямі вздовж осі дороги з боку side, від краю світу до краю; відгалуження
## (from ≥ 0) починається з найближчого стовпа раніших трас і йде на його прямій.
func _trunk() -> Array:
	var out: Array = []
	for route: Dictionary in _p.layout.get("routes", []):
		var pts: Array[Vector2] = []
		var nrm: Array[Vector2] = []
		var axis: Array = route["axis"]
		var side: float = float(route.get("side", 1.0))
		for k in range(1, axis.size()):
			var a: Vector2 = axis[k - 1]
			var b: Vector2 = axis[k]
			var steps: int = maxi(1, ceili(a.distance_to(b) / 0.2))
			var dir: Vector2 = (b - a).normalized()
			for j in steps + int(k == axis.size() - 1):
				pts.append(a.lerp(b, float(j) / steps))
				nrm.append(Vector2(side * dir.y, -side * dir.x))
		var lines: Array = _lines(pts, nrm, VERGE)
		var start := Vector2.INF
		if int(route.get("from", -1)) >= 0:
			for line: Array in out:
				for pt: Vector2 in line:
					if not start.is_finite() or pt.distance_to(pts[0]) < start.distance_to(pts[0]):
						start = pt
		var c0: Vector2 = _clamp_world(pts[0])
		var c1: Vector2 = _clamp_world(pts.back())
		var ok := func(a: Vector2, b: Vector2) -> bool: return a.distance_to(b) <= MAX_10KV and not _p.span_hits_building(a, b)
		var line_pts: Array[Vector2] = _lay(lines, c0.x if lines[0]["h"] else c0.y, c1.x if lines.back()["h"] else c1.y,
				TRUNK_GAP, MAX_10KV, ok, _end_r(pts[0]), _end_r(pts.back()), start)
		_square_up(line_pts, ok)
		for run: Array[Vector2] in _legal_runs(line_pts, ok, start):
			out.append(run)
			_avoid.append_array(run)
			_corner_cache.clear()
	return out


## Наскільки кінцева опора траси відходить уздовж лінії: на краю світу — лише всередину й не далі за пів клітинки
## (лінія виходить за край, а не обривається перед ним), всередині — до клітинки, щоб дістати межу клітинок.
func _end_r(p: Vector2) -> float:
	return 0.45 if _clamp_world(p) != p else 1.0


# --- село ----------------------------------------------------------------------------------

func _village(homes: Array, trunk: Array) -> void:
	# Місця опор, від яких до хати можливий відвід (PropLayer drop_ok), — найближчі до вулиці й до хати.
	var spots: Array = []
	for h: Dictionary in homes:
		spots.append(_drop_spots(h["rect"]))
	var near_home := func(p: Vector2) -> float:
		var best: float = INF
		for h: Dictionary in homes:
			best = minf(best, p.distance_to(h["centre"]))
		return best
	# ТП: стовп 10 кВ магістралі (наявний чи вставлений у проліт навпроти хати), біля якого є місце під шафу; кандидати —
	# від найближчого до хат, і перший, від якого вдається провести лінію до хати, — ТП. Близька наявна ТП — спільна.
	var cands: Dictionary = {}
	for line: Array in trunk:
		for k in line.size():
			if _cabinet_fits(line[k], _pole_dir(line, k)):
				cands[line[k]] = near_home.call(line[k])
			if k == 0:
				continue
			for h: Dictionary in homes:
				var proj: Vector2 = Geometry2D.get_closest_point_to_segment(h["centre"], line[k - 1], line[k])
				if proj.distance_to(line[k - 1]) < 2.0 or proj.distance_to(line[k]) < 2.0:
					continue
				# ТП у прольоті — на прямій магістралі: лише вздовж неї.
				var s: Vector2 = _along(proj, absf(line[k].y - line[k - 1].y) <= AXIS_EPS, 0.6)
				if s.is_finite() and s.distance_to(line[k - 1]) >= 2.0 and s.distance_to(line[k]) >= 2.0 \
						and _cabinet_fits(s, (line[k] - line[k - 1]).normalized()):
					cands[s] = near_home.call(s) + 0.5
	for t: Vector2 in transformers:
		if cands.keys().any(func(c: Vector2) -> bool: return c.distance_to(t) < TP_GAP):
			cands[t] = near_home.call(t)
	var order: Array = cands.keys()
	order.sort_custom(func(x: Vector2, y: Vector2) -> bool:
		return cands[x] < cands[y] or (cands[x] == cands[y] and (x.x < y.x or (x.x == y.x and x.y < y.y))))
	var stations: Array[Vector2] = []
	var parent: Dictionary = {}
	var tree_edges: Array = []
	var degree: Dictionary = {}
	var trunk_segs: Array = []
	var tp := Vector2.INF
	var shared: bool = false
	var probes: int = 0
	var by_dist: Array = range(homes.size())
	for c: Vector2 in order:
		var is_shared: bool = transformers.any(func(t: Vector2) -> bool: return t.distance_to(c) < TP_GAP)
		if is_shared and not transformers.has(c):
			continue
		probes += 1
		if probes > TP_PROBES:
			break
		stations.assign([c])
		parent = {0: -1}
		# Дерево не перетинає й ліній сусідніх сіл.
		tree_edges = _spans_04()
		# ТП — два прольоти 10 кВ (лічаться за один) і щонайбільше MAX_SPANS − 1 прольотів 0.4 кВ, разом із тими, що вже
		# йдуть від спільної ТП.
		degree = {0: 1 + _spans_04_at(c)}
		trunk_segs = _segs_with(trunk, c)
		by_dist.sort_custom(func(x: int, y: int) -> bool: return c.distance_to(homes[x]["centre"]) < c.distance_to(homes[y]["centre"]))
		# Від ТП — до будь-якої з трьох найближчих хат: важка найближча не відкидає ТП, від якої легко дійти до сусідньої.
		var first: Array[Vector2] = []
		for hi: int in by_dist.slice(0, 3):
			first.append_array(spots[hi])
		# Хутір з однієї хати біля самої траси: відвід прямо з опори ТП, без лінії 0.4 кВ; поселенню — своя лінія.
		if (homes.size() == 1 and _pick_station(homes[0]["rect"], stations, parent) >= 0) \
				or _grow(homes[by_dist[0]]["rect"], first, stations, parent, tree_edges, degree, trunk_segs, TP_TRIES):
			tp = c
			shared = is_shared
			break
	if not tp.is_finite():
		return
	var inserted: bool = false
	if not shared:
		inserted = _insert_pole(trunk, tp)
		_avoid.append(tp)
		_corner_cache.clear()
	# Дерево від ТП: кожна наступна найближча хата, до якої ще жодна опора не дістає відводом, — шлях сходинками
	# вздовж осей (_path) від опор дерева до місця опори біля неї.
	var attempts: int = 0
	for hi: int in by_dist:
		if attempts >= BRIDGE_BUDGET:
			break
		if _pick_station(homes[hi]["rect"], stations, parent) >= 0:
			continue
		_grow(homes[hi]["rect"], spots[hi], stations, parent, tree_edges, degree, trunk_segs)
		attempts += 1
		peak_attempts = maxi(peak_attempts, attempts)
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
	# Поселення з кількох хат лишається зі своєю лінією 0.4 кВ, навіть коли всі відводи дістали прямо з ТП: перша гілка
	# (до хати, заради якої обрано ТП, — станція 1) лишається.
	if homes.size() >= 2 and needed.keys().all(func(k: int) -> bool: return k == 0) and parent.has(1):
		var u: int = 1
		while u >= 0:
			needed[u] = true
			u = parent[u]
	if chosen.is_empty():
		# ТП, яка нікого не живить, не лишається ні в мережі, ні на лінії 10 кВ.
		if inserted:
			_remove_pole(trunk, tp)
			_avoid.erase(tp)
			_corner_cache.clear()
		return
	if not shared:
		transformers.append(tp)
	needed[0] = true
	for i: int in needed:
		_avoid.append(stations[i])
		_corner_cache.clear()
	# Ламані: від ТП гілками дерева (як lines).
	var kids: Dictionary = {}
	for i: int in needed:
		var par: int = parent[i]
		if par >= 0:
			if not kids.has(par):
				kids[par] = []
			(kids[par] as Array).append(i)
	var stack: Array = [[0, [] as Array[Vector2]]]
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


## Гілка дерева до хати rect: найкоротший шлях сходинками вздовж осей (_path) від будь-якої опори дерева, що ще має
## вільний проліт (MAX_SPANS) і стоїть не далі за BRIDGE_MAX від хати, до одного з місць spots, без перетину з деревом;
## між поворотами — проміжні опори (_straight). true — гілку додано (stations, parent, tree_edges, degree оновлено).
func _grow(rect: Rect2, spots: Array[Vector2], stations: Array[Vector2], parent: Dictionary, tree_edges: Array, degree: Dictionary, trunk_segs: Array, tries: int = BRIDGE_TRIES) -> bool:
	var c: Vector2 = rect.get_center()
	var from: Array[int] = []
	for k: int in parent:
		if int(degree.get(k, 0)) < MAX_SPANS and stations[k].distance_to(c) <= BRIDGE_MAX:
			from.append(k)
	var base: int = stations.size()
	var to: Array[int] = []
	for s: Vector2 in spots:
		if stations.all(func(o: Vector2) -> bool: return o.distance_to(s) >= POLE_GAP) \
				and trunk_segs.all(func(e: Array) -> bool: return Geometry2D.get_closest_point_to_segment(s, e[0], e[1]).distance_to(s) >= LEAF_CLEAR):
			stations.append(s)
			to.append(stations.size() - 1)
	if from.is_empty() or to.is_empty():
		stations.resize(base)
		return false
	# Шлях шукається по коротких відрізках; пряма, на якій потім не стали опори чи проліт (провис, перехід через дорогу),
	# виключається, і пошук повторюється — щонайбільше BRIDGE_TRIES разів.
	var blocked: Array = []
	var chain: Array[int] = []
	var all_spots: Array[Vector2] = []
	for k: int in to:
		all_spots.append(stations[k])
	for attempt in tries:
		peak_tries = maxi(peak_tries, attempt + 1)
		stations.resize(base)
		stations.append_array(all_spots)
		var path: Array[Vector2] = _path(stations, from, to, trunk_segs, tree_edges, blocked)
		if path.is_empty():
			break
		var start: int = stations.find(path[0])
		stations.resize(base)
		stations.append(path.back())
		var ids: Array[int] = [start]
		for q in path.slice(1, path.size() - 1):
			stations.append(q)
			ids.append(stations.size() - 1)
		ids.append(base)
		chain = [start]
		for k in range(1, ids.size()):
			var e: Array[int] = _straight(stations, ids[k - 1], ids[k], trunk_segs)
			if e.is_empty():
				blocked.append([stations[ids[k - 1]], stations[ids[k]]])
				chain = []
				break
			chain.append_array(e)
		# Гачок шляху не перетинає сам себе й дерева: проліт, що перетинає, виключається, і пошук повторюється.
		var spans: Array = []
		for k in range(1, chain.size()):
			var sp: Array = [stations[chain[k - 1]], stations[chain[k]]]
			if _crosses(sp[0], sp[1], spans + tree_edges):
				blocked.append(sp)
				chain = []
				break
			spans.append(sp)
		if not chain.is_empty():
			break
	if chain.is_empty():
		stations.resize(base)
		return false
	for k in range(1, chain.size()):
		parent[chain[k]] = chain[k - 1]
		degree[chain[k - 1]] = int(degree.get(chain[k - 1], 0)) + 1
		degree[chain[k]] = 1
		tree_edges.append([stations[chain[k - 1]], stations[chain[k]]])
	return true


## Найкоротший шлях (Дейкстра) від однієї зі станцій from до однієї зі станцій to по прямих уздовж осей: межі клітинок
## і координати самих станцій у рамці навколо них із запасом ROUTE_MARGIN. Поворот — нова опора: придатне місце не
## ближче POLE_GAP до інших і до попереднього повороту, коштує TURN_COST, тож шлях не смикається; дріт далі за клітинку
## від асфальту дорожчий (FIELD_COST) — лінія йде узбіччям. Відрізки — _piece_ok і не через дерево tree_edges.
## Шлях — станція from, повороти, станція to; порожній — нема.
func _path(stations: Array[Vector2], from: Array[int], to: Array[int], trunk_segs: Array, tree_edges: Array, blocked: Array = []) -> Array[Vector2]:
	var keep_x: Array[float] = []
	var keep_z: Array[float] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k: int in from + to:
		keep_x.append(stations[k].x)
		keep_z.append(stations[k].y)
	for k: int in to:
		lo = lo.min(stations[k])
		hi = hi.max(stations[k])
	# Рамка — навколо місць біля хати й найближчої опори дерева, а не всього дерева.
	var near: int = from[0]
	for k: int in from:
		if stations[k].distance_to(lo.lerp(hi, 0.5)) < stations[near].distance_to(lo.lerp(hi, 0.5)):
			near = k
	lo = lo.min(stations[near]) - Vector2(ROUTE_MARGIN, ROUTE_MARGIN)
	hi = hi.max(stations[near]) + Vector2(ROUTE_MARGIN, ROUTE_MARGIN)
	# Перетин перевіряється лише з ребрами дерева, що заходять у рамку: кожен крок пошуку — перевірка відрізка.
	var box := Rect2(lo, hi - lo).grow(0.5)
	tree_edges = tree_edges.filter(func(e: Array) -> bool: return box.intersects(Rect2(e[0], Vector2.ZERO).expand(e[1]).grow(0.01)))
	var xs: Array[float] = _route_vals(lo.x, hi.x, keep_x)
	var zs: Array[float] = _route_vals(lo.y, hi.y, keep_z)
	var nx: int = xs.size()
	var node_of := func(p: Vector2) -> int:
		var ix: int = xs.find(p.x)
		var iz: int = zs.find(p.y)
		return -1 if ix < 0 or iz < 0 else ix + iz * nx
	var goals: Dictionary = {}
	for k: int in to:
		var g: int = node_of.call(stations[k])
		if g >= 0:
			goals[g] = true
	# Крізь інші опори шлях не йде: дріт не проходить через чужий стовп.
	var poles: Dictionary = {}
	for k in stations.size():
		var pn: int = node_of.call(stations[k])
		if pn >= 0 and not goals.has(pn):
			poles[pn] = true
	const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Стан — (вузол·5 + напрям, яким у нього прийшли (4 — початок))·2 + чи пряма від останнього повороту вже не коротша за
	# POLE_GAP: коротка й довга гілки — різні стани, тож дешевша коротка не витісняє довшої, з якої можна повернути.
	# run — довжина прямої від останнього повороту, gap — від останнього місця, де може стати опора: далі за MAX_04KV
	# прольоту не буде (вода, асфальт, двір уздовж).
	var dist: Dictionary = {}
	var run: Dictionary = {}
	var gap: Dictionary = {}
	var prev: Dictionary = {}
	var open: Array = []
	# A*: у купі — ціна з оцінкою решти шляху (манхеттенська відстань до найближчої мети, не більша за справжню ціну),
	# тож пошук не розтікається рамкою, а йде до хати.
	var goal_pts: Array[Vector2] = []
	for k: int in to:
		goal_pts.append(stations[k])
	var h_of := func(q: Vector2) -> float:
		var best: float = INF
		for gp in goal_pts:
			best = minf(best, absf(gp.x - q.x) + absf(gp.y - q.y))
		return best
	for k: int in from:
		var s0: int = node_of.call(stations[k])
		if s0 >= 0:
			dist[(s0 * 5 + 4) * 2] = 0.0
			run[(s0 * 5 + 4) * 2] = 0.0
			gap[(s0 * 5 + 4) * 2] = 0.0
			_heap_push(open, [h_of.call(stations[k]), (s0 * 5 + 4) * 2, 0.0])
	var found: int = -1
	var corner_cache: Dictionary = {}
	var spot_cache: Dictionary = {}
	while not open.is_empty():
		var item: Array = _heap_pop(open)
		var s: int = item[1]
		if item[2] > float(dist.get(s, INF)):
			continue
		var node: int = s / 10
		var d_in: int = (s / 2) % 5
		var long: bool = s % 2 == 1
		if goals.has(node) and d_in < 4 and long:
			found = s
			break
		var gx: int = node % nx
		var gz: int = node / nx
		var p := Vector2(xs[gx], zs[gz])
		for d in 4:
			if d_in < 4 and DIRS[d] == -DIRS[d_in]:
				continue
			var turn: bool = d_in < 4 and d != d_in
			if turn:
				if not long:
					continue
				if not corner_cache.has(node):
					corner_cache[node] = _corner_ok(p) and stations.all(func(o: Vector2) -> bool: return o.distance_to(p) >= POLE_GAP)
				if not corner_cache[node]:
					continue
			var ux: int = gx + DIRS[d].x
			var uz: int = gz + DIRS[d].y
			if ux < 0 or uz < 0 or ux >= nx or uz >= zs.size():
				continue
			var q := Vector2(xs[ux], zs[uz])
			var g: float = (0.0 if turn else float(gap[s])) + p.distance_to(q)
			if g > MAX_04KV or poles.has(ux + uz * nx) or _on_blocked(p, q, blocked) or _crosses(p, q, tree_edges) \
					or not _piece_ok(p, q, trunk_segs):
				continue
			var mid := p.lerp(q, 0.5)
			if not _far_cache.has(mid):
				_far_cache[mid] = _p.road_edge_m(mid) > 8.0
			var far: bool = _far_cache[mid]
			var r: float = (0.0 if turn else float(run[s])) + p.distance_to(q)
			var t: int = ((ux + uz * nx) * 5 + d) * 2 + int(r >= POLE_GAP)
			var cost: float = float(item[2]) + p.distance_to(q) * (FIELD_COST if far else 1.0) + (TURN_COST if turn else 0.0)
			if cost < float(dist.get(t, INF)):
				dist[t] = cost
				run[t] = r
				var qn: int = ux + uz * nx
				if not spot_cache.has(qn):
					spot_cache[qn] = _corner_ok(q)
				gap[t] = 0.0 if spot_cache[qn] else g
				prev[t] = s
				_heap_push(open, [cost + h_of.call(q), t, cost])
	if found < 0:
		return []
	var at := func(st: int) -> Vector2: return Vector2(xs[(st / 10) % nx], zs[(st / 10) / nx])
	var path: Array[Vector2] = [at.call(found)]
	var s: int = found
	while prev.has(s):
		var ps: int = prev[s]
		if (ps / 2) % 5 != 4 and (ps / 2) % 5 != (s / 2) % 5:
			path.push_front(at.call(ps))
		s = ps
	path.push_front(at.call(s))
	return path


## Місця опори біля хати rect, від яких можливий відвід (PropLayer drop_ok): на межах клітинок навколо хати не далі
## за DROP_DIRECT; перші — ближчі до вулиці (дріт уздовж узбіччя), далі — ближчі до хати. Щонайбільше DROP_SPOTS.
func _drop_spots(rect: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var r: float = PropLayer.DROP_DIRECT
	var lo: Vector2 = rect.position - Vector2(r, r)
	var hi: Vector2 = rect.end + Vector2(r, r)
	var cands: Array[Vector2] = []
	for axis in 2:
		for k in range(floori(lo.x if axis == 0 else lo.y), ceili(hi.x if axis == 0 else hi.y) + 1):
			for o: float in [0.49, 0.51]:
				var t: float = lo.y if axis == 0 else lo.x
				while t <= (hi.y if axis == 0 else hi.x) + 1e-6:
					var q: Vector2 = Vector2(k + o, snappedf(t, 0.01)) if axis == 0 else Vector2(snappedf(t, 0.01), k + o)
					# Далі за відвід від стіни — не місце для відводу; так перевірок місця (дорогих) учетверо менше.
					var gap: float = Vector2(maxf(maxf(rect.position.x - q.x, 0.0), q.x - rect.end.x), maxf(maxf(rect.position.y - q.y, 0.0), q.y - rect.end.y)).length()
					if gap <= r:
						cands.append(q)
					t += 0.2
	# Спершу ближчі до хати; із перших DROP_SCAN придатних — ближчі до вулиці (відстань до асфальту — дорогий запит).
	cands.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da: float = a.distance_squared_to(rect.get_center())
		var db: float = b.distance_squared_to(rect.get_center())
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var keyed: Array = []
	for q in cands:
		if _corner_ok(q):
			keyed.append([q.distance_to(rect.get_center()) + minf(_p.road_edge_m(q), 16.0) / 8.0, q])
			if keyed.size() >= DROP_SCAN:
				break
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and (a[1].x < b[1].x or (a[1].x == b[1].x and a[1].y < b[1].y))))
	for kq: Array in keyed:
		var q: Vector2 = kq[1]
		if out.all(func(o: Vector2) -> bool: return o.distance_to(q) >= POLE_GAP) and _p.drop_ok(rect, q):
			out.append(q)
			if out.size() >= DROP_SPOTS:
				break
	return out


## Прольоти магістралі, з ТП у точці p: проліт, у який ТП вставляється, ділиться нею (як _insert_pole).
func _segs_with(trunk: Array, p: Vector2) -> Array:
	var segs: Array = []
	for line: Array in trunk:
		for k in range(1, line.size()):
			if line[k - 1] != p and line[k] != p and Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k]).distance_to(p) <= AXIS_EPS:
				segs.append_array([[line[k - 1], p], [p, line[k]]])
			else:
				segs.append([line[k - 1], line[k]])
	return segs


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


## Чи лежить відрізок p–q на одній із виключених прямих blocked ([a, b]).
static func _on_blocked(p: Vector2, q: Vector2, blocked: Array) -> bool:
	for e: Array in blocked:
		if Geometry2D.get_closest_point_to_segment(p, e[0], e[1]).distance_to(p) < 1e-3 \
				and Geometry2D.get_closest_point_to_segment(q, e[0], e[1]).distance_to(q) < 1e-3:
			return true
	return false


## Двійкова купа [ціна, стан, …] за ціною (за рівної — за станом, щоб шлях був однаковий щоразу).
static func _heap_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var k: int = heap.size() - 1
	while k > 0:
		var up: int = (k - 1) / 2
		if not _heap_less(heap[k], heap[up]):
			break
		var t: Array = heap[k]
		heap[k] = heap[up]
		heap[up] = t
		k = up


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var k: int = 0
	while true:
		var l: int = 2 * k + 1
		var m: int = k
		if l < heap.size() and _heap_less(heap[l], heap[m]):
			m = l
		if l + 1 < heap.size() and _heap_less(heap[l + 1], heap[m]):
			m = l + 1
		if m == k:
			break
		var t: Array = heap[k]
		heap[k] = heap[m]
		heap[m] = t
		k = m
	return top


## Координати прямих для шляху між lo і hi: межі клітинок (k ± 0.01, де може стати кут), узбіччя за 0.4 клітинки від
## межі (k + 0.1, k + 0.9 — пряма поза межею, з кутами на поперечних межах) і задані (координати самих станцій).
static func _route_vals(lo: float, hi: float, keep: Array) -> Array[float]:
	var out: Array[float] = []
	for k in range(floori(lo), ceili(hi) + 1):
		for o: float in [0.1, 0.49, 0.51, 0.9]:
			if k + o >= lo and k + o <= hi:
				out.append(k + o)
	for v: float in keep:
		if not out.has(v):
			out.append(v)
	out.sort()
	return out


## Відрізок обходу p–q: не на будівлі й не через магістраль; над асфальтом — лише впоперек вулиці, поза ним — як дріт
## (PropLayer wire_ok: двори, грядки, ліс). Кеш на весь план.
func _piece_ok(p: Vector2, q: Vector2, trunk_segs: Array) -> bool:
	# Той самий відрізок в обидва боки — один запис.
	var key := Rect2(p, q - p) if p.x < q.x or (p.x == q.x and p.y <= q.y) else Rect2(q, p - q)
	if _piece_cache.has(key):
		return _piece_cache[key]
	var ok: bool = not _p.span_hits_building(p, q)
	if ok:
		for e: Array in trunk_segs:
			if _seg_crosses(p, q, e[0], e[1]):
				ok = false
				break
	if ok:
		var mid: Vector2 = p.lerp(q, 0.5)
		if _p.road_edge_m(p) < 0.0 or _p.road_edge_m(q) < 0.0 or _p.road_edge_m(mid) < 0.0:
			ok = absf((q - p).normalized().dot(_p.street_dir(mid))) <= SQUARE_SIN
		else:
			ok = _p.wire_ok(p, q, PropLayer.SPAN_CROSS)
	_piece_cache[key] = ok
	return ok


## Опори від станції i до j на одній прямій (без i, з j): проліт, а довший за MAX_04KV (до BRIDGE_CHAIN_MAX) — з
## проміжними опорами на тій самій прямій, не ближче POLE_GAP до інших; порожній — не вийшло (нові опори знімаються).
func _straight(stations: Array[Vector2], i: int, j: int, trunk_segs: Array) -> Array[int]:
	var a: Vector2 = stations[i]
	var b: Vector2 = stations[j]
	if a.distance_to(b) < POLE_GAP or a.distance_to(b) > BRIDGE_CHAIN_MAX:
		return []
	var ok := func(u: Vector2, v: Vector2) -> bool:
		return _span_clear(u, v, trunk_segs) and (v == b or stations.all(func(o: Vector2) -> bool: return o == a or o == b or o.distance_to(v) >= POLE_GAP))
	# Опори від a до b: щоразу найдальше придатне місце не далі за MAX_04KV і не ближче POLE_GAP до b.
	var mid: Array[Vector2] = []
	var cur: Vector2 = a
	while cur.distance_to(b) > MAX_04KV or not ok.call(cur, b):
		if mid.size() > 8:
			return []
		var best := Vector2.INF
		var t: float = minf(MAX_04KV, cur.distance_to(b) - POLE_GAP)
		while t >= POLE_GAP - 1e-6:
			var q: Vector2 = cur.move_toward(b, t)
			q = Vector2(snappedf(q.x, 0.01), snappedf(q.y, 0.01))
			if _corner_ok(q) and ok.call(cur, q):
				best = q
				break
			t -= 0.1
		if not best.is_finite():
			return []
		mid.append(best)
		cur = best
	var out: Array[int] = []
	for q: Vector2 in mid:
		stations.append(q)
		out.append(stations.size() - 1)
	out.append(j)
	return out


## Прольоти 0.4 кВ уже побудованих сіл, [a, b].
func _spans_04() -> Array:
	var out: Array = []
	for line: Dictionary in lines:
		if line["kind"] == &"04kv":
			var pts: Array = line["points"]
			for k in range(1, pts.size()):
				out.append([pts[k - 1], pts[k]])
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


## Вставити ТП у проліт магістралі, якщо її там ще нема; true — вставлено.
func _insert_pole(trunk: Array, pt: Vector2) -> bool:
	for line: Array in trunk:
		if line.has(pt):
			return false
	for line: Array in trunk:
		for k in range(1, line.size()):
			if Geometry2D.get_closest_point_to_segment(pt, line[k - 1], line[k]).distance_to(pt) <= AXIS_EPS:
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
