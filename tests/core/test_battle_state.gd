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
	assert_true(events[1] is Events.TileRevealed, "туман активного гравця має розкритись слідом за початком ходу")

func test_begin_turn_reveals_objectives_only_for_the_active_player() -> void:
	# §3.10: цілі підкоряються туману. begin_turn() мусить прогнати
	# Objectives.refresh_seen() для гравця, чий хід починається, — і нікого
	# більше, точнісінько як refresh_vision() вище.
	var s: BattleState = _state(2)
	Objectives.add(s, Vector2i(5, 5), -1)
	s.add_unit(0, 0, Vector2i(5, 5), 0)
	s.active_player = 0
	s.begin_turn()
	assert_true(Objectives.at(s, Vector2i(5, 5)).seen_by[0], "активний гравець бачить ціль біля свого юніта")
	assert_false(Objectives.at(s, Vector2i(5, 5)).seen_by[1], "чужий туман не рухається чужим ходом")

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
	var eliminated_index: int = -1
	var ended_index: int = -1
	for i in events.size():
		if events[i] is Events.PlayerEliminated:
			eliminated_index = i
		elif events[i] is Events.MatchEnded:
			ended_index = i
	assert_ne(eliminated_index, -1, "має бути подія PlayerEliminated")
	assert_ne(ended_index, -1, "має бути подія MatchEnded")
	assert_true(eliminated_index < ended_index, "PlayerEliminated має передувати MatchEnded")
	assert_true(s.eliminated[1])
	assert_true(s.is_over())
	assert_eq(s.winner, 0)

func test_match_ends_in_a_draw_when_nobody_survives() -> void:
	# Досяжно не лише взаємним знищенням: карта, де жоден гравець не має юнітів,
	# дає цей стан на першій же перевірці. Без цього матч зависав би назавжди.
	var state: BattleState = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)
	var events: Array[Events.BattleEvent] = state.check_elimination()
	assert_true(state.is_over(), "матч мусить завершитися, а не зависнути")
	assert_eq(state.winner, BattleState.DRAW, "нічия — не те саме, що незавершена гра")
	var ended: bool = false
	for e in events:
		if e is Events.MatchEnded:
			ended = true
			assert_eq((e as Events.MatchEnded).winner, BattleState.DRAW)
	assert_true(ended, "MatchEnded має бути в подіях")

func test_each_player_gets_its_own_vision() -> void:
	var s: BattleState = _state(3)
	assert_eq(s.vision.size(), 3)
	assert_ne(s.vision[0], s.vision[1], "жодного спільного об'єкта туману")

func test_create_does_not_prime_vision() -> void:
	# start() не можна викликати з create(): юніти додаються ПІСЛЯ create(),
	# тож приймінг там праймив би порожню дошку без жодного юніта.
	var s: BattleState = _state()
	s.add_unit(5, 0, Vector2i(4, 4), 2)
	assert_false(s.vision[0].is_visible(Vector2i(4, 4)), "create() сам по собі не рахує зір")

func test_start_primes_every_players_vision_before_their_first_turn() -> void:
	var s: BattleState = _state(3)
	s.add_unit(5, 0, Vector2i(1, 1), 0)
	s.add_unit(5, 1, Vector2i(8, 8), 0)
	s.add_unit(5, 2, Vector2i(5, 5), 0)
	s.start()
	assert_true(s.vision[0].is_visible(Vector2i(1, 1)), "гравець 0 бачить свій юніт одразу після start()")
	assert_true(s.vision[1].is_visible(Vector2i(8, 8)), "гравець 1 теж — а не лише активний гравець")
	assert_true(s.vision[2].is_visible(Vector2i(5, 5)), "і гравець 2 — жоден не лишається нульовою сіткою")

func test_start_discards_its_own_reveal_events() -> void:
	# §BattleState.start(): один спільний потік подій (§6) не має чим розділити
	# гравців, тож повернути звідси TileRevealed кожного означало б витік. start()
	# тому повертає void — і платить за це тим, що початкового туману з потоку
	# подій не зібрати взагалі: seen уже виставлений, отже ПЕРШИЙ begin_turn()
	# не має чого відкривати. Вигляд зобовʼязаний засіяти туман зі стану.
	#
	# Друге твердження тут — головне: без нього тест проходить і тоді, коли
	# start() починає повертати події назовні або перестає праймити чужий seen.
	var s: BattleState = _state()
	s.add_unit(5, 0, Vector2i(4, 4), 0)
	s.start()
	assert_true(s.vision[0].is_seen(Vector2i(4, 4)),
		"seen усе одно оновлюється — лише подія про це не повертається назовні")

	var events: Array[Events.BattleEvent] = s.begin_turn()
	var revealed: int = 0
	for e in events:
		if e is Events.TileRevealed:
			revealed += 1
	assert_eq(revealed, 0,
		"перший begin_turn() не відкриває нічого — start() уже виставив seen, і це навмисно")
	assert_true(events.size() > 0 and events[0] is Events.TurnStarted, "лишається сам TurnStarted")
