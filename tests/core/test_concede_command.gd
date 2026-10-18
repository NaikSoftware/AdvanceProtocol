extends GutTest
## Здача: активний гравець виходить з матчу так, ніби всі його юніти знищено.

func _state(players: int) -> BattleState:
	return BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), players, 77)

func _count(events: Array[Events.BattleEvent], kind: Variant) -> int:
	var n: int = 0
	for e in events:
		if is_instance_of(e, kind):
			n += 1
	return n

func test_two_player_concede_hands_the_win_to_the_opponent() -> void:
	var s: BattleState = _state(2)
	var a: Unit = s.add_unit(0, 0, Vector2i(1, 1), 0)
	var b: Unit = s.add_unit(0, 0, Vector2i(2, 1), 0)
	s.add_unit(0, 1, Vector2i(8, 8), 0)
	s.active_player = 0
	var cmd: ConcedeCommand = ConcedeCommand.create()
	assert_eq(cmd.validate(s), "")
	var events: Array[Events.BattleEvent] = cmd.apply(s)
	assert_true(s.is_over())
	assert_eq(s.winner, 1)
	assert_false(a.is_alive())
	assert_false(b.is_alive())
	assert_eq(_count(events, Events.UnitDestroyed), 2)
	assert_eq(_count(events, Events.PlayerEliminated), 1)
	assert_eq(_count(events, Events.MatchEnded), 1)
	assert_eq(_count(events, Events.TurnStarted), 0, "матч скінчено — нового ходу немає")

func test_three_player_concede_passes_the_turn_and_skips_the_conceder() -> void:
	var s: BattleState = _state(3)
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	var gone: Unit = s.add_unit(0, 1, Vector2i(5, 5), 0)
	s.add_unit(0, 2, Vector2i(8, 8), 0)
	s.active_player = 1
	var events: Array[Events.BattleEvent] = ConcedeCommand.create().apply(s)
	assert_false(s.is_over())
	assert_true(s.eliminated[1])
	assert_false(gone.is_alive())
	assert_null(s.unit_at(Vector2i(5, 5)), "тайл здавшогося звільнено")
	assert_eq(s.active_player, 2)
	assert_eq(_count(events, Events.TurnStarted), 1)
	assert_eq(_count(events, Events.MatchEnded), 0)
	EndTurnCommand.create().apply(s)
	assert_eq(s.active_player, 0)
	EndTurnCommand.create().apply(s)
	assert_eq(s.active_player, 2, "вибулий гравець 1 пропускається")

func _three() -> BattleState:
	var s: BattleState = _state(3)
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.add_unit(0, 1, Vector2i(5, 5), 0)
	s.add_unit(0, 2, Vector2i(8, 8), 0)
	s.active_player = 0
	return s

func test_last_player_in_round_conceding_starts_a_new_round() -> void:
	var s: BattleState = _three()
	s.active_player = 2
	var before: int = s.turn_number
	ConcedeCommand.create().apply(s)
	assert_eq(s.active_player, 0)
	assert_eq(s.turn_number, before + 1, "коло замкнулося — новий номер ходу")

func test_mid_round_concede_keeps_the_turn_number() -> void:
	var s: BattleState = _three()
	s.active_player = 1
	var before: int = s.turn_number
	ConcedeCommand.create().apply(s)
	assert_eq(s.active_player, 2)
	assert_eq(s.turn_number, before, "те саме коло")

func test_validate_rejects_after_match_over() -> void:
	var s: BattleState = _state(2)
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.add_unit(0, 1, Vector2i(8, 8), 0)
	ConcedeCommand.create().apply(s)
	assert_eq(ConcedeCommand.create().validate(s), "ERR_MATCH_OVER")
