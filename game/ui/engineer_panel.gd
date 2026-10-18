class_name EngineerPanel
extends PanelContainer
## Task 8: п'ять верб інженера (§3.8), завжди всі, у порядку EngineerCommand.Action,
## крім цілей — механіку цілей прибирають окремою задачею (рішення власника),
## кожна з ціною fire_cost. Доступність і причина відмови — лише з
## EngineerCommand.action_status() (§3.13), панель нічого не виводить сама.
## Недоступна кнопка сіра, але НЕ disabled: на телефоні немає наведення, тож
## тап по ній — єдиний спосіб дізнатися причину (§1.5).

signal action_chosen(action: int)

const UNAVAILABLE_VARIATION := &"MutedButton"
const LABEL_KEYS: Dictionary = {
	EngineerCommand.Action.LAY_MINE: "eng_lay_mine",
	EngineerCommand.Action.CLEAR_MINE: "eng_clear_mine",
	EngineerCommand.Action.REPAIR_BRIDGE: "eng_repair_bridge",
	EngineerCommand.Action.DEMOLISH_BRIDGE: "eng_demolish_bridge",
	EngineerCommand.Action.REPAIR_UNIT: "eng_repair_unit",
}

var _unit: Unit = null
## action -> {tiles, reason} з action_status().
var _status: Dictionary = {}
## Ключ причини в рядку причини ("" — рядок схований); ключ, а не текст, щоб
## перекладатися після зміни мови.
var _reason_key: String = ""
var _buttons: Dictionary = {}

@onready var _grid: GridContainer = %Grid
@onready var _reason_label: Label = %ReasonLabel


func _ready() -> void:
	for action: int in LABEL_KEYS:
		var b := Button.new()
		b.name = "Verb%d" % action
		b.custom_minimum_size = Vector2(48, 48)
		b.text = LABEL_KEYS[action]
		b.pressed.connect(_on_pressed.bind(action))
		_grid.add_child(b)
		_buttons[action] = b
	_show_reason("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_relabel()
		_show_reason(_reason_key)


func show_for(state: BattleState, unit: Unit) -> void:
	_unit = unit
	_status.clear()
	for action: int in _buttons:
		_status[action] = EngineerCommand.action_status(state, unit.id, action)
		var available: bool = not (_status[action]["tiles"] as Array).is_empty()
		(_buttons[action] as Button).theme_type_variation = &"" if available else UNAVAILABLE_VARIATION
	_relabel()
	_show_reason("")


func button_for(action: int) -> Button:
	return _buttons[action]


func _relabel() -> void:
	if _unit == null:
		return
	var cost: String = tr("eng_ap_cost") % _unit.fire_cost()
	for action: int in _buttons:
		(_buttons[action] as Button).text = "%s · %s" % [tr(LABEL_KEYS[action]), cost]


func _on_pressed(action: int) -> void:
	if not _status.has(action):
		return
	if (_status[action]["tiles"] as Array).is_empty():
		_show_reason(_status[action]["reason"])
		return
	_show_reason("")
	action_chosen.emit(action)


func _show_reason(key: String) -> void:
	_reason_key = key
	_reason_label.text = tr(key) if key != "" else ""
	_reason_label.visible = key != ""
