class_name DroneCommand
extends Command
## §3.9. Окрема дія, а не модифікатор звичайної атаки.

const RANGE: int = 5

var unit_id: int = 0
var target_id: int = 0

static func create(p_unit_id: int, p_target_id: int) -> DroneCommand:
	var c := DroneCommand.new()
	c.unit_id = p_unit_id
	c.target_id = p_target_id
	return c

func validate(state: BattleState) -> String:
	return check_strike(state, state.get_unit(unit_id), state.get_unit(target_id))

static func check_strike(state: BattleState, a: Unit, t: Unit) -> String:
	## Єдине місце, де живе законність дронового удару — дзеркало
	## FireCommand.check_shot() і рівно з тієї ж причини: validate() тут тонка
	## обгортка, а Targeting.drone_targets() (§3.13) викликає саме цю функцію, а не
	## власну копію умов. Оверлей «куди я можу вдарити дроном» мусить збігатися з
	## валідацією до останньої перевірки, інакше він обіцяє удар, який гра відхилить.
	if state.is_over():
		return "ERR_MATCH_OVER"
	if a == null or not a.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if t == null or not t.is_alive():
		return "ERR_NO_SUCH_TARGET"
	if a.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if t.owner == a.owner:
		return "ERR_FRIENDLY_FIRE"
	if a.drones_left <= 0:
		return "ERR_NO_DRONES_LEFT"
	if a.has_fired:
		return "ERR_ALREADY_FIRED"
	if a.ap < a.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not UnitTypes.is_vehicle(t.unit_class()):
		return "ERR_DRONE_CANNOT_TARGET_INFANTRY"
	if not Rules.in_radius(a.pos, t.pos, RANGE):
		return "ERR_OUT_OF_RANGE"
	# §3.5: той самий гейт, що й у check_shot(), — seen, а не visible. Над розвіданою
	# землею ця перевірка інертна (§3.9 у docs/rules/vision-and-fog.md) і кусає лише
	# там, де ніхто з цього боку ще не був. Лишається саме тому: дрон не має бити
	# в тайл, про який власник не знає нічого.
	if not state.vision[a.owner].is_seen(t.pos):
		return "ERR_TARGET_NOT_VISIBLE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	# КРОК 1, той самий, що й у FireCommand.apply(): удар орієнтує загін на ціль
	# ПЕРЕД ударом. Правило навмисно формулюється одним реченням без винятку для
	# дрона — «постріл орієнтує стрільця на ціль», — хоча сьогодні це числово
	# інертно: броня піхоти 0/0/0, тож сектор відповіді по загону нічого не важить.
	# Інертність — стан ростеру, а не властивість правила; тримати тут виняток
	# означало б заводити другу редакцію правила заради нуля.
	out.append_array(FireCommand._turn_towards(a, t.pos))

	a.drones_left -= 1
	a.exhaust()
	out.append(Events.DroneLaunched.new(unit_id, target_id, a.drones_left))
	out.append_array(FireCommand._resolve_damage(state, a, t, Rules.drone_damage(state.rng)))
	out.append(Events.ApChanged.new(unit_id, 0))
	if t.is_alive():
		out.append_array(FireCommand._retaliate(state, a, t))
	return out
