extends GutTest
## Phase 5a, Task 6 (раніше Task 10): похмуре небо з хмарами. Шейдер неба GUT не
## компілює, тож перевіряється оточення, яке отримує сцена.

func test_sky_rig_gives_an_overcast_shader_sky_with_sky_ambient() -> void:
	var rig := SkyRig.new()
	add_child_autofree(rig)
	var env: Environment = rig.environment
	assert_not_null(env)
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_not_null(env.sky)
	var mat := env.sky.sky_material as ShaderMaterial
	assert_not_null(mat, "небо — шейдер, не процедурне блакитне")
	assert_eq(mat.shader.resource_path, "res://game/battle/shaders/overcast_sky.gdshader")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_SKY)
	assert_eq(env.reflected_light_source, Environment.REFLECTION_SOURCE_SKY)
	assert_between(env.ambient_light_energy, 0.2, 1.0, "помірно, щоб земля не вицвіла")
	# Туман, дощ і пресети світла — Task 10, не тут.
	assert_false(env.fog_enabled)


func test_battle_screen_has_one_sky_rig() -> void:
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	assert_eq(screen.find_children("*", "WorldEnvironment", true, false).size(), 1)
	assert_true(screen.get_node("SkyRig") is SkyRig)
