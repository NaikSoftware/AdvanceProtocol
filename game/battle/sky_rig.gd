class_name SkyRig
extends WorldEnvironment
## Похмуре небо з хмарами (Phase 5a; WeatherRig з Task 10 перейме цей вузол).
## Камера неба майже не бачить — його видно у воді й калюжах і як розсіяне світло.
## Без туману, дощу й пресетів світла: це Task 10.

const _SKY_SHADER: Shader = preload("res://game/battle/shaders/overcast_sky.gdshader")


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
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment = env
