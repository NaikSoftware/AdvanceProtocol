class_name EngineerPanel
extends Control
## П'ять верб інженера (§3.8), завжди всі, у порядку EngineerCommand.Action: одна плита-сітка 2 × 3
## клітинок по 48 dp, 269 × 148 (шоста клітинка порожня). Стовпчик із п'яти рядків по 48 зайняв би
## дві третини висоти телефона 360 dp, а нижчий рядок порушив би тап-ціль 48 (§9). Ціни немає: кожна
## верба коштує той самий fire_cost. Доступність і причина відмови — лише з EngineerCommand.action_status() (§3.13),
## панель нічого не виводить сама. Недоступна верба приглушена, але НЕ disabled: на телефоні
## немає наведення, тож тап по ній — єдиний спосіб дізнатися причину (§1.5); причина йде сигналом
## refused() у тост HUD.
##
## Озброєна верба замінює плиту смужкою [Скасувати | озброєно] (ArmedStrip), щоб тайли-цілі під
## плитою лишались тапабельними. Місце панелі на екрані задає HUD (HudDocking); тут лише
## розмір активної частини.

signal action_chosen(action: int)
signal cancel_pressed
## Ключ ERR_* відмови верби — HUD показує його тостом.
signal refused(reason: String)

const AVAILABLE_VARIATION := &"HudCellButton"
const UNAVAILABLE_VARIATION := &"HudCellButtonMuted"
const CELL_WIDTH: float = 133.0
const ROW_HEIGHT: float = 48.0
const COLUMNS: int = 2
const LABEL_KEYS: Dictionary = {
	EngineerCommand.Action.LAY_MINE: "eng_lay_mine",
	EngineerCommand.Action.CLEAR_MINE: "eng_clear_mine",
	EngineerCommand.Action.REPAIR_BRIDGE: "eng_repair_bridge",
	EngineerCommand.Action.DEMOLISH_BRIDGE: "eng_demolish_bridge",
	EngineerCommand.Action.REPAIR_UNIT: "eng_repair_unit",
}
## Та сама родина btn_*, що й на основній кнопці: один бокс чорнила й одна товщина лінії.
const ICONS: Dictionary = {
	EngineerCommand.Action.LAY_MINE: preload("res://assets/ui/icons/btn_mine_lay.svg"),
	EngineerCommand.Action.CLEAR_MINE: preload("res://assets/ui/icons/btn_mine_clear.svg"),
	EngineerCommand.Action.REPAIR_BRIDGE: preload("res://assets/ui/icons/btn_bridge_repair.svg"),
	EngineerCommand.Action.DEMOLISH_BRIDGE: preload("res://assets/ui/icons/btn_bridge_demolish.svg"),
	EngineerCommand.Action.REPAIR_UNIT: preload("res://assets/ui/icons/btn_repair_unit.svg"),
}
const _HAIR: Color = Color("3a4043")

var _unit: Unit = null
## action -> {tiles, reason} з action_status().
var _status: Dictionary = {}
var _buttons: Dictionary = {}
## Остання вибрана верба — її назва й значок у смужці.
var _chosen: int = -1
var _plate: PanelContainer
var _strip: ArmedStrip


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = PanelContainer.new()
	_plate.name = "Plate"
	# Плита верб — не число правил, тож тиха, як кнопки, а не суцільна, як плита прев'ю.
	_plate.theme_type_variation = &"HudPlateQuiet"
	add_child(_plate)
	var box := GridContainer.new()
	box.name = "Box"
	box.columns = COLUMNS
	# Проміжок 1 dp між клітинками — місце для роздільників, які малює _draw_hairs.
	box.add_theme_constant_override("h_separation", 1)
	box.add_theme_constant_override("v_separation", 1)
	box.draw.connect(_draw_hairs.bind(box))
	_plate.add_child(box)
	for action: int in LABEL_KEYS:
		var b := Button.new()
		b.name = "Verb%d" % action
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		b.theme_type_variation = AVAILABLE_VARIATION
		b.icon = ICONS[action]
		b.custom_minimum_size = Vector2(CELL_WIDTH, ROW_HEIGHT)
		b.text = LABEL_KEYS[action]
		b.pressed.connect(_on_pressed.bind(action))
		box.add_child(b)
		_buttons[action] = b
	# Шоста клітинка порожня: сітка лишається прямокутною, і роздільники не обриваються.
	var empty := Control.new()
	empty.custom_minimum_size = Vector2(CELL_WIDTH, ROW_HEIGHT)
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(empty)
	_strip = ArmedStrip.new()
	_strip.name = "Strip"
	_strip.visible = false
	_strip.cancel_pressed.connect(cancel_pressed.emit)
	add_child(_strip)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _unit != null:
		_relabel()


func show_for(state: BattleState, unit: Unit) -> void:
	_unit = unit
	_status.clear()
	for action: int in _buttons:
		_status[action] = EngineerCommand.action_status(state, unit.id, action)
		var available: bool = not (_status[action]["tiles"] as Array).is_empty()
		(_buttons[action] as Button).theme_type_variation = AVAILABLE_VARIATION if available else UNAVAILABLE_VARIATION
	_relabel()


## Озброєно (тайли-цілі на дошці) — смужка; ні — плита.
func set_armed(armed: bool) -> void:
	_plate.visible = not armed
	_strip.visible = armed
	_relabel()


func button_for(action: int) -> Button:
	return _buttons[action]


func plate() -> Control:
	return _plate


func strip() -> ArmedStrip:
	return _strip


## Розмір активної частини (плита або смужка): HUD ставить панель саме такою.
func active_size() -> Vector2:
	var part: Control = _strip if _strip.visible else _plate
	return part.get_combined_minimum_size()


## Остання вибрана верба.
func chosen() -> int:
	return _chosen


func _relabel() -> void:
	if _unit == null:
		return
	for action: int in _buttons:
		(_buttons[action] as Button).text = tr(LABEL_KEYS[action])
	if LABEL_KEYS.has(_chosen):
		_strip.configure(ICONS[_chosen], tr(LABEL_KEYS[_chosen]), tr("eng_hint_tap_tile"))
	else:
		_strip.configure(null, "", tr("eng_hint_tap_tile"))


## Роздільники 1 dp у проміжках сітки: GridContainer сам ліній не малює.
func _draw_hairs(grid: GridContainer) -> void:
	var rows: int = ceili(float(grid.get_child_count()) / COLUMNS)
	for c in range(1, COLUMNS):
		var x: float = c * (CELL_WIDTH + 1.0) - 1.0
		grid.draw_rect(Rect2(x, 0.0, 1.0, grid.size.y), _HAIR)
	for r in range(1, rows):
		var y: float = r * (ROW_HEIGHT + 1.0) - 1.0
		grid.draw_rect(Rect2(0.0, y, grid.size.x, 1.0), _HAIR)


func _on_pressed(action: int) -> void:
	if not _status.has(action):
		return
	if (_status[action]["tiles"] as Array).is_empty():
		refused.emit(_status[action]["reason"])
		return
	_chosen = action
	action_chosen.emit(action)
