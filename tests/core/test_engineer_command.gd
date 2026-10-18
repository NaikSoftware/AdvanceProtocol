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
	assert_false(state.board.penalty_at(Vector2i(4, 3)) < Terrain.IMPASSABLE)

## Рішення власника: міст підривається разом із ворогом, що на ньому стоїть, —
## юніт гине, шкода зараховується власникові інженера. Свій юніт
## на мосту — заборона: інженер не скидає своїх у річку.
func test_demolishing_a_bridge_under_an_enemy_destroys_it() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	var e: Unit = _engineer(Vector2i(4, 4))
	var enemy: Unit = state.add_unit(5, 1, Vector2i(4, 3), 0)
	var reserve: Unit = state.add_unit(5, 1, Vector2i(9, 9), 0)
	var hp_before: int = enemy.hp
	var cmd: EngineerCommand = EngineerCommand.create(e.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 3))
	assert_eq(cmd.validate(state), "", "ворог на мосту не заважає підриву")
	var events: Array = cmd.apply(state)

	assert_eq(state.board.kind_at(Vector2i(4, 3)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_false(enemy.is_alive(), "юніт на підірваному мосту гине")
	assert_eq(state.damage_dealt[0], hp_before, "уся решта hp — на рахунок власника інженера")
	var dealt: int = -1
	var destroyed: int = -1
	for i in events.size():
		if events[i] is Events.DamageDealt and events[i].unit_id == enemy.id:
			dealt = i
			assert_eq(events[i].amount, hp_before)
		if events[i] is Events.UnitDestroyed and events[i].unit_id == enemy.id:
			destroyed = i
	assert_true(dealt >= 0 and destroyed > dealt, "DamageDealt, потім UnitDestroyed — як від смертельного влучання")
	assert_true(reserve.is_alive() and not state.is_over(), "у гравця 1 лишився юніт — матч триває")

func test_demolishing_a_bridge_under_the_last_enemy_unit_ends_the_match() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	var e: Unit = _engineer(Vector2i(4, 4))
	state.add_unit(5, 1, Vector2i(4, 3), 0)
	var events: Array = EngineerCommand.create(e.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 3)).apply(state)
	assert_eq(state.winner, 0, "останній юніт гравця 1 загинув — check_elimination() завершує матч")
	var eliminated: bool = false
	for ev in events:
		if ev is Events.PlayerEliminated and ev.player == 1:
			eliminated = true
	assert_true(eliminated, "PlayerEliminated у потоці подій")

func test_demolishing_a_bridge_under_an_own_unit_is_rejected() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	var e: Unit = _engineer(Vector2i(4, 4))
	var own: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	var cmd: EngineerCommand = EngineerCommand.create(e.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 3))
	assert_eq(cmd.validate(state), "ERR_TILE_OCCUPIED")
	assert_eq(state.board.kind_at(Vector2i(4, 3)), Terrain.Kind.BRIDGE, "міст цілий")
	assert_true(own.is_alive())
	assert_eq(e.ap, e.max_ap(), "AP не списано")

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
	# §3.8: (40 + rand(0, ap_left - fire_cost)) / 2. Engineer vehicle (type 11):
	# max_ap 76, fire_cost 30 -> n = 46 at full AP.
	# roll=0   (mininum of rand(0,46))  -> (40+0)/2  = 20  — the floor.
	# roll=46  (maximum of rand(0,46))  -> (40+46)/2 = 43  — the ceiling.
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
	assert_eq(hi, 43, "roll=46 -> (40+46)/2 = 43 — повні AP піднімають стелю")

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
	#   seed=21, first randi_range(0, 46) == 41
	# n = 46 because the engineer vehicle (type 11) is at full AP (76) minus its
	# fire_cost (30). repair_amount = (40 + 41) / 2 = 40 (int division of
	# 81/2 truncates). friend starts at hp=100, so hp_left = 140.
	var e: Unit = _engineer(Vector2i(4, 4))
	var friend: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	friend.hp = 100
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).apply(state)
	assert_eq(friend.hp, 140, "seed 21: roll=41 -> (40+41)/2=40 -> 100+40")

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

# --- Запити для панелі інженера (Task 4a) ---

const A := EngineerCommand.Action

func test_lay_mine_status_lists_free_adjacent_tiles_only() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	state.add_unit(5, 1, Vector2i(4, 3), 0)
	var st: Dictionary = EngineerCommand.action_status(state, e.id, A.LAY_MINE)
	assert_eq(st["tiles"].size(), 3)
	assert_false(st["tiles"].has(Vector2i(4, 3)))
	assert_eq(st["reason"], "")

func test_status_reason_when_no_ap() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	e.ap = 20
	var st: Dictionary = EngineerCommand.action_status(state, e.id, A.LAY_MINE)
	assert_eq(st["tiles"], [])
	assert_eq(st["reason"], "ERR_NOT_ENOUGH_AP")

func test_clear_mine_reason_without_mine() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	assert_eq(EngineerCommand.action_status(state, e.id, A.CLEAR_MINE)["reason"], "ERR_NO_MINE_THERE")

func test_demolish_bridge_forbidden_with_own_unit_on_it() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	state.add_unit(5, 0, Vector2i(4, 3), 0)
	var st: Dictionary = EngineerCommand.action_status(state, e.id, A.DEMOLISH_BRIDGE)
	assert_eq(st["tiles"], [])
	# Сусіди відмовляють з різних причин (зайнято / немає мосту) — жодна з них не
	# головна, тож загальна причина.
	assert_eq(st["reason"], "ERR_NO_ADJACENT_TARGET")

func test_status_unit_reason_wins_over_tile_reasons() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	e.has_fired = true
	assert_eq(EngineerCommand.action_status(state, e.id, A.CLEAR_MINE)["reason"], "ERR_ALREADY_FIRED")
	var foe: Unit = state.add_unit(11, 1, Vector2i(8, 8), 0)
	assert_eq(EngineerCommand.action_status(state, foe.id, A.LAY_MINE),
		{"tiles": [] as Array[Vector2i], "reason": "ERR_NOT_YOUR_UNIT"})

func test_status_same_tile_reason_on_every_neighbour_is_kept() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	assert_eq(EngineerCommand.action_status(state, e.id, A.REPAIR_BRIDGE)["reason"], "ERR_NOTHING_TO_REPAIR")

func test_status_mixed_tile_reasons_give_no_adjacent_target() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	state.add_unit(5, 0, Vector2i(4, 3), 0)  # неушкоджений свій танк
	assert_eq(EngineerCommand.action_status(state, e.id, A.REPAIR_UNIT)["reason"], "ERR_NO_ADJACENT_TARGET")

func test_status_specific_reason_on_one_neighbour_still_gives_no_adjacent_target() -> void:
	# Один сусід відмовляє своєю причиною (міна), решта — іншою (зайнято): жодна
	# не головна, тож панель показує загальну причину, а не першу в DIRS_4.
	var e: Unit = _engineer(Vector2i(4, 4))
	Mines.place(state, Vector2i(4, 3), 0)
	for p in [Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4)]:
		state.add_unit(5, 0, p, 0)
	assert_eq(EngineerCommand.create(e.id, A.LAY_MINE, Vector2i(4, 3)).validate(state), "ERR_MINE_ALREADY_THERE")
	assert_eq(EngineerCommand.action_status(state, e.id, A.LAY_MINE),
		{"tiles": [] as Array[Vector2i], "reason": "ERR_NO_ADJACENT_TARGET"})

func test_status_never_changes_state_or_rng() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var before: String = JSON.stringify(BattleSerializer.to_dict(state))
	var rng_before: int = state.rng.state
	for a: int in A.values():
		EngineerCommand.action_status(state, e.id, a)
	EngineerCommand.repair_bounds(e, e)
	assert_eq(JSON.stringify(BattleSerializer.to_dict(state)), before)
	assert_eq(state.rng.state, rng_before)

func test_status_matches_validate_for_every_action_and_tile() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	state.board.set_kind(Vector2i(5, 4), Terrain.Kind.BRIDGE_DESTROYED)
	Mines.place(state, Vector2i(3, 4), 1)
	var hurt: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	hurt.hp -= 10
	for a: int in A.values():
		var tiles: Array = EngineerCommand.action_status(state, e.id, a)["tiles"]
		for d in Board.DIRS_4:
			var p: Vector2i = e.pos + d
			assert_eq(tiles.has(p), EngineerCommand.create(e.id, a, p).validate(state) == "", "action %d tile %s" % [a, p])

func test_repair_bounds_full_ap() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var t: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	t.hp = t.max_hp() - 400
	assert_eq(e.ap, 76)
	assert_eq(EngineerCommand.repair_bounds(e, t), Vector2i(20, 43))

func test_repair_bounds_after_one_field_step() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var t: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	t.hp = t.max_hp() - 400
	e.ap = 51
	assert_eq(EngineerCommand.repair_bounds(e, t), Vector2i(20, 30))

func test_repair_bounds_capped_by_missing_hp() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var t: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	t.hp = t.max_hp() - 12
	assert_eq(EngineerCommand.repair_bounds(e, t), Vector2i(12, 12))

func test_repair_bounds_bracket_actual_roll() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var t: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	t.hp = t.max_hp() - 400
	var b: Vector2i = EngineerCommand.repair_bounds(e, t)
	var rng := RandomNumberGenerator.new()
	for s in 200:
		rng.seed = s
		var r: int = EngineerCommand.repair_amount(rng, e)
		assert_true(r >= b.x and r <= b.y, "seed %d: %d" % [s, r])
