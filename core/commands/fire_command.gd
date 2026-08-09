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
	if state.is_over():
		return "ERR_MATCH_OVER"
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
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
	if a.has_fired or a.ap < a.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not Rules.in_radius(a.pos, t.pos, a.attack_range()):
		return "ERR_OUT_OF_RANGE"
	if not state.vision[a.owner].is_visible(t.pos):
		return "ERR_TARGET_NOT_VISIBLE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.veterancy[a.owner].level_of(a.unit_class())
	var dmg: int = Rules.compute_damage(state.rng, a, t, level, sector, dist_sq)

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
	var out: Array[Events.BattleEvent] = []
	if not target.is_alive() or not original_attacker.is_alive():
		return out
	if target.unit_class() == UnitTypes.UnitClass.ENGINEER:
		return out  # §3.6/§3.3.1: у інженера немає зброї — він ніколи не відповідає
	if target.has_fired or target.ap < target.fire_cost():
		return out
	if not Rules.in_radius(target.pos, original_attacker.pos, target.attack_range()):
		return out

	var sector: int = Rules.armour_sector(original_attacker.facing, original_attacker.pos, target.pos)
	var dist_sq: int = Rules.distance_sq(target.pos, original_attacker.pos)
	var level: int = state.veterancy[target.owner].level_of(target.unit_class())
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

	var before: int = state.veterancy[attacker.owner].level_of(attacker.unit_class())
	var after: int = state.veterancy[attacker.owner].add_damage(attacker.unit_class(), applied)
	if after != before:
		out.append(Events.VeterancyGained.new(attacker.owner, attacker.unit_class(), after))

	if not target.is_alive():
		out.append(Events.UnitDestroyed.new(target.id, target.pos))
		out.append_array(state.check_elimination())
		# Смерть цілі може відкрити/закрити огляд будь-кому — усі гравці.
		# Інакше, як MoveCommand.apply(), оновлюємо лише огляд атакуючого.
		for p in state.player_count:
			out.append_array(state.refresh_vision(p))
	else:
		out.append_array(state.refresh_vision(attacker.owner))
	return out

static func preview(state: BattleState, unit_id: int, target_id: int) -> Dictionary:
	## Аналітичні межі, без жодного кидка — RNG матчу тут не чіпається.
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.veterancy[a.owner].level_of(a.unit_class())
	var bounds: Vector2i = Rules.damage_bounds(a, t, level, sector, dist_sq)
	return {"sector": sector, "min": bounds.x, "max": bounds.y}
