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
const PUFFS_PER_COLUMN: int = 14
const MAX_FLAMES: int = 3
const MAX_FIRE_LIGHTS: int = 4
const FLIPBOOK_FPS: float = 8.0
## Розігріву досить кількох кадрів.
const WARM_UP_SEC: float = 0.1

## Слоти текстур: справжній флипбук замінює заступника заміною файла. Нема файла —
## процедурний заступник тієї самої сітки кадрів.
const SMOKE_TEX_PATH: String = "res://assets/vfx/smoke_column.png"
const FIRE_TEX_PATH: String = "res://assets/vfx/wreck_fire.png"
const FLIPBOOK_GRID: int = 8

## 1 тайл = 8 м: стовп 25 м заввишки, 3 м біля основи, 8 м угорі.
const COLUMN_HEIGHT: float = 25.0 / 8.0
const COLUMN_BASE_W: float = 3.0 / 8.0
const COLUMN_TOP_W: float = 8.0 / 8.0
## Язики полум'я 3 / 2,2 / 1,6 м: на ходу загибелі всі три, далі один.
const FLAME_M: Array[float] = [3.0, 2.2, 1.6]
## Нахил стовпа на одиницю вітру `WeatherRig.wind()`: дим іде туди ж, куди й дощ. За вітру
## River (0,25) це ~20°; у безвітря стовп стоїть прямо.
const SMOKE_LEAN_PER_WIND: float = 1.46
## Тепле світло вогню: радіус ~4 м, слабке — підсвічує уламки й землю довкола.
const FIRE_LIGHT_RANGE: float = 4.0 / 8.0
const FIRE_LIGHT_ENERGY: float = 0.8

## Ствол опущено на 8° (обгорілі уламки), корпус осів на 0,15 м.
const BARREL_DROP_DEG: float = 8.0
const HULL_SAG: float = 0.15 / 8.0

static var _burnt: ShaderMaterial
static var _column_shader: Shader
static var _fire_shader: Shader
static var _textures: Dictionary = {}

class _Entry:
	var node: Node3D
	var life: float

var _entries: Dictionary[Vector2i, _Entry] = {}
var _columns: MultiMeshInstance3D
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
	_column_mat.set_shader_parameter("puff_tex", _flipbook(SMOKE_TEX_PATH, false))
	_column_mat.set_shader_parameter("grid", float(FLIPBOOK_GRID))
	_column_mat.set_shader_parameter("height", COLUMN_HEIGHT)
	_column_mat.set_shader_parameter("base_w", COLUMN_BASE_W)
	_column_mat.set_shader_parameter("top_w", COLUMN_TOP_W)
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = fire_shader()
	# Вогонь — поверх диму власного стовпа, а не за ним.
	_fire_mat.render_priority = 1
	_fire_mat.set_shader_parameter("flame_tex", _flipbook(FIRE_TEX_PATH, true))
	_fire_mat.set_shader_parameter("grid", float(FLIPBOOK_GRID))
	_columns = _multimesh("Columns", _column_mat, MAX_COLUMNS * PUFFS_PER_COLUMN)
	_fires = _multimesh("Fires", _fire_mat, MAX_COLUMNS * MAX_FLAMES)
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
			_add_node(w.pos, w.type_id, life_of(state, w), w.facing)
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


static func flames_for(life: float) -> int:
	if life > 2.0 / 3.0:
		return MAX_FLAMES
	if life > 1.0 / 3.0 + 0.01:
		return 1
	return 0


func add(pos: Vector2i, type_id: int, life: float, facing: int = 0) -> void:
	if _entries.has(pos):
		return
	_add_node(pos, type_id, life, facing)
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
	for mi: MultiMeshInstance3D in [_columns, _fires]:
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
		# Лінійні кольори: вугіль L* ~8, іржа L* ~30 (a* 14, b* 20), попіл L* ~62.
		_burnt.set_shader_parameter("char_color", Color(0.010, 0.009, 0.008))
		_burnt.set_shader_parameter("rust_color", Color(0.12, 0.05, 0.027))
		_burnt.set_shader_parameter("ash_color", Color(0.30, 0.29, 0.28))
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
	for part: Node in root.get_children():
		var m := part as MeshInstance3D
		m.material_override = burnt_material()
		m.layers = 1 << (UnitView.UNIT_LAYER - 1)
		m.position.y -= HULL_SAG
		if m.name == "Barrel":
			m.rotation.x = -deg_to_rad(BARREL_DROP_DEG)
	var h: int = hash(pos)
	# Перекіс — довкола осей самого корпусу, після повороту: інакше нахил «їде» з напрямом.
	root.basis = Basis(Vector3.UP, deg_to_rad(UnitView._degrees_for_facing(facing))) \
		* Basis.from_euler(Vector3(deg_to_rad(float(h % 5 - 2)), 0.0, deg_to_rad(float((h >> 6) % 5 - 2))))
	root.position = IsoCameraRig.cell_to_world(pos)
	return root


func _add_node(pos: Vector2i, type_id: int, life: float, facing: int) -> void:
	var e := _Entry.new()
	e.node = build_wreck(pos, type_id, facing)
	e.life = life
	add_child(e.node)
	_entries[pos] = e


func _clear() -> void:
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
		for k in PUFFS_PER_COLUMN:
			var idx: int = i * PUFFS_PER_COLUMN + k
			mm.set_instance_transform(idx, Transform3D(Basis(), IsoCameraRig.cell_to_world(c)))
			mm.set_instance_custom_data(idx, Color(float(k) / float(PUFFS_PER_COLUMN), fposmod(seed + 0.618 * k, 1.0), opacity, 0.0))
	mm.visible_instance_count = _column_cells.size() * PUFFS_PER_COLUMN
	var fm: MultiMesh = _fires.multimesh
	var n: int = 0
	for c in _fire_cells:
		var base: Vector3 = IsoCameraRig.cell_to_world(c)
		for k in flames_for(_entries[c].life):
			var off := Vector3(0.09 * float(k % 2 * 2 - 1) * float(mini(k, 1)), 0.0, 0.07 * float(k - 1))
			fm.set_instance_transform(n, Transform3D(Basis(), base + off))
			fm.set_instance_custom_data(n, Color(FLAME_M[k] / 8.0, fposmod(float(hash(c) % 89) / 89.0 + 0.37 * k, 1.0), 1.0, 0.0))
			n += 1
	fm.visible_instance_count = n
	for i in _lights.size():
		_lights[i].visible = i < _fire_cells.size()
		if _lights[i].visible:
			_lights[i].position = IsoCameraRig.cell_to_world(_fire_cells[i]) + Vector3(0.0, 0.45, 0.0)
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
	_fire_mat.set_shader_parameter("fx_time", t)
	_fire_mat.set_shader_parameter("viewport_h", float(get_viewport().get_visible_rect().size.y))
	# Мерехтіння світла — з того самого кроку, без власного таймера.
	for i in _lights.size():
		_lights[i].light_energy = FIRE_LIGHT_ENERGY * (0.8 + 0.4 * absf(sin(t * 7.3 + i * 1.7)))


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


static func fire_shader() -> Shader:
	if _fire_shader == null:
		_fire_shader = Shader.new()
		_fire_shader.code = _FIRE_CODE
	return _fire_shader


## Флипбук із файла, інакше заступник тієї самої сітки 8×8 (FxPlaceholder).
static func _flipbook(path: String, fire: bool) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if not _textures.has(fire):
		_textures[fire] = ImageTexture.create_from_image(FxPlaceholder.fire_atlas() if fire else FxPlaceholder.smoke_atlas())
	return _textures[fire]


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

const _COLUMN_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Без міпмап і без розмиття: клуба на 7 см/px мусить читатись чіткою структурою.
uniform sampler2D puff_tex : source_color, filter_linear;
uniform float grid = 8.0;
// Час крокує таймером WreckLayer, 8 разів на секунду: вбудований час рушія тримав би кадр щокадрово.
uniform float fx_time = 0.0;
// Кадрів флипбука на секунду; між кадрами — змішування, тож 4 кадри/с при кроці 8/с не смикаються.
uniform float play_fps = 4.0;
uniform float height = 3.0;
uniform float base_w = 0.4;
uniform float top_w = 1.0;
uniform vec3 lean = vec3(0.0);
uniform float rise = 0.06;
// Лінійні: густе ядро L* 12–18, теплий світлий край L* 45–55 (b* +12), верх L* 35–45.
uniform vec3 core = vec3(0.020, 0.019, 0.018);
uniform vec3 rim = vec3(0.215, 0.180, 0.140);
uniform vec3 top = vec3(0.110, 0.110, 0.115);
// Твердий край клуби: вузька смуга альфи замість м'якого спаду.
uniform vec2 alpha_edge = vec2(0.42, 0.58);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї (1,2 м) лише там, де квад врізається в землю чи уламки.
uniform float soft_fade = 0.15;

varying float v_alpha;
varying float v_frame;
varying float v_t;

void vertex() {
	// INSTANCE_CUSTOM: x — місце клуби в стовпі, y — власний початковий кадр, z — густота стадії.
	float t = fract(INSTANCE_CUSTOM.x + fx_time * rise);
	vec3 root = MODEL_MATRIX[3].xyz;
	float w = mix(base_w, top_w, t);
	float jig = (INSTANCE_CUSTOM.y - 0.5) * 0.15 * w;
	// Від даху корпусу, а не від землі: інакше густа основа ховає вогонь.
	vec3 c = root + vec3(0.0, t * height + 0.38, 0.0) + lean * t * height;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	c += right * jig;
	vec3 world = c + (right * VERTEX.x + up * VERTEX.y) * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	// Густий нижче 60 % висоти, далі тоншає до ≤ 0,35 і зникає до верху.
	float dens = mix(0.95, 0.3, smoothstep(0.6, 0.85, t)) * (1.0 - smoothstep(0.9, 1.0, t));
	v_alpha = INSTANCE_CUSTOM.z * dens * smoothstep(0.0, 0.06, t);
	v_frame = fx_time * play_fps + INSTANCE_CUSTOM.y * grid * grid;
	v_t = t;
}

vec4 frame_at(float f, vec2 uv) {
	float n = mod(f, grid * grid);
	return texture(puff_tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid), floor(n / grid))) / grid);
}

void fragment() {
	vec4 tex = mix(frame_at(floor(v_frame), UV), frame_at(floor(v_frame) + 1.0, UV), fract(v_frame));
	float a = smoothstep(alpha_edge.x, alpha_edge.y, tex.a);
	// Освітлення — із самого кадру (яскравість): ядро темне, освітлений бік клуби теплий.
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(core, top, smoothstep(0.45, 0.9, v_t)) * (0.55 + 0.9 * lum);
	col = mix(col, rim, smoothstep(0.85, 1.0, lum) * 0.45 * (1.0 - smoothstep(0.6, 0.9, v_t)));
	ALBEDO = col;
	ALPHA = a * v_alpha;
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""

const _FIRE_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D flame_tex : source_color, filter_linear;
uniform float grid = 8.0;
// Той самий крок таймера, що й у диму; полум'я грає швидше.
uniform float fx_time = 0.0;
uniform float play_fps = 8.0;
// Колір несе сам кадр (серце #FFD9A0 → край #E0702A); понад 1 — найяскравіше на екрані.
uniform float gain = 2.2;
uniform vec2 alpha_edge = vec2(0.42, 0.58);
// На далекому зумі язик не дрібніший за 6 px: інакше вогонь зникає, а дим без нього бреше.
uniform float min_px = 6.0;
// Висота кадру в пікселях: VIEWPORT_SIZE у вершинному шейдері тут нульовий, тож її дає WreckLayer.
uniform float viewport_h = 1080.0;

varying float v_frame;

void vertex() {
	float w = INSTANCE_CUSTOM.x;
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 c = root + vec3(0.0, w * 0.45 + 0.5, 0.0);
	vec4 p0 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(c, 1.0);
	vec4 p1 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(c + INV_VIEW_MATRIX[1].xyz * w, 1.0);
	float px = length(p1.xy / p1.w - p0.xy / p0.w) * viewport_h * 0.5;
	w *= clamp(min_px / max(px, 0.001), 1.0, 8.0);
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_frame = fx_time * play_fps + INSTANCE_CUSTOM.y * grid * grid;
}

vec4 frame_at(float f, vec2 uv) {
	float n = mod(f, grid * grid);
	return texture(flame_tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid), floor(n / grid))) / grid);
}

void fragment() {
	vec4 tex = mix(frame_at(floor(v_frame), UV), frame_at(floor(v_frame) + 1.0, UV), fract(v_frame));
	ALBEDO = tex.rgb * gain;
	ALPHA = smoothstep(alpha_edge.x, alpha_edge.y, tex.a);
}
"""
