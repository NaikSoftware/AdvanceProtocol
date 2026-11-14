class_name ReplayOverlay
extends Control
## Оверлей повтору ходів противників: підпис такту й «Пропустити». Корінь пропускає дотики
## (MOUSE_FILTER_IGNORE): тап повз кнопку доходить до дошки й прискорює такт.

signal skip_pressed

@onready var _turn_label: Label = %TurnLabel
@onready var _skip_button: Button = %SkipButton


func _ready() -> void:
	_skip_button.pressed.connect(skip_pressed.emit)


## total_beats — скільки видимих дій покаже повтор.
func begin(_total_beats: int) -> void:
	_turn_label.text = ""
	visible = true


## actor — 0-based, як скрізь у BattleState; на екрані 1-based.
func show_beat(_index: int, actor: int, turn: int) -> void:
	_turn_label.text = tr("replay_turn") % [turn, actor + 1]


func finish() -> void:
	visible = false
