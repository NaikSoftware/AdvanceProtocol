class_name ArmedStrip
extends HBoxContainer
## Смужка озброєння (дрон або верба інженера) має форму ряду дій: дві окремі плити
## [Скасувати 104][12][клітинка «озброєно» 136] (docs/ui/hud.md#cancel-confirm-and-end-turn).
## Один тап по цілі замінює смужку рядом, тож обидві плити стоять на пікселях плит ряду: «Скасувати»
## не стрибає, а на місці майбутнього «Підтвердити» — інертна клітинка. Було б «Скасувати» праворуч —
## другий тап «передумав» влучав би в «Підтвердити» й запускав дрон чи підривав міст.
## Уся смужка 252 × 48 разом із проміжком поглинає тап: між плитами він не падає на дошку.

signal cancel_pressed

## Спільна ширина з плитою прев'ю й рядом. Довший вміст розширив би смужку ліворуч і зсунув би її
## «Скасувати» з місця «Скасувати» ряду, тож кожна справжня назва й підказка мусить влазити в клітинку:
## це перевіряє `tests/game/test_hud_components.gd`.
const WIDTH: float = HudDocking.CLUSTER_W
## Комірка «Скасувати» — той самий прямокутник 104 × 48, що й у «Скасувати» ряду дій.
const CANCEL_WIDTH: float = 104.0
## Тап-ціль ряду дій: смужка підміняє ряд, тож «Скасувати» не стрибає між озброєнням і очікуванням.
## Плити малюються на HudDocking.VISUAL_H, нижні 8 dp — лише тап-ціль.
const HEIGHT: float = HudDocking.ROW_H
## Підказка світліша за загальний HudKit.DIM: на тихій заливці 65 % над полем DIM дає ~4,1 : 1, а дрібному
## тексту треба ≥ 4,5 : 1. DIM лишається для приглушених верб і підписів на щільніших плитах.
const HINT: Color = Color("a4a69e")
## Два рядки щільніше за висоту шрифту на 2 dp: інакше під виносними підказки лишалось ~3 dp, а не 6.
## Щільніше не можна — нижні виносні назви («Підірвати», "Repair") лягли б на літери підказки.
const _LINE_TUCK: int = -2
## Над великими літерами назви шрифт тримає запас під надрядкові знаки (Й, Ї), тож чорнило двох рядків
## сидить нижче центру; порожній рядок під підказкою піднімає блок на 1 dp, і крапка над «і» теж
## лишається нижче краю плити.
const _LIFT: float = 4.0
const _ICON_CANCEL: Texture2D = preload("res://assets/ui/icons/btn_cancel.svg")

var cancel_button: Button
var armed_cell: PanelContainer
var title_label: Label
var hint_label: Label
var _icon: TextureRect
var _pips: DronePips


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	add_theme_constant_override("separation", int(HudDocking.ROW_GAP))
	# Контейнер типово пропускає тап крізь проміжок між плитами — тут він мусить зупинитися.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Та сама кнопка, що «Скасувати» ряду (hud.tscn): варіація, колір значка, NEAREST для краю 1 dp.
	cancel_button = Button.new()
	cancel_button.theme_type_variation = &"HudPlateButton"
	cancel_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cancel_button.icon = _ICON_CANCEL
	cancel_button.text = "hud_cancel"
	cancel_button.custom_minimum_size = Vector2(CANCEL_WIDTH, HEIGHT)
	cancel_button.add_theme_color_override("icon_normal_color", HudKit.DIM)
	cancel_button.pressed.connect(cancel_pressed.emit)
	add_child(cancel_button)

	# Тиха плита, а не кістяна рамка основної кнопки: тут ще нічого підтверджувати, клітинка лише
	# називає озброєну дію. Рамку вона отримує, коли ряд заміняє смужку після тапу по цілі.
	armed_cell = PanelContainer.new()
	armed_cell.theme_type_variation = &"HudPlateQuiet"
	armed_cell.mouse_filter = Control.MOUSE_FILTER_STOP
	armed_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(armed_cell)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", HudKit.ICON_GAP)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armed_cell.add_child(content)
	# Порожні комірки з обох кінців: проміжок 6 + край плити 1 = 7 dp повітря до значка й після підпису.
	content.add_child(_spacer(0.0))
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(HudKit.ICON_PX, HudKit.ICON_PX)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.modulate = HudKit.BONE
	content.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", _LINE_TUCK)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text)
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
	hint_label.add_theme_color_override("font_color", HINT)
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(hint_label)
	text.add_child(_spacer(0.0, _LIFT))
	content.add_child(_spacer(0.0))


func _ready() -> void:
	# Та сама група «значок + слово» по центру, що й у «Скасувати» ряду дій. Збирається тут, а не в
	# _init: шрифт кнопки береться з теми, яка до входу в дерево ще не діє.
	HudKit.group_content(cancel_button, HudKit.ICON_PX)
	# Плита клітинки малюється на 40 dp, як кнопки ряду, а нижні 8 dp тап-цілі лишаються без неї;
	# вміст стоїть по центру малюнка, а не всієї тап-цілі.
	var face := armed_cell.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	face.content_margin_top = 0.0
	face.content_margin_bottom = HEIGHT - HudDocking.VISUAL_H
	face.expand_margin_bottom = -(HEIGHT - HudDocking.VISUAL_H)
	armed_cell.add_theme_stylebox_override(&"panel", face)


## icon — значок дії; pips — (лишилось, усього) для дрона, Vector2i(-1, -1) — без ромбиків.
func configure(icon: Texture2D, title: String, hint: String, pips: Vector2i = Vector2i(-1, -1)) -> void:
	_icon.texture = icon
	title_label.text = title
	hint_label.text = hint
	_pips.visible = pips.y >= 0
	if pips.y >= 0:
		_pips.set_counts(pips.x, pips.y)


func _spacer(width: float, height: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
