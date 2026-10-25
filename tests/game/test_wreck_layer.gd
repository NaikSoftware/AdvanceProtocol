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
	var meshes: int = 0
	for n: Node in w.find_children("*", "", true, false):
		assert_false(n is Sprite3D or n is Label3D, "уламки не мають HP-бара й підписів")
		if n is MeshInstance3D:
			meshes += 1
			assert_eq((n as MeshInstance3D).material_override, WreckLayer.burnt_material(), "один спільний обгорілий матеріал")
	var live: Node3D = UnitSilhouettes.build(5, Color.WHITE)
	assert_eq(meshes, live.get_child_count(), "той самий силует, що в живого юніта")
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
	assert_eq(layer.flame_count(Vector2i(0, 0)), 3)
	assert_eq(layer.column_opacity(Vector2i(1, 0)), 0.6)
	assert_eq(layer.flame_count(Vector2i(1, 0)), 1)
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
## щокадрово), а крокує таймером 8 разів на секунду, і таймер стоїть, коли диму нема.
func test_smoke_is_stepped_at_eight_fps_and_stops_when_nothing_burns() -> void:
	assert_eq(WreckLayer.FLIPBOOK_FPS, 8.0)
	assert_true(layer.is_animating() == false, "порожня дошка не анімується")
	layer.add(Vector2i(3, 3), 5, 1.0)
	assert_true(layer.is_animating())
	layer.remove(Vector2i(3, 3))
	assert_false(layer.is_animating())
	for code: String in [WreckLayer.column_shader().code, WreckLayer.fire_shader().code]:
		assert_false(code.contains("TIME"), "шейдер диму не сміє читати TIME")


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
