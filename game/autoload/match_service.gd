extends Node
## Єдиний міст між сценами і core/. Сигнали йдуть лише назовні.
## Жоден вузол не тримає власного посилання на BattleState, окрім читання
## через цей сервіс (§6, task-2.1-brief.md).

signal events_ready

const SAVE_PATH: String = "user://save.json"
## Як бойовий екран мусить підняти матч: нічого (запуск сцени напряму →
## резервна карта), новий за конфігом нижче, або з уже завантаженого state.
enum Launch { NONE, NEW, RESUME }

var state: BattleState = null
var launch_mode: int = Launch.NONE
## Конфіг матчу: екран налаштувань його пише, бій читає, «Реванш» перевикористовує.
## map_path порожній — карта невідома (збереження без сайдкара): бій бере резервну.
var map_path: String = ""
var players: int = 2
var seed_value: int = 0
var _queue: Array[Events.BattleEvent] = []
## Журнал команд для повтору ходів противників; живе і зберігається разом із матчем.
var replay_log: ReplayLog = ReplayLog.new()

## seed_value < 0 — випадковий. Сід лишається прихованим від гравця (match_setup.gd),
## але живе в state.seed_value і в збереженні, тож матч відтворюваний.
func configure(p_map_path: String, p_players: int, p_seed: int = -1) -> void:
	map_path = p_map_path
	players = p_players
	seed_value = p_seed if p_seed >= 0 else _random_seed()
	launch_mode = Launch.NEW


## Той самий матч, новий сід.
func rematch() -> void:
	configure(map_path, players)


func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()


func start_match(board: Board, player_count: int, seed_value: int) -> void:
	## Лише будує стан. Виклик мусить піти після додавання всіх юнітів —
	## begin() запускає власне матч, окремим кроком.
	state = BattleState.create(board, player_count, seed_value)
	_queue.clear()
	replay_log = ReplayLog.new()

func begin() -> void:
	## Друга фаза старту, обов'язкова: BattleState.start() документує, що
	## state.start() не можна виконати всередині create(), бо юніти додаються
	## ПІСЛЯ create(), а без start() vision[p] лишається порожньою сіткою для
	## кожного гравця, чий хід ще не наставав, — і знання такого гравця (його `seen`,
	## з якого вигляд засіює туман і яке зберігається з матчем) було б нечесним.
	## Виклик — рівно один раз, після того як усі юніти вже додані, і до першого
	## take_events().
	state.start()
	_queue.append_array(state.begin_turn())
	# Знімок решти гравців: їхній перший повтор починається з початку матчу.
	for p in state.player_count:
		if p != state.active_player:
			replay_log.mark(p, state)
	events_ready.emit()

func submit(command: Command) -> String:
	var err: String = command.validate(state)
	if err != "":
		return err
	# Знімок гравця береться на межі його ходу, до передачі ходу.
	if command is EndTurnCommand or command is ConcedeCommand:
		replay_log.mark(state.active_player, state)
	_queue.append_array(command.apply(state))
	replay_log.record(command)
	events_ready.emit()
	return ""


## Що сталося, поки `viewer` не грав; null — повтору нема. Викликається на передачі ходу.
func replay_for(viewer: int) -> ReplayFilter.Result:
	if OS.is_debug_build():
		var entries: Array[Dictionary] = replay_log.rerun(viewer)
		if not entries.is_empty():
			assert(JSON.stringify(BattleSerializer.to_dict(entries[-1]["after"]), "", true) \
					== JSON.stringify(BattleSerializer.to_dict(state), "", true),
					"повторний прогін розійшовся зі станом матчу")
	return ReplayFilter.build(replay_log, viewer)

func take_events() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = _queue.duplicate()
	_queue.clear()
	return out

## Карта в серіалізаторі (core/) не живе, а «Реванш» після «Продовжити» без неї
## не знає, що грати, — тож шлях до карти лежить окремим файлом поруч.
## Завершений матч не зберігається (і старе збереження стирається): інакше
## «Продовжити» вічно відновлювало б гру, якої вже нема.
func save_current(path: String) -> Error:
	if state.is_over():
		delete_save(path)
		return ERR_UNAVAILABLE
	var err: Error = BattleSerializer.save_to(state, path)
	if err == OK and map_path != "":
		var f: FileAccess = FileAccess.open(path + ".map", FileAccess.WRITE)
		if f != null:
			f.store_string(map_path)
			f.close()
	if err == OK:
		var rf: FileAccess = FileAccess.open(path + ".replay", FileAccess.WRITE)
		if rf != null:
			rf.store_string(JSON.stringify(replay_log.to_dict()))
			rf.close()
	return err


## Завершений матч не можна продовжити.
func delete_save(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".map")
	DirAccess.remove_absolute(path + ".replay")

func load_saved(path: String) -> bool:
	var loaded: BattleState = BattleSerializer.load_from(path)
	if loaded == null:
		return false
	if loaded.is_over():
		# Інакше «Продовжити» з'являється знову при кожному поверненні в меню.
		delete_save(path)
		return false
	state = loaded
	players = loaded.player_count
	seed_value = loaded.seed_value
	var sidecar: String = path + ".map"
	map_path = FileAccess.get_file_as_string(sidecar) if FileAccess.file_exists(sidecar) else ""
	replay_log = _load_replay(path + ".replay")
	launch_mode = Launch.RESUME
	# Завантажений стан не має історії подій, яку вигляд ще не забрав — черга
	# з попереднього матчу тут неактуальна і, гірше, могла б стосуватися стану,
	# якого вже нема.
	_queue.clear()
	return true


## Сайдкар — файл на диску: зламаний чи відсутній дає порожній журнал, тобто «повтору нема».
func _load_replay(sidecar: String) -> ReplayLog:
	if FileAccess.file_exists(sidecar):
		# parse(), не parse_string(): той на зламаному тексті пише помилку рушія, яку GUT рахує падінням.
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(sidecar)) == OK and json.data is Dictionary:
			var log: ReplayLog = ReplayLog.from_dict(json.data)
			if log != null:
				return log
	return ReplayLog.new()
