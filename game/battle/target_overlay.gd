class_name TargetOverlay
extends RefCounted
## Контур довільного набору тайлів — допустимі цілі верби інженера (Task 8), далі
## й дрона (Task 10). Тайли приходять готовими з core/ (§3.13); тут лише ребра,
## тією самою логікою, що й зони руху (ZoneOverlay._edges), на власному шарі.

## Блакитний — щоб не сплутати з золотою й червоною зонами руху під ним.
const COLOR: Color = Color("4fb3c9")

var _board_view: BoardView


func _init(board_view: BoardView) -> void:
	_board_view = board_view


func show_tiles(tiles: Array[Vector2i]) -> void:
	_board_view.draw_contour(ZoneOverlay._edges(tiles, COLOR), BoardView.LAYER_TARGETS)


## Кільця огляду (§3.13): гармата й дрон — різні дії, тож і різні кольори; жоден не
## золото/червоне зон руху і не COLOR озброєних режимів.
const GUN_RING_COLOR: Color = Color("eef2f5")
const DRONE_RING_COLOR: Color = Color("a46be0")


## Огляд юніта (§3.13): кільце дальності й кільце дрона на власному шарі — режими
## верби й дрона перемальовують LAYER_TARGETS, а кільце вибраного юніта лишається.
func show_rings(ring: Array[Vector2i], drone_ring: Array[Vector2i]) -> void:
	_board_view.draw_contour(ZoneOverlay._edges(ring, GUN_RING_COLOR)
		+ ZoneOverlay._edges(drone_ring, DRONE_RING_COLOR), BoardView.LAYER_INSPECT)


func clear() -> void:
	_board_view.clear_contour(BoardView.LAYER_TARGETS)
