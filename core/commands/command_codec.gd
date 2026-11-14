class_name CommandCodec
## Команда <-> словник для збереження журналу ходів. Лише дані, жодних вузлів.


static func to_dict(c: Command) -> Dictionary:
	if c is MoveCommand:
		return {"kind": "move", "unit_id": c.unit_id, "x": c.target.x, "y": c.target.y}
	if c is TurnCommand:
		return {"kind": "turn", "unit_id": c.unit_id, "x": c.target.x, "y": c.target.y}
	if c is FireCommand:
		return {"kind": "fire", "unit_id": c.unit_id, "target_id": c.target_id}
	if c is DroneCommand:
		return {"kind": "drone", "unit_id": c.unit_id, "target_id": c.target_id}
	if c is EngineerCommand:
		return {"kind": "engineer", "unit_id": c.unit_id, "action": c.action,
			"x": c.target_pos.x, "y": c.target_pos.y}
	if c is EndTurnCommand:
		return {"kind": "end_turn"}
	if c is ConcedeCommand:
		return {"kind": "concede"}
	return {}


## Повертає null для невідомого виду, відсутнього чи не-цілого поля.
static func from_dict(d: Dictionary) -> Command:
	match d.get("kind"):
		"move":
			if _ints(d, ["unit_id", "x", "y"]):
				return MoveCommand.create(int(d["unit_id"]), Vector2i(int(d["x"]), int(d["y"])))
		"turn":
			if _ints(d, ["unit_id", "x", "y"]):
				return TurnCommand.create(int(d["unit_id"]), Vector2i(int(d["x"]), int(d["y"])))
		"fire":
			if _ints(d, ["unit_id", "target_id"]):
				return FireCommand.create(int(d["unit_id"]), int(d["target_id"]))
		"drone":
			if _ints(d, ["unit_id", "target_id"]):
				return DroneCommand.create(int(d["unit_id"]), int(d["target_id"]))
		"engineer":
			if _ints(d, ["unit_id", "action", "x", "y"]) \
					and int(d["action"]) in EngineerCommand.Action.values():
				return EngineerCommand.create(int(d["unit_id"]), int(d["action"]),
					Vector2i(int(d["x"]), int(d["y"])))
		"end_turn":
			return EndTurnCommand.create()
		"concede":
			return ConcedeCommand.create()
	return null


# JSON віддає цілі як float, тож цілим вважаємо і float без дробової частини.
static func _ints(d: Dictionary, keys: Array) -> bool:
	for k in keys:
		var v: Variant = d.get(k)
		if not (v is int or (v is float and v == floorf(v))):
			return false
	return true
