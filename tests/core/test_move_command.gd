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
