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

func test_every_event_type_constructs_and_describes() -> void:
	var all_events: Array = [
		Events.UnitMoved.new(1, [Vector2i(0, 0), Vector2i(1, 0)], 2),
		Events.UnitTurned.new(1, 3),
		Events.ShotFired.new(1, 2, UnitTypes.ArmourSector.FRONT),
		Events.DroneLaunched.new(1, 2, 1),
		Events.DamageDealt.new(2, 40, 60),
		Events.UnitDestroyed.new(2, Vector2i(3, 3)),
		Events.TileRevealed.new(0, [Vector2i(1, 1), Vector2i(1, 2)]),
		Events.MinePlaced.new(Vector2i(4, 4), 0),
		Events.MineCleared.new(Vector2i(4, 4)),
		Events.MineTriggered.new(Vector2i(5, 5), 3),
		Events.MineRevealed.new(Vector2i(5, 5), 1),
		Events.BridgeChanged.new(Vector2i(6, 6), true),
		Events.UnitRepaired.new(4, 20, 80),
		Events.ObjectiveCaptured.new(0, 1),
		Events.ObjectiveDestroyed.new(1),
		Events.VeterancyGained.new(0, UnitTypes.UnitClass.TANK, 2),
		Events.ApChanged.new(1, 30),
		Events.TurnEnded.new(0),
		Events.TurnStarted.new(1, 5),
		Events.PlayerEliminated.new(2),
		Events.MatchEnded.new(0),
	]
	for e in all_events:
		assert_true(e is Events.BattleEvent, "усе успадковує спільну базу")
		assert_false(e.describe().is_empty())
