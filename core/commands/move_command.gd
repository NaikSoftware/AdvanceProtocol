class_name MoveCommand
extends Command

var unit_id: int = 0
var target: Vector2i = Vector2i.ZERO
var facing: int = -1

static func create(p_unit_id: int, p_target: Vector2i, p_facing: int) -> MoveCommand:
	var c := MoveCommand.new()
	c.unit_id = p_unit_id
	c.target = p_target
	c.facing = p_facing
	return c

func validate(state: BattleState) -> String:
	var u: Unit = state.get_unit(unit_id)
	if u == null or not u.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if u.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if u.has_fired:
		return "ERR_ALREADY_FIRED"
	if not state.board.in_bounds(target):
		return "ERR_OFF_BOARD"
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	if not zones.can_reach(target):
		return "ERR_OUT_OF_RANGE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	var u: Unit = state.get_unit(unit_id)
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	var path: Array[Vector2i] = Pathing.path_to(zones, target)
	var spent: int = zones.cost_to(target)

	var final_facing: int = facing
	if final_facing < 0:
		final_facing = Board.facing_towards(
			path[path.size() - 2] if path.size() >= 2 else u.pos,
			target) if not path.is_empty() else u.facing

	u.pos = target
	u.facing = final_facing
	u.spend_ap(spent)

	out.append(Events.UnitMoved.new(unit_id, path, final_facing))
	out.append(Events.ApChanged.new(unit_id, u.ap))
	out.append_array(state.refresh_vision(u.owner))
	# міни під ногами обробляються в Task 1.16 — там сюди додається виклик Mines.step_on()
	return out
