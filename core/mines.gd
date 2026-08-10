class_name Mines
extends RefCounted
## §3.11. Видимість міни ведеться на гравця — так само, як туман тайлів.

## §4: у референсі (`class_1.method_105`) міна завдає `90 + rand(0, 90)`, а не фіксовану
## величину. Пласке число зробило б міну єдиним джерелом шкоди в грі, яке не кидається.
const DAMAGE_BASE: int = 90
const DAMAGE_ROLL: int = 90

class Mine extends RefCounted:
	var pos: Vector2i
	var owner: int
	var known_to: Array[bool] = []
	func _init(p_pos: Vector2i, p_owner: int, p_player_count: int) -> void:
		pos = p_pos
		owner = p_owner
		for i in p_player_count:
			known_to.append(i == p_owner)

static func mine_at(state: BattleState, pos: Vector2i) -> Mine:
	for m in state.mines:
		if m.pos == pos:
			return m
	return null

static func is_known(state: BattleState, pos: Vector2i, player: int) -> bool:
	var m: Mine = mine_at(state, pos)
	return m != null and m.known_to[player]

static func place(state: BattleState, pos: Vector2i, owner: int) -> Array[Events.BattleEvent]:
	if mine_at(state, pos) != null:
		return []
	state.mines.append(Mine.new(pos, owner, state.player_count))
	return [Events.MinePlaced.new(pos, owner)] as Array[Events.BattleEvent]

static func clear(state: BattleState, pos: Vector2i) -> Array[Events.BattleEvent]:
	var m: Mine = mine_at(state, pos)
	if m == null:
		return []
	state.mines.erase(m)
	return [Events.MineCleared.new(pos)] as Array[Events.BattleEvent]

static func reveal_near(state: BattleState, player: int) -> Array[Events.BattleEvent]:
	## §3.11: чужу міну знаходить ЛИШЕ сапер, і то в межах власного огляду —
	## того самого ромба, що й туман тайлів, тож розкрита міна завжди лежить на
	## тайлі, який гравець і справді бачить. Без сапера попереду колона заходить
	## у мінне поле наосліп — це й перетворює мінування на загрозу, а сапера
	## дає підставу вести вперед, а не тримати позаду.
	##
	## Викликати ЛИШЕ після BattleState.refresh_vision(player) — інакше твердження
	## вище справджується для кінцевого стану, але не для потоку подій: MineRevealed
	## вийде раніше за TileRevealed свого тайла, і вигляд намалює міну в тумані.
	## Пошук ведеться і на початку ходу власника (BattleState.begin_turn()), і після
	## кожного кроку (MoveCommand.apply()): це властивість присутності, не руху.
	var out: Array[Events.BattleEvent] = []
	for u in state.units_of(player):
		if u.unit_class() != UnitTypes.UnitClass.ENGINEER:
			continue
		for m in state.mines:
			if m.known_to[player]:
				continue
			if Rules.in_vision_diamond(u.pos, m.pos, u.vision()):
				m.known_to[player] = true
				out.append(Events.MineRevealed.new(m.pos, player))
	return out

static func step_on(state: BattleState, unit: Unit) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	var m: Mine = mine_at(state, unit.pos)
	if m == null or m.owner == unit.owner:
		return out
	state.mines.erase(m)
	out.append(Events.MineTriggered.new(m.pos, unit.id))
	var applied: int = mini(DAMAGE_BASE + Rules.roll(state.rng, DAMAGE_ROLL), unit.hp)
	unit.hp -= applied
	out.append(Events.DamageDealt.new(unit.id, applied, unit.hp))
	if not unit.is_alive():
		out.append(Events.UnitDestroyed.new(unit.id, unit.pos))
		out.append_array(state.check_elimination())
	return out
