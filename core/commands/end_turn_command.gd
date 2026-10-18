class_name EndTurnCommand
extends Command

static func create() -> EndTurnCommand:
	return EndTurnCommand.new()

func validate(state: BattleState) -> String:
	return "ERR_MATCH_OVER" if state.is_over() else ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	out.append(Events.TurnEnded.new(state.active_player))
	out.append_array(state.check_elimination())
	if state.is_over():
		return out
	out.append_array(state.pass_turn())
	return out
