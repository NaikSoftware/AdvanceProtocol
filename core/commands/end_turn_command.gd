class_name EndTurnCommand
extends Command

static func create() -> EndTurnCommand:
	return EndTurnCommand.new()

func validate(state: BattleState) -> String:
	return "ERR_MATCH_OVER" if state.is_over() else ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	out.append(Events.TurnEnded.new(state.active_player))
	out.append_array(state.check_elimination())
	if state.is_over():
		return out
	var previous: int = state.active_player
	state.active_player = state.advance_player()
	if state.active_player <= previous:
		state.turn_number += 1
	out.append_array(state.begin_turn())
	return out
