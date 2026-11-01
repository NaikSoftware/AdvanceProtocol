extends GutTest
## Шар уламків малює рівно те, що спостерігач має право знати (§3.5): уламки лише
## над його розвіданими тайлами, з одним спільним стовпом диму на всі уламки й без
## жодної ознаки власника.

var layer: WreckLayer
var state: BattleState


func before_each() -> void:
	layer = WreckLayer.new()
	add_child_autofree(layer)
	state = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 2, 7)


func _seen(player: int, p: Vector2i) -> void:
	state.vision[player].seen[p.y * 8 + p.x] = 1


func _wreck(p: Vector2i, type_id: int = 5, rounds_left: int = Wrecks.WRECK_ROUNDS, facing: int = 0) -> void:
	state.wrecks.append(Wrecks.Wreck.new(p, type_id, facing, state.turn_clock() + rounds_left * state.player_count))


func test_wreck_is_drawn_only_on_ground_the_observer_has_seen() -> void:
	_wreck(Vector2i(2, 2))
	_wreck(Vector2i(6, 6))
	_seen(0, Vector2i(2, 2))
	layer.rebuild(state, 0)
	assert_eq(layer.wreck_count(), 1)
	assert_not_null(layer.wreck_at(Vector2i(2, 2)))
	assert_null(layer.wreck_at(Vector2i(6, 6)), "уламки на нерозвіданому — донос про бій, якого гравець не бачив")
	assert_eq(layer.column_count(), 1, "стовп диму над нерозвіданим видно через усю мапу — його теж нема")
	assert_eq(layer.fire_count(), 1)


func test_rebuild_for_another_observer_refilters_by_that_observers_seen() -> void:
	_wreck(Vector2i(2, 2))
	_wreck(Vector2i(6, 6))
	_seen(0, Vector2i(2, 2))
	_seen(1, Vector2i(6, 6))
	layer.rebuild(state, 0)
	layer.rebuild(state, 1)
	assert_eq(layer.wreck_count(), 1)
	assert_null(layer.wreck_at(Vector2i(2, 2)))
	assert_not_null(layer.wreck_at(Vector2i(6, 6)))
	assert_eq(layer.column_count(), 1)


func test_remove_takes_the_wreck_its_column_and_its_fire() -> void:
	layer.add(Vector2i(3, 3), 5, 1.0)
	layer.remove(Vector2i(3, 3))
	assert_eq(layer.wreck_count(), 0)
	assert_null(layer.wreck_at(Vector2i(3, 3)))
	assert_eq(layer.column_count(), 0)
	assert_eq(layer.fire_count(), 0)


func test_adding_the_same_tile_twice_keeps_one_wreck() -> void:
	layer.add(Vector2i(3, 3), 5, 1.0)
	layer.add(Vector2i(3, 3), 5, 1.0)
	assert_eq(layer.wreck_count(), 1)
	assert_eq(layer.column_count(), 1)


## Стадія — частка горіння, що лишилась, із двох чисел стану; правила її не читають.
func test_life_is_the_remaining_share_of_burn_time_read_from_state() -> void:
	_wreck(Vector2i(1, 1), 5, Wrecks.WRECK_ROUNDS)
	_wreck(Vector2i(2, 1), 5, 1)
	assert_eq(WreckLayer.life_of(state, state.wrecks[0]), 1.0)
	assert_eq(WreckLayer.life_of(state, state.wrecks[1]), 1.0 / 3.0)


func test_fire_burns_only_in_the_first_round_the_column_stays_until_removal() -> void:
	_wreck(Vector2i(1, 1), 5, Wrecks.WRECK_ROUNDS)
	_wreck(Vector2i(2, 1), 5, 1)
	_seen(0, Vector2i(1, 1))
	_seen(0, Vector2i(2, 1))
	layer.rebuild(state, 0)
	assert_eq(layer.column_count(), 2)
	assert_eq(layer.fire_count(), 1)


func test_no_more_than_eight_columns_and_the_youngest_are_kept() -> void:
	for i in 10:
		layer.add(Vector2i(i % 8, i / 8), 5, 0.05 + 0.09 * float(i))
	assert_eq(layer.wreck_count(), 10, "обмеження — лише на дим, уламки лишаються всі")
	assert_eq(layer.column_count(), WreckLayer.MAX_COLUMNS)
	assert_eq(WreckLayer.MAX_COLUMNS, 8)
	assert_false(layer.has_column(Vector2i(0, 0)), "найстаріший дим гасне першим")
	assert_false(layer.has_column(Vector2i(1, 0)))
	assert_true(layer.has_column(Vector2i(1, 1)))


func test_wreck_is_neutral_burnt_and_carries_no_hp_bar() -> void:
	layer.add(Vector2i(3, 3), 5, 1.0)
	var w: Node3D = layer.wreck_at(Vector2i(3, 3))
	var meshes: Array[MeshInstance3D] = []
	for n: Node in w.find_children("*", "", true, false):
		assert_false(n is Sprite3D or n is Label3D, "уламки не мають HP-бара й підписів")
		if n is MeshInstance3D:
			meshes.append(n)
	# Одна сітка на уламки: один виклик малювання і одна тінь замість трьох-чотирьох (бюджет §8).
	assert_eq(meshes.size(), 1)
	assert_eq(meshes[0].material_override, WreckLayer.burnt_material(), "один спільний обгорілий матеріал")
	var live: Node3D = UnitSilhouettes.build(5, Color.WHITE)
	var verts: int = 0
	for part: Node in live.get_children():
		verts += ((part as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq((meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), verts, "той самий силует, що в живого юніта")
	live.free()


## Уламки читаються відтінком, не формою: вугіль / іржа / попіл ~45/40/15 %, без
## кольору власника.
func test_burnt_material_mixes_char_rust_and_ash_in_the_brief_shares() -> void:
	var mat := WreckLayer.burnt_material()
	assert_true(mat is ShaderMaterial)
	assert_eq(mat.get_shader_parameter("char_share"), 0.45)
	assert_eq(mat.get_shader_parameter("ash_share"), 0.15)
	for c: Color in UnitView.PLAYER_COLORS:
		for k: String in ["char_color", "rust_color", "ash_color"]:
			assert_ne(mat.get_shader_parameter(k), c, "жодного кольору власника")


func _forward(n: Node3D) -> Vector2i:
	var f: Vector3 = -n.basis.z
	return Vector2i(roundi(f.x), roundi(f.z))


## Уламки дивляться туди ж, куди дивився юніт у мить загибелі.
func test_wreck_keeps_the_facing_it_was_given() -> void:
	for d: int in [2, 6, 3]:
		layer.add(Vector2i(d, 1), 5, 1.0, d)
		assert_eq(_forward(layer.wreck_at(Vector2i(d, 1))), Board.DIRS_8[d])


## Перебудова на гейті й після завантаження бере напрям зі стану.
func test_rebuild_draws_the_facing_stored_in_state() -> void:
	_wreck(Vector2i(2, 2), 5, Wrecks.WRECK_ROUNDS, 6)
	_seen(0, Vector2i(2, 2))
	layer.rebuild(state, 0)
	assert_eq(_forward(layer.wreck_at(Vector2i(2, 2))), Board.DIRS_8[6])


## Стадії за частку горіння: вогонь і густий дим, ×0,6 з одним язиком, ×0,3, голі
## уламки. Двоє гравців: шість ходів горіння, частка крокує по 1/6.
func test_stages_thin_the_smoke_then_leave_a_bare_wreck() -> void:
	var lives: Array[float] = [6.0 / 6.0, 4.0 / 6.0, 2.0 / 6.0, 1.0 / 6.0]
	for i in lives.size():
		layer.add(Vector2i(i, 0), 5, lives[i])
	assert_eq(layer.column_opacity(Vector2i(0, 0)), 1.0)
	assert_eq(layer.flame_count(Vector2i(0, 0)), 1)
	assert_eq(WreckLayer.flame_scale_for(lives[0]), 1.0, "перше коло — повне полум'я")
	assert_eq(layer.column_opacity(Vector2i(1, 0)), 0.6)
	assert_eq(layer.flame_count(Vector2i(1, 0)), 1)
	assert_eq(WreckLayer.flame_scale_for(lives[1]), 0.55, "друге коло — те саме джерело, менше")
	assert_eq(layer.column_opacity(Vector2i(2, 0)), 0.3)
	assert_eq(layer.flame_count(Vector2i(2, 0)), 0)
	assert_false(layer.has_column(Vector2i(3, 0)), "останній хід — голі уламки")
	assert_eq(layer.flame_count(Vector2i(3, 0)), 0)
	assert_eq(layer.fire_count(), 2)


## Світло вогню — теплий OmniLight r ≈ 4 м, не більше чотирьох на всю дошку (бюджет §8).
func test_fire_lights_are_capped_at_four() -> void:
	for i in 6:
		layer.add(Vector2i(i, 0), 5, 1.0)
	assert_eq(layer.fire_light_count(), WreckLayer.MAX_FIRE_LIGHTS)
	assert_eq(WreckLayer.MAX_FIRE_LIGHTS, 4)
	layer.remove(Vector2i(0, 0))
	layer.remove(Vector2i(1, 0))
	layer.remove(Vector2i(2, 0))
	assert_eq(layer.fire_light_count(), 3)


func test_wreck_stands_on_its_tile() -> void:
	layer.add(Vector2i(3, 4), 5, 1.0)
	var w: Node3D = layer.wreck_at(Vector2i(3, 4))
	assert_eq(Vector2(w.position.x, w.position.z), Vector2(3.0, 4.0))


## §8: батарея — частина продукту. Дим не живе на TIME (той тримав би кадр
## щокадрово), а крокує таймером 30 разів на секунду, і таймер стоїть, коли диму нема.
func test_smoke_is_stepped_by_a_timer_and_stops_when_nothing_burns() -> void:
	# Крок не частіше за обмеження кадру в спокої (30): вогонь плавний, а кадр однаково
	# скидається, щойно все догоріло.
	assert_eq(WreckLayer.FLIPBOOK_FPS, 30.0)
	assert_true(layer.is_animating() == false, "порожня дошка не анімується")
	layer.add(Vector2i(3, 3), 5, 1.0)
	assert_true(layer.is_animating())
	layer.remove(Vector2i(3, 3))
	assert_false(layer.is_animating())
	for code: String in [WreckLayer.column_shader().code, WreckLayer.FIRE_SHADER.code, WreckLayer._FIRE_CODE]:
		assert_false(code.contains("TIME"), "шейдер диму й вогню не сміє читати TIME")


## Дим іде туди ж, куди й дощ: нахил стовпа — та сама горизонтальна вісь вітру, що й у
## WeatherRig, у SMOKE_LEAN_PER_WIND разів сильніший.
func test_column_leans_along_the_wind_it_is_given() -> void:
	var w := Vector3(0.3, 0.0, -0.3)
	layer.set_wind(w)
	assert_eq(layer.column_lean(), w * WreckLayer.SMOKE_LEAN_PER_WIND)
	layer.set_wind(Vector3.ZERO)
	assert_eq(layer.column_lean(), Vector3.ZERO, "у безвітря стовп стоїть прямо")


func _dead_squad(p: Vector2i, type_id: int = 0) -> Unit:
	var u: Unit = state.add_unit(type_id, 1, p, 2)
	u.hp = 0
	return u


## Загиблі відділення лежать до кінця матчу — зі стану, тож переживають і перебудову, і
## збереження; видно їх лише над розвіданим (§3.5).
func test_fallen_squads_lie_where_they_died_on_seen_ground_only() -> void:
	_dead_squad(Vector2i(2, 2))
	_dead_squad(Vector2i(6, 6))
	var tank: Unit = state.add_unit(5, 1, Vector2i(3, 3), 0)
	tank.hp = 0
	state.add_unit(0, 1, Vector2i(4, 4), 0)
	for p: Vector2i in [Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]:
		_seen(0, p)
	layer.rebuild_fallen(state, 0)
	assert_eq(layer.fallen_count(), 1, "лише загиблі відділення над розвіданим; техніка — уламки")
	var f: MultiMeshInstance3D = layer.fallen_at(Vector2i(2, 2))
	assert_not_null(f)
	assert_eq(f.multimesh.instance_count, UnitView.SQUAD_FIGURES)
	assert_eq(Vector2(f.position.x, f.position.z), Vector2(2.0, 2.0))
	layer.rebuild_fallen(state, 0)
	assert_eq(layer.fallen_count(), 1, "перебудова не множить")



## Другий розігрів поверх першого не губить його коробку й не вішає шар.
func test_second_warm_up_while_warming_is_ignored() -> void:
	layer.warm_up(Vector3.ZERO)
	layer.warm_up(Vector3.ZERO)
	assert_eq(layer.find_children("*", "MeshInstance3D", false, false).size(), 1)
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(1.0)
	assert_false(layer.is_warming())



## Дим і вогонь — запечені флипбуки з assets/vfx, а не заступник.
func test_column_samples_its_atlases_and_fire_matches_its_flag() -> void:
	var col := layer.get_node("Columns") as MultiMeshInstance3D
	var fire := layer.get_node("Fires") as MultiMeshInstance3D
	var cm := col.material_override as ShaderMaterial
	assert_eq((cm.get_shader_parameter("puff_tex") as Texture2D).resource_path, "res://assets/vfx/smoke_column.png")
	assert_eq((cm.get_shader_parameter("thin_tex") as Texture2D).resource_path, "res://assets/vfx/smoke_column_thin.png")
	var fm := fire.material_override as ShaderMaterial
	# Обидва варіанти вогню перевіряються завжди, а не лише активний.
	assert_eq(WreckLayer.FIRE_SHADER.code.count("sampler2D"), 2, "атлас полум'я + глибина")
	assert_eq(WreckLayer._FIRE_CODE.count("sampler2D"), 1, "процедурний: лише глибина")
	if WreckLayer.USE_FLAME02:
		assert_eq((fm.get_shader_parameter("flame_tex") as Texture2D).resource_path, "res://assets/vfx/flame02.png")



## Свіжий стовп росте від корпусу (~6 м/с), а не стоїть на повну висоту одразу; уламки зі
## стану (бій зі збереження, гейт) — давно горять, тож стовп уже повний.
func test_fresh_column_grows_and_rebuilt_column_is_full() -> void:
	assert_eq(WreckLayer.COLUMN_HEIGHT, 40.0 / 8.0)
	assert_eq(WreckLayer.COLUMN_GROW, 6.0 / 8.0)
	layer.add(Vector2i(1, 1), 5, 1.0, 0)
	assert_eq(layer.birth_of(Vector2i(1, 1)), layer.fx_time())
	_wreck(Vector2i(2, 2))
	_seen(0, Vector2i(2, 2))
	layer.rebuild(state, 0)
	assert_eq(layer.birth_of(Vector2i(2, 2)), WreckLayer.LONG_AGO)


## Під кожним стовпом — м'яка тінь; її густота йде від ясності неба в шейдері.
func test_every_column_casts_a_shadow_blob() -> void:
	for i in 3:
		layer.add(Vector2i(i, 0), 5, 1.0, 0)
	var shadows := layer.get_node("ColumnShadows") as MultiMeshInstance3D
	assert_eq(shadows.multimesh.visible_instance_count, layer.column_count())


## Вогонь виходить з погона: два корені обабіч центру даху, а не хмара над корпусом.
func test_flames_sit_on_the_hull_top_at_named_spots() -> void:
	layer.add(Vector2i(3, 3), 5, 1.0, 2)
	var spots: Array[Vector3] = layer.flame_spots(Vector2i(3, 3))
	var w: Node3D = layer.wreck_at(Vector2i(3, 3))
	var hull: Vector3 = UnitSilhouettes.spec(5).hull
	# Корені — на даху башти (0,1 над корпусом): обидва лежать у межах її сліду (0,6 × 0,5
	# корпусу), тож на рівні даху корпусу башта ховала б їх з будь-якого боку.
	var top: float = hull.y - WreckLayer.HULL_SAG + UnitSilhouettes.TURRET_HEIGHT
	# Вогонь виходить з погона в центрі даху: башта стоїть у вогні, і жоден бік не ховає корінь.
	# Два екземпляри обабіч центру: ±0,15 ширини вбік і ±0,1 довжини вздовж корпусу.
	assert_eq(spots.size(), 2)
	var a: Vector3 = (w.transform.affine_inverse() * spots[0]).snappedf(0.01)
	var b: Vector3 = (w.transform.affine_inverse() * spots[1]).snappedf(0.01)
	assert_eq(a, Vector3(-hull.x * 0.15, top, -hull.z * 0.1).snappedf(0.01))
	assert_eq(b, Vector3(hull.x * 0.15, top, hull.z * 0.1).snappedf(0.01))
	assert_eq((w.transform.affine_inverse() * layer.fire_centre(Vector2i(3, 3))).snappedf(0.01), Vector3(0.0, top, 0.0).snappedf(0.01))


## Вогонь вщухає: велике полум'я → мале → без полум'я (дим).
func test_fire_dies_down_over_the_wrecks_life() -> void:
	assert_eq(WreckLayer.flame_scale_for(1.0), 1.0)
	assert_eq(WreckLayer.flame_scale_for(4.0 / 6.0), 0.55)
	assert_eq(WreckLayer.flame_scale_for(2.0 / 6.0), 0.0)


## Іскри вилітають із вогню хаотичними сплесками: кілька штук, поки горить сильно, менше —
## коли слабше, і зовсім нема, коли лишився жар.
func test_embers_fly_while_burning_and_stop_when_smouldering() -> void:
	layer.add(Vector2i(1, 1), 5, 1.0, 0)
	layer.add(Vector2i(2, 2), 5, 4.0 / 6.0, 0)
	layer.add(Vector2i(3, 3), 5, 2.0 / 6.0, 0)
	var big: GPUParticles3D = layer.ember_emitter(Vector2i(1, 1))
	var small: GPUParticles3D = layer.ember_emitter(Vector2i(2, 2))
	assert_eq(big.amount, WreckLayer.EMBERS_HARD)
	assert_eq(small.amount, WreckLayer.EMBERS_SOFT)
	assert_true(big.explosiveness > 0.0, "сплесками, а не рівним струменем")
	assert_null(layer.ember_emitter(Vector2i(3, 3)))
	layer.remove(Vector2i(1, 1))
	assert_null(layer.ember_emitter(Vector2i(1, 1)))



## Вогонь — стовп полум'я з погона: два екземпляри по ≈ 0,4 ширини корпусу, висота ≈ 1,45 ширини
## корпусу; два екземпляри атласу з різною фазою й темпом; HDR-яскравий (понад 1).
func test_fire_is_one_column_sized_from_the_hull() -> void:
	assert_eq(WreckLayer.FLAMES_PER_SPOT, 2)
	var hull: Vector3 = UnitSilhouettes.spec(5).hull
	# Кожен білборд ~0,88 ширини корпусу (≈ 3,2 м у середнього танка); з розносом ±0,15 вони перекриваються в одну масу.
	assert_eq(WreckLayer.flame_width(5), hull.x * 0.88)
	assert_eq(WreckLayer.flame_height(5), hull.x * 1.45)
	var fire := layer.get_node("Fires") as MultiMeshInstance3D
	var mat := fire.material_override as ShaderMaterial
	assert_true(float(mat.get_shader_parameter("gain")) > 1.0)
	# Тіло вогню — два квади на уламок; ширина й висота кожного — з корпусу й стадії.
	layer.add(Vector2i(3, 3), 5, 1.0, 0)
	layer.add(Vector2i(5, 3), 5, 4.0 / 6.0, 0)
	assert_eq(fire.multimesh.visible_instance_count, 4)
	# (Дані екземплярів MultiMesh у безголовому рушії не зберігаються — читаємо через шар.)
	assert_eq(layer.flame_size(Vector2i(3, 3)), Vector2(WreckLayer.flame_width(5), WreckLayer.flame_height(5)))
	assert_eq(layer.flame_size(Vector2i(5, 3)), Vector2(WreckLayer.flame_width(5), WreckLayer.flame_height(5)) * 0.55)
	layer.remove(Vector2i(5, 3))
	var particles: Array[Node] = layer.find_children("*", "GPUParticles3D", true, false)
	assert_eq(particles.size(), 1)
	assert_eq(particles[0], layer.ember_emitter(Vector2i(3, 3)))


## Мирний дим мапи: 1–3 димарі й 1–2 руїни, вибрані за мапою (той самий вибір щоразу); на кожне
## джерело — один суцільний шлейф малої густоти, а не клуби, що виходили залпами. Горить завжди: хати й руїни видимі
## всім, і дим нічого не видає. Анімація не спиняється, поки він є.
func test_hearth_smoke_picks_a_few_faint_columns() -> void:
	var chimneys: Array[Vector3] = [Vector3(1, 1, 1), Vector3(2, 1, 1), Vector3(3, 1, 1), Vector3(4, 1, 1), Vector3(5, 1, 1)]
	var ruins: Array[Vector3] = [Vector3(1, 0, 5), Vector3(2, 0, 5), Vector3(3, 0, 5)]
	for seed in 12:
		layer.set_hearths(chimneys, ruins, seed)
		var pts: Array[Vector3] = layer.hearth_points()
		assert_true(pts.size() <= WreckLayer.HEARTH_MAX, "шлейфів не більше, ніж екземплярів")
		var c: int = pts.filter(func(p: Vector3) -> bool: return p.y > 0.5).size()
		var r: int = pts.size() - c
		assert_true(c >= 1 and c <= 3, "димарів 1–3")
		assert_true(r >= 1 and r <= 2, "руїн 1–2")
	layer.set_hearths(chimneys, ruins, 7)
	var first: Array[Vector3] = layer.hearth_points().duplicate()
	layer.set_hearths(chimneys, ruins, 7)
	assert_eq(layer.hearth_points(), first, "та сама мапа — той самий вибір")
	var mm: MultiMesh = (layer.get_node("Hearths") as MultiMeshInstance3D).multimesh
	assert_eq(mm.visible_instance_count, first.size(), "один суцільний шлейф на джерело, а не низка клубів")
	# AABB вузла — навколо самих шлейфів, а не на всю дошку: прозорий об'єкт сортується за його центром.
	var box: AABB = (layer.get_node("Hearths") as MultiMeshInstance3D).custom_aabb
	for pt in first:
		assert_true(box.has_point(pt + Vector3.UP * 0.5), "AABB охоплює шлейф")
	assert_lt(box.size.x, 40.0, "AABB тісний, а не на всю дошку (2000)")
	# Дані екземплярів headless-рендер не зберігає: перевіряємо густоти, які шар у них записав.
	var dens: Array[float] = layer.hearth_densities()
	assert_eq(dens.size(), first.size())
	var shapes: Array[Vector2] = layer.hearth_shapes()
	assert_eq(shapes.size(), first.size())
	for i in dens.size():
		var ruin: bool = first[i].y < 0.5
		assert_eq(dens[i], WreckLayer.hearth_density(ruin))
		assert_true(dens[i] > 0.0 and dens[i] <= 0.7, "ледь помітний шлейф, не пожежа")
		# Руїна — нижча й вужча біля джерела; димар — повні 14 м від вузької труби.
		assert_eq(shapes[i], Vector2(WreckLayer.RUIN_HEIGHT_SCALE, WreckLayer.RUIN_BASE_SCALE) if ruin else Vector2.ONE)
	assert_true(WreckLayer.RUIN_HEIGHT_SCALE < 1.0 and WreckLayer.RUIN_BASE_SCALE < 1.0 and WreckLayer.RUIN_DENSITY <= WreckLayer.CHIMNEY_DENSITY)
	assert_true(layer.is_animating(), "дим рухається й без уламків")
	assert_eq(layer.hearth_material().get_shader_parameter("rise"), WreckLayer.HEARTH_RISE, "шум густоти пливе вгору зі швидкістю диму")
	assert_false(layer.hearth_material().shader.code.contains("sin("), "хеш без sin: час росте весь матч")
	# Освітлення, об'єм і мокра гілка живуть у шейдері; headless його не малює, тож їхній вигляд
	# (яскравість над ґрунтом, відсутність пульсації) перевіряє tools/smoke_seq.gd у вікні. Тут —
	# лише що шейдер має параметри, які шар виставляє.
	var uniforms: Array[String] = []
	for u: Dictionary in layer.hearth_material().shader.get_shader_uniform_list():
		uniforms.append(String(u["name"]))
	for name: String in ["fx_time", "height", "base_w", "top_w", "rise", "lean"]:
		assert_true(uniforms.has(name), "шейдер диму має uniform %s" % name)
	layer.set_wind(Vector3(0.25, 0, 0))
	assert_eq(layer.hearth_material().get_shader_parameter("lean"), Vector3(0.25, 0, 0) * WreckLayer.SMOKE_LEAN_PER_WIND, "хилиться з вітром, як стовпи уламків")
	layer.rebuild(state, 0)
	assert_eq(layer.hearth_points(), first, "перебудова уламків мирного диму не гасить")


## Полум'я остова не вище за 0,6 клітинки над основою: вище язики м'яко гаснуть і не накривають
## юніт на сусідній клітинці; стовп диму починається не вище за цю верхівку.
func test_wreck_flame_is_capped_below_the_neighbouring_cell() -> void:
	var fires := layer.get_node("Fires") as MultiMeshInstance3D
	var max_h: float = (fires.material_override as ShaderMaterial).get_shader_parameter("max_h")
	assert_true(max_h <= 0.6, "стеля полум'я нижча за сусідню клітинку")
	# Стовп диму найбільшого остова росте не вище за 0,85 стелі полум'я.
	layer.add(Vector2i(3, 3), 5, 1.0)
	var c := Vector2i(3, 3)
	assert_true(layer.smoke_origin(c).y - layer.fire_centre(c).y <= 0.85 * max_h + 1e-5)
	assert_gt(layer.smoke_origin(c).y, layer.fire_centre(c).y, "дим росте з полум'я, не з землі")
	# Як гаснуть язики вище стелі — це вже сам шейдер; у безголовому рушії його не прочитати.
	assert_true(WreckLayer.FIRE_SHADER.code.contains("smoothstep(max_h * 0.7, max_h, v_h)"))


## Контури зон руху — головний інтерфейс (§3.2): вони малюються після диму, вогню й дощу, а не нарівні з ними,
## бо порядок серед рівних залежить від камери.
func test_zone_contour_is_drawn_after_smoke_fire_and_rain() -> void:
	var service: Node = (load("res://game/autoload/match_service.gd") as GDScript).new()
	add_child_autofree(service)
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.setup(load("res://maps/river.tres") as MapData, 2, 1, service)
	var contour: int = ((screen.get_node("%BoardView") as BoardView).call("_contour_material") as Material).render_priority
	var wl: WreckLayer = screen.get("_wreck_layer")
	var rain: Material = (screen.get_node("WeatherRig") as WeatherRig).rain.material_override
	assert_eq(contour, BoardView.CONTOUR_PRIORITY)
	assert_gt(contour, (wl.get_node("Fires") as MultiMeshInstance3D).material_override.render_priority, "вогонь")
	assert_gt(contour, (wl.get_node("Columns") as MultiMeshInstance3D).material_override.render_priority, "дим стовпа")
	assert_gt(contour, wl.hearth_material().render_priority, "мирний дим")
	assert_gt(contour, rain.render_priority, "дощ")
	assert_gt(contour, PropLayer.WIRE_RENDER_PRIORITY, "дроти")
	assert_gt(contour, BattleFx.PRIORITY_CORE + 1, "найгарячіший спалах BattleFx")
