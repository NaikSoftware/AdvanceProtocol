class_name Rules
extends RefCounted
## Уся математика бою (§3.2–3.4). Жодного глобального randi() тут ніколи не зʼявиться.

static func roll(rng: RandomNumberGenerator, n: int) -> int:
	## rand(0, n) включно. Повертає 0 для n <= 0 — так само, як референс §4.
	if n <= 0:
		return 0
	return rng.randi_range(0, n)

static func entry_cost(unit: Unit, penalty: int) -> int:
	## §3.2: cost = max(10, 10 + penalty - cross_country)
	if penalty >= Terrain.IMPASSABLE:
		return Terrain.IMPASSABLE
	return maxi(10, 10 + penalty - unit.cross_country())

static func entry_cost_at(unit: Unit, board: Board, p: Vector2i) -> int:
	return entry_cost(unit, board.penalty_at(p))

static func armour_sector(target_facing: int, target_pos: Vector2i, attacker_pos: Vector2i) -> int:
	## §3.4. Цілі числа, без тригонометрії.
	var v: Vector2i = attacker_pos - target_pos
	if v == Vector2i.ZERO:
		return UnitTypes.ArmourSector.FRONT
	var f: Vector2i = Board.DIRS_8[target_facing]
	var dot: int = f.x * v.x + f.y * v.y
	var len_sq_f: int = f.x * f.x + f.y * f.y
	var len_sq_v: int = v.x * v.x + v.y * v.y
	# cos²θ <= 1/2, cross-multiplied to avoid integer-division truncation.
	if 2 * dot * dot <= len_sq_f * len_sq_v:
		return UnitTypes.ArmourSector.SIDE
	return UnitTypes.ArmourSector.REAR if dot < 0 else UnitTypes.ArmourSector.FRONT

const MIN_DAMAGE: int = 10

static func compute_damage(rng: RandomNumberGenerator, attacker: Unit, target: Unit,
		veterancy_level: int, sector: int, dist_sq: int) -> int:
	## §3.3. Порядок множників критичний — не переставляти.
	var a: int = attacker.attack()
	var ac: int = attacker.unit_class()
	var tc: int = target.unit_class()

	var dmg: float = 0.75 * float(a) + float(roll(rng, a / 4))

	if ac != UnitTypes.UnitClass.ENGINEER:
		dmg += float(a * veterancy_level) / 8.0

	if ac == UnitTypes.UnitClass.INFANTRY:
		if dist_sq <= 2:
			dmg *= 4.0
		# броня не віднімається взагалі
	else:
		var r: int = target.armour(sector)
		dmg -= 0.75 * float(r) + float(roll(rng, r / 4))

	if ac == UnitTypes.UnitClass.ARTILLERY:
		if tc == UnitTypes.UnitClass.TANK:
			dmg += float(roll(rng, a / 2))
		if dist_sq <= 4:
			dmg /= 2.0
		if tc == UnitTypes.UnitClass.LIGHT_VEHICLE:
			dmg /= 2.0

	if tc == UnitTypes.UnitClass.INFANTRY and (ac == UnitTypes.UnitClass.TANK or ac == UnitTypes.UnitClass.ARTILLERY):
		dmg /= 4.0

	return maxi(MIN_DAMAGE, int(dmg))

static func drone_damage(rng: RandomNumberGenerator) -> int:
	## §3.9. Броня ігнорується повністю: дрон заходить згори, сектор не рахується.
	return 120 + roll(rng, 60)

static func distance_sq(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return d.x * d.x + d.y * d.y

static func in_radius(a: Vector2i, b: Vector2i, r: int) -> bool:
	## §3.1: евклідів радіус, порівняння квадратів — без sqrt.
	return distance_sq(a, b) <= r * r
