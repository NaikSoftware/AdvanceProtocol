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
			"ap_before_retaliation": u.ap_before_retaliation, "found_by": u.found_by,
		})
	var mines: Array = []
	for m in state.mines:
		mines.append({"x": m.pos.x, "y": m.pos.y, "owner": m.owner, "known_to": m.known_to.duplicate()})
	var wrecks: Array = []
	for w in state.wrecks:
		wrecks.append({"x": w.pos.x, "y": w.pos.y, "type_id": w.type_id, "facing": w.facing,
			"burns_out_at": w.burns_out_at})
	var broken_forest: Array = []
	for p: Vector2i in state.broken_forest:
		broken_forest.append({"x": p.x, "y": p.y})
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
		"units": units, "mines": mines, "wrecks": wrecks,
		# Лише правда: знання кожного гравця про просіки виводиться з неї та його seen
		# (BattleState.known_broken_map()), а seen і так зберігається нижче.
		"broken_forest": broken_forest,
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
		# Старі збереження укриття не знали — там ніхто нікого в будинку ще не знайшов.
		u.found_by = int(u_data.get("found_by", 0))
		state.units[u.id] = u

	state.mines.clear()
	for m_data in (data["mines"] as Array):
		var pos := Vector2i(int(m_data["x"]), int(m_data["y"]))
		var mine := Mines.Mine.new(pos, int(m_data["owner"]), state.player_count)
		mine.known_to.clear()
		for k in (m_data["known_to"] as Array):
			mine.known_to.append(bool(k))
		state.mines.append(mine)

	# Збереження до появи уламків поля не мають — уламків там і не було.
	state.wrecks.clear()
	for w_data in (data.get("wrecks", []) as Array):
		state.wrecks.append(Wrecks.Wreck.new(Vector2i(int(w_data["x"]), int(w_data["y"])),
			int(w_data["type_id"]), int(w_data.get("facing", 0)), int(w_data["burns_out_at"])))
	# Збереження до появи просік поля не мають — лісу там ніхто не валив.
	state.broken_forest.clear()
	for f_data in (data.get("broken_forest", []) as Array):
		state.broken_forest[Vector2i(int(f_data["x"]), int(f_data["y"]))] = true

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
			and _num(data, "seed_value") and _num(data, "winner") and _num(data, "next_unit_id")):
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
	var living_at: Dictionary = {}   # Vector2i -> type_id живого юніта
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
		if u.has("found_by") and not _num(u, "found_by"):
			return false
		var id: int = int(u["id"])
		if ids.has(id) or id >= int(data["next_unit_id"]):
			return false
		ids[id] = true
		if int(u["hp"]) > 0:
			var pos := Vector2i(int(u["x"]), int(u["y"]))
			if living_at.has(pos):
				return false
			living_at[pos] = int(u["type_id"])

	if not _arr(data, "mines"):
		return false
	for m in (data["mines"] as Array):
		if typeof(m) != TYPE_DICTIONARY or not (_in(m, "x", 0, w - 1) and _in(m, "y", 0, h - 1)
				and _in(m, "owner", 0, pc - 1) and _bools(m, "known_to", pc)):
			return false

	# §3.14: уламки лишає лише техніка, по одних на тайл, техніка на них не стоїть, а з
	# підірваним мостом вони падають у річку. Відсутність поля допустима (старі збереження).
	if data.has("wrecks") and not _arr(data, "wrecks"):
		return false
	var wreck_at: Dictionary = {}
	for wr in (data.get("wrecks", []) as Array):
		if typeof(wr) != TYPE_DICTIONARY or not (_in(wr, "x", 0, w - 1) and _in(wr, "y", 0, h - 1)
				and _in(wr, "type_id", 0, UnitTypes.TYPES.size() - 1) and _num(wr, "burns_out_at")):
			return false
		# Без напряму уламки з ранніх збережень дивляться на північ (0); з ним — лише 0..7.
		if wr.has("facing") and not _in(wr, "facing", 0, 7):
			return false
		var pos := Vector2i(int(wr["x"]), int(wr["y"]))
		if wreck_at.has(pos) or not _is_vehicle_type(int(wr["type_id"])):
			return false
		if living_at.has(pos) and _is_vehicle_type(living_at[pos]):
			return false
		if int((board["tiles"] as Array)[pos.y * w + pos.x]) == Terrain.Kind.BRIDGE_DESTROYED:
			return false
		wreck_at[pos] = true
	if data.has("broken_forest"):
		if not _arr(data, "broken_forest"):
			return false
		var tiles: Array = board["tiles"]
		for f in (data["broken_forest"] as Array):
			# Просіка буває лише в лісі: інакше Terrain.penalty() мовчки ігнорувала б її,
			# а вигляд валив би крони там, де їх ніколи не було.
			if typeof(f) != TYPE_DICTIONARY or not (_in(f, "x", 0, w - 1) and _in(f, "y", 0, h - 1)):
				return false
			if int(tiles[int(f["y"]) * w + int(f["x"])]) != Terrain.Kind.FOREST:
				return false

	return true

static func _is_vehicle_type(type_id: int) -> bool:
	return UnitTypes.is_vehicle(UnitTypes.get_type(type_id)["unit_class"])

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
