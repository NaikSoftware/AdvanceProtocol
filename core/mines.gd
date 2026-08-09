class_name Mines
extends RefCounted
## §3.11. Видимість міни ведеться на гравця — так само, як туман тайлів.

const DAMAGE: int = 120
const REVEAL_RADIUS: int = 1

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
	var out: Array[Events.BattleEvent] = []
	for u in state.units_of(player):
		for m in state.mines:
			if m.known_to[player]:
				continue
			if Rules.in_radius(u.pos, m.pos, REVEAL_RADIUS):
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
	var applied: int = mini(DAMAGE, unit.hp)
	unit.hp -= applied
	out.append(Events.DamageDealt.new(unit.id, applied, unit.hp))
	if not unit.is_alive():
		out.append(Events.UnitDestroyed.new(unit.id, unit.pos))
		out.append_array(state.check_elimination())
	return out
