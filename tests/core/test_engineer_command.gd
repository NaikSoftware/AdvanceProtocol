extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 21)
	state.active_player = 0

func _engineer(pos: Vector2i) -> Unit:
	return state.add_unit(11, 0, pos, 0)

func test_lay_mine_on_adjacent_tile() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var cmd: EngineerCommand = EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3))
	assert_eq(cmd.validate(state), "")
	cmd.apply(state)
	assert_not_null(Mines.mine_at(state, Vector2i(4, 3)))
	assert_true(e.ap < e.max_ap(), "дія коштує fire_cost")

func test_diagonal_target_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var cmd: EngineerCommand = EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(5, 5))
	assert_ne(cmd.validate(state), "", "§3.8: лише ортогонально сусідній тайл")

func test_clear_mine_removes_it() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	Mines.place(state, Vector2i(4, 3), 1)
	EngineerCommand.create(e.id, EngineerCommand.Action.CLEAR_MINE, Vector2i(4, 3)).apply(state)
	assert_null(Mines.mine_at(state, Vector2i(4, 3)))

func test_demolish_bridge_reshapes_the_map() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	var e: Unit = _engineer(Vector2i(4, 4))
	EngineerCommand.create(e.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 3)).apply(state)
	assert_eq(state.board.kind_at(Vector2i(4, 3)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_false(state.board.is_passable(Vector2i(4, 3)))

func test_repair_bridge_restores_it() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE_DESTROYED)
	var e: Unit = _engineer(Vector2i(4, 4))
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_BRIDGE, Vector2i(4, 3)).apply(state)
	assert_eq(state.board.kind_at(Vector2i(4, 3)), Terrain.Kind.BRIDGE)

func test_repair_heals_a_damaged_friendly_unit() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var friend: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	friend.hp = 100
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).apply(state)
	assert_true(friend.hp > 100)
	assert_true(friend.hp <= friend.max_hp(), "лікування не перевищує максимум")

func test_repair_is_worse_when_the_engineer_drove_all_turn() -> void:
	var fresh: Unit = _engineer(Vector2i(1, 1))
	var tired: Unit = _engineer(Vector2i(8, 8))
	tired.ap = tired.fire_cost()
	var a: int = EngineerCommand.repair_amount(state.rng, fresh)
	var b: int = EngineerCommand.repair_amount(state.rng, tired)
	assert_true(a >= b, "§3.8: єдине місце, де невитрачені AP щось означають")

func test_repair_of_enemy_unit_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	state.add_unit(5, 1, Vector2i(4, 3), 0)
	assert_ne(EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).validate(state), "")

func test_non_engineer_cannot_use_engineer_actions() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_ne(EngineerCommand.create(tank.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3)).validate(state), "")

func test_action_without_enough_ap_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	e.ap = 1
	assert_ne(EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3)).validate(state), "")

func test_capture_objective_flips_ownership() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	Objectives.add(state, Vector2i(4, 3), -1)
	EngineerCommand.create(e.id, EngineerCommand.Action.CAPTURE_OBJECTIVE, Vector2i(4, 3)).apply(state)
	assert_eq(Objectives.at(state, Vector2i(4, 3)).owner, 0)
