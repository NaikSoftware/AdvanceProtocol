extends GutTest

func _make(type_id: int) -> Unit:
	return Unit.create(1, type_id, 0, Vector2i(3, 3), 0)

func test_unit_starts_full() -> void:
	var u: Unit = _make(5)
	assert_eq(u.hp, 400)
	assert_eq(u.ap, 48)
	assert_true(u.is_alive())
	assert_false(u.has_fired)

func test_assault_squad_starts_with_two_drones() -> void:
	assert_eq(_make(1).drones_left, 2)
	assert_eq(_make(0).drones_left, 0)

func test_armour_lookup_by_sector() -> void:
	var u: Unit = _make(6)   # винищувач танків 45/14/8
	assert_eq(u.armour(UnitTypes.ArmourSector.FRONT), 45)
	assert_eq(u.armour(UnitTypes.ArmourSector.SIDE), 14)
	assert_eq(u.armour(UnitTypes.ArmourSector.REAR), 8)

func test_exhaust_zeroes_ap_and_marks_fired() -> void:
	var u: Unit = _make(5)
	u.exhaust()
	assert_eq(u.ap, 0)
	assert_true(u.has_fired)

func test_refill_resets_ap_and_fired_flag() -> void:
	var u: Unit = _make(5)
	u.exhaust()
	u.refill_ap()
	assert_eq(u.ap, 48)
	assert_false(u.has_fired)

func test_dead_unit_is_not_alive() -> void:
	var u: Unit = _make(0)
	u.hp = 0
	assert_false(u.is_alive())
