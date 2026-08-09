class_name EngineerCommand
extends Command
## §3.8. Верби замість гармати. Усе — на ортогонально сусідньому тайлі за fire_cost AP.

enum Action { LAY_MINE, CLEAR_MINE, REPAIR_BRIDGE, DEMOLISH_BRIDGE, REPAIR_UNIT, CAPTURE_OBJECTIVE, DEMOLISH_OBJECTIVE }

var unit_id: int = 0
var action: int = Action.LAY_MINE
var target_pos: Vector2i = Vector2i.ZERO

static func create(p_unit_id: int, p_action: int, p_target_pos: Vector2i) -> EngineerCommand:
	var c := EngineerCommand.new()
	c.unit_id = p_unit_id
	c.action = p_action
	c.target_pos = p_target_pos
	return c

static func repair_amount(rng: RandomNumberGenerator, engineer: Unit) -> int:
	## §3.8: (40 + rand(0, ap_left - fire_cost)) / 2 — інженер, що весь хід їхав, ремонтує погано.
	return (40 + Rules.roll(rng, engineer.ap - engineer.fire_cost())) / 2

func validate(state: BattleState) -> String:
	if state.is_over():
		return "ERR_MATCH_OVER"
	var e: Unit = state.get_unit(unit_id)
	if e == null or not e.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if e.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if e.unit_class() != UnitTypes.UnitClass.ENGINEER:
		return "ERR_NOT_AN_ENGINEER"
	if e.has_fired or e.ap < e.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not state.board.in_bounds(target_pos):
		return "ERR_OFF_BOARD"
	var delta: Vector2i = target_pos - e.pos
	if absi(delta.x) + absi(delta.y) != 1:
		return "ERR_NOT_ADJACENT"

	match action:
		Action.LAY_MINE:
			if Mines.mine_at(state, target_pos) != null:
				return "ERR_MINE_ALREADY_THERE"
			if state.unit_at(target_pos) != null:
				return "ERR_TILE_OCCUPIED"
		Action.CLEAR_MINE:
			if Mines.mine_at(state, target_pos) == null:
				return "ERR_NO_MINE_THERE"
		Action.DEMOLISH_BRIDGE:
			if state.board.kind_at(target_pos) != Terrain.Kind.BRIDGE:
				return "ERR_NO_BRIDGE_THERE"
		Action.REPAIR_BRIDGE:
			if state.board.kind_at(target_pos) != Terrain.Kind.BRIDGE_DESTROYED:
				return "ERR_NOTHING_TO_REPAIR"
		Action.REPAIR_UNIT:
			var t: Unit = state.unit_at(target_pos)
			if t == null or t.owner != e.owner:
				return "ERR_NO_FRIENDLY_UNIT_THERE"
			if t.hp >= t.max_hp():
				return "ERR_UNIT_UNDAMAGED"
		Action.CAPTURE_OBJECTIVE, Action.DEMOLISH_OBJECTIVE:
			var o: Objectives.Objective = Objectives.at(state, target_pos)
			if o == null:
				return "ERR_NO_OBJECTIVE_THERE"
			if action == Action.CAPTURE_OBJECTIVE and (o.owner == e.owner or not o.intact):
				return "ERR_NOTHING_TO_CAPTURE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var e: Unit = state.get_unit(unit_id)

	match action:
		Action.LAY_MINE:
			out.append_array(Mines.place(state, target_pos, e.owner))
		Action.CLEAR_MINE:
			out.append_array(Mines.clear(state, target_pos))
		Action.DEMOLISH_BRIDGE:
			state.board.set_kind(target_pos, Terrain.Kind.BRIDGE_DESTROYED)
			out.append(Events.BridgeChanged.new(target_pos, true))
		Action.REPAIR_BRIDGE:
			state.board.set_kind(target_pos, Terrain.Kind.BRIDGE)
			out.append(Events.BridgeChanged.new(target_pos, false))
		Action.REPAIR_UNIT:
			# assert(validate()) вище гарантує ціль у debug-збірці; у релізі, де
			# assert вирізано, unit_at() досі може повернути null. Мовчазний
			# no-op тут не вигідніший за легальну дію — AP однаково спишеться
			# нижче, просто без ефекту, а не крашем чи безкоштовним лікуванням.
			var t: Unit = state.unit_at(target_pos)
			if t != null:
				# рахуємо ДО списання AP: у формулі бере участь саме залишок ходу
				var healed: int = mini(repair_amount(state.rng, e), t.max_hp() - t.hp)
				t.hp += healed
				out.append(Events.UnitRepaired.new(t.id, healed, t.hp))
		Action.CAPTURE_OBJECTIVE:
			# Той самий запобіжник: Objectives.at() лишається значенням, яке
			# існує лише для дозволеної дії, і релізний виклик без validate()
			# не повинен захопити ціль з нізвідки.
			var o: Objectives.Objective = Objectives.at(state, target_pos)
			if o != null:
				o.owner = e.owner
				out.append(Events.ObjectiveCaptured.new(state.objectives.find(o), e.owner))
		Action.DEMOLISH_OBJECTIVE:
			var od: Objectives.Objective = Objectives.at(state, target_pos)
			if od != null:
				od.intact = false
				out.append(Events.ObjectiveDestroyed.new(state.objectives.find(od)))

	e.exhaust()
	out.append(Events.ApChanged.new(unit_id, 0))
	for p in state.player_count:
		out.append_array(state.refresh_vision(p))
	return out
