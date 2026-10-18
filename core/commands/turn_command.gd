class_name TurnCommand
extends Command
## §3.4: поворот на місці до будь-якого тайла. Безкоштовний, але лише поки юніт
## має AP: на 0 AP (зокрема після пострілу) юніт лишається як стоїть, тож той, хто
## вистрілив чи витратив хід, і далі вразливий із флангу.

var unit_id: int = 0
var target: Vector2i = Vector2i.ZERO

static func create(p_unit_id: int, p_target: Vector2i) -> TurnCommand:
	var c := TurnCommand.new()
	c.unit_id = p_unit_id
	c.target = p_target
	return c

func validate(state: BattleState) -> String:
	if state.is_over():
		return "ERR_MATCH_OVER"
	var u: Unit = state.get_unit(unit_id)
	if u == null or not u.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if u.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if u.ap <= 0:
		return "ERR_NOT_ENOUGH_AP"
	if not state.board.in_bounds(target):
		return "ERR_OFF_BOARD"
	# Власний тайл напрямку не має: facing_towards() повернув би довільну північ.
	if target == u.pos:
		return "ERR_OWN_TILE"
	# Холостий поворот відхиляється, а не проходить мовчки: інакше UnitTurned
	# повідомляв би про зміну, якої не було.
	if Board.facing_towards(u.pos, target) == u.facing:
		return "ERR_ALREADY_FACING"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var u: Unit = state.get_unit(unit_id)
	# Той самий 8-напрямковий знімок, що й у пострілі, — щоб поворот «на ціль» і
	# постріл у неї давали однаковий сектор броні.
	u.facing = Board.facing_towards(u.pos, target)
	var out: Array[Events.BattleEvent] = [Events.UnitTurned.new(unit_id, u.facing)]
	return out
