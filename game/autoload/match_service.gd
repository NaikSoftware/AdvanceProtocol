extends Node
## Єдиний міст між сценами і core/. Сигнали йдуть лише назовні.
## Жоден вузол не тримає власного посилання на BattleState, окрім читання
## через цей сервіс (§6, task-2.1-brief.md).

signal events_ready

var state: BattleState = null
var _queue: Array[Events.BattleEvent] = []

func start_match(board: Board, player_count: int, seed_value: int) -> void:
	## Лише будує стан. Виклик мусить піти після додавання всіх юнітів —
	## begin() запускає власне матч, окремим кроком.
	state = BattleState.create(board, player_count, seed_value)
	_queue.clear()

func begin() -> void:
	## Друга фаза старту, обовʼязкова: core/battle_state.gd:44 документує, що
	## state.start() не можна виконати всередині create(), бо юніти додаються
	## ПІСЛЯ create(), а без start() vision[p] лишається порожньою сіткою для
	## кожного гравця, чий хід ще не наставав, — і саме тому FireCommand._retaliate()
	## гейтить відповідь на state.vision[target.owner].is_seen(...), його юніти
	## не можуть відповісти на постріл узагалі. Виклик — рівно один раз, після
	## того як усі юніти вже додані, і до першого take_events().
	state.start()
	_queue.append_array(state.begin_turn())
	events_ready.emit()

func submit(command: Command) -> String:
	var err: String = command.validate(state)
	if err != "":
		return err
	_queue.append_array(command.apply(state))
	events_ready.emit()
	return ""

func take_events() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = _queue.duplicate()
	_queue.clear()
	return out

func save_current(path: String) -> Error:
	return BattleSerializer.save_to(state, path)

func load_saved(path: String) -> bool:
	var loaded: BattleState = BattleSerializer.load_from(path)
	if loaded == null:
		return false
	state = loaded
	# Завантажений стан не має історії подій, яку вигляд ще не забрав — черга
	# з попереднього матчу тут неактуальна і, гірше, могла б стосуватися стану,
	# якого вже нема.
	_queue.clear()
	return true
