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
var ground_state: int = Terrain.GroundState.DRY
var seed_value: int = 0
var _queue: Array[Events.BattleEvent] = []

## seed_value < 0 — випадковий. Сід лишається прихованим від гравця (match_setup.gd),
## але живе в state.seed_value і в збереженні, тож матч відтворюваний.
func configure(p_map_path: String, p_players: int, p_ground_state: int, p_seed: int = -1) -> void:
	map_path = p_map_path
	players = p_players
	ground_state = p_ground_state
	seed_value = p_seed if p_seed >= 0 else _random_seed()
	launch_mode = Launch.NEW


## Той самий матч, новий сід.
func rematch() -> void:
	configure(map_path, players, ground_state)


func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()


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

## Карта в серіалізаторі (core/) не живе, а «Реванш» після «Продовжити» без неї
## не знає, що грати, — тож шлях до карти лежить окремим файлом поруч.
func save_current(path: String) -> Error:
	var err: Error = BattleSerializer.save_to(state, path)
	if err == OK and map_path != "":
		var f: FileAccess = FileAccess.open(path + ".map", FileAccess.WRITE)
		if f != null:
			f.store_string(map_path)
			f.close()
	return err


## Завершений матч не можна продовжити.
func delete_save(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".map")

func load_saved(path: String) -> bool:
	var loaded: BattleState = BattleSerializer.load_from(path)
	if loaded == null:
		return false
	state = loaded
	players = loaded.player_count
	ground_state = loaded.board.ground_state
	seed_value = loaded.seed_value
	var sidecar: String = path + ".map"
	map_path = FileAccess.get_file_as_string(sidecar) if FileAccess.file_exists(sidecar) else ""
	launch_mode = Launch.RESUME
	# Завантажений стан не має історії подій, яку вигляд ще не забрав — черга
	# з попереднього матчу тут неактуальна і, гірше, могла б стосуватися стану,
	# якого вже нема.
	_queue.clear()
	return true
