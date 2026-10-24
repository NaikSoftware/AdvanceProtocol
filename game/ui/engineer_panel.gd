class_name EngineerPanel
extends PanelContainer
## П'ять верб інженера (§3.8), завжди всі, у порядку EngineerCommand.Action.
## Ціни на кнопках немає: кожна верба коштує той самий fire_cost. Доступність і причина
## відмови — лише з EngineerCommand.action_status() (§3.13), панель нічого не виводить сама.
## Недоступна кнопка сіра, але НЕ disabled: на телефоні немає наведення, тож
## тап по ній — єдиний спосіб дізнатися причину (§1.5).
##
## Розкладка (рішення контролера): одна колонка, ширина ≤ ~40 % екрана, висота
## за вмістом (прокрутка лише коли не влазить). Коли верба озброєна, панель
## згортається в смужку «верба + Скасувати» з підказкою, що тапнути, щоб тайли-цілі
## під нею лишались тапабельними.

signal action_chosen(action: int)
signal cancel_pressed

const UNAVAILABLE_VARIATION := &"MutedButton"
const LABEL_KEYS: Dictionary = {
	EngineerCommand.Action.LAY_MINE: "eng_lay_mine",
	EngineerCommand.Action.CLEAR_MINE: "eng_clear_mine",
	EngineerCommand.Action.REPAIR_BRIDGE: "eng_repair_bridge",
	EngineerCommand.Action.DEMOLISH_BRIDGE: "eng_demolish_bridge",
	EngineerCommand.Action.REPAIR_UNIT: "eng_repair_unit",
}
const HINT_KEYS: Dictionary = {
	EngineerCommand.Action.LAY_MINE: "eng_hint_lay_mine",
	EngineerCommand.Action.CLEAR_MINE: "eng_hint_clear_mine",
	EngineerCommand.Action.REPAIR_BRIDGE: "eng_hint_repair_bridge",
	EngineerCommand.Action.DEMOLISH_BRIDGE: "eng_hint_demolish_bridge",
	EngineerCommand.Action.REPAIR_UNIT: "eng_hint_repair_unit",
}

var _unit: Unit = null
## action -> {tiles, reason} з action_status().
var _status: Dictionary = {}
## Ключ причини в рядку причини ("" — рядок схований); ключ, а не текст, щоб
## перекладатися після зміни мови.
var _reason_key: String = ""
var _buttons: Dictionary = {}
## Остання вибрана верба — її назва у згорнутій смужці.
var _chosen: int = -1
## Найбільша висота панелі (0 — без обмеження). Задає HUD: висота Middle,
## яку лишили смуги, — її не можна взяти з самого Middle, бо панель його ж і роздуває.
var max_height: float = 0.0:
	set(value):
		max_height = value
		_queue_fit()

@onready var _grid: GridContainer = %Grid
@onready var _reason_label: Label = %ReasonLabel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _box: Control = %Box
@onready var _strip: Control = %Strip
@onready var _armed_label: Label = %ArmedLabel
@onready var _hint_label: Label = %HintLabel


func _ready() -> void:
	for action: int in LABEL_KEYS:
		var b := Button.new()
		b.name = "Verb%d" % action
		b.custom_minimum_size = Vector2(48, 48)
		b.text = LABEL_KEYS[action]
		b.pressed.connect(_on_pressed.bind(action))
		_grid.add_child(b)
		_buttons[action] = b
	(%StripCancel as Button).pressed.connect(cancel_pressed.emit)
	show_reason("")
	_box.minimum_size_changed.connect(_queue_fit)
	_reason_label.visibility_changed.connect(_queue_fit)
	_reason_label.minimum_size_changed.connect(_queue_fit)
	_queue_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_relabel()
		show_reason(_reason_key)


func show_for(state: BattleState, unit: Unit) -> void:
	_unit = unit
	_status.clear()
	for action: int in _buttons:
		_status[action] = EngineerCommand.action_status(state, unit.id, action)
		var available: bool = not (_status[action]["tiles"] as Array).is_empty()
		(_buttons[action] as Button).theme_type_variation = &"" if available else UNAVAILABLE_VARIATION
	_relabel()
	show_reason("")


## Озброєно (тайли-цілі на дошці) — смужка; ні — повна панель.
func set_armed(armed: bool) -> void:
	_scroll.visible = not armed
	_strip.visible = armed
	_hint_label.visible = armed
	_relabel()
	_queue_fit()


func button_for(action: int) -> Button:
	return _buttons[action]


func _relabel() -> void:
	if _unit == null:
		return
	for action: int in _buttons:
		(_buttons[action] as Button).text = tr(LABEL_KEYS[action])
	_armed_label.text = tr(LABEL_KEYS[_chosen]) if LABEL_KEYS.has(_chosen) else ""
	_hint_label.text = tr(HINT_KEYS[_chosen]) if HINT_KEYS.has(_chosen) else ""


func _on_pressed(action: int) -> void:
	if not _status.has(action):
		return
	if (_status[action]["tiles"] as Array).is_empty():
		show_reason(_status[action]["reason"])
		return
	show_reason("")
	_chosen = action
	action_chosen.emit(action)


func show_reason(key: String) -> void:
	_reason_key = key
	_reason_label.text = tr(key) if key != "" else ""
	_reason_label.visible = key != ""


func _queue_fit() -> void:
	_fit.call_deferred()


## Висота прокрутки = висота вмісту, поки панель влазить у max_height, і лише
## понад це прокручується (той самий підхід, що FitScroll).
func _fit() -> void:
	if not is_node_ready() or not _scroll.visible:
		return
	var content: float = _box.get_combined_minimum_size().y
	if max_height <= 0.0:
		_scroll.custom_minimum_size.y = content
		return
	var others: float = get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = maxf(0.0, minf(content, max_height - others))
