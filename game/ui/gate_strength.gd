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
const TICK_SNAP := 2.0
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
	# Усе в цілих пікселях пристрою: stretch і content_scale_factor стоять у трансформі вікна, а не вузла,
	# тож шкала береться з нього, інакше 1 dp на дробовому масштабі дає то 1, то 2 px.
	var to_screen: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var scale: float = maxf(to_screen.get_scale().x, 0.001)
	if mode == Mode.TWO:
		var on: float = maxf(1.0, roundf(DOT_ON * scale))
		var off: float = maxf(1.0, roundf(DOT_OFF * scale))
		for i in 2:
			var color: Color = _colors[i]
			var left: bool = i == 0
			var solid: Rect2 = solid_rects[i]
			var y: float = solid.position.y
			# Суцільна й пунктир ідуть від нікнейм-плити назовні; a — край суцільного, b — внутрішній край квадрата.
			var near: float = roundf(_dev_x(to_screen, solid.end.x if not left else solid.position.x))
			var far: float = roundf(_dev_x(to_screen, _name_rect.position.x if left else _name_rect.end.x))
			_dev_rect(to_screen, minf(near, far), maxf(near, far), y, LINE_H, color)
			var sgn: float = -1.0 if left else 1.0
			var inner: float = roundf(_dev_x(to_screen, _row.position.x + SQUARE if left else _row.end.x - SQUARE))
			var d: float = near + sgn * off
			# Крапка цілком у межах і з проміжком до квадрата: на обох кінцях дорожки лишається по одному проміжку.
			while (d + sgn * on - inner) * sgn <= -off:
				_dev_rect(to_screen, minf(d, d + sgn * on), maxf(d, d + sgn * on), y, LINE_H, DOT_COLOR)
				d += sgn * (on + off)
			draw_rect(square_rects[i], color)
	elif mode == Mode.THREE:
		if segment_rects.is_empty():
			return
		draw_rect(Rect2(_plate.position.x, _plate.end.y - BAR_H, _plate.size.x, BAR_H), GAP_COLOR)
		for i in segment_rects.size():
			draw_rect(segment_rects[i], _colors[segment_players[i]])
		var tw: float = maxf(1.0, roundf(TICK_W * scale))
		for t in [1, 2]:
			var cx: float = _dev_x(to_screen, snap_tick(_plate.position.x + _plate.size.x * t / 3.0, segment_rects))
			var x0: float = roundf(cx - tw * 0.5)
			_dev_rect(to_screen, x0, x0 + tw, _plate.end.y - BAR_H, BAR_H, TICK_COLOR)


static func _dev_x(to_screen: Transform2D, x: float) -> float:
	return (to_screen * Vector2(x, 0.0)).x


## Відрізок [x0, x1] у пікселях пристрою → прямокутник у координатах вузла.
func _dev_rect(to_screen: Transform2D, x0: float, x1: float, y: float, h: float, color: Color) -> void:
	var inv: Transform2D = to_screen.affine_inverse()
	var l0: float = (inv * Vector2(x0, 0.0)).x
	var l1: float = (inv * Vector2(x1, 0.0)).x
	draw_rect(Rect2(l0, y, l1 - l0, h), color)


## Риска, що випала на проміжок між сегментами або за 2 dp від нього, стає рівно в проміжок: вона
## лишається видимою на обох третинах і не зсувається до зеленого чи червоного краю.
static func snap_tick(x: float, segments: Array[Rect2]) -> float:
	for i in segments.size() - 1:
		var gap_mid: float = segments[i].end.x + BAR_GAP * 0.5
		if absf(x - gap_mid) <= TICK_SNAP:
			return gap_mid
	return x
