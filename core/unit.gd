class_name Unit
extends RefCounted
## Екземпляр юніта в бою. Стати читаються з UnitTypes, тут лише змінний стан.

var id: int = 0
var type_id: int = 0
var owner: int = 0
var pos: Vector2i = Vector2i.ZERO
var facing: int = 0
var hp: int = 0
var ap: int = 0
var drones_left: int = 0
var has_fired: bool = false

static func create(p_id: int, p_type_id: int, p_owner: int, p_pos: Vector2i, p_facing: int) -> Unit:
	var u := Unit.new()
	u.id = p_id
	u.type_id = p_type_id
	u.owner = p_owner
	u.pos = p_pos
	u.facing = p_facing
	var t: Dictionary = UnitTypes.get_type(p_type_id)
	u.hp = t["max_hp"]
	u.ap = t["max_ap"]
	u.drones_left = t["drones"]
	return u

func type() -> Dictionary:
	return UnitTypes.get_type(type_id)

func unit_class() -> int:
	return type()["unit_class"]

func attack() -> int:
	return type()["attack"]

func max_ap() -> int:
	return type()["max_ap"]

func max_hp() -> int:
	return type()["max_hp"]

func attack_range() -> int:
	return type()["attack_range"]

func fire_cost() -> int:
	return type()["fire_cost"]

func armour(sector: int) -> int:
	return type()["armour"][sector]

func cross_country() -> int:
	return type()["cross_country"]

func vision() -> int:
	return type()["vision"]

func is_alive() -> bool:
	return hp > 0

func refill_ap() -> void:
	ap = max_ap()
	has_fired = false

func spend_ap(n: int) -> void:
	ap = maxi(0, ap - n)

func exhaust() -> void:
	## §3.2: постріл обнуляє AP і завершує активність юніта на цей хід.
	ap = 0
	has_fired = true
