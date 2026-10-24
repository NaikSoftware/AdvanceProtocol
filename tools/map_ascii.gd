class_name MapAscii
extends RefCounted
## ASCII-формат карт → MapData. Карту легше вичитати очима як текст, ніж як .tres;
## конвертер лише розбирає текст, правил не знає. Формат і легенда — у tools/maps/README.md.

const _CHARS: Dictionary = {
	"=": Terrain.Kind.ROAD, ".": Terrain.Kind.FIELD, "T": Terrain.Kind.FOREST,
	"^": Terrain.Kind.HILL, "~": Terrain.Kind.MARSH, "w": Terrain.Kind.WATER,
	"B": Terrain.Kind.BUILDING, "r": Terrain.Kind.RUBBLE, "H": Terrain.Kind.BRIDGE,
	"x": Terrain.Kind.BRIDGE_DESTROYED,
}
## Секції-сітки: у них '#' не починає коментар посеред рядка (у кільці це заглушка дошки).
const _GRIDS: Array[String] = ["tiles", "surface", "outer", "outer_surface"]
## Заглушка на місці дошки в сітках кільця: дошка пишеться один раз, у tiles:.
const _HOLE: String = "#"


## null + push_error на будь-яку помилку формату: краще зупинити збірку, ніж зберегти криву карту.
static func parse(text: String) -> MapData:
	var m := MapData.new()
	var grids: Dictionary = {}  # секція → Array рядків
	var spawns0: Array[Array] = []
	var section: String = ""
	for raw in text.split("\n"):
		# Коментар `# ...` дозволений поза сітками; у сітці — лише цілим рядком.
		var line: String = raw.strip_edges(false, true).trim_suffix("\r")
		if not _GRIDS.has(section):
			line = line.split("#")[0].strip_edges()
			if line.is_empty():
				continue
		elif line.begins_with("#") or line.is_empty():
			continue
		if line.ends_with(":") and (_GRIDS.has(line.trim_suffix(":")) or line == "spawns:"):
			section = line.trim_suffix(":")
			grids[section] = []
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
				"outer_margin":
					if not val.is_valid_int() or int(val) < 0:
						return _fail("outer_margin — ціле >= 0, а не " + val)
					m.outer_margin = int(val)
				_:
					return _fail("невідомий ключ: " + kv[0])
		elif section != "spawns":
			grids[section].append(line)
		else:
			var p: PackedStringArray = line.split(" ", false)
			if p.size() != 4 or not (p[0] + p[1] + p[2] + p[3]).is_valid_int():
				return _fail("спавн має вигляд '<type_id> <x> <y> <facing>': " + line)
			spawns0.append([int(p[0]), int(p[1]), int(p[2]), int(p[3])])
	var rows: Array = grids.get("tiles", [])
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
	# Необов'язкова сітка підтипів: та сама форма, цифра на клітинку, '.' = 0.
	if grids.has("surface"):
		var surf_rows: Array = grids["surface"]
		if surf_rows.size() != m.height:
			return _fail("surface: %d рядків замість %d" % [surf_rows.size(), m.height])
		for y in m.height:
			if surf_rows[y].length() != m.width:
				return _fail("surface: рваний рядок %d" % y)
			for c in surf_rows[y]:
				var v: int = _subtype(c, m.tiles[m.surface.size()], "surface", y)
				if v < 0:
					return null
				m.surface.append(v)
	if not _parse_outer(m, grids):
		return null
	for s in spawns0:
		var pos := Vector2i(s[1], s[2])
		if pos.x < 0 or pos.x >= m.width or pos.y < 0 or pos.y >= m.height or s[3] < 0 or s[3] > 7:
			return _fail("спавн поза картою або facing не 0..7: %s" % [s])
		m.spawns.append({"type_id": s[0], "owner": 0, "pos": pos, "facing": s[3]})
		# Гравець 1 — дзеркало гравця 0 через центр; розворот на 180° = +4 до 8-напрямного facing.
		m.spawns.append({"type_id": s[0], "owner": 1,
			"pos": Vector2i(m.width - 1 - pos.x, m.height - 1 - pos.y), "facing": (s[3] + 4) % 8})
	return m


## Кільце: сітка (w+2m)×(h+2m) тією ж легендою, дошка в ній — суцільний блок '#'.
## Відступ без сітки чи сітка без відступу — помилка: інакше край світу тихо лишиться видимим.
static func _parse_outer(m: MapData, grids: Dictionary) -> bool:
	var mg: int = m.outer_margin
	if (mg > 0) != grids.has("outer"):
		return _bad("outer_margin=%d і секція outer: мають бути разом" % mg)
	if grids.has("outer_surface") and not grids.has("outer"):
		return _bad("outer_surface: без outer:")
	if mg == 0:
		return true
	var ow: int = m.width + 2 * mg
	var oh: int = m.height + 2 * mg
	for sec: String in ["outer", "outer_surface"]:
		if not grids.has(sec):
			continue
		var rows: Array = grids[sec]
		if rows.size() != oh:
			return _bad("%s: %d рядків замість %d" % [sec, rows.size(), oh])
		for y in oh:
			if rows[y].length() != ow:
				return _bad("%s: рваний рядок %d: %d замість %d" % [sec, y, rows[y].length(), ow])
			for x in ow:
				var c: String = rows[y][x]
				var hole: bool = x >= mg and x < mg + m.width and y >= mg and y < mg + m.height
				if hole != (c == _HOLE):
					return _bad("%s: '#' — рівно на місці дошки, рядок %d, стовпець %d" % [sec, y, x])
				if sec == "outer":
					if not hole and not _CHARS.has(c):
						return _bad("outer: невідомий символ '%s' у рядку %d" % [c, y])
					m.outer_tiles.append(MapData.OUTER_HOLE if hole else _CHARS[c])
				elif hole:
					m.outer_surface.append(MapData.OUTER_HOLE)
				else:
					var v: int = _subtype(c, m.outer_tiles[y * ow + x], sec, y)
					if v < 0:
						return false
					m.outer_surface.append(v)
	return true


## Цифра підтипу для виду kind або -1 (з push_error), якщо символ чи значення не годяться.
static func _subtype(c: String, kind: int, sec: String, y: int) -> int:
	if c != "." and not c.is_valid_int():
		_fail("%s: '%s' у рядку %d — лише цифра або '.'" % [sec, c, y])
		return -1
	var v: int = 0 if c == "." else int(c)
	if v >= MapData.surface_variants(kind):
		_fail("%s: підтип %d у рядку %d — у виду %s їх лише %d"
			% [sec, v, y, Terrain.Kind.keys()[kind], MapData.surface_variants(kind)])
		return -1
	return v


static func _fail(why: String) -> MapData:
	push_error("MapAscii: " + why)
	return null


static func _bad(why: String) -> bool:
	_fail(why)
	return false
