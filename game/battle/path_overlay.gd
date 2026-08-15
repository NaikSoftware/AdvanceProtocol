class_name PathOverlay
extends RefCounted
## Підсвітка шляху: другий тап (клітинка призначення, до підтвердження)
## показує маршрут, яким піде вибраний юніт. Живе в тій самій системі, що й
## ZoneOverlay — BoardView.draw_contour(), тонкі риски, а не заливка (§3.13)
## — і має власний шар (LAYER_PATH), бо шлях лежить УСЕРЕДИНІ зони руху й
## малюється поверх її контурів; спільний шар змішав би дві різні речі в
## один набір сегментів і жоден clear() не міг би зняти їх окремо.
##
## КРИТИЧНО: цей файл нічого не рахує. preview["path"] приходить готовим від
## InputController._set_pending_move() — Pathing.path_to() зі свіжих
## Pathing.Zones, порахованих проти known_occupied_map() (R5), а не проти
## істинної зайнятості дошки. Малювати тут щось інше означало б або
## продублювати бойову модель у вигляді (§6 CLAUDE.md), або — гірше —
## випадково звернутись до правди про дошку й спойлерити гравцю те, чого він
## не мав бачити наперед (там, де юніт реально стане, а не заплановане).
## Показується ПЛАН, а не пророцтво.

## Нейтральний, не золотий і не червоний — шлях не мусить читатись як третя
## зона руху.
const COLOR_PATH: Color = Color("e8e4d8")

var _board_view: BoardView


func _init(board_view: BoardView) -> void:
	_board_view = board_view


## Слухач InputController.action_preview: малює шлях лише для прев'ю типу
## MOVE. Порожній словник (pending_cleared — скасовано, підтверджено, чи
## перекрито новим вибором) і прев'ю пострілу — обидва знімають попередній
## шлях, а не лишають його висіти для дії, якої вже нема чи ніколи не було.
func show_preview(preview: Dictionary) -> void:
	if preview.is_empty() or int(preview.get("type", -1)) != InputController.ActionType.MOVE:
		clear()
		return
	var path: Array[Vector2i] = preview["path"]
	_board_view.draw_contour(_edges(path), BoardView.LAYER_PATH)


func clear() -> void:
	_board_view.clear_contour(BoardView.LAYER_PATH)


## Повний контур навколо кожного тайла шляху — на відміну від ZoneOverlay
## (де риска лише на межі зони), тут кожен тайл сам по собі є точкою
## маршруту, тож усі чотири боки позначають «юніт тут пройде», а ланцюжок
## суміжних квадратів читається як траса.
static func _edges(path: Array[Vector2i]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell in path:
		for d in Board.DIRS_4:
			out.append({"cell": cell, "dir": d, "color": COLOR_PATH})
	return out
