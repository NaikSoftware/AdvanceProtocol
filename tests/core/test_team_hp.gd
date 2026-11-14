extends GutTest
## Сила команди для гейта передачі ходу: поточні HP живих юнітів гравця проти суми
## max HP тих, з якими він почав матч. Вигляд лише ділить ці числа, нічого не виводить сам.

func _state(players: int = 2, seed: int = 7) -> BattleState:
	return BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), players, seed)

func test_fresh_match_is_at_full_strength() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(5, 0, Vector2i(1, 1), 2)
	var b: Unit = s.add_unit(0, 0, Vector2i(2, 1), 2)
	var c: Unit = s.add_unit(2, 1, Vector2i(9, 9), 6)
	s.start()
	assert_eq(s.team_hp(0), a.max_hp() + b.max_hp())
	assert_eq(s.team_hp_start(0), a.max_hp() + b.max_hp())
	assert_eq(s.team_hp(1), c.max_hp())
	assert_eq(s.team_hp_start(1), c.max_hp())
	assert_eq(s.team_hp_share_of_start(0), 1.0)

func test_damage_lowers_team_hp_but_not_the_start_total() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = s.add_unit(2, 1, Vector2i(6, 4), 2)
	s.begin_turn()
	FireCommand.create(a.id, t.id).apply(s)
	assert_true(t.is_alive(), "передумова: ціль пережила постріл")
	assert_lt(t.hp, t.max_hp())
	assert_eq(s.team_hp(1), t.hp)
	assert_eq(s.team_hp_start(1), t.max_hp())
	assert_almost_eq(s.team_hp_share_of_start(1), float(t.hp) / float(t.max_hp()), 0.0001)

func test_destroyed_unit_leaves_team_hp_but_stays_in_start_total() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = s.add_unit(0, 1, Vector2i(6, 4), 2)
	var other: Unit = s.add_unit(2, 1, Vector2i(10, 10), 2)
	s.begin_turn()
	t.hp = 1
	FireCommand.create(a.id, t.id).apply(s)
	assert_false(t.is_alive(), "передумова: постріл добиває ціль")
	assert_eq(s.team_hp(1), other.max_hp())
	assert_eq(s.team_hp_start(1), t.max_hp() + other.max_hp())

func test_repair_raises_team_hp_but_never_past_the_start_total() -> void:
	var s: BattleState = _state(2, 21)
	s.active_player = 0
	var e: Unit = s.add_unit(11, 0, Vector2i(4, 4), 0)
	var friend: Unit = s.add_unit(5, 0, Vector2i(4, 3), 0)
	friend.hp = friend.max_hp() - 5   # ремонт дає щонайменше 20, тож упирається в максимум
	var before: int = s.team_hp(0)
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).apply(s)
	assert_eq(s.team_hp(0), before + 5)
	assert_eq(s.team_hp(0), s.team_hp_start(0))

func test_save_round_trip_keeps_the_start_total() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = s.add_unit(0, 1, Vector2i(6, 4), 2)
	var other: Unit = s.add_unit(2, 1, Vector2i(10, 10), 2)
	s.start()
	s.begin_turn()
	t.hp = 1
	FireCommand.create(a.id, t.id).apply(s)
	assert_false(t.is_alive(), "передумова: загиблий юніт мусить пройти крізь збереження")
	var loaded: BattleState = BattleSerializer.from_dict(
		JSON.parse_string(JSON.stringify(BattleSerializer.to_dict(s))))
	assert_not_null(loaded)
	assert_eq(loaded.team_hp_start(1), t.max_hp() + other.max_hp())
	assert_eq(loaded.team_hp(1), other.max_hp())
	assert_eq(loaded.team_hp_start(0), a.max_hp())

func test_three_players_are_counted_separately() -> void:
	var s: BattleState = _state(3)
	var a: Unit = s.add_unit(5, 0, Vector2i(1, 1), 2)
	var b: Unit = s.add_unit(0, 1, Vector2i(10, 1), 6)
	var c: Unit = s.add_unit(2, 2, Vector2i(5, 10), 0)
	var c2: Unit = s.add_unit(0, 2, Vector2i(6, 10), 0)
	b.hp = 40
	c.hp = 100
	assert_eq(s.team_hp(0), a.max_hp())
	assert_eq(s.team_hp(1), 40)
	assert_eq(s.team_hp(2), 100 + c2.max_hp())
	assert_eq(s.team_hp_start(2), c.max_hp() + c2.max_hp())

func test_eliminated_player_has_no_strength_left() -> void:
	var s: BattleState = _state(3)
	s.add_unit(5, 0, Vector2i(1, 1), 2)
	var b: Unit = s.add_unit(2, 1, Vector2i(10, 1), 6)
	s.add_unit(0, 2, Vector2i(5, 10), 0)
	s.start()
	s.active_player = 1
	s.begin_turn()
	ConcedeCommand.create().apply(s)
	assert_true(s.eliminated[1], "передумова: гравець вибув")
	assert_eq(s.team_hp(1), 0)
	assert_eq(s.team_hp_start(1), b.max_hp())
	assert_eq(s.team_hp_share_of_start(1), 0.0)

func test_share_is_zero_for_a_player_who_never_had_units() -> void:
	var s: BattleState = _state()
	s.add_unit(5, 0, Vector2i(1, 1), 2)
	assert_eq(s.team_hp_start(1), 0)
	assert_eq(s.team_hp_share_of_start(1), 0.0, "без ділення на нуль")
