class_name WreckLayer
extends Node3D
## Уламки, їхній вогонь і стовпи диму для ОДНОГО спостерігача (§3.5, §3.14). Уламки
## переживають юніт, тож туман для них — окремий: вузол, вогонь, світло й дим є лише
## над тайлами, розвіданими (`seen`) спостерігачем. Стовп диму видно через пів мапи,
## тож дим над нерозвіданим — найгучніший донос із можливих.
##
## Читає стан, не потік подій: події не фільтруються за гравцем (§6, відомий борг).
## `add()`/`remove()` — лише для показу щойно зіграних подій; хто викликає `add()`,
## той і перевіряє `seen`.
##
## Ціна кадру (§8): уламок — одна сітка; усі стовпи — одна MultiMesh, усі язики полум'я —
## друга, світла вогню — не більше чотирьох. Анімація — крок таймера 30 разів на секунду,
## а не вбудований час шейдера: той тримав би кадр щокадрово, і обмеження частоти кадрів у
## спокої ніколи б не вмикалось.

## Більше стовпів на екрані з'їдає кадр перекриттям прозорих квадів, а не кількістю.
const MAX_COLUMNS: int = 8
## Клуби перекриваються щільно: рідший стовп читається як низка окремих хмарок.
## Суцільний шлейф, а не окремі кулі: багато менших прозорих клуб, кожна живе ~9 с і
## перекривається з десятком сусідніх.
const PUFFS_PER_COLUMN: int = 30
## Екземплярів атласу на уламок — по одному на корінь, зі своїми фазою й темпом.
const FLAMES_PER_SPOT: int = 2
const MAX_FIRE_LIGHTS: int = 4
## Крок часу ефектів, разів на секунду: не частіше за обмеження кадру в спокої (30), тож
## вогонь і дим рухаються плавно, а кадр однаково скидається, щойно все догоріло.
const FLIPBOOK_FPS: float = 30.0
## Шлейф: клуба живе стільки секунд від верхівки полум'я до верху.
const PLUME_LIFE_SEC: float = 9.0
## Годинники ефектів згорнуто, щоб шейдер не бачив великих чисел (за добу гри fx_time ~ 9·10⁴ с, і
## вогонь розпадався на смуги): стовп диму — період COLUMN_CLOCK_SEC, за який кожна його кутова
## швидкість (кратна COLUMN_RATE_STEP рад/с) робить цілу кількість обертів; вогонь — FIRE_LOOP_SEC,
## за який кожен темп атласу (кратний 1/16) проходить цілу кількість циклів по FIRE_FRAMES кадрів.
const COLUMN_RATE_STEP: float = 0.01
const COLUMN_CLOCK_SEC: float = TAU / COLUMN_RATE_STEP
const FIRE_TEMPO_STEPS: float = 16.0
## Розігріву досить кількох кадрів.
const WARM_UP_SEC: float = 0.1

## Мирний дим мапи: 1–3 димарі й 1–2 руїни. Не клуби (ті виходили залпами, наче кільця диму),
## а один суцільний шлейф на джерело: вузька смуга до камери, що хилиться з вітром і повільно
## звивається; густоту й рваний край дає шум, що пливе вгору зі швидкістю підйому диму, тож уздовж
## шлейфу вона міняється плавно й без жодного періоду. Об'єм — з того ж шуму: його висота дає
## нормаль, яку освітлює сонце мапи (ясно) чи розсіяне світло (похмуро, контрастніше). У мокру погоду
## (1 − sky_clear) дим важчий: до 2,2 раза ширший і до 1,5 густіший біля труби, нахил вітру не більший
## за 0,16, клуби крупніші. Хати й руїни — частина мапи, видимі всім,
## тож цей дим нічого не видає і горить завжди.
const HEARTH_MAX: int = 5
## Густота шлейфу (0–1): ледь помітний, але на телефоні читається — шлейф у середньому світліший за
## ґрунт на 15–25 рівнів (Річка 16, Перехрестя 20 на зумі 8; найяскравіша десята частина — 36–39). Руїна тліє слабше за димар: тонка низька цівка просто з уламків, вужча в основі за димар.
const CHIMNEY_DENSITY: float = 0.36
const RUIN_DENSITY: float = 0.3
## Димар: 14 м заввишки, від 0,8 м біля труби до ~3 м угорі; руїна — 0,55 висоти, вужча внизу за димар.
## Найбільший знос шлейфу вітром на тайл висоти й розмах звивання (коефіцієнти шейдера _PLUME_CODE): з них AABB шлейфу.
const HEARTH_MAX_LEAN: float = 0.45
const HEARTH_WANDER: float = 0.4
const HEARTH_HEIGHT: float = 14.0 / 8.0
const HEARTH_BASE_W: float = 0.8 / 8.0
const HEARTH_TOP_W: float = 0.42
const RUIN_HEIGHT_SCALE: float = 0.55
const RUIN_BASE_SCALE: float = 0.8
## Дим здіймається 0,8 м/с: з цією швидкістю пливе вгору шум густоти.
const HEARTH_RISE: float = 0.8 / 8.0
## Шум шлейфу пливе вгору з такими кратностями швидкості диму, у клітинках шуму на тайл підйому
## (x, y — звивання, z — виїдений край); період шуму — у шейдері _PLUME_CODE.
const PLUME_SCROLL_RATES: Vector3 = Vector3(1.2, 0.9, 8.0 / 3.5)
const PLUME_NOISE_PERIOD: float = 256.0
## Клуби — чотири шари шуму з кроком √2 за розміром: поперек клуб шару k має PLUME_LAYER_SC[k] метрів,
## уздовж — PLUME_LAYER_SC[k]² / PLUME_LAYER_REF: біля труби трохи пласкі (0,6 м), угорі витягнуті
## вгору (4,4 м). Шар не міняє масштабу з висотою, тож пливе вгору рівно зі швидкістю диму; на кожній
## висоті змішано два сусідні шари, чий розмір її обрамляє, — клуби ростуть угору, а візерунок не
## стискається з часом. При REF 0,85 (круглі клуби біля труби) великі витягнуті клуби вгорі
## перемикали яскравість усього шлейфу втричі сильніше — шлейф «дихав».
const PLUME_LAYER_SC: Vector4 = Vector4(0.85, 0.85 * sqrt(2.0), 1.7, 2.4)
const PLUME_LAYER_REF: float = 1.3
## Вертикальних сегментів смуги: шлейф гнеться плавно.
const HEARTH_SEGMENTS: int = 24

## Запечені флипбуки 8×8 (assets/vfx/SOURCES.md). Дим грає раз і закінчується порожнім:
## стовп — це клуби, що стартують уступами, кожна від кадру 0 біля корпусу до порожнього
## нагорі. Тонкий атлас — для стадії, де дим рідшає. Вогонь — процедурний (шейдер вогню).
const SMOKE_TEX: Texture2D = preload("res://assets/vfx/smoke_column.png")
const SMOKE_THIN_TEX: Texture2D = preload("res://assets/vfx/smoke_column_thin.png")
const FLIPBOOK_GRID: int = 8
## Вогонь — запечений цикл полум'я 16×4 по 64 кадри (docs/art/vfx-flipbook-sources.md), 30 кадрів/с.
## true — запечений Flame02, false — процедурний шейдер (_FIRE_CODE).
const USE_FLAME02: bool = true
const FIRE_SHADER: Shader = preload("res://game/battle/shaders/fire.gdshader")
const FIRE_TEX: Texture2D = preload("res://assets/vfx/flame02.png")
const FIRE_GRID: Vector2 = Vector2(16.0, 4.0)
const FIRE_FRAMES: float = 64.0
## Основа язика в клітинці (v згори), частка ширини клітинки під язик і висота клітинки до
## ширини; верхівка — ≈ 0,18 від верху клітинки, звідти й народжується дим.
const FIRE_BASE_V: float = 0.92
const FIRE_FILL: float = 0.55
const FIRE_CELL_ASPECT: float = 2.0
const FIRE_TIP_V: float = 0.18
## Висота верхівки над основою у ширинах полум'я (`flame_width`).
const FLAME_TIP_PER_WIDTH: float = (FIRE_BASE_V - FIRE_TIP_V) * FIRE_CELL_ASPECT / FIRE_FILL
## Клітинка диму ≈ 22 м, сама хмара в ній ≈ 19 м.
const SMOKE_CELL_PER_CLOUD: float = 22.0 / 19.0
## 64 кадри диму по 4 кадри/с: клуба живе 16 с від корпусу до верху стовпа.
const SMOKE_FPS: float = 4.0

## 1 тайл = 8 м: стовп 40 м заввишки (на далекому зумі коротший губився); клуба 2,5 м над
## полум'ям, розходиться до 12 м угорі.
const COLUMN_HEIGHT: float = 40.0 / 8.0
## Свіжий стовп росте від корпусу ~6 м/с: на повну висоту — за ~7 с, а не одразу.
const COLUMN_GROW: float = 6.0 / 8.0
## Вогонь малюється поверх диму власного стовпа (дим має пріоритет 0).
const FIRE_PRIORITY: int = 1
## Народження уламків зі стану (перебудова, збереження): горять давно, стовп уже повний.
const LONG_AGO: float = -10000.0
## Полум'я проступає під темним хвостом кулі: з цієї секунди після загибелі, за пів секунди.
const FIRE_FADE_IN_AT: float = 0.6
const FIRE_FADE_IN_SEC: float = 0.5
const COLUMN_BASE_W: float = 2.5 / 8.0
const COLUMN_TOP_W: float = 12.0 / 8.0
## Вогонь виходить з погона: два корені обабіч центру даху башти, кожен — білборд ≈ 0,88
## ширини корпусу (≈ 3,2 м у середнього танка); внизу вони перекриваються в одну масу, без
## голого даху між язиками. Висота ≈ 1,45 ширини корпусу. Основа трохи в металі, м'який край глибини ховає шов.
const FLAME_WIDTH_PER_HULL: float = 0.88
const FLAME_HEIGHT_PER_HULL: float = 1.45
## Найвищий язик над основою (0,6 клітинки): вищий накривав нижню половину юніта на сусідній
## клітинці; язики вище м'яко гаснуть, а стовп диму починається з цієї верхівки.
const FLAME_MAX_H: float = 0.6
## Нахил стовпа на одиницю вітру `WeatherRig.wind()`: дим іде туди ж, куди й дощ. За вітру
## River (0,25) це ~20°; у безвітря стовп стоїть прямо.
const SMOKE_LEAN_PER_WIND: float = 1.46
## Іскри з вогню: кілька за раз (бюджет телефону), більше — поки горить сильно.
const EMBERS_HARD: int = 10
const EMBERS_SOFT: int = 4
static var _ember_process: ParticleProcessMaterial
static var _ember_draw: StandardMaterial3D
const SPARK_GLOW: Texture2D = preload("res://game/ui/theme/glow_radial.tres")

## Тепле світло вогню над отвором: радіус ~3,5 м — дах довкола отвору й земля поруч жевріють.
const FIRE_LIGHT_RANGE: float = 3.5 / 8.0
const FIRE_LIGHT_ENERGY: float = 2.0

## Ствол опущено на 8° (обгорілі уламки), корпус осів на 0,15 м.
const BARREL_DROP_DEG: float = 8.0
const HULL_SAG: float = 0.15 / 8.0

static var _burnt: ShaderMaterial
static var _column_shader: Shader
static var _fire_shader: Shader

class _Entry:
	var node: Node3D
	var type_id: int
	var life: float
	## `fx_time()` у мить появи уламків; LONG_AGO — для перебудованих зі стану.
	var birth: float

var _entries: Dictionary[Vector2i, _Entry] = {}
var _embers: Dictionary[Vector2i, GPUParticles3D] = {}
var _columns: MultiMeshInstance3D
## Мʼяка тінь під кожним стовпом — лише на ясних мапах (густота — від `sky_clear` у шейдері).
var _shadows: MultiMeshInstance3D
var _shadow_mat: ShaderMaterial
var _fires: MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _column_mat: ShaderMaterial
var _fire_mat: ShaderMaterial
var _timer: Timer
var _frame: int = 0
var _warm: MeshInstance3D = null
## Загиблі відділення: чотири лежачі фігури на тайлі, де відділення полягло.
var _fallen: Dictionary[Vector2i, MultiMeshInstance3D] = {}
var _column_cells: Array[Vector2i] = []
var _hearths: MultiMeshInstance3D
var _hearth_mat: ShaderMaterial
var _hearth_points: Array[Vector3] = []
var _hearth_densities: Array[float] = []
var _hearth_shapes: Array[Vector2] = []
var _fire_cells: Array[Vector2i] = []


func _init() -> void:
	_column_mat = ShaderMaterial.new()
	_column_mat.shader = column_shader()
	_column_mat.set_shader_parameter("puff_tex", SMOKE_TEX)
	_column_mat.set_shader_parameter("thin_tex", SMOKE_THIN_TEX)
	_column_mat.set_shader_parameter("grid", float(FLIPBOOK_GRID))
	_column_mat.set_shader_parameter("height", COLUMN_HEIGHT)
	_column_mat.set_shader_parameter("base_w", COLUMN_BASE_W * SMOKE_CELL_PER_CLOUD)
	_column_mat.set_shader_parameter("top_w", COLUMN_TOP_W * SMOKE_CELL_PER_CLOUD)
	_column_mat.set_shader_parameter("rise", 1.0 / PLUME_LIFE_SEC)
	_column_mat.set_shader_parameter("grow", COLUMN_GROW)
	_column_mat.set_shader_parameter("rate_step", COLUMN_RATE_STEP)
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = fire_shader()
	# Вогонь — поверх диму власного стовпа, а не за ним.
	_fire_mat.render_priority = FIRE_PRIORITY
	if USE_FLAME02:
		_fire_mat.set_shader_parameter("flame_tex", FIRE_TEX)
		_fire_mat.set_shader_parameter("grid", FIRE_GRID)
		_fire_mat.set_shader_parameter("frames", FIRE_FRAMES)
		_fire_mat.set_shader_parameter("play_fps", FLIPBOOK_FPS)
		_fire_mat.set_shader_parameter("base_v", FIRE_BASE_V)
		_fire_mat.set_shader_parameter("fill", FIRE_FILL)
		_fire_mat.set_shader_parameter("cell_aspect", FIRE_CELL_ASPECT)
	_fire_mat.set_shader_parameter("gain", 1.6)
	_fire_mat.set_shader_parameter("fade_in_at", FIRE_FADE_IN_AT)
	_fire_mat.set_shader_parameter("fade_in_sec", FIRE_FADE_IN_SEC)
	_fire_mat.set_shader_parameter("max_h", FLAME_MAX_H)
	_fire_mat.set_shader_parameter("loop_sec", fire_loop_sec())
	_fire_mat.set_shader_parameter("tempo_steps", FIRE_TEMPO_STEPS)
	_columns = _multimesh("Columns", _column_mat, MAX_COLUMNS * PUFFS_PER_COLUMN)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = _shadow_shader()
	_shadow_mat.set_shader_parameter("height", COLUMN_HEIGHT)
	_shadows = _multimesh("ColumnShadows", _shadow_mat, MAX_COLUMNS)
	_fires = _multimesh("Fires", _fire_mat, MAX_COLUMNS * FLAMES_PER_SPOT)
	_hearth_mat = ShaderMaterial.new()
	_hearth_mat.shader = _plume_shader()
	_hearth_mat.set_shader_parameter("height", HEARTH_HEIGHT)
	_hearth_mat.set_shader_parameter("base_w", HEARTH_BASE_W)
	_hearth_mat.set_shader_parameter("top_w", HEARTH_TOP_W)
	_hearth_mat.set_shader_parameter("layer_sc", PLUME_LAYER_SC)
	_hearth_mat.set_shader_parameter("layer_ref", PLUME_LAYER_REF)
	_hearths = _multimesh("Hearths", _hearth_mat, HEARTH_MAX)
	var strip := QuadMesh.new()
	strip.size = Vector2.ONE
	strip.subdivide_depth = HEARTH_SEGMENTS
	_hearths.multimesh.mesh = strip
	for i in MAX_FIRE_LIGHTS:
		var l := OmniLight3D.new()
		l.name = "FireLight%d" % i
		l.light_color = Color("e0702a")
		l.light_energy = FIRE_LIGHT_ENERGY
		l.omni_range = FIRE_LIGHT_RANGE
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	_timer = Timer.new()
	_timer.name = "FlipbookStep"
	_timer.wait_time = 1.0 / FLIPBOOK_FPS
	_timer.timeout.connect(_step)
	add_child(_timer)


func rebuild(state: BattleState, observer: int) -> void:
	_clear()
	for w in state.wrecks:
		if state.vision[observer].is_seen(w.pos):
			_add_node(w.pos, w.type_id, life_of(state, w), w.facing, LONG_AGO)
	_refresh_effects()


## Частка горіння, що лишилась: 1 — щойно знищено, → 0 — от-от догорить. Лише
## стадія показу (вогонь, густота диму); жодне правило її не читає.
static func life_of(state: BattleState, w: Wrecks.Wreck) -> float:
	var total: int = Wrecks.WRECK_ROUNDS * state.player_count
	return clampf(float(w.burns_out_at - state.turn_clock()) / float(total), 0.0, 1.0)


## Стадії: перше коло — повне полум'я й густий дим; друге — менше полум'я й дим ×0,6; третє —
## дим ×0,3; останній хід — голі уламки. Ціле число ходів у частці горіння (6 для двох
## гравців), тож пороги стоять між кроками, а не на них.
static func column_opacity_for(life: float) -> float:
	if life > 2.0 / 3.0:
		return 1.0
	if life > 1.0 / 3.0 + 0.01:
		return 0.6
	if life > 0.2:
		return 0.3
	return 0.0


## Розмір полум'я за стадією, частка повного: горить → вщухає → без вогню.
static func flame_scale_for(life: float) -> float:
	if life > 2.0 / 3.0:
		return 1.0
	if life > 1.0 / 3.0 + 0.01:
		return 0.55
	return 0.0


static func flame_width(type_id: int) -> float:
	return (UnitSilhouettes.spec(type_id).hull as Vector3).x * FLAME_WIDTH_PER_HULL


static func flame_height(type_id: int) -> float:
	return (UnitSilhouettes.spec(type_id).hull as Vector3).x * FLAME_HEIGHT_PER_HULL


func ember_emitter(pos: Vector2i) -> GPUParticles3D:
	return _embers.get(pos, null)


func flame_spots(pos: Vector2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not _entries.has(pos):
		return out
	var e: _Entry = _entries[pos]
	var spec: Dictionary = UnitSilhouettes.spec(e.type_id)
	var hull: Vector3 = spec.hull
	# Корені — на даху башти: обидва в межах її сліду, тож нижче башта ховала б їх з усіх боків.
	var top: float = hull.y - HULL_SAG + (UnitSilhouettes.TURRET_HEIGHT if (spec.extras as Array).has(&"turret") else 0.0)
	# Вогонь виходить з погона в центрі даху: башта стоїть у вогні, корінь видно з будь-якого
	# боку. Два екземпляри обабіч центру — широка маса, а не один язик.
	for local: Vector3 in [Vector3(-hull.x * 0.15, top, -hull.z * 0.1), Vector3(hull.x * 0.15, top, hull.z * 0.1)]:
		out.append(e.node.transform * local)
	return out


## Центр вогню (погон на даху): звідси світло, іскри й дим.
## Ширина й висота кожного з двох язиків, одиниці світу: з корпусу, менші на другому колі.
func flame_size(pos: Vector2i) -> Vector2:
	if not _entries.has(pos):
		return Vector2.ZERO
	var e: _Entry = _entries[pos]
	return Vector2(flame_width(e.type_id), flame_height(e.type_id)) * flame_scale_for(e.life)


func fire_centre(pos: Vector2i) -> Vector3:
	var spots: Array[Vector3] = flame_spots(pos)
	return (spots[0] + spots[1]) * 0.5


static func flames_for(life: float) -> int:
	return 1 if flame_scale_for(life) > 0.0 else 0


func add(pos: Vector2i, type_id: int, life: float, facing: int = 0) -> void:
	if _entries.has(pos):
		return
	_add_node(pos, type_id, life, facing, fx_time())
	_refresh_effects()


func remove(pos: Vector2i) -> void:
	if not _entries.has(pos):
		return
	_entries[pos].node.free()
	_entries.erase(pos)
	_refresh_effects()


## Вітер вигляду (`WeatherRig.wind()`), горизонтальний вектор.
func set_wind(wind: Vector3) -> void:
	_column_mat.set_shader_parameter("lean", wind * SMOKE_LEAN_PER_WIND)
	_hearth_mat.set_shader_parameter("lean", wind * SMOKE_LEAN_PER_WIND)


## Мирний дим: з `chimneys` (верхи димарів) — 1–3, з `ruins` (центри руїн) — 1–2, вибрані за `seed`
## мапи, тож у кожного гравця й у кожному бою на цій мапі ті самі. `locate` (якщо задано) переводить
## обраний центр руїни в точку на її уламках (`PropLayer.ruin_smoke_point_at`): важка вибірка лише для обраних.
func set_hearths(chimneys: Array[Vector3], ruins: Array[Vector3], seed: int, locate: Callable = Callable()) -> void:
	_hearth_points.clear()
	_hearth_densities.clear()
	_hearth_shapes.clear()
	for ruin: bool in [false, true]:
		var pts: Array[Vector3] = _pick(ruins, 1 + (absi(seed) / 3) % 2, seed) if ruin else _pick(chimneys, 1 + absi(seed) % 3, seed)
		for p: Vector3 in pts:
			_hearth_points.append(locate.call(p) if ruin and locate.is_valid() else p)
			_hearth_densities.append(hearth_density(ruin))
			_hearth_shapes.append(hearth_shape(ruin))
	assert(_hearth_points.size() <= HEARTH_MAX, "3 димарі + 2 руїни — більше шлейфів не буває")
	var mm: MultiMesh = _hearths.multimesh
	for h in _hearth_points.size():
		# INSTANCE_CUSTOM: x — густота, y — зсув шуму (свій шлейф у кожного джерела), z — частка
		# висоти, w — частка ширини біля джерела.
		mm.set_instance_transform(h, Transform3D(Basis(), _hearth_points[h]))
		mm.set_instance_custom_data(h, Color(_hearth_densities[h], float(hash(_hearth_points[h]) % 997) / 997.0,
				_hearth_shapes[h].x, _hearth_shapes[h].y))
	mm.visible_instance_count = _hearth_points.size()
	_hearths.custom_aabb = _hearth_bounds()
	_refresh_effects()


## Тісний AABB усіх шлейфів із запасом на ширину, нахил вітром і звивання: прозорі об'єкти сортуються за центром AABB,
## тож коробка мусить стояти біля самих шлейфів, а не на всю дошку. Шлейфів мало, тож спільна коробка лишається тісною.
func _hearth_bounds() -> AABB:
	if _hearth_points.is_empty():
		return AABB(Vector3.ZERO, Vector3(0.1, 0.1, 0.1))
	var reach: float = hearth_reach()
	var box := AABB()
	for h in _hearth_points.size():
		var one := AABB(_hearth_points[h] + Vector3(-reach, -0.1, -reach), Vector3(2.0 * reach, HEARTH_HEIGHT * _hearth_shapes[h].x + 0.2, 2.0 * reach))
		box = one if h == 0 else box.merge(one)
	return box


## Найбільший горизонтальний виліт шлейфу від джерела: напівширина угорі (смуга на 35 % ширша за шлейф), знос вітром на повну
## висоту й половина звивання.
static func hearth_reach() -> float:
	return HEARTH_TOP_W * 1.35 + HEARTH_MAX_LEAN * HEARTH_HEIGHT + HEARTH_WANDER * HEARTH_HEIGHT * 0.5


## Зсуви шуму шлейфу на секунді матчу `t`: рахуються в подвійній точності й згортаються за періодом
## шуму, тож шейдер бачить малі числа й через години гри.
static func plume_scroll(t: float) -> Vector3:
	var d: float = t * HEARTH_RISE
	return Vector3(fposmod(d * PLUME_SCROLL_RATES.x, PLUME_NOISE_PERIOD), fposmod(d * PLUME_SCROLL_RATES.y, PLUME_NOISE_PERIOD),
			fposmod(d * PLUME_SCROLL_RATES.z, PLUME_NOISE_PERIOD))


## Клітинок шуму шару k на тайл підйому: 8 м, поділені на висоту його клуба.
static func plume_layer_rate(k: int) -> float:
	return 8.0 * PLUME_LAYER_REF / (PLUME_LAYER_SC[k] * PLUME_LAYER_SC[k])


## Зсуви чотирьох шарів клубів на секунді `t`, згорнуті за періодом шуму.
static func plume_layer_scroll(t: float) -> Vector4:
	var d: float = t * HEARTH_RISE
	var out := Vector4()
	for k in 4:
		out[k] = fposmod(d * plume_layer_rate(k), PLUME_NOISE_PERIOD)
	return out


## Годинник бічного дрейфу й обертання клуб стовпа: секунди матчу за модулем COLUMN_CLOCK_SEC.
static func column_clock(t: float) -> float:
	return fposmod(t, COLUMN_CLOCK_SEC)


## Шлях клуб стовпа вгору (частка підйому): за модулем 1, як і fract у шейдері.
static func column_phase(t: float) -> float:
	return fposmod(t / PLUME_LIFE_SEC, 1.0)


## Період атласу вогню: кожен темп k/FIRE_TEMPO_STEPS проходить за нього рівно k циклів.
static func fire_loop_sec() -> float:
	return FIRE_FRAMES * FIRE_TEMPO_STEPS / FLIPBOOK_FPS


static func fire_loop_time(t: float) -> float:
	return fposmod(t, fire_loop_sec())


## Густота шлейфу для шейдера (0–1): руїна тліє слабше за димар.
static func hearth_density(ruin: bool) -> float:
	return RUIN_DENSITY if ruin else CHIMNEY_DENSITY


## Звідки росте стовп диму остова: з верхівки полум'я над погоном (чи з самого погону, коли
## вогню вже нема) — не з порожнього повітря поруч, і не вище за 0,85 стелі полум'я.
func smoke_origin(c: Vector2i) -> Vector3:
	# Процедурний вогонь суцільний у нижні ~60 % висоти; атласний — до верхівки язика.
	var rise: float = minf(FLAME_TIP_PER_WIDTH * flame_size(c).x if USE_FLAME02 else 0.6 * flame_size(c).y, FLAME_MAX_H * 0.85)
	return fire_centre(c) + Vector3(0.0, rise, 0.0)


## Форма шлейфу: x — частка висоти HEARTH_HEIGHT, y — частка ширини HEARTH_BASE_W біля джерела.
static func hearth_shape(ruin: bool) -> Vector2:
	return Vector2(RUIN_HEIGHT_SCALE, RUIN_BASE_SCALE) if ruin else Vector2.ONE


## `count` точок із `pts`, перемішаних за `seed`.
static func _pick(pts: Array[Vector3], count: int, seed: int) -> Array[Vector3]:
	var out: Array[Vector3] = pts.duplicate()
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return hash(a + Vector3(seed, 0, 0)) < hash(b + Vector3(seed, 0, 0)))
	out.resize(mini(count, out.size()))
	return out


## Густота, яку отримав кожен шлейф (у тому ж порядку, що й `hearth_points`).
func hearth_densities() -> Array[float]:
	return _hearth_densities


## Форма, яку отримав кожен шлейф (`hearth_shape`), у тому ж порядку.
func hearth_shapes() -> Array[Vector2]:
	return _hearth_shapes


func hearth_points() -> Array[Vector3]:
	return _hearth_points


func hearth_material() -> ShaderMaterial:
	return _hearth_mat


## Розігрів шейдерів стовпа, вогню й обгорілого матеріалу: кілька кадрів малюємо по
## одному нульовому екземпляру й крихітну коробку в `at`, далі все як було.
func warm_up(at: Vector3) -> void:
	if _warm != null:
		return
	_warm = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.0001
	_warm.mesh = box
	_warm.material_override = burnt_material()
	_warm.position = at
	add_child(_warm)
	# Іскри теж компілюють шейдери на першому вбивстві — одна крихітна.
	_ember_emitter(at, 1, 1).reparent(_warm)
	for mi: MultiMeshInstance3D in [_columns, _fires, _shadows, _hearths]:
		if mi.multimesh.visible_instance_count == 0:
			mi.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), at))
			mi.multimesh.set_instance_custom_data(0, Color(0, 0, 0, 0))
			mi.multimesh.visible_instance_count = 1
	# Твін, а не `await`: він гине разом із шаром, тож звільнений шар не прокинеться.
	var tw: Tween = create_tween()
	tw.tween_interval(WARM_UP_SEC)
	tw.tween_callback(_end_warm_up)


func _end_warm_up() -> void:
	if _warm == null:
		return
	_warm.free()
	_warm = null
	# Розігрів позичав екземпляр 0 і в мирного диму: на мапі без димарів він лишився б.
	_hearths.multimesh.visible_instance_count = _hearth_points.size()
	_refresh_effects()


## Загиблі відділення — зі стану (мертві юніти лишаються в `state.units`), тож вони
## переживають і перебудову, і збереження. Лише над розвіданим глядача (§3.5): тіла на
## нерозвіданому — донос про бій. Техніка тут не малюється: її лишки — уламки.
func rebuild_fallen(state: BattleState, observer: int) -> void:
	for f: MultiMeshInstance3D in _fallen.values():
		f.free()
	_fallen.clear()
	for id: int in state.units:
		var u: Unit = state.units[id]
		if u.is_alive() or u.unit_class() != UnitTypes.UnitClass.INFANTRY or _fallen.has(u.pos):
			continue
		if not state.vision[observer].is_seen(u.pos):
			continue
		var f: MultiMeshInstance3D = UnitSilhouettes.figures(0, UnitSilhouettes.FALLEN_COLOR)
		f.name = "Fallen_%d_%d" % [u.pos.x, u.pos.y]
		f.position = IsoCameraRig.cell_to_world(u.pos)
		f.rotation.y = deg_to_rad(UnitView._degrees_for_facing(u.facing))
		f.layers = 1 << (UnitView.UNIT_LAYER - 1)
		add_child(f)
		_fallen[u.pos] = f


func fallen_count() -> int:
	return _fallen.size()


func fallen_at(pos: Vector2i) -> MultiMeshInstance3D:
	return _fallen.get(pos, null)


## Час ефектів, секунд: крок таймера, а не годинник рушія (див. _step()).
func fx_time() -> float:
	return float(_frame) / FLIPBOOK_FPS


func birth_of(pos: Vector2i) -> float:
	return _entries[pos].birth if _entries.has(pos) else LONG_AGO


func is_warming() -> bool:
	return _warm != null


func column_lean() -> Vector3:
	var v: Variant = _column_mat.get_shader_parameter("lean")
	return v if v is Vector3 else Vector3.ZERO


func wreck_count() -> int:
	return _entries.size()


func wreck_at(pos: Vector2i) -> Node3D:
	return _entries[pos].node if _entries.has(pos) else null


func column_count() -> int:
	return _column_cells.size()


func has_column(pos: Vector2i) -> bool:
	return _column_cells.has(pos)


func column_opacity(pos: Vector2i) -> float:
	return column_opacity_for(_entries[pos].life) if _entries.has(pos) else 0.0


func flame_count(pos: Vector2i) -> int:
	return flames_for(_entries[pos].life) if _entries.has(pos) else 0


func fire_count() -> int:
	return _fire_cells.size()


func fire_light_count() -> int:
	return _lights.filter(func(l: OmniLight3D) -> bool: return l.visible).size()


func is_animating() -> bool:
	return not _timer.is_stopped()


## Вугіль, іржа й попіл плямами 0,5–1,5 м за світовим шумом: уламки читаються
## відтінком, а не лише формою, і без жодного сліду камуфляжу чи кольору власника.
static func burnt_material() -> ShaderMaterial:
	if _burnt == null:
		_burnt = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = _BURNT_CODE
		_burnt.shader = sh
		# Лінійні кольори нейтрального вугільно-сірого корпусу (L* 21 / 27 / 41, a*/b* ≈ 0):
		# помаранчевим він стає лише біля вогню, від його світла, а не від власного кольору.
		_burnt.set_shader_parameter("char_color", Color(0.035, 0.034, 0.033))
		_burnt.set_shader_parameter("rust_color", Color(0.060, 0.051, 0.044))
		_burnt.set_shader_parameter("ash_color", Color(0.14, 0.14, 0.135))
		_burnt.set_shader_parameter("char_share", 0.45)
		_burnt.set_shader_parameter("ash_share", 0.15)
	return _burnt


## Силует живого юніта того самого типу без власника: спільний обгорілий матеріал,
## опущений ствол, осілий і ледь перекошений корпус. Напрям — юніта в мить загибелі
## (`Wreck.facing`). Перекіс — з хешу тайла, а не з
## `Rules.roll()`: косметика не сміє зсувати кидки правил, і хеш дає всім ті самі уламки.
static func build_wreck(pos: Vector2i, type_id: int, facing: int) -> Node3D:
	var root := UnitSilhouettes.build(type_id, Color.BLACK)
	root.name = "Wreck_%d_%d" % [pos.x, pos.y]
	# Усі частини — в одну сітку: один виклик малювання й одна тінь на уламки (бюджет §8).
	var st := SurfaceTool.new()
	for part: Node in root.get_children():
		var m := part as MeshInstance3D
		m.position.y -= HULL_SAG
		if m.name == "Barrel":
			m.rotation.x = -deg_to_rad(BARREL_DROP_DEG)
		st.append_from(m.mesh, 0, m.transform)
		m.free()
	var merged := MeshInstance3D.new()
	merged.name = "Body"
	merged.mesh = st.commit()
	merged.material_override = burnt_material()
	merged.layers = 1 << (UnitView.UNIT_LAYER - 1)
	root.add_child(merged)
	var h: int = hash(pos)
	# Перекіс — довкола осей самого корпусу, після повороту: інакше нахил «їде» з напрямом.
	root.basis = Basis(Vector3.UP, deg_to_rad(UnitView._degrees_for_facing(facing))) \
		* Basis.from_euler(Vector3(deg_to_rad(float(h % 5 - 2)), 0.0, deg_to_rad(float((h >> 6) % 5 - 2))))
	root.position = IsoCameraRig.cell_to_world(pos)
	return root


func _add_node(pos: Vector2i, type_id: int, life: float, facing: int, birth: float) -> void:
	var e := _Entry.new()
	e.node = build_wreck(pos, type_id, facing)
	e.type_id = type_id
	e.life = life
	e.birth = birth
	add_child(e.node)
	_entries[pos] = e


func _clear() -> void:
	for em: GPUParticles3D in _embers.values():
		em.free()
	_embers.clear()
	for e: _Entry in _entries.values():
		e.node.free()
	_entries.clear()


## Понад MAX_COLUMNS гасне найстаріший дим, уламки лишаються всі.
## shortcut: обмеження стовпів і світел — на всю дошку, а не лише на видиме в кадрі;
## коли на мапі буде більше восьми свіжих уламків одночасно, рахувати лише ті, що в кадрі.
func _refresh_effects() -> void:
	var cells: Array[Vector2i] = []
	for c: Vector2i in _entries:
		if column_opacity_for(_entries[c].life) > 0.0:
			cells.append(c)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _entries[a].life > _entries[b].life)
	_column_cells.assign(cells.slice(0, MAX_COLUMNS))
	_fire_cells.clear()
	for c in _column_cells:
		if flames_for(_entries[c].life) > 0:
			_fire_cells.append(c)
	var mm: MultiMesh = _columns.multimesh
	for i in _column_cells.size():
		var c: Vector2i = _column_cells[i]
		var seed: float = float(hash(c) % 997) / 997.0
		var opacity: float = column_opacity_for(_entries[c].life)
		var origin: Vector3 = smoke_origin(c)
		for k in PUFFS_PER_COLUMN:
			var idx: int = i * PUFFS_PER_COLUMN + k
			mm.set_instance_transform(idx, Transform3D(Basis(), origin))
			# z — густота стадії, від'ємна — тонкий атлас (дим уже рідшає); w — народження стовпа.
			mm.set_instance_custom_data(idx, Color(float(k) / float(PUFFS_PER_COLUMN), fposmod(seed + 0.618 * k, 1.0), -opacity if opacity <= 0.3 else opacity, _entries[c].birth))
	mm.visible_instance_count = _column_cells.size() * PUFFS_PER_COLUMN
	var sm: MultiMesh = _shadows.multimesh
	for i in _column_cells.size():
		sm.set_instance_transform(i, Transform3D(Basis(), IsoCameraRig.cell_to_world(_column_cells[i])))
		sm.set_instance_custom_data(i, Color(absf(column_opacity_for(_entries[_column_cells[i]].life)), 0, 0, _entries[_column_cells[i]].birth))
	sm.visible_instance_count = _column_cells.size()
	var fm: MultiMesh = _fires.multimesh
	var n: int = 0
	for c in _fire_cells:
		var e: _Entry = _entries[c]
		var size: Vector2 = flame_size(c)
		for j in FLAMES_PER_SPOT:
			# Свій зсув шуму на кожен язик: два стовпи ніколи не рухаються в такт.
			var sd: float = fposmod(float(hash(c) % 89) / 89.0 + 0.41 * float(j), 1.0)
			# Перший стовпець базису — шлях від кореня до центру вогню: язики хиляться до центру,
			# і вогонь читається одним, а не двома пучками по кутах.
			var to_centre: Vector3 = fire_centre(c) - flame_spots(c)[j]
			fm.set_instance_transform(n, Transform3D(Basis(Vector3(to_centre.x, 0.0, to_centre.z), Vector3.UP, Vector3.BACK), flame_spots(c)[j]))
			fm.set_instance_custom_data(n, Color(size.x, sd, e.birth, size.y))
			n += 1
	fm.visible_instance_count = n
	_sync_emitters()
	for i in _lights.size():
		_lights[i].visible = i < _fire_cells.size()
		if _lights[i].visible:
			_lights[i].position = fire_centre(_fire_cells[i]) + Vector3(0.0, 0.12, 0.0)
	# shortcut: поки на мапі є мирний дим, таймер не спиняється ніколи — цей шар анімується завжди,
	# і простій кадру в спокої (§8) мусить це врахувати; коли простій з'явиться, крокувати мирний
	# дим рідше (кілька разів на секунду) або гасити його, поки нічого іншого не рухається.
	if _column_cells.is_empty() and _hearth_points.is_empty():
		_timer.stop()
	elif _timer.is_stopped():
		# Таймер поза деревом не стартує; шар без дерева — лише в тестах стану.
		_timer.autostart = true
		if _timer.is_inside_tree():
			_timer.start()


func _ready() -> void:
	if not _column_cells.is_empty() or not _hearth_points.is_empty():
		_timer.start()


func _step() -> void:
	_frame += 1
	var t: float = float(_frame) / FLIPBOOK_FPS
	_column_mat.set_shader_parameter("fx_time", t)
	_column_mat.set_shader_parameter("clock", column_clock(t))
	_column_mat.set_shader_parameter("phase", column_phase(t))
	_hearth_mat.set_shader_parameter("scroll", plume_scroll(t))
	_hearth_mat.set_shader_parameter("layer_scroll", plume_layer_scroll(t))
	_shadow_mat.set_shader_parameter("fx_time", t)
	_fire_mat.set_shader_parameter("fx_time", t)
	_fire_mat.set_shader_parameter("loop_time", fire_loop_time(t))
	_fire_mat.set_shader_parameter("viewport_h", float(get_viewport().get_visible_rect().size.y))
	# Світло дихає повільно (гладкий шум, нижче ~2 Гц): швидке мерехтіння на землі й даху виглядало б стробом.
	for i in _lights.size():
		_lights[i].light_energy = FIRE_LIGHT_ENERGY * (0.85 + 0.3 * _noise1(t * (1.2 + 0.3 * i) + 13.0 * i))


func _sync_emitters() -> void:
	for c: Vector2i in _embers.keys():
		if not _fire_cells.has(c) or not _entries.has(c) or _embers[c].amount != _ember_amount(_entries[c].life):
			_embers[c].free()
			_embers.erase(c)
	for c in _fire_cells:
		if not _embers.has(c):
			_embers[c] = _ember_emitter(fire_centre(c), _ember_amount(_entries[c].life), hash(c))


static func _ember_amount(life: float) -> int:
	return EMBERS_HARD if flame_scale_for(life) >= 1.0 else EMBERS_SOFT


## Іскри: дрібні яскраві цятки вилітають сплесками — переважно вгору з жаром, деякі вбік,
## живуть 0,5–1,5 с, холонуть до темно-червоного й гаснуть, зносяться вітром.
func _ember_emitter(at: Vector3, amount: int, seed: int) -> GPUParticles3D:
	var em := GPUParticles3D.new()
	em.name = "Embers"
	em.amount = amount
	em.lifetime = 1.5
	em.preprocess = 1.5
	# Сплески, а не рівний струмінь: частина іскор вилітає разом, у випадкові моменти.
	em.explosiveness = 0.55
	em.randomness = 0.9
	em.use_fixed_seed = true
	em.seed = seed
	em.local_coords = false
	if _ember_process == null:
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3.UP
		mat.spread = 55.0
		mat.initial_velocity_min = 0.15
		mat.initial_velocity_max = 0.6
		mat.gravity = Vector3(0.05, 0.05, -0.05)
		mat.damping_min = 0.1
		mat.damping_max = 0.3
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.05
		mat.lifetime_randomness = 0.65
		mat.scale_min = 0.5
		mat.scale_max = 1.0
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 1.0), Color(1.0, 0.5, 0.15, 0.8), Color(0.6, 0.12, 0.03, 0.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		mat.color_ramp = gt
		_ember_process = mat
		_ember_draw = StandardMaterial3D.new()
		_ember_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ember_draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ember_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ember_draw.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_ember_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_ember_draw.vertex_color_use_as_albedo = true
		_ember_draw.albedo_texture = SPARK_GLOW
	em.process_material = _ember_process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.25 / 8.0
	quad.material = _ember_draw
	em.draw_pass_1 = quad
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.layers = 1 << (UnitView.UNIT_LAYER - 1)
	em.visibility_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 2, 2))
	add_child(em, true)
	em.global_position = at
	return em


## Шум значень для мерехтіння світла: гладкий, неперіодичний (синус дав би ритм).
static func _noise1(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	var a: float = fposmod(sin(i * 127.1) * 43758.5453, 1.0)
	var b: float = fposmod(sin((i + 1.0) * 127.1) * 43758.5453, 1.0)
	return lerpf(a, b, f * f * (3.0 - 2.0 * f))


func _multimesh(node_name: String, mat: ShaderMaterial, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Вершини зсуває шейдер: без широкої AABB стовп зникав би, щойно корінь за кадром.
	mi.custom_aabb = AABB(Vector3(-1000, -10, -1000), Vector3(2000, 40, 2000))
	mi.layers = 1 << (UnitView.UNIT_LAYER - 1)
	add_child(mi)
	return mi


static func column_shader() -> Shader:
	if _column_shader == null:
		_column_shader = Shader.new()
		_column_shader.code = _COLUMN_CODE
	return _column_shader


static var _plume_sh: Shader


static func _plume_shader() -> Shader:
	if _plume_sh == null:
		_plume_sh = Shader.new()
		_plume_sh.code = _PLUME_CODE
	return _plume_sh


static var _shadow_sh: Shader


static func _shadow_shader() -> Shader:
	if _shadow_sh == null:
		_shadow_sh = Shader.new()
		_shadow_sh.code = _SHADOW_CODE
	return _shadow_sh


static func fire_shader() -> Shader:
	if USE_FLAME02:
		return FIRE_SHADER
	if _fire_shader == null:
		_fire_shader = Shader.new()
		_fire_shader.code = _FIRE_CODE
	return _fire_shader


const _BURNT_CODE: String = """
shader_type spatial;
render_mode cull_back;

uniform vec3 char_color : source_color;
uniform vec3 rust_color : source_color;
uniform vec3 ash_color : source_color;
uniform float char_share = 0.45;
uniform float ash_share = 0.15;
// Плями 0,5–1,5 м: одиниця світу — тайл, 8 м.
uniform float patch_scale = 8.0;

varying vec3 wp;

float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 q = wp * patch_scale;
	float n = 0.65 * vn(q) + 0.35 * vn(q * 2.7 + 13.0);
	// Шум згладжений до середини, тож пороги розтягнуто, щоб частки вийшли близькими до заданих.
	float u = clamp((n - 0.25) / 0.5, 0.0, 1.0);
	// М'які переходи й дрібний попіл: різкі великі плями читаються як камуфляж.
	vec3 col = mix(char_color, rust_color, smoothstep(char_share - 0.18, char_share + 0.18, u));
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	float fleck = vn(q * 3.1 + 7.0);
	col = mix(col, ash_color, smoothstep(1.0 - ash_share, 1.0 - ash_share + 0.12, fleck) * (0.35 + 0.65 * up));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
"""

## Суцільний шлейф мирного диму: смуга до камери (поворот лише довкола вертикалі), висота й
## нахил вітру — як у стовпа уламків. Звивання й густота — шум у координаті «частинки диму»:
## висота мінус зсув `scroll` (plume_scroll), тож візерунок пливе вгору разом із димом.
## Зсув рахує процесор і тримає в [0, PLUME_NOISE_PERIOD): шум має той самий період, тож згортка
## не дає стрибка, а координати шуму не ростуть із часом матчу — на великих числах GPU втрачає
## точність, і шлейф після години гри розсипався на голки й темні риски.
const _PLUME_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float height = 1.75;
uniform float base_w = 0.1;
uniform float top_w = 1.0;
// Зсуви шуму вгору (у клітинках шуму, за модулем періоду): x, y — звивання, z — край.
uniform vec3 scroll = vec3(0.0);
// Шари клубів (PLUME_LAYER_SC): розмір поперек у метрах і зсув кожного.
uniform vec4 layer_sc = vec4(0.85, 1.2, 1.7, 2.4);
uniform float layer_ref = 0.85;
uniform vec4 layer_scroll = vec4(0.0);
const float PERIOD = 256.0;
uniform vec3 lean = vec3(0.0);
global uniform vec3 sun_dir;
global uniform float sky_clear;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying float v_h01;
varying float v_hh;
varying float v_w;
varying float v_sd;
varying float v_dens;
varying vec3 v_sun;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
// Шум із періодом PERIOD по обох осях: координату згортаємо до запуску, тож числа малі завжди.
float vn(vec2 p) {
	p = mod(p, PERIOD);
	vec2 i = floor(p);
	vec2 f = p - i;
	// mod у float інколи дає рівно PERIOD: клітинку згортаємо ще раз, щоб хеш не вийшов за період.
	i = mod(i, PERIOD);
	f = f * f * (3.0 - 2.0 * f);
	vec2 j = mod(i + 1.0, PERIOD);
	return mix(mix(hash(i), hash(vec2(j.x, i.y)), f.x), mix(hash(vec2(i.x, j.y)), hash(j), f.x), f.y);
}
// Висота клуба: гладкий шум із трьох октав, піднесений, щоб випуклини були округлі, а не кашаті.
float puff_h(vec2 p) {
	// Мокра погода: крупніші клуби (дрібні октави слабші), щоб не розсипалися на смуги.
	float heavy = 1.0 - sky_clear;
	float w2 = mix(0.45, 0.22, heavy);
	float w3 = mix(0.18, 0.06, heavy);
	// Кратність октав ціла: інакше згортка зсуву розірвала б шум на стику періоду.
	float a = vn(p) + w2 * vn(p * 2.0 + 3.7) + w3 * vn(p * 4.0 + 9.1);
	return a / (1.0 + w2 + w3);
}
// xy — нахил поверхні клуба (звідси нормаль і світло), z — сама висота. Скінченні різниці:
// без швів між клітинками, тож клуби м'які, а не потріскані.
vec3 billow(vec2 p) {
	float e = 0.12;
	float h0 = puff_h(p);
	return vec3((puff_h(p + vec2(e, 0.0)) - h0) / e, (puff_h(p + vec2(0.0, e)) - h0) / e, h0);
}

float pick(vec4 v, int k) {
	return k == 0 ? v.x : (k == 1 ? v.y : (k == 2 ? v.z : v.w));
}
// Клуби шару k: розмір сталий по висоті, тож шар пливе вгору рівно з димом і не стискається.
vec3 layer_billow(int k, float xm, float hm, float sd) {
	float sc = pick(layer_sc, k);
	float sv = sc * sc / layer_ref;
	return billow(vec2(xm * 8.0 / sc, hm * 8.0 / sv - pick(layer_scroll, k)) + sd + float(k) * 17.3);
}

void vertex() {
	// INSTANCE_CUSTOM: x — густота, y — зсув шуму, z — частка висоти, w — частка ширини внизу.
	float H = height * INSTANCE_CUSTOM.z;
	float h01 = VERTEX.y + 0.5;
	float h = h01 * H;
	float sd = INSTANCE_CUSTOM.y * 97.0;
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 side = vec3(-right.z, 0.0, right.x);
	// Звивання росте з висотою й пливе вгору з димом: повільний шум у координаті частинки.
	vec3 wander = (right * (vn(vec2(h * 1.2 - scroll.x + sd, 3.1)) - 0.5) + side * (vn(vec2(h * 0.9 - scroll.y + sd, 7.7)) - 0.5)) * 0.4 * H * h01 * h01;
	// Мокра погода: дим важчий — ширший біля труби й не лягає на землю (нахил обмежено).
	float heavy = 1.0 - sky_clear;
	float w = mix(base_w * INSTANCE_CUSTOM.w * (1.0 + 1.2 * heavy), top_w, pow(h01, 0.85));
	// Знос убік не більший за пів підйому навіть у ясну погоду (під похмурим небом — 0,16), інакше стовп повзе пласко й врізається в стіни.
	vec3 lean_c = lean * mix(min(1.0, 0.45 / max(length(lean), 1e-4)), min(1.0, 0.16 / max(length(lean), 1e-4)), heavy);
	// Смуга на 35 % ширша за шлейф: пухнастий край вилазить за обрис і не впирається в межу кваду.
	// Корінь на 0,5 м у шахті: стінки димаря ховають низ смуги, і дим виходить із самого отвору, а не з повітря над шапкою.
	vec3 world = root + vec3(0.0, h - 0.5 / 8.0, 0.0) + lean_c * h + wander + right * VERTEX.x * w * 1.35;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	v_h01 = h01;
	v_hh = h;
	v_w = w;
	v_sd = sd;
	v_dens = INSTANCE_CUSTOM.x * (1.0 + 0.5 * heavy * (1.0 - smoothstep(0.0, 0.5, h01)));
	// Напрямок на сонце в базисі екрана: x праворуч, y вниз (як UV), z до глядача.
	v_sun = normalize(vec3(dot(sun_dir, INV_VIEW_MATRIX[0].xyz), -dot(sun_dir, INV_VIEW_MATRIX[1].xyz), dot(sun_dir, INV_VIEW_MATRIX[2].xyz)) + 1e-4);
}

void fragment() {
	float x = (UV.x * 2.0 - 1.0) * 1.35;
	// Клуби в метрах поперек і вздовж частинки диму: біля труби дрібні, угорі крупніші.
	float sc = mix(mix(0.8, 0.9, 1.0 - sky_clear), 2.4, v_h01);
	// Не шум у (h − t·rise)/sc: там час множився на масштаб, що змінюється з висотою, і за годину гри
	// шум стискався по вертикалі в сотні разів — шлейф розсипався на горизонтальні голки. Тут — два
	// сусідні шари сталого розміру, що обрамляють sc на цій висоті; змішування залежить лише від висоти.
	float u = clamp(log(sc / layer_sc.x) / log(layer_sc.w / layer_sc.x) * 3.0, 0.0, 3.0);
	int k = min(int(u), 2);
	float f = u - float(k);
	vec3 a = mix(layer_billow(k, x * v_w, v_hh, v_sd), layer_billow(k + 1, x * v_w, v_hh, v_sd), f);
	// Суміш двох незалежних шумів пласкіша за кожен: повертаємо розкид, щоб між шарами клуби не блякли.
	float g = inversesqrt(f * f + (1.0 - f) * (1.0 - f));
	a = vec3(a.xy * g, 0.5 + (a.z - 0.5) * g);
	// Висота 0..1 з контрастом: клуби проступають із розмитої маси.
	float lump = smoothstep(0.25, 0.75, a.z);
	// Біля отвору клуби ще не сформувались: рівна густота й світло по всій ширині, інакше яскравий клуб
	// з одного боку зсуває видимий стовп над дах поруч із трубою.
	float born = smoothstep(0.04, 0.2, v_h01);
	lump = mix(0.7, lump, born);
	a.xy *= born;
	// Серцевина шлейфу рівна: клуби там дають темні западини, що на тлі землі читаються як розрив і розкладають стовп на дві цівки.
	float core = 1.0 - smoothstep(0.15, 0.65, abs(x));
	lump = mix(lump, 0.7, 0.8 * core);
	a.xy *= 1.0 - 0.8 * core;
	// Повільний шум краю, окремий для лівого й правого боку, пливе вгору з димом: край
	// виїдається вглиб, і обрис — не конус. Лише на краях: біля осі шум двох боків різний, і без цього на осі виходив
	// шов-розрив, що розколював шлейф надвоє; з тієї ж причини клуби (`lump`) зсувають лише край, а серцевина шлейфу суцільна.
	float side_sd = v_sd + (x < 0.0 ? 0.0 : 31.0);
	float bite = (vn(vec2(v_hh * 8.0 / 3.5 - scroll.z + side_sd, side_sd * 0.37)) - 0.35) * 0.7 * smoothstep(0.05, 0.25, v_h01) * smoothstep(0.3, 0.9, abs(x));
	// Запас до краю: клуби відкушують його, угорі дим розривається на клапті. М'яка рампа — пух, а не контур.
	// Перші ~0,1 тайла край не рваний: інакше густіший бік зсуває видимий стовп убік від отвору, і дим ніби йде з даху поруч.
	float e = 1.0 - abs(x) + (lump - 0.5) * mix(0.45, 0.3, 1.0 - sky_clear) * smoothstep(0.2, 0.7, abs(x)) * smoothstep(0.03, 0.12, v_h01) - bite - 0.25 * smoothstep(0.4, 1.0, v_h01);
	float dens = smoothstep(0.0, 0.6, e) * mix(0.6 + 0.4 * lump, 0.7 + 0.3 * lump, 1.0 - sky_clear);
	// Тане раніше за верх смуги: шлейф не доходить до хат позаду.
	float fade = smoothstep(0.03, 0.08, v_h01) * (1.0 - smoothstep(0.12, 0.68, v_h01));
	// Нормаль: клуби поверх округлого шлейфу в цілому.
	// Висота росте вгору (a.y — за q.y), а базис нормалі має y вниз: знак y перевернуто.
	vec3 n = normalize(vec3(vec2(-a.x, a.y) * mix(2.6, 1.1, sky_clear), 1.0) + vec3(x * 0.8, 0.0, 0.4 * sqrt(max(1.0 - x * x, 0.0))));
	// Ясно — сонце; похмуро — розсіяне світло зверху (y вниз, тож «вгору» — мінус), але з більшим
	// контрастом нормалі й діапазону світла, ніж у сонця, щоб об'єм читався й без нього.
	vec3 L = normalize(mix(vec3(0.0, -0.75, 0.66), v_sun, sky_clear));
	float lam = clamp(dot(n, L) * 0.5 + 0.5, 0.0, 1.0);
	lam = clamp((lam - 0.5) * mix(1.35, 1.0, sky_clear) + 0.5, 0.0, 1.0);
	vec3 lit_col = mix(vec3(0.46, 0.48, 0.52), vec3(0.78, 0.76, 0.73), sky_clear);
	vec3 shade_col = mix(vec3(0.10, 0.11, 0.14), vec3(0.28, 0.34, 0.42), sky_clear);
	vec3 col = mix(shade_col, lit_col, smoothstep(0.15, 0.9, lam));
	// Западини між клубами й гущавина всередині темніші.
	col *= mix(0.55, 1.0, smoothstep(0.1, 0.8, lump));
	ALBEDO = col;
	ALPHA = clamp(dens * fade * v_dens * 0.55, 0.0, 1.0);
	// М'який перехід на стику з геометрією (дах, стіна димаря): 1,1 м біля отвору, до 1,6 м вище — ширина росте з висотою,
	// щоб жорсткого краю не лишалось там, де шлейф торкається покрівлі поруч із трубою.
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, край біля даху там буде жорсткішим.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / (mix(1.1, 1.6, smoothstep(0.0, 0.25, v_h01)) / 8.0), 0.0, 1.0);
}
"""


const _COLUMN_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Колір і пряма альфа — з атласу; між кадрами — плавний перехід.
uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
uniform sampler2D thin_tex : source_color, filter_linear_mipmap;
uniform float grid = 8.0;
// Час крокує таймером WreckLayer, 30 разів на секунду: вбудований час рушія тримав би кадр щокадрово.
// fx_time — лише для віку стовпа (різниця з народженням); рух — зі згорнутих годинників нижче.
uniform float fx_time = 0.0;
// Секунди за модулем періоду, кратного обертам усіх кутових швидкостей (WreckLayer.COLUMN_CLOCK_SEC).
uniform float clock = 0.0;
// fx_time · rise за модулем 1 (WreckLayer.column_phase).
uniform float phase = 0.0;
uniform float rate_step = 0.01;
uniform float height = 3.0;
uniform float base_w = 0.8;
uniform float top_w = 1.3;
uniform vec3 lean = vec3(0.0);
// Частка шляху клуби за секунду = 1 / PLUME_LIFE_SEC: кадр атласу й висота йдуть разом.
uniform float rise = 0.0625;
// Ріст свіжого стовпа, одиниць світу за секунду від народження (INSTANCE_CUSTOM.w).
uniform float grow = 0.75;
// Сонце (WeatherRig): освітлений бік клуби світліший на ясних мапах; у похмурі — нічого.
global uniform vec3 sun_dir;
global uniform float sky_clear;
varying vec2 v_sun;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї (1,2 м) лише там, де клуба врізається в землю чи уламки.
uniform float soft_fade = 0.15;

varying float v_alpha;
varying float v_frame;
varying float v_thin;
varying float v_dark;
varying float v_sd;

void vertex() {
	// INSTANCE_CUSTOM: x — фаза клуби в шлейфі, y — її випадковість, z — густота стадії
	// (від'ємна — тонкий атлас), w — народження стовпа.
	float t = fract(INSTANCE_CUSTOM.x + phase);
	float sd = INSTANCE_CUSTOM.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	// Клуба швидка над вогнем і сповільнюється вгорі, розходячись ширше.
	float h = pow(t, 0.7) * height;
	// Біля самого полум'я клуби більші й густіші: стовп видимо починається з вогню.
	float birth = 1.0 - smoothstep(0.0, 0.08, t);
	float w = mix(base_w, top_w, sqrt(t)) * (1.0 + 0.6 * birth);
	// Хаотичний бічний дрейф росте з висотою й повільно змінюється в часі.
	vec3 wander = (right * sin(sd * 37.0 + clock * 0.35) + vec3(0.0, 0.0, 1.0) * cos(sd * 23.0 + clock * 0.27)) * w * 0.3 * t;
	vec3 c = root + vec3(0.0, h, 0.0) + lean * h + wander;
	// Швидкість обертання клуби — кратна rate_step: тоді згортка годинника не дає стрибка.
	float roll = sd * 6.2832 + round((sd - 0.5) * 0.4 / rate_step) * rate_step * clock;
	vec2 v = vec2(cos(roll) * VERTEX.x - sin(roll) * VERTEX.y, sin(roll) * VERTEX.x + cos(roll) * VERTEX.y);
	vec3 world = c + (right * v.x + up * v.y) * w * (0.85 + 0.3 * sd);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	// Свіжий стовп росте від корпусу: клуби вище досягнутої висоти ще невидимі.
	float reach = max(fx_time - INSTANCE_CUSTOM.w, 0.0) * grow;
	// Кожна клуба прозора: густину дає перекриття сусідніх, а не одна непрозора куля.
	// Біля вогню клуби малі й густі (народжуються в полум'ї, без проміжку), далі прозоріші.
	float puff = mix(0.75, 0.4, smoothstep(0.0, 0.25, t)) * (1.0 + 0.3 * birth) * (0.85 + 0.3 * sd) * smoothstep(0.0, 0.015, t) * (1.0 - smoothstep(0.45, 1.0, t));
	v_alpha = abs(INSTANCE_CUSTOM.z) * puff * (1.0 - smoothstep(reach - 0.3, reach, h));
	// На далекому зумі тонкий стовп блякнув: густіший і темніший здалеку.
	float far = smoothstep(12.0, 30.0, length(CAMERA_POSITION_WORLD - c));
	v_alpha = min(1.0, v_alpha * mix(1.0, 1.6, far));
	v_dark = mix(1.0, 0.75, far);
	// Кадр — від шляху клуби: атлас росте й розсіюється разом із нею.
	// Перші кадри атласу майже порожні (клуба ще не з'явилася): біля вогню тримаємо кадр 2,
	// інакше між полум'ям і стовпом видно проміжок.
	v_frame = max(t * (grid * grid - 1.0), 2.0);
	v_thin = INSTANCE_CUSTOM.z < 0.0 ? 1.0 : 0.0;
	v_sd = sd;
	v_sun = normalize(vec2(dot(sun_dir, right), -dot(sun_dir, up)) + 1e-4);
}

vec4 frame_at(sampler2D atlas, float f, vec2 uv) {
	float n = clamp(f, 0.0, grid * grid - 1.0);
	return texture(atlas, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid), floor(n / grid))) / grid);
}

void fragment() {
	// Край клуби кипить: UV зміщене повільним хвилястим шумом, свій для кожної клуби.
	vec2 uv = UV + 0.035 * vec2(sin(UV.y * 11.0 + clock * 1.7 + v_sd * 20.0), cos(UV.x * 9.0 - clock * 1.3 + v_sd * 13.0));
	vec4 a0;
	vec4 a1;
	if (v_thin > 0.5) {
		a0 = frame_at(thin_tex, floor(v_frame), uv);
		a1 = frame_at(thin_tex, floor(v_frame) + 1.0, uv);
	} else {
		a0 = frame_at(puff_tex, floor(v_frame), uv);
		a1 = frame_at(puff_tex, floor(v_frame) + 1.0, uv);
	}
	vec4 tex = mix(a0, a1, fract(v_frame));
	float lit = clamp(dot(normalize(uv - 0.5 + 1e-4), v_sun), 0.0, 1.0) * smoothstep(0.05, 0.35, length(uv - 0.5));
	ALBEDO = tex.rgb * v_dark * (1.0 + 0.45 * sky_clear * lit);
	ALPHA = tex.a * v_alpha;
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""

const _FIRE_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Процедурне полум'я без текстури. Густота — шум, чию область великими хвилями гне інший
// шум, що пливе вгору; поріг густоти росте з висотою. Основа (нижні ~40 %) майже
// нерухома: бічний зсув і викривлення домену ростуть із висотою від нуля. Жар = густота ×
// (1 − h)^1,5: біле — лише біля кореня, далі жовте → помаранчеве → темно-червоне → кіптява.
// Язики — окремі клапті, що відриваються від верху в випадкові миті, летять угору й
// гаснуть у дим. Дрібний шум лише їде вгору разом з полум'ям, на місці не «кипить».
// Жодного періодичного руху; у кожного білборда свій зсув і свій час.
uniform float fx_time = 0.0;
// Понад 1: біле серце світиться; верхня половина — вдвічі тьмяніша.
uniform float gain = 1.6;
// Квад ширший і вищий за полум'я, щоб м'який край і клапті не різались рамкою.
uniform float pad = 2.6;
uniform float sink = 0.08;
uniform float tall = 1.6;
// На далекому зумі язик не вужчий за 6 px: гаряча основа мусить читатися й там.
uniform float min_px = 6.0;
// Висота кадру в пікселях: VIEWPORT_SIZE у вершинному шейдері тут нульовий, тож її дає WreckLayer.
uniform float viewport_h = 1080.0;
// Полум'я проступає під темним хвостом кулі (INSTANCE_CUSTOM.z — народження уламків).
uniform float fade_in_at = 0.6;
uniform float fade_in_sec = 0.5;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Основа тоне в металі м'яко, а не обрізається рівною лінією по даху.
uniform float soft_fade = 0.08;
// Швидкість підйому язика у світі, одиниць світу за секунду (≈ 2,25 м/с при 8 м на тайл).
uniform float tongue_speed = 0.28;

varying float v_in;
varying float v_sd;
varying float v_lean;
varying float v_rise;

// Хеш без sin: sin великого аргументу у float32 губить точність і дає прямокутні латки.
float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) { return 0.6 * vn(p) + 0.4 * vn(p * 2.07 + 17.0); }
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float vnoise(float x) { float i = floor(x); float f = fract(x); return mix(h1(i), h1(i + 1.0), f * f * (3.0 - 2.0 * f)); }

void vertex() {
	// INSTANCE_CUSTOM: x — ширина полум'я, w — висота (одиниці світу), y — випадковість, z — народження.
	float w = INSTANCE_CUSTOM.x;
	float h = INSTANCE_CUSTOM.w;
	vec3 root = MODEL_MATRIX[3].xyz;
	// Стовп стоїть вертикально у світі й повернутий до камери лише довкола вертикалі.
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec4 p0 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(root, 1.0);
	vec4 p1 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(root + right * w, 1.0);
	float px = length(p1.xy / p1.w - p0.xy / p0.w) * viewport_h * 0.5;
	float grow = clamp(min_px / max(px, 0.001), 1.0, 8.0);
	// Здалеку вогонь більший (як і дим густіший): на далекому зумі він інакше губився.
	grow *= mix(1.0, 1.4, smoothstep(12.0, 30.0, length(CAMERA_POSITION_WORLD - root)));
	w *= grow;
	h *= grow;
	// UV.y = 0 згори; низ кваду — на `sink` висоти під коренем, верх — на `tall` висоти.
	vec3 world = root + right * VERTEX.x * w * pad + vec3(0.0, (VERTEX.y + 0.5) * h * (tall + sink) - h * sink, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_in = clamp((fx_time - INSTANCE_CUSTOM.z - fade_in_at) / fade_in_sec, 0.0, 1.0);
	v_sd = INSTANCE_CUSTOM.y;
	// Підйом язика у висотах полум'я за секунду.
	v_rise = tongue_speed / max(INSTANCE_CUSTOM.w, 1e-4);
	// Куди від кореня центр вогню на екрані, у ширинах полум'я.
	v_lean = dot(right, MODEL_MATRIX[0].xyz) / max(INSTANCE_CUSTOM.x, 1e-4);
}

void fragment() {
	// x — частка ширини полум'я від осі (±0,5 — край); y — висота над коренем у висотах полум'я.
	float x = (UV.x - 0.5) * pad;
	float y = (1.0 - UV.y) * (tall + sink) - sink;
	float t = fx_time + v_sd * 37.0;
	vec2 seed = vec2(v_sd * 7.1, v_sd * 2.3);
	float hh = y;
	// Вага руху: нуль на корені й у нижніх ~40 %, повна вгорі.
	float wob = smoothstep(0.4, 1.0, clamp(hh, 0.0, 1.0));
	// Верх хитається вбік (шум, не синус); основа стоїть.
	x += (vnoise(t * 2.2 + v_sd * 13.0) - 0.5) * 0.4 * wob;
	// Вище основи язик хилиться до центру даху: обидва сходяться в один вогонь.
	x -= v_lean * 0.8 * smoothstep(0.2, 0.7, hh);
	// Великі хвилі: ~1,75 циклу на ширину, амплітуда ~0,25 ширини, пливуть угору ~2 висоти/с.
	vec2 big = vec2(x * 1.75, y * 1.2 - t * 2.5) + seed;
	vec2 warp = (vec2(fbm(big), fbm(big + vec2(4.7, 1.3))) - 0.5) * vec2(0.7, 0.5) * wob;
	vec2 q = vec2(x, y) + warp;
	// Дрібниця пливе повільніше за хвилі.
	float d = fbm(vec2(q.x * 3.2, q.y * 2.4 - t * 2.1) + seed * 1.7);
	// Ширина: найширше біля кореня, вужче вгорі; м'який край.
	float half_w = mix(0.62, 0.26, clamp(hh, 0.0, 1.0)) * 0.9;
	float shape = 1.0 - smoothstep(half_w * 0.45, half_w, abs(q.x));
	// Внизу густота рівна й суцільна; угорі контрастна — поріг перетинає її на різній висоті,
	// тож верх рваний, а не зрізаний рівно.
	float dens = mix(0.35 + 0.75 * d, 0.15 + 1.1 * d * d, smoothstep(0.35, 0.9, hh));
	float n = dens * shape * smoothstep(-sink, 0.03, y);
	// Поріг росте з висотою: угорі вціліють лише клапті густоти.
	float thr = 0.15 + 0.5 * hh;
	// Біля верху кваду все гасне: клапті не зрізаються його краєм.
	// Широкий м'який перехід порогу, а край ще й роз'їдає дрібний швидкий шум: пасма, що
	// тоншають у дим, а не вирізаний папір.
	float body = smoothstep(thr - 0.15, thr + 0.4, n) * (1.0 - smoothstep(tall - 0.4, tall - 0.05, y));
	float fine = fbm(vec2(q.x * 19.0, q.y * 14.0 - t * 6.5) + seed * 3.1);
	body *= mix(1.0, fine, 1.0 - body);
	// Угорі язики гаснуть, а не висять яскраво-червоними клаптями.
	body *= 1.0 - smoothstep(0.6, 1.0, hh);
	// Той самий дрібний шум — смуги й просвіти всередині тіла.
	float heat = clamp(1.4 * n * pow(clamp(1.0 - 0.7 * hh, 0.0, 1.0), 1.5) + (fine - 0.5) * 0.4, 0.0, 1.0);
	// Кольори лінійні (екран переводить у sRGB): темно-червоне — #A52A0A, помаранчеве, жовте, біле.
	vec3 col = mix(vec3(0.033, 0.005, 0.002), vec3(0.376, 0.023, 0.003), smoothstep(0.05, 0.25, heat));
	col = mix(col, vec3(1.0, 0.22, 0.015), smoothstep(0.2, 0.4, heat));
	col = mix(col, vec3(1.0, 0.477, 0.051), smoothstep(0.5, 0.7, heat));
	// Блідо-жовто-біле серце — лише в нижній чверті висоти.
	col = mix(col, vec3(1.0, 0.83, 0.40), smoothstep(0.62, 0.8, heat) * (1.0 - smoothstep(0.25, 0.38, hh)));
	// HDR — лише гарячому серцю: помаранчеве й червоне, помножене на gain, вигоріло б у жовте.
	// Верхня половина — вдвічі тьмяніша: світиться серце, а не язики.
	col *= mix(1.0, gain, smoothstep(0.5, 0.9, heat)) * mix(1.0, 0.5, smoothstep(0.5, 0.9, hh));
	// Вище ~0,7 висоти колір іде в сірий дим, а не в яскраво-червоне.
	col = mix(col, vec3(0.06, 0.055, 0.05), smoothstep(0.7, 1.0, hh));
	// Непрозорість згасає крізь червону смугу в кіптяву; довкола — ледь помітне світіння.
	float a = body * smoothstep(0.0, 0.12, heat);
	// Розсіяне світіння довкола полум'я — ширше за саме полум'я в 1,5 раза.
	float halo = 1.0 - smoothstep(half_w * 0.6, half_w * 1.5, abs(q.x));
	// Світіння мерехтить разом із вогнем (шум, не синус), а не стоїть сталою плямою.
	float glow = 0.3 * (0.8 + 0.4 * vnoise(t * 1.2 + 3.0)) * halo * (1.0 - smoothstep(0.0, 0.8, hh)) * smoothstep(-sink, 0.05, y);
	float alpha = a * v_in;
	// Язики: три місця, у кожного свої випадкові миті. Час кожного місця ділиться на відтинки
	// різної довжини; у відтинку язик стартує не одразу, живе 0,3–1 с, летить угору, меншає й гасне.
	float tong = 0.0;
	float tu = 0.0;
	for (int k = 0; k < 3; k++) {
		float kf = float(k);
		float len = 1.2 + 0.4 * h2(vec2(kf, v_sd * 5.0));
		float tk = t + kf * 0.37;
		float ci = floor(tk / len);
		vec2 cs = vec2(ci + kf * 31.0, v_sd * 9.0 + kf);
		float start = h2(cs) * 0.45 * len;
		float life = min(0.3 + 0.7 * h2(cs + 7.3), len - start);
		float s = tk - ci * len - start;
		if (s >= 0.0 && s < life) {
			float u = s / life;
			float cx = (h2(cs + 3.1) - 0.5) * 0.3;
			float cy = 0.5 + 0.15 * h2(cs + 5.9) + s * v_rise;
			float sc = 1.0 - 0.5 * u;
			vec2 dq = vec2((x - cx) / (0.1 * sc), (y - cy) / (0.16 * sc));
			float edge = length(dq) + (fbm(vec2(x * 6.0, y * 5.0 - t * 2.0) + seed) - 0.5) * 0.5;
			float b = (1.0 - smoothstep(0.5, 1.0, edge)) * (1.0 - u);
			if (b > tong) {
				tong = b;
				tu = u;
			}
		}
	}
	// Колір язика: помаранчеве → темно-червоне зі зростанням віку, вище — сірий дим.
	vec3 tcol = mix(vec3(1.0, 0.36, 0.03), vec3(0.376, 0.023, 0.003), tu);
	tcol = mix(tcol, vec3(0.06, 0.055, 0.05), smoothstep(0.7, 1.0, y));
	float ta = tong * v_in;
	float ab = alpha * smoothstep(0.35, 0.6, heat);
	vec3 rgb = col * alpha + vec3(0.79, 0.1, 0.007) * glow * v_in;
	rgb += tcol * ta * (1.0 - ab);
	ab = ab + ta * (1.0 - ab);
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	float soft = clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
	// Попередньо помножена альфа: гаряче тіло перекриває фон, а холодна кромка лише додає
	// світло — інакше край ближнього язика лягав би темною смугою на сусідній.
	ALBEDO = rgb * soft;
	ALPHA = ab * soft;
}
"""

## М'яка тінь стовпа на землі: пляма ~16 м, зсунута від сонця на половину висоти стовпа,
## густа лише під ясним небом. Росте разом зі стовпом.
const _SHADOW_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

global uniform vec3 sun_dir;
global uniform float sky_clear;
uniform float fx_time = 0.0;
uniform float height = 5.0;
uniform float grow = 0.75;

varying float v_a;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec2 away = -sun_dir.xz / max(sun_dir.y, 0.25);
	float reach = min(max(fx_time - INSTANCE_CUSTOM.w, 0.0) * grow, height);
	// Низьке сонце відкинуло б пляму за кілька тайлів від стовпа: не далі за тайл.
	vec2 off = away * reach * 0.5;
	off *= min(1.0, 1.0 / max(length(off), 1e-4));
	vec3 c = root + vec3(off.x, 0.0, off.y) + vec3(0.0, 0.03, 0.0);
	vec3 world = c + vec3(VERTEX.x, 0.0, VERTEX.y) * 2.0;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_a = 0.3 * sky_clear * INSTANCE_CUSTOM.x * (reach / height);
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = v_a * (1.0 - smoothstep(0.1, 0.5, length(UV - 0.5)));
}
"""

