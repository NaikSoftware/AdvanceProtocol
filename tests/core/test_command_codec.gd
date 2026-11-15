extends GutTest


func _samples() -> Array[Command]:
	return [
		MoveCommand.create(3, Vector2i(4, 5)),
		TurnCommand.create(3, Vector2i(1, 2)),
		FireCommand.create(3, 7),
		DroneCommand.create(3, 8),
		EngineerCommand.create(2, EngineerCommand.Action.REPAIR_UNIT, Vector2i(6, 1)),
		EndTurnCommand.create(),
		ConcedeCommand.create(),
	]


func _same(a: Command, b: Command) -> bool:
	if b == null or a.get_script() != b.get_script():
		return false
	for p in a.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and a.get(p["name"]) != b.get(p["name"]):
			return false
	return true


func test_every_command_round_trips() -> void:
	for c in _samples():
		assert_true(_same(c, CommandCodec.from_dict(CommandCodec.to_dict(c))), str(c.get_script().get_global_name()))


func test_round_trip_survives_json() -> void:
	for c in _samples():
		var d: Dictionary = JSON.parse_string(JSON.stringify(CommandCodec.to_dict(c)))
		assert_true(_same(c, CommandCodec.from_dict(d)), str(c.get_script().get_global_name()))


func test_unknown_kind_is_null() -> void:
	assert_null(CommandCodec.from_dict({"kind": "nope"}))
	assert_null(CommandCodec.from_dict({}))


func test_missing_field_is_null() -> void:
	assert_null(CommandCodec.from_dict({"kind": "move", "unit_id": 1, "x": 2}))
	assert_null(CommandCodec.from_dict({"kind": "fire", "unit_id": 1, "target_id": "a"}))
	assert_null(CommandCodec.from_dict({"kind": "fire", "unit_id": 1, "target_id": 1.5}))


func test_engineer_action_out_of_enum_is_null() -> void:
	for a in [-1, 5]:
		assert_null(CommandCodec.from_dict({"kind": "engineer", "unit_id": 1, "action": a, "x": 0, "y": 0}))
