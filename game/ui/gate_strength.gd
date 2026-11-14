class_name GateStrength
extends Control
## Сила команд на гейті передачі ходу: без цифр і підписів, лише довжини. Вигляд нічого не
## рахує — ядро дає HP цілими, тут вони лише переходять у ширини. Малюється один раз і
## стоїть: гейт статичний, жодної роботи по кадрах.
##
## Двоє гравців: дві лінії від нікнейм-плити назовні (ліва — гравець 1, права — гравець 2).
## Троє: одна смуга по нижньому краю інфо-плити, сегмент на живого гравця.

enum Mode { NONE, TWO, THREE }

const LINE_H := 2.0
const SQUARE := 8.0
const BAR_H := 4.0
const BAR_GAP := 2.0
const TICK_W := 1.0
const DOT_ON := 2.0
const DOT_OFF := 3.0
const DOT_COLOR := Color("3a4043")
const TICK_COLOR := Color(0.8902, 0.8745, 0.8275)
const GAP_COLOR := Color(0.050980393, 0.0627451, 0.07450981, 1)

var mode: Mode = Mode.NONE
## Для перевірки в тестах: що саме намальовано суцільним (у координатах цього вузла).
var solid_rects: Array[Rect2] = []
var square_rects: Array[Rect2] = []
var segment_rects: Array[Rect2] = []
var segment_players: Array[int] = []

var _colors: Array[Color] = []
var _row: Rect2 = Rect2()
var _name_rect: Rect2 = Rect2()
var _plate: Rect2 = Rect2()
var _shares: Array[float] = []
var _weights: Array[int] = []
var _players: Array[int] = []


func clear() -> void:
	mode = Mode.NONE
	solid_rects.clear()
	square_rects.clear()
	segment_rects.clear()
	segment_players.clear()
	visible = false
	queue_redraw()


## shares[p] — частка, що лишилась від стартової сили гравця p (0..1), з ядра.
func set_two(shares: Array[float], colors: Array[Color]) -> void:
	mode = Mode.TWO
	_shares = shares
	_colors = colors
	visible = true
	_relayout()


## weights[i] — поточні HP живого гравця players[i]; вибулих у списку немає.
func set_three(players: Array[int], weights: Array[int], colors: Array[Color]) -> void:
	mode = Mode.THREE
	_players = players
	_weights = weights
	_colors = colors
	visible = true
	_relayout()


## Прямокутники елементів гейта в координатах цього вузла: ряд нікнейма (звідки лінії тягнуться
## назовні), сама нікнейм-плита й інфо-плита.
func set_geometry(row: Rect2, name_rect: Rect2, plate: Rect2) -> void:
	_row = row
	_name_rect = name_rect
	_plate = plate
	_relayout()


func _relayout() -> void:
	solid_rects.clear()
	square_rects.clear()
	segment_rects.clear()
	segment_players.clear()
	if mode == Mode.TWO:
		var y: float = _row.get_center().y - LINE_H * 0.5
		var left_len: float = _name_rect.position.x - _row.position.x
		var right_len: float = _row.end.x - _name_rect.end.x
		solid_rects.append(Rect2(_name_rect.position.x - left_len * _shares[0], y, left_len * _shares[0], LINE_H))
		solid_rects.append(Rect2(_name_rect.end.x, y, right_len * _shares[1], LINE_H))
		square_rects.append(Rect2(_row.position.x, _row.get_center().y - SQUARE * 0.5, SQUARE, SQUARE))
		square_rects.append(Rect2(_row.end.x - SQUARE, _row.get_center().y - SQUARE * 0.5, SQUARE, SQUARE))
	elif mode == Mode.THREE:
		var total: int = 0
		for w in _weights:
			total += w
		var usable: float = _plate.size.x - BAR_GAP * maxf(_weights.size() - 1, 0)
		var x: float = _plate.position.x
		var y: float = _plate.end.y - BAR_H
		for i in _weights.size():
			var width: float = usable * float(_weights[i]) / float(total)
			segment_rects.append(Rect2(x, y, width, BAR_H))
			segment_players.append(_players[i])
			x += width + BAR_GAP
	queue_redraw()


func _draw() -> void:
	if mode == Mode.TWO:
		for i in 2:
			var color: Color = _colors[i]
			var sign_out: float = -1.0 if i == 0 else 1.0
			var solid: Rect2 = solid_rects[i]
			draw_rect(solid, color)
			# Пунктир від кінця суцільного до зовнішнього краю ряду.
			var outer_x: float = _row.position.x if i == 0 else _row.end.x
			var start_x: float = solid.position.x if i == 0 else solid.end.x
			var dist: float = absf(outer_x - start_x)
			var d: float = 0.0
			while d < dist:
				var w: float = minf(DOT_ON, dist - d)
				var px: float = start_x + sign_out * d
				draw_rect(Rect2(px - w if i == 0 else px, solid.position.y, w, LINE_H), DOT_COLOR)
				d += DOT_ON + DOT_OFF
			draw_rect(square_rects[i], color)
	elif mode == Mode.THREE:
		if segment_rects.is_empty():
			return
		draw_rect(Rect2(_plate.position.x, _plate.end.y - BAR_H, _plate.size.x, BAR_H), GAP_COLOR)
		for i in segment_rects.size():
			draw_rect(segment_rects[i], _colors[segment_players[i]])
		for t in [1, 2]:
			draw_rect(Rect2(_plate.position.x + _plate.size.x * t / 3.0 - TICK_W * 0.5, _plate.end.y - BAR_H, TICK_W, BAR_H), TICK_COLOR)
