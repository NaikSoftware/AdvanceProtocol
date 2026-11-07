extends GutTest
## Миті повалення опор і парканів: удар і падіння стають у групу митей (їх прибирає передача ходу),
## звільняють себе самі й тримаються бюджету телефона — ≤ 6 викликів малювання і ≤ 80 частинок
## на виклик, бо за один хід танк може зачепити ряд паркану й лінію опор.

var parent: Node3D


func before_each() -> void:
	parent = Node3D.new()
	add_child_autofree(parent)


func _step_all(sec: float) -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(sec)


func _moments() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var at := Vector3(3, 0, 4)
	for d: int in BattleFx.Debris.values():
		for live: bool in [false, true]:
			# Опора (верх на 10 м) і паркан (верх на 1,8 м).
			out.append(BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 10.0 / 8.0, 0), d, live))
			out.append(BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 1.8 / 8.0, 0), d, live))
			out.append(BattleFx.spawn_topple_land(parent, at, at + Vector3(10.0 / 8.0, 0, 0.3), d, live))
			out.append(BattleFx.spawn_topple_land(parent, at, at + Vector3(2.0 / 8.0, 0, 0), d, live))
	return out


func test_moments_join_the_group_and_free_themselves() -> void:
	var all: Array[Node3D] = _moments()
	for m: Node3D in all:
		assert_true(m.is_in_group(BattleFx.GROUP), m.name)
		assert_false(m.is_queued_for_deletion())
	_step_all(BattleFx.TOPPLE_LAND_SEC + 0.01)
	for m: Node3D in all:
		assert_true(m.is_queued_for_deletion(), "%s звільняє себе" % m.name)


func test_each_moment_fits_the_phone_budget() -> void:
	for m: Node3D in _moments():
		var draws: int = 0
		var particles: int = 0
		for n: Node in m.find_children("*", "GeometryInstance3D", true, false):
			draws += 1
			if n is GPUParticles3D:
				particles += (n as GPUParticles3D).amount
		assert_between(draws, 1, 6, "%s: викликів малювання" % m.name)
		assert_true(particles <= 80, "%s: %d частинок" % [m.name, particles])


func test_live_wire_arcs_and_lights_then_frees_the_light() -> void:
	var at := Vector3(1, 0, 1)
	var hit: Node3D = BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 1.2, 0), BattleFx.Debris.CONCRETE, true)
	var arc := hit.get_node("Arc") as MeshInstance3D
	var light := hit.get_node("ArcLight") as OmniLight3D
	assert_eq(arc.position, Vector3(0, 1.2, 0), "дуга — на верху опори")
	assert_almost_eq(float((arc.material_override as ShaderMaterial).get_shader_parameter("arc")), 1.0, 0.001)
	_step_all(1.5)
	assert_true(light.is_queued_for_deletion(), "світло дуги не висить у сцені")
	var dead: Node3D = BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 1.2, 0), BattleFx.Debris.CONCRETE, false)
	assert_null(dead.get_node_or_null("Arc"), "без напруги дуги нема")


## Та сама точка — той самий розкид: косметика з хешу місця, а не з глобального rand.
func test_scatter_comes_from_the_position() -> void:
	var at := Vector3(5, 0, 2)
	var a: Node3D = BattleFx.spawn_topple_land(parent, at, at + Vector3(1, 0, 0), BattleFx.Debris.WOOD, false)
	var b: Node3D = BattleFx.spawn_topple_land(parent, at, at + Vector3(1, 0, 0), BattleFx.Debris.WOOD, false)
	assert_eq((a.get_node("Splinters") as GPUParticles3D).seed, (b.get_node("Splinters") as GPUParticles3D).seed)
	assert_true((a.get_node("Splinters") as GPUParticles3D).use_fixed_seed)


func test_warm_up_covers_topple_and_stays_invisible() -> void:
	BattleFx.warm_up(parent, Vector3(2, 0, 2))
	var found: int = 0
	for n: Node in parent.get_children():
		if String(n.name).begins_with("Topple"):
			found += 1
			assert_almost_eq((n as Node3D).scale.x, 0.0001, 1e-6)
			for l: Node in n.find_children("*", "OmniLight3D", true, false):
				assert_false((l as OmniLight3D).visible)
	assert_eq(found, 2, "розігрів — удар і падіння")
