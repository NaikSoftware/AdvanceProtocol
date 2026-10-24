extends GutTest
## Уламки знищеної техніки: лишаються на тайлі, перекривають його лише техніці,
## догоряють за Wrecks.WRECK_ROUNDS повних кіл і знані лише над розвіданим.
##
## Дошка — дві дорожні смуги (y = 4 і y = 5), як у тестах мін у test_move_command.gd:
## транспортер (ap 68) платить 10 за тайл, тож прямо до (4,5) — 4 тайли, в обхід (2,5) — 6.

func _two_lane_state(players: int = 2) -> BattleState:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b.set_kind(Vector2i(x, 4), Terrain.Kind.ROAD)
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	var s: BattleState = BattleState.create(b, players, 11)
	s.active_player = 0
	return s

func _inject(s: BattleState, pos: Vector2i) -> void:
	# Уламки, що догорять нескоро, — для тестів руху й планування, де причина смерті неважлива.
	s.wrecks.append(Wrecks.Wreck.new(pos, 4, 1000))

func _index_of(events: Array, kind: Variant) -> int:
	for i in events.size():
		if is_instance_of(events[i], kind):
			return i
	return -1

func _count(events: Array, kind: Variant) -> int:
	return events.filter(func(e: Events.BattleEvent) -> bool: return is_instance_of(e, kind)).size()

func _assert_wreck_left(events: Array, pos: Vector2i, type_id: int) -> void:
	var destroyed: int = _index_of(events, Events.UnitDestroyed)
	var left: int = _index_of(events, Events.WreckLeft)
	assert_true(destroyed >= 0, "передумова: юніт знищено")
	assert_eq(left, destroyed + 1, "WreckLeft іде одразу за UnitDestroyed")
	if left >= 0:
		var e: Events.WreckLeft = events[left]
		assert_eq(e.pos, pos)
		assert_eq(e.type_id, type_id)

# --- Хто лишає уламки ---------------------------------------------------------

func test_a_vehicle_killed_by_a_shot_leaves_a_wreck() -> void:
	var s: BattleState = _two_lane_state()
	var tank: Unit = s.add_unit(5, 0, Vector2i(0, 5), 2)
	var car: Unit = s.add_unit(4, 1, Vector2i(3, 5), 6)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	car.hp = 1
	s.start()
	var events: Array = FireCommand.create(tank.id, car.id).apply(s)
	_assert_wreck_left(events, Vector2i(3, 5), 4)
	assert_not_null(Wrecks.wreck_at(s, Vector2i(3, 5)))

func test_infantry_leaves_no_wreck() -> void:
	var s: BattleState = _two_lane_state()
	var tank: Unit = s.add_unit(5, 0, Vector2i(0, 5), 2)
	var squad: Unit = s.add_unit(0, 1, Vector2i(3, 5), 6)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	squad.hp = 1
	s.start()
	var events: Array = FireCommand.create(tank.id, squad.id).apply(s)
	assert_false(squad.is_alive(), "передумова: відділення знищено")
	assert_eq(_count(events, Events.WreckLeft), 0)
	assert_null(Wrecks.wreck_at(s, Vector2i(3, 5)))

func test_a_vehicle_killed_by_retaliation_leaves_a_wreck() -> void:
	var s: BattleState = _two_lane_state()
	var car: Unit = s.add_unit(4, 0, Vector2i(0, 5), 2)
	var tank: Unit = s.add_unit(5, 1, Vector2i(2, 5), 6)
	car.hp = 1
	s.start()
	var events: Array = FireCommand.create(car.id, tank.id).apply(s)
	assert_true(tank.is_alive(), "передумова: танк пережив постріл і відповів")
	_assert_wreck_left(events, Vector2i(0, 5), 4)

func test_a_vehicle_killed_by_a_drone_leaves_a_wreck() -> void:
	var s: BattleState = _two_lane_state()
	var squad: Unit = s.add_unit(1, 0, Vector2i(0, 5), 2)
	var car: Unit = s.add_unit(4, 1, Vector2i(4, 5), 6)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	car.hp = 1
	s.start()
	var events: Array = DroneCommand.create(squad.id, car.id).apply(s)
	_assert_wreck_left(events, Vector2i(4, 5), 4)

func test_a_vehicle_killed_by_a_mine_leaves_a_wreck_on_the_mine_tile() -> void:
	var s: BattleState = _two_lane_state()
	var car: Unit = s.add_unit(4, 0, Vector2i(0, 5), 2)
	s.add_unit(0, 0, Vector2i(9, 0), 0)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	Mines.place(s, Vector2i(2, 5), 1)
	car.hp = 1
	s.start()
	var events: Array = MoveCommand.create(car.id, Vector2i(3, 5)).apply(s)
	assert_false(car.is_alive(), "передумова: міна вбила машину")
	_assert_wreck_left(events, Vector2i(2, 5), 4)
	assert_null(Mines.mine_at(s, Vector2i(2, 5)), "міна витрачена, уламки лежать на її місці")

func test_conceding_leaves_wrecks_of_vehicles_only() -> void:
	var s: BattleState = _two_lane_state()
	s.add_unit(5, 0, Vector2i(0, 5), 2)
	s.add_unit(0, 0, Vector2i(0, 4), 2)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	var events: Array = ConcedeCommand.create().apply(s)
	assert_eq(_count(events, Events.WreckLeft), 1, "уламки лишає танк, а не відділення")
	assert_not_null(Wrecks.wreck_at(s, Vector2i(0, 5)))
	assert_null(Wrecks.wreck_at(s, Vector2i(0, 4)))
	assert_eq(s.winner, 1, "§3.10: уламки — не живий юніт, переможця це не змінює")

# --- Міст ---------------------------------------------------------------------

func _bridge_state() -> BattleState:
	var s: BattleState = _two_lane_state()
	s.board.set_kind(Vector2i(4, 5), Terrain.Kind.BRIDGE)
	return s

func test_demolishing_a_bridge_removes_the_wreck_on_it() -> void:
	var s: BattleState = _bridge_state()
	var eng: Unit = s.add_unit(11, 0, Vector2i(4, 4), 0)
	_inject(s, Vector2i(4, 5))
	var cmd: EngineerCommand = EngineerCommand.create(eng.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 5))
	assert_eq(cmd.validate(s), "", "уламки підрив мосту не забороняють")
	var events: Array = cmd.apply(s)
	assert_null(Wrecks.wreck_at(s, Vector2i(4, 5)))
	var i: int = _index_of(events, Events.WreckRemoved)
	assert_true(i > _index_of(events, Events.BridgeChanged), "WreckRemoved — після BridgeChanged")
	if i >= 0:
		var e: Events.WreckRemoved = events[i]
		assert_eq(e.pos, Vector2i(4, 5))
		assert_eq(e.reason, Wrecks.Reason.BRIDGE_DEMOLISHED)

func test_a_vehicle_lost_with_a_bridge_leaves_no_wreck() -> void:
	var s: BattleState = _bridge_state()
	var eng: Unit = s.add_unit(11, 0, Vector2i(4, 4), 0)
	var car: Unit = s.add_unit(4, 1, Vector2i(4, 5), 0)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	var events: Array = EngineerCommand.create(eng.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 5)).apply(s)
	assert_false(car.is_alive(), "передумова: машина впала разом із мостом")
	assert_eq(_count(events, Events.WreckLeft), 0, "машина впала в річку")
	assert_null(Wrecks.wreck_at(s, Vector2i(4, 5)))

# --- Планування й хід ---------------------------------------------------------

func test_a_seen_wreck_is_in_the_known_blocked_map_with_its_own_value() -> void:
	var s: BattleState = _two_lane_state()
	s.add_unit(3, 0, Vector2i(0, 5), 2)
	_inject(s, Vector2i(2, 5))
	s.start()
	var blocked: Dictionary = s.known_blocked_map(0)
	assert_true(blocked.has(Vector2i(2, 5)))
	assert_eq(blocked.get(Vector2i(2, 5)), Wrecks.BLOCKED)
	assert_ne(Wrecks.BLOCKED, -1, "значення відмінне від міни")
	assert_false(s.known_occupied_map(0).has(Vector2i(2, 5)),
		"мапа зайнятості юнітами уламків не включає — її читають види юнітів")

func test_an_unseen_wreck_is_not_in_the_known_blocked_map() -> void:
	var s: BattleState = _two_lane_state()
	s.add_unit(3, 0, Vector2i(0, 5), 2)
	_inject(s, Vector2i(5, 5))
	s.start()
	assert_false(s.vision[0].is_seen(Vector2i(5, 5)), "передумова: тайл не розвіданий")
	assert_false(s.known_blocked_map(0).has(Vector2i(5, 5)),
		"§3.5: нерозвідані уламки не мають виказувати себе формою маршруту")

func test_a_vehicle_routes_around_a_seen_wreck() -> void:
	var s: BattleState = _two_lane_state()
	var u: Unit = s.add_unit(3, 0, Vector2i(0, 5), 2)
	_inject(s, Vector2i(2, 5))
	s.start()
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(4, 5))
	assert_eq(cmd.validate(s), "")
	var events: Array = cmd.apply(s)
	var moved: Events.UnitMoved = events[0]
	assert_false(Vector2i(2, 5) in moved.path, "відомі уламки об'їжджають")
	assert_eq(u.pos, Vector2i(4, 5))
	assert_eq(u.ap, 8, "68 − 6×10: заплачено за гак")

func test_a_seen_wreck_is_neither_a_vehicle_destination_nor_in_its_zones() -> void:
	var s: BattleState = _two_lane_state()
	var u: Unit = s.add_unit(3, 0, Vector2i(0, 5), 2)
	_inject(s, Vector2i(2, 5))
	s.start()
	assert_eq(MoveCommand.create(u.id, Vector2i(2, 5)).validate(s), "ERR_OUT_OF_RANGE")
	var blocked: Dictionary = s.known_blocked_map(0)
	blocked.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(s.board, u, blocked)
	assert_false(zones.can_reach(Vector2i(2, 5)), "контур зони обгинає уламки")
	assert_true(zones.can_reach(Vector2i(3, 5)), "за уламками дорога далі відкрита — в обхід")

func test_infantry_walks_onto_and_through_a_wreck() -> void:
	var s: BattleState = _two_lane_state()
	var squad: Unit = s.add_unit(0, 0, Vector2i(0, 5), 2)
	_inject(s, Vector2i(1, 5))
	s.start()
	var blocked: Dictionary = s.known_blocked_map(0)
	blocked.erase(squad.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(s.board, squad, blocked)
	assert_true(zones.can_reach(Vector2i(1, 5)), "піхота стає на уламки")
	assert_eq(zones.cost_to(Vector2i(2, 5)), 20, "і йде крізь них прямо")
	assert_eq(MoveCommand.create(squad.id, Vector2i(1, 5)).validate(s), "")
	MoveCommand.create(squad.id, Vector2i(1, 5)).apply(s)
	assert_eq(squad.pos, Vector2i(1, 5))
	MoveCommand.create(squad.id, Vector2i(2, 5)).apply(s)
	assert_eq(squad.pos, Vector2i(2, 5))

func test_an_unseen_wreck_is_planned_through_and_the_vehicle_stops_before_it() -> void:
	var s: BattleState = _two_lane_state()
	var u: Unit = s.add_unit(3, 0, Vector2i(0, 5), 2)
	_inject(s, Vector2i(5, 5))
	s.start()
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(6, 5))
	assert_eq(cmd.validate(s), "", "ціль за нерозвіданими уламками — законний наказ")
	var events: Array = cmd.apply(s)
	assert_eq(u.pos, Vector2i(4, 5), "спинився перед уламками")
	assert_eq(u.ap, 28, "68 − 4×10: заплачено лише за пройдені тайли")
	var i: int = _index_of(events, Events.MoveBlocked)
	assert_true(i >= 0, "обрив — це подія")
	if i >= 0:
		assert_eq((events[i] as Events.MoveBlocked).pos, Vector2i(5, 5))
	assert_true(s.known_blocked_map(0).has(Vector2i(5, 5)), "тепер тайл розвіданий, і уламки відомі")

# --- Догоряння ----------------------------------------------------------------

func _end_turns(s: BattleState, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append_array(EndTurnCommand.create().apply(s))
	return out

func test_a_wreck_burns_out_after_exactly_wreck_rounds_rounds() -> void:
	# Знищено на ході гравця 0 у колі 1. Кожен живий гравець мусить мати WRECK_ROUNDS
	# ходів після появи: гравець 1 — кола 1–3, гравець 0 — залишок кола 1 і кола 2–3.
	# Тож догоряє на початку ходу гравця 0 у колі 4, тобто після 6 передач ходу.
	assert_eq(Wrecks.WRECK_ROUNDS, 3)
	var s: BattleState = _two_lane_state()
	var tank: Unit = s.add_unit(5, 0, Vector2i(0, 5), 2)
	var car: Unit = s.add_unit(4, 1, Vector2i(3, 5), 6)
	s.add_unit(0, 1, Vector2i(9, 9), 0)
	car.hp = 1
	s.start()
	s.begin_turn()
	FireCommand.create(tank.id, car.id).apply(s)
	var before: Array = _end_turns(s, 5)
	assert_eq(_count(before, Events.WreckRemoved), 0)
	assert_not_null(Wrecks.wreck_at(s, Vector2i(3, 5)), "коло 4, хід гравця 1 — ще горить")
	var last: Array = _end_turns(s, 1)
	assert_eq([s.turn_number, s.active_player], [4, 0])
	assert_null(Wrecks.wreck_at(s, Vector2i(3, 5)))
	var i: int = _index_of(last, Events.WreckRemoved)
	assert_true(i >= 0)
	if i >= 0:
		var e: Events.WreckRemoved = last[i]
		assert_eq(e.pos, Vector2i(3, 5))
		assert_eq(e.reason, Wrecks.Reason.BURNED_OUT)
		assert_true(i > _index_of(last, Events.TurnStarted), "догоряє вже на новому ходу")

func test_a_wreck_left_on_the_second_players_turn_burns_out_on_that_players_turn() -> void:
	var s: BattleState = _two_lane_state()
	var car: Unit = s.add_unit(4, 0, Vector2i(3, 5), 6)
	var tank: Unit = s.add_unit(5, 1, Vector2i(0, 5), 2)
	s.add_unit(0, 0, Vector2i(9, 9), 0)
	car.hp = 1
	s.start()
	_end_turns(s, 1)
	assert_eq(s.active_player, 1, "передумова")
	FireCommand.create(tank.id, car.id).apply(s)
	_end_turns(s, 5)
	assert_not_null(Wrecks.wreck_at(s, Vector2i(3, 5)), "коло 4, хід гравця 0 — ще горить")
	_end_turns(s, 1)
	assert_eq([s.turn_number, s.active_player], [4, 1])
	assert_null(Wrecks.wreck_at(s, Vector2i(3, 5)))
