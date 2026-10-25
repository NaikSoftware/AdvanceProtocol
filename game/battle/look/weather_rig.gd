class_name WeatherRig
extends WorldEnvironment
## Небо, сонце й дощ бою за вигляд карти (`BattleLook`). Камера неба майже не бачить — його
## видно у воді й калюжах і як розсіяне світло. Туман оточення вимкнено: земля й вода пишуть
## власний FOG (імла кільця, `Surroundings`), тож туман оточення сірив би лише юніти над
## чіткою землею.

const _SKY_SHADER: Shader = preload("res://game/battle/shaders/overcast_sky.gdshader")
const _RAIN_SHADER: Shader = preload("res://game/battle/shaders/rain.gdshader")

## Коробка дощу на одиницю `zoom_level` (висоти кадру в площині фокуса): уширшки й углиб —
## кадр 20:9 разом із дальньою землею вгорі кадру; заввишки — майже до камери, бо видимий дощ
## — це передусім краплі ближче до неї.
const RAIN_BOX: Vector3 = Vector3(2.0, 0.85, 2.0)
## Дальній від камери кут коробки — на стільки `zoom_level` від фокуса по x і z: там верх кадру.
## Ближчий до камери бік коробки в кадр не потрапляє, тож коробка закінчується до нього.
const RAIN_FAR: float = 1.0242
## Падіння на найменшому віддаленні, клітинок/с. Дощ у кадрі — це передусім краплі біля
## об'єктива, і їхній розмір та швидкість на екрані не залежать від того, як далеко земля. Тож
## падіння росте з віддаленням як (зум / 6)^`RAIN_FALL_ZOOM_POW` — так само, як меншає клітинка
## на екрані, — і штрих на будь-якому зумі пролітає кадр з тією самою швидкістю (~600 px/с) і
## має ту саму довжину (~20 px). Справжні 8 м/с при сталій витримці давали на далекому зумі
## крапки по 1–2 px, що читалися камінцями.
const RAIN_FALL: float = 5.6
const RAIN_FALL_ZOOM_POW: float = 1.28
## Вісь вітру — права вісь кадру (1, 0, -1): камера під `IsoCameraRig.YAW_DEGREES` і не
## обертається, тож усі штрихи дощу й стовпи диму нахилені в один бік. Сила — `BattleLook.wind`.
const WIND_AXIS: Vector3 = Vector3(0.70710678, 0.0, -0.70710678)
## Витримка, секунд: штрих — шлях краплі за цей час, у світі. Відношення довжини штриха до
## його швидкості на екрані — саме витримка, на будь-якому зумі, тож штрих не стає «палицею».
const RAIN_EXPOSURE: float = 0.033
## Крапля з'являється в новому місці раз на `RAIN_CYCLE` і видима лише `RAIN_LIFE`, секунд:
## вісім десятих крапель, що малюються, видимі водночас.
const RAIN_CYCLE: float = 0.25
const RAIN_LIFE: float = 0.2
## Шарів решітки крапель по висоті; по ширині й углиб квадів стільки, щоб разом вийшла
## кількість крапель вигляду.
const RAIN_LAYERS: int = 8

## Пріоритет матеріалу дощу серед прозорих: понад воду (0), щоб дощ над річкою не зникав.
const RAIN_PRIORITY: int = 1
const _QUAD: Array[int] = [0, 1, 2, 0, 2, 3]

var sun: DirectionalLight3D
var rain: MeshInstance3D
## Зонд відбиття дошки (`attach_probe`): у його коробці розсіяне світло бере він, а не
## оточення, тож вигляд ставить світло і йому.
var probe: ReflectionProbe
var _look: BattleLook
## Останні значення глобальних uniform: без відеокарти RenderingServer їх не повертає.
var applied_globals: Dictionary = {}
## Скільки крапель у збудованому меші — не те саме, що дощ, який іде (`rain_drops()`).
var _rain_drops: int = 0
## Квадів решітки по осях (x, висота, z); нуль — меша ще нема.
var _rain_grid: Vector3 = Vector3.ZERO
## Кількість крапель, яку просив вигляд: з нею порівнюємо, щоб не будувати меш наново, коли
## вона не ділиться націло на решітку.
var _rain_requested: int = 0
var _focus: Vector3 = Vector3.ZERO
var _zoom: float = IsoCameraRig.MAX_ZOOM
## Меш крапель на кількість: однаковий для всіх боїв процесу, будується раз.
static var _drops_cache: Dictionary = {}


func _init() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = mat
	# Небо статичне, тож радіанс рахується раз; 64 — досить для похмурого купола.
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Розсіяне світло — колір вигляду, а не небо: на дошці його однаково дає зонд кольором
	# (`attach_probe`), і небо ззовні дало б інший тон на кільці.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment = env

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	# Дальні каскади тіні мають меншу роздільність і м'якший край; змішування між ними прибирає
	# видимий шов: тінь чітка зблизька й трохи м'якша здалеку.
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	rain = MeshInstance3D.new()
	rain.name = "Rain"
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rain_mat := ShaderMaterial.new()
	rain_mat.shader = _RAIN_SHADER
	# Вода теж прозора й без запису глибини: прозорі сортуються за центром AABB, а центр меша
	# дощу — початок координат, тож без пріоритету вода залежно від пана малювалась би поверх.
	rain_mat.render_priority = RAIN_PRIORITY
	rain.material_override = rain_mat
	rain_mat.set_shader_parameter("exposure", RAIN_EXPOSURE)
	rain_mat.set_shader_parameter("cycle", RAIN_CYCLE)
	rain_mat.set_shader_parameter("life", RAIN_LIFE)
	add_child(rain)
	follow(Vector3.ZERO, IsoCameraRig.MAX_ZOOM)
	apply(BattleLook.new())


func apply(look: BattleLook) -> void:
	sun.light_color = look.light_color
	sun.light_energy = look.light_energy
	sun.rotation_degrees = Vector3(-look.light_pitch_deg, look.light_yaw_deg, 0.0)
	sun.shadow_opacity = look.shadow_opacity
	sun.shadow_blur = look.shadow_blur
	sun.light_angular_distance = look.sun_angular_deg
	environment.ambient_light_color = look.ambient_color
	environment.ambient_light_energy = look.ambient_energy
	_look = look
	_set_rain_motion()
	_light_probe()
	var sky_mat := environment.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("clear_amount", look.sky_clear)
	rain.visible = look.rain and look.rain_amount > 0
	if rain.visible and look.rain_amount != _rain_requested:
		var side: int = rain_side(look.rain_amount)
		rain.mesh = _drops_mesh(side)
		_rain_grid = Vector3(side, RAIN_LAYERS, side)
		_rain_drops = side * side * RAIN_LAYERS
		_rain_requested = look.rain_amount
		var mat := rain.material_override as ShaderMaterial
		mat.set_shader_parameter("grid", _rain_grid)
		mat.set_shader_parameter("cell", rain_cell(_rain_grid))
		_place_rain()
	_set_global(&"weather_wetness", look.wetness)
	_set_global(&"cloud_shadow_strength", look.cloud_shadow_strength)
	_set_global(&"sky_clear", look.sky_clear)
	_set_global(&"water_murk", look.water_murk)
	_set_global(&"water_wind", look.water_wind)
	_set_global(&"unit_contact_shadow", look.unit_contact_shadow)
	# Світло падає вздовж -Z сонця, тож напрям НА сонце — його +Z.
	_set_global(&"sun_dir", sun.basis.z)
	_set_global(&"haze_color", _rgb(look.haze_color))
	_set_global(&"foliage_tint", _rgb(look.foliage_tint))


## Зонд відбиття дошки з'являється, коли дошку збудовано. У його коробці Mobile бере розсіяне
## світло з самого зонда й `ambient_light_energy` оточення не чує, тож вигляд ставить зонду той
## самий колір, що й оточенню.
func attach_probe(board_probe: ReflectionProbe) -> void:
	probe = board_probe
	_light_probe()


func _light_probe() -> void:
	if probe == null or _look == null:
		return
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = _look.ambient_color
	probe.ambient_color_energy = _look.ambient_energy


## Кількість крапель у меші дощу, що зараз іде (0 — дощу нема); скільки з них малюється,
## вирішує `rain_lattice`.
func rain_drops() -> int:
	return _rain_drops if rain.visible else 0


## Дощ іде там, куди дивиться камера: решітка квадів стає над світовими клітинками довкола
## фокуса, а з віддаленням малюється менша частка клітинок, тож густота на екрані та сама на
## будь-якому зумі.
func follow(focus: Vector3, zoom_level: float) -> void:
	_focus = focus
	_zoom = zoom_level
	_place_rain()


## Ребро решітки по ширині для кількості крапель: `side² × RAIN_LAYERS` найближче до неї.
static func rain_side(count: int) -> int:
	return maxi(1, roundi(sqrt(float(count) / RAIN_LAYERS)))


## Розмір світової клітинки дощу, клітинок дошки: на найменшому віддаленні решітка з кроком 1
## саме вкриває коробку. Від фокуса й зуму не залежить — інакше краплі зсувались би у світі.
static func rain_cell(grid: Vector3) -> Vector3:
	return RAIN_BOX * IsoCameraRig.MIN_ZOOM / grid


## Коробка дощу на цьому зумі: нижній кут і розмір, клітинки дошки. Дальній від камери кут —
## `RAIN_FAR` зумів від фокуса; звідти коробка йде до камери на `RAIN_BOX` зумів.
static func rain_box(focus: Vector3, zoom_level: float) -> AABB:
	var lo := Vector3(focus.x - RAIN_FAR * zoom_level, 0.0, focus.z - RAIN_FAR * zoom_level)
	return AABB(lo, RAIN_BOX * zoom_level)


## Решітка для фокуса й зуму: крок (у клітинках), світовий номер кутової клітинки й `keep` —
## поріг рангу клітинок, що малюються.
##
## Крок — степінь двійки, найменший, з яким решітка вкриває коробку із запасом в одну клітинку
## (кут прилипає до цілої клітинки й може відстати від коробки на крок). Кут — ціле кратне кроку,
## тож пан зсуває решітку лише на цілі клітинки. `keep` тримає сталою кількість клітинок, що
## малюються в коробці: ((G-1)/G)³/8 усієї решітки за густотою найменшого віддалення. Він ≤
## 8^-log2(крок), тож усі такі клітинки кратні кроку й решітка їх має — на порозі кроку видиме не
## міняється.
static func rain_lattice(focus: Vector3, zoom_level: float, grid: Vector3) -> Dictionary:
	var cell: Vector3 = rain_cell(grid)
	var box: AABB = rain_box(focus, zoom_level)
	var stride: int = 1
	while stride < 32 and ((grid.x - 1.0) * cell.x * stride < box.size.x
			or (grid.z - 1.0) * cell.z * stride < box.size.z
			or grid.y * cell.y * stride < box.size.y):
		stride *= 2
	var origin := Vector3(floorf(box.position.x / (cell.x * stride)) * stride, 0.0,
			floorf(box.position.z / (cell.z * stride)) * stride)
	var margin: float = (grid.x - 1.0) / grid.x
	var keep: float = margin * margin * margin / 8.0 * pow(IsoCameraRig.MIN_ZOOM / zoom_level, 3.0)
	return {"cell": cell, "stride": stride, "origin": origin, "keep": keep}


## Ранг світової клітинки — дзеркало `rain_rank` у rain.gdshader (тести рахують за ним, які
## краплі малюються).
static func rain_rank(wc: Vector3) -> float:
	var lvl: int = 0
	for i in range(1, 6):
		var m: float = pow(2.0, i)
		if fposmod(wc.x, m) != 0.0 or fposmod(wc.y, m) != 0.0 or fposmod(wc.z, m) != 0.0:
			break
		lvl = i
	var u: float = rain_hash3(wc)
	if lvl >= 5:
		return u * pow(8.0, -5.0)
	return pow(8.0, -(lvl + 1.0)) * (1.0 + 7.0 * u)


## Дзеркало `rain_hash3` у rain.gdshader.
static func rain_hash3(p: Vector3) -> float:
	var p3: Vector3 = p * 0.1031
	p3 -= p3.floor()
	p3 += Vector3.ONE * p3.dot(Vector3(p3.z, p3.y, p3.x) + Vector3.ONE * 31.32)
	var v: float = (p3.x + p3.y) * p3.z
	return v - floorf(v)


func _place_rain() -> void:
	# Падіння залежить від зуму, тож оновлюється й без меша.
	_set_rain_motion()
	if _rain_grid == Vector3.ZERO:
		return
	var lat: Dictionary = rain_lattice(_focus, _zoom, _rain_grid)
	var mat := rain.material_override as ShaderMaterial
	mat.set_shader_parameter("stride", float(lat.stride))
	mat.set_shader_parameter("cell_origin", lat.origin)
	mat.set_shader_parameter("keep", lat.keep)


## Горизонтальний вітер вигляду: знос на одиницю падіння. Його читають і дощ, і дим.
func wind() -> Vector3:
	return WIND_AXIS * (_look.wind if _look != null else 0.0)


## Падіння краплі на цьому зумі, клітинок/с (див. `RAIN_FALL`).
static func rain_fall(zoom_level: float) -> float:
	return RAIN_FALL * pow(zoom_level / IsoCameraRig.MIN_ZOOM, RAIN_FALL_ZOOM_POW)


## Швидкість краплі у світі на поточному зумі камери, клітинок/с.
func rain_velocity() -> Vector3:
	var fall: float = rain_fall(_zoom)
	return Vector3.DOWN * fall + wind() * fall


func _set_rain_motion() -> void:
	var v: Vector3 = rain_velocity()
	var mat := rain.material_override as ShaderMaterial
	mat.set_shader_parameter("fall_speed", -v.y)
	mat.set_shader_parameter("wind", Vector2(v.x, v.z))


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _set_global(param: StringName, value: Variant) -> void:
	applied_globals[param] = value
	RenderingServer.global_shader_parameter_set(param, value)


## Квад на краплю, сіткою `side × RAIN_LAYERS × side`: усі чотири вершини несуть центр своєї
## клітинки сітки в одиничній коробці, а UV — кут квада; штрих будує шейдер.
static func _drops_mesh(side: int) -> ArrayMesh:
	if _drops_cache.has(side):
		return _drops_cache[side]
	var count: int = side * side * RAIN_LAYERS
	var grid := Vector3(side, RAIN_LAYERS, side)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(count * 4)
	uvs.resize(count * 4)
	idx.resize(count * 6)
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in count:
		var g := Vector3(i % side, (i / side) % RAIN_LAYERS, i / (side * RAIN_LAYERS))
		var seed: Vector3 = (g + Vector3(0.5, 0.5, 0.5)) / grid
		for k in 4:
			verts[i * 4 + k] = seed
			uvs[i * 4 + k] = corners[k]
		var b: int = i * 4
		for k in 6:
			idx[i * 6 + k] = b + _QUAD[k]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Вершини лежать в одиничній коробці, а краплі — будь-де довкола камери: без власної межі
	# меш відсікався б, щойно фокус відійде від початку координат.
	mesh.custom_aabb = AABB(Vector3(-1e4, -1e3, -1e4), Vector3(2e4, 2e3, 2e4))
	_drops_cache[side] = mesh
	return mesh
