extends GutTest
## Журнал команд: знімки гравців, відрізок команд і повторний прогін.

func _open_map() -> Board:
	var b: Board = Board.create(16, 12, Terrain.GroundState.DRY)
	for x in 16:
		b.set_kind(Vector2i(x, 6), Terrain.Kind.ROAD)
	return b

func _state() -> BattleState:
	var s: BattleState = BattleState.create(_open_map(), 2, 2024)
	s.add_unit(5, 0, Vector2i(3, 6), 2)
	s.add_unit(2, 1, Vector2i(8, 6), 6)
	s.start()
	s.begin_turn()
	return s

func _play(s: BattleState, log: ReplayLog, c: Command) -> void:
	assert_eq(c.validate(s), "", "команда мусить бути дозволена")
	c.apply(s)
	log.record(c)

func _dump(s: BattleState) -> String:
	return JSON.stringify(BattleSerializer.to_dict(s), "", true)

## Гра: p0 їде й стріляє, p1 їде й стріляє, p0 їде.
func _match(log: ReplayLog) -> BattleState:
	var s: BattleState = _state()
	log.mark(0, s)
	log.mark(1, s)
	_play(s, log, MoveCommand.create(1, Vector2i(5, 6)))
	_play(s, log, FireCommand.create(1, 2))
	_play(s, log, EndTurnCommand.create())
	log.mark(1, s)
	_play(s, log, MoveCommand.create(2, Vector2i(9, 6)))
	_play(s, log, EndTurnCommand.create())
	return s

func test_span_is_commands_since_viewers_snapshot() -> void:
	var log: ReplayLog = ReplayLog.new()
	_match(log)
	assert_eq(log.span(0).size(), 5)
	assert_eq(log.span(1).size(), 2, "p1 позначив знімок після третьої команди")
	assert_true(log.span(1)[0] is MoveCommand)
	assert_true(log.span(1)[1] is EndTurnCommand)
	assert_eq(ReplayLog.new().span(0).size(), 0, "без знімка порожньо")

func test_rerun_reaches_the_real_state() -> void:
	var log: ReplayLog = ReplayLog.new()
	var s: BattleState = _match(log)
	var r: Array[Dictionary] = log.rerun(0)
	assert_eq(r.size(), 5)
	assert_eq(_dump(r[r.size() - 1]["after"]), _dump(s))
	assert_eq(r[0]["actor"], 0)
	assert_eq(r[0]["turn"], 1)
	assert_eq(r[3]["actor"], 1, "актор — гравець до команди")
	assert_gt((r[1]["events"] as Array).size(), 0, "постріл дає події")
	assert_eq(log.rerun(1).size(), 2)
	assert_eq(ReplayLog.new().rerun(0).size(), 0)

func test_rerun_after_copies_are_independent() -> void:
	var log: ReplayLog = ReplayLog.new()
	_match(log)
	var r: Array[Dictionary] = log.rerun(0)
	var before: String = _dump(r[1]["after"])
	(r[0]["after"] as BattleState).units[1].hp = 1
	assert_eq(_dump(r[1]["after"]), before)
	var again: Array[Dictionary] = log.rerun(0)
	assert_ne(again[0]["after"].units[1].hp, 1, "повторний прогін не зачеплений")

func test_start_state_is_a_fresh_copy() -> void:
	var log: ReplayLog = ReplayLog.new()
	var s: BattleState = _state()
	log.mark(0, s)
	var a: BattleState = log.start_state(0)
	assert_eq(_dump(a), _dump(s))
	a.units[1].hp = 1
	assert_eq(_dump(log.start_state(0)), _dump(s))
	assert_null(log.start_state(1))

func test_mark_trims_behind_oldest_snapshot() -> void:
	var log: ReplayLog = ReplayLog.new()
	var s: BattleState = _state()
	log.mark(0, s)
	log.mark(1, s)
	_play(s, log, MoveCommand.create(1, Vector2i(5, 6)))
	_play(s, log, EndTurnCommand.create())
	log.mark(0, s)
	assert_eq(log.span(0).size(), 0)
	assert_eq(log.span(1).size(), 2, "p1 ще тримає ці команди")
	log.mark(1, s)
	assert_eq(log.to_dict()["commands"].size(), 0, "обидва знімки в кінці — нічого тримати")
	_play(s, log, EndTurnCommand.create())
	assert_eq(log.span(0).size(), 1)
	assert_eq(log.span(1).size(), 1)

func test_round_trip_through_json_keeps_rerun_equal() -> void:
	var log: ReplayLog = ReplayLog.new()
	var s: BattleState = _match(log)
	var parsed: Variant = JSON.parse_string(JSON.stringify(log.to_dict()))
	var back: ReplayLog = ReplayLog.from_dict(parsed)
	assert_not_null(back)
	assert_eq(back.span(1).size(), 2)
	var r: Array[Dictionary] = back.rerun(0)
	assert_eq(_dump(r[r.size() - 1]["after"]), _dump(s))
	back.record(EndTurnCommand.create())
	assert_eq(back.span(0).size(), 6, "індекси після завантаження збережені")

func test_invalid_dict_is_null() -> void:
	assert_null(ReplayLog.from_dict({}))
	assert_null(ReplayLog.from_dict({"base": 0, "commands": [{"kind": "nope"}], "snapshots": {}}))
	var log: ReplayLog = ReplayLog.new()
	_match(log)
	var d: Dictionary = JSON.parse_string(JSON.stringify(log.to_dict()))
	d["snapshots"]["0"]["index"] = 999
	assert_null(ReplayLog.from_dict(d), "індекс поза журналом")
	d = JSON.parse_string(JSON.stringify(log.to_dict()))
	d["snapshots"]["0"]["state"] = {}
	assert_null(ReplayLog.from_dict(d), "зіпсований знімок")

func test_rerun_stops_on_command_that_no_longer_validates() -> void:
	var s: BattleState = _state()
	var log: ReplayLog = ReplayLog.new()
	log.mark(0, s)
	log.record(MoveCommand.create(1, Vector2i(15, 0)))  # далеко за межами AP: не застосовано
	assert_ne(MoveCommand.create(1, Vector2i(15, 0)).validate(s), "")
	assert_eq(log.rerun(0).size(), 0)

func test_matches_only_the_state_the_log_ends_on() -> void:
	var log: ReplayLog = ReplayLog.new()
	var s: BattleState = _match(log)
	assert_true(log.matches(s))
	assert_true(ReplayLog.new().matches(s), "порожній журнал нічого не повторює")
	var stale: ReplayLog = ReplayLog.new()
	var early: BattleState = _state()
	stale.mark(0, early)
	stale.record(EndTurnCommand.create())
	assert_false(stale.matches(early), "журнал веде не туди, де стан")
	var broken: ReplayLog = ReplayLog.new()
	broken.mark(0, early)
	broken.record(MoveCommand.create(1, Vector2i(15, 0)))
	assert_false(broken.matches(early), "команда не проходить перевірку")

func test_conceded_player_snapshot_does_not_pin_the_log() -> void:
	var log: ReplayLog = ReplayLog.new()
	var s: BattleState = BattleState.create(_open_map(), 3, 2024)
	s.add_unit(5, 0, Vector2i(3, 6), 2)
	s.add_unit(2, 1, Vector2i(8, 6), 6)
	s.add_unit(2, 2, Vector2i(8, 8), 6)
	s.start()
	s.begin_turn()
	for p in 3:
		log.mark(p, s)
	_play(s, log, EndTurnCommand.create())
	_play(s, log, ConcedeCommand.create())
	_play(s, log, EndTurnCommand.create())
	assert_true(s.eliminated[1])
	_play(s, log, EndTurnCommand.create())
	log.mark(2, s)
	log.mark(0, s)
	assert_eq(log.to_dict()["commands"].size(), 0, "знімок того, хто здався, не тримає журнал")
	assert_eq(log.span(0).size(), 0)
	assert_eq(log.span(2).size(), 0)
