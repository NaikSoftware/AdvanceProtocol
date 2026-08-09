extends GutTest

func _state(players: int = 2) -> BattleState:
	return BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), players, 4242)

func test_ids_are_unique_and_increasing() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(0, 0, Vector2i(1, 1), 0)
	var b: Unit = s.add_unit(0, 1, Vector2i(8, 8), 0)
	assert_true(b.id > a.id)
	assert_eq(s.units.size(), 2)

func test_unit_at_finds_living_units_only() -> void:
	var s: BattleState = _state()
	var u: Unit = s.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_eq(s.unit_at(Vector2i(4, 4)), u)
	u.hp = 0
	assert_null(s.unit_at(Vector2i(4, 4)), "труп не займає тайл")

func test_occupied_map_covers_all_living_units() -> void:
	var s: BattleState = _state()
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.add_unit(0, 1, Vector2i(2, 2), 0)
	assert_eq(s.occupied_map().size(), 2)

func test_begin_turn_refills_only_active_players_units() -> void:
	var s: BattleState = _state()
	var mine: Unit = s.add_unit(5, 0, Vector2i(1, 1), 0)
	var theirs: Unit = s.add_unit(5, 1, Vector2i(8, 8), 0)
	mine.exhaust()
	theirs.exhaust()
	s.active_player = 0
	s.begin_turn()
	assert_eq(mine.ap, mine.max_ap())
	assert_eq(theirs.ap, 0, "чужі юніти чекають свого ходу")

func test_begin_turn_emits_turn_started() -> void:
	var s: BattleState = _state()
	s.add_unit(0, 0, Vector2i(5, 5), 0)
	var events: Array = s.begin_turn()
	assert_true(events[0] is Events.TurnStarted)

func test_rng_is_seeded_and_reproducible() -> void:
	var a: BattleState = BattleState.create(Board.create(4, 4, 0), 2, 99)
	var b: BattleState = BattleState.create(Board.create(4, 4, 0), 2, 99)
	assert_eq(Rules.roll(a.rng, 1000), Rules.roll(b.rng, 1000))

func test_advance_player_skips_eliminated_in_three_player_game() -> void:
	var s: BattleState = _state(3)
	s.active_player = 0
	s.eliminated[1] = true
	assert_eq(s.advance_player(), 2, "§3.10: усунутий гравець просто пропускається")

func test_elimination_is_detected_and_reported() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(0, 0, Vector2i(1, 1), 0)
	var b: Unit = s.add_unit(0, 1, Vector2i(8, 8), 0)
	b.hp = 0
	var events: Array = s.check_elimination()
	var kinds: Array[String] = []
	for e in events:
		kinds.append(e.describe())
	assert_true(s.eliminated[1])
	assert_true(s.is_over())
	assert_eq(s.winner, 0)

func test_each_player_gets_its_own_vision() -> void:
	var s: BattleState = _state(3)
	assert_eq(s.vision.size(), 3)
	assert_ne(s.vision[0], s.vision[1], "жодного спільного об'єкта туману")
