extends GutTest
## Миті повалення опор і парканів: удар і падіння стають у групу митей (їх прибирає передача ходу),
## звільняють себе самі й тримаються бюджету телефона — ≤ 6 викликів малювання і ≤ 80 частинок
## на виклик, бо за один хід танк може зачепити ряд паркану й лінію опор.

var parent: Node3D


func before_each() -> void:
	BattleFx.wetness = 0.0
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
			# Мокра мапа дає більше грудок — бюджет мусить триматись і там.
			BattleFx.wetness = 1.0 if live else 0.0
			# Опора (верх на 10 м) і паркан (верх на 1,8 м).
			out.append(BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 10.0 / 8.0, 0), d, live))
			out.append(BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 1.8 / 8.0, 0), d, live))
			out.append(BattleFx.spawn_topple_land(parent, at, at + Vector3(10.0 / 8.0, 0, 0.3), d, live))
			out.append(BattleFx.spawn_topple_land(parent, at, at + Vector3(2.0 / 8.0, 0, 0), d, live))
			out.append(BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 1.8 / 8.0, 0), d, live, false, Vector3(0.2, 0, 0.1)))
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
	assert_eq((a.get_node("Fine") as GPUParticles3D).seed, (b.get_node("Fine") as GPUParticles3D).seed)
	assert_true((a.get_node("Fine") as GPUParticles3D).use_fixed_seed)


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


## Той, хто кличе, знає, що це опора: низька опора все одно кришиться біля основи, а не
## розлітається парканом; без підказки — за висотою.
func test_pole_flag_overrides_the_height_guess() -> void:
	var at := Vector3(4, 0, 4)
	var guessed: Node3D = BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 2.0 / 8.0, 0), BattleFx.Debris.WOOD, false)
	var told: Node3D = BattleFx.spawn_topple_hit(parent, at, at + Vector3(0, 2.0 / 8.0, 0), BattleFx.Debris.WOOD, false, true)
	assert_eq((guessed.get_node("Fine") as GPUParticles3D).amount, 10, "2 м без підказки — паркан")
	assert_eq((told.get_node("Fine") as GPUParticles3D).amount, 7, "сказано «опора» — опора")


## Мокра мапа: пил стає бурою грязю, грудок більше.
func test_wet_ground_sprays_mud_instead_of_dust() -> void:
	var at := Vector3(6, 0, 1)
	var dry: Node3D = BattleFx.spawn_topple_land(parent, at, at + Vector3(1.25, 0, 0), BattleFx.Debris.CONCRETE, false)
	BattleFx.wetness = 1.0
	var wet: Node3D = BattleFx.spawn_topple_land(parent, at, at + Vector3(1.25, 0, 0), BattleFx.Debris.CONCRETE, false)
	assert_true((wet.get_node("Clods") as GPUParticles3D).amount > (dry.get_node("Clods") as GPUParticles3D).amount)
	var dust: Array[Color] = BattleFx._dust_colours(BattleFx.Debris.CONCRETE, 0.0)
	var mud: Array[Color] = BattleFx._dust_colours(BattleFx.Debris.CONCRETE, 1.0)
	assert_true(mud[0].get_luminance() < dust[0].get_luminance() * 0.5, "мокрий пил — темна грязь")
	var mat := (wet.get_node("Settle") as MultiMeshInstance3D).material_override as ShaderMaterial
	assert_gt(float(mat.get_shader_parameter("fall")), 0.0, "бризка падає назад")
	assert_eq(float((dry.get_node("Settle") as MultiMeshInstance3D).material_override.get_shader_parameter("fall")), 0.0, "сухий пил не падає")


## Клуби пилу стоять рівно вздовж опори (без дірок і груп), старт біжить від основи до верхівки
## за ~0,15 с, а життя різне — хмара рідшає поступово, а не гасне вся разом.
func test_pole_dust_is_even_swept_and_staggered() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n: int = 16
	var half: float = 5.0 / 8.0
	var puffs: Array[Array] = BattleFx.puff_layout(rng, n, Vector3.ZERO, Basis(), Vector3(half, 0.0, 0.0), 1.4, 3.4, 2.6, [Color.WHITE], 0.25, 0.15)
	puffs.sort_custom(func(x: Array, y: Array) -> bool: return (x[0] as Vector3).x < (y[0] as Vector3).x)
	var step: float = 2.0 * half / float(n)
	var lives: Array[float] = []
	for i in n:
		lives.append((puffs[i][2] as Color).g)
		if i > 0:
			assert_between((puffs[i][0] as Vector3).x - (puffs[i - 1][0] as Vector3).x, step * 0.6, step * 1.4, "рівний крок, без груп і дірок")
	assert_true((puffs[0][2] as Color).r < 0.04 and (puffs[n - 1][2] as Color).r > 0.12, "старт від основи до верхівки за ~0,15 с")
	assert_true(lives.max() - lives.min() > 0.4, "життя клуб різне: хвіст згасання")
	var land: Node3D = BattleFx.spawn_topple_land(parent, Vector3(2, 0, 2), Vector3(2 + 10.0 / 8.0, 0, 2), BattleFx.Debris.CONCRETE, false, true)
	assert_between((land.get_node("Settle") as MultiMeshInstance3D).multimesh.instance_count, 14, 20)


## Слід на мокрій землі: темна смуга вздовж відрізка, слабша за пляму під уламками, і лише біля нього.
func test_scuff_darkens_a_band_along_the_line() -> void:
	var scars := ScarMap.new(Vector2i(6, 6))
	scars.stamp_scuff(Vector3(1, 0, 2), Vector3(3, 0, 2))
	var img: Image = scars.image()
	var on: float = img.get_pixel(2 * ScarMap.PX_PER_TILE + 16, 2 * ScarMap.PX_PER_TILE + 16).r
	assert_between(on, 0.2, ScarMap.SCUFF_DARK + 0.01, "на лінії — помітно темніше, але не згарище")
	assert_eq(img.get_pixel(2 * ScarMap.PX_PER_TILE + 16, 4 * ScarMap.PX_PER_TILE).r, 0.0, "за 1,5 тайла — чисто")
