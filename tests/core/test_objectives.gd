extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 8)

func test_objective_is_hidden_until_seen() -> void:
	Objectives.add(state, Vector2i(10, 10), 1)
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.refresh_vision(0)
	Objectives.refresh_seen(state, 0)
	assert_false(Objectives.at(state, Vector2i(10, 10)).seen_by[0], "§3.10: цілі підкоряються туману")

func test_objective_becomes_known_once_observed() -> void:
	Objectives.add(state, Vector2i(3, 3), 1)
	state.add_unit(0, 0, Vector2i(3, 5), 0)
	state.refresh_vision(0)
	Objectives.refresh_seen(state, 0)
	assert_true(Objectives.at(state, Vector2i(3, 3)).seen_by[0])

func test_an_objective_scouted_by_a_unit_that_died_is_still_remembered() -> void:
	# §3.5/§3.10: гейт «ціль побачено» — розвідана земля, а не погляд просто зараз.
	# Реальний розрив між цими двома є, і ось він: BattleState.start() праймить
	# видимість УСІМ, але Objectives.refresh_seen() з нього не викликається — вона
	# чекає на begin_turn() свого гравця. Якщо розвідник гине між цими двома
	# моментами, під visible ціль не позначилася б НІКОЛИ, хоч гравець і дивився
	# на неї від першої хвилини матчу. Розвідка незворотна — і це теж має пережити
	# смерть розвідника.
	#
	# Гравець 1: стрілецьке відділення (огляд 5, hp 100) на (5,5) за 2 тайли від
	# цілі, і танк на (10,10), від якого до цілі 6 > 4 — після смерті відділення на
	# (5,7) не дивиться ніхто. Гравець 0: гармата (#9, atk 200, дальність 5, огляд 3)
	# на (5,2), тобто рівно за 3 тайли — і бачить, і дістає. §3.3 ділить шкоду
	# артилерії по піхоті на 4, тож із dist_sq 9 постріл дає (150 + [0,50])/4 =
	# [37, 50] — здоровому відділенню цього мало, і hp навмисно збито до 30, щоб
	# смерть була гарантованою, а тест не залежав від сіда.
	var idx: int = Objectives.add(state, Vector2i(5, 7), -1)
	var scout: Unit = state.add_unit(0, 1, Vector2i(5, 5), 0)
	scout.hp = 30
	state.add_unit(5, 1, Vector2i(10, 10), 0)
	var gun: Unit = state.add_unit(9, 0, Vector2i(5, 2), 4)
	state.start()
	assert_true(state.vision[1].is_seen(Vector2i(5, 7)), "передумова: розвідник накрив тайл цілі")
	assert_false(state.objectives[idx].seen_by[1],
		"передумова: start() праймить видимість, але цілі не позначає — це робить begin_turn()")

	state.active_player = 0
	state.begin_turn()
	FireCommand.create(gun.id, scout.id).apply(state)
	assert_false(scout.is_alive(), "передумова: піхота без броні гине від гармати")
	assert_false(state.vision[1].is_visible(Vector2i(5, 7)),
		"передумова: після смерті розвідника на тайл цілі не дивиться ніхто")

	EndTurnCommand.create().apply(state)   # хід гравця 1: саме тут біжить refresh_seen()
	assert_eq(state.active_player, 1, "передумова: хід перейшов до гравця 1")
	assert_true(state.objectives[idx].seen_by[1],
		"§3.5: ціль на розвіданій землі памʼятається, навіть коли того, хто її бачив, уже нема")

func test_map_cannot_exceed_fifteen_objectives() -> void:
	for i in 15:
		assert_true(Objectives.add(state, Vector2i(i, 0), -1) >= 0)
	assert_eq(Objectives.add(state, Vector2i(0, 5), -1), -1, "§3.10: до 15 маркерів на карту")

func test_holding_enough_objectives_wins_the_match() -> void:
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(10, 10), 0)
	for i in 3:
		Objectives.add(state, Vector2i(i, 0), 0)
	var events: Array[Events.BattleEvent] = Objectives.check_victory(state, 0, 3)
	assert_eq(state.winner, 0)
	assert_true(events.size() > 0)

func test_only_the_player_being_checked_can_claim_the_objectives() -> void:
	# §3.10: цілі утримує гравець 0, але перевіряють гравця 1 — заявити умову
	# може лише той, чий хід щойно завершився. Раніше функція перебирала всіх
	# гравців і оголосила б переможцем гравця 0 незалежно від того, чий це хід.
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(10, 10), 0)
	for i in 3:
		Objectives.add(state, Vector2i(i, 0), 0)
	var events: Array[Events.BattleEvent] = Objectives.check_victory(state, 1, 3)
	assert_eq(state.winner, BattleState.NO_WINNER, "чужі цілі не завершують матч на твоєму ході")
	assert_eq(events.size(), 0)

func test_two_holders_cannot_claim_on_the_same_check() -> void:
	# §3.10: замість tie-break нічия зроблена недосяжною. Обидва гравці
	# утримують достатньо цілей; перевірка стосується рівно одного, і саме він
	# перемагає — порядок індексів більше нічого не вирішує.
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 8)
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(10, 10), 0)
	for i in 2:
		Objectives.add(state, Vector2i(i, 0), 0)
		Objectives.add(state, Vector2i(i, 5), 1)
	Objectives.check_victory(state, 1, 2)
	assert_eq(state.winner, 1, "перемагає перевірений гравець, а не менший індекс")

func test_an_eliminated_player_cannot_claim_the_objectives() -> void:
	state.add_unit(0, 1, Vector2i(10, 10), 0)
	for i in 3:
		Objectives.add(state, Vector2i(i, 0), 0)
	state.eliminated[0] = true
	# Передумова записана явно: вибулий гравець ТРИМАЄ достатньо цілей, тож єдине,
	# що стоїть між ним і перемогою, — перевірка eliminated. Без цього рядка тест
	# лишався б істинним і тоді, коли гравець просто нічого не тримає, і мовчки
	# перестав би пришпилювати те, що названо в його імені.
	assert_eq(Objectives.held_by(state, 0), 3, "передумова: умову цілей виконано")
	Objectives.check_victory(state, 0, 3)
	assert_eq(state.winner, BattleState.NO_WINNER, "вибулий гравець не заявляє умову цілей")

func test_destroyed_objective_counts_for_nobody() -> void:
	Objectives.add(state, Vector2i(1, 0), 0)
	Objectives.at(state, Vector2i(1, 0)).intact = false
	assert_eq(Objectives.held_by(state, 0), 0)
