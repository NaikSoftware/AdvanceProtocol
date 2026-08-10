extends GutTest

func test_roster_has_thirteen_entries() -> void:
	assert_eq(UnitTypes.count(), 13, "ростер §3.6 має 13 записів, 0..12")

func test_ids_match_indices() -> void:
	for i in UnitTypes.count():
		assert_eq(UnitTypes.get_type(i)["id"], i, "id має дорівнювати індексу")

func test_armour_is_ordered_front_side_rear() -> void:
	for i in UnitTypes.count():
		var t: Dictionary = UnitTypes.get_type(i)
		var a: Array = t["armour"]
		assert_true(a[0] >= a[1], "%s: front(%d) >= side(%d)" % [t["name_key"], a[0], a[1]])
		assert_true(a[1] >= a[2], "%s: side(%d) >= rear(%d)" % [t["name_key"], a[1], a[2]])

func test_tank_mobility_is_strictly_ordered() -> void:
	# §3.6: light -> medium -> tank destroyer -> heavy, і по AP, і по прохідності
	var light: Dictionary = UnitTypes.get_type(7)
	var medium: Dictionary = UnitTypes.get_type(5)
	var destroyer: Dictionary = UnitTypes.get_type(6)
	var heavy: Dictionary = UnitTypes.get_type(8)
	for key in ["max_ap", "cross_country"]:
		assert_true(light[key] > medium[key], "light > medium за %s" % key)
		assert_true(medium[key] > destroyer[key], "medium > tank destroyer за %s" % key)
		assert_true(destroyer[key] > heavy[key], "tank destroyer > heavy за %s" % key)

func test_only_assault_squad_carries_drones() -> void:
	for i in UnitTypes.count():
		var expected: int = 2 if i == 1 else 0
		assert_eq(UnitTypes.get_type(i)["drones"], expected, "дрони лише в штурмового відділення (#1)")

func test_engineers_have_no_weapon() -> void:
	for i in UnitTypes.count():
		var t: Dictionary = UnitTypes.get_type(i)
		if t["unit_class"] == UnitTypes.UnitClass.ENGINEER:
			assert_eq(t["attack"], 0, "інженер не має зброї")

func test_every_name_key_is_unique_and_neutral() -> void:
	var seen: Dictionary = {}
	for i in UnitTypes.count():
		var key: String = UnitTypes.get_type(i)["name_key"]
		assert_false(seen.has(key), "ключ %s дублюється" % key)
		seen[key] = true
		assert_true(key.begins_with("UNIT_"), "ключ перекладу має починатися з UNIT_")
