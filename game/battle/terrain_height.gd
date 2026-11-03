class_name TerrainHeight
extends RefCounted
## Косметичний рельєф: єдина карта висот, з якої беруть
## висоту ЗЕМЛЯ (вершинний шейдер), ВОДА, юніти, контури, кільця, міст, камера й пікінг.
## Це лише вигляд: жодне правило, видимість, дальність чи вартість руху її не читає,
## і в core/ її нема.
##
## Масштаб: клітинка = 8 м = 1.0 світу, тож 1 м = M = 0.125.
## Карта береться раз за карту з виду клітинок + шуму із seed (ім'я карти) і лежить у
## полі відліків, `samples` на клітинку; ці ж відліки — вершини меша землі й текстура RGBH.
## У світі з кільцем поле зведене до поверхні меша (GroundLod.surface), тож CPU і GPU бачать
## одну поверхню, а нормаль і затінення схилу беруться з гладкого поля (`gradient_image`).

const M: float = 0.125
## Відліків на клітинку за замовчуванням; для великих карт без кільця bake() зменшує, щоб рівномірний
## меш землі лишився в бюджеті трикутників (§8). Меш світу з кільцем густоту береже за рельєфом (GroundLod).
const SAMPLES_PER_TILE: int = 7
const MAX_GROUND_TRIS: int = 58000
## Вода на 1.25 м нижче верху берега (1.0-1.5 м): берег стоїть над водою ≥ 3 м схилу.
const WATER_LEVEL: float = -1.25 * M
## Висота настилу над верхом берега: щоб міст не зливався з дорогою.
const DECK_LIFT: float = 0.01
## Насип в'їзду на міст: від краю клітинки мосту на SEAT_REACH углиб ґрунт лежить на
## deck_y + SEAT_TOP — на 1.6 см ВИЩЕ покриття настилу (воно на 6.4 см над deck_y): кінець настилу
## захований під дорогою, і видно лише лінію, де ґрунт сходить під настил, а не торець плити. Далі
## до SEAT_END ґрунт сходить до берега всередині тіла опори (build_bridges.py, SEAT_END), щоб схил
## не вилазив перед її стіною. У клітинці мосту насип рівний до SEAT_HALF від осі й сходить до SEAT_SIDE
## (один відлік меша, межа клітинки) під стіною опори, що йде до SEAT_SIDE: укіс за її краєм лишив би
## сухий виступ у руслі.
const SEAT_TOP: float = 0.010
const SEAT_REACH: float = 0.15
const SEAT_END: float = 0.28
const SEAT_HALF: float = 0.36
const SEAT_SIDE: float = 0.49

## Рельєф рівнини: дрібний ±0.35 м (плями 5-20 м) і широкий до ±1.7 м (хвиля 3.7-5.5 клітинки).
const _MICRO_AMP: float = 0.35 * M
const _BROAD_AMP: float = 1.7 * M
## Поле майже рівне: хвиля рівнини на клітинках FIELD — ця частка (лука ≤ ~0.2 м у клітинці,
## рілля вдвічі рівніша). Дорога й майданчик будівлі — теж рівна земля. Хвиля повертається за
## `_FLAT_RAMP` клітинок уже в сусідніх клітинках (у лісі — лише до `_FLAT_FOREST`, на пагорбі й
## болоті — повна), тож клітинка поля рівна до самого краю, а обриву на межі нема.
const _FLAT_MEADOW: float = 0.12
const _FLAT_PLOUGHED: float = 0.06
## Ліс — нерівний, але без горбів: повна хвиля під кронами без дерев поруч (край лісу, прогалина)
## читалась темною плямою схилу від сонця серед рівного поля.
const _FLAT_FOREST: float = 0.35
const _FLAT_RAMP: float = 1.5
const _HILL_MIN: float = 3.5 * M
const _HILL_VAR: float = 2.0 * M
## Частка висоти пагорба, яку гарантовано тримає центр кожної клітинки HILL, хоч куди
## зсунувся обрис. У світі з кільцем на клітинці біля краю дошки — ця частка, помножена на
## улоговину краю (`_edge_hill_dip`): 0.259 на крайній клітинці, 0.067 на кутовій.
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
## Крок грубого поля річки (у відліках); далі білінійно.
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
## Смуга за краєм дошки (клітинок), де вісь річки дошки переходить у вісь світу з кільцем.
const _COURSE_BLEND: float = 1.5
## Смуга вздовж краю дошки (клітинки по обидва боки), де хвиля рельєфу рівнини згасає до 0, і
## спад за нею: рівнина під червоною лінією лежить рівно на y = 0, тож кожна сторона лінії —
## пряма в 3D і на екрані, а контур зони на крайній клітинці лежить на тій самій висоті. Пагорби
## мають власну улоговину (`_EDGE_HILL_IN`, `_EDGE_HILL_OUT`), русло лишається як є.
const _EDGE_FLAT: float = 0.35
const _EDGE_FLAT_RAMP: float = 0.6
## Улоговина пагорба на краю дошки (клітинки): спад усередині дошки й назовні. Вузька улоговина
## читається темною канавою вздовж лінії межі, тож спад широкий і пологий.
const _EDGE_HILL_IN: float = 1.5
const _EDGE_HILL_OUT: float = 2.5
## Розмиття берега біля краю дошки й у кільці (σ, клітинки) і розмах ширини русла кільця.
const _RING_ROUND: float = 1.4
const _RING_WIDTH_VAR: float = 0.3
## Радіус замикання води кільця (клітинки): западини суші в березі, вужчі за нього, стають дугами.
const _RING_CLOSE: float = 0.8
## Ширина гладкого мінімуму, яким об'єднано поля осей дошки й світу (клітинки).
const _COURSE_ROUND: float = 0.4
## Майданчик будівлі: запас довкола сліду (клітинки, 1 м, але не менше кроку відліків — інакше
## білінійна висота на краю сліду брала б відлік поза майданчиком) і спад до рельєфу довкола.
const _PAD_MARGIN: float = 0.125
const _PAD_BLEND: float = 0.5
const _PAD_BLEND_MAX: float = 1.5
## Ширина спаду на одиницю глибини зрізу: найкрутіше місце smoothstep — 1.5 · глибина / ширина,
## тож 3.2 дає ≤ ~25°.
const _PAD_SLOPE: float = 3.2
## Темна волога смуга біля підніжжя зрізу: ширина (клітинки) і найбільша поправка кривизни.
const _PAD_FOOT_WIDTH: float = 0.5
const _PAD_FOOT: float = 0.6

## Поточна карта висот бою. Одна на процес: BoardView ставить її в build() і знімає, виходячи
## зі сцени; без неї (тести, меню) все лежить на y = 0.
static var active: TerrainHeight = null
## Лише для перевірки вигляду (скріншоти «з хвилями / без»): множник широкої хвилі рівнини.
static var undulation_scale: float = 1.0
## Лише для перевірки (тест «насип не виходить за стіну опори»): false — без насипів біля мостів.
static var embank: bool = true

var margin: int = 0
var board_width: int = 0
var board_height: int = 0
var samples: int = SAMPLES_PER_TILE
## Відліків по осях: (розмір + 2 * відступ) * samples + 1.
var cols: int = 0
var rows: int = 0
var _h: PackedFloat32Array = PackedFloat32Array()
## Рельєф у повній деталізації: з нього кривизна й похил для шейдера. У світі з кільцем `_h` — поверхня
## меша землі (GroundLod.surface), що вкладається в густину його вершин, а `_hd` зберігає
## гладке поле, з якого меш знято, тож нормаль і затінення схилу не стають гранями меша.
var _hd: PackedFloat32Array = PackedFloat32Array()
var _hd_base: PackedFloat32Array = PackedFloat32Array()
## Густота меша землі після зведення поля (GroundLod): клітинка -> квадів на бік.
var _quads: Dictionary = {}
var _water: PackedFloat32Array = PackedFloat32Array()
var _curv: PackedFloat32Array = PackedFloat32Array()
## Вага насипу біля мостів у кожному відліку (0 — насипу нема): на ній гаситься запечена опуклість.
var _embank_w: PackedFloat32Array = PackedFloat32Array()
## Гладка вісь річки, з якої взято відстань до урізу; null — води нема.
var course: RiverCourse = null
## Переправи (RiverCourse.build): клітинки, центр, вісь, довжина й ширина настилу.
var _groups: Array[Dictionary] = []
## Переправи дошки: лише вони рівняють русло й гасять нерівність берега біля себе. Міст кільця
## настилу не має, і пряма вода під ним читалась би каналом.
var _course_groups: Array[Dictionary] = []
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
var _gradient_texture: ImageTexture = null
## Висоти без майданчиків будівель: PropLayer ставить майданчики заново щоразу, як будує пропси.
var _h_base: PackedFloat32Array = PackedFloat32Array()
## Сліди будівель (координати дошки) і висота кожного майданчика.
var _pads: Array[Rect2] = []
var _pad_levels: PackedFloat32Array = PackedFloat32Array()
## Майданчики додано, а рельєф ще не перераховано: перерахунок — при першому читанні висоти, тож
## будівлі, поставлені поспіль, коштують один перерахунок, а не по одному на кожну.
var _pads_dirty: bool = false
## Ширина спаду кожного майданчика (клітинки).
var _pad_blend: PackedFloat32Array = PackedFloat32Array()
## Майданчики, з якими востаннє рахувалися кривизна й текстура.
var _finished_pads: Array[Rect2] = []
## Скільки разів майданчики перезалили текстуру висот (перевірка в тестах).
var texture_updates: int = 0
## Лічильник змін поля відліків після майданчиків: меш землі (GroundLod) перебудовується, коли він інший.
var revision: int = 0


## seed — з імені карти (BoardView.relief_seed); та сама карта дає той самий рельєф.
## surface — MapData.surface (тут з підтипів береться лише тип дороги для її ширини);
## порожній — усі 0.
## ring > 0: board — уже світ (дошка разом із кільцем, Surroundings.world_board), на ring клітинок
## ширший з кожного боку. Запікається в координатах світу, потім зсувається на ring, тож at(),
## deck_y(), bridge_groups() і image() далі говорять координатами дошки. course і roads лишаються
## в координатах світу: їх читають лише растри, а ті й так покривають увесь світ.
## cache — узяти поле з диска (BuildCache) і зберегти туди.
static func bake(board: Board, p_margin: int, seed_value: int, surface: PackedByteArray = PackedByteArray(), ring: int = 0, cache: bool = false) -> TerrainHeight:
	var cache_key: String = ""
	if cache:
		cache_key = _cache_key(board, p_margin, seed_value, surface, ring)
		var cached: Variant = BuildCache.fetch("height", cache_key)
		if cached is Dictionary:
			return _from_cache(cached, seed_value)
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
		t._conform(ring)
	if cache:
		BuildCache.store("height", cache_key, t._to_cache())
	return t


## Скрипти, чий код і константи визначають поле висот: правка будь-якого міняє ключ кешу.
const CACHE_SCRIPTS: PackedStringArray = [
	"res://game/battle/terrain_height.gd", "res://game/battle/river_course.gd", "res://game/battle/road_course.gd",
	"res://game/battle/surroundings.gd", "res://game/battle/ground_lod.gd", "res://core/terrain.gd", "res://core/map_data.gd", "res://core/board.gd"]


static func _cache_key(board: Board, p_margin: int, seed_value: int, surface: PackedByteArray, ring: int) -> String:
	return BuildCache.key([board.width, board.height, board.tiles, p_margin, seed_value, surface, ring, undulation_scale], CACHE_SCRIPTS)


func _to_cache() -> Dictionary:
	var state: Dictionary = BuildCache.dump_vars(self, ["course", "roads"])
	if course != null:
		state["#course"] = BuildCache.dump_vars(course)
	if roads != null:
		var images: Array = []
		for img in roads.rasterise():
			images.append(BuildCache.pack_image(img))
		state["#roads"] = [BuildCache.dump_vars(roads, ["_images"]), images]
	return state


static func _from_cache(state: Dictionary, seed_value: int) -> TerrainHeight:
	var t := TerrainHeight.new()
	var vars: Dictionary = state.duplicate()
	var course_state: Variant = vars.get("#course")
	vars.erase("#course")
	var road_state: Variant = vars.get("#roads")
	vars.erase("#roads")
	BuildCache.load_vars(t, vars)
	if course_state != null:
		var rv := RiverCourse.new()
		BuildCache.load_vars(rv, course_state)
		rv.make_warps(seed_value)
		t.course = rv
	if road_state != null:
		var rc := RoadCourse.new()
		BuildCache.load_vars(rc, road_state[0])
		var images: Array[Image] = []
		for a: Array in road_state[1]:
			images.append(BuildCache.unpack_image(a))
		rc._images = images
		t.roads = rc
	return t


## Зводить поле висот до поверхні меша землі: висота, на якій стоять юніти й пропси, вода й камера, —
## та сама, що малює меш (GroundLod), а не гладке поле, з якого меш знято. Береговим клітинкам
## допуск вужчий (GroundLod.TOL_BANK): ними йде уріз води.
func _conform(ring: int) -> void:
	var size := Vector2i(board_width, board_height)
	var fine: Dictionary = bank_cells()
	_quads = Surroundings.cell_quads(size, ring, samples, fine, GroundLod.levels(self, size, ring, fine))
	_h = GroundLod.surface(_h, cols, samples, margin, size, ring, _quads)
	_h_base = _h.duplicate()
	_bounds()


## Квадів на бік кожної клітинки меша землі, на яких поле зведено до поверхні (порожньо без кільця).
func mesh_quads() -> Dictionary:
	return _quads


## Клітинки (координати дошки), де майданчики змінили поле порівняно зі зведеним до меша: лише там
## меш мусить густішати; решта вже лежить на ньому.
func pad_cells() -> Dictionary:
	if _pads_dirty:
		_apply_pads()
	var out: Dictionary = {}
	for k in _h.size():
		if _h[k] != _h_base[k]:
			var i: int = k % cols
			var j: int = k / cols
			for cx: int in [i / samples, (i - 1) / samples] if i % samples == 0 else [i / samples]:
				for cz: int in [j / samples, (j - 1) / samples] if j % samples == 0 else [j / samples]:
					out[Vector2i(cx - margin, cz - margin)] = true
	return out


func _bounds() -> void:
	_min = INF
	_max = -INF
	for v in _h:
		_min = minf(_min, v)
		_max = maxf(_max, v)


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
	if _pads_dirty:
		_apply_pads()
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


## Клітинки (координати дошки) з водою чи схилом берега хоча б в одному відліку, разом із
## відліками на межі клітинки: там меш кільця мусить мати густоту дошки
## (`Surroundings.ground_mesh`).
func bank_cells() -> Dictionary:
	var out: Dictionary = {}
	for k in _water.size():
		if _water[k] <= 0.0:
			continue
		var i: int = k % cols
		var j: int = k / cols
		for cx: int in [i / samples, (i - 1) / samples]:
			for cz: int in [j / samples, (j - 1) / samples]:
				out[Vector2i(cx - margin, cz - margin)] = true
	return out


## Поле висот (масив відліків, не копія): його читає GroundLod, щоб обрати густоту меша.
func heights() -> PackedFloat32Array:
	if _pads_dirty:
		_apply_pads()
	return _h


## Одиничний нормаль поверхні (скінченні різниці на кроці одного відліку).
func normal_at(x: float, z: float) -> Vector3:
	var e: float = 1.0 / float(samples)
	return Vector3(at(x - e, z) - at(x + e, z), 2.0 * e, at(x, z - e) - at(x, z + e)).normalized()


## RGBA16F-текстура для шейдерів: R — висота, G — 1 під водою й спад до 0 на верху берега
## (маска берега), B — кривизна -1..1 (запечене затінення, §8), A — 0.5 + 0.5 * bend (коса < 0.5 < підмитий берег).
## Піксель (i, j) — у світі (-0.5 - відступ + i / samples, ... j / samples).
func image() -> Image:
	# Через сирі байти RGBAF і перетворення рушієм: `set_pixel` на кожен відлік світу з кільцем —
	# сотні мс.
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


## Похил для шейдера землі: RG16F, R = (h(x - e) - h(x + e)) / 2e по X, G — те саме по Z, e — один
## відлік (за краєм карти — крайовий). Піксель (i, j) — той самий відлік, що в image().
func gradient_image() -> Image:
	if _pads_dirty:
		_apply_pads()
	var px := PackedFloat32Array()
	px.resize(cols * rows * 2)
	var k2: float = float(samples) * 0.5
	for j in rows:
		for i in cols:
			var k: int = j * cols + i
			px[k * 2] = (_hd[j * cols + maxi(i - 1, 0)] - _hd[j * cols + mini(i + 1, cols - 1)]) * k2
			px[k * 2 + 1] = (_hd[maxi(j - 1, 0) * cols + i] - _hd[mini(j + 1, rows - 1) * cols + i]) * k2
	var img := Image.create_from_data(cols, rows, false, Image.FORMAT_RGF, px.to_byte_array())
	img.convert(Image.FORMAT_RGH)
	return img


## gradient_image() як текстура, одна на карту, як texture().
func gradient_texture() -> ImageTexture:
	if _gradient_texture == null:
		_gradient_texture = ImageTexture.create_from_image(gradient_image())
	return _gradient_texture


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
		for g in _groups:
			var inside := true
			for c: Vector2i in g["cells"]:
				inside = inside and c.x >= _shift and c.y >= _shift \
						and c.x < bw - _shift and c.y < bh - _shift
			if inside:
				_course_groups.append(g)
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
	# (hgrid, без зсуву, _HILL_KEEP); у світі з кільцем центр крайньої клітинки — ця частка,
	# помножена на улоговину краю (`_edge_hill_dip`, 0.259 за клітинку від краю).
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
	# Клітинки за 3 від пагорба: зсув (≤ 1.55) і білінійна опора (1) далі не сягають, тож решта
	# відліків — точно 0 без шуму. У світі з кільцем це більшість відліків.
	var near_hill: PackedByteArray = _dilate(hgrid, bw, bh, 3) if has_hill else PackedByteArray()
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
				if has_hill and near_hill[clampi(roundi(z), 0, bh - 1) * bw + clampi(roundi(x), 0, bw - 1)] == 1:
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
	var flat: PackedFloat32Array = _flatness(board, surface, fs)

	var n1 := _nz(seed_value, 0.27)
	var n2 := _nz(seed_value + 101, 0.65)
	var n3 := _nz(seed_value + 202, 0.08)
	var nb1 := _nz(seed_value + 606, 0.18)
	var nb2 := _nz(seed_value + 616, 0.27)
	var n_s3 := _nz(seed_value + 767, 2.2)
	var n_s1 := _nz(seed_value + 747, 0.4)
	var n_s2 := _nz(seed_value + 757, 0.9)
	var n_crest := _nz(seed_value + 808, 0.5)
	var n_knob := _nz(seed_value + 818, 0.7)

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
		course = RiverCourse.build(_wgrid, bw, bh, margin + 3, _course_groups, seed_value, _shift)
		var fld: Array[PackedFloat32Array] = course.field(cols, rows, s, margin, _RIVER_STEP)
		if _shift > 0:
			_keep_board_course(fld, seed_value)
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
		if _shift > 0:
			_round_ring_shores(dc, cw, ch, cstep, seed_value)
		# RiverCourse.upsample розгорнуто: розміри грубої сітки й виклик функції на кожен відлік — марні.
		var ucw: int = (cols - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
		var uch: int = (rows - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
		for k in dg.size():
			var fx: float = float(k % cols) / float(_RIVER_STEP)
			var fz: float = float(k / cols) / float(_RIVER_STEP)
			var ux: int = mini(int(fx), ucw - 2)
			var uz: int = mini(int(fz), uch - 2)
			var tx: float = fx - ux
			var tz: float = fz - uz
			dg[k] = lerpf(lerpf(dc[uz * ucw + ux], dc[uz * ucw + ux + 1], tx), lerpf(dc[(uz + 1) * ucw + ux], dc[(uz + 1) * ucw + ux + 1], tx), tz)
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
					if not _course_groups.is_empty():
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
			var damp: float = near_water * flat[k]
			# Відстань Чебишова від краю дошки зі знаком (< 0 усередині); без кільця не потрібна.
			var edge: float = 0.0
			if _shift > 0:
				var ex: float = absf(x - (bw - 1) * 0.5) - (bw - 2 * _shift) * 0.5
				var ez: float = absf(z - (bh - 1) * 0.5) - (bh - 2 * _shift) * 0.5
				edge = maxf(ex, ez)
				damp *= smoothstep(_EDGE_FLAT, _EDGE_FLAT + _EDGE_FLAT_RAMP, absf(edge))
			if has_road:
				var rd: float = road_d[clampi(int((z + 0.5 + margin) * RoadCourse.PX), 0, road_d.size() / road_rw - 1) * road_rw + clampi(int((x + 0.5 + margin) * RoadCourse.PX), 0, road_rw - 1)]
				# Рівно під намальованою дорогою й 0.5 м за її краєм (поле відстані RoadCourse),
				# далі спад за 1.5 м.
				damp *= 1.0 - _ROAD_DAMP * (1.0 - smoothstep(0.5, 2.0, rd))
			if has_pad:
				damp *= 1.0 - smoothstep(0.0, 0.4, pad_m[k])
			var rise := 0.0
			if has_hill and (hill_a[k] > 0.0 or hill_b[k] > 0.0 or near_hill[clampi(roundi(z), 0, bh - 1) * bw + clampi(roundi(x), 0, bw - 1)] == 1):
				var hill_h: float = _HILL_MIN + _HILL_VAR * (0.5 + 0.5 * n3.get_noise_2d(x, z))
				rise = hill_h * (0.7 * smoothstep(0.0, 0.55, hill_a[k]) + 0.3 * smoothstep(0.0, 0.7, hill_b[k]))
				rise *= 1.0 + 0.12 * n_crest.get_noise_2d(x, z)
				# Опора центру клітинки — горбок у кожній клітинці пагорба; рівні й однакові вони
				# стояли рядом, як лоток для яєць. Тож висота опори гуляє +0..40 % (шум ~1.4 клітинки,
				# не менше _HILL_KEEP), а стик з обрисом — гладкий максимум, без перегину між горбками.
				var keep: float = _HILL_KEEP * hill_h * (1.0 + 0.4 * (0.5 + 0.5 * n_knob.get_noise_2d(x, z))) \
						* _bilinear_cells(hgrid, bw, bh, x, z, true)
				var shaped: float = rise * _bilinear_cells(agrid, bw, bh, x, z, true)
				# Ширина згладжування росте з висотою: де обидва майже 0 (поле біля пагорба), гладкий
				# максимум інакше підняв би землю на чверть ширини.
				var kw: float = 0.8 * M * clampf(maxf(shaped, keep) / (2.0 * M), 0.0, 1.0)
				rise = maxf(shaped, keep) if kw < 1e-4 else -_smooth_min(-shaped, -keep, kw)
				# Підйом не затікає у воду (розмиття пагорба), а то центр клітинки води виходить на суходіл.
				if has_water:
					rise *= smoothstep(0.0, 1.4, d)
				# Пагорб, що перетинає край дошки, опускається до 0 рівно на краю улоговиною
				# (`_edge_hill_dip`): центр крайньої клітинки пагорба тримає 0.259 висоти, кутової —
				# 0.067. Лінія межі й контур зони на крайній клітинці лежать на y = 0.
				if _shift > 0:
					rise *= _edge_hill_dip(
							absf(x - (bw - 1) * 0.5) - (bw - 2 * _shift) * 0.5,
							absf(z - (bh - 1) * 0.5) - (bh - 2 * _shift) * 0.5)
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
	_bake_decks(board)
	_embank_bridges()
	_bake_curvature(_h)
	_h_base = _h.duplicate()
	_hd_base = _h.duplicate()
	_hd = _h.duplicate()


## Кривизна: висота мінус її розмиття на ~1.2 клітинки, у масштабі 1.5 м.
func _bake_curvature(src: PackedFloat32Array) -> void:
	var fs: float = float(samples)
	var soft: PackedFloat32Array = _blur(src, 1.2 * fs, 1.2 * fs)
	_curv.resize(cols * rows)
	for k in src.size():
		_curv[k] = clampf((src[k] - soft[k]) / _CURV_RANGE, -1.0, 1.0)
	# Насип — гребінь над руслом, і запечена опуклість світлила його плямою, світлішою за дорогу на
	# березі й за настил: на насипі лишається лише западина.
	for k in _embank_w.size():
		if _embank_w[k] > 0.0:
			_curv[k] = lerpf(_curv[k], minf(_curv[k], 0.0), _embank_w[k])


## Знімає всі майданчики будівель: рельєф — як щойно запечений.
func clear_pads() -> void:
	_h = _h_base.duplicate()
	_hd = _hd_base.duplicate()
	_pads.clear()
	_pad_levels.clear()
	_pads_dirty = false


## Додає слід будівлі (rect — координати дошки, XZ) і повертає номер майданчика; висоту підошви
## дає pad_level(), бо вона може змінитися з наступними майданчиками.
## Ґрунт під слідом із запасом рівняється до однієї висоти, а за запасом за `_PAD_BLEND` клітинки
## повертається до рельєфу. Висота — середня під слідом, тож на схилі майданчик урізається вгору й
## насипається вниз. Майданчики, чиї ядра (слід із запасом) стикаються, — одна тераса з однією
## висотою (середня під усіма їхніми слідами): інакше будівля впритул до двох інших стояла б на
## сходинці. Мокрі відліки (нижче рівня води) не змінюються: уріз лишається, де був.
func add_pad(rect: Rect2) -> int:
	_pads.append(rect)
	_pads_dirty = true
	return _pads.size() - 1


func pad_level(id: int) -> float:
	if _pads_dirty:
		_apply_pads()
	return _pad_levels[id]


func _apply_pads() -> void:
	_pads_dirty = false
	var fs: float = float(samples)
	var grow: float = maxf(_PAD_MARGIN, 1.0 / fs + 0.01)
	var n: int = _pads.size()
	# Тераси: зв'язні групи ядер, що перетинаються.
	var group := PackedInt32Array()
	group.resize(n)
	for a in n:
		group[a] = a
	for a in n:
		for b in range(a + 1, n):
			if _pads[a].grow(grow).intersects(_pads[b].grow(grow)):
				var ga: int = group[a]
				var gb: int = group[b]
				for c in n:
					if group[c] == gb:
						group[c] = ga
	var sums: Dictionary = {}
	for a in n:
		var r: Rect2 = _pads[a]
		var acc: Vector2 = sums.get(group[a], Vector2.ZERO)
		for j in range(_sample_lo(r.position.y, fs, rows), _sample_hi(r.end.y, fs, rows) + 1):
			for i in range(_sample_lo(r.position.x, fs, cols), _sample_hi(r.end.x, fs, cols) + 1):
				if r.has_point(Vector2(-0.5 - margin + i / fs, -0.5 - margin + j / fs)):
					acc += Vector2(_h_base[j * cols + i], 1.0)
		sums[group[a]] = acc
	_pad_levels.resize(n)
	_pad_blend.resize(n)
	for a in n:
		var acc: Vector2 = sums[group[a]]
		var c: Vector2 = _pads[a].get_center()
		_pad_levels[a] = maxf(acc.x / acc.y if acc.y > 0.0 else _h_base_at(c.x, c.y), WATER_LEVEL + 0.3 * M)
		# Спад тим ширший, чим глибше майданчик урізаний у схил: найкрутіше місце переходу ≤ ~25°.
		var dev := 0.0
		var r: Rect2 = _pads[a].grow(grow)
		for j in range(_sample_lo(r.position.y, fs, rows), _sample_hi(r.end.y, fs, rows) + 1):
			for i in range(_sample_lo(r.position.x, fs, cols), _sample_hi(r.end.x, fs, cols) + 1):
				if r.has_point(Vector2(-0.5 - margin + i / fs, -0.5 - margin + j / fs)) and _h_base[j * cols + i] >= WATER_LEVEL:
					dev = maxf(dev, absf(_h_base[j * cols + i] - _pad_levels[a]))
		_pad_blend[a] = clampf(_PAD_SLOPE * dev, _PAD_BLEND, _PAD_BLEND_MAX)
	_h = _h_base.duplicate()
	_hd = _hd_base.duplicate()
	# Ядра спершу: відлік ядра — точно висота тераси, і спад сусіднього майданчика його не зрушить.
	var core := PackedByteArray()
	core.resize(_h.size())
	for pass_core: bool in [true, false]:
		for a in n:
			var r: Rect2 = _pads[a].grow(grow)
			var outer: Rect2 = r.grow(_pad_blend[a])
			for j in range(_sample_lo(outer.position.y, fs, rows), _sample_hi(outer.end.y, fs, rows) + 1):
				for i in range(_sample_lo(outer.position.x, fs, cols), _sample_hi(outer.end.x, fs, cols) + 1):
					var k: int = j * cols + i
					if core[k] == 1 or _h_base[k] < WATER_LEVEL:
						continue
					var dist: float = _rect_dist(r, Vector2(-0.5 - margin + i / fs, -0.5 - margin + j / fs))
					if pass_core and dist == 0.0:
						_h[k] = _pad_levels[a]
						_hd[k] = _pad_levels[a]
						core[k] = 1
					elif not pass_core and dist < _pad_blend[a]:
						var w: float = 1.0 - smoothstep(0.0, _pad_blend[a], dist)
						_h[k] = lerpf(_h[k], _pad_levels[a], w)
						_hd[k] = lerpf(_hd[k], _pad_levels[a], w)


## Відстань від точки до прямокутника (0 усередині).
static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var q: Vector2 = (p - r.get_center()).abs() - r.size * 0.5
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


## Перший (lo) і останній (hi) відлік уздовж осі з n відліків, що покривають координату v.
func _sample_lo(v: float, fs: float, n: int) -> int:
	return clampi(floori((v + 0.5 + margin) * fs), 0, n - 1)


func _sample_hi(v: float, fs: float, n: int) -> int:
	return clampi(ceili((v + 0.5 + margin) * fs), 0, n - 1)


func _h_base_at(x: float, z: float) -> float:
	var keep: PackedFloat32Array = _h
	_h = _h_base
	var v: float = at(x, z)
	_h = keep
	return v


## Після майданчиків: кривизна, межі висот і текстура (та сама, що вже в шейдерах землі й води).
## Ті самі майданчики, що й минулого разу (перебудова клітинок посеред партії), — рельєф той самий,
## і кривизна з текстурою не перераховуються.
func finish_pads() -> void:
	if _pads_dirty:
		_apply_pads()
	if _pads == _finished_pads:
		return
	_finished_pads = _pads.duplicate()
	_bake_curvature(_hd)
	_mark_cut_feet()
	_bounds()
	if _texture != null:
		_texture.update(image())
		texture_updates += 1
	if _gradient_texture != null:
		_gradient_texture.update(gradient_image())
	revision += 1


## Підніжжя зрізу з горішнього боку майданчика — смуга ~0.5 клітинки вологого темнішого ґрунту
## (кривизна < 0 — запечене затінення западини в шейдері землі): інакше вирівняний майданчик на
## схилі не читається зовсім. Сила росте з глибиною зрізу до 1 м.
func _mark_cut_feet() -> void:
	var fs: float = float(samples)
	var grow: float = maxf(_PAD_MARGIN, 1.0 / fs + 0.01)
	for a in _pads.size():
		var r: Rect2 = _pads[a].grow(grow)
		var outer: Rect2 = r.grow(_PAD_FOOT_WIDTH)
		for j in range(_sample_lo(outer.position.y, fs, rows), _sample_hi(outer.end.y, fs, rows) + 1):
			for i in range(_sample_lo(outer.position.x, fs, cols), _sample_hi(outer.end.x, fs, cols) + 1):
				var k: int = j * cols + i
				var cut: float = _h_base[k] - _h[k]
				var dist: float = _rect_dist(r, Vector2(-0.5 - margin + i / fs, -0.5 - margin + j / fs))
				if cut <= 0.0 or dist == 0.0 or dist >= _PAD_FOOT_WIDTH:
					continue
				var w: float = (1.0 - smoothstep(0.0, _PAD_FOOT_WIDTH, dist)) * clampf(cut / M, 0.0, 1.0)
				_curv[k] = maxf(_curv[k] - _PAD_FOOT * w, -1.0)


## Річка на дошці — та сама, що й без кільця: вісь світу інша (скелет довшої маски, медіана
## ширини по всій довжині, інший крок перевибірки), і без цього вода дошки звужувалась би в
## клітинках, які правила вважають водою. Поле — об'єднання (мінімум) двох: поле осі дошки
## згасає за `_COURSE_BLEND` клітинок поза дошкою, поле осі світу з'являється за стільки ж
## усередині й на самому краю діє повністю. Не змішування: ставок, що його вісь дошки закриває
## на краю, а вода кільця продовжує, у змішуванні розпався б на два. Гладкий мінімум зсуває
## уріз щонайбільше на `_COURSE_ROUND` / 4 клітинки; що центри клітинок суші лишаються сухими в
## радіусі 0.3, перевіряє test_surroundings.gd (`test_world_bake_keeps_water_and_land_invariants`).
func _keep_board_course(fld: Array[PackedFloat32Array], seed_value: int) -> void:
	var sw: int = board_width - 2 * _shift
	var sh: int = board_height - 2 * _shift
	var sub := PackedByteArray()
	sub.resize(sw * sh)
	for cy in sh:
		for cx in sw:
			sub[cy * sw + cx] = _wgrid[(cy + _shift) * board_width + cx + _shift]
	var off := Vector2i(_shift, _shift)
	var groups: Array[Dictionary] = []
	for g in _groups:
		var cells: Array[Vector2i] = []
		var inside := true
		for c: Vector2i in g["cells"]:
			inside = inside and c.x >= _shift and c.y >= _shift and c.x < _shift + sw and c.y < _shift + sh
			cells.append(c - off)
		if inside:
			var bg: Dictionary = g.duplicate()
			bg["cells"] = cells
			bg["centre"] = (g["centre"] as Vector2) - Vector2(off)
			groups.append(bg)
	var own: RiverCourse = RiverCourse.build(sub, sw, sh, 3, groups, seed_value)
	var ofld: Array[PackedFloat32Array] = own.field(cols, rows, samples, margin + _shift, _RIVER_STEP)
	var cw: int = (cols - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
	var cstep: float = float(_RIVER_STEP) / float(samples)
	var size := Vector2i(sw, sh)
	var half := Vector2(size) * 0.5
	for k in fld[0].size():
		var p := Vector2(-0.5 - margin - _shift + (k % cw) * cstep, -0.5 - margin - _shift + (k / cw) * cstep)
		var q: Vector2 = (p - (half - Vector2(0.5, 0.5))).abs() - half
		var out: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
		var fade_board: float = RiverCourse.FAR * smoothstep(0.0, _COURSE_BLEND, out)
		var fade_world: float = RiverCourse.FAR * (1.0 - smoothstep(-_COURSE_BLEND, 0.0, out))
		var db: float = ofld[0][k] + fade_board
		var dw: float = fld[0][k] + fade_world
		fld[1][k] = lerpf(ofld[1][k], fld[1][k], smoothstep(-_COURSE_BLEND, _COURSE_BLEND, out))
		fld[0][k] = _smooth_min(db, dw, _COURSE_ROUND)
		fld[2][k] = _smooth_min(ofld[2][k] + fade_board, fld[2][k] + fade_world, _COURSE_ROUND)


## Берег біля краю дошки й у кільці: поле розмите ще раз (σ `_RING_ROUND` клітинки), тож кути, де
## стикуються осі, виступи берега й ставки, стають дугами, а не багатокутником; з клітинки за краєм
## ширина русла кільця ще й гуляє на ±`_RING_WIDTH_VAR` за шумом (хвиля ~3 клітинки), щоб автором
## намальована смуга води не читалась рівним каналом. Над руслом завширшки в клітинку розмите поле
## вище за саме поле, і ні розмиття, ні шум на ньому води не додають; тому шум лягає на менше з
## розмитого й замкнутого поля (`_closing`, радіус `_RING_CLOSE`): замкнуте заповнює западини суші,
## а біля прямого берега дорівнює відстані до урізу, тож шум розширює й вузьке русло. Вода лише
## додається, ніколи не відступає: розмиття й шум формують берег, але не звужують і не перерізають
## русло завширшки в клітинку (навіть відступ на 0.15 клітинки там, де вода широка, рве русло кільця
## River). Смуга сягає клітинки всередину дошки, глибше поле не змінюється; що кожна клітинка води
## правил лишається мокрою щонайменше на чверть, перевіряє test_surroundings.gd
## (`test_world_bake_keeps_water_and_land_invariants_on_the_board`).
func _round_ring_shores(dc: PackedFloat32Array, cw: int, ch: int, cstep: float, seed_value: int) -> void:
	var sig: float = _RING_ROUND / cstep
	var soft: PackedFloat32Array = _blur(dc, sig, sig, cw, ch)
	var closed: PackedFloat32Array = _closing(dc, cw, ch, cstep, _RING_CLOSE)
	var n := _nz(seed_value + 1717, 0.33)
	var cx: float = (board_width - 1) * 0.5
	var cz: float = (board_height - 1) * 0.5
	var hx: float = (board_width - 2 * _shift) * 0.5
	var hz: float = (board_height - 2 * _shift) * 0.5
	for k in dc.size():
		var x: float = -0.5 - margin + float(k % cw) * cstep
		var z: float = -0.5 - margin + float(k / cw) * cstep
		var out: float = maxf(absf(x - cx) - hx, absf(z - cz) - hz)
		var v: float = lerpf(dc[k], soft[k], smoothstep(-1.0, 0.5, out))
		v = minf(v, lerpf(dc[k], closed[k], smoothstep(0.5, 1.5, out)))
		v += _RING_WIDTH_VAR * n.get_noise_2d(x, z) * smoothstep(1.0, 2.5, out)
		dc[k] = minf(v, dc[k])


## Поле замкнутої води на грубому полі з кроком step: вода, розширена на r і звужена назад на r
## (наближені відстані, `chamfer`). Над руслом завширшки в клітинку розмите поле лишається більшим
## за нуль по всій ширині русла й води не додає, тож западину суші між колінами такого русла
## заповнює лише замикання. Вузли води лишаються своїми: глибина русла не змінюється. На суші —
## відстань до замкнутої води з одиничним нахилом: уздовж прямого берега це звичайна відстань до
## урізу, тож поле суші неперервне.
func _closing(dc: PackedFloat32Array, w: int, h: int, step: float, r: float) -> PackedFloat32Array:
	var land := PackedFloat32Array()
	land.resize(dc.size())
	for k in dc.size():
		land[k] = -dc[k]
	var d_out: PackedFloat32Array = _inner_distance(land, w, h, step)
	var grown := PackedFloat32Array()
	grown.resize(dc.size())
	for k in dc.size():
		grown[k] = -1.0 if dc[k] <= 0.0 else d_out[k] - r
	var d_in: PackedFloat32Array = _inner_distance(grown, w, h, step)
	# За краєм поля — суша: інакше розширена вода біля краю світу ніде не звужувалась би назад, і
	# берег між водою й краєм заливало б аж до краю.
	for k in dc.size():
		var i: int = k % w
		var j: int = k / w
		d_in[k] = minf(d_in[k], float(mini(mini(i, j), mini(w - 1 - i, h - 1 - j)) + 1) * step)
	var out := PackedFloat32Array()
	out.resize(dc.size())
	for k in dc.size():
		if dc[k] < 0.0:
			out[k] = dc[k]
		else:
			out[k] = r - d_in[k] if grown[k] < 0.0 else d_out[k]
	return out


## Множник висоти пагорба біля краю дошки; ex, ez — відстані від сторін дошки (клітинки, < 0
## усередині). На самому краю 0 з нульовим нахилом по обидва боки: дно улоговини пологе, без
## зламу під лінією. Усередині — добуток спадів від двох сторін, назовні — спад за евклідовою
## відстанню: у куті лінії рівні рельєфу закруглені, і з кута не тягнеться діагональна виїмка.
static func _edge_hill_dip(ex: float, ez: float) -> float:
	if ex < 0.0 and ez < 0.0:
		return smoothstep(0.0, _EDGE_HILL_IN, -ex) * smoothstep(0.0, _EDGE_HILL_IN, -ez)
	return smoothstep(0.0, _EDGE_HILL_OUT, Vector2(maxf(ex, 0.0), maxf(ez, 0.0)).length())


## Множник хвилі рівнини на кожному відліку: на полі `_FLAT_MEADOW` чи `_FLAT_PLOUGHED` (межа
## луки й ріллі розмита на 0.3 клітинки), на дорозі й майданчику — як на луці; поза ними росте за
## `_FLAT_RAMP` клітинок від найближчої такої клітинки — у лісі до `_FLAT_FOREST`, на пагорбі й
## болоті до 1. Кільце — так само: поле є полем і за краєм дошки.
func _flatness(board: Board, surface: PackedByteArray, fs: float) -> PackedFloat32Array:
	var bw: int = board_width
	var bh: int = board_height
	# Вид і множник — раз на клітинку, відлік лише бере їх за індексом своєї клітинки.
	var cell_k := PackedFloat32Array()
	var cell_level := PackedFloat32Array()
	var cell_far := PackedFloat32Array()
	cell_k.resize(bw * bh)
	cell_level.resize(bw * bh)
	cell_far.resize(bw * bh)
	for cz in bh:
		for cx in bw:
			var c: int = cz * bw + cx
			var kind: int = board.kind_at(Vector2i(cx, cz))
			var plough: bool = kind == Terrain.Kind.FIELD and surface.size() == bw * bh \
					and surface[c] == MapData.FieldSurface.PLOUGHED
			cell_k[c] = _FLAT_PLOUGHED if plough else _FLAT_MEADOW
			# Куди росте множник далеко від рівної землі: ліс — до `_FLAT_FOREST`, решта — до 1.
			cell_far[c] = _FLAT_FOREST if kind == Terrain.Kind.FOREST else 1.0
			var flat_kind: bool = kind == Terrain.Kind.FIELD or kind == Terrain.Kind.ROAD \
					or kind == Terrain.Kind.BUILDING or kind == Terrain.Kind.RUBBLE
			cell_level[c] = 0.0 if flat_kind else -1.0
	var col_cell := PackedInt32Array()
	col_cell.resize(cols)
	for i in cols:
		col_cell[i] = clampi(roundi(-0.5 - margin + float(i) / fs), 0, bw - 1)
	var level := PackedFloat32Array()
	var k_map := PackedFloat32Array()
	var far := PackedFloat32Array()
	level.resize(cols * rows)
	k_map.resize(cols * rows)
	far.resize(cols * rows)
	for j in rows:
		var row: int = clampi(roundi(-0.5 - margin + float(j) / fs), 0, bh - 1) * bw
		for i in cols:
			var c: int = row + col_cell[i]
			k_map[j * cols + i] = cell_k[c]
			level[j * cols + i] = cell_level[c]
			far[j * cols + i] = cell_far[c]
	var dist: PackedFloat32Array = _inner_distance(level)
	k_map = _blur(k_map, 0.3 * fs, 0.3 * fs)
	# Межа лісу й пагорба чи болота — без сходинки множника; на полі (dist = 0) far не діє.
	far = _blur(far, 0.3 * fs, 0.3 * fs)
	for k in k_map.size():
		k_map[k] = lerpf(k_map[k], far[k], smoothstep(0.0, _FLAT_RAMP, dist[k]))
	return k_map


## Гладкий мінімум (поліноміальний, ширина k): там, де дві водойми сходяться під кутом, берег
## огинає стик дугою, а не лишає вм'ятину.
static func _smooth_min(a: float, b: float, k: float) -> float:
	var h: float = maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


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


## Насип на кожному кінці переправи дошки: берег падає до води ще в клітинці дороги, і без насипу
## перед мостом була яма, а настил лежав на землі сходинкою. Ґрунт лише піднімається (max), тож
## уріз і вода під серединою мосту не змінюються. Смуга насипу — ширина переправи без 0.14 клітинки
## з кожного боку, далі укіс на 0.4 клітинки (3.2 м). Углиб берега насип за 0.8 клітинки сходить
## до рівня самого берега й за 1.3 зникає.
func _embank_bridges() -> void:
	if not embank:
		return
	_embank_w.resize(cols * rows)
	var fs: float = float(samples)
	for g in _course_groups:
		var axis: Vector2 = g["axis"]
		var side := Vector2(-axis.y, axis.x)
		var centre: Vector2 = g["centre"]
		var flat: float = 0.5 * float(g["across"]) - 0.14
		var wide: float = flat + 0.4
		var deck: float = _deck[(g["cells"] as Array)[0]]
		for s: float in [-1.0, 1.0]:
			var out: Vector2 = axis * s
			var edge: Vector2 = centre + out * (0.5 * float(g["length"]))
			var box := Rect2(edge, Vector2.ZERO).expand(edge + out * 1.3 + side * wide).expand(edge + out * 1.3 - side * wide) \
					.expand(edge - out * SEAT_END + side * wide).expand(edge - out * SEAT_END - side * wide)
			for j in range(_sample_lo(box.position.y, fs, rows), _sample_hi(box.end.y, fs, rows) + 1):
				for i in range(_sample_lo(box.position.x, fs, cols), _sample_hi(box.end.x, fs, cols) + 1):
					var p := Vector2(-0.5 - margin + i / fs, -0.5 - margin + j / fs)
					var u: float = (p - edge).dot(out)
					# У клітинці мосту (u < 0) насип рівний до SEAT_HALF і сходить до SEAT_SIDE під стіною
					# опори; на березі — повний укіс.
					var lo: float = SEAT_HALF if u < 0.0 else lerpf(SEAT_HALF, flat, smoothstep(0.0, 0.3, u))
					var hi: float = SEAT_SIDE if u < 0.0 else lerpf(SEAT_SIDE, wide, smoothstep(0.0, 0.3, u))
					var w: float = (1.0 - smoothstep(lo, hi, absf((p - centre).dot(side)))) \
							* (1.0 - smoothstep(0.8, 1.3, u)) * clampf((u + SEAT_END) / (SEAT_END - SEAT_REACH), 0.0, 1.0)
					var k: int = j * cols + i
					var target: float = deck + SEAT_TOP - (SEAT_TOP + DECK_LIFT) * smoothstep(0.05, 0.8, u)
					if w <= 0.0 or target <= _h[k]:
						continue
					_h[k] = lerpf(_h[k], target, w)
					_embank_w[k] = maxf(_embank_w[k], w)
					# Насип сухий: маска берега під ним гасне, інакше верх насипу малювався б мулом. Відлік,
					# що й піднятий лишився під водою, — дно: його мокрий вигляд не чіпаємо.
					if _h[k] >= WATER_LEVEL:
						_water[k] *= 1.0 - w
					_max = maxf(_max, _h[k])


## Вузол грубого поля далі за 0.45 клітинки від краю дошки: розмиття продовжує крайові відліки, тож
## біля краю воно витягувало б воду смугою до самого краю з прямими боками.
func _edge_clear(k: int, cw: int, cstep: float) -> bool:
	var x: float = -0.5 - margin + float(k % cw) * cstep
	var z: float = -0.5 - margin + float(k / cw) * cstep
	return minf(minf(x + 0.5, board_width - 0.5 - x), minf(z + 0.5, board_height - 0.5 - z)) >= 0.45


## Замикання не підпускає воду до центру клітинки суші (юніти стоять там): біля кожного центру
## в радіусі 0.5 клітинки поле плавно (від 0.3) повертається до незамкненого. Перевірка — на всіх
## відліках, бо білінійний підйом між вузлами грубого поля може піти нижче нуля. У світі з
## кільцем — лише клітинки дошки: у кільці юніт не стоїть, а повернення лишало б у березі круглі
## вм'ятини.
func _restore_land_clearance(dg: PackedFloat32Array, dc: PackedFloat32Array, dc0: PackedFloat32Array) -> void:
	var fs: float = float(samples)
	var cw: int = (cols - 1 + _RIVER_STEP - 1) / _RIVER_STEP + 1
	var rad: int = ceili(0.5 * fs)
	for cy in range(_shift, board_height - _shift):
		for cx in range(_shift, board_width - _shift):
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


## Відстань (клітинки) від мокрого відліку (d < 0) до найближчого сухого: наближена (`chamfer`,
## кроки 1 і 1.414), два проходи. Вода за краєм карти — продовження води, суші там нема. Глибина
## дна — монотонна функція цієї відстані, тож усередині тіла води дно не підіймається до поверхні.
## w, h, step — інше поле (грубе поле річки з кроком step у клітинках); без них — відліки
## карти висот.
func _inner_distance(dg: PackedFloat32Array, w: int = 0, h: int = 0,
		step: float = 0.0) -> PackedFloat32Array:
	var cols: int = w if w > 0 else self.cols
	var rows: int = h if h > 0 else self.rows
	if step <= 0.0:
		step = 1.0 / float(samples)
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
	for k in out.size():
		out[k] *= step
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
	for g in _course_groups:
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


## Сітка 0/1, розширена на r клітинок (квадрат Чебишова), двома проходами.
static func _dilate(grid: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(w * h)
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			for d in range(maxi(x - r, 0), mini(x + r + 1, w)):
				if grid[y * w + d] == 1:
					a[y * w + x] = 1
					break
	for y in h:
		for x in w:
			for d in range(maxi(y - r, 0), mini(y + r + 1, h)):
				if a[d * w + x] == 1:
					out[y * w + x] = 1
					break
	return out


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
		# Посередині лінії обидва індекси вже в межах: clampi там зайвий, а арифметика та сама.
		var lo: int = mini(r, n)
		var hi: int = maxi(lo, n - 1 - r)
		for i in range(0, lo):
			dst[base + i * stride] = acc * inv
			acc += src[base + clampi(i + r + 1, 0, n - 1) * stride] - src[base + clampi(i - r, 0, n - 1) * stride]
		for i in range(lo, hi):
			dst[base + i * stride] = acc * inv
			acc += src[base + (i + r + 1) * stride] - src[base + (i - r) * stride]
		for i in range(hi, n):
			dst[base + i * stride] = acc * inv
			acc += src[base + clampi(i + r + 1, 0, n - 1) * stride] - src[base + clampi(i - r, 0, n - 1) * stride]
