extends GutTest

var state: BattleState

func before_each() -> void:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	state = BattleState.create(b, 2, 11)

func test_move_costs_ap_and_moves_the_unit() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var before: int = u.ap
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(3, 5), -1)
	assert_eq(cmd.validate(state), "")
	var events: Array = cmd.apply(state)
	assert_eq(u.pos, Vector2i(3, 5))
	assert_true(u.ap < before)
	assert_true(events[0] is Events.UnitMoved)

func test_an_objective_passed_mid_turn_is_remembered_without_waiting_for_the_next_turn() -> void:
	# §3.10: цілі підкоряються туману, отже позначатися побаченими мусять там само,
	# де оновлюється туман. Доти refresh_seen() викликався лише з begin_turn(), тож
	# ціль, побачена серед ходу, не памʼяталася — а якби юніт до наступного ходу
	# відійшов, не запамʼяталася б узагалі.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var idx: int = Objectives.add(state, Vector2i(6, 5), 1)
	state.start()
	assert_false(state.objectives[idx].seen_by[0], "передумова: ціль поза оглядом до ходу")

	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)

	assert_true(state.objectives[idx].seen_by[0],
		"ціль, побачену серед ходу, памʼятаємо одразу, а не з наступного begin_turn()")

func test_move_sets_explicit_facing() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	MoveCommand.create(u.id, Vector2i(3, 5), 6).apply(state)
	assert_eq(u.facing, 6, "гравець сам вирішує, куди дивитись — це вхід у модель броні")

func test_move_without_facing_uses_last_step_direction() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 0)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_eq(u.facing, 2, "останній крок був на схід")

func test_cannot_move_beyond_ap() -> void:
	var u: Unit = state.add_unit(9, 0, Vector2i(0, 5), 2)   # арта, ap 24
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(9, 5), -1)
	assert_ne(cmd.validate(state), "", "недосяжна ціль має бути відхилена")

func test_cannot_move_onto_another_unit() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.add_unit(5, 1, Vector2i(2, 5), 2)
	assert_ne(MoveCommand.create(a.id, Vector2i(2, 5), -1).validate(state), "")

func test_cannot_move_someone_elses_unit() -> void:
	var theirs: Unit = state.add_unit(5, 1, Vector2i(0, 5), 2)
	state.active_player = 0
	assert_ne(MoveCommand.create(theirs.id, Vector2i(1, 5), -1).validate(state), "")

func test_unit_that_fired_cannot_move() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	u.exhaust()
	assert_ne(MoveCommand.create(u.id, Vector2i(1, 5), -1).validate(state), "")

func test_move_refreshes_vision() -> void:
	var u: Unit = state.add_unit(0, 0, Vector2i(0, 5), 2)
	state.begin_turn()
	var events: Array = MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	var has_reveal: bool = false
	for e in events:
		if e is Events.TileRevealed:
			has_reveal = true
	assert_true(has_reveal, "§3.5: видимість перераховується після кожного руху")

func test_end_turn_switches_player_and_bumps_turn_number() -> void:
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(8, 8), 0)
	state.active_player = 0
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 1)
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 0)
	assert_eq(state.turn_number, 2, "номер ходу росте, коли черга повертається до першого гравця")

func test_move_validate_rejects_when_match_is_over() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.check_elimination()   # у гравця 1 нема юнітів — матч завершується перемогою гравця 0
	assert_true(state.is_over(), "передумова: матч має бути завершений")
	assert_eq(MoveCommand.create(u.id, Vector2i(1, 5), -1).validate(state), "ERR_MATCH_OVER")

func test_end_turn_validate_rejects_when_match_is_over() -> void:
	state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.check_elimination()
	assert_true(state.is_over(), "передумова: матч має бути завершений")
	assert_eq(EndTurnCommand.create().validate(state), "ERR_MATCH_OVER")

func test_turn_in_place_emits_unit_turned_not_unit_moved_and_costs_no_ap() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var before: int = u.ap
	var events: Array = MoveCommand.create(u.id, Vector2i(0, 5), 6).apply(state)
	assert_eq(u.pos, Vector2i(0, 5), "поворот на місці не рухає юніт")
	assert_eq(u.facing, 6)
	assert_eq(u.ap, before, "порожній шлях не має коштувати AP")
	var has_turned: bool = false
	var has_moved: bool = false
	for e in events:
		if e is Events.UnitTurned:
			has_turned = true
		if e is Events.UnitMoved:
			has_moved = true
	assert_true(has_turned, "поворот на місці — це UnitTurned")
	assert_false(has_moved, "порожній шлях не повинен породжувати UnitMoved")

func test_moving_onto_an_enemy_mine_detonates_it() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	Mines.place(state, Vector2i(2, 5), 1)
	var before: int = u.hp
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_true(u.hp < before, "§3.11: наїзд на нерозкриту міну — підрив")
	assert_eq(u.pos, Vector2i(2, 5),
		"міна спрацьовує одразу — юніт лишається на тайлі підриву, а не доходить до (3,5)")

func test_a_minefield_cannot_be_crossed_by_stopping_past_it() -> void:
	# Найважливіший тест цього завдання: якби детонував лише кінцевий тайл,
	# міну можна було б просто переїхати, і вся механіка заборони руху зникла б.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	Mines.place(state, Vector2i(1, 5), 1)
	MoveCommand.create(u.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(u.pos, Vector2i(1, 5), "рух обривається на міні, а не проходить крізь неї")
	assert_true(state.mines.is_empty(), "міна витрачена")

func test_several_partial_moves_cost_the_same_as_one_direct_move() -> void:
	# §3.2, «рух витрачається, а не фіксується»: два часткові кроки мусять коштувати
	# рівно стільки ж AP, скільки один прямий хід на ту саму сумарну відстань.
	# Медіум танк (id 5): max_ap 48, cross_country 12; на дорозі penalty 0, тож
	# entry_cost = max(10, 10+0-12) = 10 за тайл — підлога зрізає cross_country
	# повністю, і кожен тайл коштує однаково незалежно від того, скільки їх лишилось.
	# Два кроки по 2 тайли: 20 + 20 = 40 AP, як і прямий хід на 4 тайли.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(u.pos, Vector2i(4, 5))
	assert_eq(u.ap, 8, "48 - (20 + 20) = 8 — точно як один прямий хід на 4 тайли")

func test_partial_moves_leave_enough_ap_to_fire() -> void:
	# Суть правила: зони — про сумарно витрачений AP, а не про кількість окремих
	# рухів. 48 - (10 + 10) = 28 AP лишається, це >= fire_cost 20 — золота зона,
	# і постріл після двох часткових рухів мусить лишатись легальним.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(4, 5), 0)
	state.begin_turn()
	MoveCommand.create(u.id, Vector2i(1, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	assert_eq(u.ap, 28, "48 - (10 + 10) = 28")
	var fire: FireCommand = FireCommand.create(u.id, target.id)
	assert_eq(fire.validate(state), "")
	var before_hp: int = target.hp
	fire.apply(state)
	assert_true(target.hp < before_hp, "постріл після часткових рухів дійсно влучає")

func test_partial_moves_into_the_red_zone_forecloses_firing() -> void:
	# 48 - (20 + 10) = 18 AP лишається, це < fire_cost 20 — червона зона: постріл
	# має бути відхилений, і причина мусить бути саме нестача AP, з точним кодом.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(9, 9), 0)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_eq(u.ap, 18, "48 - (20 + 10) = 18")
	assert_eq(FireCommand.create(u.id, target.id).validate(state), "ERR_NOT_ENOUGH_AP")

func test_firing_after_partial_moves_forecloses_further_movement() -> void:
	# §3.2: постріл — єдине, що завершує активність юніта, незалежно від того,
	# скількома окремими кроками він до цього рухався. На відміну від
	# test_unit_that_fired_cannot_move (де прапорець виставлений напряму через
	# u.exhaust()), тут has_fired виникає зі справжнього FireCommand.apply() після
	# двох часткових рухів, і перевіряється точний код відмови, а не лише його
	# непорожність.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(4, 5), 0)
	state.begin_turn()
	MoveCommand.create(u.id, Vector2i(1, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	FireCommand.create(u.id, target.id).apply(state)
	assert_eq(MoveCommand.create(u.id, Vector2i(3, 5), -1).validate(state), "ERR_ALREADY_FIRED")

func test_zones_predict_whether_firing_is_legal_after_the_move() -> void:
	# Звʼязує обіцянку UI (Pathing.compute_zones) із фактичною поведінкою команд:
	# золота зона мусить означати рівно "після ходу лишиться AP на постріл", а
	# червона — рівно "не лишиться".
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	var gold: Vector2i = Vector2i(2, 5)   # 2 тайли дороги = 20 AP, лишається 28 >= 20
	var red: Vector2i = Vector2i(3, 5)    # 3 тайли дороги = 30 AP, лишається 18 < 20
	assert_true(zones.move_and_fire.has(gold), "передумова: (2,5) — золота зона")
	assert_true(zones.move_only.has(red), "передумова: (3,5) — червона зона")

	var target: Unit = state.add_unit(0, 1, Vector2i(5, 5), 0)
	state.begin_turn()
	MoveCommand.create(u.id, gold, -1).apply(state)
	assert_eq(FireCommand.create(u.id, target.id).validate(state), "",
		"золота зона: постріл лишається легальним після ходу")

	var b2: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b2.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	var state2: BattleState = BattleState.create(b2, 2, 11)
	var u2: Unit = state2.add_unit(5, 0, Vector2i(0, 5), 2)
	var target2: Unit = state2.add_unit(0, 1, Vector2i(5, 5), 0)
	state2.begin_turn()
	MoveCommand.create(u2.id, red, -1).apply(state2)
	assert_eq(FireCommand.create(u2.id, target2.id).validate(state2), "ERR_NOT_ENOUGH_AP",
		"червона зона: рух зʼїв AP, потрібний на постріл")

func _index_of_tile_revealed(events: Array, player: int, tile: Vector2i) -> int:
	for i in events.size():
		var e: Variant = events[i]
		if e is Events.TileRevealed and e.player == player and tile in e.tiles:
			return i
	return -1

func _index_of_mine_revealed(events: Array, player: int, tile: Vector2i) -> int:
	for i in events.size():
		var e: Variant = events[i]
		if e is Events.MineRevealed and e.player == player and e.pos == tile:
			return i
	return -1

func test_mine_revealed_comes_after_the_tile_it_sits_on_is_revealed() -> void:
	# §3.5/§6: вигляд програє список подій по порядку, тож порядок — це контракт,
	# а не косметика. Сапер їде дорогою і з нової позиції вперше бачить і тайл
	# (7,5), і міну на ньому. Розкриття міни мусить іти ПІСЛЯ TileRevealed цього
	# тайла — інакше вигляд один крок малює міну на клітинці, що ще в тумані.
	# Кінцевий стан однаковий за будь-якого порядку, тому перевіряти треба саме
	# індекси подій.
	var eng: Unit = state.add_unit(11, 0, Vector2i(0, 5), 2)   # сапер, огляд 3
	Mines.place(state, Vector2i(7, 5), 1)
	state.begin_turn()
	assert_false(Mines.is_known(state, Vector2i(7, 5), 0),
		"передумова: з (0,5) до міни 7 тайлів — сапер її ще не бачить")
	var events: Array = MoveCommand.create(eng.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(eng.pos, Vector2i(4, 5), "передумова: 4 тайли дороги по 15 AP — 60 з 68")
	var tile_at: int = _index_of_tile_revealed(events, 0, Vector2i(7, 5))
	var mine_at: int = _index_of_mine_revealed(events, 0, Vector2i(7, 5))
	assert_true(tile_at >= 0, "передумова: тайл міни розкрито саме цим рухом")
	assert_true(mine_at >= 0, "передумова: міна знайдена саме цим рухом")
	assert_true(tile_at < mine_at,
		"MineRevealed не має випереджати TileRevealed свого тайла (%d проти %d)" % [mine_at, tile_at])

func test_a_unit_killed_by_a_mine_stops_contributing_vision() -> void:
	# Пришпилює те, що відхилений фінд рев'ю намагався б "полагодити" —
	# обгорнути виклики видимості/розкриття міни в if u.is_alive(): це саме
	# та зміна, яку не можна вносити, бо вона лишає видимість мертвого юніта
	# на дошці. refresh_vision() після смерті — обов'язковий виклик, не зайвий.
	var u: Unit = state.add_unit(0, 0, Vector2i(0, 5), 2)   # піхота, vision 5
	u.hp = 90   # гарантована смерть: міна тепер завдає 90 + rand(0, 90), капується по hp юніта
	state.refresh_vision(0)
	assert_true(state.vision[0].is_visible(Vector2i(5, 5)),
		"передумова: юніт бачить (5,5) з (0,5) — vision 5, dist_sq точно на межі")
	Mines.place(state, Vector2i(1, 5), 1)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_false(u.is_alive(), "передумова: міна гарантовано вбиває при hp <= 90")
	assert_false(state.vision[0].is_visible(Vector2i(5, 5)),
		"мертвий юніт не має продовжувати світити видимість")
