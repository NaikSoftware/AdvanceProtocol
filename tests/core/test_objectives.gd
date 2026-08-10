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
	Objectives.check_victory(state, 0, 3)
	assert_eq(state.winner, BattleState.NO_WINNER, "вибулий гравець не заявляє умову цілей")

func test_destroyed_objective_counts_for_nobody() -> void:
	Objectives.add(state, Vector2i(1, 0), 0)
	Objectives.at(state, Vector2i(1, 0)).intact = false
	assert_eq(Objectives.held_by(state, 0), 0)
