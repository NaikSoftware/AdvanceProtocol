extends GutTest
## §3.3.1/§3.4/§3.5: відповідь як в оригіналі.
##
##   * Влучання відкриває стрільця: тайл атакувальника назавжди стає `seen` для
##     боку цілі ще до того, як ляже шкода. Тому окремого «відповідач мусить бачити»
##     немає — умова відповіді рівно три пункти: дальність, не інженер, AP.
##   * Ціль, що вижила, завжди розвертається до атакувальника — навіть коли
##     відповісти не може. Розворот іде ПІСЛЯ шкоди, тож сектор першого пострілу
##     рахується від старої орієнтації.
##
## Середні танки (#5: hp 400, дальність 4, fire_cost 20) — найбільший постріл ~80,
## тож ціль переживає будь-який обмін нижче.

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(16, 16, Terrain.GroundState.DRY), 2, 11)
	state.active_player = 0

func _first(events: Array, pred: Callable) -> int:
	for i in events.size():
		if pred.call(events[i]):
			return i
	return -1

func _retaliations(events: Array) -> int:
	return events.filter(func(e: Events.BattleEvent) -> bool: return e is Events.ShotRetaliated).size()

func _turns_of(events: Array, unit_id: int) -> Array:
	return events.filter(func(e: Events.BattleEvent) -> bool:
		return e is Events.UnitTurned and e.unit_id == unit_id)

func _shots(events: Array) -> Array:
	return events.filter(func(e: Events.BattleEvent) -> bool: return e is Events.ShotFired)

func _blind(player: int) -> void:
	# Бік цілі не розвідував нічого — стан, у якому за старим правилом відповіді не було.
	state.vision[player].visible.fill(0)
	state.vision[player].seen.fill(0)

func test_a_shot_from_unscouted_ground_is_answered() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	_blind(t.owner)
	var hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_eq(_retaliations(events), 1, "§3.3.1: постріл з нерозвіданої землі однаково дістає відповідь")
	assert_lt(a.hp, hp_before)

func test_the_shooters_tile_becomes_seen_by_the_victims_side_before_the_damage() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	_blind(t.owner)
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(state.vision[t.owner].is_seen(a.pos), "§3.5: влучання відкриває тайл стрільця назавжди")
	var i_reveal: int = _first(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.TileRevealed and e.player == t.owner and e.tiles.has(a.pos))
	var i_dmg: int = _first(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.DamageDealt and e.unit_id == t.id)
	assert_gt(i_reveal, -1, "відкриття — подія для вигляду")
	assert_lt(i_reveal, i_dmg, "відкриття передує шкоді")

func test_a_survivor_with_no_ap_turns_but_does_not_answer() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)   # схід — кормою до атакувальника
	state.begin_turn()
	t.ap = 0
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_eq(_retaliations(events), 0)
	assert_eq(t.facing, 6, "§3.4: ціль, що вижила, розвертається до стрільця завжди")
	assert_eq(_turns_of(events, t.id).size(), 1)
	assert_eq(t.ap, 0)
	assert_false(t.has_fired)

func test_a_survivor_out_of_range_turns_but_does_not_answer() -> void:
	# Гармата (#9: дальність 5) по винищувачу танків (#6: дальність 4) з відстані 5.
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)
	var t: Unit = state.add_unit(6, 1, Vector2i(5, 0), 2)
	state.begin_turn()
	state.vision[0].seen.fill(1)  # знання атакувальника — не предмет тесту
	var ap_before: int = t.ap
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive())
	assert_eq(_retaliations(events), 0, "25 > 4^2 — не дістає")
	assert_eq(t.facing, 6)
	assert_eq(_turns_of(events, t.id).size(), 1)
	assert_eq(t.ap, ap_before)

func test_the_first_shot_lands_in_the_sector_of_the_pre_turn_facing() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)   # кормою до атакувальника
	state.begin_turn()
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_eq(_shots(events)[0].sector, UnitTypes.ArmourSector.REAR, "сектор — від старої орієнтації")
	var i_dmg: int = _first(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.DamageDealt and e.unit_id == t.id)
	var i_turn: int = _first(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.UnitTurned and e.unit_id == t.id)
	assert_lt(i_dmg, i_turn, "розворот — після шкоди")
	assert_eq(t.facing, 6)

func test_a_second_attacker_from_the_same_flank_now_hits_the_front() -> void:
	var a1: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var a2: Unit = state.add_unit(5, 0, Vector2i(3, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)   # кормою до обох
	state.begin_turn()
	var first: Array = FireCommand.create(a1.id, t.id).apply(state)
	assert_eq(_shots(first)[0].sector, UnitTypes.ArmourSector.REAR)
	assert_eq(FireCommand.create(a2.id, t.id).validate(state), "")
	var second: Array = FireCommand.create(a2.id, t.id).apply(state)
	assert_eq(_shots(second)[0].sector, UnitTypes.ArmourSector.FRONT,
		"§3.4: після першого пострілу ціль стоїть лобом до того ж флангу")

func test_an_engineer_target_turns_but_never_answers() -> void:
	var a: Unit = state.add_unit(0, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(11, 1, Vector2i(5, 4), 2)
	state.begin_turn()
	var ap_before: int = t.ap
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive())
	assert_eq(_retaliations(events), 0)
	assert_eq(t.facing, 6)
	assert_eq(_turns_of(events, t.id).size(), 1)
	assert_eq(t.ap, ap_before)

func test_the_drone_strike_reveals_turns_and_is_answered_from_unscouted_ground() -> void:
	var a: Unit = state.add_unit(1, 0, Vector2i(2, 2), 2)   # штурмове відділення
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)   # важкий танк, кормою до загону
	state.begin_turn()
	_blind(t.owner)
	var events: Array = DroneCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "120..180 << 350 hp")
	assert_true(state.vision[t.owner].is_seen(a.pos), "§3.9: дрон відкриває загін так само")
	assert_eq(t.facing, 6)
	assert_eq(_retaliations(events), 1)

func test_a_drone_strike_survivor_with_no_ap_turns_but_does_not_answer() -> void:
	var a: Unit = state.add_unit(1, 0, Vector2i(2, 2), 2)
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)
	state.begin_turn()
	t.ap = 0
	var events: Array = DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(_retaliations(events), 0)
	assert_eq(t.facing, 6)
	assert_eq(_turns_of(events, t.id).size(), 1)
