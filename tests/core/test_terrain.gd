extends GutTest

func test_road_is_free_of_penalty() -> void:
	assert_eq(Terrain.penalty(Terrain.Kind.ROAD, Terrain.GroundState.DRY), 0)

func test_ground_state_never_touches_roads() -> void:
	for gs in [Terrain.GroundState.DRY, Terrain.GroundState.MUD, Terrain.GroundState.FROZEN]:
		assert_eq(Terrain.penalty(Terrain.Kind.ROAD, gs), 0, "дорога не залежить від ґрунту — у цьому її сенс")
		assert_eq(Terrain.penalty(Terrain.Kind.BRIDGE, gs), 0, "міст поводиться як дорога")

func test_mud_makes_offroad_worse() -> void:
	var dry: int = Terrain.penalty(Terrain.Kind.FIELD, Terrain.GroundState.DRY)
	var mud: int = Terrain.penalty(Terrain.Kind.FIELD, Terrain.GroundState.MUD)
	assert_true(mud > dry, "багнюка дорожча за суху землю")

func test_frozen_makes_offroad_cheaper() -> void:
	var dry: int = Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.DRY)
	var frozen: int = Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.FROZEN)
	assert_true(frozen < dry, "мерзла земля дешевша")

func test_marsh_is_impassable_until_frozen() -> void:
	assert_false(Terrain.is_passable(Terrain.Kind.MARSH, Terrain.GroundState.DRY))
	assert_false(Terrain.is_passable(Terrain.Kind.MARSH, Terrain.GroundState.MUD))
	assert_true(Terrain.is_passable(Terrain.Kind.MARSH, Terrain.GroundState.FROZEN),
		"§3.12: на морозі болото стає прохідним")

func test_water_is_never_passable() -> void:
	for gs in [Terrain.GroundState.DRY, Terrain.GroundState.MUD, Terrain.GroundState.FROZEN]:
		assert_false(Terrain.is_passable(Terrain.Kind.WATER, gs), "лід по воді — окрема фіча, не зараз")

func test_destroyed_bridge_is_impassable() -> void:
	assert_true(Terrain.is_passable(Terrain.Kind.BRIDGE, Terrain.GroundState.DRY))
	assert_false(Terrain.is_passable(Terrain.Kind.BRIDGE_DESTROYED, Terrain.GroundState.DRY))

func test_penalty_never_negative() -> void:
	for kind in Terrain.Kind.values():
		for gs in Terrain.GroundState.values():
			var p: int = Terrain.penalty(kind, gs)
			assert_true(p >= 0, "штраф не може бути відʼємним")
