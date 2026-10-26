extends GutTest
## Миті бою: вогняна куля знищеної техніки, влучання за зброєю, дульний спалах. Вибух різкий
## (повний об'єм за 0,1–0,2 с), дим після нього не зникає на місці: здіймається з
## уповільненням, ширшає й рівно розріджується до нуля за 1–6 с; програвач чекає лише 0,3 с.

var parent: Node3D


func before_each() -> void:
	parent = Node3D.new()
	add_child_autofree(parent)


func _step_all(sec: float) -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(sec)


## Спалах — кадри 2–15 атласу по 90 кадрів/с (≈ 0,16 с), світло — 3–5 кадрів екрана.
func test_flash_plays_its_frames_and_the_light_dies_fast() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var flash := boom.get_node("Flash") as MeshInstance3D
	assert_true(BattleFx.FLASH_SEC >= 0.06 and BattleFx.FLASH_SEC <= 0.1)
	assert_true(flash.visible)
	assert_eq((flash.material_override as ShaderMaterial).get_shader_parameter("frame"), float(BattleFx.FLASH_FIRST))
	_step_all(BattleFx.FLASH_SEC + 0.001)
	assert_eq((boom.get_node("Light") as OmniLight3D).light_energy, 0.0)
	_step_all((16.0 - BattleFx.FLASH_FIRST) / BattleFx.FLASH_FPS)
	_step_all(0.01)
	assert_false(flash.visible, "спалах дограв і сховався, а не висить над кулею")


## Куля народжується в корпусі, ~1 м над землею, і здіймається з нього: точка вибуху атласу
## внизу клітинки, тож вищий корінь підняв би всю кулю над машиною.
func test_fireball_is_born_inside_the_hull() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var mat := (boom.get_node("Ball") as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("lift"), 1.0 / 8.0)
	assert_eq(boom.position, Vector3(2, 0, 3))


## Куля перетікає в дим: вогонь згасає за FIRE_OUT, дим проступає за SMOKE_IN і живе до кінця.
func test_fireball_hands_over_to_smoke() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	var ball := (boom.get_node("Ball") as MeshInstance3D).material_override as ShaderMaterial
	var smoke := (boom.get_node("Smoke") as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(smoke.get_shader_parameter("tex"), BattleFx.SMOKE_TEX)
	assert_eq(smoke.get_shader_parameter("opacity"), 0.0, "дим проступає, а не стоїть із першого кадру")
	_step_all(BattleFx.FIRE_OUT.y + 0.05)
	assert_false((boom.get_node("Ball") as MeshInstance3D).visible, "вогонь згас")
	assert_almost_eq(float(smoke.get_shader_parameter("opacity")), 1.0, 0.05, "дим уже повний")
	assert_eq(ball.get_shader_parameter("opacity"), 0.0)


## Дим кулі знищення висить 3–6 с і лише тоді звільняється разом із коренем; програвачеві
## на нього чекати не треба.
func test_explosion_frees_itself_after_its_smoke() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	assert_true(BattleFx.EXPLOSION_SEC >= 3.0 and BattleFx.EXPLOSION_SEC <= 6.0)
	_step_all(BattleFx.EXPLOSION_SEC - 0.1)
	assert_false(boom.is_queued_for_deletion(), "дим ще розріджується")
	_step_all(0.11)
	assert_true(boom.is_queued_for_deletion())


## Мить влучання — за класом зброї стрільця: одноразова, звільняє себе, коли дим уже розвіявся.
func test_every_hit_moment_frees_itself() -> void:
	for weapon: int in BattleFx.Weapon.values():
		for armoured: bool in [true, false]:
			var hit: Node3D = BattleFx.spawn_hit(parent, Vector3(1, 0, 1), weapon, armoured)
			_step_all(BattleFx.HIT_SEC + 0.01)
			assert_true(hit.is_queued_for_deletion(), "зброя %d" % weapon)
	assert_true(BattleFx.HIT_SEC <= 6.5)
	assert_eq(BattleFx.HIT_HOLD_SEC, 0.3, "програвач чекає лише на спалах")


## Кожен квад диму ховається лише тоді, коли вже прозорий: жодного обриву в кінці.
func test_smoke_is_transparent_before_it_hides() -> void:
	var roots: Array[Node3D] = [BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)]
	for w: int in BattleFx.Weapon.values():
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 3), w, false))
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 6), w, true))
	var last_opacity: Dictionary = {}
	for i in 140:
		_step_all(0.05)
		for r: Node3D in roots:
			for n: Node in r.find_children("*", "MeshInstance3D", true, false):
				if n.name.begins_with("Flash"):
					continue
				var mi := n as MeshInstance3D
				var op: float = (mi.material_override as ShaderMaterial).get_shader_parameter("opacity")
				if not mi.visible and last_opacity.has(mi) and last_opacity[mi] >= 0.0:
					assert_lt(last_opacity[mi], 0.05, "%s сховався непрозорим" % mi.name)
					last_opacity[mi] = -1.0
				elif mi.visible:
					last_opacity[mi] = op


## Дим здіймається й ширшає: за 2 с клуба снаряда вища й більша, ніж на старті.
func test_smoke_rises_and_spreads() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var dirt := hit.get_node("Dirt") as MeshInstance3D
	var y0: float = dirt.position.y
	_step_all(2.0)
	assert_gt(dirt.position.y - y0, 1.0 / 8.0, "піднялась більш ніж на метр")
	assert_gt(dirt.scale.x, 1.2)


## Криві диму: атлас набирає повний об'єм за `full` с, далі повзе; прозорість спадає рівно й
## лягає в нуль без зламу; підйом гальмує.
func test_smoke_curves() -> void:
	var tau: float = BattleFx.snap_tau(0.15, 0.0, BattleFx.LAST_FRAME)
	assert_almost_eq(BattleFx.smoke_frame(0.0, tau, 5.0), 0.0, 1e-6)
	assert_almost_eq(BattleFx.smoke_frame(0.15, tau, 5.0), BattleFx.FULL_FRAME, 0.5, "повний об'єм за 0,15 с")
	assert_almost_eq(BattleFx.smoke_frame(5.0, tau, 5.0), BattleFx.LAST_FRAME, 1e-4)
	var early: float = BattleFx.smoke_frame(0.5, tau, 5.0) - BattleFx.smoke_frame(0.0, tau, 5.0)
	var late: float = BattleFx.smoke_frame(5.0, tau, 5.0) - BattleFx.smoke_frame(4.5, tau, 5.0)
	assert_gt(early, late * 10.0, "атлас швидкий на старті й повільний у кінці")
	assert_eq(BattleFx.smoke_opacity(0.0, 5.0), 1.0)
	assert_eq(BattleFx.smoke_opacity(5.0, 5.0), 0.0)
	assert_lt(BattleFx.smoke_opacity(4.75, 5.0), 0.01, "останні 5 % — майже нуль: обриву нема")
	var prev: float = 1.0
	for i in 51:
		var o: float = BattleFx.smoke_opacity(i * 0.1, 5.0)
		assert_true(o <= prev + 1e-6)
		prev = o
	var v0: float = BattleFx.rise_m(1.5, 0.1) / 0.1
	var v3: float = BattleFx.rise_m(1.5, 3.1) - BattleFx.rise_m(1.5, 3.0)
	assert_almost_eq(v0, 1.5, 0.05, "стартова швидкість 1,5 м/с")
	assert_lt(v3 / 0.1, v0 * 0.5, "за 3 с підйом сповільнився")


## Передача ходу прибирає всі миті: дим над нерозвіданим тайлом показав би ціль (§3.5).
func test_clear_all_frees_every_moment() -> void:
	var a: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var b: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	var c: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)
	BattleFx.clear_all(get_tree())
	for n: Node3D in [a, b, c]:
		assert_true(n.is_queued_for_deletion())


## Розігрів малює кулю, влучання в броню й снаряд у ґрунт — невидимо мало, без світла.
func test_warm_up_is_invisible() -> void:
	BattleFx.warm_up(parent, Vector3.ZERO)
	var roots: Array[Node] = parent.get_children()
	assert_eq(roots.size(), 3)
	for r: Node in roots:
		assert_eq((r as Node3D).scale, Vector3.ONE * 0.0001)
		for l: Node in r.find_children("*", "OmniLight3D", true, false):
			assert_eq((l as OmniLight3D).light_energy, 0.0)


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


## Спалах — на кінчику ствола: танк (5,5 м попереду, вісь у башті) і гаубиця (над станиною).
func test_muzzle_flash_sits_at_the_barrel_tip() -> void:
	var tank: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(Basis(), Vector3(2, 0, 3)), BattleFx.Weapon.TANK_GUN, 5)
	assert_almost_eq(tank.position, Vector3(2.0, 0.3 - 0.05, 3.0 - 0.69), Vector3.ONE * 0.05)
	var how: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.SHELL, 10)
	assert_almost_eq(how.position, Vector3(0.0, 0.34, -0.45), Vector3.ONE * 0.05)


func _paths(root: Node) -> Array[String]:
	var out: Array[String] = []
	for t: Texture2D in BattleFx.atlases_of(root):
		out.append(t.resource_path.get_file())
	out.sort()
	return out


## Кожна мить бере свій запечений атлас: куля — вибух, дим і спалах; сіра клуба по броні —
## знебарвлений атлас ґрунту; іскри — частинки без атласу.
func test_each_effect_samples_its_atlas() -> void:
	assert_eq(_paths(BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)), ["explosion.png", "impact_flash.png", "smoke_column.png"])
	var expect: Dictionary = {
		[BattleFx.Weapon.RIFLE, true]: [],
		[BattleFx.Weapon.RIFLE, false]: ["dirt_burst.png"],
		[BattleFx.Weapon.AUTOCANNON, true]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.AUTOCANNON, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.TANK_GUN, true]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.TANK_GUN, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.SHELL, false]: ["dirt_burst.png", "impact_flash.png"],
		[BattleFx.Weapon.DRONE, true]: ["explosion.png", "impact_flash.png", "smoke_column.png"],
	}
	for k: Array in expect:
		assert_eq(_paths(BattleFx.spawn_hit(parent, Vector3.ZERO, k[0], k[1])), expect[k], str(k))
	assert_eq(_paths(BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)), ["dirt_burst.png", "impact_flash.png"])


func _sparks(root: Node) -> int:
	var n: int = 0
	for e: Node in root.find_children("Sparks*", "GPUParticles3D", true, false):
		n += (e as GPUParticles3D).amount
	return n


## Влучання в броню — біло-жовті іскри, що розлітаються рисками вздовж швидкості під
## справжньою вагою й холонуть: автогармата — п'ять на снаряд, гармата — віяло з вісімнадцяти.
## По ґрунту іскор нема.
func test_armour_hits_spray_sparks() -> void:
	assert_eq(_sparks(BattleFx.spawn_hit(parent, Vector3(1, 0, 1), BattleFx.Weapon.AUTOCANNON, true)), 20)
	var gun: Node3D = BattleFx.spawn_hit(parent, Vector3(2, 0, 1), BattleFx.Weapon.TANK_GUN, true)
	assert_eq(_sparks(gun), 18)
	assert_eq(_sparks(BattleFx.spawn_hit(parent, Vector3(3, 0, 1), BattleFx.Weapon.TANK_GUN, false)), 0)
	var em := gun.get_node("Sparks") as GPUParticles3D
	assert_eq(em.transform_align, GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY)
	assert_true(em.one_shot)
	assert_eq((em.process_material as ParticleProcessMaterial).gravity, Vector3(0.0, -9.8 / 8.0, 0.0))
	assert_true(em.lifetime <= 0.5, "іскра живе частки секунди")


func _params(root: Node, key: String) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(((n as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(key))
	return out


## Кожна клуба народжується в точці вибуху свого атласу (SOURCES.md): квад зсунуто так, що
## ця точка атласу лягає на точку влучання (дуло, ґрунт, корпус). Край м'який на 1,5 м, а в
## малої клуби — на п'яту її кваду.
func test_each_sprite_is_born_at_its_atlas_blast_point() -> void:
	var expect := {
		BattleFx.EXPLOSION_TEX: Vector2(0.5 - 0.508, 0.866 - 0.5),
		BattleFx.DIRT_TEX: Vector2(0.5 - 0.495, 0.882 - 0.5),
		BattleFx.FLASH_TEX: Vector2(0.5 - 0.479, 0.788 - 0.5),
		BattleFx.SMOKE_TEX: Vector2(0.5 - 0.514, 0.835 - 0.5),
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
			assert_almost_eq(float(mat.get_shader_parameter("soft_fade")), minf(BattleFx.HIT_SOFT_FADE, float(mat.get_shader_parameter("size")) * 0.2), 1e-6)
			seen[tex] = true
	assert_eq(seen.size(), 4, "перевірено всі чотири атласи")
	assert_true(_params(BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false), "soft_fade").has(BattleFx.HIT_SOFT_FADE), "велика клуба — 1,5 м")


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


## Атлас клуби не доходить до кадрів, де сам гасне до порожнечі: згасання веде крива
## прозорості, тож клуба рідшає рівно, а не зникає разом із флипбуком.
func test_smoke_never_plays_the_atlas_own_fade() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var mat := (hit.get_node("Dirt") as MeshInstance3D).material_override as ShaderMaterial
	var top: float = 0.0
	for i in 70:
		_step_all(0.1)
		top = maxf(top, float(mat.get_shader_parameter("frame")))
	assert_true(top <= BattleFx.LAST_FRAME + 1e-4)


## Спалах не вигорає в чисто біле: перші ~4 кадри тьмяніші, а там, де альфа спадає, колір
## холоне до #B8400F. Клуби цього не мають.
func test_flash_starts_soft_and_cools_at_its_edge() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	for n: Node in hit.find_children("Flash*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		assert_eq(mat.get_shader_parameter("early_gain"), BattleFx.FLASH_EARLY_GAIN)
		assert_eq(mat.get_shader_parameter("cool_edge"), 1.0)
	assert_eq(BattleFx.FLASH_EARLY_GAIN, 0.55)
	for n: Node in hit.find_children("Dirt*", "MeshInstance3D", true, false):
		assert_eq(((n as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("cool_edge"), 0.0)


## Розміри влучань, діаметр клуби в метрах: по броні — клуба з даху, по ґрунту — викид землі.
func test_hit_sizes_follow_the_weapon_and_the_target() -> void:
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.AUTOCANNON, true), 2.5)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.TANK_GUN, true), 5.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.TANK_GUN, false), 6.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.SHELL, false), 12.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.DRONE, true), 6.0)


## Клуби влучання в броню стоять перед корпусом, а не в ньому: інакше корпус їх закриває.
func test_armour_hit_sprites_are_pulled_towards_the_camera() -> void:
	for p: Variant in _params(BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.DRONE, true), "pull"):
		assert_eq(p, BattleFx.ARMOUR_PULL)
	for p: Variant in _params(BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false), "pull"):
		assert_eq(p, 0.0)


## Вибух у ґрунті викидає грудки землі й кілька смуг балістичними дугами: одна система
## частинок на грудки й одна на смуги, коротке життя, кількість і розмір — від радіуса вибуху.
## По броні ґрунту нема — й грудок теж; знищена техніка розкидає уламки 0,3–1 м.
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
	assert_eq((gun.get_node("Debris") as GPUParticles3D).amount, 12)
	assert_eq((gun.get_node("DebrisStreaks") as GPUParticles3D).amount, 3)
	for weapon: BattleFx.Weapon in [BattleFx.Weapon.TANK_GUN, BattleFx.Weapon.DRONE, BattleFx.Weapon.AUTOCANNON]:
		var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, weapon, true)
		assert_eq(hit.find_children("Debris*", "GPUParticles3D", true, false).size(), 0)
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	var wreckage := (boom.get_node("Debris") as GPUParticles3D).process_material as ParticleProcessMaterial
	assert_almost_eq(wreckage.scale_min, 0.3 / 8.0, 1e-6)
	assert_almost_eq(wreckage.scale_max, 1.0 / 8.0, 1e-6)
	assert_eq((boom.get_node("Debris") as GPUParticles3D).amount, 24)
