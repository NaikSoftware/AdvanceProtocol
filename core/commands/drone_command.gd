class_name DroneCommand
extends Command
## §3.9. Окрема дія, а не модифікатор звичайної атаки.

const RANGE: int = 5

var unit_id: int = 0
var target_id: int = 0

static func create(p_unit_id: int, p_target_id: int) -> DroneCommand:
	var c := DroneCommand.new()
	c.unit_id = p_unit_id
	c.target_id = p_target_id
	return c

func validate(state: BattleState) -> String:
	if state.is_over():
		return "ERR_MATCH_OVER"
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	if a == null or not a.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if t == null or not t.is_alive():
		return "ERR_NO_SUCH_TARGET"
	if a.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if t.owner == a.owner:
		return "ERR_FRIENDLY_FIRE"
	if a.drones_left <= 0:
		return "ERR_NO_DRONES_LEFT"
	if a.has_fired or a.ap < a.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if t.unit_class() == UnitTypes.UnitClass.INFANTRY:
		return "ERR_DRONE_CANNOT_TARGET_INFANTRY"
	if not Rules.in_radius(a.pos, t.pos, RANGE):
		return "ERR_OUT_OF_RANGE"
	if not state.vision[a.owner].is_visible(t.pos):
		return "ERR_TARGET_NOT_VISIBLE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	a.drones_left -= 1
	a.exhaust()
	out.append(Events.DroneLaunched.new(unit_id, target_id, a.drones_left))
	out.append_array(FireCommand._resolve_damage(state, a, t, Rules.drone_damage(state.rng)))
	out.append(Events.ApChanged.new(unit_id, 0))
	return out
