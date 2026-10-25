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
const RAIN_BOX: Vector3 = Vector3(2.6, 0.85, 2.6)
## Падіння, клітинок/с (28 м/с). Справжні 8 м/с з висоти камери дають штрихи в 1–5 px, що
## читаються крапками; швидший дощ з тією самою витримкою виглядає так, як справжній зблизька.
const RAIN_FALL: float = 3.5
## Вісь вітру — права вісь кадру (1, 0, -1): камера під `IsoCameraRig.YAW_DEGREES` і не
## обертається, тож усі штрихи дощу й стовпи диму нахилені в один бік. Сила — `BattleLook.wind`.
const WIND_AXIS: Vector3 = Vector3(0.70710678, 0.0, -0.70710678)
## Витримка, секунд: штрих — шлях краплі за цей час, у світі. Відношення довжини штриха до
## його швидкості на екрані — саме витримка, на будь-якому зумі.
const RAIN_EXPOSURE: float = 0.045
## Крапля з'являється в новому місці раз на `RAIN_CYCLE` і видима лише `RAIN_LIFE`, секунд:
## третина крапель видима водночас.
const RAIN_CYCLE: float = 0.6
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
	environment.ambient_light_color = look.ambient_color
	environment.ambient_light_energy = look.ambient_energy
	_look = look
	var v: Vector3 = rain_velocity()
	var rain_mat := rain.material_override as ShaderMaterial
	rain_mat.set_shader_parameter("fall_speed", -v.y)
	rain_mat.set_shader_parameter("wind", Vector2(v.x, v.z))
	_light_probe()
	var sky_mat := environment.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("clear_amount", look.sky_clear)
	rain.visible = look.rain and look.rain_amount > 0
	if rain.visible and look.rain_amount != _rain_drops:
		var side: int = rain_side(look.rain_amount)
		rain.mesh = _drops_mesh(side)
		_rain_grid = Vector3(side, RAIN_LAYERS, side)
		_rain_drops = side * side * RAIN_LAYERS
		_place_rain()
	_set_global(&"weather_wetness", look.wetness)
	_set_global(&"cloud_shadow_strength", look.cloud_shadow_strength)
	_set_global(&"sky_clear", look.sky_clear)
	_set_global(&"water_murk", look.water_murk)
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


## Кількість крапель у дощі, що зараз іде (0 — дощу нема).
func rain_drops() -> int:
	return _rain_drops if rain.visible else 0


## Дощ іде там, куди дивиться камера: решітка квадів стає над світовими клітинками довкола
## фокуса й рідшає з віддаленням, тож густота на екрані та сама на будь-якому зумі.
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


## Крок решітки (у клітинках) і світовий номер кутової клітинки для фокуса й зуму. Крок — степінь
## двійки, найменший, з яким решітка вкриває коробку на цьому зумі: кожна крапля рідшої решітки —
## та сама крапля густішої. Кут — ціле кратне кроку, тож пан зсуває решітку лише на цілі клітинки.
static func rain_lattice(focus: Vector3, zoom_level: float, grid: Vector3) -> Dictionary:
	var cell: Vector3 = rain_cell(grid)
	var need: Vector3 = RAIN_BOX * zoom_level
	var stride: int = 1
	while stride < 64 and (grid.x * cell.x * stride < need.x - 1e-4
			or grid.y * cell.y * stride < need.y - 1e-4):
		stride *= 2
	var span: Vector3 = grid * cell * stride
	# Коробка трохи зсунута до камери: там у кадрі ближча земля й вища частина шару.
	var toward := Vector3(1.0, 0.0, 1.0).normalized()
	var lo: Vector3 = Vector3(focus.x, 0.0, focus.z) - Vector3(span.x, 0.0, span.z) * 0.5 \
			+ toward * span.x * 0.15
	var origin := Vector3(floorf(lo.x / (cell.x * stride)) * stride, 0.0,
			floorf(lo.z / (cell.z * stride)) * stride)
	return {"cell": cell, "stride": stride, "origin": origin}


func _place_rain() -> void:
	if _rain_grid == Vector3.ZERO:
		return
	var lat: Dictionary = rain_lattice(_focus, _zoom, _rain_grid)
	var mat := rain.material_override as ShaderMaterial
	mat.set_shader_parameter("grid", _rain_grid)
	mat.set_shader_parameter("cell", lat.cell)
	mat.set_shader_parameter("stride", float(lat.stride))
	mat.set_shader_parameter("cell_origin", lat.origin)


## Горизонтальний вітер вигляду: знос на одиницю падіння. Його читають і дощ, і дим.
func wind() -> Vector3:
	return WIND_AXIS * (_look.wind if _look != null else 0.0)


## Швидкість краплі у світі, клітинок/с.
func rain_velocity() -> Vector3:
	return Vector3.DOWN * RAIN_FALL + wind() * RAIN_FALL


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
