class_name ZoneOverlay
extends RefCounted
## Дві зони руху (§3.2) — головний UI гри. Малює РЕБРА зони
## (BoardView.draw_contour), не заливку тайлів (§3.13, PO-скарга: «контурно,
## не заливкою») — старіша версія цього файла вже звужувала підсвітку до
## тайлів межі, але кожен такий тайл малювався суцільним квадратом
## (BoardView.highlight_tiles), а це й досі заливка: місцевість і бойові сліди під
## самими межовими тайлами лишались сховані. Тепер контур — це тонкі риски
## вздовж ребер, що дивляться поза зону; решта тайла, навіть межового,
## лишається видимою повністю.
##
## Отримує вже пораховані Pathing.Zones ззовні й нічого сам не рахує: вибір
## occupancy (known vs. true, R5) належить виклику (Task 2.7, Task 2.10),
## не цьому файлу. Тут немає ні BattleState, ні occupancy-мапи.

## Золотий — move_and_fire: юніт долетить і ще матиме AP на постріл.
const COLOR_MOVE_AND_FIRE: Color = Color("e8c547")
## Червоний — move_only: тайл досяжний, але після руху стріляти вже нічим.
const COLOR_MOVE_ONLY: Color = Color("c94f3f")

var _board_view: BoardView


func _init(board_view: BoardView) -> void:
	_board_view = board_view


## Перемальовує обидві зони від нуля — «перемальовується після кожної дії»
## (§3.2) означає заміну, а не накопичення, тож старий контур завжди
## знімається раніше, ніж лягає новий (BoardView.draw_contour теж заміняє,
## але clear() тут явний — той самий стиль, що й раніше).
func show_for(unit: Unit, zones: Pathing.Zones) -> void:
	assert(zones.origin == unit.pos, "zones пораховані для іншого юніта: origin %v != unit.pos %v" % [zones.origin, unit.pos])
	clear()
	var segments: Array[Dictionary] = []
	segments.append_array(_edges(zones.move_only, COLOR_MOVE_ONLY))
	segments.append_array(_edges(zones.move_and_fire, COLOR_MOVE_AND_FIRE))
	_board_view.draw_contour(segments, BoardView.LAYER_ZONES)


func clear() -> void:
	_board_view.clear_contour(BoardView.LAYER_ZONES)


## Одна риска на кожне ребро тайла зони, що дивиться на клітинку поза цією ж
## зоною — байдуже, чи той сусід поза дошкою, недосяжний узагалі, чи належить
## іншій зоні (Board.DIRS_4, лише ортогональні сусіди — §3.1). Внутрішній
## тайл суцільного блоку не дає жодної риски: усі чотири сусіди в тій самій
## зоні.
static func _edges(zone: Array[Vector2i], color: Color) -> Array[Dictionary]:
	var in_zone: Dictionary = {}
	for p in zone:
		in_zone[p] = true

	var out: Array[Dictionary] = []
	for p in zone:
		for d in Board.DIRS_4:
			if not in_zone.has(p + d):
				out.append({"cell": p, "dir": d, "color": color})
	return out
