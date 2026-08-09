extends GutTest

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func test_roll_is_zero_for_non_positive() -> void:
	assert_eq(Rules.roll(_rng(1), 0), 0)
	assert_eq(Rules.roll(_rng(1), -5), 0)

func test_roll_stays_within_inclusive_bounds() -> void:
	var r := _rng(12345)
	var saw_low: bool = false
	var saw_high: bool = false
	for i in 500:
		var v: int = Rules.roll(r, 10)
		assert_between(v, 0, 10)
		saw_low = saw_low or v == 0
		saw_high = saw_high or v == 10
	assert_true(saw_low, "0 має випадати — межа включна")
	assert_true(saw_high, "n має випадати — межа включна")

func test_roll_is_deterministic_for_same_seed() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	var ra := _rng(777)
	var rb := _rng(777)
	for i in 20:
		a.append(Rules.roll(ra, 100))
		b.append(Rules.roll(rb, 100))
	assert_eq(a, b, "один сід — одна послідовність, інакше реплеї неможливі")

func test_entry_cost_has_floor_of_ten() -> void:
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)   # cross_country 80
	assert_eq(Rules.entry_cost(infantry, 12), 10, "піхота платить підлогу всюди")
	assert_eq(Rules.entry_cost(infantry, 0), 10)

func test_entry_cost_formula() -> void:
	var medium: Unit = Unit.create(1, 5, 0, Vector2i.ZERO, 0)     # cross_country 12
	assert_eq(Rules.entry_cost(medium, 0), 10, "дорога: max(10, 10+0-12)")
	assert_eq(Rules.entry_cost(medium, 20), 18, "10 + 20 - 12")

func test_engineer_is_the_worst_offroad() -> void:
	var engineer: Unit = Unit.create(1, 11, 0, Vector2i.ZERO, 0)  # cross_country -5
	var medium: Unit = Unit.create(2, 5, 0, Vector2i.ZERO, 0)
	assert_true(Rules.entry_cost(engineer, 12) > Rules.entry_cost(medium, 12),
		"§3.6: інженер живе на дорогах")

func test_impassable_stays_impassable_for_everyone() -> void:
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)
	assert_true(Rules.entry_cost(infantry, Terrain.IMPASSABLE) >= Terrain.IMPASSABLE,
		"непрохідність — це нескінченний штраф, а не спецвипадок у мувері")
