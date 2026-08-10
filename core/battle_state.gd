class_name BattleState
extends RefCounted
## Весь стан матчу. Серіалізовний, детермінований, без жодного нода.

## Матч триває, доки winner == NO_WINNER. DRAW потрібен окремим значенням, бо −1
## уже зайняте «ще триває»: без нього нічия була б невідрізненна від незавершеної гри.
const NO_WINNER: int = -1
const DRAW: int = -2

var board: Board = null
var units: Dictionary = {}                # int -> Unit
var player_count: int = 2
var active_player: int = 0
var turn_number: int = 1
var seed_value: int = 0
var rng: RandomNumberGenerator = null
var vision: Array[Vision] = []
var veterancy: Array[Veterancy] = []
var eliminated: Array[bool] = []
var winner: int = NO_WINNER
var mines: Array[Mines.Mine] = []
var objectives: Array[Objectives.Objective] = []
## §3.10: скільки цілей потрібно утримувати, щоб перемогти цим способом.
## 0 — навмисне значення «на цій мапі немає умови перемоги за цілі»:
## Objectives.check_victory() уже трактує hold_target <= 0 як «умову вимкнено»
## (core/objectives.gd), тож анігіляційна мапа просто лишає це поле дефолтним
## замість того, щоб потребувати окремого прапорця «умова цілей є/немає».
var objective_hold_target: int = 0
var _next_unit_id: int = 1

static func create(p_board: Board, p_player_count: int, p_seed: int) -> BattleState:
	var s := BattleState.new()
	s.board = p_board
	s.player_count = p_player_count
	s.seed_value = p_seed
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = p_seed
	for i in p_player_count:
		s.vision.append(Vision.create(p_board.width, p_board.height))
		s.veterancy.append(Veterancy.create())
		s.eliminated.append(false)
	return s

func start() -> void:
	## Праймить видимість КОЖНОГО гравця рівно один раз, до першого begin_turn().
	## Без цього vision[p] лишається порожньою сіткою нулів аж до першого ходу
	## гравця p — а FireCommand._retaliate() гейтить відповідь саме на
	## state.vision[target.owner].is_visible(...), тож юніти гравців, чий хід
	## ще не наставав, не можуть відповісти на постріл узагалі. У грі на 2
	## гравці це робить увесь відкривний хід гравця 0 безкарним; у грі на 3 —
	## гравець 2 не може відповісти цілий перший раунд.
	##
	## Не можна викликати з create(): юніти додаються ПІСЛЯ create(), тож
	## приймінг там прайм би порожню дошку. Викликати рівно один раз, після
	## того як усі юніти вже додані, і до першого begin_turn().
	##
	## Повернені події тут навмисно ВІДКИДАЮТЬСЯ, а не повертаються викликачу:
	## ці тайли не є щойно розкритими для гравця, чий хід ось-ось почнеться —
	## begin_turn() для нього прийде окремим TileRevealed. Повернути їх звідси
	## означало б випустити TileRevealed для гравців, які зараз не діють, у
	## потік подій, призначений для показу того, що бачить активний гравець.
	## Не "виправляти" це на повернення подій пізніше без нового рішення.
	for p in player_count:
		refresh_vision(p)

func add_unit(type_id: int, owner: int, pos: Vector2i, facing: int) -> Unit:
	var u: Unit = Unit.create(_next_unit_id, type_id, owner, pos, facing)
	_next_unit_id += 1
	units[u.id] = u
	return u

func get_unit(id: int) -> Unit:
	return units.get(id, null)

func alive_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for id in units:
		var u: Unit = units[id]
		if u.is_alive():
			out.append(u)
	return out

func units_of(player: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in alive_units():
		if u.owner == player:
			out.append(u)
	return out

func unit_at(p: Vector2i) -> Unit:
	for u in alive_units():
		if u.pos == p:
			return u
	return null

func occupied_map() -> Dictionary:
	## Уключає кожен живий юніт, і того, що рухається, теж: хто заповнює
	## прохідність для конкретного юніта, мусить виключити його власний тайл сам.
	var out: Dictionary = {}
	for u in alive_units():
		out[u.pos] = u.id
	return out

func is_over() -> bool:
	return winner != NO_WINNER

func begin_turn() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	out.append(Events.TurnStarted.new(active_player, turn_number))
	for u in units_of(active_player):
		u.refill_ap()
	out.append_array(refresh_vision(active_player))
	out.append_array(Objectives.refresh_seen(self, active_player))
	## §3.11: пошук мін — властивість присутності, а не руху. Доти єдиним
	## викликачем Mines.reveal_near() був MoveCommand, тож сапер, який нікуди не
	## пішов, не знаходив нічого: ворожа міна за крок від нього лишалася б
	## невидимою весь матч, хоч і стоїть усередині його ромба огляду.
	## Це свідомий відхід від референсу (§4), де пошук теж прив'язаний до руху.
	##
	## Прохід — рівно за активного гравця: чужі міни чужим не відкриваються, і за
	## гравця, чий хід не йде, ніхто не шукає. Повторної події не буде — reveal_near()
	## пропускає міну, вже позначену known_to[player]. Стоїть ПІСЛЯ refresh_vision()
	## з тієї ж причини, що й у MoveCommand: MineRevealed не має випереджати
	## TileRevealed свого тайла.
	out.append_array(Mines.reveal_near(self, active_player))
	return out

func refresh_vision(player: int) -> Array[Events.BattleEvent]:
	## §3.5: перерахунок з нуля, ніколи не переносити чужу видимість у рендерер.
	var revealed: Array[Vector2i] = vision[player].recompute(board, alive_units(), player)
	if revealed.is_empty():
		return []
	return [Events.TileRevealed.new(player, revealed)] as Array[Events.BattleEvent]

func refresh_vision_all() -> Array[Events.BattleEvent]:
	## Vision.recompute() читає ЛИШЕ живі юніти самого player — жоден чужий
	## юніт на нього не впливає. Тож єдине, що взагалі здатне змінити чужу
	## видимість, — це смерть чийогось юніта (той юніт перестає світити власну
	## видимість власникові). Усюди, де дія не може нікого вбити, оновлювати
	## варто лише видимість того, чий це юніт; лише на гілці, де хтось
	## помирає, потрібен прохід по всіх гравцях — саме це робить цей метод.
	var out: Array[Events.BattleEvent] = []
	for p in player_count:
		out.append_array(refresh_vision(p))
	return out

func advance_player() -> int:
	assert(not is_over(), "advance_player() після завершення матчу")
	var next: int = active_player
	for i in player_count:
		next = (next + 1) % player_count
		if not eliminated[next]:
			break
	return next

func check_elimination() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for p in player_count:
		if eliminated[p]:
			continue
		if units_of(p).is_empty():
			eliminated[p] = true
			out.append(Events.PlayerEliminated.new(p))
	var alive: Array[int] = []
	for p in player_count:
		if not eliminated[p]:
			alive.append(p)
	if alive.size() <= 1 and winner == NO_WINNER:
		winner = alive[0] if alive.size() == 1 else DRAW
		out.append(Events.MatchEnded.new(winner))
	return out
