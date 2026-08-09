extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 5)

func test_mine_is_visible_only_to_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 0), "власник свої міни бачить")
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "§3.11: для решти вона невидима")

func test_passing_near_reveals_the_mine_for_that_player_only() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 3, 5)
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 1, Vector2i(5, 6), 0)
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1))
	assert_false(Mines.is_known(state, Vector2i(5, 5), 2), "розкриття — на гравця, як і туман")

func test_driving_onto_an_unknown_mine_detonates_it() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	var u: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	var before: int = u.hp
	var events: Array = Mines.step_on(state, u)
	assert_true(u.hp < before)
	assert_null(Mines.mine_at(state, Vector2i(5, 5)), "міна одноразова")
	var triggered: bool = false
	for e in events:
		if e is Events.MineTriggered:
			triggered = true
	assert_true(triggered)

func test_own_mines_do_not_detonate_under_the_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	var before: int = u.hp
	Mines.step_on(state, u)
	assert_eq(u.hp, before, "своя міна свого не рве")

func test_clearing_removes_the_mine() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	Mines.clear(state, Vector2i(5, 5))
	assert_null(Mines.mine_at(state, Vector2i(5, 5)))

func test_mine_can_kill_and_end_the_match() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	var u: Unit = state.add_unit(2, 1, Vector2i(5, 5), 0)
	u.hp = 10
	var events: Array = Mines.step_on(state, u)
	assert_false(u.is_alive())
	var ended: bool = false
	for e in events:
		if e is Events.MatchEnded:
			ended = true
	assert_true(ended)
