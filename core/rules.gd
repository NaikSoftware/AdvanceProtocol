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

static func _damage_from_rolls(attacker: Unit, target: Unit, experience_level: int, sector: int,
		dist_sq: int, r_attack: int, r_armour: int, r_arty: int) -> int:
	## §3.3. Порядок множників критичний — не переставляти. Спільне тіло для
	## compute_damage() (справжні кидки) і damage_bounds() (підставлені межі
	## кидків) — щоб формула жила рівно в одному місці.
	var a: int = attacker.attack()
	var ac: int = attacker.unit_class()
	var tc: int = target.unit_class()

	var dmg: float = 0.75 * float(a) + float(r_attack)

	if ac != UnitTypes.UnitClass.ENGINEER:
		dmg += float(a * experience_level) / 8.0

	if ac == UnitTypes.UnitClass.INFANTRY:
		if dist_sq <= 2:
			dmg *= 4.0
		# броня не віднімається взагалі
	else:
		var r: int = target.armour(sector)
		dmg -= 0.75 * float(r) + float(r_armour)

	if ac == UnitTypes.UnitClass.ARTILLERY:
		if tc == UnitTypes.UnitClass.TANK:
			dmg += float(r_arty)
		if dist_sq <= 4:
			dmg /= 2.0
		if tc == UnitTypes.UnitClass.LIGHT_VEHICLE:
			dmg /= 2.0

	if tc == UnitTypes.UnitClass.INFANTRY and (ac == UnitTypes.UnitClass.TANK or ac == UnitTypes.UnitClass.ARTILLERY):
		dmg /= 4.0

	return maxi(MIN_DAMAGE, int(dmg))

static func compute_damage(rng: RandomNumberGenerator, attacker: Unit, target: Unit,
		experience_level: int, sector: int, dist_sq: int) -> int:
	## §3.3. Порядок кидків критичний — не переставляти: атака завжди, броня —
	## лише не для піхоти-атакера, артбонус — лише артилерія по танку.
	var a: int = attacker.attack()
	var ac: int = attacker.unit_class()
	var tc: int = target.unit_class()

	var r_attack: int = roll(rng, a / 4)
	var r_armour: int = 0
	if ac != UnitTypes.UnitClass.INFANTRY:
		r_armour = roll(rng, target.armour(sector) / 4)
	var r_arty: int = 0
	if ac == UnitTypes.UnitClass.ARTILLERY and tc == UnitTypes.UnitClass.TANK:
		r_arty = roll(rng, a / 2)

	return _damage_from_rolls(attacker, target, experience_level, sector, dist_sq, r_attack, r_armour, r_arty)

static func damage_bounds(attacker: Unit, target: Unit, experience_level: int, sector: int,
		dist_sq: int) -> Vector2i:
	## Прев'ю (§3.4): точні межі формули без жодного кидка. compute_damage()
	## монотонне за кожним окремим кидком і зрізає (int()) лише один раз
	## наприкінці, тож підстановка 0 і максимуму кожного кидка на його місці
	## дає справжній мінімум і максимум — вибірка сідів тут не потрібна і не
	## гарантує влучення в крайні значення.
	var a: int = attacker.attack()
	var ac: int = attacker.unit_class()
	var tc: int = target.unit_class()

	# roll(rng, n) повертає 0 для n <= 0, інакше сягає щонайбільше n — та сама
	# охорона тут, без rng.
	var attack_roll_max: int = maxi(a / 4, 0)
	var armour_roll_max: int = 0
	if ac != UnitTypes.UnitClass.INFANTRY:
		armour_roll_max = maxi(target.armour(sector) / 4, 0)
	var arty_roll_max: int = 0
	if ac == UnitTypes.UnitClass.ARTILLERY and tc == UnitTypes.UnitClass.TANK:
		arty_roll_max = maxi(a / 2, 0)

	var lo: int = _damage_from_rolls(attacker, target, experience_level, sector, dist_sq,
			0, armour_roll_max, 0)
	var hi: int = _damage_from_rolls(attacker, target, experience_level, sector, dist_sq,
			attack_roll_max, 0, arty_roll_max)
	return Vector2i(lo, hi)

static func drone_damage(rng: RandomNumberGenerator) -> int:
	## §3.9. Броня ігнорується повністю: дрон заходить згори, сектор не рахується.
	return 120 + roll(rng, 60)

static func distance_sq(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return d.x * d.x + d.y * d.y

static func in_radius(a: Vector2i, b: Vector2i, r: int) -> bool:
	## §3.1: ДАЛЬНІСТЬ ЗБРОЇ — евклідове коло, порівняння квадратів, без sqrt.
	## Не для огляду: той міряється ромбом, див. in_vision_diamond().
	return distance_sq(a, b) <= r * r

static func distance_manhattan(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return absi(d.x) + absi(d.y)

static func in_vision_diamond(a: Vector2i, b: Vector2i, r: int) -> bool:
	## §3.1: ОГЛЯД — манхеттенський ромб, а не коло. Це лічильник кроків по
	## 4-напрямковій сітці: «за три тайли» означає за три ходи, тож огляд має ту
	## саму форму, що й рух, і радіус читається як число кроків.
	##
	## Розбіжність з in_radius() на діагоналях — не похибка, а сенс поділу:
	## (3, 4) лежить у колі радіуса 5 і поза ромбом радіуса 5, тож ціль буває
	## в межах дальності й водночас невидимою. Постріл вимагає видимості, отже
	## справжня обвідна вогню — перетин двох форм; саме це дає зуби перевірці
	## видимості дрона (§3.9). Назви двох предикатів навмисне не схожі —
	## сплутати їх на місці виклику не має бути можливо.
	return distance_manhattan(a, b) <= r
