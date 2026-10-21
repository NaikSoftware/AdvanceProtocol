class_name TerrainHeight
extends RefCounted
## Косметичний рельєф (рішення власника 2026-10-22): єдина карта висот, з якої беруть
## висоту ЗЕМЛЯ (вершинний шейдер), ВОДА, юніти, контури, кільця, міст, камера й пікінг.
## Це лише вигляд: жодне правило, видимість, дальність чи вартість руху її не читає,
## і в core/ її нема.
##
## Масштаб: клітинка = 8 м = 1.0 світу, тож 1 м = M = 0.125.
## Карта береться раз за карту з виду клітинок + шуму із seed (ім'я карти) і лежить у
## сітці `samples` відліків на клітинку; ця ж сітка — вершини меша землі й текстура RGBH,
## тож CPU і GPU бачать одну поверхню.

const M: float = 0.125
## Відліків на клітинку за замовчуванням; для великих карт bake() зменшує, щоб меш землі
## лишився в бюджеті трикутників (§8, ~50k на всю землю).
const SAMPLES_PER_TILE: int = 7
const MAX_GROUND_TRIS: int = 58000
## Вода на 1.25 м нижче верху берега (1.0-1.5 м): берег стоїть над водою ≥ 3 м схилу.
const WATER_LEVEL: float = -1.25 * M
## Висота настилу над верхом берега: щоб міст не зливався з дорогою.
const DECK_LIFT: float = 0.01

## Рельєф рівнини: дрібний ±0.35 м (плями 5-20 м) і широкий до ±1.7 м (хвиля 3.7-5.5 клітинки).
const _MICRO_AMP: float = 0.35 * M
const _BROAD_AMP: float = 1.7 * M
const _HILL_MIN: float = 3.5 * M
const _HILL_VAR: float = 2.0 * M
const _BED_MIN: float = 2.2 * M
const _BED_VAR: float = 0.5 * M
## Берег падає від верху до води на 0.3-0.5 клітинки (схил ≤ ~35°); степінь робить верх м'яким.
const _BANK_RUN: float = 0.4
const _BANK_RUN_VAR: float = 0.1
const _BANK_POWER: float = 1.35
## Меандр: бічний зсув русла ±0.3 клітинки (хвиля ~5), ширина ±0.15, дрібна рваність ±0.12.
## Усе гаситься до нуля в центрах клітинок (правила: центр не-води сухий, води — мокрий) і
## біля мостів (русло йде прямо під ними).
const _MEANDER: float = 0.3
const _WIDTH_VAR: float = 0.15
const _SHORE_JITTER: float = 0.12
const _BRIDGE_STRAIGHT: float = 0.5
## Крайовий обрив (лише без відступу): зовнішні 0.5 клітинки плити м'яко хилить униз.
const _RIM_WIDTH: float = 0.5
const _RIM_DROP: float = 0.1
const _CURV_RANGE: float = 1.5 * M
## Дорога глаже за поле, але не геометрично плоска: слідує за ґрунтом.
const _ROAD_DAMP: float = 0.9

## Поточна карта висот бою. Одна на процес: BoardView ставить її в build() і знімає, виходячи
## зі сцени; без неї (тести, меню) все лежить на y = 0.
static var active: TerrainHeight = null
## Лише для перевірки вигляду (скріншоти «з хвилями / без»): множник широкої хвилі рівнини.
static var undulation_scale: float = 1.0

var margin: int = 0
var board_width: int = 0
var board_height: int = 0
var samples: int = SAMPLES_PER_TILE
## Відліків по осях: (розмір + 2 * відступ) * samples + 1.
var cols: int = 0
var rows: int = 0
var _h: PackedFloat32Array = PackedFloat32Array()
var _water: PackedFloat32Array = PackedFloat32Array()
var _curv: PackedFloat32Array = PackedFloat32Array()
var _min: float = 0.0
var _max: float = 0.0
## клітинка мосту -> верх настилу.
var _deck: Dictionary = {}
# Клас клітинки (1 — так): вода (з мостами), міст; і «поряд з…».
var _wgrid: PackedByteArray = PackedByteArray()
var _bgrid: PackedByteArray = PackedByteArray()
var _wnear: PackedByteArray = PackedByteArray()
var _bnear: PackedByteArray = PackedByteArray()


## seed — з імені карти (BoardView.relief_seed); та сама карта дає той самий рельєф.
static func bake(board: Board, p_margin: int, seed_value: int) -> TerrainHeight:
	var t := TerrainHeight.new()
	t.margin = p_margin
	t.board_width = board.width
	t.board_height = board.height
	while t.samples > 2 and (board.width + 2 * p_margin) * (board.height + 2 * p_margin) * t.samples * t.samples * 2 > MAX_GROUND_TRIS:
		t.samples -= 1
	t._bake(board, seed_value)
	return t


## Висота землі під світовою точкою (білінійно по відліках, за межею — крайова).
func at(x: float, z: float) -> float:
	var s: float = float(samples)
	var fx: float = clampf((x + 0.5 + margin) * s, 0.0, float(cols - 1))
	var fz: float = clampf((z + 0.5 + margin) * s, 0.0, float(rows - 1))
	var ix: int = mini(int(fx), cols - 2)
	var iz: int = mini(int(fz), rows - 2)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var a: float = lerpf(_h[iz * cols + ix], _h[iz * cols + ix + 1], tx)
	var b: float = lerpf(_h[(iz + 1) * cols + ix], _h[(iz + 1) * cols + ix + 1], tx)
	return lerpf(a, b, tz)


## Висота під світовою точкою для всього, що лежить на землі; 0 без карти.
static func ground_y(x: float, z: float) -> float:
	return active.at(x, z) if active != null else 0.0


## Верх настилу мосту в клітинці: рівень найвищого берега при переправі (дорога на обох
## кінцях), а не русло. Клітинка не-мосту — висота землі.
func deck_y(cell: Vector2i) -> float:
	return _deck.get(cell, at(float(cell.x), float(cell.y)))


func min_height() -> float:
	return _min


func max_height() -> float:
	return _max


## Одиничний нормаль поверхні (скінченні різниці на кроці одного відліку).
func normal_at(x: float, z: float) -> Vector3:
	var e: float = 1.0 / float(samples)
	return Vector3(at(x - e, z) - at(x + e, z), 2.0 * e, at(x, z - e) - at(x, z + e)).normalized()


## RGB16F-текстура для шейдерів: R — висота, G — 1 під водою й спад до 0 на верху берега
## (маска берега), B — кривизна -1..1 (запечене затінення, §8).
## Піксель (i, j) — у світі (-0.5 - відступ + i / samples, ... j / samples).
func image() -> Image:
	var img := Image.create_empty(cols, rows, false, Image.FORMAT_RGBH)
	for j in rows:
		for i in cols:
			var k: int = j * cols + i
			img.set_pixel(i, j, Color(_h[k], _water[k], _curv[k]))
	return img


## Світова точка, де промінь вперше входить у поверхню, або null (промінь не йде вниз чи
## мине землю). Крок 0.05 по променю й уточнення бісекцією: точніше за піксель.
func pick(origin: Vector3, dir: Vector3) -> Variant:
	if dir.y >= -1e-6:
		return null
	var d: Vector3 = dir.normalized()
	var t: float = maxf((_max + 0.01 - origin.y) / d.y, 0.0)
	var t_end: float = (_min - 0.01 - origin.y) / d.y
	var step: float = 0.05
	var prev: float = t
	while t <= t_end + step:
		var p: Vector3 = origin + d * t
		if p.y <= at(p.x, p.z):
			var lo: float = prev
			var hi: float = t
			for _i in 14:
				var mid: float = 0.5 * (lo + hi)
				var q: Vector3 = origin + d * mid
				if q.y <= at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return origin + d * hi
		prev = t
		t += step
	return null


func _bake(board: Board, seed_value: int) -> void:
	var s: int = samples
	var fs: float = float(s)
	var bw: int = board_width
	var bh: int = board_height
	cols = (bw + 2 * margin) * s + 1
	rows = (bh + 2 * margin) * s + 1

	# Класи клітинок одним проходом: далі рахуємо лише з масивів, без Board.
	_wgrid.resize(bw * bh)
	_bgrid.resize(bw * bh)
	var hgrid := PackedByteArray()
	var rgrid := PackedByteArray()
	var pgrid := PackedByteArray()
	hgrid.resize(bw * bh)
	rgrid.resize(bw * bh)
	pgrid.resize(bw * bh)
	var has_water := false
	var has_bridge := false
	var has_hill := false
	var has_road := false
	var has_pad := false
	for cy in bh:
		for cx in bw:
			var kind: int = board.kind_at(Vector2i(cx, cy))
			var i: int = cy * bw + cx
			_wgrid[i] = 1 if _is_water(kind) else 0
			_bgrid[i] = 1 if _is_bridge(kind) else 0
			hgrid[i] = 1 if kind == Terrain.Kind.HILL else 0
			rgrid[i] = 1 if kind == Terrain.Kind.ROAD else 0
			pgrid[i] = 1 if (kind == Terrain.Kind.BUILDING or kind == Terrain.Kind.RUBBLE) else 0
			has_water = has_water or _wgrid[i] == 1
			has_bridge = has_bridge or _bgrid[i] == 1
			has_hill = has_hill or hgrid[i] == 1
			has_road = has_road or rgrid[i] == 1
			has_pad = has_pad or pgrid[i] == 1
	_wnear = _near_changes(_wgrid, bw, bh)
	_bnear = _dilate(_bgrid, bw, bh, 2)

	# Індикатори на відліках (клітинка точки; на межі зсув у пів відліку згладжує розмиття).
	var hill := PackedFloat32Array()
	var road := PackedFloat32Array()
	var pad := PackedFloat32Array()
	hill.resize(cols * rows)
	road.resize(cols * rows)
	pad.resize(cols * rows)
	var warp_x := _noise(seed_value + 404, 0.45)
	var warp_z := _noise(seed_value + 505, 0.45)
	if has_hill or has_road or has_pad:
		for j in rows:
			var z: float = -0.5 - margin + float(j) / fs
			for i in cols:
				var x: float = -0.5 - margin + float(i) / fs
				var k: int = j * cols + i
				if has_road or has_pad:
					var c: int = clampi(roundi(z), 0, bh - 1) * bw + clampi(roundi(x), 0, bw - 1)
					road[k] = float(rgrid[c])
					pad[k] = float(pgrid[c])
				if has_hill:
					# Обрис пагорба рваний: клітинку беруть із зсувом шумом.
					var hx: int = clampi(roundi(x + 0.3 * warp_x.get_noise_2d(x, z)), 0, bw - 1)
					var hz: int = clampi(roundi(z + 0.3 * warp_z.get_noise_2d(x, z)), 0, bh - 1)
					hill[k] = float(hgrid[hz * bw + hx])

	# Пагорб витягнуто вздовж осі, обраної seed'ом карти (1.5 : 1); спад ≥ 1 клітинки.
	var long_x: bool = (seed_value & 1) == 0
	var hill_a := PackedFloat32Array()
	var hill_b := PackedFloat32Array()
	if has_hill:
		hill_a = _blur(hill, (0.9 if long_x else 0.6) * fs, (0.6 if long_x else 0.9) * fs)
		hill_b = _blur(hill, (1.8 if long_x else 1.2) * fs, (1.2 if long_x else 1.8) * fs)
	var road_m := PackedFloat32Array()
	var pad_m := PackedFloat32Array()
	if has_road:
		road_m = _blur(road, 0.35 * fs, 0.35 * fs)
	if has_pad:
		pad_m = _blur(pad, 0.35 * fs, 0.35 * fs)

	var n1 := _noise(seed_value, 0.27)
	var n2 := _noise(seed_value + 101, 0.65)
	var n3 := _noise(seed_value + 202, 0.08)
	var n4 := _noise(seed_value + 303, 0.1)
	var nb1 := _noise(seed_value + 606, 0.18)
	var nb2 := _noise(seed_value + 616, 0.27)
	var n_mx := _noise(seed_value + 717, 0.2)
	var n_mz := _noise(seed_value + 727, 0.2)
	var n_w := _noise(seed_value + 737, 0.25)
	var n_s1 := _noise(seed_value + 747, 0.4)
	var n_s2 := _noise(seed_value + 757, 0.9)
	var n_crest := _noise(seed_value + 808, 0.5)

	_h.resize(cols * rows)
	_water.resize(cols * rows)
	_min = INF
	_max = -INF
	var drop: float = -WATER_LEVEL
	# Перший прохід: знакова відстань до води d і зсув берега shift (одне поле для урізу,
	# верху берега й ширини схилу). Далі d злегка розмивається, щоб не лишати заломів.
	var dg := PackedFloat32Array()
	var sg := PackedFloat32Array()
	dg.resize(cols * rows)
	sg.resize(cols * rows)
	for j in rows:
		var z: float = -0.5 - margin + float(j) / fs
		var cz: int = clampi(roundi(z), 0, bh - 1)
		var fz: float = absf(z - roundf(z))
		for i in cols:
			var x: float = -0.5 - margin + float(i) / fs
			var k: int = j * cols + i
			var cell: int = cz * bw + clampi(roundi(x), 0, bw - 1)
			var inside: bool = _wgrid[cell] == 1
			dg[k] = -2.0 if inside else 2.0
			if has_water and _wnear[cell] == 1:
				# Усе, що зсуває берег, гаситься до 0 у центрах клітинок і біля мостів.
				var fac: float = smoothstep(0.1, 0.4, maxf(absf(x - roundf(x)), fz))
				if has_bridge and _bnear[cell] == 1:
					fac *= smoothstep(_BRIDGE_STRAIGHT, _BRIDGE_STRAIGHT + 0.5, _bridge_dist(x, z))
				var qx: float = x + fac * _MEANDER * clampf(1.5 * n_mx.get_noise_2d(x, z), -1.0, 1.0)
				var qz: float = z + fac * _MEANDER * clampf(1.5 * n_mz.get_noise_2d(x, z), -1.0, 1.0)
				var shift: float = fac * (_WIDTH_VAR * clampf(1.5 * n_w.get_noise_2d(x, z), -1.0, 1.0)
						+ _SHORE_JITTER * clampf(1.8 * (0.7 * n_s1.get_noise_2d(x, z) + 0.3 * n_s2.get_noise_2d(x, z)), -1.0, 1.0))
				dg[k] = _water_dist(qx, qz) + shift
				sg[k] = shift
	if has_water:
		dg = _blur(dg, 0.8, 0.8)
		sg = _blur(sg, 0.8, 0.8)
	for j in rows:
		var z: float = -0.5 - margin + float(j) / fs
		for i in cols:
			var x: float = -0.5 - margin + float(i) / fs
			var k: int = j * cols + i
			var d: float = dg[k]
			# Верх берега з того самого поля, що й уріз: ширина схилу 0.3-0.5 клітинки.
			var run: float = clampf(_BANK_RUN + 0.35 * sg[k], _BANK_RUN - _BANK_RUN_VAR, _BANK_RUN + _BANK_RUN_VAR)
			var bed: float = _BED_MIN + _BED_VAR * (0.5 + 0.5 * n4.get_noise_2d(x, z)) if has_water else 0.0
			var near_water: float = smoothstep(0.1, 1.2, d) if d > 0.0 else 0.0
			var undul: float = _MICRO_AMP * (0.7 * n1.get_noise_2d(x, z) + 0.3 * n2.get_noise_2d(x, z)) \
					+ undulation_scale * _BROAD_AMP * clampf(1.6 * (0.65 * nb1.get_noise_2d(x, z) + 0.35 * nb2.get_noise_2d(x, z)), -1.0, 1.0)
			# Суха земля не опускається нижче рівня води (інакше впадина стала б озером, бо
			# вода береться за висотою): м'яка підлога на -0.6 м, далі нахил 0.3.
			if undul < -0.6 * M:
				undul = -0.6 * M + (undul + 0.6 * M) * 0.3
			var damp: float = near_water
			if has_road:
				damp *= 1.0 - _ROAD_DAMP * smoothstep(0.0, 0.6, road_m[k])
			if has_pad:
				damp *= 1.0 - smoothstep(0.0, 0.4, pad_m[k])
			var rise := 0.0
			if has_hill:
				var hill_h: float = _HILL_MIN + _HILL_VAR * (0.5 + 0.5 * n3.get_noise_2d(x, z))
				rise = hill_h * (0.7 * smoothstep(0.0, 0.55, hill_a[k]) + 0.3 * smoothstep(0.0, 0.7, hill_b[k]))
				rise *= 1.0 + 0.12 * n_crest.get_noise_2d(x, z)
			var sink := 0.0
			if d >= 0.0:
				sink = drop * pow(1.0 - clampf(d / run, 0.0, 1.0), _BANK_POWER)
			elif has_water:
				sink = drop + (bed - drop) * smoothstep(0.0, 0.5, -d)
			var v: float = undul * damp + rise - sink
			if margin == 0:
				var e: float = minf(minf(x + 0.5, bw - 0.5 - x), minf(z + 0.5, bh - 0.5 - z))
				if e < _RIM_WIDTH:
					v -= _RIM_DROP * pow(1.0 - maxf(e, 0.0) / _RIM_WIDTH, 2.0)
			_h[k] = v
			# G: 1 під водою, 0 на верху берега (d = run), між ними — схил.
			_water[k] = clampf(1.0 - d / run, 0.0, 1.0) if has_water else 0.0
			_min = minf(_min, v)
			_max = maxf(_max, v)
	# Кривизна: висота мінус її розмиття на ~1.2 клітинки, у масштабі 1.5 м.
	var soft: PackedFloat32Array = _blur(_h, 1.2 * fs, 1.2 * fs)
	_curv.resize(cols * rows)
	for k in _h.size():
		_curv[k] = clampf((_h[k] - soft[k]) / _CURV_RANGE, -1.0, 1.0)
	_bake_decks(board)


## Настил кожної переправи — на рівні найвищої суші, що торкається її клітинок (дорога на
## кінцях), бо міст тримається на берегах, а не на руслі. Одна висота на всю групу.
func _bake_decks(board: Board) -> void:
	var seen: Dictionary = {}
	for y in board.height:
		for x in board.width:
			var start := Vector2i(x, y)
			if seen.has(start) or not _is_bridge(board.kind_at(start)):
				continue
			var group: Array[Vector2i] = [start]
			seen[start] = true
			var top := -INF
			var i := 0
			while i < group.size():
				var c: Vector2i = group[i]
				i += 1
				for d in Board.DIRS_4:
					var n: Vector2i = c + d
					if not board.in_bounds(n):
						continue
					var kind: int = board.kind_at(n)
					if _is_bridge(kind):
						if not seen.has(n):
							seen[n] = true
							group.append(n)
					elif not _is_water(kind):
						top = maxf(top, at(float(n.x), float(n.y)))
			if top == -INF:
				top = 0.0
			for c in group:
				_deck[c] = top + DECK_LIFT


static func _is_water(kind: int) -> bool:
	return kind == Terrain.Kind.WATER or _is_bridge(kind)


static func _is_bridge(kind: int) -> bool:
	return kind == Terrain.Kind.BRIDGE or kind == Terrain.Kind.BRIDGE_DESTROYED


static func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value
	n.frequency = frequency
	return n


## 1 — у радіусі 2 клітинок є клітинка іншого класу (там відстань до межі ще рахується).
func _near_changes(grid: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for cy in h:
		for cx in w:
			var v: int = grid[cy * w + cx]
			var hit := 0
			for yy in range(maxi(cy - 2, 0), mini(cy + 3, h)):
				for xx in range(maxi(cx - 2, 0), mini(cx + 3, w)):
					if grid[yy * w + xx] != v:
						hit = 1
			out[cy * w + cx] = hit
	return out


## 1 — у радіусі r клітинок є клітинка класу 1.
func _dilate(grid: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for cy in h:
		for cx in w:
			var hit := 0
			for yy in range(maxi(cy - r, 0), mini(cy + r + 1, h)):
				for xx in range(maxi(cx - r, 0), mini(cx + r + 1, w)):
					if grid[yy * w + xx] == 1:
						hit = 1
			out[cy * w + cx] = hit
	return out


## Знакова відстань (клітинки, ±2) від точки до межі води: мінус усередині. Межа — край
## квадратів клітинок, тож центр клітинки не-води завжди має d >= 0.5 до зсуву.
func _water_dist(x: float, z: float) -> float:
	var cx0: int = clampi(roundi(x), 0, board_width - 1)
	var cz0: int = clampi(roundi(z), 0, board_height - 1)
	var inside: bool = _wgrid[cz0 * board_width + cx0] == 1
	var best: float = 2.0
	for cz in range(maxi(cz0 - 2, 0), mini(cz0 + 3, board_height)):
		for cx in range(maxi(cx0 - 2, 0), mini(cx0 + 3, board_width)):
			if (_wgrid[cz * board_width + cx] == 1) == inside:
				continue
			var dx: float = maxf(absf(x - cx) - 0.5, 0.0)
			var dz: float = maxf(absf(z - cz) - 0.5, 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return -best if inside else best


## Відстань (клітинки, до 2) від точки до найближчої клітинки мосту.
func _bridge_dist(x: float, z: float) -> float:
	var cx0: int = clampi(roundi(x), 0, board_width - 1)
	var cz0: int = clampi(roundi(z), 0, board_height - 1)
	var best: float = 2.0
	for cz in range(maxi(cz0 - 2, 0), mini(cz0 + 3, board_height)):
		for cx in range(maxi(cx0 - 2, 0), mini(cx0 + 3, board_width)):
			if _bgrid[cz * board_width + cx] == 0:
				continue
			var dx: float = maxf(absf(x - cx) - 0.5, 0.0)
			var dz: float = maxf(absf(z - cz) - 0.5, 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return best


## Гаусове розмиття (sigma по X і по Z у відліках), що наближене трьома прохідами рухомого
## середнього: вартість не залежить від sigma. Крайові відліки продовжуються.
func _blur(src: PackedFloat32Array, sigma_x: float, sigma_z: float) -> PackedFloat32Array:
	var a: PackedFloat32Array = src.duplicate()
	var b := PackedFloat32Array()
	b.resize(cols * rows)
	var rx: int = _box_radius(sigma_x)
	var rz: int = _box_radius(sigma_z)
	for _pass in 3:
		_box_pass(a, b, cols, 1, rows, cols, rx)
		_box_pass(b, a, rows, cols, cols, 1, rz)
	return a


## Радіус рухомого середнього, що за три проходи дає sigma (ширина ідеального ящика).
static func _box_radius(sigma: float) -> int:
	var w: float = sqrt(12.0 * sigma * sigma / 3.0 + 1.0)
	return maxi(0, int((w - 1.0) * 0.5 + 0.5))


## Один прохід вздовж осі: n відліків із кроком stride на кожній із lines ліній.
static func _box_pass(src: PackedFloat32Array, dst: PackedFloat32Array, n: int, stride: int, lines: int, line_stride: int, r: int) -> void:
	var inv: float = 1.0 / float(2 * r + 1)
	for l in lines:
		var base: int = l * line_stride
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += src[base + clampi(k, 0, n - 1) * stride]
		for i in n:
			dst[base + i * stride] = acc * inv
			acc += src[base + clampi(i + r + 1, 0, n - 1) * stride] - src[base + clampi(i - r, 0, n - 1) * stride]
