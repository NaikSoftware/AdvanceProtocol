extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(14, 14, Terrain.GroundState.DRY), 2, 3)
	state.active_player = 0

func _assault(pos: Vector2i) -> Unit:
	return state.add_unit(1, 0, pos, 2)

func test_drone_ignores_armour_and_hits_hard() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(6, 2), 2)   # важкий танк, лоб 56
	state.begin_turn()
	var before: int = t.hp
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "")
	DroneCommand.create(a.id, t.id).apply(state)
	assert_true(before - t.hp >= 120, "§3.9: 120 + rand(0,60), броня не віднімається")

func test_drone_reaches_five_tiles() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(7, 2), 2)
	state.begin_turn()
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "", "рівно 5 — у межах")

func test_drone_cannot_reach_six_tiles() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(8, 2), 2)
	state.begin_turn()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "")

func test_drone_cannot_target_infantry() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(0, 1, Vector2i(4, 2), 2)
	state.begin_turn()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "",
		"§3.9: піхота — не ціль для дрона, це і є контргра")

func test_drone_can_target_every_vehicle_class() -> void:
	for type_id in [2, 5, 9, 11]:
		before_each()
		var a: Unit = _assault(Vector2i(2, 2))
		var t: Unit = state.add_unit(type_id, 1, Vector2i(5, 2), 2)
		state.begin_turn()
		assert_eq(DroneCommand.create(a.id, t.id).validate(state), "", "тип %d має бути цілю" % type_id)

func test_rifle_squad_has_no_drones() -> void:
	var a: Unit = state.add_unit(0, 0, Vector2i(2, 2), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.begin_turn()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "")

func test_ammo_is_two_and_not_replenishable() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)
	t.hp = 10_000
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(a.drones_left, 1)
	a.refill_ap()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(a.drones_left, 0)
	a.refill_ap()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "", "третього дрона немає ніколи")

func test_drone_costs_all_remaining_ap() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(a.ap, 0)
	assert_true(a.has_fired)

func test_invisible_target_is_rejected() -> void:
	# Цей стан сьогодні недосяжний чесною грою, і тест про це чесно каже.
	# Зір штурмового відділення — 5, дальність дрона — 5, а туман ведеться ПО ТАЙЛАХ
	# і без перекриття перешкодами. Тому будь-яка ціль у межах дальності стоїть на
	# видимому тайлі, і гілка ERR_TARGET_NOT_VISIBLE недосяжна доти, доки ці два
	# числа рівні. Попередня версія тесту ставила ціль на 6 тайлів і насправді
	# перевіряла ERR_OUT_OF_RANGE, тобто не перевіряла нічого.
	# Гасимо туман вручну: гілка має працювати на той день, коли числа розійдуться.
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(2, 6), 2)   # 4 тайли — усередині дальності
	state.begin_turn()
	state.vision[0].visible.fill(0)
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"§3.9: ціль має бути видима гравцеві просто зараз")

func test_drone_damage_feeds_infantry_pool() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)
	t.hp = 10_000
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_true(state.veterancy[0].xp[UnitTypes.UnitClass.INFANTRY] > 0)
