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


## Куля народжується в корпусі, ~1 м над землею, і здіймається з нього: точка вибуху атласу
## внизу клітинки, тож вищий корінь підняв би всю кулю над машиною.
func test_fireball_is_born_inside_the_hull() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var mat := (boom.get_node("Ball") as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("lift"), 1.0 / 8.0)
	assert_eq(boom.position, Vector3(2, 0, 3))


func test_explosion_frees_itself_within_one_and_a_half_seconds() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	_step_all(BattleFx.EXPLOSION_SEC + 0.01)
	assert_true(boom.is_queued_for_deletion())
	# Куля знищення — не мить влучання: темному хвосту дано ще ~1 с, щоб полум'я уламків
	# встигло проступити, а не замінило кулю одним кадром.
	assert_eq(BattleFx.EXPLOSION_SEC, 40.0 / BattleFx.EXPLOSION_FPS + BattleFx.EXPLOSION_TAIL_SEC)
	assert_eq(BattleFx.EXPLOSION_TAIL_SEC, 1.0)


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
		[BattleFx.Weapon.AUTOCANNON, true]: ["armour_sparks.png", "explosion.png", "impact_flash.png"],
		[BattleFx.Weapon.AUTOCANNON, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.TANK_GUN, true]: ["armour_sparks.png", "explosion.png", "impact_flash.png"],
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
		var sparks: Array[Node] = _sparks(hit)
		assert_eq(sparks.size(), 6, "кожна іскра — свій вузол, усі шість")
		for n: Node in sparks:
			var f: float = ((n as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("frame")
			assert_false(f == 2.0 or f == 3.0)



func _sparks(root: Node) -> Array[Node]:
	return root.find_children("Spark*", "MeshInstance3D", true, false)


## Влучання в броню — бризки біло-жовтих іскор, а не вогняні клуби: автогармата — три іскри
## на снаряд, гармата — віяло з восьми.
func test_armour_hits_spray_sparks() -> void:
	assert_eq(_sparks(BattleFx.spawn_hit(parent, Vector3(1, 0, 1), BattleFx.Weapon.AUTOCANNON, true)).size(), 12)
	assert_eq(_sparks(BattleFx.spawn_hit(parent, Vector3(2, 0, 1), BattleFx.Weapon.TANK_GUN, true)).size(), 8)
	assert_eq(_sparks(BattleFx.spawn_hit(parent, Vector3(3, 0, 1), BattleFx.Weapon.TANK_GUN, false)).size(), 0)


func _params(root: Node, key: String) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(((n as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(key))
	return out


## Кожна клуба народжується в точці вибуху свого атласу (SOURCES.md): квад зсунуто так, що
## ця точка атласу лягає на точку влучання (дуло, ґрунт, корпус). Край м'який на 1,5 м.
func test_each_sprite_is_born_at_its_atlas_blast_point() -> void:
	var expect := {
		BattleFx.EXPLOSION_TEX: Vector2(0.5 - 0.508, 0.866 - 0.5),
		BattleFx.DIRT_TEX: Vector2(0.5 - 0.495, 0.882 - 0.5),
		BattleFx.FLASH_TEX: Vector2(0.5 - 0.479, 0.788 - 0.5),
		BattleFx.SPARKS_TEX: Vector2.ZERO,
	}
	var roots: Array[Node3D] = [BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5), BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)]
	for w: int in BattleFx.Weapon.values():
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 5), w, false))
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 7), w, true))
	var seen: Dictionary = {}
	for root: Node3D in roots:
		if root == null:
			continue
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mat := (n as MeshInstance3D).material_override as ShaderMaterial
			var tex: Texture2D = mat.get_shader_parameter("tex")
			var got: Vector2 = mat.get_shader_parameter("anchor")
			assert_almost_eq(got, expect[tex], Vector2.ONE * 1e-6, "%s" % tex.resource_path)
			seen[tex] = true
	assert_eq(seen.size(), 4, "перевірено всі чотири атласи")
	for f: Variant in _params(BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false), "soft_fade"):
		assert_eq(f, 1.5 / 8.0)


## Розміри клітинок атласів і вмісту — з SOURCES.md і виміряних кадрів: куля на піку
## 197 текселів із 256 у 21,7-метровій клітинці, ґрунт 190 із 256 у 13,4 м, спалах 112 із 192
## у 9,2 м.
func test_atlas_cells_match_sources() -> void:
	assert_eq(BattleFx.EXPLOSION_CELL_M, 21.7)
	assert_eq(BattleFx.DIRT_CELL_M, 13.4)
	assert_eq(BattleFx.FLASH_CELL_M, 9.2)
	assert_almost_eq(BattleFx.EXPLOSION_BALL_M, 21.7 * 197.0 / 256.0, 1e-9)
	assert_almost_eq(BattleFx.DIRT_CLOUD_M, 13.4 * 190.0 / 256.0, 1e-9)
	assert_almost_eq(BattleFx.FLASH_CORE_M, 9.2 * 112.0 / 192.0, 1e-9)


## Атлас ґрунту сам плавно гасне на останніх кадрах: другого згасання поверх нього нема,
## інакше хмара зникала б різко раніше за свій кінець.
func test_dirt_plays_the_atlas_own_fade() -> void:
	assert_false(BattleFx._shader(false).code.contains("fade_from"))


## Спалах не вигорає в чисто біле: перші ~4 кадри тьмяніші, а там, де альфа спадає, колір
## холоне до #B8400F. Іскри цього не мають.
func test_flash_starts_soft_and_cools_at_its_edge() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	for n: Node in hit.find_children("Flash*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		assert_eq(mat.get_shader_parameter("early_gain"), BattleFx.FLASH_EARLY_GAIN)
		assert_eq(mat.get_shader_parameter("cool_edge"), 1.0)
	assert_eq(BattleFx.FLASH_EARLY_GAIN, 0.55)
	var armour: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.TANK_GUN, true)
	for n: Node in armour.find_children("Spark*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		assert_eq(mat.get_shader_parameter("cool_edge"), 0.0)


## Розміри влучань, діаметр клуби в метрах: по броні — менші, ніж по ґрунту.
func test_hit_sizes_follow_the_weapon_and_the_target() -> void:
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.AUTOCANNON, true), 0.5)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.TANK_GUN, true), 2.5)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.TANK_GUN, false), 3.5)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.SHELL, false), 12.0)


## Вибух у ґрунті викидає грудки землі й кілька смуг балістичними дугами: одна система
## частинок на грудки й одна на смуги, коротке життя, кількість і розмір — від радіуса вибуху.
## По броні ґрунту нема — й грудок теж.
func test_ground_bursts_throw_clods_and_armour_hits_do_not() -> void:
	var shell: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var clods := shell.get_node("Debris") as GPUParticles3D
	var streaks := shell.get_node("DebrisStreaks") as GPUParticles3D
	assert_eq(clods.amount, 18)
	assert_eq(streaks.amount, 4)
	assert_true(clods.one_shot and streaks.one_shot)
	assert_eq(clods.lifetime, 1.2)
	var pm := clods.process_material as ParticleProcessMaterial
	assert_eq(pm.gravity, Vector3(0.0, -9.8 / 8.0, 0.0), "справжня вага, 1 тайл = 8 м")
	# Властивість зберігається у float32: допуск — лише на округлення.
	assert_almost_eq(pm.scale_min, 0.1 / 8.0, 1e-7)
	assert_almost_eq(pm.scale_max, 0.4 / 8.0, 1e-7)
	var gun: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.TANK_GUN, false)
	assert_eq((gun.get_node("Debris") as GPUParticles3D).amount, 10)
	assert_eq((gun.get_node("DebrisStreaks") as GPUParticles3D).amount, 2)
	for weapon: BattleFx.Weapon in [BattleFx.Weapon.TANK_GUN, BattleFx.Weapon.DRONE, BattleFx.Weapon.AUTOCANNON]:
		var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, weapon, true)
		assert_eq(hit.find_children("Debris*", "GPUParticles3D", true, false).size(), 0)
