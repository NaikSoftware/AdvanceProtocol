class_name ConcedeCommand
extends Command
## Здача активного гравця. Його юніти знищуються тим самим шляхом, що й від
## пострілу чи міни, — тож вони перестають займати тайли, бути цілями й
## відповідати вогнем, а вибуття й кінець матчу вирішує check_elimination().

static func create() -> ConcedeCommand:
	return ConcedeCommand.new()

func validate(state: BattleState) -> String:
	return "ERR_MATCH_OVER" if state.is_over() else ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	out.append(Events.TurnEnded.new(state.active_player))
	for u in state.units_of(state.active_player):
		u.hp = 0
		out.append(Events.UnitDestroyed.new(u.id, u.pos))
	out.append_array(state.check_elimination())
	if state.is_over():
		return out
	# Далі — той самий хвіст, що в EndTurnCommand: advance_player() вже пропускає
	# щойно вибулого, тож хід іде до наступного гравця в колі.
	out.append_array(state.pass_turn())
	return out
