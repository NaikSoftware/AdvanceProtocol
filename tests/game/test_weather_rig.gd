extends GutTest
## Небо, світло й погода бою. Шейдери GUT не компілює, тож перевіряються оточення, світло й
## частинки, які отримує сцена. Погода й час доби — суто вигляд (§3.12).

const MAPS: Array[String] = ["res://maps/river.tres", "res://maps/crossroads.tres",
		"res://maps/ridge.tres"]


func _rig() -> WeatherRig:
	var rig := WeatherRig.new()
	add_child_autofree(rig)
	return rig


func test_weather_rig_gives_an_overcast_shader_sky_with_sky_ambient() -> void:
	var env: Environment = _rig().environment
	assert_not_null(env)
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_not_null(env.sky)
	var mat := env.sky.sky_material as ShaderMaterial
	assert_not_null(mat, "небо — шейдер, не процедурне блакитне")
	assert_eq(mat.shader.resource_path, "res://game/battle/shaders/overcast_sky.gdshader")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_SKY)
	assert_eq(env.reflected_light_source, Environment.REFLECTION_SOURCE_SKY)
	# Земля пише власний FOG, тож туман оточення сірив би лише юніти над чіткою землею.
	assert_false(env.fog_enabled)


func test_battle_screen_has_one_weather_rig_and_one_sun_with_shadows() -> void:
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	assert_eq(screen.find_children("*", "WorldEnvironment", true, false).size(), 1)
	assert_true(screen.get_node("WeatherRig") is WeatherRig)
	var suns: Array[Node] = screen.find_children("*", "DirectionalLight3D", true, false)
	assert_eq(suns.size(), 1, "§8: одне напрямлене світло")
	assert_true((suns[0] as DirectionalLight3D).shadow_enabled)


func test_river_rains_and_the_other_maps_stay_dry() -> void:
	assert_true(BattleLook.for_map_path("res://maps/river.tres").rain)
	for path: String in ["res://maps/crossroads.tres", "res://maps/ridge.tres", ""]:
		var look: BattleLook = BattleLook.for_map_path(path)
		assert_false(look.rain, path)
		assert_eq(look.wetness, 0.0, path)


## Дощ чи мокра земля на карті з ґрунтом «сухо» суперечили б значку ґрунту в HUD (§3.12).
func test_only_a_map_whose_ground_is_not_dry_looks_wet() -> void:
	for path: String in MAPS:
		var look: BattleLook = BattleLook.for_map_path(path)
		if (load(path) as MapData).ground_state == Terrain.GroundState.DRY:
			assert_false(look.rain, path)
			assert_eq(look.wetness, 0.0, path)


func test_each_map_has_its_own_light() -> void:
	var seen: Dictionary = {}
	for path: String in MAPS:
		var look: BattleLook = BattleLook.for_map_path(path)
		seen[[look.light_color, look.light_pitch_deg, look.light_yaw_deg]] = path
	assert_eq(seen.size(), MAPS.size())


func test_apply_sets_the_sun_from_the_look() -> void:
	var rig: WeatherRig = _rig()
	var look: BattleLook = BattleLook.for_map_path("res://maps/ridge.tres")
	rig.apply(look)
	assert_eq(rig.sun.light_color, look.light_color)
	assert_almost_eq(rig.sun.light_energy, look.light_energy, 1e-5)
	assert_almost_eq(rig.sun.rotation_degrees.x, -look.light_pitch_deg, 1e-3)
	assert_almost_eq(rig.sun.rotation_degrees.y, look.light_yaw_deg, 1e-3)
	assert_true(rig.sun.shadow_enabled)
	assert_almost_eq(rig.environment.ambient_light_energy, look.ambient_energy, 1e-5)


func test_apply_turns_rain_and_wetness_on_and_off() -> void:
	var rig: WeatherRig = _rig()
	var wet: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	rig.apply(wet)
	assert_true(rig.rain.visible)
	assert_eq(rig.rain_drops(), wet.rain_amount)
	assert_almost_eq(rig.applied_globals[&"weather_wetness"], wet.wetness, 1e-5)
	assert_almost_eq(rig.applied_globals[&"cloud_shadow_strength"], wet.cloud_shadow_strength, 1e-5)
	rig.apply(BattleLook.for_map_path("res://maps/crossroads.tres"))
	assert_false(rig.rain.visible)
	assert_eq(rig.rain_drops(), 0)
	assert_eq(rig.applied_globals[&"weather_wetness"], 0.0)


## Дощ — коробка довкола фокуса камери, завбільшки з кадр: густота на екрані та сама на
## будь-якому віддаленні, а краплі не витрачаються на невидиму частину дошки.
func test_rain_follows_the_camera_focus_and_frame() -> void:
	var rig: WeatherRig = _rig()
	var mat := rig.rain.material_override as ShaderMaterial
	rig.follow(Vector3(5.0, 0.0, 7.0), 6.0)
	assert_eq(mat.get_shader_parameter("focus"), Vector3(5.0, 0.0, 7.0))
	var near: Vector3 = mat.get_shader_parameter("box_size")
	rig.follow(Vector3(5.0, 0.0, 7.0), 18.0)
	var far: Vector3 = mat.get_shader_parameter("box_size")
	assert_almost_eq(far, near * 3.0, Vector3.ONE * 1e-3)


## §3.12: вигляд не тримає жодного числа правил.
func test_a_look_has_no_rule_fields() -> void:
	var banned: Array[String] = ["vision", "range", "ap", "cost", "damage", "penalty", "hp",
			"armour", "armor", "ground", "mud"]
	for prop: Dictionary in BattleLook.new().get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		for token: String in String(prop.name).split("_"):
			assert_false(token in banned, "поле %s схоже на правило" % prop.name)


func test_battle_screen_applies_the_look_of_its_map() -> void:
	var service: Node = (load("res://game/autoload/match_service.gd") as GDScript).new()
	add_child_autofree(service)
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.setup(load("res://maps/river.tres") as MapData, 2, 1, service)
	var rig: WeatherRig = screen.get_node("WeatherRig")
	assert_true(rig.rain.visible)
	assert_almost_eq(rig.applied_globals[&"weather_wetness"],
			BattleLook.for_map_path("res://maps/river.tres").wetness, 1e-5)
