extends GutTest
## Правила розкидання лісу (`ForestScatter.plan`): відтворюваність, локальність проламу і
## частки осінніх крон. Бібліотека — розміри вузлів без самих мешів: план від мешів не залежить.

const LIB: Dictionary = {
	"Pine_A": {"h": 1.6, "half": 0.35}, "Pine_B": {"h": 1.7, "half": 0.35},
	"Spruce_A": {"h": 1.6, "half": 0.3}, "Spruce_B": {"h": 1.5, "half": 0.3},
	"Birch_A": {"h": 1.2, "half": 0.3}, "Oak_A": {"h": 1.3, "half": 0.4},
	"Shrub_Hazel": {"h": 0.45, "half": 0.25}, "Shrub_Thorn": {"h": 0.3, "half": 0.2},
	"Hedge_Spruce": {"h": 0.45, "half": 0.6}, "Hedge_Shrub": {"h": 0.45, "half": 0.6},
	"Log_A": {"h": 0.05, "half": 0.4}, "Log_B": {"h": 0.05, "half": 0.3}, "Litter_A": {"h": 0.02, "half": 0.6},
	"Hero_Oak": {"h": 1.5, "half": 1.0},
}


func _cells(w: int, h: int) -> Dictionary:
	var cells: Dictionary = {}
	for y in h:
		for x in w:
			cells[Vector2i(x, y)] = true
	return cells


func _plan(cells: Dictionary, broken: Dictionary, season: String, seed: int = 7) -> Array[Dictionary]:
	return ForestScatter.plan(cells, func(_p: Vector2) -> String: return "mixed", broken, season, seed, LIB)


## Запис як рядок: однакові дерева — однакові рядки, незалежно від порядку.
func _keys(plan: Array[Dictionary], skip_near: Vector2 = Vector2(INF, INF), radius: float = 0.0) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in plan:
		if (e["pos"] as Vector2).distance_to(skip_near) <= radius:
			continue
		out.append("%s %s %s %s" % [e["node"], e["xf"], e["rgb"], e["turn"]])
	out.sort()
	return out


func test_same_input_same_forest() -> void:
	var cells := _cells(10, 8)
	var broken: Dictionary = {Vector2i(4, 4): true, Vector2i(4, 3): true}
	for season: String in ["late", "summer", "early"]:
		var a := _plan(cells, broken, season)
		assert_gt(a.size(), 100, "%s: ліс не порожній" % season)
		assert_eq(_keys(a), _keys(_plan(cells, broken, season)), "%s: той самий вхід — той самий ліс" % season)
	assert_ne(_keys(_plan(cells, broken, "summer", 7)), _keys(_plan(cells, broken, "summer", 8)), "інше зерно — інший ліс")


func test_break_changes_only_nearby_trees() -> void:
	# Проломи свої в кожного гравця: ліс далі від нового проламу мусить лишитись тим самим,
	# інакше різниця видала б, де пройшов ворог. Радіус — LANE_NEAR (крони біля просіки
	# вужчі) плюс найширша крона.
	var cells := _cells(14, 10)
	var base: Dictionary = {Vector2i(3, 5): true}
	var more: Dictionary = base.duplicate()
	var c := Vector2i(10, 4)
	more[c] = true
	var radius: float = ForestScatter.LANE_NEAR + 1.0
	for season: String in ["late", "summer", "early"]:
		var a := _keys(_plan(cells, base, season), Vector2(c), radius)
		var b := _keys(_plan(cells, more, season), Vector2(c), radius)
		assert_eq(a, b, "%s: пролам у %s змінив дерева далі %.1f тайла" % [season, c, radius])


func test_autumn_shares() -> void:
	var counts: Dictionary = {"orange": 0, "green": 0, "": 0}
	for e: Dictionary in _plan(_cells(24, 20), {}, "early"):
		var species: String = String(e["node"]).get_slice("_", 0)
		if species in ["Birch", "Oak"]:
			counts[e["turn"]] += 1
	var total: float = float(counts["orange"] + counts["green"] + counts[""])
	assert_gt(total, 200.0, "листяних досить для частки")
	assert_almost_eq(counts["orange"] / total, ForestScatter.TURN_ORANGE_SHARE, 0.1, "частка жовто-помаранчевих")
	assert_almost_eq(counts["green"] / total, ForestScatter.TURN_GREEN_SHARE, 0.1, "частка ще зелених")
	for e: Dictionary in _plan(_cells(6, 6), {}, "summer"):
		assert_eq(e["turn"], "", "влітку осені немає")


func test_fixed_trees_get_every_autumn_tone() -> void:
	# П'ять поодиноких дерев за частками 22 / 58 / 20 %: одне жовто-помаранчеве, три оливкові,
	# одне зелене.
	var fixed: Array = []
	for i in 5:
		fixed.append(["Hero_Oak", Vector2(30 + 3 * i, 2)])
	var counts: Dictionary = {"orange": 0, "green": 0, "": 0}
	for e: Dictionary in ForestScatter.plan(_cells(4, 4), func(_p: Vector2) -> String: return "mixed", {}, "early", 7, LIB, fixed):
		if e["node"] == "Hero_Oak":
			counts[e["turn"]] += 1
	assert_eq(counts, {"orange": 1, "green": 1, "": 3}, "частки осені серед поставлених вручну")


func test_species_follow_weights() -> void:
	# Пізня осінь: ~70 % листяних (голих і з бурим листям) у верхньому ярусі (намет і крайовий ряд — дерева з
	# масштабом ≥ 0,85; підріст і крони біля просіки менші).
	var broad: int = 0
	var all: int = 0
	for e: Dictionary in _plan(_cells(24, 20), {}, "late"):
		var species: String = String(e["node"]).get_slice("_", 0)
		if species in ["Pine", "Spruce", "Birch", "Oak"] and (e["xf"] as Transform3D).basis.get_scale().y >= 0.85:
			all += 1
			if species in ["Birch", "Oak"]:
				broad += 1
	assert_gt(all, 300, "дерев досить для частки")
	assert_almost_eq(float(broad) / all, 0.7, 0.1, "частка листяних у верхньому ярусі пізньої осені")
