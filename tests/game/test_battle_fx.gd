extends GutTest
## Миті бою: вогняна куля знищеної техніки, влучання за зброєю, дульний спалах. Вибух різкий
## (~80 % об'єму за 0,1–0,2 с), дим після нього не зникає на місці: здіймається з
## уповільненням, але не зупиняється, ширшає й розчиняється від країв до ядра за 3–6 с;
## програвач чекає лише 0,3 с.

const UnitViewScene := preload("res://game/battle/unit_view.tscn")

var parent: Node3D


func before_each() -> void:
	BattleFx.wind = Vector3.ZERO
	parent = Node3D.new()
	add_child_autofree(parent)


func _step_all(sec: float) -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(sec)


func _mat(n: Node) -> ShaderMaterial:
	return (n as MeshInstance3D).material_override as ShaderMaterial


func _smoke_sprites(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		if _mat(n).get_shader_parameter("erode") != null:
			out.append(n as MeshInstance3D)
	return out


## Гаряче ядро кулі — два кадри, світло — 3–5 кадрів і після згасання звільняється.
func test_hot_core_lasts_two_frames_and_the_light_is_freed() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	var hot := boom.get_node("Hot") as MeshInstance3D
	assert_true(hot.visible)
	assert_true(BattleFx.HOT_SEC <= 2.5 / 60.0, "не довше двох кадрів")
	assert_true(BattleFx.FLASH_SEC >= 0.06 and BattleFx.FLASH_SEC <= 0.1)
	var light := boom.get_node("Light") as OmniLight3D
	_step_all(BattleFx.HOT_SEC + 0.001)
	assert_false(hot.visible)
	_step_all(BattleFx.FLASH_SEC)
	assert_eq(light.light_energy, 0.0)
	assert_true(light.is_queued_for_deletion(), "згасле світло не висить у сцені")


## Куля народжується в корпусі, ~1 м над землею, і здіймається з нього.
func test_fireball_is_born_inside_the_hull() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3(2, 0, 3), 1.5)
	assert_eq(_mat(boom.get_node("Ball")).get_shader_parameter("lift"), 1.0 / 8.0)
	assert_eq(boom.position, Vector3(2, 0, 3))


## Куля перетікає в дим без провалу «темно → світло → темно»: дим під кулею повний раніше, ніж
## куля почне розчинятись, і куля ховається, лише розчинившись.
func test_fireball_hands_over_to_smoke_without_a_gap() -> void:
	for root: Node3D in [BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5), BattleFx.spawn_hit(parent, Vector3(3, 0, 0), BattleFx.Weapon.DRONE, true)]:
		var ball := _mat(root.get_node("Ball"))
		var smoke := _mat(root.get_node("Smoke"))
		assert_eq(smoke.get_shader_parameter("tex"), BattleFx.SMOKE_TEX)
		assert_eq(smoke.get_shader_parameter("opacity"), 0.0, "дим проступає, а не стоїть із першого кадру")
		assert_true(ball.render_priority > smoke.render_priority, "вогонь — поверх диму")
	_step_all(0.36)
	for root: Node in parent.get_children():
		assert_almost_eq(float(_mat(root.get_node("Smoke")).get_shader_parameter("opacity")), 1.0, 1e-3, "дим повний")
		assert_almost_eq(float(_mat(root.get_node("Ball")).get_shader_parameter("erode")), 0.0, 1e-3, "куля ще ціла")
	_step_all(BattleFx.FIRE_SEC)
	for root: Node in parent.get_children():
		assert_false((root.get_node("Ball") as MeshInstance3D).visible)


func test_explosion_frees_itself_after_its_smoke() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	assert_true(BattleFx.EXPLOSION_SEC >= 3.0 and BattleFx.EXPLOSION_SEC <= 6.0)
	_step_all(BattleFx.EXPLOSION_SEC - 0.1)
	assert_false(boom.is_queued_for_deletion(), "дим ще розчиняється")
	_step_all(0.25)
	assert_true(boom.is_queued_for_deletion())


## Корінь живе довше за найпізніший дим кожної пари зброя/ціль; програвач чекає лише на спалах.
func test_no_moment_is_freed_while_its_smoke_shows() -> void:
	assert_eq(BattleFx.HIT_HOLD_SEC, 0.3, "програвач чекає лише на спалах")
	for weapon: int in BattleFx.Weapon.values():
		for armoured: bool in [true, false]:
			var life: float = BattleFx.smoke_sec(weapon, armoured) + BattleFx.smoke_delay(weapon, armoured)
			assert_true(BattleFx.HIT_SEC >= life, "зброя %d, броня %s" % [weapon, armoured])
			var hit: Node3D = BattleFx.spawn_hit(parent, Vector3(weapon, 0, 1 if armoured else 4), weapon, armoured)
			var sprites: Array[MeshInstance3D] = _smoke_sprites(hit)
			while not hit.is_queued_for_deletion():
				_step_all(0.1)
			for q: MeshInstance3D in sprites:
				assert_false(q.visible and float(_mat(q).get_shader_parameter("erode")) < 0.98, "%s ще видно" % q.name)
	assert_true(BattleFx.HIT_SEC <= 6.5)


## Клуба ховається, лише коли вже розчинилась (ерозія чи рівне згасання порохового диму), а не
## обривається з кінцем флипбука.
func test_smoke_dissolves_before_it_hides() -> void:
	var roots: Array[Node3D] = [BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5), BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)]
	for w: int in BattleFx.Weapon.values():
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 3), w, false))
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 6), w, true))
	var last: Dictionary = {}
	for i in 140:
		_step_all(0.05)
		for r: Node3D in roots:
			for q: MeshInstance3D in _smoke_sprites(r):
				if not q.visible and last.has(q) and last[q] >= 0.0:
					assert_lt(last[q], 0.15, "%s сховався, не розчинившись" % q.name)
					last[q] = -1.0
				elif q.visible:
					last[q] = (1.0 - float(_mat(q).get_shader_parameter("erode"))) * float(_mat(q).get_shader_parameter("opacity"))


## Дим здіймається й ширшає, і підйом гальмує, але не зупиняється до самого кінця.
func test_smoke_rises_spreads_and_never_hangs() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.TANK_GUN, true)
	var puff := hit.get_node("Puff") as MeshInstance3D
	var y0: float = puff.position.y
	_step_all(2.0)
	assert_gt(puff.position.y - y0, 1.0 / 8.0, "піднялась більш ніж на метр")
	assert_gt(puff.scale.x, 1.3)
	var life: float = BattleFx.smoke_sec(BattleFx.Weapon.TANK_GUN, true)
	assert_true(life >= 3.5 and life <= 5.0)
	var v_end: float = (BattleFx.rise_m(1.0, life) - BattleFx.rise_m(1.0, life - 0.1)) / 0.1
	assert_gt(v_end, 0.3 * 0.99, "у кінці клуба ще здіймається")
	var v0: float = BattleFx.rise_m(1.0, 0.05) / 0.05
	assert_almost_eq(v0, 1.0, 0.03, "старт — 1 м/с")


## Вибух різкий: ~80 % об'єму (кадр FULL_FRAME) — за `full` с; далі атлас повзе до кінця життя,
## не зупиняючись; ерозія рівна й лягає в 1 без зламу.
func test_smoke_curves() -> void:
	assert_eq(BattleFx.smoke_frame(0.0, 0.12, 4.0), 0.0)
	assert_almost_eq(BattleFx.smoke_frame(0.12, 0.12, 4.0), BattleFx.FULL_FRAME, 1e-4)
	assert_almost_eq(BattleFx.smoke_frame(4.0, 0.12, 4.0), BattleFx.LAST_FRAME, 1e-4)
	var prev: float = -1.0
	for i in 41:
		var f: float = BattleFx.smoke_frame(i * 0.1, 0.12, 4.0)
		assert_gt(f, prev, "атлас не застигає")
		prev = f
	var early: float = BattleFx.smoke_frame(0.12, 0.12, 4.0) / 0.12
	var late: float = (BattleFx.smoke_frame(4.0, 0.12, 4.0) - BattleFx.smoke_frame(3.5, 0.12, 4.0)) / 0.5
	assert_gt(early, late * 10.0, "швидко на старті, повільно в кінці")
	assert_eq(BattleFx.smoke_erode(0.5, 4.0, 1.0), 0.0)
	assert_eq(BattleFx.smoke_erode(4.0, 4.0, 1.0), 1.0)
	assert_almost_eq(BattleFx.smoke_erode(2.5, 4.0, 1.0), 0.5, 1e-6, "лінійно: без обвалу в кінці")
	assert_eq(BattleFx.ERODE_FROM, 0.35, "форму тримає перші 35 % життя")
	assert_true(BattleFx._SPRITE_CODE.contains("(1.0 - erode)"), "уся клуба рівно тане разом з ерозією")


## Сіра клуба влучання в броню майже повна вже за 0,15 с: далі лише ширшає й здіймається.
func test_armour_puff_is_nearly_full_at_once() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.TANK_GUN, true)
	var puff := _mat(hit.get_node("Puff"))
	_step_all(0.15)
	assert_true(float(puff.get_shader_parameter("frame")) >= BattleFx.FULL_FRAME)
	assert_eq(puff.get_shader_parameter("opacity"), 1.0)
	assert_lt(float(puff.get_shader_parameter("erode")), 0.01, "ще не розчиняється")


## Передача ходу прибирає всі миті: дим над нерозвіданим тайлом показав би ціль (§3.5).
func test_clear_all_frees_every_moment() -> void:
	var a: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var b: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	var c: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)
	BattleFx.clear_all(get_tree())
	for n: Node3D in [a, b, c]:
		assert_true(n.is_queued_for_deletion())


## Розігрів малює кулю, влучання в броню, снаряд у ґрунт і постріл гармати — невидимо мало, без
## світла, частинки нульові й нерухомі.
func test_warm_up_is_invisible() -> void:
	BattleFx.warm_up(parent, Vector3.ZERO)
	var roots: Array[Node] = parent.get_children()
	assert_eq(roots.size(), 4)
	for r: Node in roots:
		assert_eq((r as Node3D).scale, Vector3.ONE * 0.0001)
		for l: Node in r.find_children("*", "OmniLight3D", true, false):
			assert_eq((l as OmniLight3D).light_energy, 0.0)
		for e: Node in r.find_children("*", "GPUParticles3D", true, false):
			var pm := (e as GPUParticles3D).process_material as ParticleProcessMaterial
			assert_true(pm.scale_max < 0.001, "частинка розігріву невидима")
			assert_eq(pm.initial_velocity_max, 0.0)


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


## Спалах — на кінчику ствола: танк (5,8 м попереду, вісь у башті) і гаубиця (над станиною).
func test_muzzle_flash_sits_at_the_barrel_tip() -> void:
	var tank: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(Basis(), Vector3(2, 0, 3)), BattleFx.Weapon.TANK_GUN, 5)
	assert_almost_eq(tank.position, Vector3(2.0, 0.3 - 0.05, 3.0 - 0.72), Vector3.ONE * 0.05)
	var how: Node3D = BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.SHELL, 10)
	assert_almost_eq(how.position, Vector3(0.0, 0.34, -0.45), Vector3.ONE * 0.05)


## Постріл гармати: гаряче ядро на два кадри, 3–4 клуби сіро-бежевого порохового диму вздовж
## осі ствола (різні розміри, рівне згасання), низький рваний шар пилу 1,25 клітинки під корпусом
## і перед ним, що осідає за 1,5–2 с.
func test_tank_muzzle_has_core_powder_along_the_barrel_and_ground_dust() -> void:
	var shooter := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(2, 0, 3))
	var m: Node3D = BattleFx.spawn_muzzle(parent, shooter, BattleFx.Weapon.TANK_GUN, 5)
	var hot := _mat(m.get_node("Hot"))
	assert_almost_eq(float(hot.get_shader_parameter("size")) * 8.0, 2.0, 1e-6, "ядро 1,5–2 м")
	assert_eq(hot.get_shader_parameter("yellow"), 1.0, "жовто-помаранчеве")
	assert_true(BattleFx.MUZZLE_HOT_SEC >= 0.045 and BattleFx.MUZZLE_HOT_SEC <= 0.06, "три кадри, ~50 мс")
	var axis: Vector3 = -shooter.basis.z
	var powder: Array[Node] = m.find_children("Powder*", "MeshInstance3D", true, false)
	assert_true(powder.size() >= 3 and powder.size() <= 4)
	var prev: float = -1.0
	var sizes: Dictionary = {}
	for p: Node in powder:
		var along: float = (p as Node3D).position.dot(axis)
		assert_gt(along, prev, "клуби йдуть від дула вздовж ствола")
		prev = along
		sizes[_mat(p).get_shader_parameter("size")] = true
		assert_almost_eq((_mat(p).get_shader_parameter("tint") as Vector4).x, 0.254, 1e-3, "сіро-бежевий #8a8274")
		assert_eq(_mat(p).get_shader_parameter("feather"), 1.0, "розмитий край")
	assert_gt(sizes.size(), 1, "клуби різного розміру")
	var dust := m.get_node("Dust") as MeshInstance3D
	assert_almost_eq(float(_mat(dust).get_shader_parameter("size")), 10.0 / 8.0, 1e-6)
	var world: Vector3 = m.position + dust.position
	assert_almost_eq(world.y, 0.03 + 0.3 / 8.0, 0.005, "висить на 0,3 м над землею")
	assert_almost_eq(Vector2(world.x, world.z), Vector2(2.0, 3.0) + Vector2(axis.x, axis.z) * 0.3, Vector2.ONE * 0.01, "під корпусом і перед ним, а не довкола дула")
	assert_true(_mat(dust).shader.code.contains("vec3(VERTEX.x, 0.0, VERTEX.y)"), "пласкій, а не в камеру")
	_step_all(2.6)
	assert_false(dust.visible, "осів за 1,8 с")
	for p: Node in powder:
		assert_false((p as MeshInstance3D).visible, "пороховий дим розтанув за 1,5–2,5 с")


func _paths(root: Node) -> Array[String]:
	var out: Array[String] = []
	for t: Texture2D in BattleFx.atlases_of(root):
		out.append(t.resource_path.get_file())
	out.sort()
	return out


## Кожна мить бере свої атласи: куля — вибух і дим; сіра клуба по броні — знебарвлений атлас
## ґрунту, а гармата ще й коротка вогняна куля; фугас у ґрунті — ґрунт і чорне ядро з атласу
## диму. Гарячі ядра, кільця пилу й іскри — процедурні, без атласу.
func test_each_effect_samples_its_atlas() -> void:
	assert_eq(_paths(BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)), ["explosion.png", "smoke_column.png"])
	var expect: Dictionary = {
		[BattleFx.Weapon.RIFLE, true]: [],
		[BattleFx.Weapon.RIFLE, false]: ["dirt_burst.png"],
		[BattleFx.Weapon.AUTOCANNON, true]: ["dirt_burst.png"],
		[BattleFx.Weapon.AUTOCANNON, false]: ["dirt_burst.png"],
		[BattleFx.Weapon.TANK_GUN, true]: ["dirt_burst.png", "explosion.png"],
		[BattleFx.Weapon.TANK_GUN, false]: ["dirt_burst.png", "smoke_column.png"],
		[BattleFx.Weapon.SHELL, false]: ["dirt_burst.png", "smoke_column.png"],
		[BattleFx.Weapon.DRONE, true]: ["explosion.png", "smoke_column.png"],
	}
	for k: Array in expect:
		assert_eq(_paths(BattleFx.spawn_hit(parent, Vector3.ZERO, k[0], k[1])), expect[k], str(k))
	assert_eq(_paths(BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)), ["dirt_burst.png"])


func _spark_emitters(root: Node) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	for e: Node in root.find_children("Sparks*", "GPUParticles3D", true, false):
		out.append(e as GPUParticles3D)
	return out


## Іскри по броні: риски вздовж швидкості, дугою під вагою, 0,15–0,3 с, кольором чорного тіла
## (біле → жовте → помаранчеве → тьмяно-червоне, прозоре), звичайне змішування, не адитив.
## Кількість і напрям віяла різні від влучання до влучання — не однакова «зірочка». По ґрунту іскор нема.
func test_armour_sparks_are_blackbody_streaks_with_random_fans() -> void:
	var counts: Dictionary = {}
	var dirs: Dictionary = {}
	for i in 8:
		var hit: Node3D = BattleFx.spawn_hit(parent, Vector3(i * 2, 0, 1), BattleFx.Weapon.TANK_GUN, true)
		var em: GPUParticles3D = _spark_emitters(hit)[0]
		assert_true(em.amount >= 7 and em.amount <= 12, "менше на третину–половину")
		counts[em.amount] = true
		var pm := em.process_material as ParticleProcessMaterial
		dirs[pm.direction] = true
		assert_true(pm.spread <= 35.0, "конус довкола напряму рикошету, не віяло")
		assert_eq(em.transform_align, GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY)
		assert_true(em.one_shot)
		assert_eq(pm.gravity, Vector3(0.0, -9.8 / 8.0, 0.0))
		assert_almost_eq(em.lifetime, 0.3, 1e-6)
		assert_almost_eq(em.lifetime * (1.0 - pm.lifetime_randomness), 0.15, 1e-6)
		var ramp: Gradient = (pm.color_ramp as GradientTexture1D).gradient
		assert_gt(ramp.colors[0].b, 0.8, "старт — біло-гарячий")
		var end: Color = ramp.colors[ramp.colors.size() - 1]
		assert_true(end.r > end.g * 3.0 and end.a == 0.0, "кінець — тьмяно-червоний і прозорий")
		var shader: Shader = (em.draw_pass_1.surface_get_material(0) as ShaderMaterial).shader
		assert_false(shader.code.contains("blend_add"))
	assert_gt(counts.size(), 1, "кількість іскор різна")
	assert_gt(dirs.size(), 1, "віяло летить у різні боки")
	assert_eq(_spark_emitters(BattleFx.spawn_hit(parent, Vector3(3, 0, 1), BattleFx.Weapon.TANK_GUN, false)).size(), 0)


## Кожна клуба народжується в точці вибуху свого атласу (SOURCES.md). Край м'який на 1,5 м, а
## в малої клуби — на п'яту її кваду.
func test_each_sprite_is_born_at_its_atlas_blast_point() -> void:
	var expect := {
		BattleFx.EXPLOSION_TEX: Vector2(0.5 - 0.508, 0.866 - 0.5),
		BattleFx.DIRT_TEX: Vector2(0.5 - 0.495, 0.882 - 0.5),
		BattleFx.SMOKE_TEX: Vector2(0.5 - 0.514, 0.835 - 0.5),
	}
	var roots: Array[Node3D] = [BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5), BattleFx.spawn_muzzle(parent, Transform3D(), BattleFx.Weapon.TANK_GUN)]
	for w: int in BattleFx.Weapon.values():
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 5), w, false))
		roots.append(BattleFx.spawn_hit(parent, Vector3(w, 0, 7), w, true))
	var seen: Dictionary = {}
	for root: Node3D in roots:
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mat := _mat(n)
			var tex: Texture2D = mat.get_shader_parameter("tex")
			if tex == null:
				continue
			assert_almost_eq(mat.get_shader_parameter("anchor"), expect[tex], Vector2.ONE * 1e-6, "%s" % tex.resource_path)
			assert_almost_eq(float(mat.get_shader_parameter("soft_fade")), minf(BattleFx.HIT_SOFT_FADE, float(mat.get_shader_parameter("size")) * 0.2), 1e-6)
			seen[tex] = true
	assert_eq(seen.size(), 3, "перевірено всі три атласи")


## Розміри клітинок атласів і вмісту — з SOURCES.md і виміряних кадрів.
func test_atlas_cells_match_sources() -> void:
	assert_eq(BattleFx.EXPLOSION_CELL_M, 21.7)
	assert_eq(BattleFx.DIRT_CELL_M, 13.4)
	assert_almost_eq(BattleFx.EXPLOSION_BALL_M, 21.7 * 197.0 / 256.0, 1e-9)
	assert_almost_eq(BattleFx.DIRT_CLOUD_M, 13.4 * 190.0 / 256.0, 1e-9)


## Атлас клуби не доходить до кадрів, де сам гасне до порожнечі: розчинення веде ерозія.
func test_smoke_never_plays_the_atlas_own_fade() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var mat := _mat(hit.get_node("Dirt"))
	var top: float = 0.0
	for i in 70:
		_step_all(0.1)
		top = maxf(top, float(mat.get_shader_parameter("frame")))
	assert_true(top <= BattleFx.LAST_FRAME + 1e-4)


## Гаряче ядро — м'який радіальний градієнт (біле → жовте → помаранчеве) зі спадом прозорості,
## звичайне змішування й кольори не вище 1: без білого багатокутника й рожевої облямівки.
## Адитивного спалаху над корпусом (бузкова пляма) нема зовсім.
func test_hot_cores_are_soft_gradients() -> void:
	var code: String = BattleFx._HOT_CODE
	assert_false(code.contains("blend_add"))
	assert_true(code.contains("pow(clamp(1.0 - re, 0.0, 1.0), 1.5)"), "прозорість спадає до краю")
	assert_false(code.contains("* 1.6"), "без пересвіту")
	for w: int in BattleFx.Weapon.values():
		for n: Node in BattleFx.spawn_hit(parent, Vector3(w, 0, 0), w, true).find_children("*", "MeshInstance3D", true, false):
			assert_false(_mat(n).shader.code.contains("blend_add"), "%s" % n.name)


## Розміри влучань, діаметр клуби в метрах: по броні — клуба з даху, по ґрунту — викид землі.
func test_hit_sizes_follow_the_weapon_and_the_target() -> void:
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.AUTOCANNON, true), 3.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.TANK_GUN, true), 5.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.TANK_GUN, false), 6.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.SHELL, false), 12.0)
	assert_eq(BattleFx.hit_cloud_m(BattleFx.Weapon.DRONE, true), 6.0)


## Клуби влучання в броню стоять перед корпусом, а не в ньому: інакше корпус їх закриває.
func test_armour_hit_sprites_are_pulled_towards_the_camera() -> void:
	for n: Node in BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.DRONE, true).find_children("*", "MeshInstance3D", true, false):
		assert_eq(_mat(n).get_shader_parameter("pull"), BattleFx.ARMOUR_PULL)
	for n: Node in BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false).find_children("*", "MeshInstance3D", true, false):
		assert_eq(_mat(n).get_shader_parameter("pull") if _mat(n).get_shader_parameter("pull") != null else 0.0, 0.0)


## Фугас у ґрунті: помаранчево-біле ядро 0,5–0,8 клітинки на два кадри під чорним ядром, над
## бурим ґрунтом; і низьке кільце пилу.
func test_he_ground_burst_layers() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var hot := _mat(hit.get_node("Hot"))
	var size: float = hot.get_shader_parameter("size")
	assert_true(size >= 0.5 and size <= 0.8)
	assert_true(_mat(hit.get_node("Core")).render_priority > hot.render_priority, "ядро — під чорним")
	assert_true(hot.render_priority > _mat(hit.get_node("Dirt")).render_priority)
	var dust := hit.get_node("Dust") as MeshInstance3D
	assert_true(float(_mat(dust).get_shader_parameter("size")) <= 3.0, "радіус пилу не більший за 1,5 клітинки")


## Уламки: неправильні шматки 0,2–0,7 м (не кубики), живуть увесь політ 2v/g і ще 0,6 с —
## падають на землю (тверде зіткнення), лежать і за останні 0,5 с осідають, а не зникають у
## повітрі. Ґрунт снаряда — грудки 0,1–0,4 м. По броні ґрунту нема — й грудок теж.
func test_debris_flies_its_whole_arc_lands_and_settles() -> void:
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	var wreckage := boom.get_node("Debris") as GPUParticles3D
	var pm := wreckage.process_material as ParticleProcessMaterial
	assert_almost_eq(pm.scale_min, 0.2 / 8.0, 1e-6)
	assert_almost_eq(pm.scale_max, 0.7 / 8.0, 1e-6)
	assert_eq(wreckage.amount, 24)
	assert_false(wreckage.draw_pass_1 is BoxMesh, "не кубики")
	var v_max: float = pm.initial_velocity_max * 8.0
	assert_true(wreckage.lifetime >= BattleFx.debris_flight_sec(v_max), "живе весь політ")
	assert_eq(pm.collision_mode, ParticleProcessMaterial.COLLISION_RIGID)
	assert_not_null(boom.get_node("Ground") as GPUParticlesCollisionBox3D)
	var curve: Curve = (pm.scale_curve as CurveTexture).curve
	assert_eq(curve.sample(0.5), 1.0)
	assert_eq(curve.sample(1.0), 0.0)
	assert_almost_eq((1.0 - curve.get_point_position(1).x) * wreckage.lifetime, 0.5, 1e-3, "осідає за 0,5 с")
	var shell: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var clods := shell.get_node("Debris") as GPUParticles3D
	assert_eq(clods.amount, 18)
	assert_almost_eq((clods.process_material as ParticleProcessMaterial).scale_max, 0.4 / 8.0, 1e-7)
	assert_null(shell.get_node_or_null("DebrisStreaks"), "без тонких палиць-смуг")
	var box: AABB = wreckage.draw_pass_1.get_aabb()
	var dims: Array[float] = [box.size.x, box.size.y, box.size.z]
	assert_true(dims.max() / dims.min() <= 2.1, "шматок не довший за 2:1")
	for weapon: BattleFx.Weapon in [BattleFx.Weapon.TANK_GUN, BattleFx.Weapon.DRONE, BattleFx.Weapon.AUTOCANNON]:
		var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, weapon, true)
		assert_eq(hit.find_children("Debris*", "GPUParticles3D", true, false).size(), 0)


## Дим не ховає сусідів: видимі живі юніти поруч (не ціль) стають щитом, над яким усі шари миті
## разом не густіші за 0,45 — сусід бере відтінок диму, а не світиться в дірці; далекі юніти,
## невидимі (поза розвіданим) і ті, що гинуть, — ні.
func test_smoke_spares_visible_neighbours() -> void:
	var views: Array[UnitView] = []
	for pos: Vector3 in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(6, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]:
		var u: UnitView = UnitViewScene.instantiate()
		parent.add_child(u)
		u.position = pos
		views.append(u)
	views[3].visible = false
	views[4].destroyed = true
	var boom: Node3D = BattleFx.spawn_explosion(parent, Vector3.ZERO, 1.5)
	var smoke := _mat(boom.get_node("Smoke"))
	assert_eq(smoke.get_shader_parameter("occ_n"), 1, "лише живий видимий сусід за тайл")
	var occ: Vector4 = smoke.get_shader_parameter("occ0")
	assert_almost_eq(occ.x, 1.0, 1e-6)
	assert_almost_eq(occ.w, BattleFx.OCCLUDE_R, 1e-6)
	assert_eq(smoke.get_shader_parameter("occ1"), Vector4.ZERO)
	assert_true(smoke.shader.code.contains("occ[i].w + %s" % str(BattleFx.OCCLUDE_FEATHER)), "спад розмитий")
	assert_true(BattleFx.OCCLUDE_FEATHER >= 1.0, "спад на тайл — без виїмки в стовпі")
	assert_true(smoke.shader.code.contains("min(a, lim)"), "над сусідом — без м'якого краю за глибиною, що вирізав дірку")
	var ball := _mat(boom.get_node("Ball"))
	assert_eq(ball.get_shader_parameter("occ_floor"), 0.0, "найяскравіша фаза кулі над сусідом вирізана зовсім")
	_step_all(BattleFx.FIREBALL_CUT_SEC + 0.06)
	assert_almost_eq(float(ball.get_shader_parameter("occ_floor")), 0.6, 1e-4, "далі куля над сусідом ≤ 0,6")
	assert_eq(smoke.get_shader_parameter("occ_floor"), 1.0)
	_step_all(0.3)
	assert_eq(smoke.get_shader_parameter("occ_k"), 1.0, "обмеження повне з 0,3 с")
	_assert_total_cap(boom)


func _assert_total_cap(root: Node3D) -> void:
	var clear: float = 1.0
	var n: int = 0
	for q: Node in root.find_children("*", "MeshInstance3D", true, false):
		var cap: Variant = _mat(q).get_shader_parameter("occ_cap")
		if cap != null and int(_mat(q).get_shader_parameter("occ_n")) > 0:
			clear *= 1.0 - float(cap)
			n += 1
	assert_gt(n, 0)
	assert_almost_eq(1.0 - clear, BattleFx.OCCLUDE_TOTAL, 1e-4, "усі шари миті над сусідом — разом 0,45")


## Кілька клубів однієї миті (4 снаряди автогармати, 3–4 клуби пороху) над сусідом разом теж ≤ 0,45.
func test_overlapping_puffs_share_the_cap() -> void:
	var u: UnitView = UnitViewScene.instantiate()
	parent.add_child(u)
	u.position = Vector3(1, 0, 0)
	_assert_total_cap(BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.AUTOCANNON, true))
	_assert_total_cap(BattleFx.spawn_muzzle(parent, Transform3D(Basis(), Vector3(0.2, 0, 0)), BattleFx.Weapon.TANK_GUN, 5))
	assert_almost_eq(BattleFx.occlude_cap(4), 1.0 - pow(0.55, 0.25), 1e-6)


## Хвиля пилу фугаса розбігається низькими клубами по колу й над сусідом лише рідшає — малий окремий
## бюджет, що не з'їдає межу самої хмари.
func test_he_dust_wave_runs_out_and_only_thins_over_a_neighbour() -> void:
	var u: UnitView = UnitViewScene.instantiate()
	parent.add_child(u)
	u.position = Vector3(1, 0, 0)
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3.ZERO, BattleFx.Weapon.SHELL, false)
	var wave: Array[Node] = hit.find_children("Wave*", "MeshInstance3D", true, false)
	assert_gt(wave.size(), 8)
	var start: float = (wave[0] as Node3D).position.length()
	for q: Node in wave:
		assert_almost_eq(float(_mat(q).get_shader_parameter("occ_cap")), BattleFx.WAVE_CAP, 1e-6)
	assert_almost_eq(float(_mat(hit.get_node("Dirt")).get_shader_parameter("occ_cap")), BattleFx.occlude_cap(2), 1e-6, "хмара й ядро — свій бюджет")
	_step_all(BattleFx.DUST_SPREAD_SEC + 0.05)
	var reached: float = Vector2((wave[0] as Node3D).position.x, (wave[0] as Node3D).position.z).length()
	assert_gt(reached, 1.0, "за 0,5 с хвиля дійшла понад клітинку від розриву")
	assert_lt(start, 0.3, "і почалась біля нього")


## Дрібні клуби різняться поворотом і початковим кадром: однакові «капустини» читались штампом.
func test_small_puffs_vary() -> void:
	var hit: Node3D = BattleFx.spawn_hit(parent, Vector3(2, 0, 2), BattleFx.Weapon.AUTOCANNON, true)
	var rolls: Dictionary = {}
	for q: Node in hit.find_children("Puff*", "MeshInstance3D", true, false):
		rolls[_mat(q).get_shader_parameter("roll")] = true
	assert_gt(rolls.size(), 1)
