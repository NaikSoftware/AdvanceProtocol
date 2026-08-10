extends GutTest

const INF_RIFLE := 0
const LIGHT_CAR := 2
const MEDIUM_TANK := 5
const HEAVY_TANK := 8
const FIELD_GUN := 9
const ENGINEER := 11

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _u(type_id: int) -> Unit:
	return Unit.create(1, type_id, 0, Vector2i.ZERO, 0)

func _samples(attacker_type: int, target_type: int, level: int, sector: int, dist_sq: int) -> Array[int]:
	var out: Array[int] = []
	for s in 200:
		out.append(Rules.compute_damage(_rng(s), _u(attacker_type), _u(target_type), level, sector, dist_sq))
	return out

func _min(a: Array[int]) -> int:
	var m: int = a[0]
	for v in a:
		m = mini(m, v)
	return m

func _max(a: Array[int]) -> int:
	var m: int = a[0]
	for v in a:
		m = maxi(m, v)
	return m

func test_damage_never_below_ten() -> void:
	var s: Array[int] = _samples(LIGHT_CAR, HEAVY_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_eq(_min(s), 10, "§3.3: мінімум 10, ніщо не є невразливим")

func test_infantry_ignores_armour_entirely() -> void:
	var vs_heavy: Array[int] = _samples(INF_RIFLE, HEAVY_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	var vs_infantry: Array[int] = _samples(INF_RIFLE, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_eq(_min(vs_heavy), _min(vs_infantry), "піхота не віднімає броню взагалі")
	assert_eq(_max(vs_heavy), _max(vs_infantry))

func test_infantry_base_range_band() -> void:
	# A = 15: 0.75*15 = 11.25, кидок 0..3 -> 11..14, але підлога 10 не втручається
	var s: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_between(_min(s), 11, 12)
	assert_between(_max(s), 13, 15)

func test_infantry_close_assault_is_quadruple() -> void:
	var far: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	var close: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 2)
	assert_between(_min(close), _min(far) * 4, _min(far) * 4 + 3,
		"§3.3: dist_sq <= 2 множить на 4, з поправкою на зрізання int()")

func test_close_assault_boundary_is_dist_sq_two() -> void:
	var at_two: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 2)
	var at_three: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 3)
	assert_true(_min(at_two) > _min(at_three), "діагональний сусід (dist_sq=2) ще штурм, dist_sq=3 вже ні")

func test_experience_adds_one_eighth_of_attack_per_level() -> void:
	var v0: Array[int] = _samples(MEDIUM_TANK, LIGHT_CAR, 0, UnitTypes.ArmourSector.REAR, 9)
	var v4: Array[int] = _samples(MEDIUM_TANK, LIGHT_CAR, 4, UnitTypes.ArmourSector.REAR, 9)
	assert_between(_min(v4) - _min(v0), 47, 48, "+A*V/8 = 47.5")

func test_engineers_get_no_experience_bonus() -> void:
	var v0: Array[int] = _samples(ENGINEER, LIGHT_CAR, 0, UnitTypes.ArmourSector.FRONT, 9)
	var v5: Array[int] = _samples(ENGINEER, LIGHT_CAR, 5, UnitTypes.ArmourSector.FRONT, 9)
	assert_eq(_min(v0), _min(v5), "§3.3: інженер не отримує бонусу за досвід")

func test_flanking_beats_frontal_fire() -> void:
	var front: Array[int] = _samples(MEDIUM_TANK, HEAVY_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	var side: Array[int] = _samples(MEDIUM_TANK, HEAVY_TANK, 0, UnitTypes.ArmourSector.SIDE, 9)
	var rear: Array[int] = _samples(MEDIUM_TANK, HEAVY_TANK, 0, UnitTypes.ArmourSector.REAR, 9)
	assert_true(_min(side) > _min(front), "борт болючіший за лоб")
	assert_true(_min(rear) > _min(side), "корма болючіша за борт")

func test_artillery_bonus_against_tanks() -> void:
	var vs_tank: Array[int] = _samples(FIELD_GUN, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 25)
	# Без бонусу максимум недосяжний вище 0.75*200 + 50 - 0.75*37 = 172.25 -> 172.
	# Усе, що більше, може дати лише додатковий rand(0, A/2) проти танка.
	assert_true(_max(vs_tank) > 172, "§3.3: проти танка додається rand(0, A/2)")

func test_artillery_minimum_range_penalty() -> void:
	var close: Array[int] = _samples(FIELD_GUN, LIGHT_CAR, 0, UnitTypes.ArmourSector.FRONT, 4)
	var far: Array[int] = _samples(FIELD_GUN, LIGHT_CAR, 0, UnitTypes.ArmourSector.FRONT, 25)
	assert_true(_min(close) < _min(far), "dist_sq <= 4 ділить шкоду навпіл")

func test_artillery_halved_against_light_vehicles() -> void:
	var vs_light: Array[int] = _samples(FIELD_GUN, LIGHT_CAR, 0, UnitTypes.ArmourSector.SIDE, 25)
	var vs_tank: Array[int] = _samples(FIELD_GUN, MEDIUM_TANK, 0, UnitTypes.ArmourSector.SIDE, 25)
	assert_true(_min(vs_light) < _min(vs_tank), "легка техніка отримує половину")

func test_armour_piercing_quartered_against_infantry() -> void:
	var vs_inf: Array[int] = _samples(MEDIUM_TANK, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	var vs_gun: Array[int] = _samples(MEDIUM_TANK, FIELD_GUN, 0, UnitTypes.ArmourSector.REAR, 9)
	assert_true(_min(vs_inf) * 3 < _min(vs_gun), "§3.3: танк/арта по піхоті — /4")

func test_light_vehicles_do_not_take_the_infantry_penalty() -> void:
	# §3.9: саме тому легка техніка — відповідь на дронарів
	var light_vs_inf: Array[int] = _samples(LIGHT_CAR, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	var tank_vs_inf: Array[int] = _samples(MEDIUM_TANK, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_true(_min(light_vs_inf) > _min(tank_vs_inf))

func test_drone_strike_band() -> void:
	var out: Array[int] = []
	for s in 300:
		out.append(Rules.drone_damage(_rng(s)))
	assert_eq(_min(out), 120, "§3.9: 120 + rand(0, 60)")
	assert_between(_max(out), 170, 180)

func test_damage_is_deterministic_per_seed() -> void:
	var a: int = Rules.compute_damage(_rng(42), _u(MEDIUM_TANK), _u(HEAVY_TANK), 2, UnitTypes.ArmourSector.SIDE, 9)
	var b: int = Rules.compute_damage(_rng(42), _u(MEDIUM_TANK), _u(HEAVY_TANK), 2, UnitTypes.ArmourSector.SIDE, 9)
	assert_eq(a, b)
