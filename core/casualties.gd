class_name Casualties
extends RefCounted
## Тіла бійців відділення. Лише для вигляду: жодне правило їх не читає — вони не
## перешкода, не ціль і не впливають ні на огляд, ні на перемогу. Живуть у стані, а не у
## вигляді, бо мусять пережити перебудову дошки й збереження, а показувати їх можна лише
## на розвіданому глядача (§3.5).
##
## Відділення — чотири фігури, і фігура падає, щойно втрачено її чверть HP. Боєць, що впав,
## лишається на тайлі, де відділення стояло в ту мить, і більше не рухається.

const SQUAD_FIGURES: int = 4

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
	func _init(p_unit_id: int, p_pos: Vector2i, p_owner: int, p_type_id: int, p_facing: int, p_first: int, p_count: int) -> void:
		unit_id = p_unit_id
		pos = p_pos
		owner = p_owner
		type_id = p_type_id
		facing = p_facing
		first = p_first
		count = p_count


## Скільки фігур стоїть: `ceil(SQUAD_FIGURES · hp / max_hp)` цілими.
static func figures(hp: int, max_hp: int) -> int:
	if max_hp <= 0 or hp <= 0:
		return 0
	return mini(SQUAD_FIGURES, (SQUAD_FIGURES * hp + max_hp - 1) / max_hp)


## Викликати одразу після того, як HP піхоти зменшилось (до DamageDealt чи після — байдуже,
## подія тіл іде слідом). Лікування фігуру знову ставить, але тіла не забирає: нові тіла
## лягають, лише коли втрати перевищать усі, що вже лежать, тож у знищеного відділення
## тіл рівно SQUAD_FIGURES.
static func record(state: BattleState, unit: Unit) -> Array[Events.BattleEvent]:
	if unit.unit_class() != UnitTypes.UnitClass.INFANTRY:
		return []
	var down: int = SQUAD_FIGURES - figures(unit.hp, unit.max_hp())
	var lying: int = 0
	for b in state.bodies:
		if b.unit_id == unit.id:
			lying += b.count
	if down <= lying:
		return []
	var body := Body.new(unit.id, unit.pos, unit.owner, unit.type_id, unit.facing, SQUAD_FIGURES - down, down - lying)
	state.bodies.append(body)
	return [Events.FiguresFell.new(body)] as Array[Events.BattleEvent]
