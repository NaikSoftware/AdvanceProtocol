class_name DroneButton
extends Button
## Дроновий удар (§3.9) — окрема дія в слоті внизу праворуч: значок, «Дрон», роздільник і ромбики
## залишку. Числа в тексті немає: лічильник — ромбики (публічний, §3.9). Видима лише для типу з
## дронами. Без дронів кнопка лишається натискною: тап — єдиний спосіб на телефоні дізнатися
## причину відмови (та сама логіка, що й приглушені верби інженера).

const WIDTH: float = 133.0
const _PAD_RIGHT: float = 16.0
const _DIVIDER_GAP: float = 10.0

var _unit: Unit = null
var _pips: DronePips
var _divider: ColorRect


func _init() -> void:
	theme_type_variation = &"HudPlateButton"
	icon = preload("res://assets/ui/icons/drone.svg")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(WIDTH, 48.0)
	_divider = ColorRect.new()
	_divider.color = Color("3a4043")
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider)
	_pips = DronePips.new()
	add_child(_pips)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_relabel()


## null або тип без дронів — кнопку сховано.
func show_for(unit: Unit) -> void:
	_unit = unit if unit != null and int(unit.type()["drones"]) > 0 else null
	visible = _unit != null
	_relabel()
	if _unit != null:
		_pips.set_counts(_unit.drones_left, int(_unit.type()["drones"]))
		var w: float = _pips.custom_minimum_size.x
		var h: float = _pips.custom_minimum_size.y
		_pips.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_pips.offset_right = -_PAD_RIGHT
		_pips.offset_left = -_PAD_RIGHT - w
		_pips.offset_top = -h * 0.5
		_pips.offset_bottom = h * 0.5
		_divider.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_divider.offset_right = -_PAD_RIGHT - w - _DIVIDER_GAP
		_divider.offset_left = _divider.offset_right - 1.0
		_divider.offset_top = -8.0
		_divider.offset_bottom = 8.0


## Лічильник ромбиків (лишилось, усього) — для тестів, бо Control не віддає намальоване.
func pips() -> Vector2i:
	return _pips.counts()


func _relabel() -> void:
	if _unit != null:
		text = tr("hud_drone_strike")
