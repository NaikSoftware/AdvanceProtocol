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
