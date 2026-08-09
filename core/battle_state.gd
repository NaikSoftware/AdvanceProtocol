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
var mines: Array = []                     # заповнюється в Task 1.16
var objectives: Array = []                # заповнюється в Task 1.17
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
	return out

func refresh_vision(player: int) -> Array[Events.BattleEvent]:
	## §3.5: перерахунок з нуля, ніколи не переносити чужу видимість у рендерер.
	var revealed: Array[Vector2i] = vision[player].recompute(board, alive_units(), player)
	if revealed.is_empty():
		return []
	return [Events.TileRevealed.new(player, revealed)] as Array[Events.BattleEvent]

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
