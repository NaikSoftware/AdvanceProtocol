class_name MapAscii
extends RefCounted
## ASCII-формат карт → MapData. Карту легше вичитати очима як текст, ніж як .tres;
## конвертер лише розбирає текст, правил не знає. Формат — у tools/maps/.

const _CHARS: Dictionary = {
	"=": Terrain.Kind.ROAD, ".": Terrain.Kind.FIELD, "T": Terrain.Kind.FOREST,
	"^": Terrain.Kind.HILL, "~": Terrain.Kind.MARSH, "w": Terrain.Kind.WATER,
	"B": Terrain.Kind.BUILDING, "r": Terrain.Kind.RUBBLE, "H": Terrain.Kind.BRIDGE,
	"x": Terrain.Kind.BRIDGE_DESTROYED,
}


## null + push_error на будь-яку помилку формату: краще зупинити збірку, ніж зберегти криву карту.
static func parse(text: String) -> MapData:
	var m := MapData.new()
	var rows: Array[String] = []
	var spawns0: Array[Array] = []
	var section: String = ""
	for raw in text.split("\n"):
		# Коментар `# ...` дозволений лише поза ґратками тайлів (там '#' не символ, але й не потрібен).
		var line: String = raw.strip_edges(false, true).trim_suffix("\r")
		if section != "tiles":
			line = line.split("#")[0].strip_edges()
			if line.is_empty():
				continue
		elif line.begins_with("#") or line.is_empty():
			continue
		if line == "tiles:" or line == "spawns:":
			section = line.trim_suffix(":")
		elif section == "":
			var kv: PackedStringArray = line.split("=", true, 1)
			if kv.size() != 2:
				return _fail("рядок заголовка без '=': " + line)
			var val: String = kv[1].strip_edges()
			match kv[0].strip_edges():
				"name_key":
					m.name_key = val
				"ground":
					if not Terrain.GroundState.has(val):
						return _fail("невідомий ґрунт: " + val)
					m.ground_state = Terrain.GroundState[val]
				_:
					return _fail("невідомий ключ: " + kv[0])
		elif section == "tiles":
			rows.append(line)
		else:
			var p: PackedStringArray = line.split(" ", false)
			if p.size() != 4 or not (p[0] + p[1] + p[2] + p[3]).is_valid_int():
				return _fail("спавн має вигляд '<type_id> <x> <y> <facing>': " + line)
			spawns0.append([int(p[0]), int(p[1]), int(p[2]), int(p[3])])
	if rows.is_empty():
		return _fail("порожня сітка тайлів")
	m.height = rows.size()
	m.width = rows[0].length()
	for y in m.height:
		if rows[y].length() != m.width:
			return _fail("рваний рядок %d: %d замість %d" % [y, rows[y].length(), m.width])
		for c in rows[y]:
			if not _CHARS.has(c):
				return _fail("невідомий символ '%s' у рядку %d" % [c, y])
			m.tiles.append(_CHARS[c])
	for s in spawns0:
		var pos := Vector2i(s[1], s[2])
		if pos.x < 0 or pos.x >= m.width or pos.y < 0 or pos.y >= m.height or s[3] < 0 or s[3] > 7:
			return _fail("спавн поза картою або facing не 0..7: %s" % [s])
		m.spawns.append({"type_id": s[0], "owner": 0, "pos": pos, "facing": s[3]})
		# Гравець 1 — дзеркало гравця 0 через центр; розворот на 180° = +4 до 8-напрямного facing.
		m.spawns.append({"type_id": s[0], "owner": 1,
			"pos": Vector2i(m.width - 1 - pos.x, m.height - 1 - pos.y), "facing": (s[3] + 4) % 8})
	return m


static func _fail(why: String) -> MapData:
	push_error("MapAscii: " + why)
	return null
