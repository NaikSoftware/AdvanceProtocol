extends GutTest
## Укриття в будівлі: піхота на тайлі BUILDING дістає половину шкоди і прихована від
## ворожого боку навіть на розвіданій землі, доки той її не знайде — сусідством (8
## клітинок довкола) або влучанням. Знайдена лишається знайденою, доки не зійде з тайла.
## Типи: 0 — стрілецьке відділення (дальність 3, огляд 5, 30 AP), 1 — штурмове
## (дрони), 5 — середній танк.

var state: BattleState


func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0


func _cover(owner: int, pos: Vector2i, type_id: int = 0) -> Unit:
	state.board.set_kind(pos, Terrain.Kind.BUILDING)
	return state.add_unit(type_id, owner, pos, 0)


func _begin() -> void:
	state.start()
	state.begin_turn()


# --- половина шкоди ---------------------------------------------------------------

func test_cover_halves_close_assault_golden() -> void:
	var a: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)
	var t: Unit = Unit.create(2, 0, 1, Vector2i.ZERO, 0)
	# Без укриття: (11.25 + 0..3) × 4 = 45..57; в укритті — навпіл, до підлоги: 22..28.
	assert_eq(Rules.damage_bounds(a, t, UnitTypes.ArmourSector.FRONT, 1), Vector2i(45, 57))
	assert_eq(Rules.damage_bounds(a, t, UnitTypes.ArmourSector.FRONT, 1, true), Vector2i(22, 28))


func test_cover_halving_keeps_the_minimum_damage_floor() -> void:
	var a: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)
	var t: Unit = Unit.create(2, 0, 1, Vector2i.ZERO, 0)
	# На дальності 11..14 навпіл — 5..7, але підлога 10 тримається.
	assert_eq(Rules.damage_bounds(a, t, UnitTypes.ArmourSector.FRONT, 9, true), Vector2i(10, 10))
	for s in 20:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		assert_eq(Rules.compute_damage(rng, a, t, UnitTypes.ArmourSector.FRONT, 9, true), 10)


func test_retaliation_into_cover_is_halved() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var answerer: Unit = state.add_unit(0, 0, Vector2i(4, 6), 0)
	_begin()
	state.active_player = 1
	state.begin_turn()
	FireCommand.create(c.id, answerer.id).apply(state)
	assert_true(answerer.is_alive(), "передумова: відповідач вижив")
	assert_between(100 - c.hp, 22, 28, "відповідь упритул по укриттю — навпіл")


func test_preview_shows_halved_damage_on_found_cover() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var a: Unit = state.add_unit(0, 0, Vector2i(4, 6), 0)
	_begin()
	var p: Dictionary = FireCommand.preview(state, a.id, c.id)
	assert_eq([p["min"], p["max"]], [22, 28])


func test_rubble_gives_no_cover() -> void:
	state.board.set_kind(Vector2i(4, 5), Terrain.Kind.RUBBLE)
	var t: Unit = state.add_unit(0, 1, Vector2i(4, 5), 0)
	var a: Unit = state.add_unit(0, 0, Vector2i(4, 6), 0)
	_begin()
	assert_false(Rules.in_cover(state.board, t))
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	assert_eq([p["min"], p["max"]], [45, 57])
	var far: Unit = state.add_unit(0, 0, Vector2i(4, 8), 0)
	assert_true(state.can_see_unit(0, t), "на руїнах — звичайні правила seen")
	assert_eq(FireCommand.check_shot(state, far, t), "")


func test_vehicle_on_building_is_not_in_cover() -> void:
	var tank: Unit = _cover(1, Vector2i(4, 5), 5)
	state.add_unit(0, 0, Vector2i(4, 8), 0)
	_begin()
	assert_false(Rules.in_cover(state.board, tank))
	assert_true(state.can_see_unit(0, tank))


# --- прихованість -----------------------------------------------------------------

func test_cover_unit_is_hidden_on_seen_ground_at_distance_two() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var a: Unit = state.add_unit(0, 0, Vector2i(2, 5), 0)
	_begin()
	assert_true(state.vision[0].is_seen(c.pos), "передумова: тайл розвіданий")
	assert_false(state.can_see_unit(0, c))
	assert_true(state.can_see_unit(1, c), "власник бачить свій юніт завжди")
	assert_false(state.known_occupied_map(0).has(c.pos))
	assert_eq(FireCommand.check_shot(state, a, c), "ERR_TARGET_NOT_VISIBLE")
	assert_does_not_have(Targeting.firing_targets(state, a.id), c)
	var ins: Dictionary = Targeting.inspection(state, c.id, 0)
	assert_eq(ins["radius"], 0, "прихований юніт не оглядається")
	assert_eq(Targeting.threatened_units(state, c.id, 0).size(), 0)


func test_hidden_assault_squad_shows_no_drone_threat() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5), 1)
	state.add_unit(5, 0, Vector2i(4, 8), 0)
	_begin()
	assert_eq(Targeting.drone_threatened_units(state, c.id, 0).size(), 0)


func test_found_at_diagonal_adjacency() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var a: Unit = state.add_unit(0, 0, Vector2i(3, 4), 0)
	_begin()
	assert_true(state.can_see_unit(0, c))
	assert_eq(FireCommand.check_shot(state, a, c), "")


func test_found_by_walking_next_to_it() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var a: Unit = state.add_unit(0, 0, Vector2i(1, 4), 0)
	_begin()
	assert_false(state.can_see_unit(0, c), "передумова: ще не знайдено")
	MoveCommand.create(a.id, Vector2i(3, 4)).apply(state)
	assert_true(state.can_see_unit(0, c))


func test_found_when_the_cover_unit_walks_in_next_to_an_enemy() -> void:
	state.board.set_kind(Vector2i(6, 5), Terrain.Kind.BUILDING)
	var c: Unit = state.add_unit(0, 1, Vector2i(5, 5), 0)
	state.add_unit(0, 0, Vector2i(7, 6), 0)
	_begin()
	state.active_player = 1
	state.begin_turn()
	MoveCommand.create(c.id, Vector2i(6, 5)).apply(state)
	assert_eq(c.pos, Vector2i(6, 5), "передумова: увійшов")
	assert_true(state.can_see_unit(0, c))


func test_entering_a_building_hides_from_everyone() -> void:
	state.board.set_kind(Vector2i(6, 5), Terrain.Kind.BUILDING)
	var c: Unit = state.add_unit(0, 1, Vector2i(5, 5), 0)
	state.add_unit(0, 0, Vector2i(2, 5), 0)
	_begin()
	assert_true(state.can_see_unit(0, c), "передумова: у полі видно")
	state.active_player = 1
	state.begin_turn()
	MoveCommand.create(c.id, Vector2i(6, 5)).apply(state)
	assert_eq(c.pos, Vector2i(6, 5), "передумова: увійшов")
	assert_false(state.can_see_unit(0, c))


func test_stays_found_after_the_finder_leaves() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var a: Unit = state.add_unit(0, 0, Vector2i(3, 4), 0)
	_begin()
	MoveCommand.create(a.id, Vector2i(1, 4)).apply(state)
	assert_eq(a.pos, Vector2i(1, 4), "передумова: пішов")
	assert_true(state.can_see_unit(0, c))
	state.pass_turn()
	state.pass_turn()
	assert_true(state.can_see_unit(0, c), "і на наступних ходах")


func test_leaving_the_building_clears_found() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	state.add_unit(0, 0, Vector2i(3, 4), 0)
	_begin()
	assert_eq(c.found_by, 1, "передумова: знайдено гравцем 0")
	state.active_player = 1
	state.begin_turn()
	MoveCommand.create(c.id, Vector2i(5, 5)).apply(state)
	assert_eq(c.found_by, 0)
	assert_true(state.can_see_unit(0, c), "поза будівлею — звичайні правила seen")


# --- знайдено влучанням -----------------------------------------------------------

func test_found_by_hitting_with_fire() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 8), 0)
	_begin()
	assert_false(state.can_see_unit(0, c), "передумова: прихований")
	state.active_player = 1
	state.begin_turn()
	FireCommand.create(c.id, tank.id).apply(state)
	assert_true(state.can_see_unit(0, c))


func test_found_by_hitting_with_a_drone() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5), 1)
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 9), 0)
	_begin()
	assert_false(state.can_see_unit(0, c), "передумова: прихований")
	state.active_player = 1
	state.begin_turn()
	DroneCommand.create(c.id, tank.id).apply(state)
	assert_true(state.can_see_unit(0, c))


func test_cover_unit_still_answers_fire() -> void:
	# Укриття не забирає відповіді (§3.3.1): ціль, знайдена сусідством, відповідає як завжди.
	var c: Unit = _cover(1, Vector2i(4, 5))
	var a: Unit = state.add_unit(0, 0, Vector2i(4, 6), 0)
	_begin()
	var b: Vector2i = Rules.damage_bounds(a, c, 0, 1, true)
	FireCommand.create(a.id, c.id).apply(state)
	assert_between(100 - c.hp, b.x, b.y, "прямий постріл по укриттю — навпіл")
	assert_lt(a.hp, 100)


func test_found_by_one_side_stays_hidden_from_another() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 3, 7)
	state.active_player = 0
	var c: Unit = _cover(1, Vector2i(4, 5))
	state.add_unit(0, 0, Vector2i(5, 6), 0)
	state.add_unit(0, 2, Vector2i(4, 7), 0)
	_begin()
	state.vision[2].recompute(state.board, state.alive_units(), 2)
	assert_true(state.vision[2].is_seen(c.pos))
	assert_true(state.can_see_unit(0, c), "сусід по діагоналі знайшов")
	assert_false(state.can_see_unit(2, c), "третій бік за дві клітинки — ні")


# --- планування -------------------------------------------------------------------

func test_planning_does_not_route_around_hidden_cover_and_the_walk_finds_it() -> void:
	# Коридор в один рядок: обходу немає, тож видимий юніт зробив би (3, 0) недосяжним.
	state = BattleState.create(Board.create(6, 1, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0
	var c: Unit = _cover(1, Vector2i(2, 0))
	var a: Unit = state.add_unit(0, 0, Vector2i(0, 0), 2)
	_begin()
	a.ap = 50  # вхід у будівлю коштує піхоті 30 — дати запас на прохід крізь неї
	assert_false(state.known_blocked_map(0).has(c.pos))
	var cmd: MoveCommand = MoveCommand.create(a.id, Vector2i(3, 0))
	assert_eq(cmd.validate(state), "", "маршрут іде крізь прихований юніт")
	var events: Array[Events.BattleEvent] = cmd.apply(state)
	assert_eq(a.pos, Vector2i(1, 0), "хід спиняється на тайлі перед ним")
	assert_true(events.any(func(e: Events.BattleEvent) -> bool: return e is Events.MoveBlocked))
	assert_true(state.can_see_unit(0, c), "і знаходить його сусідством")


# --- серіалізація -----------------------------------------------------------------

func test_found_by_round_trips() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	state.add_unit(0, 0, Vector2i(3, 4), 0)
	_begin()
	c.found_by = 5
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(state))
	assert_eq(b.get_unit(c.id).found_by, 5)


func test_a_save_without_found_by_finds_adjacent_on_load() -> void:
	var c: Unit = _cover(1, Vector2i(4, 5))
	state.add_unit(0, 0, Vector2i(4, 4), 0)
	_begin()
	var d: Dictionary = BattleSerializer.to_dict(state)
	for u: Dictionary in d["units"]:
		u.erase("found_by")
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_true(b.can_see_unit(0, b.get_unit(c.id)), "сусід знаходить одразу після завантаження")


func test_a_save_without_found_by_loads_as_unfound() -> void:
	_cover(1, Vector2i(4, 5))
	var d: Dictionary = BattleSerializer.to_dict(state)
	for u: Dictionary in d["units"]:
		u.erase("found_by")
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_eq(b.get_unit(1).found_by, 0)
