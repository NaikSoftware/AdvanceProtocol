class_name ArmedStrip
extends PanelContainer
## Смужка озброєння (дрон або верба інженера): [Скасувати | клітинка «озброєно»], spec §2.
## «Скасувати» стоїть ЛІВОРУЧ, на місці «Скасувати» ряду дій: один тап по цілі замінює
## смужку рядом, і «Підтвердити» з'являється на правому кінці. Було б «Скасувати» праворуч —
## другий тап «передумав» влучав би в «Підтвердити» й запускав дрон чи підривав міст.
## Клітинка «озброєно» поглинає тап і нічого не робить: вона не пропускає його на дошку.

signal cancel_pressed

## Спільна ширина з плитою прев'ю й рядом. Довший вміст розширив би смужку ліворуч і зсунув би її
## «Скасувати» з місця «Скасувати» ряду, тож кожна справжня назва й підказка мусить влазити в цю ширину:
## це перевіряє `tests/game/test_hud_components.gd`.
const WIDTH: float = HudDocking.CLUSTER_W
## Комірка «Скасувати» — той самий прямокутник 104 × 48, що й у «Скасувати» ряду дій.
const CANCEL_WIDTH: float = 104.0
## Тап-ціль ряду дій: смужка підміняє ряд, тож «Скасувати» не стрибає між озброєнням і очікуванням.
## Плита малюється на HudDocking.VISUAL_H, нижні 8 dp — лише тап-ціль.
const HEIGHT: float = HudDocking.ROW_H
const _ICON_CANCEL: Texture2D = preload("res://assets/ui/icons/btn_cancel.svg")

var cancel_button: Button
var armed_cell: HBoxContainer
var title_label: Label
var hint_label: Label
var _icon: TextureRect
var _pips: DronePips


func _init() -> void:
	theme_type_variation = &"HudPlateQuiet"
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
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
	bar.custom_minimum_size = Vector2(3.0, HudDocking.VISUAL_H)
	bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	armed_cell = HBoxContainer.new()
	armed_cell.mouse_filter = Control.MOUSE_FILTER_STOP
	armed_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Вміст — по центру малюнка 40 dp; нижні 8 dp тап-цілі ловить сама смужка, тап на дошку не проходить.
	armed_cell.custom_minimum_size = Vector2(0.0, HudDocking.VISUAL_H)
	armed_cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	armed_cell.add_theme_constant_override("separation", HudKit.ICON_GAP)
	row.add_child(armed_cell)
	armed_cell.add_child(_spacer(0.0))
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(HudKit.ICON_PX, HudKit.ICON_PX)
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
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# Порожня комірка в кінці: проміжок 6 перед нею + край плити 1 = 7 dp повітря після підпису.
	armed_cell.add_child(_spacer(0.0))


func _ready() -> void:
	# Та сама група «значок + слово» по центру, що й у «Скасувати» ряду дій. Збирається тут, а не в
	# _init: шрифт кнопки береться з теми, яка до входу в дерево ще не діє.
	HudKit.group_content(cancel_button, HudKit.ICON_PX)
	# Без полів плити «Скасувати» займає той самий прямокутник, що й у ряду дій (край плити 1 dp лягає
	# під кнопку): центр групи «значок + слово» збігається піксель у піксель, тап-ціль лишається ≥ 48.
	# Плита малюється на 40 dp, як кнопки ряду, а нижні 8 dp тап-цілі лишаються без неї.
	var face := get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	face.content_margin_left = 0.0
	face.content_margin_top = 0.0
	face.content_margin_bottom = 0.0
	face.expand_margin_bottom = -(HEIGHT - HudDocking.VISUAL_H)
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
