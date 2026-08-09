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
	var events: Array[Events.BattleEvent] = Objectives.check_victory(state, 3)
	assert_eq(state.winner, 0)
	assert_true(events.size() > 0)

func test_destroyed_objective_counts_for_nobody() -> void:
	Objectives.add(state, Vector2i(1, 0), 0)
	Objectives.at(state, Vector2i(1, 0)).intact = false
	assert_eq(Objectives.held_by(state, 0), 0)
