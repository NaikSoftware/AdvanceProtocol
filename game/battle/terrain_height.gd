class_name TerrainHeight
extends RefCounted
## Косметичний рельєф: єдина карта висот, з якої беруть
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
## Частка висоти пагорба, яку гарантовано тримає центр кожної клітинки HILL, хоч куди
## зсунувся обрис.
const _HILL_KEEP: float = 0.62
const _BED_MIN: float = 2.2 * M
const _BED_VAR: float = 0.5 * M
## Берег падає від верху до води на 0.3-0.5 клітинки (схил ≤ ~35°); степінь робить верх м'яким.
const _BANK_RUN: float = 0.4
const _BANK_RUN_VAR: float = 0.1
const _BANK_POWER: float = 1.35
## Асиметрія берегів за кривизною осі русла (RiverCourse): ширина схилу множиться на
## 2^(-bend), тож на зовнішній стороні повороту (bend = 1) вона вдвічі менша — 1.2-2 м крутого
## обриву, а на внутрішній (bend = -1) вдвічі більша — 4.8-8 м пологої піщаної коси.
## Прямий плес (bend = 0) не міняється.
## Ширина схилу гуляє вздовж берега на ±30 % (хвиля ~2.5 клітинки), щоб не було рівної смуги.
const _RUN_WAVE: float = 0.3
## Зовнішній берег різкіший за верх (степінь менший), внутрішній — рівномірний схил.
const _CUT_POWER_DROP: float = 0.35
const _BAR_POWER_DROP: float = 0.35
## Нерівність урізу лише ЗВУЖУЄ воду (зсув ≥ 0), щоб не з'їсти запас до центрів суші:
## 0..0.12 клітинки з хвилею 1-2.5 клітинки і 0..0.08 (0.64 м) з хвилею 0.3-0.6 (2-5 м).
const _SHORE_JITTER: float = 0.12
const _SHORE_FINE: float = 0.08
const _SHORE_MEAN: float = 0.1
## Додаткова хвиля берега поблизу мосту (клітинок, лише звужує воду).
const _APPROACH_WOBBLE: float = 0.15
## Крок грубої сітки поля річки (у відліках); далі білінійно.
const _RIVER_STEP: int = 2
## Згладжування контуру води (клітинки): заповнює западини між виступами, ширину русла не чіпає.
const _OUTLINE_SIGMA: float = 0.4
## Згладжування поля ставка (клітинки) і поправка на усадку від нього.
const _POND_SIGMA: float = 0.4
const _POND_BIAS: float = 0.05
const _POND_SHRINK: float = 0.12
## Мілина (d >= цього), не з'єднана з сушею, — теж «острів»: затоплюється.
const _HOLE_LEVEL: float = -0.2
## Крайовий обрив (лише без відступу й кільця): зовнішні 0.5 клітинки плити м'яко хилить униз.
const _RIM_WIDTH: float = 0.5
const _RIM_DROP: float = 0.1
const _LN2: float = 0.6931472
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
## Гладка вісь річки, з якої взято відстань до урізу; null — води нема.
var course: RiverCourse = null
## Переправи (RiverCourse.build): клітинки, центр, вісь, довжина й ширина настилу.
var _groups: Array[Dictionary] = []
## Дорога як власна геометрія (RoadCourse); null — доріг нема. Її растр рівняє рельєф під
## дорогою.
var roads: RoadCourse = null
## Вигин для шейдера: 0.5 + 0.5 * bend, bend -1 (коса) .. +1 (підмитий берег), 0 — плес.
var _bar: PackedFloat32Array = PackedFloat32Array()
var _min: float = 0.0
var _max: float = 0.0
## клітинка мосту -> верх настилу.
var _deck: Dictionary = {}
# Клітинка води (з мостами): 1 — так.
var _wgrid: PackedByteArray = PackedByteArray()
## Ширина кільця, на яку зсунуті координати світу під час bake (0 — кільця нема).
var _shift: int = 0
var _texture: ImageTexture = null


## seed — з імені карти (BoardView.relief_seed); та сама карта дає той самий рельєф.
## surface — MapData.surface (тут з підтипів береться лише тип дороги для її ширини);
## порожній — усі 0.
## ring > 0: board — уже світ (дошка разом із кільцем, Surroundings.world_board), на ring клітинок
## ширший з кожного боку. Запікається в координатах світу, потім зсувається на ring, тож at(),
## deck_y(), bridge_groups() і image() далі говорять координатами дошки. course і roads лишаються
## в координатах світу: їх читають лише растри, а ті й так покривають увесь світ.
static func bake(board: Board, p_margin: int, seed_value: int, surface: PackedByteArray = PackedByteArray(), ring: int = 0) -> TerrainHeight:
	var t := TerrainHeight.new()
	t.margin = p_margin
	t.board_width = board.width
	t.board_height = board.height
	t._shift = ring
	# Бюджет трикутників рахує лише дошку: кільце має власний грубіший меш (Surroundings).
	while t.samples > 2 and (board.width - 2 * ring) * (board.height - 2 * ring) * t.samples * t.samples * 2 > MAX_GROUND_TRIS:
		t.samples -= 1
	t._bake(board, seed_value, surface)
	if ring > 0:
		t._to_board_coords(ring)
	return t


func _to_board_coords(ring: int) -> void:
	margin += ring
	board_width -= 2 * ring
	board_height -= 2 * ring
	var off := Vector2i(ring, ring)
	var deck: Dictionary = {}
	for c: Vector2i in _deck:
		deck[c - off] = _deck[c]
	_deck = deck
	for g in _groups:
		var cells: Array[Vector2i] = []
		for c: Vector2i in g["cells"]:
			cells.append(c - off)
		g["cells"] = cells
		g["centre"] = (g["centre"] as Vector2) - Vector2(off)


## Шум рельєфу прив'язаний до дошки: у світі з кільцем (координати зсунуті на _shift) дошка
## лишається тим самим рельєфом, що й без кільця.
func _nz(seed_value: int, frequency: float) -> FastNoiseLite:
	var n := _noise(seed_value, frequency)
	n.offset = Vector3(-_shift, -_shift, 0.0)
	return n


## Переправи (зв'язні групи клітинок мосту): cells, centre, axis, length, across.
func bridge_groups() -> Array[Dictionary]:
	return _groups


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


## RGBA16F-текстура для шейдерів: R — висота, G — 1 під водою й спад до 0 на верху берега
## (маска берега), B — кривизна -1..1 (запечене затінення, §8), A — 0.5 + 0.5 * bend (коса < 0.5 < підмитий берег).
## Піксель (i, j) — у світі (-0.5 - відступ + i / samples, ... j / samples).
func image() -> Image:
	# Через сирі байти RGBAF і перетворення рушієм: set_pixel на кожен відлік світу з кільцем — сотні мс.
	var px := PackedFloat32Array()
	px.resize(cols * rows * 4)
	for k in cols * rows:
		px[k * 4] = _h[k]
		px[k * 4 + 1] = _water[k]
		px[k * 4 + 2] = _curv[k]
		px[k * 4 + 3] = _bar[k]
	var img := Image.create_from_data(cols, rows, false, Image.FORMAT_RGBAF, px.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	return img


## image() як текстура, одна на карту: земля й вода беруть ту саму, а не будують її двічі.
func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(image())
	return _texture


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


func _bake(board: Board, seed_value: int, surface: PackedByteArray) -> void:
	var s: int = samples
	var fs: float = float(s)
	var bw: int = board_width
	var bh: int = board_height
	cols = (bw + 2 * margin) * s + 1
	rows = (bh + 2 * margin) * s + 1

	# Класи клітинок одним проходом: далі рахуємо лише з масивів, без Board.
	_wgrid.resize(bw * bh)
	var bgrid := PackedByteArray()
	bgrid.resize(bw * bh)
	var hgrid := PackedByteArray()
	var rgrid := PackedByteArray()
	var pgrid := PackedByteArray()
	hgrid.resize(bw * bh)
	rgrid.resize(bw * bh)
	pgrid.resize(bw * bh)
	var has_water := false
	var has_hill := false
	var has_road := false
	var has_pad := false
	for cy in bh:
		for cx in bw:
			var kind: int = board.kind_at(Vector2i(cx, cy))
			var i: int = cy * bw + cx
			_wgrid[i] = 1 if _is_water(kind) else 0
			bgrid[i] = 1 if _is_bridge(kind) else 0
			hgrid[i] = 1 if kind == Terrain.Kind.HILL else 0
			rgrid[i] = 1 if kind == Terrain.Kind.ROAD else 0
			pgrid[i] = 1 if (kind == Terrain.Kind.BUILDING or kind == Terrain.Kind.RUBBLE) else 0
			has_water = has_water or _wgrid[i] == 1
			has_hill = has_hill or hgrid[i] == 1
			has_road = has_road or rgrid[i] == 1
			has_pad = has_pad or pgrid[i] == 1

	if has_water:
		_groups = _bridge_groups(board, bgrid)
	# Дорога — власна геометрія (RoadCourse): рельєф рівняється під намальованою дорогою, а не
	# під клітинками.
	var road_d := PackedFloat32Array()
	var road_rw: int = (bw + 2 * margin) * RoadCourse.PX
	if has_road:
		roads = RoadCourse.build(board, surface, margin, seed_value, _shift)
		road_d = roads.d_grid()

	# Індикатори на відліках. Пагорб — гладкий (білінійний по клітинках) індикатор у точці,
	# зсунутій шумом на ±1.2 клітинки (хвиля ~5 клітинок) і ±0.35 (~2): обрис — неправильний
	# овал без осей сітки; зсув ±0.6 дає майже коло (круговість 0.95+).
	# Межі зсуву (HILL — клітинка правил, штраф руху 20): поза клітинками пагорба й їхніми
	# сусідами підйому нема (agrid), а центр кожної клітинки пагорба тримає ≥ 62 % висоти
	# (hgrid, без зсуву, _HILL_KEEP).
	var agrid := PackedByteArray()
	agrid.resize(bw * bh)
	for cz in bh:
		for cx in bw:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var qx: int = cx + dx
					var qz: int = cz + dz
					if qx >= 0 and qz >= 0 and qx < bw and qz < bh and hgrid[qz * bw + qx] == 1:
						agrid[cz * bw + cx] = 1
	var hill := PackedFloat32Array()
	var pad := PackedFloat32Array()
	hill.resize(cols * rows)
	pad.resize(cols * rows)
	var warp_x := _nz(seed_value + 404, 0.2)
	var warp_z := _nz(seed_value + 505, 0.2)
	var warp_x2 := _nz(seed_value + 414, 0.5)
	var warp_z2 := _nz(seed_value + 515, 0.5)
	if has_hill or has_pad:
		for j in rows:
			var z: float = -0.5 - margin + float(j) / fs
			for i in cols:
				var x: float = -0.5 - margin + float(i) / fs
				var k: int = j * cols + i
				if has_pad:
					pad[k] = float(pgrid[clampi(roundi(z), 0, bh - 1) * bw + clampi(roundi(x), 0, bw - 1)])
				if has_hill:
					var hx: float = x + 1.2 * warp_x.get_noise_2d(x, z) + 0.35 * warp_x2.get_noise_2d(x, z)
					var hz: float = z + 1.2 * warp_z.get_noise_2d(x, z) + 0.35 * warp_z2.get_noise_2d(x, z)
					hill[k] = _bilinear_cells(hgrid, bw, bh, hx, hz)

	# Спад ≥ 1 клітинки, однаковий в усі боки (без витягування вздовж осі сітки).
	var hill_a := PackedFloat32Array()
	var hill_b := PackedFloat32Array()
	if has_hill:
		hill_a = _blur(hill, 0.75 * fs, 0.75 * fs)
		hill_b = _blur(hill, 1.5 * fs, 1.5 * fs)
	var pad_m := PackedFloat32Array()
	if has_pad:
		pad_m = _blur(pad, 0.35 * fs, 0.35 * fs)

	var n1 := _nz(seed_value, 0.27)
	var n2 := _nz(seed_value + 101, 0.65)
	var n3 := _nz(seed_value + 202, 0.08)
	var nb1 := _nz(seed_value + 606, 0.18)
	var nb2 := _nz(seed_value + 616, 0.27)
	var n_s3 := _nz(seed_value + 767, 2.2)
	var n_s1 := _nz(seed_value + 747, 0.4)
	var n_s2 := _nz(seed_value + 757, 0.9)
	var n_crest := _nz(seed_value + 808, 0.5)

	_h.resize(cols * rows)
	_bar.resize(cols * rows)
	_water.resize(cols * rows)
	_min = INF
	_max = -INF
	var drop: float = -WATER_LEVEL
	# Перший прохід: знакова відстань до урізу d (з гладкої осі річки, RiverCourse) і зсув
	# берега shift (нерівність урізу). Клітинки тут ні до чого: вода йде за віссю, а не за сіткою.
	var dg := PackedFloat32Array()
	var sg := PackedFloat32Array()
	dg.resize(cols * rows)
	dg.fill(2.0)
	sg.resize(cols * rows)
	var wd := PackedFloat32Array()
	var dc := PackedFloat32Array()
	var bc := PackedFloat32Array()
	if has_water:
		course = RiverCourse.build(_wgrid, bw, bh, margin + 3, _groups, seed_value, _shift)
		var fld: Array[PackedFloat32Array] = course.field(cols, rows, s, margin, _RIVER_STEP)
		dc = fld[0]
		bc = fld[1]
		# Спершу об'єднання капсул і дисків, потім згладжування його знакового поля, і лише тоді
		# нерівність урізу: інакше накладені виступи читаються як окремі «бульби» (ставок-хрест).
		# min(d, розмите d) — «замикання»: западини суші між виступами заповнюються, а вода
		# ніде не звужується (розмиття саме з'їдає вузькі ставки й стрімки). Рахуємо на грубій сітці.
		var cw: int = (cols - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
		var ch: int = (rows - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
		var pc: PackedFloat32Array = fld[2]
		var dc0: PackedFloat32Array = dc.duplicate()
		for k in dc0.size():
			dc0[k] = minf(dc[k], pc[k])
		# Ставок — об'єднання дисків: його поле згладжено сильніше (розмиття мінус поправка на усадку),
		# щоб у контурі не проступали сходинки клітинок; далі — спільне замикання з річкою.
		var sig_p: float = _POND_SIGMA * fs / float(_RIVER_STEP)
		var pond_soft: PackedFloat32Array = _blur(pc, sig_p, sig_p, cw, ch)
		var cstep: float = float(_RIVER_STEP) / fs
		for k in dc.size():
			# Усадка обмежена, щоб ставок з однієї клітинки не висох у клітинці (мокрі 25 %).
			if _edge_clear(k, cw, cstep):
				dc[k] = minf(dc[k], minf(pond_soft[k] - _POND_BIAS, pc[k] + _POND_SHRINK))
		var sig_c: float = _OUTLINE_SIGMA * fs / float(_RIVER_STEP)
		var soft_c: PackedFloat32Array = _blur(dc, sig_c, sig_c, cw, ch)
		for k in dc.size():
			if soft_c[k] < dc[k] and dc[k] < 0.6 and _edge_clear(k, cw, cstep):
				dc[k] = soft_c[k]
		for k in dg.size():
			dg[k] = RiverCourse.upsample(dc, cols, rows, _RIVER_STEP, k % cols, k / cols)
		_restore_land_clearance(dg, dc, dc0)
		for j in rows:
			var z: float = -0.5 - margin + float(j) / fs
			for i in cols:
				var k: int = j * cols + i
				var d: float = dg[k]
				if absf(d) < 1.2:
					var x: float = -0.5 - margin + float(i) / fs
					var jit: float = 0.5 + 0.5 * clampf(1.8 * (0.7 * n_s1.get_noise_2d(x, z) + 0.3 * n_s2.get_noise_2d(x, z)), -1.0, 1.0)
					var fine: float = 0.5 + 0.5 * clampf(1.5 * n_s3.get_noise_2d(x, z), -1.0, 1.0)
					var shift: float = _SHORE_JITTER * jit + _SHORE_FINE * fine
					# Прямий плес під мостом і за ним не лишається лінійкою: берег звужує воду ще на 0..0.15
					# хвилею ~3 клітинок, але не під самим настилом (піни моста).
					if not _groups.is_empty():
						shift += _APPROACH_WOBBLE * (0.5 + 0.5 * clampf(1.6 * n_s1.get_noise_2d(x * 0.6 + 31.0, z * 0.6 - 17.0), -1.0, 1.0)) * _bar_fade(x, z)
					dg[k] = d + shift
					# Ширину схилу веде відхил від середнього зсуву, а не сам зсув.
					sg[k] = shift - _SHORE_MEAN
		sg = _blur(sg, 0.8, 0.8)
		_fill_holes(dg)
		wd = _inner_distance(dg)
	for j in rows:
		var z: float = -0.5 - margin + float(j) / fs
		for i in cols:
			var x: float = -0.5 - margin + float(i) / fs
			var k: int = j * cols + i
			var d: float = dg[k]
			# Верх берега з того самого поля, що й уріз: ширина схилу 0.3-0.5 клітинки.
			var b: float = RiverCourse.upsample(bc, cols, rows, _RIVER_STEP, i, j) if has_water and absf(d) < 1.3 else 0.0
			var run: float = clampf(_BANK_RUN + 0.35 * sg[k], _BANK_RUN - _BANK_RUN_VAR, _BANK_RUN + _BANK_RUN_VAR) * exp(-b * _LN2) * (1.0 + _RUN_WAVE * clampf(1.5 * n_s1.get_noise_2d(x + 9.0, z - 4.0), -1.0, 1.0))
			var bed: float = _BED_MIN + 0.5 * _BED_VAR if has_water else 0.0
			var near_water: float = smoothstep(0.1, 1.2, d) if d > 0.0 else 0.0
			var undul: float = _MICRO_AMP * (0.7 * n1.get_noise_2d(x, z) + 0.3 * n2.get_noise_2d(x, z)) \
					+ undulation_scale * _BROAD_AMP * clampf(1.6 * (0.65 * nb1.get_noise_2d(x, z) + 0.35 * nb2.get_noise_2d(x, z)), -1.0, 1.0)
			# Суха земля не опускається нижче рівня води (інакше впадина стала б озером, бо
			# вода береться за висотою): м'яка підлога на -0.6 м, далі нахил 0.3.
			if undul < -0.6 * M:
				undul = -0.6 * M + (undul + 0.6 * M) * 0.3
			var damp: float = near_water
			if has_road:
				var rd: float = road_d[clampi(int((z + 0.5 + margin) * RoadCourse.PX), 0, road_d.size() / road_rw - 1) * road_rw + clampi(int((x + 0.5 + margin) * RoadCourse.PX), 0, road_rw - 1)]
				# Рівно під намальованою дорогою й 0.5 м за її краєм (поле відстані RoadCourse),
				# далі спад за 1.5 м.
				damp *= 1.0 - _ROAD_DAMP * (1.0 - smoothstep(0.5, 2.0, rd))
			if has_pad:
				damp *= 1.0 - smoothstep(0.0, 0.4, pad_m[k])
			var rise := 0.0
			if has_hill:
				var hill_h: float = _HILL_MIN + _HILL_VAR * (0.5 + 0.5 * n3.get_noise_2d(x, z))
				rise = hill_h * (0.7 * smoothstep(0.0, 0.55, hill_a[k]) + 0.3 * smoothstep(0.0, 0.7, hill_b[k]))
				rise *= 1.0 + 0.12 * n_crest.get_noise_2d(x, z)
				rise = maxf(rise * _bilinear_cells(agrid, bw, bh, x, z, true), _HILL_KEEP * hill_h * _bilinear_cells(hgrid, bw, bh, x, z, true))
				# Підйом не затікає у воду (розмиття пагорба), а то центр клітинки води виходить на суходіл.
				if has_water:
					rise *= smoothstep(0.0, 1.4, d)
			var sink := 0.0
			if d >= 0.0:
				sink = drop * pow(1.0 - clampf(d / run, 0.0, 1.0), _BANK_POWER - _CUT_POWER_DROP * maxf(b, 0.0) - _BAR_POWER_DROP * maxf(-b, 0.0))
			elif has_water:
				# Під косою мілина тягнеться далі, під підмитим берегом глибина одразу.
				# Глибина лише зростає з відстанню від урізу й за 0.3-0.5 клітинки сягає дна; без
				# шуму, щоб дно не підіймалось до поверхні посеред русла (темні плями крізь воду).
				sink = drop + (bed - drop) * smoothstep(0.0, clampf(0.5 * exp(-b * _LN2), 0.3, 0.5), maxf(-d, wd[k] - 1.0 / fs))
			var v: float = undul * damp + rise - sink
			if margin == 0 and _shift == 0:
				var e: float = minf(minf(x + 0.5, bw - 0.5 - x), minf(z + 0.5, bh - 0.5 - z))
				if e < _RIM_WIDTH:
					var lowered: float = v - _RIM_DROP * pow(1.0 - maxf(e, 0.0) / _RIM_WIDTH, 2.0)
					# Крайовий обрив не топить сушу біля води: інакше по краю дошки йде мокрий вінець.
					v = lowered if v < WATER_LEVEL else maxf(lowered, WATER_LEVEL + 0.001)
			_h[k] = v
			_bar[k] = 0.5 + 0.5 * (clampf(b, -1.0, 1.0) * (_bar_fade(x, z) if b < 0.0 else 1.0) if has_water else 0.0)
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


## Переправи для осі річки: зв'язні групи клітинок мосту; вісь настилу — та, де обидва кінці
## ланцюжка впираються в сушу (не воду), довжина й ширина — розміри групи.
func _bridge_groups(board: Board, bgrid: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for y in board.height:
		for x in board.width:
			var start := Vector2i(x, y)
			if seen.has(start) or bgrid[y * board.width + x] == 0:
				continue
			var group: Array[Vector2i] = [start]
			seen[start] = true
			var i := 0
			var lo := start
			var hi := start
			while i < group.size():
				var c: Vector2i = group[i]
				i += 1
				lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
				hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
				for d in Board.DIRS_4:
					var n: Vector2i = c + d
					if board.in_bounds(n) and bgrid[n.y * board.width + n.x] == 1 and not seen.has(n):
						seen[n] = true
						group.append(n)
			# Кінці уздовж осі: клітинки поза обмежувальною рамкою, у межах її ширини упоперек.
			var best_axis := Vector2i(1, 0)
			var best_score := -1
			for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var score := 0
				for c in group:
					for dir: Vector2i in [axis, -axis]:
						var n: Vector2i = c + dir
						if board.in_bounds(n) and bgrid[n.y * board.width + n.x] == 0 and _wgrid[n.y * board.width + n.x] == 0:
							score += 1
				if score > best_score:
					best_score = score
					best_axis = axis
			var ext: Vector2i = hi - lo + Vector2i.ONE
			out.append({
				"cells": group,
				"centre": Vector2(lo + hi) * 0.5,
				"axis": Vector2(best_axis),
				"length": float(ext.x if best_axis.x != 0 else ext.y),
				"across": float(ext.y if best_axis.x != 0 else ext.x),
			})
	return out


## Настил кожної переправи — на рівні найвищої суші, що торкається її клітинок (дорога на
## кінцях), бо міст тримається на берегах, а не на руслі. Одна висота на всю групу.
func _bake_decks(board: Board) -> void:
	for g in _groups:
		var top := -INF
		for c: Vector2i in g["cells"]:
			for d in Board.DIRS_4:
				var n: Vector2i = c + d
				if board.in_bounds(n) and not _is_water(board.kind_at(n)):
					top = maxf(top, at(float(n.x), float(n.y)))
		if top == -INF:
			top = 0.0
		for c: Vector2i in g["cells"]:
			_deck[c] = top + DECK_LIFT


## Вузол грубої сітки далі за 0.45 клітинки від краю дошки: розмиття продовжує крайові відліки, тож
## біля краю воно витягувало б воду смугою до самого краю з прямими боками.
func _edge_clear(k: int, cw: int, cstep: float) -> bool:
	var x: float = -0.5 - margin + float(k % cw) * cstep
	var z: float = -0.5 - margin + float(k / cw) * cstep
	return minf(minf(x + 0.5, board_width - 0.5 - x), minf(z + 0.5, board_height - 0.5 - z)) >= 0.45


## Замикання не підпускає воду до центру клітинки суші (юніти стоять там): біля кожного центру
## в радіусі 0.5 клітинки поле плавно (від 0.3) повертається до незамкненого. Перевірка на повній
## сітці, бо білінійний підйом між вузлами грубої сітки може піти нижче нуля.
func _restore_land_clearance(dg: PackedFloat32Array, dc: PackedFloat32Array, dc0: PackedFloat32Array) -> void:
	var fs: float = float(samples)
	var cw: int = (cols - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
	var rad: int = ceili(0.5 * fs)
	for cy in board_height:
		for cx in board_width:
			if _wgrid[cy * board_width + cx] == 1:
				continue
			var ci: int = (2 * cx + 1 + 2 * margin) * samples / 2
			var cj: int = (2 * cy + 1 + 2 * margin) * samples / 2
			var changed := false
			for nj in range((cj - rad) / _RIVER_STEP, (cj + rad) / _RIVER_STEP + 2):
				for ni in range((ci - rad) / _RIVER_STEP, (ci + rad) / _RIVER_STEP + 2):
					var nk: int = nj * cw + ni
					if ni >= 0 and nj >= 0 and ni < cw and nk < dc.size() and absf(dc[nk] - dc0[nk]) > 1e-5:
						changed = true
			if not changed:
				continue
			for j in range(maxi(cj - rad, 0), mini(cj + rad + 1, rows)):
				for i in range(maxi(ci - rad, 0), mini(ci + rad + 1, cols)):
					var dist: float = Vector2(i - ci, j - cj).length() / fs
					if dist >= 0.5:
						continue
					var orig: float = RiverCourse.upsample(dc0, cols, rows, _RIVER_STEP, i, j)
					var k: int = j * cols + i
					dg[k] = lerpf(maxf(orig, dg[k]), dg[k], smoothstep(0.3, 0.5, dist))


## Вода — суцільна площа без «островів»-артефактів: суша (d >= 0), не з'єднана з краєм карти й без
## жодного центру клітинки суші, затоплюється: острівець
## без клітинки під ним читається як дефект запікання. Справжній острів (є клітинка суші, юніти
## стоять на ній) лишається з берегами: правило стосується вигляду, а не логічної суші.
func _fill_holes(dg: PackedFloat32Array) -> void:
	var centres := PackedInt32Array()
	for cy in board_height:
		for cx in board_width:
			if _wgrid[cy * board_width + cx] == 0:
				centres.append(((2 * cy + 1 + 2 * margin) * samples / 2) * cols + (2 * cx + 1 + 2 * margin) * samples / 2)
	# Прохід 1: суша (d >= 0), не з'єднана з краєм, — острів: топимо його й смугу мілини навколо.
	var seen: PackedByteArray = _flood_from_border(dg, 0.0, centres)
	var deep := PackedInt32Array()
	for k in dg.size():
		if dg[k] >= 0.0 and seen[k] == 0:
			deep.append(k)
	for k in deep:
		var x: int = k % cols
		var y: int = k / cols
		for yy in range(maxi(y - 2, 0), mini(y + 3, rows)):
			for xx in range(maxi(x - 2, 0), mini(x + 3, cols)):
				if dg[yy * cols + xx] >= _HOLE_LEVEL:
					dg[yy * cols + xx] = -0.5
	# Прохід 2: мілина-горб (d >= -0.2) без з'єднання з краєм — теж острів.
	seen = _flood_from_border(dg, _HOLE_LEVEL, centres)
	for k in dg.size():
		if dg[k] >= _HOLE_LEVEL and seen[k] == 0:
			dg[k] = -0.5


## Відстань (клітинки) від мокрого відліку (d < 0) до найближчого сухого; хамфер 1 / 1.414, дві
## проходи. Вода за краєм карти — продовження води, суші там нема. Глибина дна — монотонна
## функція цієї відстані, тож усередині тіла води дно не підіймається до поверхні.
func _inner_distance(dg: PackedFloat32Array) -> PackedFloat32Array:
	var inf: float = 1e6
	var out := PackedFloat32Array()
	out.resize(cols * rows)
	for k in out.size():
		out[k] = inf if dg[k] < 0.0 else 0.0
	var diag: float = 1.4142
	for j in rows:
		for i in cols:
			var k: int = j * cols + i
			var v: float = out[k]
			if v == 0.0:
				continue
			if i > 0:
				v = minf(v, out[k - 1] + 1.0)
			if j > 0:
				v = minf(v, out[k - cols] + 1.0)
				if i > 0:
					v = minf(v, out[k - cols - 1] + diag)
				if i < cols - 1:
					v = minf(v, out[k - cols + 1] + diag)
			out[k] = v
	for j in range(rows - 1, -1, -1):
		for i in range(cols - 1, -1, -1):
			var k: int = j * cols + i
			var v: float = out[k]
			if v == 0.0:
				continue
			if i < cols - 1:
				v = minf(v, out[k + 1] + 1.0)
			if j < rows - 1:
				v = minf(v, out[k + cols] + 1.0)
				if i < cols - 1:
					v = minf(v, out[k + cols + 1] + diag)
				if i > 0:
					v = minf(v, out[k + cols - 1] + diag)
			out[k] = v
	var inv: float = 1.0 / float(samples)
	for k in out.size():
		out[k] *= inv
	return out


## Відліки, з'єднані (по 4) з краєм карти через значення d >= level.
func _flood_from_border(dg: PackedFloat32Array, level: float, extra: PackedInt32Array = PackedInt32Array()) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var stack: Array[int] = []
	for k in extra:
		stack.append(k)
	for i in cols:
		stack.append(i)
		stack.append((rows - 1) * cols + i)
	for j in rows:
		stack.append(j * cols)
		stack.append(j * cols + cols - 1)
	while not stack.is_empty():
		var k: int = stack.pop_back()
		if seen[k] == 1 or dg[k] < level:
			continue
		seen[k] = 1
		var x: int = k % cols
		var y: int = k / cols
		if x > 0:
			stack.append(k - 1)
		if x < cols - 1:
			stack.append(k + 1)
		if y > 0:
			stack.append(k - cols)
		if y < rows - 1:
			stack.append(k + cols)
	return seen


## 0 біля настилу, 1 далі 3 клітинок від центру переправи: піщані коси не лежать у кінців мосту
## (пісок біля настилу не відрізнити від в'їзду на міст).
func _bar_fade(x: float, z: float) -> float:
	var f := 1.0
	for g in _groups:
		f = minf(f, smoothstep(1.6, 3.0, Vector2(x, z).distance_to(g["centre"])))
	return f


## Білінійне значення сітки клітинок 0/1 у світовій точці (центр клітинки — цілі координати).
## smooth — вага Ерміта замість лінійної: без зламу схилу на межі клітинки.
static func _bilinear_cells(grid: PackedByteArray, w: int, h: int, x: float, z: float, smooth: bool = false) -> float:
	var x0: int = floori(x)
	var z0: int = floori(z)
	var tx: float = x - x0
	var tz: float = z - z0
	if smooth:
		tx = tx * tx * (3.0 - 2.0 * tx)
		tz = tz * tz * (3.0 - 2.0 * tz)
	var ax: int = clampi(x0, 0, w - 1)
	var bx: int = clampi(x0 + 1, 0, w - 1)
	var az: int = clampi(z0, 0, h - 1)
	var bz: int = clampi(z0 + 1, 0, h - 1)
	return lerpf(lerpf(grid[az * w + ax], grid[az * w + bx], tx), lerpf(grid[bz * w + ax], grid[bz * w + bx], tx), tz)


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


## Гаусове розмиття (sigma по X і по Z у відліках), що наближене трьома прохідами рухомого
## середнього: вартість не залежить від sigma. Крайові відліки продовжуються.
func _blur(src: PackedFloat32Array, sigma_x: float, sigma_z: float, w: int = cols, h: int = rows) -> PackedFloat32Array:
	var a: PackedFloat32Array = src.duplicate()
	var b := PackedFloat32Array()
	b.resize(w * h)
	var rx: int = _box_radius(sigma_x)
	var rz: int = _box_radius(sigma_z)
	for _pass in 3:
		_box_pass(a, b, w, 1, h, w, rx)
		_box_pass(b, a, h, w, w, 1, rz)
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
