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
	# check_elimination() перевіряється першою: вона — оригінальний інваріант
	# (winner == NO_WINNER), і check_victory() сама гейтить на state.is_over(),
	# тож якщо елімінація вже завершила матч цим ходом, виклик нижче — no-op,
	# а не другий MatchEnded. Коли обидві умови стають істинними того самого
	# кінця ходу, елімінація вирішує першою — той самий детермінований
	# tie-break, що й усередині check_elimination() між одним переможцем і
	# нічиєю.
	#
	# §3.10: елімінація лишається глобальною — гравець без юнітів вибуває, чий би
	# хід не йшов, — а умову цілей заявляє рівно один гравець. Виклик стоїть ДО
	# advance_player() нижче, тож state.active_player тут — це той, чий хід щойно
	# завершився, і саме він передається явно. Пересунути цей рядок за
	# advance_player() означало б перевіряти вже наступного гравця.
	out.append_array(Objectives.check_victory(state, state.active_player, state.objective_hold_target))
	if state.is_over():
		return out
	var previous: int = state.active_player
	state.active_player = state.advance_player()
	if state.active_player <= previous:
		state.turn_number += 1
	out.append_array(state.begin_turn())
	return out
