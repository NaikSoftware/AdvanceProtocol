extends GutTest

func test_events_carry_their_payload() -> void:
	var e := Events.UnitMoved.new(7, [Vector2i(1, 1), Vector2i(1, 2)], 4)
	assert_eq(e.unit_id, 7)
	assert_eq(e.path.size(), 2)
	assert_eq(e.facing, 4)

func test_every_event_describes_itself() -> void:
	var samples: Array = [
		Events.UnitMoved.new(1, [Vector2i.ZERO], 0),
		Events.ShotFired.new(1, 2, UnitTypes.ArmourSector.SIDE),
		Events.DamageDealt.new(2, 40, 60),
		Events.UnitDestroyed.new(2, Vector2i(3, 3)),
		Events.MatchEnded.new(0),
	]
	for e in samples:
		assert_true(e is Events.BattleEvent, "усе успадковує спільну базу")
		assert_false(e.describe().is_empty())
