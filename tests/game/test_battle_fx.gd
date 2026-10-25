extends GutTest
## Вогняна куля знищеної техніки: спалах 3–5 м на 0,06–0,1 с зі світлом, далі куля,
## що накриває корпус, і самозвільнення ≤ 1,5 с.

var parent: Node3D


func before_each() -> void:
	parent = Node3D.new()
	add_child_autofree(parent)


func _step_all(sec: float) -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(sec)


func test_flash_is_a_four_metre_sprite_that_lasts_under_a_tenth_of_a_second() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var flash := boom.get_node("Flash") as MeshInstance3D
	assert_eq((flash.mesh as QuadMesh).size, Vector2.ONE * BattleFx.FLASH_M / 8.0)
	assert_true(BattleFx.FLASH_M >= 3.0 and BattleFx.FLASH_M <= 5.0)
	assert_true(BattleFx.FLASH_SEC >= 0.06 and BattleFx.FLASH_SEC <= 0.1)
	assert_true(flash.visible)
	_step_all(BattleFx.FLASH_SEC + 0.001)
	assert_false(flash.visible, "спалах — кілька кадрів, не біла коробка на всю кулю")
	assert_eq((boom.get_node("Light") as OmniLight3D).light_energy, 0.0)


## Куля стоїть на корпусі й починається ~2 м над землею, а не лежить на траві поруч.
func test_fireball_is_centred_on_the_hull_two_metres_up() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var mat := (boom.get_node("Ball") as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("lift"), 2.0 / 8.0)
	assert_eq(boom.position, Vector3(2, 0, 3))


func test_explosion_frees_itself_within_one_and_a_half_seconds() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	_step_all(BattleFx.EXPLOSION_SEC + 0.01)
	assert_true(boom.is_queued_for_deletion())
	assert_true(BattleFx.EXPLOSION_SEC <= 1.5)
