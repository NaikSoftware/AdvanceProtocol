class_name DronePips
extends Control
## Залишок дронів ромбиками (spec §2): лишилось — заливка кістки, витрачено — контур 1 dp dim.
## Лічильник публічний (§3.9), тож малюється для будь-якого видимого загону, а не лише свого.

const BONE: Color = Color("e3dfd3")
const DIM: Color = Color("8f918a")
## Півдіагональ квадрата 7×7, повернутого на 45°, і крок між центрами (проміжок між вершинами 2,1 dp).
const _HALF: float = 4.95
const _PITCH: float = 12.0

var _left: int = 0
var _total: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_counts(left: int, total: int) -> void:
	_left = left
	_total = total
	custom_minimum_size = Vector2(maxf(0.0, _PITCH * total - (_PITCH - 2.0 * _HALF)), 2.0 * _HALF + 2.0)
	queue_redraw()


func counts() -> Vector2i:
	return Vector2i(_left, _total)


func _draw() -> void:
	var y: float = size.y * 0.5
	for i in _total:
		var c := Vector2(_HALF + _PITCH * i, y)
		var diamond: PackedVector2Array = [c + Vector2(0, -_HALF), c + Vector2(_HALF, 0), c + Vector2(0, _HALF), c + Vector2(-_HALF, 0)]
		if i < _left:
			draw_colored_polygon(diamond, BONE)
		else:
			diamond.append(diamond[0])
			draw_polyline(diamond, DIM, 1.0)
