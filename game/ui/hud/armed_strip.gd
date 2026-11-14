class_name ArmedStrip
extends PanelContainer
## Смужка озброєння (дрон або верба інженера): [Скасувати | клітинка «озброєно»], spec §2.
## «Скасувати» стоїть ЛІВОРУЧ, на місці «Скасувати» ряду дій: один тап по цілі замінює
## смужку рядом, і «Підтвердити» з'являється на правому кінці. Було б «Скасувати» праворуч —
## другий тап «передумав» влучав би в «Підтвердити» й запускав дрон чи підривав міст.
## Клітинка «озброєно» поглинає тап і нічого не робить: вона не пропускає його на дошку.

signal cancel_pressed

const MIN_WIDTH: float = 285.0
## Комірка «Скасувати» — той самий прямокутник 122 × 48, що й у «Скасувати» ряду дій.
const CANCEL_WIDTH: float = 122.0
## Висота ряду дій: смужка підміняє ряд, тож «Скасувати» не стрибає між озброєнням і очікуванням.
const HEIGHT: float = 48.0
const _ICON_CANCEL: Texture2D = preload("res://assets/ui/icons/cancel.svg")

var cancel_button: Button
var armed_cell: HBoxContainer
var title_label: Label
var hint_label: Label
var _icon: TextureRect
var _pips: DronePips


func _init() -> void:
	theme_type_variation = &"HudPlateSolid"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(MIN_WIDTH, HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	cancel_button = Button.new()
	cancel_button.theme_type_variation = &"HudPlateButton"
	cancel_button.flat = true
	cancel_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	cancel_button.icon = _ICON_CANCEL
	cancel_button.text = "hud_cancel"
	cancel_button.custom_minimum_size = Vector2(CANCEL_WIDTH, HEIGHT)
	cancel_button.add_theme_color_override("icon_normal_color", Color("8f918a"))
	cancel_button.pressed.connect(cancel_pressed.emit)
	row.add_child(cancel_button)

	var bar := ColorRect.new()
	bar.color = Color("e3dfd3")
	bar.custom_minimum_size = Vector2(3.0, 0.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	armed_cell = HBoxContainer.new()
	armed_cell.mouse_filter = Control.MOUSE_FILTER_STOP
	armed_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armed_cell.add_theme_constant_override("separation", 6)
	row.add_child(armed_cell)
	armed_cell.add_child(_spacer(0.0))
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(20.0, 20.0)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate = HudKit.BONE
	armed_cell.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armed_cell.add_child(text)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title_row)
	title_label = Label.new()
	title_label.theme_type_variation = &"HudLabel"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_label)
	_pips = DronePips.new()
	_pips.visible = false
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_pips)
	hint_label = Label.new()
	hint_label.theme_type_variation = &"HudHint"
	hint_label.add_theme_color_override("font_color", Color("8f918a"))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(hint_label)
	armed_cell.add_child(_spacer(2.0))


func _ready() -> void:
	# Та сама група «значок + слово» по центру, що й у «Скасувати» ряду дій. Збирається тут, а не в
	# _init: шрифт кнопки береться з теми, яка до входу в дерево ще не діє.
	HudKit.group_content(cancel_button, 20.0)
	# Без полів плити «Скасувати» займає той самий прямокутник, що й у ряду дій (край плити 1 dp лягає
	# під кнопку): центр групи «значок + слово» збігається піксель у піксель, тап-ціль лишається ≥ 48.
	var face := get_theme_stylebox(&"panel").duplicate() as StyleBox
	face.content_margin_left = 0.0
	face.content_margin_top = 0.0
	face.content_margin_bottom = 0.0
	add_theme_stylebox_override(&"panel", face)


## icon — значок дії; pips — (лишилось, усього) для дрона, Vector2i(-1, -1) — без ромбиків.
func configure(icon: Texture2D, title: String, hint: String, pips: Vector2i = Vector2i(-1, -1)) -> void:
	_icon.texture = icon
	title_label.text = title
	hint_label.text = hint
	_pips.visible = pips.y >= 0
	if pips.y >= 0:
		_pips.set_counts(pips.x, pips.y)


func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
