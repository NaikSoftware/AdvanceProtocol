class_name FireCommand
extends Command

var unit_id: int = 0
var target_id: int = 0

static func create(p_unit_id: int, p_target_id: int) -> FireCommand:
	var c := FireCommand.new()
	c.unit_id = p_unit_id
	c.target_id = p_target_id
	return c

func validate(state: BattleState) -> String:
	return check_shot(state, state.get_unit(unit_id), state.get_unit(target_id))

static func check_shot(state: BattleState, a: Unit, t: Unit) -> String:
	## Єдине місце, де живе законність пострілу. validate() — тонка обгортка над
	## цією функцією, і Targeting.firing_targets() (§3.13) викликає рівно її ж,
	## а не власну копію умов: оверлей «по кому я можу вистрілити» мусить збігатися
	## з валідацією до останньої перевірки, інакше він бреше гравцеві про постріл,
	## який той ось-ось підтвердить. Продубльована умова тут — це і є дефект.
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
	if a.unit_class() == UnitTypes.UnitClass.ENGINEER:
		return "ERR_NO_WEAPON"
	if a.has_fired:
		return "ERR_ALREADY_FIRED"
	if a.ap < a.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not Rules.in_radius(a.pos, t.pos, a.attack_range()):
		return "ERR_OUT_OF_RANGE"
	# §3.5: гейт — seen, а не visible. Розвідка незворотна, тож обвідна вогню — це
	# коло дальності, перетнуте з РОЗВІДАНОЮ землею, а не з чиїмось ромбом огляду
	# просто зараз. Ромб вирішує, як швидко та земля відкривається, і обмежує
	# постріл лише над тайлами, куди не ступала жодна нога цього гравця.
	if not state.vision[a.owner].is_seen(t.pos):
		return "ERR_TARGET_NOT_VISIBLE"
	return ""

static func _turn_towards(shooter: Unit, at: Vector2i) -> Array[Events.BattleEvent]:
	## Постріл орієнтує стрільця на ціль. Це НАСЛІДОК пострілу, ніколи не
	## передумова: дуги вогню в грі немає, розворот не коштує AP, не може «не
	## вдатися» і не бере участі в жодній перевірці законності — тому він живе тут,
	## а не у validate()/check_shot().
	##
	## Подія йде лише тоді, коли обличчя СПРАВДІ змінилось: UnitTurned означає
	## «юніт повернувся», а не «юніт вистрілив». Порожній розворот у потоці був би
	## анімацією нізвідки і змусив би вигляд самому відсіювати шум.
	var out: Array[Events.BattleEvent] = []
	var new_facing: int = Board.facing_towards(shooter.pos, at)
	if new_facing == shooter.facing:
		return out
	shooter.facing = new_facing
	out.append(Events.UnitTurned.new(shooter.id, new_facing))
	return out

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	# ПОРЯДОК КРОКІВ 1–3 — головне в цій функції, і саме його ламатимуть.
	#
	# КРОК 2 (лічиться першим, застосовується другим): сектор вхідного пострілу
	# береться від СТАРОЇ орієнтації цілі. Ціль не повертається передом до удару —
	# інакше флангування, найвиразніший хід у грі (§3.4), знецінилось би до нуля:
	# будь-який удар у корму сам себе перетворював би на лобовий.
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.experience[a.owner].level_of(a.unit_class())
	var dmg: int = Rules.compute_damage(state.rng, a, t, level, sector, dist_sq)

	# КРОК 1: атакувальник розвертається на ціль ПЕРЕД своїм пострілом. Наслідок
	# навмисний — відповідь (§3.3.1) прилетить йому вже в НОВИЙ сектор, і
	# геометрично це завжди лоб: прив'язка до 8 напрямків дає похибку щонайбільше
	# 22.5°, а поріг SIDE потребує більшого. Стріляти по комусь означає підставити
	# йому лоб, і це ціна першого пострілу.
	#
	# Розворот не чіпає RNG, тож його можна ставити після обчислення dmg, не
	# зсуваючи потік випадкових чисел; сектор вище рахується від t.facing і
	# a.pos, яких розворот атакувальника не торкається взагалі.
	out.append_array(_turn_towards(a, t.pos))

	a.exhaust()
	out.append(Events.ShotFired.new(unit_id, target_id, sector))
	out.append_array(_resolve_damage(state, a, t, dmg))
	out.append(Events.ApChanged.new(unit_id, 0))
	if t.is_alive():
		out.append_array(_retaliate(state, a, t))
	return out

static func _retaliate(state: BattleState, original_attacker: Unit, target: Unit) -> Array[Events.BattleEvent]:
	## §3.3.1. Пряме обчислення шкоди — НЕ рекурсивний виклик FireCommand.new().apply().
	## Ця функція ніде не створює Command і не викликає apply()/_retaliate() —
	## єдиний виклик, який вона робить у бік завдання шкоди, це _resolve_damage(),
	## а той, своєю чергою, ніколи не викликає _retaliate(). Тобто в графі викликів
	## немає шляху назад до _retaliate() — рекурсія неможлива структурно, а не лише
	## відсутня випадково через AP чи дальність.
	##
	## Порядок перевірок навмисно дзеркалить validate(): живість/клас, AP, дальність,
	## зір — так обидва читаються однаково.
	var out: Array[Events.BattleEvent] = []
	if not target.is_alive() or not original_attacker.is_alive():
		return out
	if target.unit_class() == UnitTypes.UnitClass.ENGINEER:
		return out  # §3.6/§3.3.1: у інженера немає зброї — він ніколи не відповідає
	if target.has_fired or target.ap < target.fire_cost():
		return out
	if not Rules.in_radius(target.pos, original_attacker.pos, target.attack_range()):
		return out
	if not state.vision[target.owner].is_seen(original_attacker.pos):
		# §3.3.1 (переглянуто): відповідач мусить бачити атакувальника — той самий
		# закон видимості, що й для будь-якого пострілу, але власним знанням цілі
		# (target.owner), а не зором того, хто стріляв першим. Це навмисний відхід
		# від референсу, який гейтить контратаку лише на AP, дальність і клас —
		# зафіксовано в CLAUDE.md §3.3.1/§4, не "виправляти" назад до референсу.
		#
		# «Не бачить» тут означає seen (§3.5): тайл, якого власник цілі не розвідував
		# ЖОДНОГО разу. Безкарність від цього не зникає, але стає зброєю дебюту —
		# з ходами розвідана земля росте, і стріляти без відповіді стає нізвідки.
		return out

	# КРОК 3, і його місце тут — не деталь. _retaliate() викликається вже ПІСЛЯ
	# _resolve_damage(), тобто після застосування шкоди, а всі гейти вище вже
	# пройдено — отже відповідач розвертається рівно тоді, коли відповідь СПРАВДІ
	# відбувається. Пересунути розворот вище (до гейтів) означало б крутити ціль
	# від самого факту отриманої шкоди, а це витік: орієнтація цілі показала б,
	# звідки прилетіло, навіть коли її власник стрільця ніколи не розвідував.
	# Безкарність невидимої атаки (§3.3.1) пішла б каналом, якого туман не
	# фільтрує взагалі (§6, «known debt» про нефільтровані події).
	out.append_array(_turn_towards(target, original_attacker.pos))

	var sector: int = Rules.armour_sector(original_attacker.facing, original_attacker.pos, target.pos)
	var dist_sq: int = Rules.distance_sq(target.pos, original_attacker.pos)
	var level: int = state.experience[target.owner].level_of(target.unit_class())
	var dmg: int = Rules.compute_damage(state.rng, target, original_attacker, level, sector, dist_sq)

	target.exhaust()
	out.append(Events.ShotRetaliated.new(target.id, original_attacker.id, sector))
	out.append_array(_resolve_damage(state, target, original_attacker, dmg))
	out.append(Events.ApChanged.new(target.id, 0))
	return out

static func _resolve_damage(state: BattleState, attacker: Unit, target: Unit, dmg: int) -> Array[Events.BattleEvent]:
	## Спільний хвіст для пострілу і для дронового удару.
	var out: Array[Events.BattleEvent] = []
	var applied: int = mini(dmg, target.hp)
	target.hp -= applied
	out.append(Events.DamageDealt.new(target.id, applied, target.hp))

	var before: int = state.experience[attacker.owner].level_of(attacker.unit_class())
	var after: int = state.experience[attacker.owner].add_damage(attacker.unit_class(), applied)
	if after != before:
		out.append(Events.ExperienceGained.new(attacker.owner, attacker.unit_class(), after))

	if not target.is_alive():
		out.append(Events.UnitDestroyed.new(target.id, target.pos))
		out.append_array(state.check_elimination())
		# Смерть цілі може відкрити/закрити огляд будь-кому — усі гравці.
		# Інакше, як MoveCommand.apply(), оновлюємо лише огляд атакуючого.
		out.append_array(state.refresh_vision_all())
	else:
		out.append_array(state.refresh_vision(attacker.owner))
	return out

static func preview(state: BattleState, unit_id: int, target_id: int) -> Dictionary:
	## Аналітичні межі, без жодного кидка — RNG матчу тут не чіпається.
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.experience[a.owner].level_of(a.unit_class())
	var bounds: Vector2i = Rules.damage_bounds(a, t, level, sector, dist_sq)
	return {"sector": sector, "min": bounds.x, "max": bounds.y}
