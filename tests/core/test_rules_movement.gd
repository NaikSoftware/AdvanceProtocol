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
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)   # cross_country 110
	assert_eq(Rules.entry_cost(infantry, 12), 10, "піхота платить підлогу всюди")
	assert_eq(Rules.entry_cost(infantry, 0), 10)

func test_entry_cost_formula() -> void:
	var medium: Unit = Unit.create(1, 5, 0, Vector2i.ZERO, 0)     # cross_country 12
	assert_eq(Rules.entry_cost(medium, 0), 10, "дорога: max(10, 10+0-12)")
	assert_eq(Rules.entry_cost(medium, 20), 18, "10 + 20 - 12")

func test_infantry_pays_the_floor_on_every_passable_tile() -> void:
	# Забудова (100, у багнюці 110) — найдорожчий прохідний тайл. Якщо піхота платить
	# за неї більше підлоги, сховок у будинках (§3.3) недосяжний: при 30 AP вхід
	# з'їдає весь хід, а в багнюці будинок — стіна.
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)
	for kind in Terrain.Kind.values():
		for gs in Terrain.GroundState.values():
			var p: int = Terrain.penalty(kind, gs)
			if p < Terrain.IMPASSABLE:
				assert_eq(Rules.entry_cost(infantry, p), 10, "Kind %d x GroundState %d" % [kind, gs])

func test_vehicles_cannot_afford_a_building() -> void:
	# Забудова — земля піхоти арифметикою, без окремого правила (§4, референс).
	for id in UnitTypes.TYPES.size():
		var u: Unit = Unit.create(1, id, 0, Vector2i.ZERO, 0)
		if u.unit_class() == UnitTypes.UnitClass.INFANTRY:
			continue
		var cost: int = Rules.entry_cost(u, Terrain.penalty(Terrain.Kind.BUILDING, Terrain.GroundState.FROZEN))
		assert_true(cost > u.max_ap(), "unit %d: %d AP проти %d" % [id, u.max_ap(), cost])

func test_engineer_is_the_worst_offroad() -> void:
	var engineer: Unit = Unit.create(1, 11, 0, Vector2i.ZERO, 0)  # cross_country -5
	var medium: Unit = Unit.create(2, 5, 0, Vector2i.ZERO, 0)
	assert_true(Rules.entry_cost(engineer, 12) > Rules.entry_cost(medium, 12),
		"§3.6: інженер живе на дорогах")

func test_impassable_stays_impassable_for_everyone() -> void:
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)
	assert_true(Rules.entry_cost(infantry, Terrain.IMPASSABLE) >= Terrain.IMPASSABLE,
		"непрохідність — це нескінченний штраф, а не спецвипадок у мувері")

func test_terrain_penalty_never_lands_in_the_gap_between_ordinary_and_impassable() -> void:
	# entry_cost()'s `penalty >= Terrain.IMPASSABLE` guard is only safe because
	# Terrain.penalty() never returns a value between the ordinary maximum
	# (~30 base, ~110 with mud) and 1_000_000. Pin that assumption here so a
	# future mid-range penalty (say, 5000) fails this build instead of quietly
	# tricking entry_cost() into treating a merely-expensive tile as passable.
	for kind in Terrain.Kind.values():
		for gs in Terrain.GroundState.values():
			var p: int = Terrain.penalty(kind, gs)
			var ok: bool = p < 1000 or p == Terrain.IMPASSABLE
			assert_true(ok, "Kind %d x GroundState %d: penalty %d потрапив у заборонений проміжок" % [kind, gs, p])
