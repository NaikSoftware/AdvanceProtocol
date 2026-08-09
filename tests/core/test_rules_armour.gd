extends GutTest

const FRONT := UnitTypes.ArmourSector.FRONT
const SIDE := UnitTypes.ArmourSector.SIDE
const REAR := UnitTypes.ArmourSector.REAR

# Ціль стоїть у (5,5) і дивиться на північ (facing 0 = Vector2i(0,-1)).
const T := Vector2i(5, 5)

func test_attacker_straight_ahead_hits_front() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(5, 2)), FRONT)

func test_attacker_directly_behind_hits_rear() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(5, 9)), REAR)

func test_attacker_abeam_hits_side() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(9, 5)), SIDE)
	assert_eq(Rules.armour_sector(0, T, Vector2i(1, 5)), SIDE)

func test_forty_five_degrees_is_side() -> void:
	# рівно 45° від осі фейсингу: cos^2 = 0.5, а поріг у §3.4 — "<= 16" при масштабі 32
	assert_eq(Rules.armour_sector(0, T, Vector2i(8, 2)), SIDE)

func test_shallow_angle_is_still_front() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(6, 1)), FRONT)

func test_rotating_target_rotates_the_sectors() -> void:
	# та сама позиція атакера, ціль розвернулась на схід (facing 2)
	assert_eq(Rules.armour_sector(2, T, Vector2i(9, 5)), FRONT)
	assert_eq(Rules.armour_sector(2, T, Vector2i(1, 5)), REAR)
	assert_eq(Rules.armour_sector(2, T, Vector2i(5, 1)), SIDE)

func test_attacker_on_target_tile_is_front() -> void:
	assert_eq(Rules.armour_sector(0, T, T), FRONT, "виродженого випадку не має бути, але падати він не сміє")

func test_every_facing_has_a_front_a_side_and_a_rear() -> void:
	for facing in 8:
		var seen: Dictionary = {}
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				if dx == 0 and dy == 0:
					continue
				seen[Rules.armour_sector(facing, T, T + Vector2i(dx, dy))] = true
		assert_eq(seen.size(), 3, "фейсинг %d має давати всі три сектори" % facing)
