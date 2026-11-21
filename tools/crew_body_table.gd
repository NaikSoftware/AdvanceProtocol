extends SceneTree
## Складає таблицю дозволених місць тіл розрахунку гармати (див. crew_body_legal.gd).
##   $GODOT --headless --path . -s tools/crew_body_table.gd -- table      # перезаписує body_legal рядків 9 і 10 у _SPECS і _SET_SPECS
##   $GODOT --headless --path . -s tools/crew_body_table.gd -- scan 9 1 [мін. напрямів, типово 4] [крок, типово 0,04]   # сітка кандидатів типу 9 набору 1
## `table` — єдина команда, що оновлює таблицю (її ж називає тест `test_the_stored_crew_body_table_is_current`):
## друкує маски й підставляє їх у `game/battle/unit_silhouettes.gd`. `scan` допомагає вибрати `body_spots`.
const SPECS_PATH: String = "res://game/battle/unit_silhouettes.gd"

const Legal := preload("res://tools/crew_body_legal.gd")


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() > 0 and a[0] == "scan":
		_scan(int(a[1]), int(a[2]) if a.size() > 2 else 0, int(a[3]) if a.size() > 3 else 4, float(a[4]) if a.size() > 4 else 0.04)
	else:
		var source: String = FileAccess.get_file_as_string(SPECS_PATH)
		for set_id in UnitSilhouettes.SET_COUNT:
			for id: int in [9, 10]:
				# набір без власної моделі гармати бере рядок набору 0: його таблиця вже складена
				if UnitSilhouettes._resolved_set(id, set_id) != set_id:
					continue
				var masks: PackedInt32Array = Legal.legal_masks(id, set_id)
				print("TABLE set %d type %d body_legal: %s" % [set_id, id, Array(masks)])
				var rewritten: String = _with_masks(source, id, set_id, masks)
				if rewritten.is_empty():
					# Рядок не знайдено: файл не чіпаємо, і команда падає, а не тихо лишає стару таблицю.
					push_error("crew_body_table: у рядках набору %d нема типу %d з body_legal" % [set_id, id])
					quit(1)
					return
				source = rewritten
				var spots: Array = UnitSilhouettes.spec(id, set_id).get("body_spots", [])
				for facing in 8:
					var legal: Array[int] = []
					for i in spots.size():
						if masks[facing] & (1 << i) != 0:
							legal.append(i)
					print("  facing %d legal %s" % [facing, legal])
		var out := FileAccess.open(SPECS_PATH, FileAccess.WRITE)
		out.store_string(source)
		out.close()
	quit()


## Рядок типу `id` набору `set_id` (`_SPECS` — закінчується коментарем `# <id> `, `_SET_SPECS` — починається `\t\t<id>: {`)
## з новим масивом `body_legal`; порожній рядок — рядка нема.
static func _with_masks(source: String, id: int, set_id: int, masks: PackedInt32Array) -> String:
	var lines: PackedStringArray = source.split("\n")
	var matched: bool = false
	var in_sets: bool = false
	var current: int = -1
	var head := RegEx.create_from_string("^\\t(\\d): \\{$")
	for i in lines.size():
		if lines[i].begins_with("const _SET_SPECS"):
			in_sets = true
		var m: RegExMatch = head.search(lines[i]) if in_sets else null
		if m != null:
			current = int(m.get_string(1))
		var hit: bool = false
		if set_id == 0:
			hit = not in_sets and lines[i].contains("},  # %d " % id)
		else:
			hit = in_sets and current == set_id and lines[i].begins_with("\t\t%d: {" % id)
		if hit and lines[i].contains("\"body_legal\": ["):
			var from: int = lines[i].find("\"body_legal\": [")
			var to: int = lines[i].find("]", from)
			lines[i] = lines[i].substr(0, from) + "\"body_legal\": " + str(Array(masks)) + lines[i].substr(to + 1)
			matched = true
	if not matched:
		return ""
	return "\n".join(lines)


func _scan(id: int, set_id: int = 0, min_facings: int = 4, step: float = 0.04) -> void:
	var per_facing: Array = []
	for facing in 8:
		var tilts: Array = []
		for tx: float in [-Legal.TILT_DEG, Legal.TILT_DEG]:
			for tz: float in [-Legal.TILT_DEG, Legal.TILT_DEG]:
				tilts.append(Legal.ground_index(Legal.wreck_tris(id, set_id, facing, Vector2(tx, tz))))
		var plain: PackedVector3Array = Legal.wreck_tris(id, set_id, facing, Vector2.ZERO)
		tilts.append(Legal.ground_index(plain))
		var seen: PackedVector3Array = plain + Legal.flame_tris(id, set_id, facing)
		per_facing.append([tilts, [Legal.silhouette(seen, IsoCameraRig.PITCH_NEAR_DEG), Legal.silhouette(seen, IsoCameraRig.PITCH_FAR_DEG)]])
	var rows: Array = []
	var reach: int = roundi(0.36 / step)
	# грубіша сітка — чотири повороти, дрібніша — шість: на ній шукають місця для напрямів, де їх бракує
	var headings: Array[float] = [0.0, 45.0, 90.0, 135.0]
	if step < 0.04:
		headings = [0.0, 30.0, 60.0, 90.0, 120.0, 150.0]
	for xi in range(-reach, reach + 1):
		for zi in range(-reach, reach + 1):
			for h: float in headings:
				var spot := Vector3(float(xi) * step, float(zi) * step, h)
				var n: int = 0
				var which: String = ""
				for facing in 8:
					var rep: Dictionary = Legal.spot_report(spot, facing, per_facing[facing][0], per_facing[facing][1])
					if rep.tile and rep.clear and rep.cover <= Legal.TABLE_COVER:
						n += 1
						which += str(facing)
				if n >= min_facings:
					rows.append([n, spot, which])
	rows.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	for r: Array in rows.slice(0, 200):
		print("SCAN %d  spot %s  facings %s" % [r[0], r[1], r[2]])
