extends GutTest
## §3.2: танк валить ліс, у який в'їжджає; колісна техніка, артилерія та інженер
## у цілий ліс не в'їжджають, лише в просіки; піхота ліс не ламає.

const MEDIUM_TANK: int = 5
const RIFLE: int = 0
const ARMOURED_CAR: int = 2
const FIELD_GUN: int = 9
const ENGINEER: int = 11

var state: BattleState

func before_each() -> void:
	# Суцільна стіна лісу по x = 3: обійти її неможливо, тож досяжність тайла за нею
	# означає, що юніт пройшов крізь ліс.
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for y in 10:
		b.set_kind(Vector2i(3, y), Terrain.Kind.FOREST)
	state = BattleState.create(b, 2, 7)

func _tank_cuts_through() -> Unit:
	## Танк гравця 0 проходить (2,5) → (3,5) → (4,5) і лишає просіку на (3,5). Ціль
	## саме (4,5): до (4,4) є рівноцінний шлях крізь (3,4).
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(1, 5), 2)
	state.start()
	assert_eq(MoveCommand.create(tank.id, Vector2i(4, 5)).validate(state), "", "передумова: танк проходить ліс")
	MoveCommand.create(tank.id, Vector2i(4, 5)).apply(state)
	return tank

func test_a_tank_breaks_the_forest_it_enters_and_pays_the_forest_cost() -> void:
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(2, 5), 2)
	state.start()
	MoveCommand.create(tank.id, Vector2i(3, 5)).apply(state)
	assert_true(state.broken_forest.has(Vector2i(3, 5)), "ліс під танком повалено")
	assert_false(state.broken_forest.has(Vector2i(3, 4)), "сусідній ліс цілий")
	assert_eq(tank.ap, 48 - (10 + 20 - 12), "в'їзд у цілий ліс — за ціною лісу")

func test_every_tank_class_unit_passes_standing_forest() -> void:
	for type_id in [5, 6, 7, 8]:  # середній, винищувач танків, легкий, важкий
		assert_true(Rules.passes_standing_forest(Unit.create(0, type_id, 0, Vector2i.ZERO, 0)), "тип %d" % type_id)

func test_breaking_emits_forest_broken_once() -> void:
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(2, 5), 2)
	state.start()
	var events: Array = MoveCommand.create(tank.id, Vector2i(3, 5)).apply(state)
	var broken: Array = events.filter(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken)
	assert_eq(broken.size(), 1)
	assert_eq((broken[0] as Events.ForestBroken).pos, Vector2i(3, 5))
	# Повторний в'їзд у просіку нічого не валить.
	MoveCommand.create(tank.id, Vector2i(4, 5)).apply(state)
	tank.refill_ap()
	var again: Array = MoveCommand.create(tank.id, Vector2i(3, 5)).apply(state)
	assert_false(again.any(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken))

func _assert_blocked(type_id: int) -> void:
	var u: Unit = state.add_unit(type_id, 0, Vector2i(2, 5), 2)
	state.start()
	# Без заборони AP вистачило б: max(10, 30 - cross_country) <= max_ap.
	assert_true(Rules.entry_cost(u, 20) <= u.ap, "передумова: на ціну лісу AP вистачає")
	assert_eq(MoveCommand.create(u.id, Vector2i(3, 5)).validate(state), "ERR_OUT_OF_RANGE")
	assert_eq(Rules.entry_cost_at(u, state.board, Vector2i(3, 5)), Terrain.IMPASSABLE)

func test_a_light_vehicle_cannot_enter_standing_forest() -> void:
	_assert_blocked(ARMOURED_CAR)

func test_artillery_cannot_enter_standing_forest() -> void:
	_assert_blocked(FIELD_GUN)

func test_the_engineer_vehicle_cannot_enter_standing_forest() -> void:
	_assert_blocked(ENGINEER)

func test_light_vehicle_artillery_and_engineer_enter_a_broken_cell() -> void:
	for type_id in [ARMOURED_CAR, FIELD_GUN, ENGINEER]:
		before_each()
		_tank_cuts_through()
		var u: Unit = state.add_unit(type_id, 0, Vector2i(2, 5), 2)
		state.refresh_vision(0)
		assert_eq(MoveCommand.create(u.id, Vector2i(3, 5)).validate(state), "", "тип %d у просіку" % type_id)
		var before: int = state.broken_forest.size()
		var events: Array = MoveCommand.create(u.id, Vector2i(3, 5)).apply(state)
		assert_eq(u.pos, Vector2i(3, 5), "тип %d у просіці" % type_id)
		assert_false(events.any(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken), "тип %d лісу не валить" % type_id)
		assert_eq(state.broken_forest.size(), before, "тип %d не змінив просік" % type_id)

func test_infantry_walks_through_forest_and_never_breaks_it() -> void:
	var inf: Unit = state.add_unit(RIFLE, 0, Vector2i(2, 5), 2)
	state.start()
	var events: Array = MoveCommand.create(inf.id, Vector2i(4, 5)).apply(state)
	assert_eq(inf.pos, Vector2i(4, 5))
	assert_true(state.broken_forest.is_empty())
	assert_false(events.any(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken))

func test_broken_forest_costs_like_ordinary_ground() -> void:
	assert_eq(Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.DRY, true), 10)
	assert_eq(Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.MUD, true), 20, "грязь діє і на просіку")
	var car: Unit = Unit.create(1, ARMOURED_CAR, 0, Vector2i(2, 5), 2)
	assert_eq(Rules.entry_cost_at(car, state.board, Vector2i(3, 5), true), 10 + 10 - 5)
	var tank: Unit = Unit.create(2, MEDIUM_TANK, 0, Vector2i(2, 5), 2)
	assert_eq(Rules.entry_cost_at(tank, state.board, Vector2i(3, 5), true), 10, "танк на просіці платить підлогу")

func test_a_break_the_enemy_never_saw_is_absent_from_its_planning() -> void:
	# Окремий тайл лісу, а не стіна: тут ціль — сам тайл, і в нього можна потрапити
	# лише як у просіку.
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	b.set_kind(Vector2i(3, 5), Terrain.Kind.FOREST)
	state = BattleState.create(b, 2, 7)
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(3, 7), 0)
	var car: Unit = state.add_unit(ARMOURED_CAR, 1, Vector2i(7, 5), 6)
	state.start()
	MoveCommand.create(tank.id, Vector2i(3, 3)).apply(state)
	assert_true(state.broken_forest.has(Vector2i(3, 5)), "передумова: просіка є")
	assert_false(state.vision[1].is_seen(Vector2i(3, 5)), "передумова: гравець 1 її не бачив")
	assert_false(state.known_broken_map(1).has(Vector2i(3, 5)))
	assert_true(state.known_broken_map(0).has(Vector2i(3, 5)), "власник танка просіку знає")
	# Шлях 4 × 15 = 60 <= 68: за правдою досяжно, за знанням — ні.
	state.active_player = 1
	car.refill_ap()
	assert_eq(MoveCommand.create(car.id, Vector2i(3, 5)).validate(state), "ERR_OUT_OF_RANGE")
	var occupied: Dictionary = state.known_blocked_map(1)
	occupied.erase(car.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, car, occupied, state.known_broken_map(1))
	assert_false(zones.can_reach(Vector2i(3, 5)), "зони не доносять про невидимий танк")

func test_the_enemy_learns_the_break_once_it_scouts_the_tile() -> void:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	b.set_kind(Vector2i(3, 5), Terrain.Kind.FOREST)
	state = BattleState.create(b, 2, 7)
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(3, 7), 0)
	var car: Unit = state.add_unit(ARMOURED_CAR, 1, Vector2i(7, 5), 6)
	state.start()
	MoveCommand.create(tank.id, Vector2i(3, 3)).apply(state)
	state.active_player = 1
	car.refill_ap()
	MoveCommand.create(car.id, Vector2i(6, 5)).apply(state)
	assert_true(state.vision[1].is_seen(Vector2i(3, 5)), "передумова: тайл розвідано")
	assert_true(state.known_broken_map(1).has(Vector2i(3, 5)))
	assert_eq(MoveCommand.create(car.id, Vector2i(3, 5)).validate(state), "")

func test_the_walk_charges_the_true_forest_cost_not_the_believed_one() -> void:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	b.set_kind(Vector2i(3, 5), Terrain.Kind.FOREST)
	state = BattleState.create(b, 2, 7)
	var breaker: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(3, 7), 0)
	state.start()
	MoveCommand.create(breaker.id, Vector2i(3, 3)).apply(state)
	# Танк гравця 1 з'являється після start(): його seen порожня, тож просіку він не знає,
	# і планує крізь ліс, який має за цілий, — а ціна кроку мусить бути за правдою.
	var tank: Unit = state.add_unit(MEDIUM_TANK, 1, Vector2i(2, 5), 6)
	state.active_player = 1
	tank.refill_ap()
	assert_false(state.known_broken_map(1).has(Vector2i(3, 5)), "передумова: гравець 1 просіки не знає")
	var ap_before: int = tank.ap
	MoveCommand.create(tank.id, Vector2i(4, 5)).apply(state)
	assert_eq(tank.pos, Vector2i(4, 5))
	assert_eq(ap_before - tank.ap, 10 + 10, "обидва кроки — за ціною просіки, а не цілого лісу")

func test_a_move_stopped_before_an_unseen_unit_in_forest_does_not_break_it() -> void:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	b.set_kind(Vector2i(3, 5), Terrain.Kind.FOREST)
	state = BattleState.create(b, 2, 7)
	state.start()
	# Обидва юніти додано після start(): гравець 0 піхоту в лісі не бачить.
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(2, 5), 2)
	state.add_unit(RIFLE, 1, Vector2i(3, 5), 6)
	var events: Array = MoveCommand.create(tank.id, Vector2i(4, 5)).apply(state)
	assert_true(events.any(func(e: Events.BattleEvent) -> bool: return e is Events.MoveBlocked), "передумова: хід обірвано")
	assert_eq(tank.pos, Vector2i(2, 5))
	assert_true(state.broken_forest.is_empty(), "танк у ліс не в'їхав — нічого не повалено")
	assert_false(events.any(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken))

func test_a_tank_breaks_the_forest_even_when_a_mine_goes_off_there() -> void:
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(2, 5), 2)
	Mines.place(state, Vector2i(3, 5), 1)
	state.start()
	var events: Array = MoveCommand.create(tank.id, Vector2i(4, 5)).apply(state)
	assert_eq(tank.pos, Vector2i(3, 5), "міна спинила танк на собі")
	assert_true(state.broken_forest.has(Vector2i(3, 5)), "танк уже в'їхав — дерева впали")
	assert_true(events.any(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken))

func test_broken_forest_survives_save_and_load() -> void:
	_tank_cuts_through()
	var loaded: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(state))
	assert_not_null(loaded)
	assert_eq(loaded.broken_forest.keys(), [Vector2i(3, 5)])
	assert_eq(loaded.known_broken_map(0).keys(), [Vector2i(3, 5)], "знання — з seen, воно теж зберігається")
	assert_true(loaded.known_broken_map(1).is_empty())

func test_a_save_without_broken_forest_loads_with_none() -> void:
	var d: Dictionary = BattleSerializer.to_dict(state)
	d.erase("broken_forest")
	var loaded: BattleState = BattleSerializer.from_dict(d)
	assert_not_null(loaded, "старі збереження мусять відкриватися")
	assert_true(loaded.broken_forest.is_empty())

func test_a_save_breaking_a_non_forest_tile_is_rejected() -> void:
	var d: Dictionary = BattleSerializer.to_dict(state)
	d["broken_forest"] = [{"x": 1, "y": 1}]
	assert_null(BattleSerializer.from_dict(d), "просіка буває лише в лісі")
