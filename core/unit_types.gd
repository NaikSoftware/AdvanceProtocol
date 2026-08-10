class_name UnitTypes
extends RefCounted
## Таблиця статів — джерело істини для ростера (§3.6 CLAUDE.md).
## Таблиця в CLAUDE.md з моменту появи цього файлу є документацією, а не істиною.

enum UnitClass { INFANTRY, LIGHT_VEHICLE, TANK, ARTILLERY, ENGINEER }
enum ArmourSector { FRONT, SIDE, REAR }

const TYPES: Array[Dictionary] = [
	{"id": 0, "name_key": "UNIT_RIFLE_SQUAD", "unit_class": UnitClass.INFANTRY,
	 "attack": 15, "max_ap": 30, "max_hp": 100, "attack_range": 3, "fire_cost": 10,
	 "armour": [0, 0, 0], "cross_country": 80, "vision": 5, "drones": 0},
	{"id": 1, "name_key": "UNIT_ASSAULT_SQUAD", "unit_class": UnitClass.INFANTRY,
	 "attack": 15, "max_ap": 30, "max_hp": 100, "attack_range": 3, "fire_cost": 10,
	 "armour": [0, 0, 0], "cross_country": 80, "vision": 5, "drones": 2},
	{"id": 2, "name_key": "UNIT_ARMOURED_CAR", "unit_class": UnitClass.LIGHT_VEHICLE,
	 "attack": 60, "max_ap": 68, "max_hp": 250, "attack_range": 3, "fire_cost": 18,
	 "armour": [27, 18, 10], "cross_country": 5, "vision": 3, "drones": 0},
	{"id": 3, "name_key": "UNIT_TROOP_CARRIER", "unit_class": UnitClass.LIGHT_VEHICLE,
	 "attack": 70, "max_ap": 68, "max_hp": 250, "attack_range": 3, "fire_cost": 18,
	 "armour": [36, 31, 7], "cross_country": 7, "vision": 3, "drones": 0},
	{"id": 4, "name_key": "UNIT_SCOUT_CAR", "unit_class": UnitClass.LIGHT_VEHICLE,
	 "attack": 55, "max_ap": 48, "max_hp": 200, "attack_range": 3, "fire_cost": 18,
	 "armour": [35, 15, 7], "cross_country": 8, "vision": 3, "drones": 0},
	{"id": 5, "name_key": "UNIT_MEDIUM_TANK", "unit_class": UnitClass.TANK,
	 "attack": 95, "max_ap": 48, "max_hp": 400, "attack_range": 4, "fire_cost": 20,
	 "armour": [37, 27, 18], "cross_country": 12, "vision": 4, "drones": 0},
	{"id": 6, "name_key": "UNIT_TANK_DESTROYER", "unit_class": UnitClass.TANK,
	 "attack": 130, "max_ap": 44, "max_hp": 400, "attack_range": 4, "fire_cost": 20,
	 "armour": [45, 14, 8], "cross_country": 11, "vision": 4, "drones": 0},
	{"id": 7, "name_key": "UNIT_LIGHT_TANK", "unit_class": UnitClass.TANK,
	 "attack": 108, "max_ap": 56, "max_hp": 300, "attack_range": 4, "fire_cost": 25,
	 "armour": [37, 16, 10], "cross_country": 13, "vision": 4, "drones": 0},
	{"id": 8, "name_key": "UNIT_HEAVY_TANK", "unit_class": UnitClass.TANK,
	 "attack": 121, "max_ap": 40, "max_hp": 350, "attack_range": 4, "fire_cost": 20,
	 "armour": [56, 25, 20], "cross_country": 9, "vision": 4, "drones": 0},
	{"id": 9, "name_key": "UNIT_FIELD_GUN", "unit_class": UnitClass.ARTILLERY,
	 "attack": 200, "max_ap": 24, "max_hp": 200, "attack_range": 5, "fire_cost": 14,
	 "armour": [15, 0, 0], "cross_country": 6, "vision": 3, "drones": 0},
	{"id": 10, "name_key": "UNIT_HOWITZER", "unit_class": UnitClass.ARTILLERY,
	 "attack": 180, "max_ap": 24, "max_hp": 200, "attack_range": 5, "fire_cost": 14,
	 "armour": [15, 0, 0], "cross_country": 6, "vision": 3, "drones": 0},
	{"id": 11, "name_key": "UNIT_ENGINEER_SQUAD", "unit_class": UnitClass.ENGINEER,
	 "attack": 0, "max_ap": 68, "max_hp": 200, "attack_range": 1, "fire_cost": 20,
	 "armour": [10, 5, 5], "cross_country": -5, "vision": 3, "drones": 0},
	{"id": 12, "name_key": "UNIT_ENGINEER_VEHICLE", "unit_class": UnitClass.ENGINEER,
	 "attack": 0, "max_ap": 76, "max_hp": 200, "attack_range": 1, "fire_cost": 30,
	 "armour": [10, 5, 5], "cross_country": -5, "vision": 3, "drones": 0},
]

static func count() -> int:
	return TYPES.size()

static func get_type(id: int) -> Dictionary:
	assert(id >= 0 and id < TYPES.size(), "невідомий тип юніта: %d" % id)
	return TYPES[id]

static func is_vehicle(unit_class: int) -> bool:
	return unit_class != UnitClass.INFANTRY
