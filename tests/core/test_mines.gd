extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 5)

func test_mine_is_visible_only_to_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 0), "власник свої міни бачить")
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "§3.11: для решти вона невидима")

func test_an_engineer_passing_near_reveals_the_mine_for_that_player_only() -> void:
	# Сапера тут не «підсунуто, щоб тест проходив»: до §3.11 розкривав будь-який
	# юніт, і в цій ролі стояло стрілецьке відділення (тип 0). Тепер шукати вміє
	# лише сапер, тож юніт замінено на тип 11 — сама перевірка (розкриття ведеться
	# на гравця, а не глобально) лишилась тою самою.
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 3, 5)
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(11, 1, Vector2i(5, 6), 0)
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1))
	assert_false(Mines.is_known(state, Vector2i(5, 5), 2), "розкриття — на гравця, як і туман")

func test_only_an_engineer_finds_an_enemy_mine() -> void:
	# §3.11: без сапера попереду колона заходить у мінне поле наосліп. Стрілецьке
	# відділення стоїть УПРИТУЛ до міни й однаково її не бачить — попри те, що його
	# огляд (5) накриває тайл із запасом. Шукає клас, а не відстань.
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 1, Vector2i(5, 6), 0)     # стрілецьке відділення, сусідній тайл
	state.add_unit(5, 1, Vector2i(4, 5), 0)     # середній танк, теж поруч
	Mines.reveal_near(state, 1)
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1),
		"§3.11: чужу міну знаходить лише сапер")

func test_an_engineer_finds_a_mine_across_its_whole_vision() -> void:
	# §3.11: радіус — власний огляд сапера (3), а не один тайл, і міряється
	# ромбом. Три тайли — усередині; чотири — уже ні.
	Mines.place(state, Vector2i(5, 5), 0)
	var eng: Unit = state.add_unit(11, 1, Vector2i(5, 9), 0)   # |0|+|4| = 4 — задалеко
	Mines.reveal_near(state, 1)
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "4 тайли — поза оглядом сапера")
	eng.pos = Vector2i(5, 8)                                   # |0|+|3| = 3 — рівно на межі
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1), "3 тайли — сапер бачить")

func test_engineer_search_uses_the_diamond_not_the_circle() -> void:
	# §3.11 через §3.1: (2, 2) від міни — це 2+2 = 4 > 3 поза ромбом, хоча
	# dist_sq 8 <= 9 і коло радіуса 3 цей тайл накрило б.
	Mines.place(state, Vector2i(5, 5), 0)
	assert_true(Rules.in_radius(Vector2i(7, 7), Vector2i(5, 5), 3), "передумова: у колі радіуса 3")
	state.add_unit(11, 1, Vector2i(7, 7), 0)
	Mines.reveal_near(state, 1)
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "огляд — ромб, не коло")

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
