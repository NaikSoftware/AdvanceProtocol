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
			"ap_before_retaliation": u.ap_before_retaliation,
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
		"objective_hold_target": state.objective_hold_target,
		"units": units, "mines": mines, "objectives": objectives,
		"vision": vision,
		"damage_dealt": state.damage_dealt.duplicate(),
	}

static func from_dict(data: Dictionary) -> BattleState:
	if not _num(data, "version") or int(data["version"]) != VERSION:
		return null
	# Файл збереження — межа довіри: зіпсований чи обрізаний, він інакше відкривався б
	# і падав пізніше, далеко від причини (check_elimination(), туман, get_type()).
	# Усе, що читається нижче, перевіряється тут, а не по дорозі, щоб відмова була
	# тихою і цілою: або стан повністю, або null.
	if not _is_valid(data):
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
	state.objective_hold_target = int(data["objective_hold_target"])

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
		# Старі збереження поля не мають — там ніхто й не чекає повернення AP.
		u.ap_before_retaliation = int(u_data.get("ap_before_retaliation", -1))
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

	# Збереження до появи лічильника поля не мають — рахуємо з нуля, а не відмовляємо.
	state.damage_dealt.clear()
	var dealt: Array = data.get("damage_dealt", [])
	for p in state.player_count:
		state.damage_dealt.append(int(dealt[p]) if p < dealt.size() else 0)

	return state

static func _is_valid(data: Dictionary) -> bool:
	## Кожна частина збереження мусить погоджуватися з рештою: розміри на гравця —
	## з player_count, сітки — з width*height, індекси — з діапазонами. JSON дає числа
	## як float, тому числом вважається і TYPE_INT, і TYPE_FLOAT.
	if not (_dict(data, "board") and _num(data, "player_count") and _num(data, "turn_number")
			and _num(data, "seed_value") and _num(data, "winner") and _num(data, "next_unit_id")
			and _num(data, "objective_hold_target")):
		return false
	if not (data.has("rng_state") and typeof(data["rng_state"]) == TYPE_STRING
			and (data["rng_state"] as String).is_valid_int()):
		return false
	var pc: int = int(data["player_count"])
	if pc < 1 or not _in(data, "active_player", 0, pc - 1):
		return false
	var winner: int = int(data["winner"])
	if winner != BattleState.NO_WINNER and winner != BattleState.DRAW and (winner < 0 or winner >= pc):
		return false

	var board: Dictionary = data["board"]
	if not (_num(board, "width") and _num(board, "height")
			and _in(board, "ground_state", 0, Terrain.GroundState.size() - 1)):
		return false
	var w: int = int(board["width"])
	var h: int = int(board["height"])
	if w < 1 or h < 1 or not _nums(board, "tiles", w * h, 0, Terrain.Kind.size() - 1):
		return false

	if not _bools(data, "eliminated", pc):
		return false
	if data.has("damage_dealt") and not _nums(data, "damage_dealt", pc):
		return false  # відсутність допустима (старі збереження), неправильний розмір — ні

	if not _arr(data, "vision", pc):
		return false
	for v in (data["vision"] as Array):
		if typeof(v) != TYPE_DICTIONARY or not _nums(v, "visible", w * h) or not _nums(v, "seen", w * h):
			return false

	if not _arr(data, "units"):
		return false
	# id — ключ словника units (дублікат мовчки затер би юніт), тайл — одного живого
	# (unit_at() бачив би лише першого), а next_unit_id має бути вище за всі id, інакше
	# наступний add_unit() видав би вже зайнятий.
	var ids: Dictionary = {}
	var living_at: Dictionary = {}
	for u in (data["units"] as Array):
		if typeof(u) != TYPE_DICTIONARY:
			return false
		if not (_num(u, "id") and _in(u, "type_id", 0, UnitTypes.TYPES.size() - 1)
				and _in(u, "owner", 0, pc - 1) and _in(u, "x", 0, w - 1) and _in(u, "y", 0, h - 1)
				and _in(u, "facing", 0, 7) and _num(u, "hp") and _num(u, "ap")
				and _num(u, "drones_left") and _bool(u, "has_fired")):
			return false
		if u.has("ap_before_retaliation") and not _num(u, "ap_before_retaliation"):
			return false
		var id: int = int(u["id"])
		if ids.has(id) or id >= int(data["next_unit_id"]):
			return false
		ids[id] = true
		if int(u["hp"]) > 0:
			var pos := Vector2i(int(u["x"]), int(u["y"]))
			if living_at.has(pos):
				return false
			living_at[pos] = true

	if not _arr(data, "mines"):
		return false
	for m in (data["mines"] as Array):
		if typeof(m) != TYPE_DICTIONARY or not (_in(m, "x", 0, w - 1) and _in(m, "y", 0, h - 1)
				and _in(m, "owner", 0, pc - 1) and _bools(m, "known_to", pc)):
			return false

	if not _arr(data, "objectives"):
		return false
	for o in (data["objectives"] as Array):
		# −1 — нейтральна ціль.
		if typeof(o) != TYPE_DICTIONARY or not (_in(o, "x", 0, w - 1) and _in(o, "y", 0, h - 1)
				and _in(o, "owner", -1, pc - 1) and _bool(o, "intact") and _bools(o, "seen_by", pc)):
			return false
	return true

static func _num(d: Dictionary, key: String) -> bool:
	return d.has(key) and (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT)

static func _in(d: Dictionary, key: String, lo: int, hi: int) -> bool:
	return _num(d, key) and int(d[key]) >= lo and int(d[key]) <= hi

static func _bool(d: Dictionary, key: String) -> bool:
	return d.has(key) and typeof(d[key]) == TYPE_BOOL

static func _dict(d: Dictionary, key: String) -> bool:
	return d.has(key) and typeof(d[key]) == TYPE_DICTIONARY

static func _arr(d: Dictionary, key: String, size: int = -1) -> bool:
	return d.has(key) and typeof(d[key]) == TYPE_ARRAY and (size < 0 or (d[key] as Array).size() == size)

static func _nums(d: Dictionary, key: String, size: int, lo: int = -9223372036854775807, hi: int = 9223372036854775807) -> bool:
	if not _arr(d, key, size):
		return false
	for x in (d[key] as Array):
		if (typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT) or int(x) < lo or int(x) > hi:
			return false
	return true

static func _bools(d: Dictionary, key: String, size: int) -> bool:
	if not _arr(d, key, size):
		return false
	for x in (d[key] as Array):
		if typeof(x) != TYPE_BOOL:
			return false
	return true

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
