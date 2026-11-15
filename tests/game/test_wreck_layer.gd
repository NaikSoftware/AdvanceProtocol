extends GutTest
## Шар уламків малює рівно те, що спостерігач має право знати (§3.5): уламки лише
## над його розвіданими тайлами, з одним спільним стовпом диму на всі уламки й без
## жодної ознаки власника.

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")

var layer: WreckLayer
var state: BattleState


func before_each() -> void:
	UnitSilhouettes.use_models({})
	layer = WreckLayer.new()
	add_child_autofree(layer)
	state = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 2, 7)


func after_each() -> void:
	UnitSilhouettes.reset_models()


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
	var live: Node3D = UnitSilhouettes.build(5)
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


## Відділення втрачає фігури на трьох тайлах, бо між влучаннями йде далі; повертає юніт.
func _squad_hit_on_the_move(type_id: int = 0, owner: int = 1) -> Unit:
	var u: Unit = state.add_unit(type_id, owner, Vector2i(2, 2), 2)
	for step in 3:
		var before: int = u.hp
		u.hp = [60, 40, 0][step]
		Casualties.record(state, u, before)
		if step < 2:
			u.pos += Vector2i(1, 0)
	return u


## Тіла лежать до кінця матчу там, де кожен упав, — зі стану, тож переживають і перебудову, і
## збереження; видно лише ті, що глядачеві вже показані (§3.5). Техніка тіл не лишає: її лишки — уламки.
func test_bodies_lie_where_each_fell_and_only_shown_ones_are_drawn() -> void:
	var sq: Unit = _squad_hit_on_the_move()
	var tank: Unit = state.add_unit(5, 1, Vector2i(6, 6), 0)
	tank.hp = 0
	Casualties.record(state, tank, 100)
	for p: Vector2i in [Vector2i(2, 2), Vector2i(4, 2), Vector2i(6, 6)]:
		_seen(0, p)
	Casualties.reveal(state, 0)
	layer.rebuild_fallen(state, 0)
	# 1 + 0 (тайл 3,2 не розвіданий) + 2: тіло з нерозвіданого — донос про бій
	assert_eq(layer.fallen_count(), 3)
	_seen(0, Vector2i(3, 2))
	Casualties.reveal(state, 0)
	layer.rebuild_fallen(state, 0)
	assert_eq(layer.fallen_count(), UnitView.SQUAD_FIGURES, "чотири тіла на трьох тайлах")
	assert_eq(layer.fallen_meshes().size(), 1, "один набір — один MultiMesh, один виклик малювання")
	var mi: MultiMeshInstance3D = layer.fallen_meshes()[0]
	assert_eq(mi.multimesh.instance_count, UnitView.SQUAD_FIGURES)
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(mi.layers, 1 << (UnitView.UNIT_LAYER - 1))
	var cells: Dictionary = {}
	for xf: Transform3D in layer.body_transforms():
		cells[Vector2i(roundi(xf.origin.x), roundi(xf.origin.z))] = true
	assert_eq(cells.keys().size(), 3, "тіла на трьох тайлах")
	layer.rebuild_fallen(state, 0)
	assert_eq(layer.fallen_count(), UnitView.SQUAD_FIGURES, "перебудова не множить")
	assert_eq(layer.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Bodies_")).size(), 1)
	assert_eq(sq.hp, 0)


## Тіло лежить не на місці стоячого: на кільці довкола середини тайла, зі сталим за сідом зсувом і поворотом,
## довгою віссю щонайменше 35° від погляду камери, а різні тіла — не однаковим строєм.
func test_bodies_lie_off_the_standing_slots_and_across_the_view() -> void:
	var cam: float = deg_to_rad(IsoCameraRig.YAW_DEGREES)
	var headings: Dictionary = {}
	for unit_id in 6:
		for facing in 8:
			var b := Casualties.Body.new(unit_id, Vector2i(3, 3), 0, 0, facing, 0, 4)
			for slot in 4:
				var xf: Transform3D = WreckLayer.body_transform(b, slot)
				assert_eq(xf, WreckLayer.body_transform(b, slot), "те саме тіло лягає однаково")
				var r: float = Vector2(xf.origin.x - 3.0, xf.origin.z - 3.0).length()
				assert_between(r, WreckLayer.BODY_RING_MIN - 0.0001, WreckLayer.BODY_RING_MAX + 0.0001, "довкола стоячих місць і в межах тайла")
				var axis: Vector3 = xf.basis.z
				var off: float = absf(wrapf(atan2(axis.x, axis.z) - cam, -PI * 0.5, PI * 0.5))
				assert_gte(off, WreckLayer.BODY_VIEW_MIN - 0.0001, "довга вісь не вздовж погляду")
				headings[snappedf(atan2(axis.x, axis.z), 0.05)] = true
	assert_gt(headings.size(), 20, "тіла лягають по-різному, а не строєм")


## Модель загиблого — окрема сітка (лежить на боці) під матеріалом простого бійця з `fallen`: один на набір.
func test_model_bodies_use_the_body_mesh_and_one_fallen_material_per_set() -> void:
	var body: ArrayMesh = UnitModelFixture.mesh(Vector3(0.06, 0.05, 0.225))
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier(), 1: UnitModelFixture.tube_soldier(), UnitSilhouettes.BODY_KEY: body})
	_squad_hit_on_the_move(0)
	var other: Unit = state.add_unit(1, 1, Vector2i(5, 5), 0)
	other.hp = 0
	var ev: Array[Events.BattleEvent] = Casualties.record(state, other, 100)
	for p: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]:
		_seen(0, p)
	Casualties.reveal(state, 0)
	layer.rebuild_fallen(state, 0)
	assert_eq(layer.fallen_meshes().size(), 1)
	var mi: MultiMeshInstance3D = layer.fallen_meshes()[0]
	assert_same(mi.multimesh.mesh, body, "загиблий — своя сітка, не стоячий боєць плазом")
	assert_same(mi.material_override, UnitSilhouettes.fallen_material(1))
	assert_true((mi.material_override as ShaderMaterial).get_shader_parameter("fallen"), "шейдер темнить загиблих")
	assert_lte((mi.material_override as ShaderMaterial).get_shader_parameter("specular"), 0.1, "тіло без відблиску")
	assert_eq((mi.material_override as ShaderMaterial).get_shader_parameter("roughness"), 1.0)
	assert_ne(UnitSilhouettes.model_material(0).get_shader_parameter("fallen"), true, "живі — ні")
	assert_same((mi.material_override as ShaderMaterial).get_shader_parameter("albedo_tex"),
		UnitSilhouettes.model_material(0).get_shader_parameter("albedo_tex"), "атлас простого бійця")
	layer.add_body((ev[0] as Events.FiguresFell).body)
	assert_eq(layer.fallen_count(), 2 * UnitView.SQUAD_FIGURES)
	assert_eq(layer.fallen_meshes().size(), 1, "штурмовики лягають простим бійцем: той самий MultiMesh")
	assert_eq(layer.fallen_meshes()[0].multimesh.instance_count, 2 * UnitView.SQUAD_FIGURES)


## Тіла знищеного відділення лежать у різних позах (на боці, ниць, на спині), а одне — на краю плями.
func test_destroyed_squad_bodies_take_several_poses_and_one_lies_at_the_scorch_edge() -> void:
	var meshes: Dictionary = {0: UnitModelFixture.soldier()}
	for pose in UnitSilhouettes.BODY_POSES.size():
		meshes[UnitSilhouettes.BODY_KEY + pose * 10] = UnitModelFixture.mesh(Vector3(0.06, 0.05 + 0.01 * pose, 0.225))
	UnitSilhouettes.use_models(meshes)
	assert_eq(UnitSilhouettes.body_pose_count(0), 3)
	var poses: Dictionary = {}
	for unit_id in 8:
		var b := Casualties.Body.new(unit_id, Vector2i(3, 3), 0, 0, unit_id % 8, 0, 4)
		for slot in 4:
			poses[WreckLayer.body_pose_index(b, slot, 3)] = true
		var edge: Vector3 = WreckLayer.body_transform(b, 0).origin
		assert_almost_eq(Vector2(edge.x - 3.0, edge.z - 3.0).length(), WreckLayer.BODY_RING_SCORCH, WreckLayer.BODY_JITTER * 1.5, "одне тіло — на краю плями")
	assert_eq(poses.size(), 3, "три пози, не парад")
	var sq: Unit = state.add_unit(0, 1, Vector2i(2, 2), 2)
	sq.hp = 0
	Casualties.record(state, sq, 100)
	_seen(0, Vector2i(2, 2))
	Casualties.reveal(state, 0)
	layer.rebuild_fallen(state, 0)
	assert_gt(layer.fallen_meshes().size(), 1, "пози — окремі MultiMesh одного матеріалу")
	for mi: MultiMeshInstance3D in layer.fallen_meshes():
		assert_same(mi.material_override, UnitSilhouettes.fallen_material(1))


## Без моделі загиблі — темні коробки плазом.
func test_box_bodies_lie_flat_in_the_fallen_colour() -> void:
	_squad_hit_on_the_move()
	for p: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]:
		_seen(0, p)
	Casualties.reveal(state, 0)
	layer.rebuild_fallen(state, 0)
	var mi: MultiMeshInstance3D = layer.fallen_meshes()[0]
	assert_true(mi.multimesh.mesh is BoxMesh)
	assert_eq((mi.material_override as StandardMaterial3D).albedo_color, UnitSilhouettes.FALLEN_COLOR)
	for xf: Transform3D in layer.body_transforms():
		assert_almost_eq(absf(xf.basis.y.normalized().y), 0.0, 0.0001, "коробка лежить")


## Тіло, показане глядачеві, лишається: відділення, що повернулося в незнайдений будинок на тому самому
## тайлі, його не ховає (§3.5); тіла, ще не показані, шар не малює.
func test_a_shown_body_stays_when_its_squad_hides_again() -> void:
	state = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 3, 7)
	state.board.set_kind(Vector2i(2, 2), Terrain.Kind.BUILDING)
	_seen(2, Vector2i(2, 2))
	var sq: Unit = state.add_unit(0, 1, Vector2i(2, 2), 0)
	sq.hp = 60
	Casualties.record(state, sq, 100)
	layer.rebuild_fallen(state, 2)
	assert_eq(layer.fallen_count(), 0, "відділення ховається на тайлі — тіло його виказало б")
	sq.pos = Vector2i(3, 2)
	Casualties.reveal(state, 2)
	layer.rebuild_fallen(state, 2)
	assert_eq(layer.fallen_count(), 1)
	sq.pos = Vector2i(2, 2)
	Casualties.reveal(state, 2)
	layer.rebuild_fallen(state, 2)
	assert_eq(layer.fallen_count(), 1, "повернулося в будинок — показане тіло лишається")


## Шар тіл перекладає лише перетворення екземплярів, а не вершини: 40 тіл — швидко.
func test_forty_bodies_rebuild_fast() -> void:
	for i in 10:
		var u: Unit = state.add_unit(i % 2, 1, Vector2i(i % 8, i / 8 + 4), i % 8)
		u.hp = 0
		Casualties.record(state, u, 100)
	for y in 8:
		for x in 8:
			_seen(0, Vector2i(x, y))
	Casualties.reveal(state, 0)
	var t0: int = Time.get_ticks_usec()
	layer.rebuild_fallen(state, 0)
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	assert_eq(layer.fallen_count(), 40)
	# перекладання лише перетворень займає ~0,4 мс; межа — з запасом на повільну машину, але нижча за
	# 50+ мс перезбирання сітки вершинами, тож повернення до нього ловить
	assert_lt(ms, 30.0, "40 тіл за %.1f мс" % ms)


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
	# Верх шлейфу на повну висоту при найбільшому нахилі вітром в усі боки лишається всередині AABB.
	var reach: float = WreckLayer.hearth_reach()
	for h in first.size():
		var top_y: float = WreckLayer.HEARTH_HEIGHT * layer.hearth_shapes()[h].x
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				assert_true(box.has_point(first[h] + Vector3(sx * reach * 0.99, top_y, sz * reach * 0.99)), "верх шлейфу при найбільшому нахилі в AABB")
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
	# Шум пливе вгору зі швидкістю диму: за секунду зсув — підйом на тайл, помножений на кратність шуму.
	var step: Vector3 = WreckLayer.plume_scroll(11.0) - WreckLayer.plume_scroll(10.0)
	assert_almost_eq(step.z, WreckLayer.HEARTH_RISE * WreckLayer.PLUME_SCROLL_RATES.z, 1e-6, "край пливе вгору зі швидкістю диму")
	var lstep: Vector4 = WreckLayer.plume_layer_scroll(11.0) - WreckLayer.plume_layer_scroll(10.0)
	for k in 4:
		# Шар k: клуб висотою sc²/ref метрів, тож за секунду підйому на 0,8 м — 8·ref/sc² клітинок на тайл.
		var sc_k: float = WreckLayer.PLUME_LAYER_SC[k]
		assert_almost_eq(WreckLayer.plume_layer_rate(k), 8.0 * WreckLayer.PLUME_LAYER_REF / (sc_k * sc_k), 1e-9)
		assert_almost_eq(lstep[k], WreckLayer.HEARTH_RISE * WreckLayer.plume_layer_rate(k), 1e-6, "кожен шар клубів пливе рівно зі швидкістю диму")
		if k > 0:
			assert_gt(sc_k, WreckLayer.PLUME_LAYER_SC[k - 1], "шари клубів ростуть від труби вгору")
	# Шари обрамляють розмір клубів по всій висоті: від труби (0,8–0,9 м) до верху (2,4 м).
	assert_true(WreckLayer.PLUME_LAYER_SC.x <= 0.9 and is_equal_approx(WreckLayer.PLUME_LAYER_SC.w, 2.4))
	# Через години гри зсуви лишаються в межах періоду шуму: великі числа в шейдері розсипали шлейф на голки.
	for t: float in [0.0, 3600.0, 10800.0, 86400.0]:
		var sc: Vector3 = WreckLayer.plume_scroll(t)
		var ls: Vector4 = WreckLayer.plume_layer_scroll(t)
		for k in 3:
			assert_true(sc[k] >= 0.0 and sc[k] < WreckLayer.PLUME_NOISE_PERIOD, "зсув шуму згорнуто за періодом (t=%s)" % t)
		for k in 4:
			assert_true(ls[k] >= 0.0 and ls[k] < WreckLayer.PLUME_NOISE_PERIOD, "зсув шару згорнуто за періодом (t=%s)" % t)
	var code: String = layer.hearth_material().shader.code
	assert_true(code.contains("const float PERIOD = %.1f;" % WreckLayer.PLUME_NOISE_PERIOD), "період шуму в шейдері той самий, що й у згортці")
	assert_true(code.contains("p = mod(p, PERIOD);") and code.contains("i = mod(i, PERIOD);"), "шум згорнуто за періодом, і клітинка теж — mod у float інколи дає рівно PERIOD")
	assert_false(code.contains("fx_time"), "шлейф не бачить часу матчу напряму — лише згорнуті зсуви")
	# Октави шуму мусять мати цілу кратність, інакше згортка зсуву розірве їх на стику періоду.
	var re := RegEx.new()
	re.compile("vn\\(p \\* ([0-9.]+)")
	var octaves: Array[RegExMatch] = re.search_all(code)
	assert_eq(octaves.size(), 2, "дві вищі октави клубів")
	for m: RegExMatch in octaves:
		var ratio: float = float(m.get_string(1))
		assert_eq(ratio, roundf(ratio), "кратність октави %s ціла" % m.get_string(1))
	assert_false(layer.hearth_material().shader.code.contains("sin("), "хеш без sin: час росте весь матч")
	# Освітлення, об'єм і мокра гілка живуть у шейдері; headless його не малює, тож їхній вигляд
	# (яскравість над ґрунтом, відсутність пульсації) перевіряє tools/smoke_seq.gd у вікні. Тут —
	# лише що шейдер має параметри, які шар виставляє.
	var uniforms: Array[String] = []
	for u: Dictionary in layer.hearth_material().shader.get_shader_uniform_list():
		uniforms.append(String(u["name"]))
	for name: String in ["scroll", "layer_scroll", "layer_sc", "layer_ref", "height", "base_w", "top_w", "lean"]:
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


## Рух стовпа й вогню читає лише згорнуті годинники: за великого fx_time (доба гри) кадр атласу
## вогню губив точність і полум'я йшло смугами. Згортка без стрибка — коли кожна швидкість робить за
## період цілу кількість обертів чи циклів атласу.
func test_column_and_fire_clocks_stay_bounded_and_wrap_without_a_jump() -> void:
	for t: float in [0.0, 3600.0, 10800.0, 86400.0, 864000.0]:
		assert_true(WreckLayer.column_clock(t) >= 0.0 and WreckLayer.column_clock(t) < WreckLayer.COLUMN_CLOCK_SEC)
		assert_true(WreckLayer.column_phase(t) >= 0.0 and WreckLayer.column_phase(t) < 1.0)
		assert_true(WreckLayer.fire_loop_time(t) >= 0.0 and WreckLayer.fire_loop_time(t) < WreckLayer.fire_loop_sec())
	# Фаза клуби — час у частках життя клуби, за модулем 1.
	assert_almost_eq(WreckLayer.column_phase(100.0), fposmod(100.0 / WreckLayer.PLUME_LIFE_SEC, 1.0), 1e-9)
	# Атлас крокує з темпом таймера, і за період темп k/FIRE_TEMPO_STEPS проходить рівно k циклів атласу —
	# але лише якщо шейдер справді округлює темп до кроку 1/FIRE_TEMPO_STEPS (перевірка нижче).
	assert_eq(layer.get("_fire_mat").get_shader_parameter("play_fps"), WreckLayer.FLIPBOOK_FPS)
	var column: String = WreckLayer.column_shader().code
	var fire: String = WreckLayer.FIRE_SHADER.code
	# Кутові швидкості стовпа кратні COLUMN_RATE_STEP: за COLUMN_CLOCK_SEC — ціла кількість обертів.
	var re := RegEx.new()
	re.compile("clock \\* ([0-9.]+)")
	var rates: Array[RegExMatch] = re.search_all(column)
	assert_eq(rates.size(), 4, "дрейф уздовж двох осей і кипіння краю вздовж двох")
	for m: RegExMatch in rates:
		var steps: float = float(m.get_string(1)) / WreckLayer.COLUMN_RATE_STEP
		assert_almost_eq(steps, roundf(steps), 1e-6, "швидкість %s кратна кроку" % m.get_string(1))
	assert_true(column.contains("round((sd - 0.5) * 0.4 / rate_step) * rate_step * clock"), "обертання клуби кратне кроку")
	# fx_time лишається лише для віку (різниця з народженням), ні на що не множиться.
	for code: String in [column, fire]:
		assert_false(code.contains("fx_time *"), "час матчу не множиться на швидкість")
	assert_true(fire.contains("mod(i, n)"), "шум тремтіння періодичний")
	assert_true(fire.contains("round((0.8 + 0.4 * h1(sd * 17.0)) * tempo_steps) / tempo_steps"), "темп атласу кратний 1/tempo_steps")
	assert_true(fire.contains("v_frame = mod(loop_time * play_fps * tempo"), "кадр атласу — від згорнутого годинника й округленого темпу")
	assert_false(column.contains("uniform float rise"), "шлях клуб — лише зі згорнутої фази")
	# Процедурний вогонь (поки вимкнений прапорцем) теж не бачить сирого часу матчу й не хешує через sin.
	assert_true(WreckLayer._FIRE_CODE.contains("float t = proc_time"))
	assert_false(WreckLayer._FIRE_CODE.contains("fx_time +") or WreckLayer._FIRE_CODE.contains("sin("))
	assert_eq(layer.get("_fire_mat").get_shader_parameter("loop_sec"), WreckLayer.fire_loop_sec())
	assert_eq(layer.get("_column_mat").get_shader_parameter("rate_step"), WreckLayer.COLUMN_RATE_STEP)


## Уламок моделі — та сама сітка під обгорілим матеріалом, осіла на HULL_SAG.
func test_model_wreck_reuses_the_model_mesh_under_burnt_material() -> void:
	var model: ArrayMesh = UnitModelFixture.vehicle(5)
	UnitSilhouettes.use_models({5: model})
	var root: Node3D = WreckLayer.build_wreck(Vector2i(2, 2), 5, 0)
	var body := root.get_node("Body") as MeshInstance3D
	assert_same(body.mesh, model)
	assert_same(body.material_override, WreckLayer.burnt_material())
	assert_almost_eq(body.position.y, -WreckLayer.HULL_SAG, 0.0001)
	assert_eq(root.get_child_count(), 1)
	root.free()


## Уламок несе набір власника: модель і рядок набору, не набору 0 (власник 4 — набір 1).
func test_wreck_of_owner_four_uses_set_one_model_and_spec() -> void:
	var row: Dictionary = {"hull": Vector3(0.5, 0.2, 0.9), "barrel": 0.7, "wheel": 0.05, "extras": [&"turret"]}
	var m1: ArrayMesh = UnitModelFixture.mesh(row.hull)
	UnitSilhouettes.use_models({5: UnitModelFixture.vehicle(5), Vector2i(1, 5): m1})
	UnitSilhouettes.use_set_specs({1: {5: row}})
	var set_id: int = UnitSilhouettes.set_of(4)
	var root: Node3D = WreckLayer.build_wreck(Vector2i(2, 2), 5, 0, set_id)
	assert_same((root.get_node("Body") as MeshInstance3D).mesh, m1)
	root.free()
	layer.add(Vector2i(3, 3), 5, 1.0, 0, set_id)
	assert_eq(layer.flame_size(Vector2i(3, 3)), Vector2(WreckLayer.flame_width(5, 1), WreckLayer.flame_height(5, 1)))
	assert_eq(WreckLayer.flame_width(5, 1), row.hull.x * 0.88)
	_wreck(Vector2i(4, 4))
	state.wrecks[-1].owner = 4
	_seen(0, Vector2i(4, 4))
	layer.rebuild(state, 0)
	assert_almost_eq(layer.flame_size(Vector2i(4, 4)).x, WreckLayer.flame_width(5, 1), 0.00001, "перебудова зі стану бере набір власника")


## Гармати й інженерна машина лишають уламок із власної моделі, а не з коробок: тип без вежі й дула теж будується.
func test_shipped_gun_and_engineer_models_make_wrecks() -> void:
	UnitSilhouettes.reset_models()
	for id: int in [9, 10, 11]:
		var root: Node3D = WreckLayer.build_wreck(Vector2i(2, 2), id, 0)
		assert_not_null(UnitSilhouettes.model_mesh(id, 0), "модель типу %d" % id)
		assert_same((root.get_node("Body") as MeshInstance3D).mesh, UnitSilhouettes.model_mesh(id, 0), "уламок — сама модель типу %d" % id)
		root.free()


## Корінь полум'я лежить на металі моделі: поряд (по землі й по висоті) є вершина сітки, а не повітря над порожньою землею.
func test_flame_roots_of_guns_and_engineer_sit_on_model_metal() -> void:
	UnitSilhouettes.reset_models()
	for id: int in [9, 10, 11]:
		layer.add(Vector2i(3 + id, 3), id, 1.0, 0)
		var node: Node3D = layer.wreck_at(Vector2i(3 + id, 3))
		var verts: PackedVector3Array = UnitSilhouettes.model_mesh(id).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for spot: Vector3 in layer.flame_spots(Vector2i(3 + id, 3)):
			var local: Vector3 = node.transform.affine_inverse() * spot
			# промінь униз від кореня: найвища поверхня моделі під ним не далі як 0,15 м від кореня
			var idx: PackedInt32Array = UnitSilhouettes.model_mesh(id).surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			var lift: float = node.get_child(0).position.y
			var from := Vector3(local.x, local.y + 1.0, local.z)
			var hit_y: float = -INF
			for t in range(0, idx.size(), 3):
				var q: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, verts[idx[t]] + Vector3(0, lift, 0),
						verts[idx[t + 1]] + Vector3(0, lift, 0), verts[idx[t + 2]] + Vector3(0, lift, 0))
				if q != null:
					hit_y = maxf(hit_y, (q as Vector3).y)
			assert_gt(hit_y, -INF, "під коренем полум'я типу %d є модель" % id)
			assert_lte(absf(local.y - hit_y), 0.019, "корінь полум'я типу %d лежить на металі (0,15 м)" % id)


const CrewLegal := preload("res://tools/crew_body_legal.gd")


## Дошки для перевірки місця тіл розрахунку: суша й вода з одного, двох боків, кутова, оточення.
func _crew_boards() -> Dictionary:
	var out: Dictionary = {}
	out["поле"] = Board.create(8, 8, Terrain.GroundState.DRY)
	var cases: Dictionary = {
		"берег зі сходу": [Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4)],
		"берег з півдня": [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
		"кут": [Vector2i(4, 4)],
		"два береги": [Vector2i(4, 3), Vector2i(2, 3)],
		"оточено": [Vector2i(4, 3), Vector2i(2, 3), Vector2i(3, 4), Vector2i(3, 2)],
	}
	for name: String in cases:
		var b: Board = Board.create(8, 8, Terrain.GroundState.DRY)
		for w: Vector2i in cases[name]:
			b.set_kind(w, Terrain.Kind.WATER)
		out[name] = b
	return out


## Сітка землі уламка не порожня й збігається з прямим перебором: інакше кожна перевірка «не під уламком» минала б
## сама собою (Packed* у масиві віддається копією, і додавання через `as` губиться).
func test_ground_index_is_not_empty_and_agrees_with_brute_force() -> void:
	UnitSilhouettes.reset_models()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for id: int in [9, 10]:
		var index: Dictionary = CrewLegal.ground_index(CrewLegal.wreck_tris(id, 0, 2, Vector2.ZERO))
		assert_gt(CrewLegal.indexed_count(index), 100, "у сітці землі типу %d є трикутники" % id)
		var hits: int = 0
		for n in 300:
			var mid := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
			var long := Vector2.from_angle(rng.randf() * TAU)
			var fast: bool = CrewLegal.rect_hits(mid, long, 0.11, 0.095, index)
			assert_eq(fast, CrewLegal.rect_hits_brute(mid, long, 0.11, 0.095, index), "сітка й перебір за одним прямокутником")
			hits += int(fast)
		assert_gt(hits, 20, "серед випадкових прямокутників є й такі, що влучають в уламок")
		assert_lt(hits, 280, "і такі, що ні")


## Таблиця дозволених місць у рядках — та, що складає tools/crew_body_table.gd: перерахунок збігається. Застаріла, коли
## змінилась модель гармати чи місця: тоді запустити інструмент і внести рядки.
func test_the_stored_crew_body_table_is_current() -> void:
	UnitSilhouettes.reset_models()
	for id: int in [9, 10]:
		var row: Dictionary = UnitSilhouettes.spec(id)
		assert_gte((row.body_spots as Array).size(), 8, "місць у рядку типу %d" % id)
		var fresh: PackedInt32Array = CrewLegal.legal_masks(id, 0)
		assert_eq(Array(fresh), row.body_legal, "таблиця типу %d: tools/crew_body_table.gd -- table" % id)


## Кожне дозволене місце — поза уламком, яким його малює `build_wreck` (справжній нахил у різних тайлах), на тайлі й на
## виду: уламок, що ближче до камери, закриває не більше MAX_COVER прямокутника. Таблиця не порожня й не суцільна.
func test_every_legal_crew_spot_is_clear_of_the_wreck_as_built_and_visible() -> void:
	UnitSilhouettes.reset_models()
	for id: int in [9, 10]:
		var row: Dictionary = UnitSilhouettes.spec(id)
		var spots: Array = row.body_spots
		var legal_total: int = 0
		var illegal_total: int = 0
		for facing in 8:
			var mask: int = int(row.body_legal[facing])
			for tile in [Vector2i(1, 1), Vector2i(2, 5), Vector2i(3, 3), Vector2i(6, 2), Vector2i(7, 7)]:
				var node: Node3D = WreckLayer.build_wreck(tile, id, facing)
				var mesh: ArrayMesh = (node.get_node("Body") as MeshInstance3D).mesh
				var a: Array = mesh.surface_get_arrays(0)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var tris := PackedVector3Array()
				for k in idx:
					tris.append(node.basis * (v[k] + (node.get_node("Body") as Node3D).position))
				var index: Dictionary = CrewLegal.ground_index(tris)
				var bufs: Array = [CrewLegal.silhouette(tris, IsoCameraRig.PITCH_NEAR_DEG), CrewLegal.silhouette(tris, IsoCameraRig.PITCH_FAR_DEG)]
				node.free()
				for i in spots.size():
					if mask & (1 << i) == 0:
						continue
					var r: Array = CrewLegal.spot_rect(spots[i], facing)
					var where: String = "тип %d, напрям %d, місце %d, тайл %s" % [id, facing, i, tile]
					assert_false(CrewLegal.rect_hits(r[0], r[1], WreckLayer.BODY_LENGTH * 0.5, WreckLayer.BODY_WIDTH * 0.5, index), "поза уламком, " + where)
					assert_lte(maxf(CrewLegal.covered(r[0], r[1], bufs[0], IsoCameraRig.PITCH_NEAR_DEG), CrewLegal.covered(r[0], r[1], bufs[1], IsoCameraRig.PITCH_FAR_DEG)),
							CrewLegal.MAX_COVER, "на виду, " + where)
			for i in spots.size():
				if mask & (1 << i) != 0:
					legal_total += 1
				else:
					illegal_total += 1
			assert_gte(legal_total, 3, "дозволені місця є, тип %d" % id)
		assert_gt(illegal_total, 0, "таблиця не суцільна, тип %d" % id)


## Тіла розрахунку знищеної гармати на дошках: у тайлі, не за воду з боку, де вона є, не на уламку, двоє — не одне на
## одному, а за можливості — з відстанню й кутом. Кому місця нема, того не покладено; на полі кладуться обоє.
func test_crew_bodies_follow_the_rules_on_land_and_shore() -> void:
	UnitSilhouettes.reset_models()
	WreckLayer.clear_deck_cache()
	var boards: Dictionary = _crew_boards()
	var laid_total: Dictionary = {}
	for id: int in [9, 10]:
		var plain: Dictionary = {}
		for facing in 8:
			plain[facing] = CrewLegal.ground_index(CrewLegal.wreck_tris(id, 0, facing, Vector2.ZERO))
		for bname: String in boards:
			var board: Board = boards[bname]
			for unit_id in [3, 7, 11, 19]:
				for facing in 8:
					var b := Casualties.Body.new(unit_id, Vector2i(3, 3), 0, id, facing, 0, Casualties.CREW_FIGURES)
					var centre: Vector3 = IsoCameraRig.cell_to_world(b.pos)
					var dirs: Array[Vector2i] = WreckLayer._water_dirs(board, b.pos)
					var where: String = "тип %d, юніт %d, напрям %d, %s" % [id, unit_id, facing, bname]
					var rects: Array = []
					for slot in Casualties.CREW_FIGURES:
						var xf: Transform3D = WreckLayer.body_transform(b, slot, board, [])
						if not WreckLayer.body_is_laid(xf):
							continue
						var mid: Vector3 = WreckLayer.body_centre(xf) - centre
						var long := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
						var wide := Vector2(-long.y, long.x)
						for sl: float in [-1.0, 1.0]:
							for sw: float in [-1.0, 1.0]:
								var corner: Vector2 = Vector2(mid.x, mid.z) + long * (WreckLayer.BODY_LENGTH * 0.5 * sl) + wide * (WreckLayer.BODY_WIDTH * 0.5 * sw)
								assert_lte(absf(corner.x), 0.5, "кут у тайлі по x, " + where)
								assert_lte(absf(corner.y), 0.5, "кут у тайлі по z, " + where)
								assert_true(WreckLayer._water_ok(corner, dirs), "кут не за воду, " + where)
						assert_false(CrewLegal.rect_hits(Vector2(mid.x, mid.z), long, WreckLayer.BODY_LENGTH * 0.5, WreckLayer.BODY_WIDTH * 0.5, plain[facing]), "не під уламком, " + where)
						rects.append([Vector2(mid.x, mid.z), long])
					if bname == "поле":
						assert_eq(rects.size(), 2, "на полі лягають обоє, " + where)
					laid_total[bname] = int(laid_total.get(bname, 0)) + rects.size()
					if rects.size() == 2:
						assert_false(WreckLayer.body_rects_overlap(rects[0][0], rects[0][1], rects[1][0], rects[1][1]), "одне на одному, " + where)
						assert_gte((rects[0][0] as Vector2).distance_to(rects[1][0]), WreckLayer.CREW_MIN_APART - 0.0001, "середини, " + where)
						var apart: float = absf(wrapf(atan2(rects[0][1].x, rects[0][1].y) - atan2(rects[1][1].x, rects[1][1].y), -PI * 0.5, PI * 0.5))
						assert_gte(apart, WreckLayer.CREW_MIN_TURN - 0.0001, "кути, " + where)
	for bname: String in boards:
		if bname != "оточено":
			assert_gt(int(laid_total.get(bname, 0)), 20, "на дошці «%s» тіла лягають" % bname)


## Тіло не лягає у воду з боку, де вона є, навіть коли місць лишається мало: з водою з чотирьох боків їх може
## не лишитись зовсім, і тоді тіл нема. Інших запасних місць немає.
func test_a_crew_body_without_a_legal_spot_is_not_laid_at_all() -> void:
	UnitSilhouettes.reset_models()
	var board: Board = _crew_boards()["оточено"]
	var laid: int = 0
	for unit_id in [3, 7, 11, 19, 23]:
		for facing in 8:
			var b := Casualties.Body.new(unit_id, Vector2i(3, 3), 0, 10, facing, 0, Casualties.CREW_FIGURES)
			for slot in Casualties.CREW_FIGURES:
				var xf: Transform3D = WreckLayer.body_transform(b, slot, board, [])
				if WreckLayer.body_is_laid(xf):
					laid += 1
					var mid: Vector3 = WreckLayer.body_centre(xf) - IsoCameraRig.cell_to_world(b.pos)
					assert_lte(absf(mid.x), WreckLayer.WATER_REACH, "середина тіла не за воду")
					assert_lte(absf(mid.z), WreckLayer.WATER_REACH, "середина тіла не за воду")
	assert_lt(laid, 5 * 8 * 2, "не кожне місце знайшлось: води з усіх боків")


## Уламок на мосту стоїть на настилі, а не в руслі під ним: корінь на deck_y, для будь-якого типу. Тіла розрахунку
## гармати, знищеної на мосту, лежать між поручнями, на настилі й не під уламком.
func test_a_wreck_on_a_bridge_stands_on_the_deck_and_its_crew_lies_on_the_span() -> void:
	UnitSilhouettes.reset_models()
	WreckLayer.clear_deck_cache()
	var b := Board.create(14, 14, Terrain.GroundState.DRY)
	for x in 14:
		b.set_kind(Vector2i(x, 7), Terrain.Kind.WATER)
		b.set_kind(Vector2i(x, 8), Terrain.Kind.WATER)
	b.set_kind(Vector2i(11, 7), Terrain.Kind.BRIDGE)
	b.set_kind(Vector2i(11, 8), Terrain.Kind.BRIDGE)
	b.set_kind(Vector2i(11, 6), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(11, 9), Terrain.Kind.ROAD)
	var previous: TerrainHeight = TerrainHeight.active
	var th := TerrainHeight.bake(b, 0, 1)
	TerrainHeight.active = th
	var cell := Vector2i(11, 7)
	var deck: float = th.deck_y(cell)
	assert_gt(deck - th.at(float(cell.x), float(cell.y)), 0.1, "передумова: настил вище за русло")
	for id: int in [5, 9, 10]:
		var wreck: Node3D = WreckLayer.build_wreck(cell, id, 0)
		assert_almost_eq(wreck.position.y, deck, 0.0001, "корінь уламка типу %d на настилі" % id)
		wreck.free()
	# вода зі сходу й заходу від мосту: він іде вздовж z, і від осі настилу (x) тіло не далі за ширину проїзду
	for id: int in [9, 10]:
		for facing: int in [0, 2, 3, 5]:
			var body := Casualties.Body.new(5, cell, 0, id, facing, 0, Casualties.CREW_FIGURES)
			var plain: Dictionary = CrewLegal.ground_index(CrewLegal.wreck_tris(id, 0, facing, Vector2.ZERO))
			var centre: Vector3 = IsoCameraRig.cell_to_world(cell)
			var laid: int = 0
			for slot in Casualties.CREW_FIGURES:
				var xf: Transform3D = WreckLayer.body_transform(body, slot, b, [])
				if not WreckLayer.body_is_laid(xf):
					continue
				laid += 1
				var mid: Vector3 = WreckLayer.body_centre(xf) - centre
				var long := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
				var wide := Vector2(-long.y, long.x)
				assert_almost_eq(xf.origin.y, deck, 0.0001, "тіло на настилі")
				var where: String = "тип %d, напрям %d, місце %d" % [id, facing, slot]
				for sl: float in [-1.0, 1.0]:
					for sw: float in [-1.0, 1.0]:
						var corner: Vector2 = Vector2(mid.x, mid.z) + long * (WreckLayer.BODY_LENGTH * 0.5 * sl) + wide * (WreckLayer.BODY_WIDTH * 0.5 * sw)
						assert_lte(absf(corner.x), WreckLayer.BODY_DECK_HALF_ROAD - WreckLayer.BODY_DECK_RAIL_GAP + 0.0001, "кут між поручнями, " + where)
						assert_lte(absf(corner.y), 0.5, "кут у тайлі, " + where)
				assert_false(CrewLegal.rect_hits(Vector2(mid.x, mid.z), long, WreckLayer.BODY_LENGTH * 0.5, WreckLayer.BODY_WIDTH * 0.5, plain), "тіло на мосту не під уламком, " + where)
	TerrainHeight.active = previous
	WreckLayer.clear_deck_cache()
