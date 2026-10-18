extends GutTest
## Перемога — лише знищенням: EndTurnCommand перевіряє елімінацію в кінці ходу.

func _state(players: int = 2) -> BattleState:
	return BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), players, 77)

func _count_match_ended(events: Array[Events.BattleEvent]) -> int:
	var ended: int = 0
	for e in events:
		if e is Events.MatchEnded:
			ended += 1
	return ended

func test_both_sides_alive_passes_the_turn() -> void:
	var s: BattleState = _state()
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.add_unit(0, 1, Vector2i(8, 8), 0)
	s.active_player = 0
	EndTurnCommand.create().apply(s)
	assert_false(s.is_over())
	assert_eq(s.active_player, 1)

func test_opponent_without_units_ends_the_match_with_one_match_ended() -> void:
	var s: BattleState = _state()
	var theirs: Unit = s.add_unit(0, 1, Vector2i(8, 8), 0)
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.active_player = 0
	theirs.hp = 0
	var events: Array[Events.BattleEvent] = EndTurnCommand.create().apply(s)
	assert_true(s.is_over())
	assert_eq(s.winner, 0)
	assert_eq(_count_match_ended(events), 1, "рівно одна подія MatchEnded")

func test_the_player_whose_turn_ended_can_lose_by_elimination() -> void:
	# Елімінація глобальна: вибуває гравець без юнітів, чий би хід не скінчився.
	var s: BattleState = _state()
	s.add_unit(0, 1, Vector2i(8, 8), 0)
	s.active_player = 0
	var events: Array[Events.BattleEvent] = EndTurnCommand.create().apply(s)
	assert_true(s.is_over())
	assert_eq(s.winner, 1)
	assert_true(s.eliminated[0])
	assert_eq(_count_match_ended(events), 1)
