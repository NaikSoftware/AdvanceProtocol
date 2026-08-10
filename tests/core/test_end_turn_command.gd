extends GutTest
## §3.10: перемога за ціль перевіряється в кінці ходу поряд з елімінацією.
## Obectives.check_victory() мала тести на собі (tests/core/test_objectives.gd),
## але жодного виробничого викликача — ці тести проганяють умову через
## EndTurnCommand, як вона насправді спрацьовує в матчі.

func _state(players: int = 2) -> BattleState:
	return BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), players, 77)

func _two_survivors(s: BattleState) -> void:
	## Обидва гравці мають живий юніт, щоб check_elimination() не завершив
	## матч сам по собі раніше, ніж встигне спрацювати умова цілей.
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.add_unit(0, 1, Vector2i(8, 8), 0)

func test_holding_the_target_ends_the_match_at_end_of_turn() -> void:
	var s: BattleState = _state()
	_two_survivors(s)
	for i in 3:
		Objectives.add(s, Vector2i(i, 0), 0)
	s.objective_hold_target = 3
	s.active_player = 0
	var events: Array[Events.BattleEvent] = EndTurnCommand.create().apply(s)
	assert_true(s.is_over(), "§3.10: утримання N з M цілей закінчує матч")
	assert_eq(s.winner, 0)
	var ended: int = 0
	for e in events:
		if e is Events.MatchEnded:
			ended += 1
	assert_eq(ended, 1, "рівно одна подія MatchEnded")

func test_objective_victory_waits_for_the_holders_own_end_of_turn() -> void:
	# §3.10: цілі утримує гравець 1, а хід завершує гравець 0 — заявити умову
	# може лише той, чий хід щойно скінчився. Раніше перебір усіх гравців
	# оголосив би переможцем гравця 1 вже на цьому виклику — тобто наприкінці
	# чужого ходу, за утримання, яке гравець 1 сам цього ходу не заявляв.
	var s: BattleState = _state()
	_two_survivors(s)
	for i in 3:
		Objectives.add(s, Vector2i(i, 0), 1)
	s.objective_hold_target = 3
	s.active_player = 0
	EndTurnCommand.create().apply(s)
	assert_false(s.is_over(), "не твій хід — не твоя заявка")
	assert_eq(s.active_player, 1, "передумова: хід перейшов до утримувача")
	EndTurnCommand.create().apply(s)
	assert_true(s.is_over(), "а на власному кінці ходу — перемога")
	assert_eq(s.winner, 1)

func test_holding_objectives_never_wins_when_target_is_unset() -> void:
	# Негативний контроль: objective_hold_target лишається дефолтним 0 —
	# анігіляційна мапа без умови цілей не повинна завершитись, скільки б
	# цілей гравець не утримував.
	var s: BattleState = _state()
	_two_survivors(s)
	for i in 3:
		Objectives.add(s, Vector2i(i, 0), 0)
	s.active_player = 0
	EndTurnCommand.create().apply(s)
	assert_false(s.is_over(), "objective_hold_target=0 означає «немає умови перемоги за цілі»")

func test_elimination_beats_the_objective_condition_on_the_same_end_of_turn() -> void:
	# §3.10: коли обидві умови розвʼязуються на тому самому кінці ходу, вирішує
	# елімінація — вона безумовна, а утримання цілей мапа лише опційно заявляє.
	# Тут це не збіг двох переможців, а суперечка: гравець 0 утримує всі три цілі
	# й водночас не має жодного юніта. Порядок викликів у EndTurnCommand — єдине,
	# що тримає правильну відповідь: Objectives.check_victory() гейтить на
	# state.eliminated[player], а той прапорець піднімає саме check_elimination().
	# Переставити виклики місцями — і матч коронує гравця, якого вже немає на мапі.
	var s: BattleState = _state()
	s.add_unit(0, 1, Vector2i(8, 8), 0)   # юніти лишилися тільки у гравця 1
	for i in 3:
		Objectives.add(s, Vector2i(i, 0), 0)
	s.objective_hold_target = 3
	s.active_player = 0
	assert_eq(Objectives.held_by(s, 0), 3, "передумова: умова цілей у гравця 0 виконана")
	assert_true(s.units_of(0).is_empty(), "передумова: і водночас у нього немає юнітів")

	var events: Array[Events.BattleEvent] = EndTurnCommand.create().apply(s)
	assert_true(s.is_over())
	assert_eq(s.winner, 1, "§3.10: гравець без юнітів вибуває, скільки б цілей він не тримав")
	assert_true(s.eliminated[0], "і саме як вибулий, а не як переможець")
	var ended: int = 0
	for e in events:
		if e is Events.MatchEnded:
			ended += 1
	assert_eq(ended, 1, "рівно одна подія MatchEnded")

func test_elimination_and_objective_victory_together_emit_one_match_ended() -> void:
	# Обидві умови стають істинними на тому самому кінці ходу: юніт гравця 1
	# гине (елімінація), і гравець 0 водночас уже утримує ціль. Матч не
	# повинен оголосити двох переможців чи випустити два MatchEnded.
	var s: BattleState = _state()
	var theirs: Unit = s.add_unit(0, 1, Vector2i(8, 8), 0)
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	for i in 3:
		Objectives.add(s, Vector2i(i, 0), 0)
	s.objective_hold_target = 3
	s.active_player = 0
	theirs.hp = 0
	var events: Array[Events.BattleEvent] = EndTurnCommand.create().apply(s)
	assert_true(s.is_over())
	assert_eq(s.winner, 0)
	var ended: int = 0
	for e in events:
		if e is Events.MatchEnded:
			ended += 1
	assert_eq(ended, 1, "елімінація й цілі не повинні подвоїти MatchEnded")
