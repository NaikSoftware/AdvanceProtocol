class_name BattleSerializer
extends RefCounted
## Стан ↔ Dictionary. Використовується і для збереження матчу, і для реплеїв.
##
## Кожне поле пишеться і читається явно — жодного inst_to_dict, жодної рефлексії.
## Поле, додане до BattleState пізніше й забуте тут, мусить провалити тест, а не
## тихо зникнути зі збереження.
##
## rng.state зберігається окремо від seed_value: відновлення з сіда перекрутило б
## генератор назад і змусило гру перекинути вже витрачені числа заново. JSON не має
## цілого типу — усе повертається як float, тож кожне ціле поле явно проганяється
## через int() на зворотному шляху; це особливо важливо для rng.state, великого
## цілого, яке float може округлити.

const VERSION: int = 1

static func to_dict(state: BattleState) -> Dictionary:
	var units: Array = []
	for id in state.units:
		var u: Unit = state.units[id]
		units.append({
			"id": u.id, "type_id": u.type_id, "owner": u.owner,
			"x": u.pos.x, "y": u.pos.y, "facing": u.facing,
			"hp": u.hp, "ap": u.ap, "drones_left": u.drones_left, "has_fired": u.has_fired,
		})
	var mines: Array = []
	for m in state.mines:
		mines.append({"x": m.pos.x, "y": m.pos.y, "owner": m.owner, "known_to": m.known_to.duplicate()})
	var objectives: Array = []
	for o in state.objectives:
		objectives.append({"x": o.pos.x, "y": o.pos.y, "owner": o.owner, "intact": o.intact, "seen_by": o.seen_by.duplicate()})
	var vision: Array = []
	for v in state.vision:
		vision.append({"visible": Array(v.visible), "seen": Array(v.seen)})
	var veterancy: Array = []
	for vet in state.veterancy:
		veterancy.append({"xp": vet.xp.duplicate(), "level": vet.level.duplicate()})
	return {
		"version": VERSION,
		"board": {
			"width": state.board.width, "height": state.board.height,
			"ground_state": state.board.ground_state, "tiles": Array(state.board.tiles),
		},
		"player_count": state.player_count,
		"active_player": state.active_player,
		"turn_number": state.turn_number,
		"seed_value": state.seed_value,
		"rng_state": str(state.rng.state),
		"winner": state.winner,
		"eliminated": state.eliminated.duplicate(),
		"next_unit_id": state._next_unit_id,
		"units": units, "mines": mines, "objectives": objectives,
		"vision": vision, "veterancy": veterancy,
	}

static func from_dict(data: Dictionary) -> BattleState:
	if int(data.get("version", -1)) != VERSION:
		return null

	var board_data: Dictionary = data["board"]
	var board := Board.new()
	board.width = int(board_data["width"])
	board.height = int(board_data["height"])
	board.ground_state = int(board_data["ground_state"])
	board.tiles = PackedInt32Array(board_data["tiles"])

	var state := BattleState.new()
	state.board = board
	state.player_count = int(data["player_count"])
	state.active_player = int(data["active_player"])
	state.turn_number = int(data["turn_number"])
	state.seed_value = int(data["seed_value"])
	state.rng = RandomNumberGenerator.new()
	state.rng.state = int(data["rng_state"])
	state.winner = int(data["winner"])

	state.eliminated.clear()
	for e in (data["eliminated"] as Array):
		state.eliminated.append(bool(e))

	state._next_unit_id = int(data["next_unit_id"])

	state.units.clear()
	for u_data in (data["units"] as Array):
		var u := Unit.new()
		u.id = int(u_data["id"])
		u.type_id = int(u_data["type_id"])
		u.owner = int(u_data["owner"])
		u.pos = Vector2i(int(u_data["x"]), int(u_data["y"]))
		u.facing = int(u_data["facing"])
		u.hp = int(u_data["hp"])
		u.ap = int(u_data["ap"])
		u.drones_left = int(u_data["drones_left"])
		u.has_fired = bool(u_data["has_fired"])
		state.units[u.id] = u

	state.mines.clear()
	for m_data in (data["mines"] as Array):
		var pos := Vector2i(int(m_data["x"]), int(m_data["y"]))
		var mine := Mines.Mine.new(pos, int(m_data["owner"]), state.player_count)
		mine.known_to.clear()
		for k in (m_data["known_to"] as Array):
			mine.known_to.append(bool(k))
		state.mines.append(mine)

	state.objectives.clear()
	for o_data in (data["objectives"] as Array):
		var pos := Vector2i(int(o_data["x"]), int(o_data["y"]))
		var obj := Objectives.Objective.new(pos, int(o_data["owner"]), state.player_count)
		obj.intact = bool(o_data["intact"])
		obj.seen_by.clear()
		for sb in (o_data["seen_by"] as Array):
			obj.seen_by.append(bool(sb))
		state.objectives.append(obj)

	state.vision.clear()
	for v_data in (data["vision"] as Array):
		var v := Vision.create(state.board.width, state.board.height)
		v.visible = PackedByteArray(v_data["visible"])
		v.seen = PackedByteArray(v_data["seen"])
		state.vision.append(v)

	state.veterancy.clear()
	for vet_data in (data["veterancy"] as Array):
		var vet := Veterancy.new()
		vet.xp.clear()
		for x in (vet_data["xp"] as Array):
			vet.xp.append(int(x))
		vet.level.clear()
		for l in (vet_data["level"] as Array):
			vet.level.append(int(l))
		state.veterancy.append(vet)

	return state

static func save_to(state: BattleState, path: String) -> Error:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(state)))
	f.close()
	return OK

static func load_from(path: String) -> BattleState:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
