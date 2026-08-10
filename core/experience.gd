class_name Experience
extends RefCounted
## §3.7. Прогрес — на клас і на гравця, за завдану шкоду. У скірміші — на матч.

const MAX_LEVEL: int = 5

const THRESHOLDS: Dictionary = {
	UnitTypes.UnitClass.INFANTRY:      [150, 375, 938, 2344, 5859],
	UnitTypes.UnitClass.LIGHT_VEHICLE: [700, 1750, 4375, 10938, 27344],
	UnitTypes.UnitClass.TANK:          [1000, 2500, 6250, 15625, 39063],
	UnitTypes.UnitClass.ARTILLERY:     [2000, 5000, 12500, 31250, 78125],
	UnitTypes.UnitClass.ENGINEER:      [],
}

var xp: Array[int] = [0, 0, 0, 0, 0]
var level: Array[int] = [0, 0, 0, 0, 0]

static func create() -> Experience:
	return Experience.new()

func level_of(unit_class: int) -> int:
	return level[unit_class]

func add_damage(unit_class: int, amount: int) -> int:
	var thresholds: Array = THRESHOLDS[unit_class]
	if thresholds.is_empty() or amount <= 0:
		return level[unit_class]
	xp[unit_class] += amount
	while level[unit_class] < MAX_LEVEL:
		var next: int = thresholds[level[unit_class]]
		if xp[unit_class] < next:
			break
		xp[unit_class] -= next
		level[unit_class] += 1
	return level[unit_class]
