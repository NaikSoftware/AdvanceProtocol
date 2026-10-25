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
## Ціна кадру (§8): уламок — один меш на деталь силуету; усі стовпи — одна
## MultiMesh, усі язики полум'я — друга, світла вогню — не більше чотирьох. Анімація —
## крок таймера 8 разів на секунду, а не вбудований час шейдера: той тримав би кадр
## щокадрово, і обмеження частоти кадрів у спокої ніколи б не вмикалось.

## Більше стовпів на екрані з'їдає кадр перекриттям прозорих квадів, а не кількістю.
const MAX_COLUMNS: int = 8
## Клуби перекриваються щільно: рідший стовп читається як низка окремих хмарок.
## Суцільний шлейф, а не окремі кулі: багато менших прозорих клуб, кожна живе ~9 с і
## перекривається з десятком сусідніх.
const PUFFS_PER_COLUMN: int = 30
## Екземплярів атласу на одне джерело вогню: накладені з різною фазою, кутом і масштабом,
## вони дають хаотичне полум'я, що весь час міняє форму.
const FLAMES_PER_SPOT: int = 2
const MAX_FIRE_LIGHTS: int = 4
## Крок часу ефектів, разів на секунду: не частіше за обмеження кадру в спокої (30), тож
## вогонь і дим рухаються плавно, а кадр однаково скидається, щойно все догоріло.
const FLIPBOOK_FPS: float = 30.0
## Атлас вогню — швидше за його 8 кадрів/с: справжнє полум'я мерехтить хаотично й швидко.
const FIRE_PLAY_FPS: float = 30.0
## Шлейф: клуба живе стільки секунд від верхівки полум'я до верху.
const PLUME_LIFE_SEC: float = 9.0
## Розігріву досить кількох кадрів.
const WARM_UP_SEC: float = 0.1

## Запечені флипбуки 8×8 (assets/vfx/SOURCES.md). Дим грає раз і закінчується порожнім:
## стовп — це клуби, що стартують уступами, кожна від кадру 0 біля корпусу до порожнього
## нагорі. Тонкий атлас — для стадії, де дим рідшає. Вогонь — безшовна петля.
const SMOKE_TEX: Texture2D = preload("res://assets/vfx/smoke_column.png")
const SMOKE_THIN_TEX: Texture2D = preload("res://assets/vfx/smoke_column_thin.png")
const FIRE_TEX: Texture2D = preload("res://assets/vfx/wreck_fire.png")
const FLIPBOOK_GRID: int = 8
## Клітинка диму ≈ 22 м, сама хмара в ній ≈ 19 м.
const SMOKE_CELL_PER_CLOUD: float = 22.0 / 19.0
## 64 кадри диму по 4 кадри/с: клуба живе 16 с від корпусу до верху стовпа.
const SMOKE_FPS: float = 4.0

## 1 тайл = 8 м: стовп 40 м заввишки (на далекому зумі коротший губився); клуба 2,5 м над
## полум'ям, розходиться до 12 м угорі.
const COLUMN_HEIGHT: float = 40.0 / 8.0
## Свіжий стовп росте від корпусу ~6 м/с: на повну висоту — за ~7 с, а не одразу.
const COLUMN_GROW: float = 6.0 / 8.0
## Народження уламків зі стану (перебудова, збереження): горять давно, стовп уже повний.
const LONG_AGO: float = -10000.0
## Полум'я проступає під темним хвостом кулі: з цієї секунди після загибелі, за пів секунди.
const FIRE_FADE_IN_AT: float = 0.6
const FIRE_FADE_IN_SEC: float = 0.5
const COLUMN_BASE_W: float = 2.5 / 8.0
const COLUMN_TOP_W: float = 12.0 / 8.0
## Вогонь — один стовп полум'я з одного отвору (моторний відсік ззаду), як горить підбита
## машина: ширина ≈ 0,45 ширини корпусу, висота ≈ ширина корпусу. Два екземпляри атласу з
## різною фазою й темпом; основа трохи в металі, м'який край глибини ховає шов.
const FLAME_WIDTH_PER_HULL: float = 0.4
const FLAME_HEIGHT_PER_HULL: float = 1.0
## Атлас вогню: сітка, кадрів, де в клітинці основа полум'я (v згори), яку частку ширини
## клітинки займає полум'я, і висота клітинки до ширини.
static var fire_tex: Texture2D = FIRE_TEX
static var fire_grid: Vector2 = Vector2(8, 8)
static var fire_frames: float = 64.0
static var fire_base_v: float = 0.8
static var fire_fill: float = 0.6
static var fire_cell_aspect: float = 1.0
## Нахил стовпа на одиницю вітру `WeatherRig.wind()`: дим іде туди ж, куди й дощ. За вітру
## River (0,25) це ~20°; у безвітря стовп стоїть прямо.
const SMOKE_LEAN_PER_WIND: float = 1.46
## Полум'я з точок на корпусі — частинки, як вогонь у головному меню: дрібні адитивні цятки
## з гарячим біло-жовтим ядром, що здіймаються, тоншають і червоніють. На джерело — не більше
## FLAME_PARTICLES; коли лишається жар, частинок нема, і довгі уламки нічого не коштують.
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
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = fire_shader()
	# Вогонь — поверх диму власного стовпа, а не за ним.
	_fire_mat.render_priority = 1
	_fire_mat.set_shader_parameter("flame_tex", fire_tex)
	_fire_mat.set_shader_parameter("grid", fire_grid)
	_fire_mat.set_shader_parameter("frames", fire_frames)
	_fire_mat.set_shader_parameter("base_v", fire_base_v)
	_fire_mat.set_shader_parameter("fill", fire_fill)
	_fire_mat.set_shader_parameter("cell_aspect", fire_cell_aspect)
	_fire_mat.set_shader_parameter("gain", 2.8)
	_fire_mat.set_shader_parameter("play_fps", FIRE_PLAY_FPS)
	_fire_mat.set_shader_parameter("fade_in_at", FIRE_FADE_IN_AT)
	_fire_mat.set_shader_parameter("fade_in_sec", FIRE_FADE_IN_SEC)
	_columns = _multimesh("Columns", _column_mat, MAX_COLUMNS * PUFFS_PER_COLUMN)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = _shadow_shader()
	_shadow_mat.set_shader_parameter("height", COLUMN_HEIGHT)
	_shadows = _multimesh("ColumnShadows", _shadow_mat, MAX_COLUMNS)
	_fires = _multimesh("Fires", _fire_mat, MAX_COLUMNS * FLAMES_PER_SPOT)
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


## Стадії: перше коло — три язики й густий дим; друге — один язик і дим ×0,6; третє —
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


## Атлас вогню на заміну (настроювання на тимчасовому флипбуці); діє на нові шари.
static func use_fire_atlas(tex: Texture2D, grid: Vector2, frames: float, base_v: float, fill: float, cell_aspect: float) -> void:
	fire_tex = tex
	fire_grid = grid
	fire_frames = frames
	fire_base_v = base_v
	fire_fill = fill
	fire_cell_aspect = cell_aspect


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
	var top: float = hull.y - HULL_SAG + (0.14 if (spec.extras as Array).has(&"turret") else 0.0)
	# Вогонь виходить з погона в центрі даху: башта стоїть у вогні, корінь видно з будь-якого
	# боку. Два екземпляри обабіч центру — широка маса, а не один язик.
	for local: Vector3 in [Vector3(-hull.x * 0.15, top, -hull.z * 0.1), Vector3(hull.x * 0.15, top, hull.z * 0.1)]:
		out.append(e.node.transform * local)
	return out


## Центр вогню (погон на даху): звідси світло, іскри й дим.
func fire_centre(pos: Vector2i) -> Vector3:
	var spots: Array[Vector3] = flame_spots(pos)
	return (spots[0] + spots[1]) * 0.5


static func flames_for(life: float) -> int:
	if life > 2.0 / 3.0:
		return 1
	if life > 1.0 / 3.0 + 0.01:
		return 1
	return 0


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
	for mi: MultiMeshInstance3D in [_columns, _fires, _shadows]:
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
		# Дим народжується на верхівці стовпа полум'я (чи на даху моторного відсіку, коли вогню
		# вже нема) — не з порожнього повітря поруч.
		var e: _Entry = _entries[c]
		# Видима верхівка полум'я — близько половини висоти кваду: атлас угорі вже розсіюється.
		var origin: Vector3 = fire_centre(c) + Vector3(0.0, 0.5 * flame_height(e.type_id) * flame_scale_for(e.life), 0.0)
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
		var sc: float = flame_scale_for(e.life)
		for j in FLAMES_PER_SPOT:
			# Свої фаза й темп атласу на кожен екземпляр: стовп не мерехтить у такт.
			var sd: float = fposmod(float(hash(c) % 89) / 89.0 + 0.41 * float(j), 1.0)
			fm.set_instance_transform(n, Transform3D(Basis(), flame_spots(c)[j]))
			fm.set_instance_custom_data(n, Color(flame_width(e.type_id) * sc, sd, e.birth, 0.0))
			n += 1
	fm.visible_instance_count = n
	_sync_emitters()
	for i in _lights.size():
		_lights[i].visible = i < _fire_cells.size()
		if _lights[i].visible:
			_lights[i].position = fire_centre(_fire_cells[i]) + Vector3(0.0, 0.12, 0.0)
	if _column_cells.is_empty():
		_timer.stop()
	elif _timer.is_stopped():
		# Таймер поза деревом не стартує; шар без дерева — лише в тестах стану.
		_timer.autostart = true
		if _timer.is_inside_tree():
			_timer.start()


func _ready() -> void:
	if not _column_cells.is_empty():
		_timer.start()


func _step() -> void:
	_frame += 1
	var t: float = float(_frame) / FLIPBOOK_FPS
	_column_mat.set_shader_parameter("fx_time", t)
	_shadow_mat.set_shader_parameter("fx_time", t)
	_fire_mat.set_shader_parameter("fx_time", t)
	_fire_mat.set_shader_parameter("viewport_h", float(get_viewport().get_visible_rect().size.y))
	# Мерехтіння світла — з того самого кроку, без власного таймера.
	for i in _lights.size():
		_lights[i].light_energy = FIRE_LIGHT_ENERGY * (0.7 + 0.6 * _noise1(t * (6.1 + 1.7 * i) + 13.0 * i))


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


static var _shadow_sh: Shader


static func _shadow_shader() -> Shader:
	if _shadow_sh == null:
		_shadow_sh = Shader.new()
		_shadow_sh.code = _SHADOW_CODE
	return _shadow_sh


static func fire_shader() -> Shader:
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
	// Жар — рідкі дрібні плями на верхніх гранях, не суцільна помаранчева плямистість.
}
"""

const _COLUMN_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Колір і пряма альфа — з атласу; між кадрами — плавний перехід.
uniform sampler2D puff_tex : source_color, filter_linear_mipmap;
uniform sampler2D thin_tex : source_color, filter_linear_mipmap;
uniform float grid = 8.0;
// Час крокує таймером WreckLayer, 8 разів на секунду: вбудований час рушія тримав би кадр щокадрово.
uniform float fx_time = 0.0;
uniform float height = 3.0;
uniform float base_w = 0.8;
uniform float top_w = 1.3;
uniform vec3 lean = vec3(0.0);
// Частка шляху клуби за секунду = кадрів/с атласу / 64: кадр і висота йдуть разом.
uniform float rise = 0.0625;
// Ріст свіжого стовпа, одиниць світу за секунду від народження (INSTANCE_CUSTOM.w).
uniform float grow = 0.75;
// Стовп починається з верхівок полум'я (дах корпусу + ~2 м), а не з порожнього повітря.
uniform float column_base = 0.0;
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
	float t = fract(INSTANCE_CUSTOM.x + fx_time * rise);
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
	vec3 wander = (right * sin(sd * 37.0 + fx_time * 0.35) + vec3(0.0, 0.0, 1.0) * cos(sd * 23.0 + fx_time * 0.27)) * w * 0.3 * t;
	vec3 c = root + vec3(0.0, h + column_base, 0.0) + lean * h + wander;
	float roll = sd * 6.2832 + (sd - 0.5) * fx_time * 0.4;
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
	vec2 uv = UV + 0.035 * vec2(sin(UV.y * 11.0 + fx_time * 1.7 + v_sd * 20.0), cos(UV.x * 9.0 - fx_time * 1.3 + v_sd * 13.0));
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
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D flame_tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(8.0);
uniform float frames = 64.0;
// Той самий крок таймера, що й у диму. Петля ≥ 2 с, кожен екземпляр — свій темп ±30 % і старт.
uniform float fx_time = 0.0;
uniform float play_fps = 30.0;
// Понад 1: ядро світиться майже білим, краї й верх — помаранчеві з атласу.
uniform float gain = 2.8;
// Де в клітинці основа полум'я (v згори), яку частку ширини воно займає, висота клітинки до ширини.
uniform float base_v = 0.8;
uniform float fill = 0.6;
uniform float cell_aspect = 1.0;
// На далекому зумі стовп не вужчий за 6 px: інакше вогонь зникає, а дим без нього бреше.
uniform float min_px = 6.0;
// Висота кадру в пікселях: VIEWPORT_SIZE у вершинному шейдері тут нульовий, тож її дає WreckLayer.
uniform float viewport_h = 1080.0;
// Полум'я проступає під темним хвостом кулі (INSTANCE_CUSTOM.z — народження уламків).
uniform float fade_in_at = 0.6;
uniform float fade_in_sec = 0.5;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Основа тоне в металі м'яко, а не обрізається рівною лінією по даху.
uniform float soft_fade = 0.08;

varying float v_frame;
varying float v_in;

float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
// Шум значень: гладкий, але неперіодичний (синус дав би розмірене «танцювання»).
float vnoise(float x) { float i = floor(x); float f = fract(x); return mix(h1(i), h1(i + 1.0), f * f * (3.0 - 2.0 * f)); }

void vertex() {
	// INSTANCE_CUSTOM: x — ширина полум'я (одиниці світу), y — випадковість, z — народження.
	float w = INSTANCE_CUSTOM.x;
	float sd = INSTANCE_CUSTOM.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	// Стовп стоїть вертикально у світі й повернутий до камери лише довкола вертикалі.
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec4 p0 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(root, 1.0);
	vec4 p1 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(root + right * w, 1.0);
	float px = length(p1.xy / p1.w - p0.xy / p0.w) * viewport_h * 0.5;
	w *= clamp(min_px / max(px, 0.001), 1.0, 8.0);
	w *= 0.9 + 0.2 * vnoise(fx_time * (4.1 + 2.7 * sd) + sd * 61.0);
	float qw = w / fill;
	float qh = qw * cell_aspect;
	// Основа полум'я (v = base_v) — у точці отвору, на 1 см у металі.
	float base_y = 0.5 - base_v;
	vec3 world = root + right * VERTEX.x * qw + vec3(0.0, (VERTEX.y - base_y) * qh - 0.01, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_frame = fx_time * play_fps * (0.7 + 0.6 * fract(sd * 7.31)) + sd * frames;
	v_in = clamp((fx_time - INSTANCE_CUSTOM.z - fade_in_at) / fade_in_sec, 0.0, 1.0);
}

vec4 frame_at(float f, vec2 uv) {
	float n = mod(floor(f), frames);
	return texture(flame_tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid.x), floor(n / grid.x))) / grid);
}

void fragment() {
	vec4 tex = mix(frame_at(v_frame, UV), frame_at(v_frame + 1.0, UV), fract(v_frame));
	// Біля отвору — майже біле розжарене серце, вище — колір атласу.
	vec3 col = mix(tex.rgb, vec3(1.0, 0.94, 0.80), smoothstep(base_v - 0.35, base_v, UV.y) * 0.6);
	ALBEDO = col * gain;
	ALPHA = tex.a * v_in;
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
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
	vec3 c = root + vec3(away.x, 0.0, away.y) * reach * 0.5 + vec3(0.0, 0.03, 0.0);
	vec3 world = c + vec3(VERTEX.x, 0.0, VERTEX.y) * 2.0;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_a = 0.3 * sky_clear * INSTANCE_CUSTOM.x * (reach / height);
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = v_a * (1.0 - smoothstep(0.1, 0.5, length(UV - 0.5)));
}
"""

