extends GutTest
## Уламки (§3.14) і просіки (§3.2) в одному ході: обидва правила живуть у циклі
## MoveCommand.apply(), і порядок перевірок у ньому — це спостережувана поведінка.

const MEDIUM_TANK: int = 5
const RIFLE: int = 0
const ARMOURED_CAR: int = 2

var state: BattleState
const FOREST_TILE := Vector2i(3, 5)

func before_each() -> void:
	# Один тайл лісу на відкритому полі: в обхід нього є шлях, тож «у ліс» — вибір.
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	b.set_kind(FOREST_TILE, Terrain.Kind.FOREST)
	state = BattleState.create(b, 2, 7)

func _index_of(events: Array, kind: Variant) -> int:
	for i in events.size():
		if is_instance_of(events[i], kind):
			return i
	return -1

func test_an_unseen_wreck_in_standing_forest_stops_the_tank_before_it_and_breaks_nothing() -> void:
	state.add_unit(RIFLE, 0, Vector2i(9, 0), 0)
	state.add_unit(RIFLE, 1, Vector2i(9, 9), 0)
	state.start()
	# Уламки лежать у цілому лісі; танк додано після start(), тож його seen порожня.
	state.wrecks.append(Wrecks.Wreck.new(FOREST_TILE, MEDIUM_TANK, 0, 1000))
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(0, 5), 2)
	assert_false(state.vision[0].is_seen(FOREST_TILE), "передумова: тайл не розвіданий")
	var cmd: MoveCommand = MoveCommand.create(tank.id, FOREST_TILE)
	assert_eq(cmd.validate(state), "", "передумова: наказ законний")
	var events: Array = cmd.apply(state)
	assert_eq(tank.pos, Vector2i(2, 5), "спинився на тайлі перед лісом")
	assert_eq(tank.ap, 48 - 20, "платить лише за два тайли, у які ввійшов")
	var i: int = _index_of(events, Events.MoveBlocked)
	assert_true(i >= 0, "обрив — це подія")
	if i >= 0:
		assert_eq((events[i] as Events.MoveBlocked).pos, FOREST_TILE)
	assert_false(state.broken_forest.has(FOREST_TILE), "танк у ліс не в'їхав — нічого не повалено")
	assert_eq(_index_of(events, Events.ForestBroken), -1, "ForestBroken немає")

func test_a_tank_killed_by_a_mine_in_forest_breaks_it_and_leaves_a_wreck_in_order() -> void:
	var tank: Unit = state.add_unit(MEDIUM_TANK, 0, Vector2i(2, 5), 2)
	state.add_unit(RIFLE, 0, Vector2i(9, 0), 0)
	state.add_unit(RIFLE, 1, Vector2i(9, 9), 0)
	Mines.place(state, FOREST_TILE, 1)
	tank.hp = 1
	state.start()
	var events: Array = MoveCommand.create(tank.id, Vector2i(4, 5)).apply(state)
	assert_false(tank.is_alive(), "передумова: міна вбила танк")
	assert_true(state.broken_forest.has(FOREST_TILE), "дерева впали від в'їзду")
	assert_not_null(Wrecks.wreck_at(state, FOREST_TILE), "уламки лежать на просіці")
	var broken: int = _index_of(events, Events.ForestBroken)
	var mine: int = _index_of(events, Events.MineTriggered)
	var dead: int = _index_of(events, Events.UnitDestroyed)
	var left: int = _index_of(events, Events.WreckLeft)
	assert_true(broken >= 0 and mine >= 0 and dead >= 0 and left >= 0, "усі чотири події є")
	assert_true(broken < mine and mine < dead and dead < left, "ForestBroken < MineTriggered < UnitDestroyed < WreckLeft")

	# Тайл розвіданий (танк на ньому стояв), тож уламки відомі гравцеві 0.
	assert_true(state.vision[0].is_seen(FOREST_TILE))
	var car: Unit = state.add_unit(ARMOURED_CAR, 0, Vector2i(2, 5), 2)
	assert_eq(MoveCommand.create(car.id, FOREST_TILE).validate(state), "ERR_OUT_OF_RANGE", "уламки на просіці не пускають техніку")
	var cmd: MoveCommand = MoveCommand.create(car.id, Vector2i(4, 4))
	assert_eq(cmd.validate(state), "")
	var moved: Events.UnitMoved = cmd.apply(state)[0]
	assert_false(FOREST_TILE in moved.path, "легка техніка обминає уламки")
	assert_eq(car.pos, Vector2i(4, 4))

	var inf: Unit = state.add_unit(RIFLE, 0, Vector2i(2, 5), 2)
	assert_eq(MoveCommand.create(inf.id, Vector2i(4, 5)).validate(state), "")
	var path: Array = (MoveCommand.create(inf.id, Vector2i(4, 5)).apply(state)[0] as Events.UnitMoved).path
	assert_true(FOREST_TILE in path, "піхота йде крізь уламки найкоротшим шляхом")
