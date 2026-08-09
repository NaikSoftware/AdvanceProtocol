extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0

func test_fire_deals_damage_and_zeroes_ap() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	var before: int = t.hp
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "")
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.hp < before)
	assert_eq(a.ap, 0, "§3.2: постріл обнуляє AP")
	assert_true(a.has_fired)

func test_fire_emits_shot_then_damage() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(events[0] is Events.ShotFired)
	assert_true(events[1] is Events.DamageDealt)

func test_out_of_range_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(0, 0), 2)   # range 4
	var t: Unit = state.add_unit(2, 1, Vector2i(11, 11), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_OUT_OF_RANGE")

func test_invisible_target_cannot_be_shot() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)   # арта, vision 3, range 5
	var t: Unit = state.add_unit(2, 1, Vector2i(4, 0), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"§3.5: стріляти можна лише по тому, що бачиш")

func test_friendly_fire_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var f: Unit = state.add_unit(5, 0, Vector2i(5, 4), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, f.id).validate(state), "ERR_FRIENDLY_FIRE")

func test_engineer_cannot_fire() -> void:
	var e: Unit = state.add_unit(11, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(5, 4), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(e.id, t.id).validate(state), "ERR_NO_WEAPON", "§3.6: інженер не має зброї")

func test_second_shot_in_a_turn_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	FireCommand.create(a.id, t.id).apply(state)
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_NOT_ENOUGH_AP")

func test_kill_emits_destruction_and_checks_victory() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	t.hp = 1
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	var destroyed: bool = false
	var ended: bool = false
	for e in events:
		if e is Events.UnitDestroyed:
			destroyed = true
		if e is Events.MatchEnded:
			ended = true
	assert_true(destroyed)
	assert_true(ended, "останній юніт супротивника — кінець матчу")

func test_damage_feeds_the_attackers_class_pool() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(state.veterancy[0].xp[UnitTypes.UnitClass.TANK] > 0)

func test_preview_reports_sector_and_bounds() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)   # дивиться на схід, атака зі заходу
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	assert_eq(p["sector"], UnitTypes.ArmourSector.REAR)
	assert_eq(p["min"], 61, "нижня межа — нульовий кидок атаки і максимальний кидок броні")
	assert_eq(p["max"], 86, "верхня межа — максимальний кидок атаки і нульовий кидок броні")

func test_preview_bounds_bracket_every_real_roll() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.veterancy[a.owner].level_of(a.unit_class())
	var seen_min: int = p["max"]
	var seen_max: int = p["min"]
	for s in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var dmg: int = Rules.compute_damage(rng, a, t, level, sector, dist_sq)
		assert_true(dmg >= p["min"] and dmg <= p["max"],
			"%d поза межами прев'ю [%d, %d]" % [dmg, p["min"], p["max"]])
		seen_min = mini(seen_min, dmg)
		seen_max = maxi(seen_max, dmg)
	assert_eq(seen_min, p["min"], "нижня межа має бути реально досяжною, не лише теоретичною")
	assert_eq(seen_max, p["max"], "верхня межа має бути реально досяжною, не лише теоретичною")

func test_preview_does_not_disturb_the_rng() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var before: int = Rules.roll(state.rng, 1000)
	state.rng.seed = state.seed_value
	Rules.roll(state.rng, 1000)
	FireCommand.preview(state, a.id, t.id)
	var after: int = Rules.roll(state.rng, 1000)
	state.rng.seed = state.seed_value
	Rules.roll(state.rng, 1000)
	assert_eq(after, Rules.roll(state.rng, 1000), "прев'ю не має споживати кидки")
