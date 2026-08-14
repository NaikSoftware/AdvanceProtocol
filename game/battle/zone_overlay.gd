class_name ZoneOverlay
extends RefCounted
## Дві зони руху (§3.2) — головний UI гри. Малює лише контур кожної зони,
## не суцільну заливку (§3.13, R15): контур — це тайли зони, у яких є хоч
## один ортогональний сусід поза цією ж зоною. `highlight_tiles` лишається
## тим самим механізмом, що й у BoardView — сюди передається лише межа, а
## не весь набір.
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
## знімається раніше, ніж лягає новий.
func show_for(unit: Unit, zones: Pathing.Zones) -> void:
	assert(zones.origin == unit.pos, "zones пораховані для іншого юніта: origin %v != unit.pos %v" % [zones.origin, unit.pos])
	clear()
	_board_view.highlight_tiles(_contour(zones.move_only), COLOR_MOVE_ONLY, BoardView.LAYER_ZONES)
	_board_view.highlight_tiles(_contour(zones.move_and_fire), COLOR_MOVE_AND_FIRE, BoardView.LAYER_ZONES)


func clear() -> void:
	_board_view.clear_highlights(BoardView.LAYER_ZONES)


## Тайл зони лишається в контурі, якщо хоч один з його чотирьох ортогональних
## сусідів (Board.DIRS_4) не належить цій самій зоні — байдуже, чи той сусід
## поза дошкою, недосяжний узагалі, чи належить іншій зоні.
static func _contour(zone: Array[Vector2i]) -> Array[Vector2i]:
	var in_zone: Dictionary = {}
	for p in zone:
		in_zone[p] = true

	var out: Array[Vector2i] = []
	for p in zone:
		for d in Board.DIRS_4:
			if not in_zone.has(p + d):
				out.append(p)
				break
	return out
