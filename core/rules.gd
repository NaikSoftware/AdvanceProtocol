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
	var cos2_scaled: int = (dot * dot << 5) / (len_sq_f * len_sq_v)
	if cos2_scaled <= 16:
		return UnitTypes.ArmourSector.SIDE
	return UnitTypes.ArmourSector.REAR if dot < 0 else UnitTypes.ArmourSector.FRONT
