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
	assert_eq(cmd.validate(state), "ERR_NOT_ADJACENT", "§3.8: лише ортогонально сусідній тайл")

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

func test_repair_amount_at_full_ap_ranges_up_to_the_ap_bonus() -> void:
	# §3.8: (40 + rand(0, ap_left - fire_cost)) / 2. Engineer squad (type 11):
	# max_ap 68, fire_cost 20 -> n = 48 at full AP.
	# roll=0   (mininum of rand(0,48))  -> (40+0)/2  = 20  — the floor.
	# roll=48  (maximum of rand(0,48))  -> (40+48)/2 = 44  — the ceiling.
	# Sampled across many seeds (same idiom as test_rules_damage.gd's _samples()),
	# so the assertion is on the formula's exact analytical bounds, not on one
	# seed's arbitrary output.
	var fresh: Unit = _engineer(Vector2i(1, 1))
	var lo: int = 999999
	var hi: int = -999999
	for s in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var v: int = EngineerCommand.repair_amount(rng, fresh)
		lo = mini(lo, v)
		hi = maxi(hi, v)
	assert_eq(lo, 20, "roll=0 -> (40+0)/2 = 20")
	assert_eq(hi, 44, "roll=48 -> (40+48)/2 = 44 — повні AP піднімають стелю")

func test_repair_amount_is_exactly_the_floor_when_ap_is_spent() -> void:
	# ap_left == fire_cost -> n = 0. Rules.roll() returns 0 for n <= 0 WITHOUT
	# reading the rng at all, so this is deterministic regardless of seed —
	# no sampling needed to know it is exactly 20 every time.
	var tired: Unit = _engineer(Vector2i(8, 8))
	tired.ap = tired.fire_cost()
	for s in 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		assert_eq(EngineerCommand.repair_amount(rng, tired), 20,
			"§3.8: інженер, що весь хід їхав, ремонтує рівно на підлогу формули")

func test_repair_apply_produces_the_hand_derived_hp_delta() -> void:
	# Integration test through the real apply(), to catch an AP/repair
	# ordering regression that a pure repair_amount() test cannot see (it
	# never touches AP state at all).
	#
	# Ground truth for the derivation: BattleState.create(..., 21) in
	# before_each seeds state.rng with 21. Nothing before this call consumes
	# state.rng (BattleState.create()/add_unit() never touch it), so this is
	# the very first draw. Independently probed with RandomNumberGenerator
	# directly (NOT via EngineerCommand/repair_amount — the RNG primitive
	# Rules.roll() itself wraps, not the code under test):
	#   seed=21, first randi_range(0, 48) == 11
	# n = 48 because the engineer (type 11) is at full AP (68) minus its
	# fire_cost (20). repair_amount = (40 + 11) / 2 = 25 (int division of
	# 51/2 truncates). friend starts at hp=100, so hp_left = 125.
	var e: Unit = _engineer(Vector2i(4, 4))
	var friend: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	friend.hp = 100
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).apply(state)
	assert_eq(friend.hp, 125, "seed 21: roll=11 -> (40+11)/2=25 -> 100+25")

func test_repair_of_enemy_unit_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var enemy: Unit = state.add_unit(5, 1, Vector2i(4, 3), 0)
	enemy.hp = 1  # damaged, not merely undamaged — isolates the ownership check:
	# an enemy at full HP would also be rejected as "undamaged", which would
	# pass even if the ownership check were deleted outright.
	assert_eq(EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).validate(state),
		"ERR_NO_FRIENDLY_UNIT_THERE")

func test_non_engineer_cannot_use_engineer_actions() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_eq(EngineerCommand.create(tank.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3)).validate(state),
		"ERR_NOT_AN_ENGINEER")

func test_action_without_enough_ap_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	e.ap = 1
	assert_eq(EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3)).validate(state),
		"ERR_NOT_ENOUGH_AP")

func test_capture_objective_flips_ownership() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	Objectives.add(state, Vector2i(4, 3), -1)
	EngineerCommand.create(e.id, EngineerCommand.Action.CAPTURE_OBJECTIVE, Vector2i(4, 3)).apply(state)
	assert_eq(Objectives.at(state, Vector2i(4, 3)).owner, 0)
