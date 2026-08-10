class_name Objectives
extends RefCounted
## §3.10. Цілі підкоряються туману так само, як тайли.

const MAX_PER_MAP: int = 15

class Objective extends RefCounted:
	var pos: Vector2i
	var owner: int = -1
	var intact: bool = true
	var seen_by: Array[bool] = []
	func _init(p_pos: Vector2i, p_owner: int, p_player_count: int) -> void:
		pos = p_pos
		owner = p_owner
		for i in p_player_count:
			seen_by.append(false)

static func add(state: BattleState, pos: Vector2i, owner: int) -> int:
	if state.objectives.size() >= MAX_PER_MAP:
		return -1
	state.objectives.append(Objective.new(pos, owner, state.player_count))
	return state.objectives.size() - 1

static func at(state: BattleState, pos: Vector2i) -> Objective:
	for o in state.objectives:
		if o.pos == pos:
			return o
	return null

static func refresh_seen(state: BattleState, player: int) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for o in state.objectives:
		if o.seen_by[player]:
			continue
		if state.vision[player].is_visible(o.pos):
			o.seen_by[player] = true
			out.append(Events.TileRevealed.new(player, [o.pos] as Array[Vector2i]))
	return out

static func held_by(state: BattleState, player: int) -> int:
	var n: int = 0
	for o in state.objectives:
		if o.intact and o.owner == player:
			n += 1
	return n

static func check_victory(state: BattleState, player: int, hold_target: int) -> Array[Events.BattleEvent]:
	## §3.10: умову цілей заявляє рівно один гравець — той, чий хід щойно
	## завершився. Гравець передається явно, а не читається зі state.active_player,
	## бо «чий хід закінчився» — властивість моменту виклику, а не стану: викликач
	## робить це ДО advance_player(), і функція не має залежати від того порядку.
	##
	## Перебір усіх гравців тут раніше означав, що при двох утримувачах перемагав
	## менший індекс — порядок циклу замість правила. Нічия не розвʼязується, а
	## стає недосяжною: бути тим, чий хід щойно завершився, може лише один.
	## Побічний ефект — кращий за саме виправлення: узяту ціль треба ще втримати
	## до власного наступного кінця ходу, і кожен супротивник встигає її відбити.
	if state.is_over() or hold_target <= 0:
		return []
	if state.eliminated[player]:
		return []
	if held_by(state, player) < hold_target:
		return []
	state.winner = player
	return [Events.MatchEnded.new(player)] as Array[Events.BattleEvent]
