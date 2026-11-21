class_name Casualties
extends RefCounted
## Тіла бійців відділення й розрахунку гармати. Лише для вигляду: жодне правило їх не читає — вони не
## перешкода, не ціль і не впливають ні на огляд, ні на перемогу. Живуть у стані, а не у
## вигляді, бо мусять пережити перебудову дошки й збереження, а показувати їх можна лише
## тому, хто їх побачив (§3.5).
##
## Відділення — чотири фігури, і фігура падає, щойно втрачено її чверть HP. Боєць, що впав,
## лишається на тайлі, де відділення стояло в ту мить, і більше не рухається. Кожна втрачена
## фігура лишає тіло, і після лікування теж, тож тіл у відділення може бути й більше за чотири.

const SQUAD_FIGURES: int = 4
## Розрахунок гармати: двоє. Косметика, як і тіла відділення: без HP, без правил; лягає, коли гармата знищена.
const CREW_FIGURES: int = 2

class Body extends RefCounted:
	var unit_id: int
	var pos: Vector2i
	var owner: int
	var type_id: int
	## Напрям відділення в мить влучання: тіла лежать там, де стояли їхні місця.
	var facing: int
	## Місця фігур у відділенні: лежать `first .. first + count - 1`. Стоять завжди перші
	## місця, тож падають останні.
	var first: int
	var count: int
	## Бітова маска гравців, яким тіло вже показане: показане лишається показаним. Без неї тіло
	## зникало б, щойно відділення повернулося б у свій незнайдений будинок, — і цим його виказало б.
	var revealed_to: int = 0
	## Номер запису серед тіл свого юніта: два записи на тому самому тайлі й місці (влучання, лікування,
	## знову влучання) інакше лягли б один на одного — вигляд бере його в сід розкладу тіл.
	var seq: int = 0
	func _init(p_unit_id: int, p_pos: Vector2i, p_owner: int, p_type_id: int, p_facing: int, p_first: int, p_count: int) -> void:
		unit_id = p_unit_id
		pos = p_pos
		owner = p_owner
		type_id = p_type_id
		facing = p_facing
		first = p_first
		count = p_count

	func shown_to(player: int) -> bool:
		return revealed_to & (1 << player) != 0


## Чи має тип розрахунок, що лишає тіла, коли його знищено: польова гармата й гаубиця (артилерія).
static func has_crew(type_id: int) -> bool:
	return UnitTypes.get_type(type_id).unit_class == UnitTypes.UnitClass.ARTILLERY


## Скільки фігур стоїть: `ceil(SQUAD_FIGURES · hp / max_hp)` цілими.
static func figures(hp: int, max_hp: int) -> int:
	if max_hp <= 0 or hp <= 0:
		return 0
	return mini(SQUAD_FIGURES, (SQUAD_FIGURES * hp + max_hp - 1) / max_hp)


## Викликати одразу після того, як HP піхоти чи гармати зменшилось з `hp_before`; подія тіл іде слідом за
## `DamageDealt`. У відділення лягають фігури, що стояли до влучання й уже не стоять; у гармати — двоє бійців
## розрахунку, коли її знищено.
static func record(state: BattleState, unit: Unit, hp_before: int) -> Array[Events.BattleEvent]:
	var first: int = 0
	var count: int = 0
	if has_crew(unit.type_id):
		# Розрахунок не втрачає фігур від влучань: обоє лягають разом із гарматою, що ось-ось лишить уламки.
		if unit.hp > 0 or hp_before <= 0:
			return []
		count = CREW_FIGURES
	elif unit.unit_class() == UnitTypes.UnitClass.INFANTRY:
		var before: int = figures(hp_before, unit.max_hp())
		first = figures(unit.hp, unit.max_hp())
		if first >= before:
			return []
		count = before - first
	else:
		return []
	var body := Body.new(unit.id, unit.pos, unit.owner, unit.type_id, unit.facing, first, count)
	# Найбільший номер + 1, а не кількість записів: підірваний міст забирає записи, і лічба повторила б номер.
	for b in state.bodies:
		if b.unit_id == unit.id:
			body.seq = maxi(body.seq, b.seq + 1)
	state.bodies.append(body)
	for p in state.player_count:
		_reveal(state, p, body)
	return [Events.FiguresFell.new(body)] as Array[Events.BattleEvent]


## Тіла, які гравець щойно побачив: тайл розвіданий (`seen`), і там не ховається незнайдене
## ним відділення, якому тіло належить (укриття в будинку). Кличе BattleState.refresh_vision().
static func reveal(state: BattleState, player: int) -> void:
	for b in state.bodies:
		_reveal(state, player, b)


static func _reveal(state: BattleState, player: int, b: Body) -> void:
	if b.shown_to(player) or not state.vision[player].is_seen(b.pos):
		return
	var u: Unit = state.get_unit(b.unit_id)
	if u != null and u.is_alive() and u.pos == b.pos and not state.can_see_unit(player, u):
		return
	b.revealed_to |= 1 << player


## Прогін мосту впав: тіла на ньому йдуть у річку разом з ним.
static func remove_at(state: BattleState, pos: Vector2i) -> void:
	for i in range(state.bodies.size() - 1, -1, -1):
		if state.bodies[i].pos == pos:
			state.bodies.remove_at(i)
