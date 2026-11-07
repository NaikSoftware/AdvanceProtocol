class_name ForestScatter
extends RefCounted
## Правила розкидання лісу: де стоїть яке дерево, кущ, смуга узлісся, колода й шматок землі
## просіки, якого масштабу й тону. Чиста функція `plan()`: ті самі клітинки, проломи, сезон і
## зерно дають той самий ліс.
##
## Кожна точка сітки, клітинка й сторона узлісся має власне зерно `hash([зерно, шар, x, y])`,
## а не один послідовний генератор: новий пролам змінює лише дерева біля нього. Проломи
## на дошці свої для кожного гравця (з його `seen`), і перемішаний після пролому ліс видав
## би, де пройшов ворог. `Rules.roll` тут не використовується: дерева не зсувають кидки бою.
##
## Глибина `depth` — відстань у тайлах до найближчої клітинки без лісу (назовні — мінус
## відстань до лісу), плюс шум ±`EDGE_NOISE`: край не йде по межах клітинок. Проламані
## клітинки для глибини лишаються лісом.

const TILE_M: float = 8.0

const EDGE_NOISE: float = 0.3
const JITTER: float = 0.4
## Намет: `depth` > `CANOPY_FROM`, масштаб меша 0,9–1,1; крайовий ряд — `EDGE_FROM`–`EDGE_TO`.
const CANOPY_FROM: float = 0.35
const CANOPY_GRID: float = 4.8
const CANOPY_SCALE: Vector2 = Vector2(0.9, 1.1)
const EDGE_FROM: float = 0.15
const EDGE_TO: float = 0.4
const EDGE_DENSITY: float = 3.5
const EDGE_SCALE: Vector2 = Vector2(0.85, 1.0)
## Кущі біля краю (`depth` 0…`SHRUB_BAND`) і підлісок усередині; висоти — у метрах.
const SHRUB_BAND: float = 0.6
const SHRUB_DENSITY: float = 4.5
const SHRUB_H: Vector2 = Vector2(2.0, 4.0)
const UNDERSTORY_DENSITY: float = 1.0
const UNDERSTORY_H: Vector2 = Vector2(1.5, 2.5)
const LOG_DENSITY: float = 0.25
## Смуга узлісся: відступ від сторони клітинки ± шум, уздовж сторони ±10°.
const HEDGE_INSET: float = 0.2
const HEDGE_WANDER: float = 0.25
## Вид — із шуму насаджень (10–30 м), тон — великий спокійний шум ±`TONE_VAR`.
const STAND_FREQ: float = 1.0 / 3.0
const TONE_FREQ: float = 1.0 / 2.5
const TONE_VAR: float = 0.03
## У скільки разів крона ширша за масштаб висоти: зімкнений ліс, ≥85 % закрито згори.
const WIDE: float = 1.45
## Біля просіки: крони тоншають до неї поступово (`LANE_THIN`) і не нависають над нею; обабіч —
## `LANE_SHRUBS` кущів на тайл (0,3–1,2 тайла від проламу). Танк трощить лише свою клітинку: поле
## в 0,45 тайла за краєм крони вирубувало й сусідні клітинки, і просіка в одну клітинку ставала
## галявиною в три. Крона, що нависала б над проламом, з камери накривала танк у ньому.
const LANE_THIN: float = 0.15
const LANE_SHRUBS: float = 4.0
## Ближче за `LANE_NEAR` тайла до проламу крона вужча й нижча (×0,7): широка з полем до
## просіки не вміщалась у сусідню клітинку, і та лишалась порожньою.
const LANE_NEAR: float = 2.0
## Тон повалених стовбурів просіки (множник кольору екземпляра) за порою року — кожна пора має
## свою карту й своє світло. Під похмурим небом пізньої осені тонкий циліндр світлішав до сірої
## жердини; на сонячних картах низьке сонце світить у тіньовий бік, що бере блакитне небо, і
## стовбур синів до чорного. Тон теплий — кора сіро-бура.
const LOG_TONE: Dictionary = {"late": Color(1.0, 0.86, 0.68), "summer": Color(1.8, 1.5, 1.15), "early": Color(1.8, 1.5, 1.15)}

## Склад лісу: частки видів (префікс вузла або ім'я вузла) у наметі й у крайовому ряду.
const WOODS: Dictionary = {
	"pine": {"canopy": {"Pine": 0.35, "Spruce": 0.55, "Birch": 0.1}, "edge": {"Spruce_B": 0.45, "Pine": 0.3, "Birch": 0.25}, "belt": {"Shrub": 1.0}, "hedge_evergreen": 0.85, "density": 4.8},
	"mixed": {"canopy": {"Pine": 0.2, "Spruce": 0.4, "Birch": 0.2, "Oak": 0.2}, "edge": {"Spruce_B": 0.35, "Birch": 0.4, "Oak": 0.25}, "belt": {"Shrub": 1.0}, "hedge_evergreen": 0.6, "density": 4.6},
	"deciduous": {"canopy": {"Oak": 0.6, "Birch": 0.3, "Spruce": 0.1}, "edge": {"Birch": 0.45, "Oak": 0.3, "Spruce_B": 0.25}, "belt": {"Shrub": 1.0}, "hedge_evergreen": 0.4, "density": 3.4},
}

## Пізня осінь: листяний ліс з хвойною домішкою (~30 %): зелені лише хвойні, а листяні на дві
## третини голі, решта з бурим листям (форми `*_R` у бібліотеці пізньої осені).
const LATE_CANOPY: Dictionary = {"Spruce": 0.2, "Pine": 0.1, "Birch": 0.4, "Oak": 0.3}
const LATE_DENSITY: float = 5.0
const LATE_EDGE: Dictionary = {"Spruce_B": 0.3, "Birch": 0.4, "Oak": 0.3}
## Ширина крони ялини пізньої осені (замість WIDE): вужчі шпилі, але без просвітів голої
## землі між ними.
const LATE_SPRUCE_W: float = 0.85
const LATE_SPRUCE := Color(0.62, 0.68, 0.76)
## Підріст по всій підлозі пізнього лісу (0,1–0,2 тайла заввишки): голі бурі кущі з рідкою
## молодою ялиною — земля під голими кронами не світить, а зеленого — лише хвоя.
const LATE_FLOOR_DENSITY: float = 6.0
const LATE_FLOOR_H: Vector2 = Vector2(0.8, 1.6)
const LATE_FLOOR: Dictionary = {"Shrub": 0.7, "Spruce_B": 0.3}
## Пояс узлісся, підлісок і смуга біля просіки пізньої осені.
const LATE_UNDER: Dictionary = {"Shrub": 0.7, "Spruce_B": 0.3}
const LATE_HEDGE_EVERGREEN: float = 0.35

## Рання осінь: атлас листяних крон оливково-жовтий; цілими кронами частка `TURN_ORANGE_SHARE`
## жовто-помаранчеві, `TURN_GREEN_SHARE` ще зелені. Пороги — квантилі шуму `TURN_FREQ` по
## лісових клітинках цієї карти, тож частки ті самі на будь-якій карті. Яскравість тонів та
## сама (≈ 1): різниться відтінок, а не світлість, інакше крони лягають плямами.
const TURN_FREQ: float = 1.0 / 2.0
const TURN_ORANGE_SHARE: float = 0.22
const TURN_GREEN_SHARE: float = 0.2
const TURN_ORANGE := Color(1.08, 0.94, 0.76)
const TURN_GREEN := Color(0.84, 1.04, 0.9)
const AUTUMN_SPECIES: PackedStringArray = ["Birch", "Oak", "Hero"]
## Літо: береза світліша й жовтіша, дуб темніший — породи не зливаються в один тон.
const SUMMER_TONE: Dictionary = {"Birch": Color(1.07, 1.08, 0.9), "Oak": Color(0.9, 0.95, 0.88)}

## Номери шарів для зерна точки: однакова точка різних шарів не має однакових кидків.
enum Layer { CANOPY, EDGE, BELT, LOGS, UNDER, FLOOR, LANE, HEDGE, BROKEN, FIXED }

var _cells: Dictionary
var _wood_at: Callable
var _broken: Dictionary
var _season: String
var _seed: int
var _lib: Dictionary
var _prefixes: Dictionary = {}  ## префікс виду -> Array[String] імен вузлів
var _noise := FastNoiseLite.new()
var _stand := FastNoiseLite.new()
var _tone := FastNoiseLite.new()
var _turn := FastNoiseLite.new()
var _turn_hi: float = 0.0
var _turn_lo: float = 0.0
var _stand_sorted: PackedFloat32Array = []  ## шум насаджень по лісу карти, для квантилів
var _out: Array[Dictionary] = []
var _limit := Rect2i()
var _fixed_u: Dictionary = {}  ## Vector2 -> частка в розподілі осені для поставлених вручну


## План лісу.
## - `cells`: Vector2i -> true — лісові клітинки;
## - `wood_at`: (Vector2) -> String — склад лісу в точці (ключ `WOODS`);
## - `broken`: Vector2i -> true — проламані клітинки того, хто дивиться;
## - `season`: late | summer | early; `seed` — зерно карти;
## - `library`: ім'я вузла -> {"h": висота AABB, "half": півширина AABB} (тайли, масштаб 1);
## - `fixed`: [[ім'я вузла, Vector2]] — поодинокі дерева, поставлені вручну;
## - `area`: лише ця частина карти (тайли); порожня — увесь ліс. Зерна точок ті самі, тож
##   план частини збігається з тією самою частиною плану цілого.
## Повертає записи {"node", "xf" (Transform3D у тайлах, y = 0 — земля), "pos", "r" (радіус
## крони), "rgb" (тон), "turn" ("orange" | "green" | ""), "ground" (шматок землі просіки)}.
static func plan(cells: Dictionary, wood_at: Callable, broken: Dictionary, season: String, seed: int,
		library: Dictionary, fixed: Array = [], area: Rect2i = Rect2i()) -> Array[Dictionary]:
	var f := ForestScatter.new()
	f._limit = area
	f._cells = cells
	f._wood_at = wood_at
	f._broken = broken
	f._season = season
	f._seed = seed
	f._lib = library
	for name: String in library:
		var prefix: String = name.get_slice("_", 0)
		if not f._prefixes.has(prefix):
			f._prefixes[prefix] = []
		(f._prefixes[prefix] as Array).append(name)
	f._init_noise()
	f._scatter()
	# Поставлених вручну дерев мало, і випадковий тон давав їм усім один колір: частки осені
	# розкладено по них рівно (u = (i + 0,5) / n) і перемішано зерном.
	var us: Array[float] = []
	for i in fixed.size():
		us.append((i + 0.5) / fixed.size())
	var shuffle := f._rng(Layer.FIXED, fixed.size(), 1)
	for i in range(us.size() - 1, 0, -1):
		var j: int = shuffle.randi_range(0, i)
		var t: float = us[i]
		us[i] = us[j]
		us[j] = t
	for i in fixed.size():
		f._fixed_u[fixed[i][1]] = us[i]
	for i in fixed.size():
		var rng := f._rng(Layer.FIXED, i, 0)
		if library.has(fixed[i][0]):
			f._place(fixed[i][0], fixed[i][1], 1.0, rng, true)
	return f._out


## Глибина точки в лісі (тайли): усередині — до найближчої клітинки без лісу, назовні — мінус.
static func depth(cells: Dictionary, p: Vector2) -> float:
	var c := Vector2i(floori(p.x + 0.5), floori(p.y + 0.5))
	var inside: bool = cells.has(c)
	var best: float = 99.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := c + Vector2i(dx, dy)
			if cells.has(n) == inside:
				continue
			var lo := Vector2(n) - Vector2(0.5, 0.5)
			best = minf(best, p.distance_to(p.clamp(lo, lo + Vector2.ONE)))
	return best if inside else -best


## Відстань від точки до найближчої проламаної клітинки (тайли), 99 — немає поруч.
static func broken_distance(broken: Dictionary, p: Vector2) -> float:
	var best: float = 99.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := Vector2i(floori(p.x + 0.5) + dx, floori(p.y + 0.5) + dy)
			if broken.has(c):
				var lo := Vector2(c) - Vector2(0.5, 0.5)
				best = minf(best, p.distance_to(p.clamp(lo, lo + Vector2.ONE)))
	return best


func _rng(layer: int, x: int, y: int, z: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed, layer, x, y, z])
	return r


func _init_noise() -> void:
	var noises: Array[FastNoiseLite] = [_noise, _stand, _tone, _turn]
	for i in noises.size():
		noises[i].seed = _seed + i
	_noise.frequency = 1.0 / 1.5
	_stand.frequency = STAND_FREQ
	_tone.frequency = TONE_FREQ
	_turn.frequency = TURN_FREQ
	# Квантилі шуму осені й насаджень по лісових клітинках (4 × 4 точки на клітинку).
	var v: Array[float] = []
	var st: Array[float] = []
	for c: Vector2i in _cells:
		for k in 16:
			var q := Vector2(c.x - 0.375 + 0.25 * (k % 4), c.y - 0.375 + 0.25 * floorf(k / 4.0))
			v.append(_turn.get_noise_2d(q.x, q.y))
			st.append(_stand.get_noise_2d(q.x, q.y))
	v.sort()
	st.sort()
	_stand_sorted = PackedFloat32Array(st)
	if not v.is_empty():
		_turn_hi = v[clampi(int(v.size() * (1.0 - TURN_ORANGE_SHARE)), 0, v.size() - 1)]
		_turn_lo = v[clampi(int(v.size() * TURN_GREEN_SHARE), 0, v.size() - 1)]


func _area() -> Rect2i:
	if _limit.has_area():
		return _limit
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for c: Vector2i in _cells:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2i(lo - Vector2i(2, 2), hi - lo + Vector2i(5, 5))


func _scatter() -> void:
	if _cells.is_empty():
		return
	var late: bool = _season == "late"
	var canopy := func(d: float) -> bool: return d > CANOPY_FROM
	var edge := func(d: float) -> bool: return d > EDGE_FROM and d <= EDGE_TO
	var shrub := func(d: float) -> bool: return d > 0.0 and d <= SHRUB_BAND
	var under: Dictionary = LATE_UNDER if late else {"Shrub": 1.0}
	_layer(Layer.CANOPY, CANOPY_GRID, canopy, func(p: Vector2) -> Dictionary: return LATE_CANOPY if late else WOODS[_wood_at.call(p)]["canopy"],
			CANOPY_SCALE, true, func(p: Vector2) -> float: return LATE_DENSITY if late else float(WOODS[_wood_at.call(p)]["density"]))
	_layer(Layer.EDGE, EDGE_DENSITY, edge, func(p: Vector2) -> Dictionary: return LATE_EDGE if late else WOODS[_wood_at.call(p)]["edge"], EDGE_SCALE, true)
	_layer(Layer.BELT, SHRUB_DENSITY, shrub, func(p: Vector2) -> Dictionary: return LATE_UNDER if late else WOODS[_wood_at.call(p)]["belt"], SHRUB_H, false)
	if _prefixes.has("Log"):
		_layer(Layer.LOGS, LOG_DENSITY, func(d: float) -> bool: return d > 0.3, func(_p: Vector2) -> Dictionary: return {"Log": 1.0}, Vector2.ONE, true)
	_layer(Layer.UNDER, UNDERSTORY_DENSITY, func(d: float) -> bool: return d > SHRUB_BAND, func(_p: Vector2) -> Dictionary: return under, UNDERSTORY_H, false)
	if late:
		_layer(Layer.FLOOR, LATE_FLOOR_DENSITY, func(d: float) -> bool: return d > 0.1,
				func(_p: Vector2) -> Dictionary: return LATE_FLOOR, LATE_FLOOR_H, false)
	# Підлісок обабіч просіки, темний: заповнює поле між просікою й кронами, щоб пролам
	# лишався смугою, а не галявиною.
	_layer(Layer.LANE, LANE_SHRUBS, func(d: float) -> bool: return d > 0.0, func(_p: Vector2) -> Dictionary: return under, SHRUB_H, false,
			func(p: Vector2) -> float:
				var bd: float = broken_distance(_broken, p)
				return LANE_SHRUBS if bd > 0.3 and bd < 1.2 else 0.0)
	_hedges()
	_broken_cells()


## Сітка з кроком 1/√густини, прив'язана до початку координат карти (не до краю лісу): точка
## (ix, iy) і її зерно не залежать від того, які ще клітинки є лісом.
## `sizes` — масштаб меша (by_scale) або висота в метрах.
func _layer(layer: int, density: float, band: Callable, species_at: Callable, sizes: Vector2, by_scale: bool, density_at: Callable = Callable()) -> void:
	var step: float = 1.0 / sqrt(density)
	var area: Rect2i = _area()
	for iy in range(floori(area.position.y / step), ceili(area.end.y / step)):
		for ix in range(floori(area.position.x / step), ceili(area.end.x / step)):
			var rng := _rng(layer, ix, iy)
			var p := Vector2(ix * step, iy * step) + Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER)) * step
			var d: float = depth(_cells, p) + _noise.get_noise_2d(p.x, p.y) * EDGE_NOISE
			var keep: bool = density_at.is_null() or rng.randf() < float(density_at.call(p)) / density
			if not (band.call(d) and keep):
				continue
			var k: String = _pick(species_at.call(p), p, rng)
			if k.is_empty():
				continue
			var name: String = k if _lib.has(k) else (_prefixes[k] as Array)[rng.randi() % (_prefixes[k] as Array).size()]
			var v: float = rng.randf_range(sizes.x, sizes.y)
			var s: float = v if by_scale else v / TILE_M / float(_lib[name]["h"])
			_place(name, p, s, rng)


## Вид за шумом насаджень: сусідні дерева здебільшого одного виду. Шум береться як квантиль
## по лісу карти: значення шуму скупчені посередині, і без цього види з кінця списку (берези й
## дуби) майже не траплялись — частки видів не відповідали вагам.
func _pick(weights: Dictionary, p: Vector2, rng: RandomNumberGenerator) -> String:
	var q: float = float(_stand_sorted.bsearch(_stand.get_noise_2d(p.x, p.y))) / maxf(_stand_sorted.size(), 1.0)
	var r: float = clampf(q + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	var acc: float = 0.0
	var total: float = 0.0
	for k: String in weights:
		total += weights[k]
	for k: String in weights:
		acc += weights[k] / total
		if r <= acc and (_prefixes.has(k) or _lib.has(k)):
			return k
	for k: String in weights:
		if _prefixes.has(k) or _lib.has(k):
			return k
	return ""


## Масштаб s (по висоті); дерева ширші за свою висоту в WIDE разів, щоб ліс зімкнувся.
## Крона не нависає над проламом.
func _place(name: String, p: Vector2, s: float, rng: RandomNumberGenerator, fixed: bool = false) -> void:
	# Ліс стоїть лише на клітинках лісу: край рваний (шум глибини), але не заходить у поле, де
	# дерево стояло б на чужій клітинці й плутало б, де ліс за правилами.
	if not fixed and not _cells.has(Vector2i(roundi(p.x), roundi(p.y))):
		return
	var species: String = name.get_slice("_", 0)
	var w: float = 1.0
	var bd: float = broken_distance(_broken, p)
	if bd < LANE_NEAR:
		s *= 0.7
	elif species == "Spruce" and _season == "late":
		w = LATE_SPRUCE_W
	elif species in ["Pine", "Spruce", "Birch", "Oak", "Hero"]:
		w = WIDE
	elif species == "Shrub":
		w = 1.3
	# AABB меша — центри карток; пучки виходять за нього ще на ~1,2 м угору й до 2 м убік.
	var r: float = float(_lib[name]["half"]) * s * w + 0.25
	# Нічого в коридорі просіки; далі дерева рідшають поступово, а не обриваються по межі клітинки.
	var gap: float = bd - r
	if gap < 0.0 or rng.randf() > smoothstep(0.0, LANE_THIN, gap):
		return
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * w, s, s * w)), Vector3(p.x, 0.0, p.y))
	var tone: float = 1.0 + TONE_VAR * _tone.get_noise_2d(p.x, p.y)
	var rgb := Color(tone, tone, tone)
	if species == "Shrub" and bd < 1.2:
		rgb *= 0.7  # темний підлісок біля просіки: світлі кущі читались мазками фарби
	if _season == "late" and species == "Spruce":
		rgb *= LATE_SPRUCE  # похмуре світло: ялини темніші й холодніші
	if _season == "summer" and SUMMER_TONE.has(species):
		rgb *= SUMMER_TONE[species]
	var turn: String = ""
	if _season == "early" and species in AUTUMN_SPECIES:
		turn = _turn_of(species, p)
		if turn == "orange":
			rgb *= TURN_ORANGE
		elif turn == "green":
			rgb *= TURN_GREEN
	_out.append({"node": name, "xf": xf, "pos": p, "r": r, "rgb": rgb, "turn": turn, "ground": false})


func _turn_of(species: String, p: Vector2) -> String:
	if _fixed_u.has(p):
		var u: float = _fixed_u[p]
		return "orange" if u < TURN_ORANGE_SHARE else ("green" if u >= 1.0 - TURN_GREEN_SHARE else "")
	var t: float = _turn.get_noise_2d(p.x, p.y)
	return "orange" if t > _turn_hi else ("green" if t < _turn_lo else "")


func _add(name: String, xf: Transform3D, p: Vector2, r: float, rgb: Color = Color.WHITE) -> void:
	if _lib.has(name) and _cells.has(Vector2i(roundi(p.x), roundi(p.y))):
		_out.append({"node": name, "xf": xf, "pos": p, "r": r, "rgb": rgb, "turn": "", "ground": false})


## Узлісся: на кожну сторону лісової клітинки, що дивиться в поле, — шматок смуги.
func _hedges() -> void:
	var area: Rect2i = _area()
	for c: Vector2i in _cells:
		if _broken.has(c) or not area.has_point(c):
			continue
		var open: Array[Vector2i] = []
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _cells.has(c + dir):
				open.append(dir)
		var corner: bool = open.size() >= 2
		for dir: Vector2i in open:
			var rng := _rng(Layer.HEDGE, c.x, c.y, dir.x * 3 + dir.y)
			if corner and rng.randf() < 0.15:
				continue  # опуклий кут заокруглюється
			var base: Vector2 = Vector2(c) + Vector2(dir) * 0.5
			# Не менше 0,15: смуга (і її зсув біля виходу просіки) лишається у своїй клітинці лісу.
			var inset: float = maxf(0.15, HEDGE_INSET + _noise.get_noise_2d(base.x * 3.1, base.y * 3.1) * HEDGE_WANDER)
			var p: Vector2 = Vector2(c) + Vector2(dir) * (0.5 - inset)
			var share: float = WOODS[_wood_at.call(p)]["hedge_evergreen"]
			if _season == "late":
				share = maxf(share, LATE_HEDGE_EVERGREEN)  # голі кущі пізньої осені нічого не ховають
			var name: String = "Hedge_Spruce" if rng.randf() < share else "Hedge_Shrub"
			var yaw: float = (PI / 2.0 if dir.x != 0 else 0.0) + deg_to_rad(rng.randf_range(-10.0, 10.0))
			# Біля входу просіки з поля смуга розвернута назовні й зсунута від просіки: вхід
			# розірваний і розкиданий, а не охайний отвір.
			for q: Vector2i in [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x)]:
				if _broken.has(c + q) and not _cells.has(c + q + dir):
					p -= Vector2(q) * 0.15
					p += Vector2(dir) * 0.1
					yaw += deg_to_rad(rng.randf_range(15.0, 25.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(rng.randf_range(0.9, 1.15), rng.randf_range(0.85, 1.15), 1.0))
			_add(name, Transform3D(basis, Vector3(p.x, 0.0, p.y)), p, 0.45)


## Напрям проламу в клітинці: уздовж сусідньої проламаної клітинки.
func _lane_yaw(c: Vector2i, rng: RandomNumberGenerator) -> float:
	if _broken.has(c + Vector2i(1, 0)) or _broken.has(c - Vector2i(1, 0)):
		return 0.0
	if _broken.has(c + Vector2i(0, 1)) or _broken.has(c - Vector2i(0, 1)):
		return PI / 2.0
	return rng.randf() * PI


## Проламана клітинка: розрита земля (`Soil_Lane`), гілля, 2–3 стовбури уздовж проламу по краях.
func _broken_cells() -> void:
	var area: Rect2i = _area()
	for c: Vector2i in _broken:
		if not _cells.has(c) or not area.has_point(c):
			continue
		var rng := _rng(Layer.BROKEN, c.x, c.y)
		var yaw: float = _lane_yaw(c, rng)
		var jit: float = deg_to_rad(rng.randf_range(-8.0, 8.0))
		var off := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08))
		_out.append({"node": "Soil_Lane", "xf": Transform3D(Basis(Vector3.UP, yaw + jit), Vector3(c.x, 0.0, c.y) + off),
				"pos": Vector2(c), "r": 0.5, "rgb": Color.WHITE, "turn": "", "ground": true})
		_add("Litter_A", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x, 0.0, c.y)), Vector2(c), 0.5)
		var along := Vector2(cos(yaw), -sin(yaw))
		var across := Vector2(-along.y, along.x)
		_lane_damage(c, along, across, rng)
		# Один-два повалені стовбури вздовж просіки, по різних її боках.
		for k in rng.randi_range(1, 2):
			var p := Vector2(c) + across * (1.0 if k % 2 == 0 else -1.0) * rng.randf_range(0.2, 0.35) + along * rng.randf_range(-0.2, 0.2)
			_pressed_log(p, yaw + deg_to_rad(rng.randf_range(-15.0, 15.0)), rng)


## Межа просіки рвана, а не по лінії клітинки: по боках — гілля на 0,3–0,5 тайла за краєм під
## стоячими деревами. Нічого стоячого чи прим'ятого, що стирчить, усередині просіки: прим'ятий
## кущ з камери читався кущем, що стоїть. Там, де просіка виходить у поле, — гілля врозкид біля
## виходу (ще в лісовій клітинці): вхід розірваний, а не двері.
func _lane_damage(c: Vector2i, along: Vector2, across: Vector2, rng: RandomNumberGenerator) -> void:
	for side: float in [1.0, -1.0]:
		var n := Vector2i(roundi(c.x + across.x * side), roundi(c.y + across.y * side))
		if _broken.has(n) or not _cells.has(n):
			continue
		var lp: Vector2 = Vector2(c) + across * side * rng.randf_range(0.8, 1.0) + along * rng.randf_range(-0.3, 0.3)
		_add("Litter_A", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.55, 1.0, 0.55)), Vector3(lp.x, 0.0, lp.y)), lp, 0.3)
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _cells.has(c + dir):
			continue
		for k in 2:
			var p: Vector2 = Vector2(c) + Vector2(dir) * rng.randf_range(0.3, 0.45) + across * rng.randf_range(-0.45, 0.45)
			_add("Litter_A", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.6, 1.0, 0.6)), Vector3(p.x, 0.0, p.y)), p, 0.3)


## Повалений стовбур на просіці: 1,5–2,5 клітинки завдовжки (Log_B — 4,5 м уздовж x), товщий у
## 1,3 раза (тонкий з камери читався жердиною), втиснутий у глину на ~10 см. Шейдер крони темнить
## кору стоячих стовбурів (bark_dark 0,45: вони в тіні крони), а цей лежить на відкритій просіці,
## тож тон `LOG_TONE` повертає йому сіро-бурий колір кори, а не чорний і не світлий.
func _pressed_log(p: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(rng.randf_range(2.7, 4.4), 1.3, 1.3))
	_add("Log_B", Transform3D(b, Vector3(p.x, -0.012, p.y)), p, 0.3, LOG_TONE.get(_season, Color.WHITE))
