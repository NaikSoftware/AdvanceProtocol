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
	# Ціль пересунуто з (2, 6) на (5, 6), а ручне гасіння туману
	# (state.vision[0].visible.fill(0)) прибрано: після §3.1 ця гілка досяжна
	# чесною грою, і тест більше не потребує милиці. Дальність — коло, огляд —
	# ромб, тож на діагоналі дрон дістає далі, ніж бачить власне відділення:
	# (3, 4) від стрільця — це dist_sq 25 <= 25 у межах дальності 5 і 3 + 4 = 7 > 5
	# поза оглядом 5. Стара версія коментаря стверджувала, що гілка недосяжна;
	# це було правдою, лише поки обидві форми були колами.
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 6), 2)
	state.begin_turn()
	assert_true(Rules.in_radius(a.pos, t.pos, DroneCommand.RANGE), "передумова: у межах дальності дрона")
	assert_false(state.vision[0].is_seen(t.pos), "передумова: тайл цілі не розвідано жодного разу")
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"§3.9/§3.5: ціль має стояти на розвіданій землі — над нею ця перевірка інертна")

func test_the_same_diagonal_stays_unlocked_after_the_spotter_leaves() -> void:
	# §3.5: коригувальник не мусить стояти поруч вічно — розвідка незворотна, і
	# §3.9 над розвіданою землею вже нічого не ріже. Та сама діагональ, що й вище:
	# стрілецьке відділення з (5,3) накриває (5,6) ромбом 3, потім їде на (2,3)
	# (3 тайли поля по 10 з 30 AP), звідки до цілі вже 3 + 3 = 6 > 5. Саме́ штурмове
	# відділення цілі не бачить ніколи (7 > 5), і все одно бʼє.
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 6), 2)
	var scout: Unit = state.add_unit(0, 0, Vector2i(5, 3), 4)
	state.start()
	state.begin_turn()
	assert_true(state.vision[0].is_seen(t.pos), "передумова: коригувальник розвідав тайл цілі")

	MoveCommand.create(scout.id, Vector2i(2, 3), -1).apply(state)
	assert_eq(scout.pos, Vector2i(2, 3), "передумова: 3 тайли поля по 10 — рівно 30 AP")
	assert_false(state.vision[0].is_visible(t.pos), "передумова: зараз за ціллю не стежить ніхто")
	assert_true(state.vision[0].is_seen(t.pos), "передумова: але землю під нею колись розвідали")

	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "",
		"§3.9/§3.5: над розвіданою землею перевірка видимості інертна — удар лишається законним")


func test_a_spotter_unlocks_the_diagonal_the_squad_cannot_see() -> void:
	# §3.9: найдовша рука в грі — і найзалежніша від решти війська. Той самий
	# постріл, що його відхилено вище, стає легальним, щойно ціль підсвічує
	# чужа піхота. Саме це мала на увазі вимога видимості.
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 6), 2)
	state.begin_turn()
	# Обидві половини потрібні. Раніше тест ставив коригувальника одразу і
	# перевіряв лише дозвіл — а такий тест проходить і тоді, коли огляд знову коло:
	# під колом відділення бачить (5,6) саме́ (dist_sq 25 <= 25), і коригувальник
	# нічого не доводить. Відмова ДО нього — і є доказ, що ромб справді ріже.
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"передумова: 3 + 4 = 7 > 5 — власним оглядом відділення цілі не бачить")
	state.add_unit(0, 0, Vector2i(5, 4), 2)   # стрілецьке відділення-коригувальник
	state.refresh_vision(0)
	assert_true(state.vision[0].is_seen(t.pos), "коригувальник розвідав тайл цілі")
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "",
		"§3.9: з коригувальником той самий удар дозволено")

func test_drone_damage_feeds_infantry_pool() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)
	t.hp = 10_000
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_true(state.veterancy[0].xp[UnitTypes.UnitClass.INFANTRY] > 0)
