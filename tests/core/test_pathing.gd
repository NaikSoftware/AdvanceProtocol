extends GutTest

func _open_board() -> Board:
	return Board.create(10, 10, Terrain.GroundState.DRY)

func _road_board() -> Board:
	var b: Board = _open_board()
	for x in 10:
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	return b

func test_zones_split_at_fire_cost() -> void:
	var b: Board = _road_board()
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)   # ap 48, fire_cost 20
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, {})
	for p in z.move_and_fire:
		assert_true(tank.ap - z.cost_to(p) >= tank.fire_cost(),
			"золота зона: після руху лишається >= fire_cost")
	for p in z.move_only:
		assert_true(tank.ap - z.cost_to(p) < tank.fire_cost(),
			"червона зона: на постріл уже не вистачає")

func test_zones_do_not_overlap() -> void:
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(_road_board(), tank, {})
	for p in z.move_and_fire:
		assert_false(z.move_only.has(p), "тайл належить рівно одній зоні")

func test_start_tile_is_reachable_at_zero_cost() -> void:
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(4, 4), 0)
	var z: Pathing.Zones = Pathing.compute_zones(_open_board(), tank, {})
	assert_eq(z.cost_to(Vector2i(4, 4)), 0)
	assert_true(z.move_and_fire.has(Vector2i(4, 4)), "стояти на місці й стріляти завжди можна")

func test_road_reaches_further_than_rough_ground() -> void:
	var tank_road: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z_road: Pathing.Zones = Pathing.compute_zones(_road_board(), tank_road, {})
	var forest: Board = _open_board()
	for x in 10:
		forest.set_kind(Vector2i(x, 5), Terrain.Kind.FOREST)
	var tank_forest: Unit = Unit.create(2, 5, 0, Vector2i(0, 5), 2)
	var z_forest: Pathing.Zones = Pathing.compute_zones(forest, tank_forest, {})
	var target := Vector2i(2, 5)
	assert_true(z_road.can_reach(target), "дорогою сюди дістатися можна")
	assert_true(z_forest.can_reach(target), "лісом теж можна, тільки дорожче")
	assert_true(z_road.cost_to(target) < z_forest.cost_to(target))

func test_infantry_ignores_terrain() -> void:
	var b: Board = _open_board()
	for y in 10:
		b.set_kind(Vector2i(3, y), Terrain.Kind.FOREST)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, inf, {})
	assert_eq(z.cost_to(Vector2i(3, 5)), 30, "піхота платить по 10 за тайл незалежно від лісу")

func test_impassable_tiles_are_unreachable() -> void:
	var b: Board = _open_board()
	for y in 10:
		b.set_kind(Vector2i(2, y), Terrain.Kind.WATER)
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, {})
	assert_false(z.can_reach(Vector2i(2, 5)))
	assert_false(z.can_reach(Vector2i(5, 5)), "за водою нічого не досяжно")

func test_occupied_tiles_block_movement() -> void:
	var b: Board = _road_board()
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var occupied: Dictionary = {Vector2i(2, 5): 99}
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, occupied)
	assert_false(z.can_reach(Vector2i(2, 5)), "на чужий тайл не стають")

func test_movement_never_uses_diagonals() -> void:
	var b: Board = _open_board()
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(0, 0), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, inf, {})
	assert_eq(z.cost_to(Vector2i(1, 1)), 20, "§3.1: діагональ — це два ортогональні кроки")

func test_path_reconstruction_is_contiguous() -> void:
	var b: Board = _road_board()
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, {})
	var path: Array[Vector2i] = Pathing.path_to(z, Vector2i(3, 5))
	assert_eq(path.size(), 3, "шлях не містить стартовий тайл")
	assert_eq(path[path.size() - 1], Vector2i(3, 5))
	var prev: Vector2i = tank.pos
	for step in path:
		assert_eq(absi(step.x - prev.x) + absi(step.y - prev.y), 1, "кожен крок — один ортогональний тайл")
		prev = step

func test_exhausted_unit_can_reach_only_itself() -> void:
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(4, 4), 0)
	tank.exhaust()
	var z: Pathing.Zones = Pathing.compute_zones(_open_board(), tank, {})
	assert_eq(z.cost.size(), 1)
	assert_eq(z.move_and_fire.size(), 0, "з нулем AP стріляти вже нічим")
