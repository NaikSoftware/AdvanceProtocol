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
## Знос вітром на одиницю падіння — уздовж правої осі кадру, тож усі штрихи нахилені в один бік.
const RAIN_SLANT: float = 0.25
## Витримка, секунд: штрих — шлях краплі за цей час, у світі. Відношення довжини штриха до
## його швидкості на екрані — саме витримка, на будь-якому зумі.
const RAIN_EXPOSURE: float = 0.045
## Крапля з'являється в новому місці раз на `RAIN_CYCLE` і видима лише `RAIN_LIFE`, секунд.
const RAIN_CYCLE: float = 1.0
const RAIN_LIFE: float = 0.2

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
	var v: Vector3 = rain_velocity()
	rain_mat.set_shader_parameter("fall_speed", -v.y)
	rain_mat.set_shader_parameter("wind", Vector2(v.x, v.z))
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
	_light_probe()
	var sky_mat := environment.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("clear_amount", look.sky_clear)
	rain.visible = look.rain and look.rain_amount > 0
	if rain.visible and look.rain_amount != _rain_drops:
		rain.mesh = _drops_mesh(look.rain_amount)
		_rain_drops = look.rain_amount
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


## Коробка дощу стоїть на фокусі камери й росте з віддаленням: густота на екрані та сама на
## будь-якому зумі.
func follow(focus: Vector3, zoom_level: float) -> void:
	var mat := rain.material_override as ShaderMaterial
	mat.set_shader_parameter("focus", Vector3(focus.x, 0.0, focus.z))
	mat.set_shader_parameter("box_size", RAIN_BOX * zoom_level)


## Швидкість краплі у світі, клітинок/с. Права вісь кадру — (1, 0, -1): камера під
## `IsoCameraRig.YAW_DEGREES` і не обертається.
static func rain_velocity() -> Vector3:
	var right := Vector3(1.0, 0.0, -1.0).normalized()
	return Vector3.DOWN * RAIN_FALL + right * RAIN_FALL * RAIN_SLANT


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _set_global(param: StringName, value: Variant) -> void:
	applied_globals[param] = value
	RenderingServer.global_shader_parameter_set(param, value)


## Квад на краплю: усі чотири вершини несуть ту саму випадкову точку одиничної коробки, а UV —
## кут квада; смугу будує шейдер. Сід сталий, тож дощ однаковий від запуску до запуску.
static func _drops_mesh(count: int) -> ArrayMesh:
	if _drops_cache.has(count):
		return _drops_cache[count]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(count * 4)
	uvs.resize(count * 4)
	idx.resize(count * 6)
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in count:
		var seed := Vector3(rng.randf(), rng.randf(), rng.randf())
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
	_drops_cache[count] = mesh
	return mesh
