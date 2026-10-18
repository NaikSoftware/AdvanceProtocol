extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 11)

func test_turns_toward_each_of_the_eight_directions_without_spending_ap() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	for facing in 8:
		u.facing = (facing + 4) % 8   # дивиться навпаки, щоб поворот не був холостим
		var ap_before: int = u.ap
		var cmd: TurnCommand = TurnCommand.create(u.id, u.pos + Board.DIRS_8[facing] * 3)
		assert_eq(cmd.validate(state), "", "напрямок %d" % facing)
		var events: Array = cmd.apply(state)
		assert_eq(u.facing, facing)
		assert_eq(u.ap, ap_before, "поворот безкоштовний")
		assert_eq(events.size(), 1)
		assert_true(events[0] is Events.UnitTurned)
		assert_eq(events[0].unit_id, u.id)
		assert_eq(events[0].facing, facing)

func test_facing_snaps_like_firing_does() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 4)
	TurnCommand.create(u.id, Vector2i(6, 1)).apply(state)
	assert_eq(u.facing, Board.facing_towards(Vector2i(5, 5), Vector2i(6, 1)))

func test_refused_at_zero_ap() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	u.spend_ap(u.ap)
	assert_eq(TurnCommand.create(u.id, Vector2i(5, 9)).validate(state), "ERR_NOT_ENOUGH_AP")

func test_refused_after_firing() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	u.exhaust()
	assert_eq(TurnCommand.create(u.id, Vector2i(5, 9)).validate(state), "ERR_NOT_ENOUGH_AP")

func test_refused_for_an_enemy_unit() -> void:
	var e: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	assert_eq(TurnCommand.create(e.id, Vector2i(5, 9)).validate(state), "ERR_NOT_YOUR_UNIT")

func test_refused_for_a_dead_or_missing_unit() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	u.hp = 0
	assert_eq(TurnCommand.create(u.id, Vector2i(5, 9)).validate(state), "ERR_NO_SUCH_UNIT")
	assert_eq(TurnCommand.create(999, Vector2i(5, 9)).validate(state), "ERR_NO_SUCH_UNIT")

func test_refused_onto_its_own_tile() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 2)
	assert_eq(TurnCommand.create(u.id, u.pos).validate(state), "ERR_OWN_TILE")

func test_refused_off_the_board() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 2)
	assert_eq(TurnCommand.create(u.id, Vector2i(5, 10)).validate(state), "ERR_OFF_BOARD")

func test_refused_when_already_facing_that_way() -> void:
	# Холостий поворот відхиляється, щоб не було події без зміни стану.
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	assert_eq(TurnCommand.create(u.id, Vector2i(5, 0)).validate(state), "ERR_ALREADY_FACING")

func test_refused_when_the_match_is_over() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	state.winner = 0
	assert_eq(TurnCommand.create(u.id, Vector2i(5, 9)).validate(state), "ERR_MATCH_OVER")

func test_turning_toward_an_attacker_presents_the_front() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	var attacker := Vector2i(5, 9)
	assert_eq(Rules.armour_sector(u.facing, u.pos, attacker), UnitTypes.ArmourSector.REAR, "передумова")
	TurnCommand.create(u.id, attacker).apply(state)
	assert_eq(Rules.armour_sector(u.facing, u.pos, attacker), UnitTypes.ArmourSector.FRONT)

func test_reads_nothing_about_enemies() -> void:
	# Ворог, якого гравець не бачить, на цільовому тайлі не змінює ні відповіді, ні подій.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 0), 4)
	var target := Vector2i(9, 0)
	var without_enemy: String = TurnCommand.create(u.id, target).validate(state)
	state.add_unit(5, 1, target, 0)
	state.start()
	assert_false(state.vision[0].is_seen(target), "передумова: ворога не видно")
	var cmd: TurnCommand = TurnCommand.create(u.id, target)
	assert_eq(cmd.validate(state), without_enemy)
	var events: Array = cmd.apply(state)
	assert_eq(events.size(), 1)
	assert_eq(events[0].describe(), "UnitTurned(unit=%d, facing=2)" % u.id)


## Хід на власний тайл з напрямком — це поворот в обхід AP-гейту; його закрито.
func test_move_to_own_tile_cannot_turn() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	u.ap = 0
	assert_eq(MoveCommand.create(u.id, u.pos).validate(state), "ERR_OWN_TILE")
