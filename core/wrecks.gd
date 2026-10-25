class_name Wrecks
extends RefCounted
## §3.14. Уламки знищеної техніки: перешкода лише для техніки, і лише поки горять.
## Піхота заходить на тайл з уламками і стоїть на ньому; вогню, огляду, вогню у
## відповідь і перемозі (§3.10 рахує лише живих) уламки не заважають.

## Скільки повних кіл уламки горять. Коло — кожен живий гравець зробив хід.
const WRECK_ROUNDS: int = 3
## Значення тайла з уламками в BattleState.known_blocked_map(). Окреме від міни (−1),
## бо уламки, на відміну від міни, перекривають тайл лише техніці — Pathing
## розрізняє їх саме за ним. Невід'ємні значення там — id юнітів.
const BLOCKED: int = -2

enum Reason { BURNED_OUT, BRIDGE_DEMOLISHED }

class Wreck extends RefCounted:
	var pos: Vector2i
	var type_id: int
	## Напрям юніта в мить загибелі: вигляд малює уламки так само, і після
	## завантаження теж, тож напрям зберігається, а не береться з мертвого юніта.
	var facing: int
	## Момент на годиннику ходів (BattleState.turn_clock()), з якого уламків уже немає.
	var burns_out_at: int
	func _init(p_pos: Vector2i, p_type_id: int, p_facing: int, p_burns_out_at: int) -> void:
		pos = p_pos
		type_id = p_type_id
		facing = p_facing
		burns_out_at = p_burns_out_at

static func wreck_at(state: BattleState, pos: Vector2i) -> Wreck:
	for w in state.wrecks:
		if w.pos == pos:
			return w
	return null

static func blocks(state: BattleState, unit: Unit, pos: Vector2i) -> bool:
	return UnitTypes.is_vehicle(unit.unit_class()) and wreck_at(state, pos) != null

static func leave(state: BattleState, unit: Unit) -> Array[Events.BattleEvent]:
	## Викликати одразу після UnitDestroyed. Техніка, що впала разом із мостом,
	## сюди не потрапляє: вона в річці, і тайл під нею — BRIDGE_DESTROYED.
	if not UnitTypes.is_vehicle(unit.unit_class()) or wreck_at(state, unit.pos) != null:
		return []
	# Горить до того самого місця в колі через WRECK_ROUNDS кіл: так кожен живий
	# гравець, зокрема той, на чиєму ході техніку знищено, має рівно WRECK_ROUNDS
	# ходів після появи уламків. Відлік від початку кола дав би гравцям, що ходять
	# раніше за вбивцю, на хід менше.
	var burns_out_at: int = state.turn_clock() + WRECK_ROUNDS * state.player_count
	state.wrecks.append(Wreck.new(unit.pos, unit.type_id, unit.facing, burns_out_at))
	return [Events.WreckLeft.new(unit.pos, unit.type_id, unit.facing)] as Array[Events.BattleEvent]

static func remove(state: BattleState, pos: Vector2i, reason: int) -> Array[Events.BattleEvent]:
	var w: Wreck = wreck_at(state, pos)
	if w == null:
		return []
	state.wrecks.erase(w)
	return [Events.WreckRemoved.new(pos, reason)] as Array[Events.BattleEvent]

static func burn_out(state: BattleState) -> Array[Events.BattleEvent]:
	## `>=`, а не `==`: годинник перескакує хід вибулого гравця, і уламки, що мали
	## догоріти саме на ньому, догоряють на наступному живому.
	var out: Array[Events.BattleEvent] = []
	for w in state.wrecks.duplicate():
		if state.turn_clock() >= w.burns_out_at:
			out.append_array(remove(state, w.pos, Reason.BURNED_OUT))
	return out
