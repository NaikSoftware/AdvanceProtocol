extends GutTest
## Прев'ю пострілу несе два факти, які формула шкоди вже використовує: чи віднімається
## броня і чи діє укриття. Кожне правило, що впливає на кидок, має бути видно в UI
## (стовп 5), а вивести їх у поданні означало б дублювати формулу поза core/.
## Типи: 0 — стрілецьке відділення, 2 — бронеавтомобіль, 5 — середній танк.

var state: BattleState


func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0


func _preview(shooter_type: int, target_type: int, target_kind: int = Terrain.Kind.FIELD) -> Dictionary:
	state.board.set_kind(Vector2i(4, 5), target_kind)
	var t: Unit = state.add_unit(target_type, 1, Vector2i(4, 5), 0)
	var a: Unit = state.add_unit(shooter_type, 0, Vector2i(4, 6), 0)
	return FireCommand.preview(state, a.id, t.id)


func test_infantry_shot_at_tank_ignores_armour() -> void:
	assert_true(_preview(0, 5)["armour_ignored"])


func test_tank_shot_at_tank_does_not_ignore_armour() -> void:
	assert_false(_preview(5, 5)["armour_ignored"])


func test_infantry_in_building_is_in_cover_for_any_shooter() -> void:
	for shooter: int in [0, 2, 5]:
		before_each()
		assert_true(_preview(shooter, 0, Terrain.Kind.BUILDING)["in_cover"], "стрілець %d" % shooter)


func test_infantry_on_rubble_or_open_ground_is_not_in_cover() -> void:
	assert_false(_preview(5, 0, Terrain.Kind.RUBBLE)["in_cover"])
	before_each()
	assert_false(_preview(5, 0, Terrain.Kind.FIELD)["in_cover"])


func test_vehicle_in_building_is_never_in_cover() -> void:
	assert_false(_preview(0, 5, Terrain.Kind.BUILDING)["in_cover"])
	before_each()
	assert_false(_preview(5, 2, Terrain.Kind.BUILDING)["in_cover"])
