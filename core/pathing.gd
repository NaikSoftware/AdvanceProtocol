class_name Pathing
extends RefCounted
## Дві зони руху (§3.2) — Dijkstra по вартості входу, 4-звʼязна сітка.

class Zones extends RefCounted:
	var origin: Vector2i = Vector2i.ZERO
	var cost: Dictionary = {}          # Vector2i -> int
	var came_from: Dictionary = {}     # Vector2i -> Vector2i
	var move_and_fire: Array[Vector2i] = []
	var move_only: Array[Vector2i] = []

	func can_reach(p: Vector2i) -> bool:
		return cost.has(p)

	func cost_to(p: Vector2i) -> int:
		## Викликати лише після can_reach(). Недосяжний тайл — це помилка виклику,
		## а не значення: −1 мовчки перевертає будь-яке порівняння `<`, і саме так
		## двічі падали тести цього завдання. Assert вирізається в release-збірці,
		## тож там лишається −1 як мʼяка деградація замість падіння на телефоні.
		assert(cost.has(p), "cost_to() для недосяжного тайла: %v" % p)
		return cost.get(p, -1)

static func compute_zones(board: Board, unit: Unit, occupied: Dictionary) -> Zones:
	var z := Zones.new()
	z.origin = unit.pos
	z.cost[unit.pos] = 0

	# Проста черга з пошуком мінімуму: карти маленькі (десятки на десятки),
	# купа тут не окупається і лише додає коду.
	var frontier: Array[Vector2i] = [unit.pos]
	while not frontier.is_empty():
		var best_i: int = 0
		for i in frontier.size():
			if z.cost[frontier[i]] < z.cost[frontier[best_i]]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)

		for n in board.neighbours4(current):
			if occupied.has(n):
				continue
			var step: int = Rules.entry_cost_at(unit, board, n)
			if step >= Terrain.IMPASSABLE:
				continue
			var total: int = z.cost[current] + step
			if total > unit.ap:
				continue
			if z.cost.has(n) and z.cost[n] <= total:
				continue
			z.cost[n] = total
			z.came_from[n] = current
			frontier.append(n)

	var fire_cost: int = unit.fire_cost()
	for p: Vector2i in z.cost:
		var left: int = unit.ap - z.cost[p]
		if left >= fire_cost:
			z.move_and_fire.append(p)
		else:
			z.move_only.append(p)
	return z

static func path_to(zones: Zones, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not zones.cost.has(target) or target == zones.origin:
		return out
	var current: Vector2i = target
	while current != zones.origin:
		out.push_front(current)
		current = zones.came_from[current]
	return out
