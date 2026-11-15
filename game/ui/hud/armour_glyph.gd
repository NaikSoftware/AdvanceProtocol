class_name ArmourGlyph
extends Control
## Корпус зверху, перед угору, з підсвіченим сектором броні. Малюється кодом
## (docs/ui/hud.md#action-previews): сектор і слово приходять із core/ у прев'ю, а ця геометрія
## лише показує, куди влучить постріл, — нічого не виводить сама. Переюзається карткою
## утримання (там нічого не світиться).

## Немає підсвіченого сектора. Не 0: FRONT теж сектор.
const NO_SECTOR: int = -1

const BONE: Color = Color("e3dfd3")
const PLATE: Color = Color("121516")
const SIZE: Vector2 = Vector2(26.0, 40.0)
## Геометрія нижче — у кресленні 30 × 46; _draw масштабує її до SIZE, тож пропорції корпуса й клинів не
## залежать від розміру глифа.
const _DRAWN: Vector2 = Vector2(30.0, 46.0)
## Контур корпуса із зрізаним носом.
const _HULL: PackedVector2Array = [
	Vector2(8, 7), Vector2(22, 7), Vector2(26, 11), Vector2(26, 44), Vector2(4, 44), Vector2(4, 11),
]
const _CENTER: Vector2 = Vector2(15.0, 25.5)
## Кути охопного прямокутника корпуса: діагоналі з центра ділять його на сектори.
const _TL: Vector2 = Vector2(4, 7)
const _TR: Vector2 = Vector2(26, 7)
const _BR: Vector2 = Vector2(26, 44)
const _BL: Vector2 = Vector2(4, 44)

var _sector: int = NO_SECTOR
var _turret: bool = false


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_sector(sector: int) -> void:
	if sector == _sector:
		return
	_sector = sector
	queue_redraw()


func set_turret(turret: bool) -> void:
	if turret == _turret:
		return
	_turret = turret
	queue_redraw()


func sector() -> int:
	return _sector


## Клин сектора, обрізаний контуром (інакше він вилазив би за зрізаний ніс).
func _wedge(points: PackedVector2Array) -> PackedVector2Array:
	var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(points, _HULL)
	return clipped[0] if not clipped.is_empty() else PackedVector2Array()


func _lit_polygons() -> Array[PackedVector2Array]:
	match _sector:
		UnitTypes.ArmourSector.FRONT:
			return [_wedge([_CENTER, _TL, _TR])]
		UnitTypes.ArmourSector.REAR:
			return [_wedge([_CENTER, _BL, _BR])]
		UnitTypes.ArmourSector.SIDE:
			return [_wedge([_CENTER, _TL, _BL]), _wedge([_CENTER, _TR, _BR])]
	return []


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, SIZE / _DRAWN)
	var dim_fill := Color(BONE, 0.10)
	var dim_line := Color(BONE, 0.26)
	draw_colored_polygon(_HULL, dim_fill)
	for p in [_TL, _TR, _BL, _BR]:
		draw_line(_CENTER, _clip_to_hull(p), dim_line, 1.5, true)
	for x in [8.5, 21.5]:
		draw_line(Vector2(x, 12), Vector2(x, 43), dim_line, 1.0, true)
	for poly in _lit_polygons():
		if poly.size() >= 3:
			draw_colored_polygon(poly, BONE)
	# У світлому секторі діагоналі й гусениці перемальовані темним, щоб клин читався одним тілом.
	if _sector != NO_SECTOR:
		for p in [_TL, _TR, _BL, _BR]:
			if _diagonal_in_lit(p):
				draw_line(_CENTER, _clip_to_hull(p), PLATE, 1.5, true)
		for x in [8.5, 21.5]:
			if _track_in_lit(x):
				draw_line(Vector2(x, 12), Vector2(x, 43), PLATE, 1.0, true)
	var outline: PackedVector2Array = _HULL.duplicate()
	outline.append(_HULL[0])
	draw_polyline(outline, BONE, 1.5, true)
	if _turret:
		draw_line(Vector2(15, 21), Vector2(15, 1), PLATE, 4.0, true)
		draw_line(Vector2(15, 21), Vector2(15, 1), BONE, 2.0, true)
		draw_circle(Vector2(15, 27), 5.5, PLATE)
		draw_arc(Vector2(15, 27), 5.5, 0.0, TAU, 24, BONE, 1.5, true)


## Діагональ закінчується на контурі, а не в куті охопного прямокутника.
func _clip_to_hull(corner: Vector2) -> Vector2:
	var best: Vector2 = corner
	var best_t: float = 1.0
	for i in _HULL.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(_CENTER, corner, _HULL[i], _HULL[(i + 1) % _HULL.size()])
		if hit != null:
			var t: float = _CENTER.distance_to(hit as Vector2) / _CENTER.distance_to(corner)
			if t <= best_t:
				best_t = t
				best = hit as Vector2
	return best


## Діагональ — межа двох секторів: темна, якщо світиться один із них.
func _diagonal_in_lit(corner: Vector2) -> bool:
	var top: bool = corner.y == _TL.y
	match _sector:
		UnitTypes.ArmourSector.FRONT:
			return top
		UnitTypes.ArmourSector.REAR:
			return not top
	return _sector == UnitTypes.ArmourSector.SIDE


## Гусеничні лінії x = 8.5 і 21.5 лежать у боковому клині; у лобовому/кормовому — лише верх/низ.
func _track_in_lit(_x: float) -> bool:
	return _sector == UnitTypes.ArmourSector.SIDE
