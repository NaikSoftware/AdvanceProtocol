extends GutTest

const INF := UnitTypes.UnitClass.INFANTRY
const TANK := UnitTypes.UnitClass.TANK
const ENG := UnitTypes.UnitClass.ENGINEER

func test_starts_at_zero() -> void:
	assert_eq(Veterancy.create().level_of(INF), 0)

func test_first_infantry_threshold_is_150() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(INF, 149), 0)
	assert_eq(v.add_damage(INF, 1), 1, "150 сумарно — рівень 1")

func test_threshold_is_subtracted_not_reset() -> void:
	var v: Veterancy = Veterancy.create()
	v.add_damage(INF, 200)
	assert_eq(v.xp[INF], 50, "§3.7: пул зменшується на поріг, залишок переноситься")

func test_multiple_levels_in_one_hit() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(INF, 600), 2, "150 + 375 = 525 <= 600")

func test_caps_at_five() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(INF, 1_000_000), 5)
	assert_eq(v.add_damage(INF, 1_000_000), 5, "вище пʼятого не росте")

func test_classes_are_independent() -> void:
	var v: Veterancy = Veterancy.create()
	v.add_damage(INF, 500)
	assert_eq(v.level_of(TANK), 0, "пули не течуть між класами")

func test_tank_progresses_slower_than_infantry() -> void:
	var a: Veterancy = Veterancy.create()
	var b: Veterancy = Veterancy.create()
	a.add_damage(INF, 1000)
	b.add_damage(TANK, 1000)
	assert_true(a.level_of(INF) > b.level_of(TANK))

func test_engineers_never_level() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(ENG, 1_000_000), 0, "§3.7: інженери шкоди не завдають і рівнів не мають")
