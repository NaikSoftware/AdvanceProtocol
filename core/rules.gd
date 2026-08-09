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
