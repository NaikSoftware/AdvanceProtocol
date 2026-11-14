class_name HudDocking
extends RefCounted
## Правило стикування плит HUD до кутів екрана (spec §2): чисті функції над екранними
## прямокутниками, без вузлів. Прямокутники юнітів приходять із реальної проєкції
## видимих UnitView (UnitScreenBox), ціль — з прев'ю. Жодне правило гри тут не рахується:
## лише «де на екрані не закрити те, що гравцю треба бачити».

const SAFE_X: float = 24.0
const SAFE_BOTTOM: float = 12.0
## Під кнопкою паузи (вона закінчується на 56) і під чипом.
const TOP_RIGHT_Y: float = 64.0
const TOP_LEFT_Y: float = 56.0
const GAP: float = 8.0
const ROW_H: float = 48.0
const CLUSTER_W: float = 285.0
const END_TURN_W: float = 161.0
## Запас навколо юніта: вище 2 dp плита вже «торкається» напису HP.
const UNIT_MARGIN: float = 2.0
const TARGET_GROW: float = 8.0
const TARGET_GROW_TIGHT: float = 4.0

## Порядок варіантів кластера: a@8 → a@4 → b → c → d.
const CLUSTER_ORDER: Array[String] = ["a", "a4", "b", "c", "d"]


## Усі варіанти кластера «плита прев'ю + ряд дій». Ключ — назва з CLUSTER_ORDER.
static func cluster_rects(screen: Vector2, plate_h: float) -> Dictionary:
	var right_x: float = screen.x - SAFE_X - CLUSTER_W
	var row_br := Rect2(right_x, screen.y - SAFE_BOTTOM - ROW_H, CLUSTER_W, ROW_H)
	var plate_a := Rect2(right_x, row_br.position.y - GAP - plate_h, CLUSTER_W, plate_h)
	var plate_tr := Rect2(right_x, TOP_RIGHT_Y, CLUSTER_W, plate_h)
	var plate_tl := Rect2(SAFE_X, TOP_LEFT_Y, CLUSTER_W, plate_h)
	var a: Array[Rect2] = [plate_a, row_br]
	var b: Array[Rect2] = [plate_tr, row_br]
	var c: Array[Rect2] = [plate_tr, Rect2(right_x, plate_tr.end.y + GAP, CLUSTER_W, ROW_H)]
	var d: Array[Rect2] = [plate_tl, Rect2(SAFE_X, plate_tl.end.y + GAP, CLUSTER_W, ROW_H)]
	return {"a": a, "a4": a, "b": b, "c": c, "d": d}


## Вибір кластера: перший варіант, що не закриває жодного юніта й тримає ціль на відстані;
## інакше найменше перекриття юнітів, потім цілі, потім порядок. Повертає
## {"name", "rects": [плита, ряд], "clear": bool}.
static func choose_cluster(screen: Vector2, plate_h: float, units: Array[Rect2], targets: Array[Rect2]) -> Dictionary:
	var options: Dictionary = cluster_rects(screen, plate_h)
	var candidates: Array = []
	for name: String in CLUSTER_ORDER:
		candidates.append({"name": name, "rects": options[name],
			"grow": TARGET_GROW_TIGHT if name == "a4" else TARGET_GROW})
	return _pick(candidates, units, targets)


## Плита верб інженера: праворуч унизу, інакше внизу ліворуч від «Завершити хід».
static func choose_verb_plate(screen: Vector2, plate_size: Vector2, units: Array[Rect2], targets: Array[Rect2]) -> Dictionary:
	var y: float = screen.y - SAFE_BOTTOM - plate_size.y
	var right: Array[Rect2] = [Rect2(screen.x - SAFE_X - plate_size.x, y, plate_size.x, plate_size.y)]
	var left: Array[Rect2] = [Rect2(SAFE_X + END_TURN_W + 16.0, y, plate_size.x, plate_size.y)]
	var candidates: Array = [
		{"name": "br", "rects": right, "grow": TARGET_GROW},
		{"name": "bl", "rects": left, "grow": TARGET_GROW},
	]
	return _pick(candidates, units, targets)


## Смужка озброєння: внизу праворуч → угорі праворуч → угорі ліворуч. Права межа смужки
## фіксована — вона росте ліворуч, тож її «Скасувати» лишається на місці «Скасувати» ряду.
static func choose_strip(screen: Vector2, strip_size: Vector2, units: Array[Rect2], targets: Array[Rect2]) -> Dictionary:
	var right_x: float = screen.x - SAFE_X - strip_size.x
	var br: Array[Rect2] = [Rect2(right_x, screen.y - SAFE_BOTTOM - strip_size.y, strip_size.x, strip_size.y)]
	var tr: Array[Rect2] = [Rect2(right_x, TOP_RIGHT_Y, strip_size.x, strip_size.y)]
	var tl: Array[Rect2] = [Rect2(SAFE_X, TOP_LEFT_Y, strip_size.x, strip_size.y)]
	var candidates: Array = [
		{"name": "br", "rects": br, "grow": TARGET_GROW},
		{"name": "tr", "rects": tr, "grow": TARGET_GROW},
		{"name": "tl", "rects": tl, "grow": TARGET_GROW},
	]
	return _pick(candidates, units, targets)


static func _pick(candidates: Array, units: Array[Rect2], targets: Array[Rect2]) -> Dictionary:
	for c: Dictionary in candidates:
		if _overlap(c["rects"], units, UNIT_MARGIN) == 0.0 and _overlap(c["rects"], targets, c["grow"]) == 0.0:
			return {"name": c["name"], "rects": c["rects"], "clear": true}
	var best: Dictionary = candidates[0]
	var best_key: Array = [INF, INF, INF]
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		var key: Array = [_overlap(c["rects"], units, UNIT_MARGIN),
			_overlap(c["rects"], targets, TARGET_GROW), float(i)]
		if _less(key, best_key):
			best_key = key
			best = c
	return {"name": best["name"], "rects": best["rects"], "clear": false}


static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Сумарна площа перетину кожного з rects з кожною перешкодою, розтягнутою на grow.
static func _overlap(rects: Array, obstacles: Array[Rect2], grow: float) -> float:
	var total: float = 0.0
	for r: Rect2 in rects:
		for o in obstacles:
			var hit: Rect2 = r.intersection((o as Rect2).grow(grow))
			total += hit.size.x * hit.size.y
	return total
