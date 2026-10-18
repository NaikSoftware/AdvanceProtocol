extends GutTest
## Task 4.5: міни на дошці активного гравця, наскрізно через battle_screen.tscn.
## Міну кладе інженер кнопкою панелі (T8): тап по інженеру, «Поставити міну»,
## тап по тайлу, підтвердження.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const ARMOURED_CAR: int = 2
const ENGINEER: int = 11
const W: int = 6
const E: int = 2

const ENG_POS := Vector2i(2, 1)
const MINE_POS := Vector2i(3, 1)

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i, facing: int = E) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": facing}


## Коридор у рядку 1: рядки 0 і 2 — вода, крім (3,2), тож броньовик із (6,1)
## до (3,2) має рівно один шлях — крізь MINE_POS.
func _corridor() -> Dictionary:
	var tiles: Dictionary = {}
	for x in 8:
		tiles[Vector2i(x, 0)] = Terrain.Kind.WATER
		if x != 3:
			tiles[Vector2i(x, 2)] = Terrain.Kind.WATER
	return tiles


func _boot(spawns: Array, with_mine: bool = true) -> void:
	await _e2e.boot(8, 3, spawns, {"tiles": _corridor(), "seed": 7})
	if with_mine:
		await _e2e.engineer_act(ENG_POS, EngineerCommand.Action.LAY_MINE, MINE_POS)


func _layer() -> MineLayer:
	return _e2e.screen.get_node("%MineLayer")


func _state() -> BattleState:
	return _e2e.service.state


func test_engineer_lays_mine_and_it_shows_for_owner() -> void:
	await _boot([_spawn(ENGINEER, 0, ENG_POS), _spawn(ARMOURED_CAR, 1, Vector2i(6, 1), W)])
	assert_eq(_state().mines.size(), 1)
	assert_eq(_state().unit_at(ENG_POS).ap, 0)
	assert_not_null(_layer().marker_at(MINE_POS))
	assert_eq(_layer().marker_at(MINE_POS).get_meta("style"), MineLayer.Style.OWN)


func test_own_mine_hidden_after_handover() -> void:
	await _boot([_spawn(ENGINEER, 0, ENG_POS), _spawn(ARMOURED_CAR, 1, Vector2i(6, 1), W)])
	assert_eq(_layer().marker_count(), 1)
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	assert_eq(_state().active_player, 1)
	assert_eq(_layer().marker_count(), 0)
	assert_eq(_layer().get_child_count(), 0)


func _p1_zone_segments(with_mine: bool) -> Array:
	await _boot([_spawn(ENGINEER, 0, ENG_POS), _spawn(ARMOURED_CAR, 1, Vector2i(6, 1), W)], with_mine)
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	_e2e.tap(Vector2i(6, 1))
	await _e2e.settle()
	var bv: BoardView = _e2e.screen.get_node("%BoardView")
	return bv.contour_segments(BoardView.LAYER_ZONES).duplicate(true)


func test_unrevealed_enemy_mine_leaves_no_trace_in_any_layer() -> void:
	var without: Array = await _p1_zone_segments(false)
	var with_mine: Array = await _p1_zone_segments(true)
	assert_eq(_state().mines.size(), 1)
	assert_false(without.is_empty(), "броньовик P1 мусить бути вибраним і мати зону")
	assert_eq(with_mine, without)
	assert_eq(_layer().marker_count(), 0)
	assert_eq(_layer().get_child_count(), 0)


## Seed 7, перший кидок матчу: randi_range(0, 90) = 32 → шкода 90 + 32 = 122,
## HP 250 - 122 = 128 (у межах [70, 160]). Укладання міни кидків не робить.
func test_driving_onto_mine_detonates_on_entry() -> void:
	await _boot([_spawn(ENGINEER, 0, ENG_POS), _spawn(ARMOURED_CAR, 1, Vector2i(6, 1), W)])
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	var car: Unit = _state().unit_at(Vector2i(6, 1))
	await _e2e.act(Vector2i(6, 1), Vector2i(3, 2))
	assert_eq(car.pos, MINE_POS)
	assert_eq(_e2e.events_of(Events.MineTriggered).size(), 1)
	assert_eq(car.hp, 128)
	assert_eq(_state().mines.size(), 0)
	assert_eq(_layer().marker_count(), 0)


func test_engineer_reveals_enemy_mine_in_its_diamond() -> void:
	# Інженер P1 на (6,1): |6-3| + 0 = 3 — рівно на межі ромба огляду 3.
	await _boot([_spawn(ENGINEER, 0, ENG_POS), _spawn(ENGINEER, 1, Vector2i(6, 1), W)])
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	var m: Node3D = _layer().marker_at(MINE_POS)
	assert_not_null(m)
	assert_eq(m.get_meta("style"), MineLayer.Style.ENEMY_REVEALED)
	assert_eq(_layer().marker_count(), 1)
