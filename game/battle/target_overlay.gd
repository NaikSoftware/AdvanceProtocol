class_name TargetOverlay
extends RefCounted
## Контур довільного набору тайлів — допустимі цілі верби інженера (Task 8); тайли
## приходять готовими з core/ (§3.13), тут лише ребра тією самою логікою, що й зони
## руху (ZoneOverlay._edges). Кільця дальності — огляд і режим дрона — геометричні
## кола (BoardView.draw_circles), радіус яких теж дає core/.

## Блакитний — щоб не сплутати з золотою й червоною зонами руху під ним.
const COLOR: Color = Color("4fb3c9")

var _board_view: BoardView


func _init(board_view: BoardView) -> void:
	_board_view = board_view


## Будь-яка зміна режиму знімає й коло дрона: обидва живуть на шарі режимів.
func show_tiles(tiles: Array[Vector2i]) -> void:
	_board_view.draw_contour(ZoneOverlay._edges(tiles, COLOR), BoardView.LAYER_TARGETS)
	_board_view.draw_circles([] as Array[Dictionary], BoardView.LAYER_TARGETS)


## Режим DRONE: досяжність — те саме коло, що й у огляді, на шарі режимів.
func show_drone_reach(center: Vector2i, radius: int) -> void:
	_board_view.draw_circles([{"center": center, "radius": radius, "color": DRONE_RING_COLOR}] as Array[Dictionary],
		BoardView.LAYER_TARGETS)


## Кільця огляду (§3.13): гармата й дрон — різні дії, тож і різні кольори; жоден не
## золото/червоне зон руху і не COLOR озброєних режимів.
const GUN_RING_COLOR: Color = Color("eef2f5")
const DRONE_RING_COLOR: Color = Color("a46be0")


## Огляд юніта (§3.13): кола гармати й дрона з Targeting.inspection на власному шарі —
## режими верби й дрона перемальовують LAYER_TARGETS, а огляд лишається. Радіус 0 —
## кола немає; {} — огляд знято.
func show_rings(inspection: Dictionary) -> void:
	var circles: Array[Dictionary] = []
	for ring: Array in [["radius", GUN_RING_COLOR], ["drone_radius", DRONE_RING_COLOR]]:
		if int(inspection.get(ring[0], 0)) > 0:
			circles.append({"center": inspection["center"], "radius": inspection[ring[0]], "color": ring[1]})
	_board_view.draw_circles(circles, BoardView.LAYER_INSPECT)


func clear() -> void:
	_board_view.clear_contour(BoardView.LAYER_TARGETS)
	_board_view.draw_circles([] as Array[Dictionary], BoardView.LAYER_TARGETS)
