extends GutTest
## Прев'ю несе HP цілі й клас наслідку, щоб підпис плити не рахував нічого у вигляді (§6).
## Типи: 0 — стрілецьке відділення, 2 — бронеавтомобіль, 5 — середній танк.

var state: BattleState


func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0


func _shot(shooter_type: int, target_type: int, target_hp: int, kind: int = Terrain.Kind.FIELD) -> Dictionary:
	state.board.set_kind(Vector2i(4, 5), kind)
	var t: Unit = state.add_unit(target_type, 1, Vector2i(4, 5), 0)
	t.hp = target_hp
	var a: Unit = state.add_unit(shooter_type, 0, Vector2i(4, 6), 0)
	return FireCommand.preview(state, a.id, t.id)


func test_shot_none_leaves_hp_range() -> void:
	var p: Dictionary = _shot(5, 5, 250)
	assert_eq(p["hp"], 250)
	assert_eq(p["hp_left_min"], maxi(0, 250 - p["max"]))
	assert_eq(p["hp_left_max"], maxi(0, 250 - p["min"]))
	assert_eq(p["kill"], "none")


func test_shot_maybe_when_only_max_reaches_hp() -> void:
	var base: Dictionary = _shot(5, 5, 250)
	before_each()
	var p: Dictionary = _shot(5, 5, base["max"])
	assert_gt(p["max"], p["min"])
	assert_eq(p["kill"], "maybe")
	assert_eq(p["hp_left_min"], 0)
	assert_eq(p["hp_left_max"], p["hp"] - p["min"])


func test_shot_sure_when_min_reaches_hp() -> void:
	var base: Dictionary = _shot(5, 5, 250)
	before_each()
	var p: Dictionary = _shot(5, 5, base["min"])
	assert_eq(p["kill"], "sure")
	assert_eq(p["hp_left_min"], 0)
	assert_eq(p["hp_left_max"], 0)


func test_shot_cover_halving_moves_the_class() -> void:
	# Піхота в будівлі: шкода ділиться навпіл, тож HP, що гинуло б у полі, тут вціліє.
	var open_p: Dictionary = _shot(5, 0, 100, Terrain.Kind.FIELD)
	before_each()
	var hp: int = open_p["min"]
	var p_open: Dictionary = _shot(5, 0, hp, Terrain.Kind.FIELD)
	before_each()
	var p_cover: Dictionary = _shot(5, 0, hp, Terrain.Kind.BUILDING)
	assert_eq(p_open["kill"], "sure")
	assert_ne(p_cover["kill"], "sure")
	assert_eq(p_cover["hp"], hp)


func _drone(target_hp: int) -> Dictionary:
	var t: Unit = state.add_unit(5, 1, Vector2i(4, 5), 0)
	t.hp = target_hp
	var a: Unit = state.add_unit(1, 0, Vector2i(4, 6), 0)
	return DroneCommand.preview(state, a.id, t.id)


func test_drone_none_maybe_sure() -> void:
	var b: Vector2i = Rules.drone_damage_bounds()
	var none: Dictionary = _drone(b.y + 100)
	assert_eq(none["kill"], "none")
	assert_eq(none["min"], b.x)
	assert_eq(none["max"], b.y)
	assert_eq(none["hp_left_min"], b.y + 100 - b.y)
	assert_eq(none["hp_left_max"], b.y + 100 - b.x)
	before_each()
	var maybe: Dictionary = _drone(b.y)
	assert_eq(maybe["kill"], "maybe")
	assert_eq(maybe["hp_left_min"], 0)
	assert_eq(maybe["hp_left_max"], b.y - b.x)
	before_each()
	assert_eq(_drone(b.x)["kill"], "sure")
