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


## Спалах — 16 кадрів атласу по 60 кадрів/с (≈ 0,27 с), світло — 3–5 кадрів екрана.
func test_flash_plays_its_sixteen_frames_and_the_light_dies_fast() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var flash := boom.get_node("Flash") as MeshInstance3D
	assert_true(BattleFx.FLASH_SEC >= 0.06 and BattleFx.FLASH_SEC <= 0.1)
	assert_true(flash.visible)
	_step_all(BattleFx.FLASH_SEC + 0.001)
	assert_eq((boom.get_node("Light") as OmniLight3D).light_energy, 0.0)
	_step_all(16.0 / BattleFx.FLASH_FPS)
	_step_all(0.01)
	assert_false(flash.visible, "спалах дограв і сховався, а не висить над кулею")


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


## Мить влучання — за класом зброї стрільця: одноразова, ≤ 1,5 с, звільняє себе.
func test_every_hit_moment_frees_itself_within_one_and_a_half_seconds() -> void:
	for weapon: int in BattleFx.Weapon.values():
		for armoured: bool in [true, false]:
			var hit: Node3D = BattleFx.spawn_hit(parent, Vector3(1, 0, 1), weapon, armoured)
			_step_all(BattleFx.HIT_SEC + 0.01)
			assert_true(hit.is_queued_for_deletion(), "зброя %d" % weapon)
	assert_true(BattleFx.HIT_SEC <= 1.5)


## Світло — лише там, де спалах справді яскравий: гармата й снаряд, не кулі.
func test_only_guns_and_shells_light_up_the_hit() -> void:
	var lit: Dictionary = {}
	for weapon: int in BattleFx.Weapon.values():
		var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, weapon, true)
		lit[weapon] = hit.find_children("*", "OmniLight3D", true, false).size()
	assert_eq(lit[BattleFx.Weapon.RIFLE], 0)
	assert_eq(lit[BattleFx.Weapon.AUTOCANNON], 0)
	assert_eq(lit[BattleFx.Weapon.TANK_GUN], 1)
	assert_eq(lit[BattleFx.Weapon.SHELL], 1)


func test_weapon_follows_the_shooters_class() -> void:
	assert_eq(BattleFx.weapon_of(UnitTypes.UnitClass.INFANTRY), BattleFx.Weapon.RIFLE)
	assert_eq(BattleFx.weapon_of(UnitTypes.UnitClass.LIGHT_VEHICLE), BattleFx.Weapon.AUTOCANNON)
	assert_eq(BattleFx.weapon_of(UnitTypes.UnitClass.TANK), BattleFx.Weapon.TANK_GUN)
	assert_eq(BattleFx.weapon_of(UnitTypes.UnitClass.ARTILLERY), BattleFx.Weapon.SHELL)


## Дульний спалах малих калібрів на екрані субпіксельний: у стрілецької зброї його нема.
func test_rifles_have_no_muzzle_flash() -> void:
	assert_null(BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.RIFLE))
	var m: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)
	assert_not_null(m)
	_step_all(BattleFx.HIT_SEC + 0.01)
	assert_true(m.is_queued_for_deletion())



func _paths(root: Node) -> Array[String]:
	var out: Array[String] = []
	for t: Texture2D in BattleFx.atlases_of(root):
		out.append(t.resource_path.get_file())
	out.sort()
	return out


## Кожна мить бере свій запечений атлас: куля — вибух і спалах, удари — за зброєю й ціллю.
func test_each_effect_samples_its_atlas() -> void:
	assert_eq(_paths(BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)), ["explosion.png", "impact_flash.png"])
	var expect: Dictionary = {
		[BattleFx.Weapon.RIFLE, true]: ["armour_sparks.png"],
		[BattleFx.Weapon.RIFLE, false]: ["dirt_burst.png"],
		[BattleFx.Weapon.AUTOCANNON, true]: ["explosion.png", "impact_flash.png"],
		[BattleFx.Weapon.AUTOCANNON, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.TANK_GUN, true]: ["explosion.png", "impact_flash.png"],
		[BattleFx.Weapon.TANK_GUN, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.SHELL, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.DRONE, true]: ["explosion.png", "impact_flash.png"],
	}
	for k: Array in expect:
		assert_eq(_paths(BattleFx.spawn_hit(parent, Vector3.ZERO, k[0], k[1])), expect[k], str(k))
	assert_eq(_paths(BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)), ["impact_flash.png"])


## Іскри trace_03/04 звиваються блискавкою — їх ніколи не показуємо.
func test_sparks_never_use_the_lightning_cells() -> void:
	for i in 20:
		var hit: Node3D = BattleFx.spawn_hit(parent, Vector3(i, 0, i * 3), BattleFx.Weapon.RIFLE, true)
		for n: Node in hit.find_children("Spark*", "", true, false):
			var f: float = ((n as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("frame")
			assert_false(f == 2.0 or f == 3.0)
